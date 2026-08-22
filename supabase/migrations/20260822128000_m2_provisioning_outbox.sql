-- ============================================================================
-- M2 / R11 — Outbox de PROVISIONAMENTO Site -> App (camada 1 de 5)
--
-- DOMÍNIO SEPARADO do outbox de e-mail: tabela própria e operações de serviço
-- próprias (prov_*), nunca as svc_* específicas de notificação. O que se
-- reaproveita do M1 é o PADRÃO: lease, tentativas, idempotência, ACL,
-- auditoria estruturada e tratamento de segredo.
--
-- CAMADAS (só a 1 existe aqui):
--   1. banco/outbox + vínculo durável        -> IMPLEMENTADA
--   2. worker assinado (Ed25519, JTI, kid)   -> fronteira de adaptador
--   3. transporte HTTP                        -> fronteira de adaptador
--   4. resposta/binding do App                -> BLOCKED_APP_REPOSITORY
--   5. E2E real                               -> BLOCKED_APP_REPOSITORY
--
-- Nenhuma chave, segredo ou token é gerado ou persistido aqui: a assinatura
-- acontece fora do banco, no worker, com a chave carregada em tempo de
-- execução.
-- ============================================================================

CREATE TABLE public.app_provisioning_messages (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schema_version text        NOT NULL DEFAULT 'bdflow.commercial_provisioning.v1',
  environment    text        NOT NULL,
  exclusivity_id uuid        NOT NULL REFERENCES public.commercial_exclusivities(id),
  -- Correlação = também o JTI antirreplay da mensagem assinada.
  correlation_id uuid        NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  payload        jsonb       NOT NULL,
  payload_hash   text        NOT NULL,
  status         text        NOT NULL DEFAULT 'pending',
  attempt_count  integer     NOT NULL DEFAULT 0,
  dispatched_at  timestamptz,
  accepted_at    timestamptz,
  operational_cycle_id uuid,
  rejection_code text,
  last_error     text,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT apm_env_allowed
    CHECK (environment = ANY (ARRAY['local','staging','production'])),
  CONSTRAINT apm_status_allowed
    CHECK (status = ANY (ARRAY['pending','dispatching','accepted','rejected','failed'])),
  CONSTRAINT apm_payload_objeto CHECK (jsonb_typeof(payload) = 'object'),
  CONSTRAINT apm_hash_formato CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT apm_attempt_nao_neg CHECK (attempt_count >= 0),
  CONSTRAINT apm_aceite_coerente
    CHECK ((status <> 'accepted')
           OR (accepted_at IS NOT NULL AND operational_cycle_id IS NOT NULL)),
  CONSTRAINT apm_rejeicao_coerente
    CHECK ((status <> 'rejected') OR rejection_code IS NOT NULL),
  CONSTRAINT apm_erro_tamanho CHECK (last_error IS NULL OR length(last_error) <= 2000),
  CONSTRAINT apm_timestamps CHECK (updated_at >= created_at)
);

-- Uma mensagem viva por (exclusividade, ambiente).
CREATE UNIQUE INDEX apm_viva_idx
  ON public.app_provisioning_messages (exclusivity_id, environment)
  WHERE status IN ('pending','dispatching','accepted');

CREATE TRIGGER trg_apm_touch
  BEFORE UPDATE ON public.app_provisioning_messages
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

CREATE FUNCTION public.m2_provisioning_protect()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'provisionamento_imutavel: mensagem nao pode ser excluida (id=%).', OLD.id;
  END IF;
  IF NEW.payload        IS DISTINCT FROM OLD.payload
  OR NEW.payload_hash   IS DISTINCT FROM OLD.payload_hash
  OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
  OR NEW.exclusivity_id IS DISTINCT FROM OLD.exclusivity_id
  OR NEW.environment    IS DISTINCT FROM OLD.environment
  OR NEW.schema_version IS DISTINCT FROM OLD.schema_version THEN
    RAISE EXCEPTION 'provisionamento_imutavel: snapshot da mensagem e imutavel (id=%).', OLD.id;
  END IF;
  IF OLD.status = 'accepted' THEN
    IF NEW.status <> 'accepted'
    OR NEW.operational_cycle_id IS DISTINCT FROM OLD.operational_cycle_id THEN
      RAISE EXCEPTION 'provisionamento_imutavel: aceite do App e imutavel (id=%).', OLD.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_apm_protect
  BEFORE UPDATE OR DELETE ON public.app_provisioning_messages
  FOR EACH ROW EXECUTE FUNCTION public.m2_provisioning_protect();

-- ----------------------------------------------------------------------------
-- Vínculo durável exclusividade <-> ciclo operacional (append-only)
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_operational_bindings (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exclusivity_id       uuid NOT NULL UNIQUE REFERENCES public.commercial_exclusivities(id),
  operational_cycle_id uuid NOT NULL,
  environment          text NOT NULL,
  provisioning_message_id uuid NOT NULL UNIQUE
                          REFERENCES public.app_provisioning_messages(id),
  bound_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cob_env_allowed
    CHECK (environment = ANY (ARRAY['local','staging','production'])),
  -- Um ciclo operacional serve a uma única formação no ambiente.
  CONSTRAINT cob_ciclo_unico UNIQUE (operational_cycle_id, environment)
);

CREATE FUNCTION public.m2_bindings_protect()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  RAISE EXCEPTION 'vinculo_imutavel: vinculo comercial<->operacional e imutavel (id=%).',
    coalesce(OLD.id, NEW.id);
END;
$$;

CREATE TRIGGER trg_cob_protect
  BEFORE UPDATE OR DELETE ON public.commercial_operational_bindings
  FOR EACH ROW EXECUTE FUNCTION public.m2_bindings_protect();

ALTER TABLE public.app_provisioning_messages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_operational_bindings ENABLE ROW LEVEL SECURITY;

CREATE POLICY apm_admin_select ON public.app_provisioning_messages
  FOR SELECT TO authenticated USING (public.is_site_admin());
CREATE POLICY cob_admin_select ON public.commercial_operational_bindings
  FOR SELECT TO authenticated USING (public.is_site_admin());

REVOKE ALL ON TABLE public.app_provisioning_messages
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.commercial_operational_bindings
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.app_provisioning_messages      TO authenticated;
GRANT SELECT ON public.commercial_operational_bindings TO authenticated;

-- ----------------------------------------------------------------------------
-- SNAPSHOT MÍNIMO
-- ENVIA: versão, ambiente, exclusividade, UUIDs de ponte, nicho, referência do
--        pedido, janela operacional, pool contratual, moeda, versões de
--        política, quantidade nominal, filiais e validadores ativos.
-- NÃO ENVIA: CNPJ, razão social, CPF, e-mail, telefone, documentos, valores
--        devidos à BDFlow, pagamento, valor econômico, PII.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.build_app_provisioning_payload(
  p_exclusivity_id uuid, p_environment text
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_excl   public.commercial_exclusivities%ROWTYPE;
  v_region public.commercial_regions%ROWTYPE;
  v_parts  jsonb;
BEGIN
  SELECT * INTO v_excl FROM public.commercial_exclusivities WHERE id = p_exclusivity_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'partner_network_bridge_id', c.partner_network_bridge_id,
      'niche_code', o.niche_code,
      'site_order_reference', o.id,
      'nominal_quantity', o.nominal_quantity,
      'currency', o.currency,
      'contractual_pool_cents', o.contractual_pool_cents,
      'expected_operation_start', o.expected_operation_start,
      'expected_operation_end',
        o.expected_operation_start + (o.exclusivity_period_days || ' days')::interval,
      'partner_status', c.status,
      'branches', coalesce((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'partner_branch_bridge_id', u.partner_branch_bridge_id,
                 'status', u.status) ORDER BY u.partner_branch_bridge_id)
          FROM public.site_partner_units u
         WHERE u.company_id = c.id AND u.status = 'active'), '[]'::jsonb),
      'validators', coalesce((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'validator_bridge_id', m.validator_bridge_id,
                 'role', m.role) ORDER BY m.validator_bridge_id)
          FROM public.site_company_members m
         WHERE m.company_id = c.id AND m.status = 'active'), '[]'::jsonb))
      ORDER BY o.niche_code), '[]'::jsonb)
    INTO v_parts
    FROM public.commercial_exclusivity_orders o
    JOIN public.site_partner_companies c ON c.id = o.company_id
   WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed';

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'schema_version', 'bdflow.commercial_provisioning.v1',
    'environment', p_environment,
    'commercial_exclusivity_id', v_excl.id,
    'region', pg_catalog.jsonb_build_object('uf', v_region.uf, 'name', v_region.name),
    'sequence_number', v_excl.sequence_number,
    'participant_target', 84,
    'distribution_policy_version', 1,
    'schedule_policy_version', 1,
    'partners', v_parts);
END;
$$;

-- ----------------------------------------------------------------------------
-- Enfileiramento (admin) — só após a autorização operacional
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.admin_enqueue_app_provisioning(
  p_exclusivity_id uuid, p_environment text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_excl    public.commercial_exclusivities%ROWTYPE;
  v_exist   public.app_provisioning_messages%ROWTYPE;
  v_payload jsonb;
  v_id      uuid;
BEGIN
  PERFORM public.m1_exigir_admin();
  IF p_environment NOT IN ('local','staging','production') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_environment');
  END IF;

  SELECT * INTO v_excl FROM public.commercial_exclusivities
   WHERE id = p_exclusivity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF v_excl.operation_authorized_at IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'operation_not_authorized');
  END IF;

  SELECT * INTO v_exist FROM public.app_provisioning_messages
   WHERE exclusivity_id = p_exclusivity_id AND environment = p_environment
     AND status IN ('pending','dispatching','accepted');
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'message_id', v_exist.id, 'correlation_id', v_exist.correlation_id,
      'status', v_exist.status);
  END IF;

  v_payload := public.build_app_provisioning_payload(p_exclusivity_id, p_environment);
  IF (v_payload->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_payload->>'reason');
  END IF;

  INSERT INTO public.app_provisioning_messages
    (environment, exclusivity_id, payload, payload_hash, created_by)
  VALUES (p_environment, p_exclusivity_id, v_payload,
          pg_catalog.encode(pg_catalog.sha256(
            pg_catalog.convert_to(v_payload::text,'UTF8')), 'hex'),
          auth.uid())
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('app_provisioning.enqueued', v_id, 'admin',
    pg_catalog.jsonb_build_object('exclusivity_id', p_exclusivity_id,
                                  'environment', p_environment));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'message_id', v_id,
    'correlation_id', (SELECT correlation_id FROM public.app_provisioning_messages
                        WHERE id = v_id),
    'status', 'pending');
END;
$$;

-- ----------------------------------------------------------------------------
-- Operações de SERVIÇO PRÓPRIAS deste domínio (prov_*), com lease e tentativas
-- no mesmo padrão do M1 — sem passar pelas svc_* de e-mail.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.prov_claim_provisioning_message(p_message_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_msg public.app_provisioning_messages%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  SELECT * INTO v_msg FROM public.app_provisioning_messages
   WHERE id = p_message_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF v_msg.status = 'accepted' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'status', 'accepted');
  END IF;
  -- Lease: outro worker está despachando agora.
  IF v_msg.status = 'dispatching'
     AND v_msg.updated_at > pg_catalog.now() - public.m1_mint_lease() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'lease_held');
  END IF;
  IF v_msg.status NOT IN ('pending','dispatching','failed') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;
  IF v_msg.attempt_count >= public.m1_mint_max_tentativas() THEN
    UPDATE public.app_provisioning_messages
       SET status = 'failed', last_error = 'max_attempts'
     WHERE id = v_msg.id;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'max_attempts');
  END IF;

  UPDATE public.app_provisioning_messages
     SET status = 'dispatching', attempt_count = attempt_count + 1,
         dispatched_at = pg_catalog.now()
   WHERE id = v_msg.id;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false,
    'message_id', v_msg.id,
    'correlation_id', v_msg.correlation_id,   -- JTI
    'environment', v_msg.environment,
    'schema_version', v_msg.schema_version,
    'payload', v_msg.payload,
    'payload_hash', v_msg.payload_hash,
    'attempt', v_msg.attempt_count + 1);
END;
$$;

CREATE FUNCTION public.prov_record_provisioning_result(
  p_message_id uuid,
  p_accepted   boolean,
  p_operational_cycle_id uuid DEFAULT NULL,
  p_rejection_code text DEFAULT NULL,
  p_error text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_msg public.app_provisioning_messages%ROWTYPE;
  v_bind uuid;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  SELECT * INTO v_msg FROM public.app_provisioning_messages
   WHERE id = p_message_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF v_msg.status = 'accepted' THEN
    SELECT id INTO v_bind FROM public.commercial_operational_bindings
     WHERE provisioning_message_id = v_msg.id;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'status', 'accepted', 'binding_id', v_bind,
      'operational_cycle_id', v_msg.operational_cycle_id);
  END IF;

  IF p_accepted THEN
    IF p_operational_cycle_id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
                                           'reason', 'operational_cycle_required');
    END IF;

    BEGIN
      UPDATE public.app_provisioning_messages
         SET status = 'accepted', accepted_at = pg_catalog.now(),
             operational_cycle_id = p_operational_cycle_id, last_error = NULL
       WHERE id = v_msg.id;

      INSERT INTO public.commercial_operational_bindings
        (exclusivity_id, operational_cycle_id, environment, provisioning_message_id)
      VALUES (v_msg.exclusivity_id, p_operational_cycle_id, v_msg.environment, v_msg.id)
      RETURNING id INTO v_bind;
    EXCEPTION
      WHEN unique_violation THEN
        RETURN pg_catalog.jsonb_build_object('ok', false,
                                             'reason', 'operational_cycle_already_bound');
    END;

    PERFORM public.m1_auditar('app_provisioning.accepted', v_msg.id, 'service_backend',
      pg_catalog.jsonb_build_object('operational_cycle_id', p_operational_cycle_id,
                                    'binding_id', v_bind,
                                    'correlation_id', v_msg.correlation_id));

    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
      'status', 'accepted', 'binding_id', v_bind,
      'operational_cycle_id', p_operational_cycle_id);
  END IF;

  UPDATE public.app_provisioning_messages
     SET status = CASE WHEN p_rejection_code IS NOT NULL THEN 'rejected' ELSE 'failed' END,
         rejection_code = p_rejection_code,
         last_error = left(coalesce(p_error, ''), 2000)
   WHERE id = v_msg.id;

  PERFORM public.m1_auditar('app_provisioning.not_accepted', v_msg.id, 'service_backend',
    pg_catalog.jsonb_build_object('rejection_code', p_rejection_code,
                                  'correlation_id', v_msg.correlation_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'status', CASE WHEN p_rejection_code IS NOT NULL THEN 'rejected' ELSE 'failed' END);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.build_app_provisioning_payload(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.build_app_provisioning_payload(uuid,text)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.build_app_provisioning_payload(uuid,text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_enqueue_app_provisioning(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_enqueue_app_provisioning(uuid,text)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_enqueue_app_provisioning(uuid,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.prov_claim_provisioning_message(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_claim_provisioning_message(uuid)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_claim_provisioning_message(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.prov_record_provisioning_result(uuid,boolean,uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_record_provisioning_result(uuid,boolean,uuid,text,text)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_record_provisioning_result(uuid,boolean,uuid,text,text)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.m2_provisioning_protect() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_bindings_protect() FROM PUBLIC;

COMMENT ON TABLE public.app_provisioning_messages IS
  'Camada 1 de 5 da ponte Site->App: outbox de provisionamento. Worker '
  'assinado, transporte HTTP, resposta do App e E2E permanecem pendentes '
  '(BLOCKED_APP_REPOSITORY). Nenhum segredo é gerado ou persistido aqui.';
