-- ===========================================================================
-- M1-C3 — RPCs CORRIGIDAS (B1, B2, B4, B5, B8, identidade de e-mail)
-- ===========================================================================
-- Substitui as RPCs afetadas por CREATE OR REPLACE. Assinaturas preservadas,
-- exceto onde a auditoria exigiu função nova.
-- Todas mantêm SECURITY DEFINER + search_path fixo; os grants existentes
-- permanecem válidos e são reafirmados ao final.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. create_partner_application — agora exige aceite jurídico real (B4)
--    e valida CNPJ/CPF por dígito verificador no servidor (B6)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_partner_application(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_cnpj      text;
  v_cpf       text;
  v_email     text;
  v_rep_email text;
  v_app_id    uuid;
  v_segredo   text;
BEGIN
  IF p_payload IS NULL OR pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  END IF;

  v_cnpj      := pg_catalog.regexp_replace(coalesce(p_payload->>'cnpj',''), '[^0-9]', '', 'g');
  v_cpf       := pg_catalog.regexp_replace(coalesce(p_payload->>'representative_cpf',''), '[^0-9]', '', 'g');
  v_email     := pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'contact_email','')));
  v_rep_email := pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'representative_email', v_email)));

  IF NOT public.m1_cnpj_valido(v_cnpj) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_cnpj');
  END IF;
  IF NOT public.m1_cpf_valido(v_cpf) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_cpf');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.partner_applications a
     WHERE a.cnpj = v_cnpj
       AND a.status IN ('pending_email_verification','pending_account_setup',
                        'under_review','changes_requested')
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
       v_cpf, v_rep_email,
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'representative_phone',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'representative_role_title','')), ''));

    -- Aceite jurídico server-side. Sem documento publicado, nada é criado:
    -- a exceção reverte a transação inteira.
    PERFORM public.m1_registrar_aceites_preauth(
      v_app_id,
      pg_catalog.jsonb_build_object('collected_at', pg_catalog.now()));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'legal_document_unavailable');
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'application_in_progress');
  END;

  v_segredo := public.m1_emitir_token(v_app_id, 'email_verification', v_email, interval '24 hours');

  PERFORM public.m1_enfileirar_email(
    v_email, 'partner_application_email_verification',
    pg_catalog.jsonb_build_object('application_id', v_app_id, 'token', v_segredo),
    v_app_id,
    'pav:' || v_app_id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));

  PERFORM public.m1_auditar('partner_application.created', v_app_id, 'anon',
                            pg_catalog.jsonb_build_object('status','pending_email_verification'));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app_id,
                                       'status', 'pending_email_verification');
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. confirm_partner_application_email — para em pending_account_setup (B1)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_partner_application_email(p_token text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tok   public.partner_application_tokens%ROWTYPE;
  v_app   public.partner_applications%ROWTYPE;
  v_claim text;
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
  IF v_tok.consumed_at    IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_already_used');
  END IF;
  IF v_tok.invalidated_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_invalidated');
  END IF;
  IF v_tok.expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_expired');
  END IF;

  SELECT * INTO v_app FROM public.partner_applications WHERE id = v_tok.application_id FOR UPDATE;

  UPDATE public.partner_application_tokens SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;

  IF v_app.email_verified_at IS NOT NULL THEN
    -- Já confirmado: efeito idempotente. Se ainda falta a conta, emitimos um
    -- claim novo (o anterior pode ter se perdido na resposta).
    IF v_app.status = 'pending_account_setup' THEN
      v_claim := public.m1_emitir_token(v_app.id, 'account_claim', v_app.contact_email, interval '30 minutes');
      PERFORM public.m1_enfileirar_email(
        v_app.contact_email, 'partner_application_account_claim',
        pg_catalog.jsonb_build_object('application_id', v_app.id, 'token', v_claim),
        v_app.id,
        'pac1r:' || v_app.id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
      RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                           'status', v_app.status, 'already_confirmed', true,
                                           'claim_token', v_claim);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                         'status', v_app.status, 'already_confirmed', true);
  END IF;

  UPDATE public.partner_applications
     SET email_verified_at = pg_catalog.now(),
         status            = 'pending_account_setup'
   WHERE id = v_app.id;

  v_claim := public.m1_emitir_token(v_app.id, 'account_claim', v_app.contact_email, interval '30 minutes');

  -- B2/7: o claim tambem vai por e-mail. Se a RESPOSTA desta chamada se
  -- perder (rede, aba fechada, StrictMode), o titular ainda consegue criar
  -- a conta pelo link recebido, sem replay do token de verificacao.
  PERFORM public.m1_enfileirar_email(
    v_app.contact_email, 'partner_application_account_claim',
    pg_catalog.jsonb_build_object('application_id', v_app.id, 'token', v_claim),
    v_app.id,
    'pac1:' || v_app.id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));

  PERFORM public.m1_auditar('partner_application.email_confirmed', v_app.id, 'anon',
                            pg_catalog.jsonb_build_object('status','pending_account_setup'),
                            pg_catalog.jsonb_build_object('status', v_app.status));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                       'status', 'pending_account_setup',
                                       'already_confirmed', false,
                                       'claim_token', v_claim);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. claim_partner_application_account — identidade de e-mail + B1 + B4
-- ---------------------------------------------------------------------------
-- Default seguro: a primeira conta provisória usa o MESMO e-mail verificado.
-- Delegação a outro endereço exigiria decisão de produto e verificação
-- própria — não é presumida aqui.
CREATE OR REPLACE FUNCTION public.claim_partner_application_account(p_claim_token text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tok        public.partner_application_tokens%ROWTYPE;
  v_app        public.partner_applications%ROWTYPE;
  v_uid        uuid := auth.uid();
  v_email_auth text;
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
     OR v_tok.consumed_at    IS NOT NULL
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

  IF v_app.status <> 'pending_account_setup' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_claimable');
  END IF;

  -- IDENTIDADE DO E-MAIL: a conta Auth precisa ser o mesmo endereço que foi
  -- verificado. O token NÃO é consumido em caso de divergência, para que o
  -- titular legítimo ainda consiga usá-lo.
  SELECT pg_catalog.lower(pg_catalog.btrim(u.email)) INTO v_email_auth
    FROM auth.users u WHERE u.id = v_uid;

  IF v_email_auth IS DISTINCT FROM v_app.contact_email THEN
    PERFORM public.m1_auditar('partner_application.claim_email_mismatch', v_app.id, 'applicant',
                              NULL, NULL, pg_catalog.jsonb_build_object('motivo','email_mismatch'));
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'email_mismatch');
  END IF;

  UPDATE public.partner_application_tokens SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;

  UPDATE public.partner_applications
     SET account_user_id   = v_uid,
         account_linked_at = pg_catalog.now(),
         account_kind      = 'provisional',
         status            = 'under_review'
   WHERE id = v_app.id;

  -- B4: promoção ATÔMICA do vínculo jurídico, compatível com
  -- legal_acceptances_protect (linked_auth_user_id e auth_user_id juntos).
  UPDATE public.legal_acceptances
     SET linked_auth_user_id = v_uid,
         auth_user_id        = v_uid
   WHERE partner_application_id = v_app.id
     AND linked_auth_user_id IS NULL;

  PERFORM public.m1_auditar('partner_application.account_claimed', v_app.id, 'applicant',
                            pg_catalog.jsonb_build_object('account_kind','provisional',
                                                          'status','under_review'),
                            pg_catalog.jsonb_build_object('status','pending_account_setup'));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                       'account_kind', 'provisional',
                                       'status', 'under_review', 'already_linked', false);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. request_partner_application_recovery — B2, recuperação pública real
-- ---------------------------------------------------------------------------
-- Resposta SEMPRE idêntica: não confirma existência de CNPJ nem de e-mail.
-- Cobre os dois buracos: link de verificação expirado, e e-mail já
-- confirmado com claim perdido/expirado. O segredo novo vai apenas para o
-- endereço já registrado na solicitação; nunca para um informado agora.
CREATE FUNCTION public.request_partner_application_recovery(
  p_cnpj  text,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_cnpj    text;
  v_email   text;
  v_app     public.partner_applications%ROWTYPE;
  v_recente boolean;
  v_segredo text;
BEGIN
  v_cnpj  := pg_catalog.regexp_replace(coalesce(p_cnpj,''), '[^0-9]', '', 'g');
  v_email := pg_catalog.lower(pg_catalog.btrim(coalesce(p_email,'')));

  SELECT * INTO v_app
    FROM public.partner_applications a
   WHERE a.cnpj = v_cnpj
     AND a.contact_email = v_email
     AND a.status IN ('pending_email_verification','pending_account_setup')
   FOR UPDATE;

  IF FOUND THEN
    -- Contenção de abuso: no máximo um envio por minuto por aplicação.
    SELECT EXISTS (
      SELECT 1 FROM public.partner_application_tokens t
       WHERE t.application_id = v_app.id
         AND t.created_at > pg_catalog.now() - interval '1 minute'
    ) INTO v_recente;

    IF NOT v_recente THEN
      IF v_app.status = 'pending_email_verification' THEN
        v_segredo := public.m1_emitir_token(v_app.id, 'email_verification',
                                            v_app.contact_email, interval '24 hours');
        PERFORM public.m1_enfileirar_email(
          v_app.contact_email, 'partner_application_email_verification',
          pg_catalog.jsonb_build_object('application_id', v_app.id, 'token', v_segredo),
          v_app.id,
          'pav:' || v_app.id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
      ELSE
        v_segredo := public.m1_emitir_token(v_app.id, 'account_claim',
                                            v_app.contact_email, interval '30 minutes');
        PERFORM public.m1_enfileirar_email(
          v_app.contact_email, 'partner_application_account_claim',
          pg_catalog.jsonb_build_object('application_id', v_app.id, 'token', v_segredo),
          v_app.id,
          'pac2:' || v_app.id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
      END IF;

      -- Auditoria sem token algum.
      PERFORM public.m1_auditar('partner_application.recovery_requested', v_app.id, 'anon',
                                pg_catalog.jsonb_build_object('status', v_app.status));
    END IF;
  END IF;

  -- Resposta invariante: anti-enumeração.
  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'message', 'Se houver uma solicitacao ativa para estes dados, enviaremos um e-mail.');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_partner_application_recovery(text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.request_partner_application_recovery(text, text) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. register_partner_application_document — supersessão append-only (B5)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_partner_application_document(
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
  v_app_id     uuid;
  v_doc_id     uuid;
  v_anterior   uuid;
  v_uid        uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT a.id INTO v_app_id
    FROM public.partner_applications a
   WHERE a.account_user_id = v_uid
     AND a.status IN ('under_review','changes_requested')
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_allowed');
  END IF;

  IF p_storage_path IS NULL OR p_storage_path NOT LIKE (v_app_id::text || '/%') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_path');
  END IF;

  SELECT d.id INTO v_anterior
    FROM public.partner_application_documents d
   WHERE d.application_id = v_app_id
     AND d.doc_type       = p_doc_type
     AND d.superseded_at IS NULL
   FOR UPDATE;

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

  -- Reenvio não substitui: o anterior vira histórico apontando para o novo.
  IF v_anterior IS NOT NULL THEN
    UPDATE public.partner_application_documents
       SET superseded_at = pg_catalog.now(),
           superseded_by_document_id = v_doc_id
     WHERE id = v_anterior;
  END IF;

  PERFORM public.m1_auditar('partner_application.document_registered', v_app_id, 'applicant',
                            pg_catalog.jsonb_build_object('document_id', v_doc_id,
                                                          'doc_type', p_doc_type,
                                                          'supersedes', v_anterior));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'document_id', v_doc_id,
                                       'supersedes', v_anterior);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. B8 — SERIALIZAÇÃO: travar a APLICAÇÃO antes de mexer em autoridade
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_review_partner_authority(
  p_application_id uuid,
  p_decision       text,
  p_reason         text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_rep_id   uuid;
  v_anterior text;
  v_status   text;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_decision NOT IN ('approved','rejected','changes_requested') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  -- Lock da PRÓPRIA aplicação primeiro: serializa contra decide/replace.
  SELECT status INTO v_status
    FROM public.partner_applications
   WHERE id = p_application_id
   FOR UPDATE;

  IF NOT FOUND OR v_status NOT IN ('under_review','changes_requested') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  SELECT r.id, r.authority_status INTO v_rep_id, v_anterior
    FROM public.partner_application_representatives r
   WHERE r.application_id = p_application_id AND r.is_current
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  UPDATE public.partner_application_representatives
     SET authority_status = p_decision,
         decision_reason  = p_reason,
         decided_at       = CASE WHEN p_decision IN ('approved','rejected') THEN pg_catalog.now() END,
         decided_by       = CASE WHEN p_decision IN ('approved','rejected') THEN auth.uid() END
   WHERE id = v_rep_id;

  UPDATE public.partner_applications
     SET authority_review_status = p_decision
   WHERE id = p_application_id;

  PERFORM public.m1_auditar('partner_application.authority_reviewed', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('authority_review_status', p_decision,
                                                          'representative_id', v_rep_id),
                            pg_catalog.jsonb_build_object('authority_review_status', v_anterior),
                            pg_catalog.jsonb_build_object('reason', p_reason));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'authority_review_status', p_decision,
                                       'representative_id', v_rep_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_replace_partner_representative(
  p_application_id uuid,
  p_payload        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_novo_id uuid;
  v_status  text;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- Lock da aplicação ANTES de decidir que ela ainda é revisável.
  SELECT status INTO v_status
    FROM public.partner_applications
   WHERE id = p_application_id
   FOR UPDATE;

  IF NOT FOUND OR v_status NOT IN ('under_review','changes_requested') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  UPDATE public.partner_application_representatives
     SET is_current  = false,
         replaced_at = pg_catalog.now()
   WHERE application_id = p_application_id AND is_current;

  BEGIN
    INSERT INTO public.partner_application_representatives
      (application_id, full_name, cpf, email, phone, role_title)
    VALUES
      (p_application_id,
       pg_catalog.btrim(p_payload->>'full_name'),
       pg_catalog.regexp_replace(coalesce(p_payload->>'cpf',''), '[^0-9]', '', 'g'),
       pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'email',''))),
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'phone',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'role_title','')), ''))
    RETURNING id INTO v_novo_id;
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_representative');
  END;

  UPDATE public.partner_applications
     SET authority_review_status = 'pending'
   WHERE id = p_application_id;

  PERFORM public.m1_auditar('partner_application.representative_replaced', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('representative_id', v_novo_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'representative_id', v_novo_id);
END;
$$;

-- ---------------------------------------------------------------------------
-- Reafirmação explícita dos grants (política de intenção declarada)
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.create_partner_application(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_partner_application(jsonb) TO anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirm_partner_application_email(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.confirm_partner_application_email(text) TO anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.claim_partner_application_account(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.claim_partner_application_account(text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.register_partner_application_document(text, text, text, text, bigint, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.register_partner_application_document(text, text, text, text, bigint, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_review_partner_authority(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_review_partner_authority(uuid, text, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_replace_partner_representative(uuid, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_replace_partner_representative(uuid, jsonb) TO authenticated, service_role;
