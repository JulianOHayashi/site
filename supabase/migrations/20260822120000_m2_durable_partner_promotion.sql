-- ============================================================================
-- M2 / R2 — Promoção durável: candidatura APROVADA -> empresa + owner
--
-- Constrói SOBRE o domínio canônico do M1. Regras absolutas:
--   * NUNCA cria, recria ou altera public.partner_applications;
--   * só promove candidatura em status 'approved' com AMBAS as análises
--     ('company_review_status' e 'authority_review_status') aprovadas;
--   * o owner é o representante CORRENTE com autoridade aprovada, e a conta
--     é o account_user_id canônico (conta provisória já vinculada no M1);
--   * NÃO cria aceite jurídico algum (aceite exige ação explícita do usuário
--     e pertence ao M1);
--   * NÃO revalida CPF/CNPJ com regex: os dados vêm do domínio canônico, que
--     já os validou por dígito verificador;
--   * idempotente, concorrência-segura (trava de linha), auditada pelos
--     helpers canônicos m1_exigir_admin/m1_auditar.
--
-- Identidades de ponte Site<->App são UUID dedicados — nunca CNPJ/CPF.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Empresa parceira durável
-- ----------------------------------------------------------------------------
CREATE TABLE public.site_partner_companies (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_application_id     uuid NOT NULL UNIQUE
                              REFERENCES public.partner_applications(id),
  cnpj                      text        NOT NULL,
  legal_name                text        NOT NULL,
  trade_name                text,
  contact_email             text        NOT NULL,
  contact_phone             text,
  city                      text        NOT NULL,
  uf                        text        NOT NULL,
  status                    text        NOT NULL DEFAULT 'active',
  partner_network_bridge_id uuid        NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  promoted_at               timestamptz NOT NULL DEFAULT now(),
  promoted_by               uuid,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),

  -- Dígito verificador, jamais regex de formato (não regride o M1).
  CONSTRAINT spc_cnpj_valido CHECK (public.m1_cnpj_valido(cnpj)),
  CONSTRAINT spc_legal_name_nonempty
    CHECK (length(btrim(legal_name)) BETWEEN 2 AND 200),
  CONSTRAINT spc_uf_valida CHECK (public.commercial_is_valid_uf(uf)),
  CONSTRAINT spc_status_allowed
    CHECK (status = ANY (ARRAY['active','suspended','archived'])),
  CONSTRAINT spc_timestamps CHECK (updated_at >= created_at)
);

-- Um CNPJ vivo por vez no domínio durável.
CREATE UNIQUE INDEX spc_cnpj_vivo_idx
  ON public.site_partner_companies (cnpj)
  WHERE status <> 'archived';

CREATE TRIGGER trg_spc_touch
  BEFORE UPDATE ON public.site_partner_companies
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 2. Vínculo durável de pessoa (owner agora; managers no R4)
-- ----------------------------------------------------------------------------
CREATE TABLE public.site_company_members (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid        NOT NULL REFERENCES public.site_partner_companies(id),
  auth_user_id         uuid        NOT NULL REFERENCES auth.users(id),
  role                 text        NOT NULL,
  status               text        NOT NULL DEFAULT 'active',
  full_name            text        NOT NULL,
  cpf                  text,
  email                text,
  phone                text,
  source               text        NOT NULL,
  source_representative_id uuid    REFERENCES public.partner_application_representatives(id),
  validator_bridge_id  uuid        NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  activated_at         timestamptz NOT NULL DEFAULT now(),
  revoked_at           timestamptz,
  revocation_reason    text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT scm_role_allowed
    CHECK (role = ANY (ARRAY['partner_owner','partner_manager'])),
  CONSTRAINT scm_status_allowed
    CHECK (status = ANY (ARRAY['active','suspended','revoked','archived'])),
  CONSTRAINT scm_source_allowed
    CHECK (source = ANY (ARRAY['application_promotion','manager_invite'])),
  CONSTRAINT scm_cpf_valido CHECK (cpf IS NULL OR public.m1_cpf_valido(cpf)),
  CONSTRAINT scm_full_name_nonempty
    CHECK (length(btrim(full_name)) BETWEEN 3 AND 200),
  CONSTRAINT scm_revogacao_coerente
    CHECK ((revoked_at IS NULL AND revocation_reason IS NULL)
           OR (revoked_at IS NOT NULL AND status = 'revoked'
               AND length(btrim(coalesce(revocation_reason,''))) >= 3)),
  CONSTRAINT scm_timestamps CHECK (updated_at >= created_at)
);

-- Um vínculo vivo por (empresa, conta) e um único owner vivo por empresa.
CREATE UNIQUE INDEX scm_vinculo_vivo_idx
  ON public.site_company_members (company_id, auth_user_id)
  WHERE status IN ('active','suspended');
CREATE UNIQUE INDEX scm_um_owner_vivo_idx
  ON public.site_company_members (company_id)
  WHERE role = 'partner_owner' AND status IN ('active','suspended');
-- Uma conta Auth é owner de no máximo uma empresa viva.
CREATE UNIQUE INDEX scm_owner_por_conta_idx
  ON public.site_company_members (auth_user_id)
  WHERE role = 'partner_owner' AND status IN ('active','suspended');

CREATE TRIGGER trg_scm_touch
  BEFORE UPDATE ON public.site_company_members
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 3. Helpers de autorização (SECURITY DEFINER para não recursar em RLS)
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.m2_is_company_owner(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.site_company_members m
     WHERE m.company_id = p_company_id
       AND m.auth_user_id = auth.uid()
       AND m.role = 'partner_owner'
       AND m.status = 'active');
$$;

CREATE FUNCTION public.m2_is_company_member(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.site_company_members m
     WHERE m.company_id = p_company_id
       AND m.auth_user_id = auth.uid()
       AND m.status = 'active');
$$;

REVOKE EXECUTE ON FUNCTION public.m2_is_company_owner(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_is_company_member(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_is_company_owner(uuid) FROM service_role;
REVOKE EXECUTE ON FUNCTION public.m2_is_company_member(uuid) FROM service_role;
GRANT  EXECUTE ON FUNCTION public.m2_is_company_owner(uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.m2_is_company_member(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. RLS — leitura mínima; escrita só por RPC administrativa
-- ----------------------------------------------------------------------------
ALTER TABLE public.site_partner_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_company_members  ENABLE ROW LEVEL SECURITY;

CREATE POLICY spc_membro_select ON public.site_partner_companies
  FOR SELECT TO authenticated
  USING (public.m2_is_company_member(id) OR public.is_site_admin());

CREATE POLICY scm_proprio_ou_owner_select ON public.site_company_members
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid()
         OR public.m2_is_company_owner(company_id)
         OR public.is_site_admin());

REVOKE ALL ON TABLE public.site_partner_companies
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.site_company_members
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.site_partner_companies TO authenticated;
GRANT SELECT ON public.site_company_members  TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. RPC administrativa de promoção
--
-- Contrato de retorno segue o padrão do M1: jsonb {ok, reason|...}.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.admin_promote_partner_application(
  p_application_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app     public.partner_applications%ROWTYPE;
  v_rep     public.partner_application_representatives%ROWTYPE;
  v_company uuid;
  v_member  uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- Trava de linha: promoções concorrentes serializam aqui.
  SELECT * INTO v_app
    FROM public.partner_applications
   WHERE id = p_application_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- IDEMPOTÊNCIA: já promovida devolve o mesmo resultado, sem duplicar.
  SELECT id INTO v_company
    FROM public.site_partner_companies
   WHERE source_application_id = p_application_id;
  IF FOUND THEN
    SELECT id INTO v_member
      FROM public.site_company_members
     WHERE company_id = v_company AND role = 'partner_owner'
       AND status IN ('active','suspended')
     LIMIT 1;
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'already', true,
      'company_id', v_company, 'owner_member_id', v_member);
  END IF;

  -- Estado canônico: aprovada E as duas análises aprovadas.
  IF v_app.status <> 'approved' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_approved');
  END IF;
  IF v_app.company_review_status <> 'approved'
     OR v_app.authority_review_status <> 'approved' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reviews_incomplete');
  END IF;

  -- A conta provisória canônica torna-se a conta do owner.
  IF v_app.account_user_id IS NULL OR v_app.account_kind <> 'provisional' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'account_not_linked');
  END IF;

  -- Representante CORRENTE com autoridade aprovada.
  SELECT * INTO v_rep
    FROM public.partner_application_representatives
   WHERE application_id = p_application_id
     AND is_current
     AND authority_status = 'approved'
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'representative_not_approved');
  END IF;

  INSERT INTO public.site_partner_companies
    (source_application_id, cnpj, legal_name, trade_name,
     contact_email, contact_phone, city, uf, promoted_by)
  VALUES
    (v_app.id, v_app.cnpj, v_app.legal_name, v_app.trade_name,
     v_app.contact_email, v_app.contact_phone, v_app.city, v_app.uf, auth.uid())
  RETURNING id INTO v_company;

  INSERT INTO public.site_company_members
    (company_id, auth_user_id, role, status, full_name, cpf, email, phone,
     source, source_representative_id)
  VALUES
    (v_company, v_app.account_user_id, 'partner_owner', 'active',
     v_rep.full_name, v_rep.cpf, v_rep.email, v_rep.phone,
     'application_promotion', v_rep.id)
  RETURNING id INTO v_member;

  PERFORM public.m1_auditar(
    'partner_application.promoted', p_application_id, 'admin',
    pg_catalog.jsonb_build_object('company_id', v_company,
                                  'owner_member_id', v_member),
    pg_catalog.jsonb_build_object('status', v_app.status),
    pg_catalog.jsonb_build_object('source', 'admin_promote_partner_application'));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false,
    'company_id', v_company, 'owner_member_id', v_member);

EXCEPTION
  -- Corrida vencida por outra transação: devolve o estado existente.
  WHEN unique_violation THEN
    SELECT id INTO v_company
      FROM public.site_partner_companies
     WHERE source_application_id = p_application_id;
    IF v_company IS NOT NULL THEN
      SELECT id INTO v_member
        FROM public.site_company_members
       WHERE company_id = v_company AND role = 'partner_owner'
       LIMIT 1;
      RETURN pg_catalog.jsonb_build_object(
        'ok', true, 'already', true,
        'company_id', v_company, 'owner_member_id', v_member);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'conflict');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_promote_partner_application(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_promote_partner_application(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_promote_partner_application(uuid) FROM service_role;
GRANT  EXECUTE ON FUNCTION public.admin_promote_partner_application(uuid) TO authenticated;

COMMENT ON FUNCTION public.admin_promote_partner_application(uuid) IS
  'M2: promove candidatura canônica aprovada a empresa + owner duráveis. '
  'Idempotente e concorrência-segura. Não cria aceite jurídico e não altera '
  'public.partner_applications.';
