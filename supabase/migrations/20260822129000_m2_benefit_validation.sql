-- ============================================================================
-- M2 / R12 — Autorização de validador e preparação da validação (LADO SITE)
--
-- O App é autoridade sobre entitlement, token e uso. O Site apenas PROVA quem
-- valida, em que unidade e por qual rede, registra a tentativa de forma
-- auditável e entrega o pacote mínimo ao gateway.
--
-- LIMITE EXPLÍCITO: sem o repositório do App, a chamada ao gateway e o
-- desfecho real do benefício permanecem BLOCKED_APP_REPOSITORY. Nada aqui
-- afirma que o benefício foi validado — apenas que o Site autorizou o
-- validador e encaminhou.
--
-- Negativas locais RETORNAM allowed=false em vez de levantar exceção: uma
-- exceção desfaria a própria linha de auditoria da tentativa negada.
-- ============================================================================

CREATE TABLE public.benefit_validation_attempts (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES public.site_partner_companies(id),
  unit_id        uuid REFERENCES public.site_partner_units(id),
  validator_member_id uuid NOT NULL REFERENCES public.site_company_members(id),
  validator_role text NOT NULL,
  -- Identidades de ponte enviadas ao App (nunca CNPJ/CPF).
  partner_network_bridge_id uuid NOT NULL,
  partner_branch_bridge_id  uuid,
  validator_bridge_id       uuid NOT NULL,
  -- Hash do token lido no Portal: o cru NUNCA é persistido.
  token_hash     bytea       NOT NULL,
  result         text        NOT NULL,
  rejection_code text,
  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT bva_role_allowed
    CHECK (validator_role = ANY (ARRAY['partner_owner','partner_manager'])),
  CONSTRAINT bva_result_allowed
    CHECK (result = ANY (ARRAY['forwarded_to_app','denied_local'])),
  CONSTRAINT bva_hash_tamanho CHECK (octet_length(token_hash) = 32),
  CONSTRAINT bva_negativa_coerente
    CHECK ((result = 'forwarded_to_app' AND rejection_code IS NULL
            AND unit_id IS NOT NULL AND partner_branch_bridge_id IS NOT NULL)
           OR (result = 'denied_local' AND rejection_code IS NOT NULL))
);

CREATE INDEX bva_company_idx ON public.benefit_validation_attempts (company_id, created_at DESC);

-- Histórico append-only.
CREATE FUNCTION public.m2_validation_attempts_protect()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  RAISE EXCEPTION 'validacao_imutavel: historico de validacao e imutavel (id=%).',
    coalesce(OLD.id, NEW.id);
END;
$$;

CREATE TRIGGER trg_bva_protect
  BEFORE UPDATE OR DELETE ON public.benefit_validation_attempts
  FOR EACH ROW EXECUTE FUNCTION public.m2_validation_attempts_protect();

ALTER TABLE public.benefit_validation_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY bva_select ON public.benefit_validation_attempts
  FOR SELECT TO authenticated
  USING (public.is_site_admin()
         OR public.m2_is_company_owner(company_id)
         OR EXISTS (SELECT 1 FROM public.site_company_members m
                     WHERE m.id = validator_member_id AND m.auth_user_id = auth.uid()));

REVOKE ALL ON TABLE public.benefit_validation_attempts
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.benefit_validation_attempts TO authenticated;

-- ----------------------------------------------------------------------------
-- Prova de autoridade do validador + pacote mínimo para o gateway
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.prepare_benefit_validation(
  p_company_id uuid, p_unit_id uuid, p_token text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_comp    public.site_partner_companies%ROWTYPE;
  v_member  public.site_company_members%ROWTYPE;
  v_unit    public.site_partner_units%ROWTYPE;
  v_hash    bytea;
  v_motivo  text;
  v_id      uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  IF p_token IS NULL OR pg_catalog.length(pg_catalog.btrim(p_token)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_required');
  END IF;
  v_hash := public.m1_token_hash(pg_catalog.btrim(p_token));

  SELECT * INTO v_comp FROM public.site_partner_companies WHERE id = p_company_id;
  IF NOT FOUND OR v_comp.status <> 'active' THEN
    -- Sem empresa conhecida não há a quem atribuir a tentativa.
    RETURN pg_catalog.jsonb_build_object('ok', true, 'allowed', false,
                                         'reason', 'validation_denied');
  END IF;

  SELECT * INTO v_member FROM public.site_company_members
   WHERE company_id = p_company_id AND auth_user_id = v_uid AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'allowed', false,
                                         'reason', 'validation_denied');
  END IF;

  SELECT * INTO v_unit FROM public.site_partner_units
   WHERE id = p_unit_id AND company_id = p_company_id AND status = 'active';
  IF NOT FOUND THEN
    v_motivo := 'UNIT_INVALID';
  ELSIF v_member.role = 'partner_manager' AND NOT EXISTS (
      SELECT 1 FROM public.site_member_unit_bindings b
       WHERE b.member_id = v_member.id AND b.unit_id = p_unit_id AND b.status = 'active') THEN
    v_motivo := 'MANAGER_NOT_BOUND_TO_UNIT';
  END IF;

  IF v_motivo IS NOT NULL THEN
    -- A negativa também é auditada (por isso não se levanta exceção).
    INSERT INTO public.benefit_validation_attempts
      (company_id, unit_id, validator_member_id, validator_role,
       partner_network_bridge_id, partner_branch_bridge_id,
       validator_bridge_id, token_hash, result, rejection_code)
    VALUES (p_company_id, v_unit.id, v_member.id, v_member.role,
            v_comp.partner_network_bridge_id, v_unit.partner_branch_bridge_id,
            v_member.validator_bridge_id, v_hash, 'denied_local', v_motivo);

    PERFORM public.m1_auditar('benefit_validation.denied_local', p_company_id,
      v_member.role,
      pg_catalog.jsonb_build_object('rejection_code', v_motivo));

    RETURN pg_catalog.jsonb_build_object('ok', true, 'allowed', false,
                                         'reason', 'validation_denied');
  END IF;

  INSERT INTO public.benefit_validation_attempts
    (company_id, unit_id, validator_member_id, validator_role,
     partner_network_bridge_id, partner_branch_bridge_id,
     validator_bridge_id, token_hash, result)
  VALUES (p_company_id, v_unit.id, v_member.id, v_member.role,
          v_comp.partner_network_bridge_id, v_unit.partner_branch_bridge_id,
          v_member.validator_bridge_id, v_hash, 'forwarded_to_app')
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('benefit_validation.prepared', p_company_id,
    v_member.role,
    pg_catalog.jsonb_build_object('attempt_id', v_id, 'unit_id', v_unit.id,
                                  'validator_role', v_member.role));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'allowed', true,
    'attempt_id', v_id,
    'correlation_id', (SELECT correlation_id FROM public.benefit_validation_attempts
                        WHERE id = v_id),
    'partner_network_bridge_id', v_comp.partner_network_bridge_id,
    'partner_branch_bridge_id', v_unit.partner_branch_bridge_id,
    'validator_bridge_id', v_member.validator_bridge_id,
    'validator_role', v_member.role,
    -- Hash em hexadecimal; o token cru NÃO volta e não é persistido.
    'token_hash', pg_catalog.encode(v_hash, 'hex'),
    -- O desfecho real depende do App.
    'app_gateway', 'BLOCKED_APP_REPOSITORY');
END;
$$;

-- Desfecho devolvido pelo gateway do App (quando existir): vira auditoria,
-- preservando a imutabilidade do histórico.
CREATE FUNCTION public.prov_record_validation_result(
  p_attempt_id uuid, p_app_request_id uuid DEFAULT NULL,
  p_rejection_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_a public.benefit_validation_attempts%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  SELECT * INTO v_a FROM public.benefit_validation_attempts WHERE id = p_attempt_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  PERFORM public.m1_auditar(
    CASE WHEN p_rejection_code IS NULL
         THEN 'benefit_validation.accepted_by_app'
         ELSE 'benefit_validation.rejected_by_app' END,
    v_a.company_id, 'service_backend',
    pg_catalog.jsonb_build_object('attempt_id', v_a.id,
                                  'app_request_id', p_app_request_id,
                                  'rejection_code', p_rejection_code,
                                  'correlation_id', v_a.correlation_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'recorded', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prepare_benefit_validation(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_benefit_validation(uuid,uuid,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.prepare_benefit_validation(uuid,uuid,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.prov_record_validation_result(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_record_validation_result(uuid,uuid,text) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_record_validation_result(uuid,uuid,text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.m2_validation_attempts_protect() FROM PUBLIC;

COMMENT ON FUNCTION public.prepare_benefit_validation(uuid,uuid,text) IS
  'LADO SITE da validação de benefício: prova validador, unidade e rede, e '
  'devolve o pacote mínimo ao gateway. O desfecho do benefício é autoridade '
  'do App (BLOCKED_APP_REPOSITORY).';
