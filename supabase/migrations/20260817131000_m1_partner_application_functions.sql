-- ===========================================================================
-- M1 — RPCs DO ONBOARDING FASE 2A
-- ===========================================================================
-- Toda transição de estado acontece aqui, server-side. O frontend nunca é
-- autoridade de status, papel ou permissão.
--
-- Padrões obrigatórios aplicados a TODAS as funções deste arquivo:
--   * SECURITY DEFINER com SET search_path fixo ('pg_catalog');
--   * nomes totalmente qualificados;
--   * REVOKE EXECUTE ... FROM PUBLIC seguido de GRANT às roles estritamente
--     necessárias (mesmo com o H1 fail-closed: a intenção é declarada);
--   * auth.uid() como autoridade — nenhum user_id vindo do browser;
--   * erros genéricos para o chamador anônimo, sem enumeração de dados.
--
-- A RPC legada create_my_partner_owner_registration NÃO é chamada.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Helper interno: emissão e hash de token
-- ---------------------------------------------------------------------------
-- Sem grants a nenhuma role do Data API. Uso exclusivo interno.
CREATE FUNCTION public.m1_token_hash(p_token text)
RETURNS bytea
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8'));
$$;

REVOKE EXECUTE ON FUNCTION public.m1_token_hash(text) FROM PUBLIC;

COMMENT ON FUNCTION public.m1_token_hash(text) IS
  'sha256 do segredo. Helper interno: nenhuma role do Data API recebe EXECUTE.';

-- ---------------------------------------------------------------------------
-- Helper interno: emitir token, invalidando o anterior do mesmo propósito
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.m1_emitir_token(
  p_application_id uuid,
  p_purpose        text,
  p_email          text,
  p_ttl            interval
)
RETURNS text
LANGUAGE plpgsql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_segredo text;
BEGIN
  -- Um novo token invalida o anterior do mesmo propósito.
  UPDATE public.partner_application_tokens
     SET invalidated_at = pg_catalog.now()
   WHERE application_id = p_application_id
     AND purpose        = p_purpose
     AND consumed_at    IS NULL
     AND invalidated_at IS NULL;

  v_segredo := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.partner_application_tokens
    (application_id, purpose, email, token_hash, expires_at)
  VALUES
    (p_application_id, p_purpose, p_email,
     public.m1_token_hash(v_segredo), pg_catalog.now() + p_ttl);

  RETURN v_segredo;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_emitir_token(uuid, text, text, interval) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Helper interno: auditoria append-only
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.m1_auditar(
  p_action     text,
  p_entity_id  uuid,
  p_actor_role text,
  p_new_state  jsonb DEFAULT NULL,
  p_prev_state jsonb DEFAULT NULL,
  p_metadata   jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE sql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
  INSERT INTO public.audit_logs
    (actor_user_id, actor_role, action, entity_type, entity_id,
     previous_state, new_state, source, metadata)
  VALUES
    (auth.uid(), p_actor_role, p_action, 'partner_application',
     p_entity_id::text, p_prev_state, p_new_state, 'site_m1', p_metadata);
$$;

REVOKE EXECUTE ON FUNCTION public.m1_auditar(text, uuid, text, jsonb, jsonb, jsonb) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Helper interno: enfileirar notificação no outbox existente
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.m1_enfileirar_email(
  p_address        text,
  p_template_key   text,
  p_template_data  jsonb,
  p_application_id uuid,
  p_idempotency    text
)
RETURNS void
LANGUAGE sql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
  INSERT INTO public.notification_events
    (channel, recipient_address, template_key, template_data,
     idempotency_key, correlation_entity_type, correlation_entity_id)
  VALUES
    ('email', p_address, p_template_key, p_template_data,
     p_idempotency, 'partner_application', p_application_id::text)
  ON CONFLICT (channel, idempotency_key) DO NOTHING;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_enfileirar_email(text, text, jsonb, uuid, text) FROM PUBLIC;

COMMENT ON FUNCTION public.m1_enfileirar_email(text, text, jsonb, uuid, text) IS
  'Entrega desacoplada. O segredo em claro trafega apenas aqui, no payload do outbox, legível somente por service_role.';

-- ===========================================================================
-- 1. create_partner_application — solicitação empresarial PRÉ-AUTH
-- ===========================================================================
CREATE FUNCTION public.create_partner_application(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_cnpj    text;
  v_email   text;
  v_rep_email text;
  v_app_id  uuid;
  v_segredo text;
BEGIN
  IF p_payload IS NULL OR pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  END IF;

  -- Normalização server-side. O que o browser manda é entrada, não verdade.
  v_cnpj      := pg_catalog.regexp_replace(coalesce(p_payload->>'cnpj',''), '[^0-9]', '', 'g');
  v_email     := pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'contact_email','')));
  v_rep_email := pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'representative_email', v_email)));

  IF v_cnpj !~ '^[0-9]{14}$' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_cnpj');
  END IF;

  -- Bloqueio de duplicidade em estado NÃO TERMINAL. Mensagem genérica:
  -- não confirmamos ao anônimo detalhes da solicitação existente.
  IF EXISTS (
    SELECT 1 FROM public.partner_applications a
     WHERE a.cnpj = v_cnpj
       AND a.status IN ('pending_email_verification','under_review','changes_requested')
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'application_in_progress');
  END IF;

  BEGIN
    INSERT INTO public.partner_applications
      (cnpj, legal_name, trade_name, contact_email, contact_phone,
       postal_code, street, street_number, complement, district, city, uf)
    VALUES
      (v_cnpj,
       pg_catalog.btrim(p_payload->>'legal_name'),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'trade_name','')), ''),
       v_email,
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'contact_phone',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'postal_code',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'street','')), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'street_number','')), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'complement','')), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'district','')), ''),
       pg_catalog.btrim(p_payload->>'city'),
       pg_catalog.upper(pg_catalog.btrim(coalesce(p_payload->>'uf',''))))
    RETURNING id INTO v_app_id;

    INSERT INTO public.partner_application_representatives
      (application_id, full_name, cpf, email, phone, role_title)
    VALUES
      (v_app_id,
       pg_catalog.btrim(p_payload->>'representative_full_name'),
       pg_catalog.regexp_replace(coalesce(p_payload->>'representative_cpf',''), '[^0-9]', '', 'g'),
       v_rep_email,
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'representative_phone',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'representative_role_title','')), ''));
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'application_in_progress');
  END;

  v_segredo := public.m1_emitir_token(v_app_id, 'email_verification', v_email, interval '24 hours');

  PERFORM public.m1_enfileirar_email(
    v_email,
    'partner_application_email_verification',
    pg_catalog.jsonb_build_object('application_id', v_app_id, 'token', v_segredo),
    v_app_id,
    'pav:' || v_app_id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS')
  );

  PERFORM public.m1_auditar('partner_application.created', v_app_id, 'anon',
                            pg_catalog.jsonb_build_object('status','pending_email_verification'));

  -- Nunca devolvemos o token ao chamador: ele viaja apenas pelo outbox.
  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app_id,
                                       'status', 'pending_email_verification');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_partner_application(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_partner_application(jsonb) TO anon, authenticated, service_role;

-- ===========================================================================
-- 2. confirm_partner_application_email — uso único, expirável, idempotente
-- ===========================================================================
CREATE FUNCTION public.confirm_partner_application_email(p_token text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tok    public.partner_application_tokens%ROWTYPE;
  v_app    public.partner_applications%ROWTYPE;
  v_claim  text;
BEGIN
  IF p_token IS NULL OR pg_catalog.length(pg_catalog.btrim(p_token)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  SELECT * INTO v_tok
    FROM public.partner_application_tokens
   WHERE token_hash = public.m1_token_hash(p_token)
     AND purpose    = 'email_verification'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  -- Reutilização falha. O estado da aplicação NÃO é tocado.
  IF v_tok.consumed_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_already_used');
  END IF;

  IF v_tok.invalidated_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_invalidated');
  END IF;

  IF v_tok.expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_expired');
  END IF;

  SELECT * INTO v_app FROM public.partner_applications WHERE id = v_tok.application_id FOR UPDATE;

  -- Idempotência de efeito: se o e-mail já está confirmado, consumimos o
  -- token e devolvemos o mesmo resultado, sem re-transicionar o estado nem
  -- duplicar eventos.
  IF v_app.email_verified_at IS NOT NULL THEN
    UPDATE public.partner_application_tokens
       SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                         'status', v_app.status, 'already_confirmed', true);
  END IF;

  UPDATE public.partner_application_tokens
     SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;

  UPDATE public.partner_applications
     SET email_verified_at = pg_catalog.now(),
         status            = 'under_review'
   WHERE id = v_app.id;

  -- Token de reivindicação da conta provisória: curto e de uso único.
  v_claim := public.m1_emitir_token(v_app.id, 'account_claim', v_app.contact_email, interval '30 minutes');

  PERFORM public.m1_auditar('partner_application.email_confirmed', v_app.id, 'anon',
                            pg_catalog.jsonb_build_object('status','under_review'),
                            pg_catalog.jsonb_build_object('status', v_app.status));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                       'status', 'under_review',
                                       'already_confirmed', false,
                                       'claim_token', v_claim);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_partner_application_email(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.confirm_partner_application_email(text) TO anon, authenticated, service_role;

-- ===========================================================================
-- 3. claim_partner_application_account — vínculo com Auth (conta provisória)
-- ===========================================================================
-- Chamada DEPOIS do signUp, já autenticado. A autoridade é auth.uid();
-- nenhum user_id é aceito do browser.
CREATE FUNCTION public.claim_partner_application_account(p_claim_token text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tok public.partner_application_tokens%ROWTYPE;
  v_app public.partner_applications%ROWTYPE;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF p_claim_token IS NULL OR pg_catalog.length(pg_catalog.btrim(p_claim_token)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  SELECT * INTO v_tok
    FROM public.partner_application_tokens
   WHERE token_hash = public.m1_token_hash(p_claim_token)
     AND purpose    = 'account_claim'
   FOR UPDATE;

  IF NOT FOUND
     OR v_tok.consumed_at IS NOT NULL
     OR v_tok.invalidated_at IS NOT NULL
     OR v_tok.expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  SELECT * INTO v_app FROM public.partner_applications WHERE id = v_tok.application_id FOR UPDATE;

  IF v_app.account_user_id IS NOT NULL THEN
    UPDATE public.partner_application_tokens SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;
    IF v_app.account_user_id = v_uid THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                           'account_kind', 'provisional', 'already_linked', true);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_linked');
  END IF;

  UPDATE public.partner_application_tokens SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;

  UPDATE public.partner_applications
     SET account_user_id   = v_uid,
         account_linked_at = pg_catalog.now(),
         account_kind      = 'provisional'
   WHERE id = v_app.id;

  PERFORM public.m1_auditar('partner_application.account_claimed', v_app.id, 'applicant',
                            pg_catalog.jsonb_build_object('account_kind','provisional'));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                       'account_kind', 'provisional', 'already_linked', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_partner_application_account(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.claim_partner_application_account(text) TO authenticated, service_role;

-- ===========================================================================
-- 4. get_my_partner_application — leitura da conta provisória
-- ===========================================================================
CREATE FUNCTION public.get_my_partner_application()
RETURNS jsonb
LANGUAGE sql STABLE
SECURITY INVOKER
SET search_path TO 'pg_catalog'
AS $$
  -- SECURITY INVOKER de propósito: a RLS da tabela é quem filtra as linhas.
  SELECT coalesce(
    (SELECT pg_catalog.jsonb_build_object(
        'application_id', a.id,
        'status', a.status,
        'company_review_status', a.company_review_status,
        'authority_review_status', a.authority_review_status,
        'account_kind', a.account_kind,
        'cnpj', a.cnpj,
        'legal_name', a.legal_name,
        'city', a.city,
        'uf', a.uf,
        'created_at', a.created_at,
        'pending_corrections', (
           SELECT pg_catalog.count(*) FROM public.partner_application_corrections c
            WHERE c.application_id = a.id AND c.responded_at IS NULL),
        'documents', (
           SELECT pg_catalog.count(*) FROM public.partner_application_documents d
            WHERE d.application_id = a.id))
       FROM public.partner_applications a
      WHERE a.account_user_id = auth.uid()
      LIMIT 1),
    pg_catalog.jsonb_build_object('application_id', NULL));
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_partner_application() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_my_partner_application() TO authenticated, service_role;

-- ===========================================================================
-- 5. respond_partner_application_correction
-- ===========================================================================
CREATE FUNCTION public.respond_partner_application_correction(
  p_correction_id uuid,
  p_message       text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app_id uuid;
  v_uid    uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT c.application_id INTO v_app_id
    FROM public.partner_application_corrections c
    JOIN public.partner_applications a ON a.id = c.application_id
   WHERE c.id = p_correction_id
     AND a.account_user_id = v_uid
     AND c.responded_at IS NULL
   FOR UPDATE OF c;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF p_message IS NULL OR pg_catalog.length(pg_catalog.btrim(p_message)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_message');
  END IF;

  UPDATE public.partner_application_corrections
     SET response_message = pg_catalog.left(pg_catalog.btrim(p_message), 2000),
         responded_at     = pg_catalog.now(),
         responded_by     = v_uid
   WHERE id = p_correction_id;

  PERFORM public.m1_auditar('partner_application.correction_answered', v_app_id, 'applicant',
                            pg_catalog.jsonb_build_object('correction_id', p_correction_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'correction_id', p_correction_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.respond_partner_application_correction(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.respond_partner_application_correction(uuid, text) TO authenticated, service_role;

-- ===========================================================================
-- 6. register_partner_application_document — metadados após upload privado
-- ===========================================================================
CREATE FUNCTION public.register_partner_application_document(
  p_doc_type          text,
  p_storage_path      text,
  p_original_filename text,
  p_mime_type         text,
  p_byte_size         bigint,
  p_checksum_sha256   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app_id uuid;
  v_doc_id uuid;
  v_uid    uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT a.id INTO v_app_id
    FROM public.partner_applications a
   WHERE a.account_user_id = v_uid
     AND a.status IN ('under_review','changes_requested');

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_allowed');
  END IF;

  -- O caminho precisa pertencer à pasta da própria aplicação. A constraint
  -- da tabela repete essa exigência: defesa em profundidade.
  IF p_storage_path IS NULL OR p_storage_path NOT LIKE (v_app_id::text || '/%') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_path');
  END IF;

  BEGIN
    INSERT INTO public.partner_application_documents
      (application_id, doc_type, storage_path, original_filename,
       mime_type, byte_size, checksum_sha256, uploaded_by)
    VALUES
      (v_app_id, p_doc_type, p_storage_path, p_original_filename,
       p_mime_type, p_byte_size, pg_catalog.lower(p_checksum_sha256), v_uid)
    RETURNING id INTO v_doc_id;
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_document');
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'duplicate_document');
  END;

  PERFORM public.m1_auditar('partner_application.document_registered', v_app_id, 'applicant',
                            pg_catalog.jsonb_build_object('document_id', v_doc_id, 'doc_type', p_doc_type));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'document_id', v_doc_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.register_partner_application_document(text, text, text, text, bigint, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.register_partner_application_document(text, text, text, text, bigint, text) TO authenticated, service_role;
