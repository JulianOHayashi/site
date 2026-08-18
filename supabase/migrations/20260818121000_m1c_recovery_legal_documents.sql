-- ===========================================================================
-- M1-C2 — CORREÇÕES DA AUDITORIA (B1 RPCs, B2, B4, B5, identidade de e-mail)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- B4 — ACEITE JURÍDICO PRÉ-AUTH COM VÍNCULO REAL
-- ---------------------------------------------------------------------------
-- O checkbox do formulário não persistia nada: uma chamada direta à RPC
-- criava aplicação sem aceite algum. Passa a existir aceite server-side,
-- ligado à aplicação real e a um legal_document PUBLICADO.
--
-- Nenhum conteúdo jurídico é inventado aqui. Enquanto não houver documento
-- publicado, a solicitação é RECUSADA com `legal_document_unavailable` — o
-- launch blocker passa a ser executável, não apenas anotado.

ALTER TABLE public.legal_acceptances
  ADD CONSTRAINT legal_acceptances_partner_application_fk
    FOREIGN KEY (partner_application_id)
    REFERENCES public.partner_applications(id)
    ON DELETE RESTRICT;

CREATE INDEX legal_acceptances_partner_application_idx
  ON public.legal_acceptances (partner_application_id)
  WHERE partner_application_id IS NOT NULL;

-- Declarações exigidas na solicitação empresarial. Os doc_types já existem
-- no enum da baseline; nenhum tipo novo é criado.
CREATE FUNCTION public.m1_doc_types_solicitacao()
RETURNS text[]
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT ARRAY['truthfulness_declaration','document_analysis_authorization'];
$$;

REVOKE EXECUTE ON FUNCTION public.m1_doc_types_solicitacao() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_doc_types_solicitacao() FROM service_role;

-- Registra os aceites pré-Auth. Não usa nem altera record_legal_acceptance
-- (função legada/protegida).
CREATE FUNCTION public.m1_registrar_aceites_preauth(
  p_application_id uuid,
  p_evidence       jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tipo text;
  v_doc  public.legal_documents%ROWTYPE;
  v_n    integer := 0;
BEGIN
  FOREACH v_tipo IN ARRAY public.m1_doc_types_solicitacao() LOOP
    SELECT * INTO v_doc FROM public.current_legal_document(v_tipo);
    IF v_doc.id IS NULL THEN
      RAISE EXCEPTION 'legal_document_unavailable:%', v_tipo
        USING ERRCODE = 'no_data_found';
    END IF;

    INSERT INTO public.legal_acceptances
      (subject_type, subject_id, partner_application_id, legal_document_id,
       context, origin, evidence)
    VALUES
      ('partner_application', p_application_id, p_application_id, v_doc.id,
       'partner_application', 'server',
       p_evidence || pg_catalog.jsonb_build_object(
         'doc_type', v_tipo,
         'doc_version', v_doc.version,
         'doc_content_hash', v_doc.content_hash));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_registrar_aceites_preauth(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_registrar_aceites_preauth(uuid, jsonb) FROM service_role;

-- ---------------------------------------------------------------------------
-- B5 — DOCUMENTOS APPEND-ONLY
-- ---------------------------------------------------------------------------
-- Antes era possível: upload A → metadado accepted → delete A → upload B no
-- mesmo path → metadado continua accepted. Agora o metadado registrado
-- fecha o path, e reenvio cria objeto/path/registro NOVOS.

ALTER TABLE public.partner_application_documents
  ADD COLUMN superseded_at             timestamptz,
  ADD COLUMN superseded_by_document_id uuid REFERENCES public.partner_application_documents(id);

ALTER TABLE public.partner_application_documents
  ADD CONSTRAINT pad_supersede_coerente
    CHECK ((superseded_at IS NULL) = (superseded_by_document_id IS NULL)),
  ADD CONSTRAINT pad_nao_supersede_a_si
    CHECK (superseded_by_document_id IS DISTINCT FROM id);

CREATE INDEX pad_ativos_idx
  ON public.partner_application_documents (application_id, doc_type)
  WHERE superseded_at IS NULL;

-- Metadado é imutável nos campos de conteúdo; revisão e supersessão são as
-- únicas evoluções permitidas, e nenhuma delas volta atrás.
CREATE FUNCTION public.m1_documents_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Documento nao pode ser excluido (id=%). Use supersessao.', OLD.id;
  END IF;

  IF NEW.id                IS DISTINCT FROM OLD.id
  OR NEW.application_id    IS DISTINCT FROM OLD.application_id
  OR NEW.doc_type          IS DISTINCT FROM OLD.doc_type
  OR NEW.storage_bucket    IS DISTINCT FROM OLD.storage_bucket
  OR NEW.storage_path      IS DISTINCT FROM OLD.storage_path
  OR NEW.original_filename IS DISTINCT FROM OLD.original_filename
  OR NEW.mime_type         IS DISTINCT FROM OLD.mime_type
  OR NEW.byte_size         IS DISTINCT FROM OLD.byte_size
  OR NEW.checksum_sha256   IS DISTINCT FROM OLD.checksum_sha256
  OR NEW.uploaded_by       IS DISTINCT FROM OLD.uploaded_by
  OR NEW.created_at        IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Campos de conteudo do documento sao imutaveis (id=%).', OLD.id;
  END IF;

  IF OLD.superseded_at IS NOT NULL
     AND (NEW.superseded_at IS DISTINCT FROM OLD.superseded_at
          OR NEW.superseded_by_document_id IS DISTINCT FROM OLD.superseded_by_document_id) THEN
    RAISE EXCEPTION 'Supersessao e irreversivel (id=%).', OLD.id;
  END IF;

  IF OLD.review_status IN ('accepted','rejected')
     AND NEW.review_status IS DISTINCT FROM OLD.review_status THEN
    RAISE EXCEPTION 'Revisao de documento e final (id=%). Envie um novo documento.', OLD.id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_documents_append_only() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_documents_append_only() FROM service_role;

CREATE TRIGGER trg_pad_append_only_upd
  BEFORE UPDATE ON public.partner_application_documents
  FOR EACH ROW EXECUTE FUNCTION public.m1_documents_append_only();

CREATE TRIGGER trg_pad_append_only_del
  BEFORE DELETE ON public.partner_application_documents
  FOR EACH ROW EXECUTE FUNCTION public.m1_documents_append_only();

-- Storage: o titular só pode apagar objeto que AINDA NÃO tem metadado.
-- Registrado o metadado, o objeto fica imutável para ele.
DROP POLICY m1_partner_docs_titular_delete ON storage.objects;

CREATE POLICY m1_partner_docs_titular_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'partner-application-docs'
    AND EXISTS (
      SELECT 1 FROM public.partner_applications a
       WHERE a.account_user_id = auth.uid()
         AND a.id::text = split_part(storage.objects.name, '/', 1)
         AND a.status IN ('under_review','changes_requested')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.partner_application_documents d
       WHERE d.storage_bucket = 'partner-application-docs'
         AND d.storage_path = storage.objects.name
    )
  );

-- Inserir objeto em path que já possui metadado também é bloqueado: evita
-- substituir conteúdo por delete+insert ou por caminho reaproveitado.
DROP POLICY m1_partner_docs_titular_insert ON storage.objects;

CREATE POLICY m1_partner_docs_titular_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'partner-application-docs'
    AND EXISTS (
      SELECT 1 FROM public.partner_applications a
       WHERE a.account_user_id = auth.uid()
         AND a.id::text = split_part(storage.objects.name, '/', 1)
         AND a.status IN ('under_review','changes_requested')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.partner_application_documents d
       WHERE d.storage_bucket = 'partner-application-docs'
         AND d.storage_path = storage.objects.name
    )
  );
