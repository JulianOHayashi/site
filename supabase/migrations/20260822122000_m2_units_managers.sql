-- ============================================================================
-- M2 / R4 — Unidades e managers
--
-- Regras congeladas:
--   * partner_owner E partner_manager podem validar benefício;
--   * o mínimo de lançamento é 1 unidade ativa + >=1 validador ativo
--     (owner OU manager) — múltiplos managers são o esperado, não o gate;
--   * manager NÃO tem acesso financeiro por padrão;
--   * revogação/suspensão tem efeito IMEDIATO;
--   * auditoria com ator, papel, unidade, momento e resultado.
--
-- CONVITE DE MANAGER: propósito PRÓPRIO, nunca reaproveitando o token de
-- candidatura. O padrão de segurança do M1 é espelhado: segredo cunhado no
-- DESPACHO, somente hash persistido, TTL de 48h, uso único, lease com
-- recuperação, teto de tentativas, revogação e auditoria sem segredo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Unidades (filiais)
-- ----------------------------------------------------------------------------
CREATE TABLE public.site_partner_units (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               uuid NOT NULL REFERENCES public.site_partner_companies(id),
  name                     text        NOT NULL,
  city                     text        NOT NULL,
  uf                       text        NOT NULL,
  status                   text        NOT NULL DEFAULT 'active',
  partner_branch_bridge_id uuid        NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT spu_name_nonempty CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  CONSTRAINT spu_city_nonempty CHECK (length(btrim(city)) BETWEEN 2 AND 120),
  CONSTRAINT spu_uf_valida     CHECK (public.commercial_is_valid_uf(uf)),
  CONSTRAINT spu_status_allowed
    CHECK (status = ANY (ARRAY['active','suspended','archived'])),
  CONSTRAINT spu_timestamps CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX spu_nome_vivo_idx
  ON public.site_partner_units (company_id, lower(btrim(name)))
  WHERE status <> 'archived';

CREATE TRIGGER trg_spu_touch
  BEFORE UPDATE ON public.site_partner_units
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 2. Convites de manager (sem coluna de segredo)
-- ----------------------------------------------------------------------------
CREATE TABLE public.site_manager_invites (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES public.site_partner_companies(id),
  unit_id              uuid REFERENCES public.site_partner_units(id),
  email                text        NOT NULL,
  full_name            text        NOT NULL,
  invited_by_member_id uuid NOT NULL REFERENCES public.site_company_members(id),
  status               text        NOT NULL DEFAULT 'pending',
  accepted_member_id   uuid REFERENCES public.site_company_members(id),
  accepted_at          timestamptz,
  revoked_at           timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT smi_email_formato
    CHECK (email = lower(btrim(email))
           AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
           AND length(email) <= 320),
  CONSTRAINT smi_full_name_nonempty
    CHECK (length(btrim(full_name)) BETWEEN 3 AND 200),
  CONSTRAINT smi_status_allowed
    CHECK (status = ANY (ARRAY['pending','accepted','revoked','expired','superseded'])),
  CONSTRAINT smi_aceite_coerente
    CHECK ((status = 'accepted')
           = (accepted_member_id IS NOT NULL AND accepted_at IS NOT NULL)),
  CONSTRAINT smi_revogacao_coerente
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL)),
  CONSTRAINT smi_timestamps CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX smi_pendente_por_email_idx
  ON public.site_manager_invites (company_id, email)
  WHERE status = 'pending';

CREATE TRIGGER trg_smi_touch
  BEFORE UPDATE ON public.site_manager_invites
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- Tokens de convite: tabela PRÓPRIA, espelhando partner_application_tokens.
CREATE TABLE public.site_manager_invite_tokens (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id      uuid NOT NULL REFERENCES public.site_manager_invites(id) ON DELETE CASCADE,
  purpose        text        NOT NULL,
  email          text        NOT NULL,
  token_hash     bytea       NOT NULL,
  expires_at     timestamptz NOT NULL,
  consumed_at    timestamptz,
  invalidated_at timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),

  -- Propósito EXPLÍCITO e exclusivo deste domínio.
  CONSTRAINT smit_purpose_allowed CHECK (purpose = 'manager_invite'),
  CONSTRAINT smit_email_formato
    CHECK (email = lower(btrim(email)) AND length(email) <= 320),
  CONSTRAINT smit_hash_tamanho  CHECK (octet_length(token_hash) = 32),
  CONSTRAINT smit_expira_depois CHECK (expires_at > created_at),
  CONSTRAINT smit_consumo_unico CHECK (consumed_at IS NULL OR invalidated_at IS NULL)
);

CREATE INDEX smit_invite_idx ON public.site_manager_invite_tokens (invite_id);
CREATE UNIQUE INDEX smit_hash_vivo_idx
  ON public.site_manager_invite_tokens (token_hash)
  WHERE consumed_at IS NULL AND invalidated_at IS NULL;

-- ----------------------------------------------------------------------------
-- 3. Vínculo manager <-> unidade
-- ----------------------------------------------------------------------------
CREATE TABLE public.site_member_unit_bindings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id         uuid NOT NULL REFERENCES public.site_company_members(id),
  unit_id           uuid NOT NULL REFERENCES public.site_partner_units(id),
  status            text        NOT NULL DEFAULT 'active',
  revoked_at        timestamptz,
  revocation_reason text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT smub_status_allowed CHECK (status = ANY (ARRAY['active','revoked'])),
  CONSTRAINT smub_revogacao_coerente
    CHECK ((status = 'active' AND revoked_at IS NULL AND revocation_reason IS NULL)
           OR (status = 'revoked' AND revoked_at IS NOT NULL
               AND length(btrim(coalesce(revocation_reason,''))) >= 3)),
  CONSTRAINT smub_timestamps CHECK (updated_at >= created_at)
);

CREATE UNIQUE INDEX smub_vivo_idx
  ON public.site_member_unit_bindings (member_id, unit_id)
  WHERE status = 'active';

CREATE TRIGGER trg_smub_touch
  BEFORE UPDATE ON public.site_member_unit_bindings
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ----------------------------------------------------------------------------
-- 4. RLS
-- ----------------------------------------------------------------------------
ALTER TABLE public.site_partner_units        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_manager_invites      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_manager_invite_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_member_unit_bindings ENABLE ROW LEVEL SECURITY;

CREATE POLICY spu_membro_select ON public.site_partner_units
  FOR SELECT TO authenticated
  USING (public.m2_is_company_member(company_id) OR public.is_site_admin());

-- Convites carregam e-mail de terceiros: só owner e admin leem.
CREATE POLICY smi_owner_select ON public.site_manager_invites
  FOR SELECT TO authenticated
  USING (public.m2_is_company_owner(company_id) OR public.is_site_admin());

CREATE POLICY smub_select ON public.site_member_unit_bindings
  FOR SELECT TO authenticated
  USING (public.is_site_admin()
         OR EXISTS (SELECT 1 FROM public.site_company_members m
                     WHERE m.id = member_id
                       AND (m.auth_user_id = auth.uid()
                            OR public.m2_is_company_owner(m.company_id))));

-- Tokens: NENHUMA policy. Nem o owner lê hashes de convite.
REVOKE ALL ON TABLE public.site_partner_units
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.site_manager_invites
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.site_manager_invite_tokens
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.site_member_unit_bindings
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.site_partner_units        TO authenticated;
GRANT SELECT ON public.site_manager_invites      TO authenticated;
GRANT SELECT ON public.site_member_unit_bindings TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Emissão de token do convite (helper interno, espelha m1_emitir_token)
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.m2_emitir_token_convite(
  p_invite_id uuid,
  p_email     text,
  p_ttl       interval
)
RETURNS text
LANGUAGE plpgsql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_segredo text;
BEGIN
  -- Um novo token invalida o anterior do mesmo convite.
  UPDATE public.site_manager_invite_tokens
     SET invalidated_at = pg_catalog.now()
   WHERE invite_id      = p_invite_id
     AND consumed_at    IS NULL
     AND invalidated_at IS NULL;

  v_segredo := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.site_manager_invite_tokens
    (invite_id, purpose, email, token_hash, expires_at)
  VALUES
    (p_invite_id, 'manager_invite', p_email,
     public.m1_token_hash(v_segredo), pg_catalog.now() + p_ttl);

  RETURN v_segredo;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.m2_emitir_token_convite(uuid, text, interval) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_emitir_token_convite(uuid, text, interval) FROM service_role;

-- TTL do convite: 48 horas (regra preservada).
CREATE FUNCTION public.m2_convite_ttl()
RETURNS interval LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$ SELECT interval '48 hours'; $$;
REVOKE EXECUTE ON FUNCTION public.m2_convite_ttl() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_convite_ttl() FROM service_role;

-- ----------------------------------------------------------------------------
-- 6. Unidades — RPCs do owner
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.owner_create_unit(
  p_company_id uuid, p_name text, p_city text, p_uf text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT (public.m2_is_company_owner(p_company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_partner_companies
                  WHERE id = p_company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;

  BEGIN
    INSERT INTO public.site_partner_units (company_id, name, city, uf)
    VALUES (p_company_id, pg_catalog.btrim(p_name), pg_catalog.btrim(p_city),
            pg_catalog.upper(pg_catalog.btrim(p_uf)))
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'duplicate_unit');
    WHEN check_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
  END;

  PERFORM public.m1_auditar('partner_unit.created', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'name', pg_catalog.btrim(p_name)));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'unit_id', v_id);
END;
$$;

CREATE FUNCTION public.owner_set_unit_status(
  p_unit_id uuid, p_status text, p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_unit public.site_partner_units%ROWTYPE;
BEGIN
  IF p_status NOT IN ('active','suspended','archived') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_status');
  END IF;
  SELECT * INTO v_unit FROM public.site_partner_units
   WHERE id = p_unit_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_unit.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_unit.status = p_status THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true);
  END IF;

  UPDATE public.site_partner_units SET status = p_status WHERE id = p_unit_id;

  PERFORM public.m1_auditar('partner_unit.status_changed', p_unit_id, 'owner',
    pg_catalog.jsonb_build_object('status', p_status),
    pg_catalog.jsonb_build_object('status', v_unit.status),
    pg_catalog.jsonb_build_object('reason', p_reason));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false);
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. Convite de manager — criação (o segredo NÃO nasce aqui)
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.owner_create_manager_invite(
  p_company_id uuid, p_email text, p_full_name text, p_unit_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_owner_member uuid;
  v_email text := pg_catalog.lower(pg_catalog.btrim(p_email));
  v_id uuid;
BEGIN
  SELECT m.id INTO v_owner_member
    FROM public.site_company_members m
   WHERE m.company_id = p_company_id AND m.auth_user_id = auth.uid()
     AND m.role = 'partner_owner' AND m.status = 'active';

  IF v_owner_member IS NULL THEN
    IF NOT public.is_site_admin() THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
    END IF;
    SELECT m.id INTO v_owner_member FROM public.site_company_members m
     WHERE m.company_id = p_company_id AND m.role = 'partner_owner'
       AND m.status = 'active';
    IF v_owner_member IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_without_owner');
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.site_partner_companies
                  WHERE id = p_company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;
  IF p_unit_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.site_partner_units
        WHERE id = p_unit_id AND company_id = p_company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_unit');
  END IF;

  -- Reenvio: o convite pendente anterior é SUPERSEDIDO e seu token morre.
  UPDATE public.site_manager_invites
     SET status = 'superseded'
   WHERE company_id = p_company_id AND email = v_email AND status = 'pending';
  UPDATE public.site_manager_invite_tokens t
     SET invalidated_at = pg_catalog.now()
    FROM public.site_manager_invites i
   WHERE t.invite_id = i.id AND i.status = 'superseded'
     AND i.company_id = p_company_id AND i.email = v_email
     AND t.consumed_at IS NULL AND t.invalidated_at IS NULL;

  BEGIN
    INSERT INTO public.site_manager_invites
      (company_id, unit_id, email, full_name, invited_by_member_id)
    VALUES (p_company_id, p_unit_id, v_email,
            pg_catalog.btrim(p_full_name), v_owner_member)
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN check_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
  END;

  -- O segredo é cunhado no DESPACHO pelo worker (svc_mint_manager_invite_token).
  PERFORM public.m1_enfileirar_email(
    v_email, 'manager_invite',
    pg_catalog.jsonb_build_object('invite_id', v_id, 'purpose', 'manager_invite',
                                  'company_id', p_company_id),
    NULL, 'smi:' || v_id::text);

  PERFORM public.m1_auditar('manager_invite.created', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id, 'unit_id', p_unit_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'invite_id', v_id);
END;
$$;

CREATE FUNCTION public.owner_revoke_manager_invite(p_invite_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_inv public.site_manager_invites%ROWTYPE;
BEGIN
  SELECT * INTO v_inv FROM public.site_manager_invites
   WHERE id = p_invite_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_inv.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_inv.status <> 'pending' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'status', v_inv.status);
  END IF;

  UPDATE public.site_manager_invites
     SET status = 'revoked', revoked_at = pg_catalog.now() WHERE id = p_invite_id;
  UPDATE public.site_manager_invite_tokens
     SET invalidated_at = pg_catalog.now()
   WHERE invite_id = p_invite_id
     AND consumed_at IS NULL AND invalidated_at IS NULL;

  PERFORM public.m1_auditar('manager_invite.revoked', p_invite_id, 'owner');
  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false);
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. Cunhagem NO DESPACHO — espelha svc_mint_partner_application_token
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.svc_mint_manager_invite_token(p_notification_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_evt     public.notification_events%ROWTYPE;
  v_inv     public.site_manager_invites%ROWTYPE;
  v_segredo text;
  v_ttl     interval := public.m2_convite_ttl();
BEGIN
  SELECT * INTO v_evt FROM public.notification_events
   WHERE id = p_notification_id FOR UPDATE;

  IF NOT FOUND OR v_evt.template_key IS DISTINCT FROM 'manager_invite' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- Lease: outro worker está entregando agora.
  IF v_evt.status = 'sending'
     AND v_evt.updated_at > pg_catalog.now() - public.m1_mint_lease() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'lease_held');
  END IF;

  IF v_evt.status = 'scheduled'
     AND (v_evt.scheduled_for IS NULL OR v_evt.scheduled_for > pg_catalog.now()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_due_yet');
  END IF;

  IF v_evt.status NOT IN ('pending','scheduled','sending') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- Lease vencido: recupera pelo caminho legítimo sending -> failed -> scheduled.
  IF v_evt.status = 'sending' THEN
    UPDATE public.notification_events
       SET status = 'failed',
           first_failed_at = coalesce(first_failed_at, pg_catalog.now()),
           last_failed_at  = pg_catalog.now(),
           error_code      = 'lease_expired'
     WHERE id = v_evt.id;
    UPDATE public.notification_events
       SET status = 'scheduled', scheduled_for = pg_catalog.now()
     WHERE id = v_evt.id;
  END IF;

  IF v_evt.attempt_count >= public.m1_mint_max_tentativas() THEN
    UPDATE public.notification_events
       SET status = 'failed',
           first_failed_at = coalesce(first_failed_at, pg_catalog.now()),
           last_failed_at  = pg_catalog.now(),
           error_code      = 'max_attempts',
           updated_at      = pg_catalog.now()
     WHERE id = v_evt.id;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'max_attempts');
  END IF;

  SELECT * INTO v_inv FROM public.site_manager_invites
   WHERE id = (v_evt.template_data->>'invite_id')::uuid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- Propósito coerente com o estado: convite morto não ressuscita por envio atrasado.
  IF v_inv.status <> 'pending' THEN
    UPDATE public.notification_events
       SET status = 'cancelled', updated_at = pg_catalog.now() WHERE id = v_evt.id;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'stale_for_state');
  END IF;

  v_segredo := public.m2_emitir_token_convite(v_inv.id, v_inv.email, v_ttl);

  UPDATE public.notification_events
     SET status = 'sending', attempt_count = attempt_count + 1,
         updated_at = pg_catalog.now()
   WHERE id = v_evt.id;

  -- Auditoria SEM segredo.
  PERFORM public.m1_auditar('manager_invite.token_minted', v_inv.id, 'system',
    pg_catalog.jsonb_build_object('purpose', 'manager_invite',
                                  'notification_id', v_evt.id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'invite_id', v_inv.id, 'purpose', 'manager_invite',
    'recipient', v_inv.email, 'token', v_segredo,
    'attempt', v_evt.attempt_count + 1,
    'expires_in_seconds', (extract(epoch FROM v_ttl))::bigint);
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. Aceite do convite (uso único)
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.accept_manager_invite(p_token text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_tok   public.site_manager_invite_tokens%ROWTYPE;
  v_inv   public.site_manager_invites%ROWTYPE;
  v_email text;
  v_member uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  IF p_token IS NULL OR pg_catalog.length(pg_catalog.btrim(p_token)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  SELECT * INTO v_tok FROM public.site_manager_invite_tokens
   WHERE token_hash = public.m1_token_hash(pg_catalog.btrim(p_token))
     AND purpose = 'manager_invite'
   FOR UPDATE;

  IF NOT FOUND OR v_tok.consumed_at IS NOT NULL OR v_tok.invalidated_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;
  IF v_tok.expires_at <= pg_catalog.now() THEN
    UPDATE public.site_manager_invite_tokens
       SET invalidated_at = pg_catalog.now() WHERE id = v_tok.id;
    UPDATE public.site_manager_invites
       SET status = 'expired' WHERE id = v_tok.invite_id AND status = 'pending';
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;

  SELECT * INTO v_inv FROM public.site_manager_invites
   WHERE id = v_tok.invite_id FOR UPDATE;
  IF v_inv.status <> 'pending' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_partner_companies
                  WHERE id = v_inv.company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;

  -- O convite é para um e-mail específico: a conta precisa ser aquela.
  SELECT pg_catalog.lower(pg_catalog.btrim(u.email)) INTO v_email
    FROM auth.users u WHERE u.id = v_uid;
  IF v_email IS DISTINCT FROM v_inv.email THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'email_mismatch');
  END IF;

  IF EXISTS (SELECT 1 FROM public.site_company_members
              WHERE company_id = v_inv.company_id AND auth_user_id = v_uid
                AND status IN ('active','suspended')) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_member');
  END IF;

  INSERT INTO public.site_company_members
    (company_id, auth_user_id, role, status, full_name, email, source)
  VALUES (v_inv.company_id, v_uid, 'partner_manager', 'active',
          v_inv.full_name, v_inv.email, 'manager_invite')
  RETURNING id INTO v_member;

  IF v_inv.unit_id IS NOT NULL THEN
    INSERT INTO public.site_member_unit_bindings (member_id, unit_id)
    VALUES (v_member, v_inv.unit_id);
  END IF;

  -- USO ÚNICO: token consumido e convite encerrado.
  UPDATE public.site_manager_invite_tokens
     SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;
  UPDATE public.site_manager_invites
     SET status = 'accepted', accepted_member_id = v_member,
         accepted_at = pg_catalog.now()
   WHERE id = v_inv.id;

  PERFORM public.m1_auditar('manager_invite.accepted', v_inv.id, 'partner_manager',
    pg_catalog.jsonb_build_object('member_id', v_member,
                                  'company_id', v_inv.company_id,
                                  'unit_id', v_inv.unit_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'member_id', v_member,
                                       'company_id', v_inv.company_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. Gestão de managers e vínculos
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.owner_set_manager_status(
  p_member_id uuid, p_action text, p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_m public.site_company_members%ROWTYPE;
BEGIN
  IF p_action NOT IN ('suspend','reactivate','revoke') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_action');
  END IF;
  SELECT * INTO v_m FROM public.site_company_members
   WHERE id = p_member_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_m.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  -- O owner não se auto-revoga por esta via.
  IF v_m.role <> 'partner_manager' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'manager_only');
  END IF;

  IF p_action = 'revoke' THEN
    IF v_m.status = 'revoked' THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true);
    END IF;
    IF p_reason IS NULL OR pg_catalog.length(pg_catalog.btrim(p_reason)) < 3 THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reason_required');
    END IF;
    UPDATE public.site_company_members
       SET status = 'revoked', revoked_at = pg_catalog.now(),
           revocation_reason = pg_catalog.btrim(p_reason)
     WHERE id = p_member_id;
    -- Efeito IMEDIATO também nos vínculos de unidade.
    UPDATE public.site_member_unit_bindings
       SET status = 'revoked', revoked_at = pg_catalog.now(),
           revocation_reason = 'manager revogado'
     WHERE member_id = p_member_id AND status = 'active';
  ELSIF p_action = 'suspend' THEN
    IF v_m.status <> 'active' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_transition');
    END IF;
    UPDATE public.site_company_members SET status = 'suspended' WHERE id = p_member_id;
  ELSE
    IF v_m.status <> 'suspended' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_transition');
    END IF;
    UPDATE public.site_company_members SET status = 'active' WHERE id = p_member_id;
  END IF;

  PERFORM public.m1_auditar('company_member.status_changed', p_member_id, 'owner',
    pg_catalog.jsonb_build_object('action', p_action),
    pg_catalog.jsonb_build_object('status', v_m.status),
    pg_catalog.jsonb_build_object('reason', p_reason));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false);
END;
$$;

CREATE FUNCTION public.owner_set_manager_unit_binding(
  p_member_id uuid, p_unit_id uuid, p_bound boolean, p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_m public.site_company_members%ROWTYPE;
BEGIN
  SELECT * INTO v_m FROM public.site_company_members
   WHERE id = p_member_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_m.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_m.role <> 'partner_manager' OR v_m.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'manager_inactive');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_partner_units
                  WHERE id = p_unit_id AND company_id = v_m.company_id
                    AND status <> 'archived') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_unit');
  END IF;

  IF p_bound THEN
    IF EXISTS (SELECT 1 FROM public.site_member_unit_bindings
                WHERE member_id = p_member_id AND unit_id = p_unit_id
                  AND status = 'active') THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true);
    END IF;
    INSERT INTO public.site_member_unit_bindings (member_id, unit_id)
    VALUES (p_member_id, p_unit_id);
  ELSE
    UPDATE public.site_member_unit_bindings
       SET status = 'revoked', revoked_at = pg_catalog.now(),
           revocation_reason = coalesce(nullif(pg_catalog.btrim(coalesce(p_reason,'')), ''),
                                        'desvinculado pelo owner')
     WHERE member_id = p_member_id AND unit_id = p_unit_id AND status = 'active';
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true);
    END IF;
  END IF;

  PERFORM public.m1_auditar('company_member.unit_binding_changed', p_member_id, 'owner',
    pg_catalog.jsonb_build_object('unit_id', p_unit_id, 'bound', p_bound));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false);
END;
$$;

-- ----------------------------------------------------------------------------
-- 11. Elegibilidade de validador (owner OU manager) e prontidão de lançamento
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.get_my_validator_context(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_m   public.site_company_members%ROWTYPE;
  v_units jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'eligible', false);
  END IF;

  SELECT * INTO v_m FROM public.site_company_members
   WHERE company_id = p_company_id AND auth_user_id = v_uid AND status = 'active';

  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.site_partner_companies
                               WHERE id = p_company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'eligible', false);
  END IF;

  IF v_m.role = 'partner_owner' THEN
    -- Owner valida em todas as unidades ativas da empresa.
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'unit_id', u.id, 'name', u.name,
             'branch_bridge_id', u.partner_branch_bridge_id) ORDER BY u.name), '[]'::jsonb)
      INTO v_units
      FROM public.site_partner_units u
     WHERE u.company_id = p_company_id AND u.status = 'active';
  ELSE
    -- Manager valida SOMENTE nas unidades ativas às quais está vinculado.
    SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'unit_id', u.id, 'name', u.name,
             'branch_bridge_id', u.partner_branch_bridge_id) ORDER BY u.name), '[]'::jsonb)
      INTO v_units
      FROM public.site_member_unit_bindings b
      JOIN public.site_partner_units u ON u.id = b.unit_id
     WHERE b.member_id = v_m.id AND b.status = 'active' AND u.status = 'active';
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'eligible', pg_catalog.jsonb_array_length(v_units) > 0,
    'role', v_m.role,
    'member_id', v_m.id,
    'validator_bridge_id', v_m.validator_bridge_id,
    'units', v_units);
END;
$$;

CREATE FUNCTION public.company_launch_readiness(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT pg_catalog.jsonb_build_object(
    'company_id', p_company_id,
    'active_unit', EXISTS (
      SELECT 1 FROM public.site_partner_units u
       WHERE u.company_id = p_company_id AND u.status = 'active'),
    -- >=1 validador ativo: owner (com unidade ativa) OU manager vinculado.
    'active_validator', EXISTS (
      SELECT 1 FROM public.site_partner_units u
       WHERE u.company_id = p_company_id AND u.status = 'active')
      AND EXISTS (
      SELECT 1 FROM public.site_company_members m
       WHERE m.company_id = p_company_id AND m.status = 'active'
         AND (m.role = 'partner_owner'
              OR EXISTS (SELECT 1 FROM public.site_member_unit_bindings b
                           JOIN public.site_partner_units u2 ON u2.id = b.unit_id
                          WHERE b.member_id = m.id AND b.status = 'active'
                            AND u2.status = 'active'))));
$$;

-- ----------------------------------------------------------------------------
-- 12. ACLs
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.owner_create_unit(uuid,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owner_create_unit(uuid,text,text,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.owner_create_unit(uuid,text,text,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.owner_set_unit_status(uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owner_set_unit_status(uuid,text,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.owner_set_unit_status(uuid,text,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.owner_create_manager_invite(uuid,text,text,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owner_create_manager_invite(uuid,text,text,uuid) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.owner_create_manager_invite(uuid,text,text,uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.owner_revoke_manager_invite(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owner_revoke_manager_invite(uuid) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.owner_revoke_manager_invite(uuid) TO authenticated;

-- Cunhagem: EXCLUSIVA do worker.
REVOKE EXECUTE ON FUNCTION public.svc_mint_manager_invite_token(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.svc_mint_manager_invite_token(uuid) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.svc_mint_manager_invite_token(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.accept_manager_invite(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.accept_manager_invite(text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.accept_manager_invite(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.owner_set_manager_status(uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owner_set_manager_status(uuid,text,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.owner_set_manager_status(uuid,text,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.owner_set_manager_unit_binding(uuid,uuid,boolean,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owner_set_manager_unit_binding(uuid,uuid,boolean,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.owner_set_manager_unit_binding(uuid,uuid,boolean,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_validator_context(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_validator_context(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_my_validator_context(uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.company_launch_readiness(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.company_launch_readiness(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.company_launch_readiness(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.svc_mint_manager_invite_token(uuid) IS
  'Cunha o segredo do convite de manager no despacho e devolve o bruto APENAS '
  'no retorno. Propósito próprio (manager_invite), somente hash persistido, '
  'TTL 48h, lease e teto de tentativas. Exclusiva do worker service_role.';
