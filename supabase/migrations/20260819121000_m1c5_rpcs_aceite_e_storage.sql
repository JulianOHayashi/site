-- ===========================================================================
-- M1-C5b — RPCs: aceite explícito (B4) e vínculo com Storage real (B5)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- B4 — create_partner_application passa a EXIGIR o ato de aceite
-- ---------------------------------------------------------------------------
-- A validação dos aceites acontece ANTES de qualquer INSERT, de modo que uma
-- recusa não deixa nem aplicação nem representante nem aceite parciais.
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
  v_aceites   jsonb;
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

  -- ATO DE ACEITE: validado antes de tocar qualquer tabela.
  v_aceites := public.m1_resolver_aceites(p_payload->'acceptances');
  IF (v_aceites->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
             'reason', v_aceites->>'reason',
             'doc_type', v_aceites->>'doc_type');
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

    PERFORM public.m1_persistir_aceites(
      v_app_id, v_aceites->'docs',
      pg_catalog.jsonb_build_object('collected_at', pg_catalog.now()));
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'application_in_progress');
  END;

  PERFORM public.m1_enfileirar_email(
    v_email, 'partner_application_email_verification',
    pg_catalog.jsonb_build_object('application_id', v_app_id, 'purpose', 'email_verification'),
    v_app_id,
    'pav:' || v_app_id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));

  PERFORM public.m1_auditar('partner_application.created', v_app_id, 'anon',
                            pg_catalog.jsonb_build_object('status','pending_email_verification'));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app_id,
                                       'status', 'pending_email_verification');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_partner_application(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_partner_application(jsonb) TO anon, authenticated, service_role;

-- Leitura pública dos termos vigentes, para a UI exibir e enviar os ids.
CREATE FUNCTION public.get_partner_application_terms()
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tipo  text;
  v_doc   public.legal_documents%ROWTYPE;
  v_itens jsonb := '[]'::jsonb;
BEGIN
  FOREACH v_tipo IN ARRAY public.m1_doc_types_solicitacao() LOOP
    SELECT * INTO v_doc FROM public.current_legal_document(v_tipo);
    IF v_doc.id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'legal_document_unavailable');
    END IF;
    v_itens := v_itens || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'legal_document_id', v_doc.id,
      'doc_type',          v_doc.doc_type,
      'version',           v_doc.version,
      'title',             v_doc.title,
      'content',           v_doc.content,
      'content_url',       v_doc.content_url));
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'documents', v_itens);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_partner_application_terms() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_partner_application_terms() TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- B5 — METADADO SÓ EXISTE SE O OBJETO EXISTIR
-- ---------------------------------------------------------------------------
-- DEFEITO CORRIGIDO: o registro não verificava storage.objects. Era possível
-- criar metadado — e supersedir o documento anterior — sem que arquivo algum
-- tivesse sido enviado.
--
-- ORDEM OBRIGATÓRIA: verificar objeto -> inserir metadado novo -> só então
-- supersedir o anterior. Qualquer falha antes disso deixa o documento
-- corrente intacto.
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
  v_app_id   uuid;
  v_doc_id   uuid;
  v_anterior uuid;
  v_uid      uuid := auth.uid();
  v_obj      storage.objects%ROWTYPE;
  v_size     bigint;
  v_mime     text;
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

  -- 1. O OBJETO PRECISA EXISTIR, no bucket certo e na pasta da aplicação.
  SELECT * INTO v_obj
    FROM storage.objects o
   WHERE o.bucket_id = 'partner-application-docs'
     AND o.name      = p_storage_path;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_found');
  END IF;

  IF split_part(v_obj.name, '/', 1) <> v_app_id::text THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_path');
  END IF;

  IF v_obj.owner IS NOT NULL AND v_obj.owner <> v_uid THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_owned');
  END IF;

  -- 2. Tamanho e mime AUTORITATIVOS vêm do Storage quando disponíveis; o que
  --    o cliente informou não é aceito como verdade.
  v_size := coalesce((v_obj.metadata->>'size')::bigint, p_byte_size);
  v_mime := coalesce(nullif(v_obj.metadata->>'mimetype',''), p_mime_type);

  IF v_obj.metadata IS NOT NULL THEN
    IF (v_obj.metadata ? 'size')     AND p_byte_size IS DISTINCT FROM v_size THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'metadata_mismatch');
    END IF;
    IF (v_obj.metadata ? 'mimetype') AND p_mime_type IS DISTINCT FROM v_mime THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'metadata_mismatch');
    END IF;
  END IF;

  -- 3. Insere o metadado NOVO antes de mexer no anterior.
  BEGIN
    INSERT INTO public.partner_application_documents
      (application_id, doc_type, storage_path, original_filename,
       mime_type, byte_size, checksum_sha256, uploaded_by)
    VALUES
      (v_app_id, p_doc_type, p_storage_path, p_original_filename,
       v_mime, v_size, pg_catalog.lower(p_checksum_sha256), v_uid)
    RETURNING id INTO v_doc_id;
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_document');
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'duplicate_document');
  END;

  -- 4. Só agora o anterior vira histórico.
  SELECT d.id INTO v_anterior
    FROM public.partner_application_documents d
   WHERE d.application_id = v_app_id
     AND d.doc_type       = p_doc_type
     AND d.superseded_at IS NULL
     AND d.id <> v_doc_id
   FOR UPDATE;

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

REVOKE EXECUTE ON FUNCTION public.register_partner_application_document(text, text, text, text, bigint, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.register_partner_application_document(text, text, text, text, bigint, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- B5 — admin revisa apenas o documento CORRENTE de aplicação revisável
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_review_partner_document(
  p_document_id uuid,
  p_decision    text,
  p_notes       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app_id uuid;
  v_super  timestamptz;
  v_status text;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_decision NOT IN ('accepted','rejected') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  SELECT d.application_id, d.superseded_at INTO v_app_id, v_super
    FROM public.partner_application_documents d
   WHERE d.id = p_document_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- Histórico é somente leitura: não é a submissão corrente.
  IF v_super IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_superseded');
  END IF;

  SELECT status INTO v_status FROM public.partner_applications
   WHERE id = v_app_id FOR UPDATE;

  IF v_status NOT IN ('under_review','changes_requested') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  UPDATE public.partner_application_documents
     SET review_status = p_decision,
         review_notes  = p_notes,
         reviewed_at   = pg_catalog.now(),
         reviewed_by   = auth.uid()
   WHERE id = p_document_id;

  PERFORM public.m1_auditar('partner_application.document_reviewed', v_app_id, 'admin',
                            pg_catalog.jsonb_build_object('document_id', p_document_id,
                                                          'review_status', p_decision));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'document_id', p_document_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_review_partner_document(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_review_partner_document(uuid, text, text) TO authenticated, service_role;
