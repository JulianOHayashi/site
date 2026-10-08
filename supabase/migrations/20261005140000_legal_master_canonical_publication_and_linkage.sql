-- ---------------------------------------------------------------------------
-- Correções C1 e C2 da auditoria de 2026-10-05
--
-- Migration ADITIVA. Nenhuma migration histórica é editada, nenhuma linha
-- existente é reescrita e nenhum dado de produção é tocado.
--
-- C1 — O caminho canônico de publicação não alcançava o Acordo Mestre.
--      A migration anterior acrescentou 'master_agreement' ao CHECK da tabela,
--      mas `admin_publish_legal_document` tem allowlist PRÓPRIA, que parava em
--      'commercial_order_terms'. Consequência real: o seed de QA conseguia
--      inserir direto, porém a publicação administrativa normal — a auditada —
--      devolveria `doc_type_not_allowed` para um Mestre de verdade.
--
-- C2 — Não havia prova de que o Mestre assinado por uma empresa corresponde a
--      uma publicação pública concreta. `commercial_master_agreements` aceitava
--      `agreement_version` e `document_hash` como texto livre, então uma linha
--      podia nomear versão e hash que não existem em `legal_documents`. O
--      pedido guardava `master_agreement_id`, o que prova qual linha de empresa
--      foi usada, mas não que ela corresponde ao texto público renderizado.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- C1. Allowlist do caminho canônico de publicação
-- ===========================================================================
--
-- CREATE OR REPLACE preservando assinatura, exigência de admin, modelo de
-- segurança, idempotência e auditoria. A ÚNICA diferença em relação ao corpo
-- original é 'master_agreement' na allowlist. Todos os tipos anteriores
-- continuam aceitos exatamente como antes.

CREATE OR REPLACE FUNCTION public.admin_publish_legal_document(
  p_doc_type       text,
  p_version        text,
  p_title          text,
  p_content        text,
  p_content_hash   text,
  p_content_url    text DEFAULT NULL,
  p_effective_from timestamptz DEFAULT NULL,
  p_is_material_change boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tipo    text := pg_catalog.btrim(coalesce(p_doc_type, ''));
  v_versao  text := pg_catalog.btrim(coalesce(p_version, ''));
  v_hash    text := pg_catalog.btrim(coalesce(p_content_hash, ''));
  v_desde   timestamptz;
  v_vigente public.legal_documents%ROWTYPE;
  v_id      uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- Allowlist explícita: publicar tipo fora dela seria criar categoria
  -- jurídica por parâmetro. 'master_agreement' entra aqui para que o Acordo
  -- Mestre use o MESMO caminho auditado dos demais documentos.
  IF v_tipo NOT IN ('privacy_notice','provisional_account_terms',
                    'truthfulness_declaration','document_analysis_authorization',
                    'representation_declaration','future_commercial_terms',
                    'commercial_order_terms','master_agreement') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'doc_type_not_allowed');
  END IF;
  IF v_versao = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'version_required');
  END IF;
  IF pg_catalog.btrim(coalesce(p_title,'')) = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'title_required');
  END IF;
  IF pg_catalog.btrim(coalesce(p_content,'')) = ''
     AND pg_catalog.btrim(coalesce(p_content_url,'')) = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'content_required');
  END IF;
  IF v_hash = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'content_hash_required');
  END IF;

  v_desde := coalesce(p_effective_from, pg_catalog.now());
  IF v_desde < pg_catalog.now() - interval '1 minute' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'effective_from_in_past');
  END IF;

  SELECT * INTO v_vigente FROM public.legal_documents
   WHERE doc_type = v_tipo AND version = v_versao;
  IF FOUND THEN
    IF v_vigente.status = 'published' AND v_vigente.content_hash = v_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
        'legal_document_id', v_vigente.id, 'doc_type', v_tipo,
        'version', v_versao, 'content_hash', v_vigente.content_hash);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'version_already_exists');
  END IF;

  UPDATE public.legal_documents
     SET effective_to = v_desde, updated_at = pg_catalog.now()
   WHERE doc_type = v_tipo AND status = 'published'
     AND (effective_to IS NULL OR effective_to > v_desde);

  INSERT INTO public.legal_documents
    (doc_type, version, title, content, content_url, content_hash, status,
     is_material_change, effective_from, published_at, published_by)
  VALUES
    (v_tipo, v_versao, pg_catalog.btrim(p_title),
     nullif(pg_catalog.btrim(coalesce(p_content,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_content_url,'')), ''),
     v_hash, 'published', coalesce(p_is_material_change, false),
     v_desde, pg_catalog.now(), auth.uid())
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('legal_document.published', v_id, 'admin',
    pg_catalog.jsonb_build_object('doc_type', v_tipo, 'version', v_versao,
                                  'content_hash', v_hash));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'legal_document_id', v_id, 'doc_type', v_tipo, 'version', v_versao,
    'content_hash', v_hash, 'effective_from', v_desde);
END;
$$;

-- Os GRANTs originais seguem valendo: CREATE OR REPLACE não os altera.

-- ===========================================================================
-- C2. Vínculo imutável entre o Mestre assinado pela empresa e o publicado
-- ===========================================================================

-- 1. FK explícita para a identidade pública do Mestre.
--
-- NULLABLE de propósito: as linhas SANDBOX e qualquer registro histórico
-- permanecem legíveis e não são reescritos. O vínculo é exigido apenas de
-- registros NOVOS, pela RPC abaixo.

ALTER TABLE public.commercial_master_agreements
  ADD COLUMN IF NOT EXISTS legal_document_id uuid
    REFERENCES public.legal_documents(id);

COMMENT ON COLUMN public.commercial_master_agreements.legal_document_id IS
  'Identidade pública EXATA do Acordo Mestre assinado por esta empresa. Nulo '
  'apenas em linhas históricas anteriores a esta migration.';

CREATE INDEX IF NOT EXISTS cma_legal_document_idx
  ON public.commercial_master_agreements (legal_document_id);

-- 2. Coerência: quando houver vínculo, versão e hash têm de ser os do
--    documento apontado. Sem isto, a FK provaria apenas que ALGUM documento
--    foi apontado, e não que é aquele cuja versão a linha declara.
--
-- NOT VALID: não revalida linhas antigas — elas ficam como estão, e a trava
-- passa a valer para toda inserção ou atualização a partir de agora.

CREATE OR REPLACE FUNCTION public.cma_exigir_coerencia_legal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_doc public.legal_documents%ROWTYPE;
BEGIN
  IF NEW.legal_document_id IS NULL THEN
    RETURN NEW; -- linha histórica, sem vínculo: preservada.
  END IF;

  SELECT * INTO v_doc FROM public.legal_documents WHERE id = NEW.legal_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'legal_document_id inexistente' USING ERRCODE = 'check_violation';
  END IF;
  IF v_doc.doc_type <> 'master_agreement' THEN
    RAISE EXCEPTION 'legal_document_id nao e um master_agreement (doc_type=%)', v_doc.doc_type
      USING ERRCODE = 'check_violation';
  END IF;
  -- Rascunho nunca rege contrato assinado.
  IF v_doc.status NOT IN ('published','archived') THEN
    RAISE EXCEPTION 'master_agreement em status % nao pode reger assinatura', v_doc.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF pg_catalog.btrim(NEW.agreement_version) IS DISTINCT FROM v_doc.version THEN
    RAISE EXCEPTION 'agreement_version (%) diverge da versao publicada (%)',
      NEW.agreement_version, v_doc.version USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.document_hash IS NOT NULL
     AND pg_catalog.btrim(NEW.document_hash) IS DISTINCT FROM v_doc.content_hash THEN
    RAISE EXCEPTION 'document_hash diverge do hash publicado'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Hash ausente é preenchido a partir da fonte: assim a linha nunca fica com
  -- versão vinculada e hash em branco.
  NEW.document_hash := coalesce(nullif(pg_catalog.btrim(coalesce(NEW.document_hash,'')), ''),
                                v_doc.content_hash);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS cma_coerencia_legal ON public.commercial_master_agreements;
CREATE TRIGGER cma_coerencia_legal
  BEFORE INSERT OR UPDATE ON public.commercial_master_agreements
  FOR EACH ROW EXECUTE FUNCTION public.cma_exigir_coerencia_legal();

-- 3. Registro de assinatura passa a exigir a identidade pública.
--
-- A assinatura ganha um parâmetro NOVO ao final, com DEFAULT, então chamadas
-- existentes continuam compilando. O comportamento muda num ponto: um
-- registro NOVO sem Mestre público válido falha fechado, em vez de gravar
-- versão e hash arbitrários.

CREATE OR REPLACE FUNCTION public.admin_register_master_agreement(
  p_company_id        uuid,
  p_agreement_version text,
  p_signed_at         timestamptz,
  p_signatory_name    text,
  p_document_reference text DEFAULT NULL,
  p_document_hash      text DEFAULT NULL,
  p_external_signature_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_atual public.commercial_master_agreements%ROWTYPE;
  v_doc   public.legal_documents%ROWTYPE;
  v_id    uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signed_at');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_partner_companies
                  WHERE id = p_company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_not_active');
  END IF;

  -- C2: a versão assinada tem de corresponder a UM Mestre público concreto.
  -- Publicado OU arquivado: uma empresa pode assinar hoje a versão que regia
  -- quando negociou, e essa versão pode já ter sido sucedida.
  SELECT * INTO v_doc FROM public.legal_documents
   WHERE doc_type = 'master_agreement'
     AND version  = pg_catalog.btrim(p_agreement_version)
     AND status IN ('published','archived');
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'master_agreement_version_not_published',
      'agreement_version', pg_catalog.btrim(p_agreement_version));
  END IF;
  IF pg_catalog.btrim(coalesce(p_document_hash,'')) <> ''
     AND pg_catalog.btrim(p_document_hash) <> v_doc.content_hash THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_hash_mismatch');
  END IF;

  PERFORM 1 FROM public.site_partner_companies WHERE id = p_company_id FOR UPDATE;

  SELECT * INTO v_atual FROM public.commercial_master_agreements
   WHERE company_id = p_company_id AND status = 'signed';

  IF FOUND THEN
    IF v_atual.agreement_version = pg_catalog.btrim(p_agreement_version)
       AND v_atual.signed_at = p_signed_at THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                           'agreement_id', v_atual.id);
    END IF;
    -- A linha anterior vira histórica. Seu vínculo NÃO é alterado: publicar
    -- um Mestre novo não pode reescrever o que a empresa assinou antes.
    UPDATE public.commercial_master_agreements
       SET status = 'superseded', superseded_at = pg_catalog.now()
     WHERE id = v_atual.id;
  END IF;

  BEGIN
    INSERT INTO public.commercial_master_agreements
      (company_id, agreement_version, document_reference, document_hash,
       signed_at, signatory_name, external_signature_ref,
       supersedes_agreement_id, registered_by, legal_document_id)
    VALUES
      (p_company_id, pg_catalog.btrim(p_agreement_version),
       coalesce(nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
                'bdflow:legal_document/' || v_doc.id::text),
       v_doc.content_hash,
       p_signed_at, pg_catalog.btrim(p_signatory_name),
       nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
       v_atual.id, auth.uid(), v_doc.id)
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN check_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
  END;

  PERFORM public.m1_auditar('master_agreement.registered', v_id, 'admin',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'agreement_version', pg_catalog.btrim(p_agreement_version),
                                  'legal_document_id', v_doc.id,
                                  'content_hash', v_doc.content_hash,
                                  'supersedes', v_atual.id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
                                       'agreement_id', v_id,
                                       'legal_document_id', v_doc.id,
                                       'agreement_version', v_doc.version,
                                       'content_hash', v_doc.content_hash);
END;
$$;

-- 4. Leitura do Mestre que rege a intenção de checkout.
--
-- Serve à UI: antes do aceite, o titular precisa ver a versão e o hash do
-- Mestre que rege a SUA empresa — não o que estiver publicado hoje. Devolve
-- `ok:false` com motivo quando o vínculo falta, para a tela falhar fechada
-- em vez de exibir o Mestre corrente como se fosse o aplicável.

CREATE OR REPLACE FUNCTION public.get_governing_master_for_intent(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_company uuid;
  v_agree   public.commercial_master_agreements%ROWTYPE;
  v_doc     public.legal_documents%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  -- A empresa vem da intenção, e só o titular ATIVO daquela empresa lê.
  SELECT i.company_id INTO v_company
    FROM public.commercial_checkout_intents i
   WHERE i.id = p_intent_id;
  IF v_company IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_found');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_company_members m
                  WHERE m.company_id = v_company AND m.auth_user_id = auth.uid()
                    AND m.role = 'partner_owner' AND m.status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = v_company AND status = 'signed';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;
  IF v_agree.legal_document_id IS NULL THEN
    -- Linha histórica, sem vínculo público: não se inventa correspondência.
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_linkage_missing',
      'agreement_version', v_agree.agreement_version);
  END IF;

  SELECT * INTO v_doc FROM public.legal_documents WHERE id = v_agree.legal_document_id;
  IF NOT FOUND OR v_doc.status NOT IN ('published','archived') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_document_unavailable');
  END IF;

  RETURN pg_catalog.jsonb_build_object('ok', true,
    'legal_document_id', v_doc.id,
    'version', v_doc.version,
    'title', v_doc.title,
    'content_hash', v_doc.content_hash,
    'status', v_doc.status,
    'signed_at', v_agree.signed_at);
END;
$$;

ALTER FUNCTION public.get_governing_master_for_intent(uuid) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.get_governing_master_for_intent(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_governing_master_for_intent(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_governing_master_for_intent(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.get_governing_master_for_intent(uuid) IS
  'Versao e hash do Acordo Mestre que rege a empresa desta intencao de '
  'checkout. Falha fechada quando o vinculo publico esta ausente.';
