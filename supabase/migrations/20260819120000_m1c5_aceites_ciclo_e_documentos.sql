-- ===========================================================================
-- M1-C5 — CORREÇÕES DA AUDITORIA INDEPENDENTE (B4, B2, B5)
-- ===========================================================================
-- Migration corretiva posterior. Não reescreve nada aceito, não toca a
-- baseline, não reabilita a RPC legada.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- B4 — O ACEITE PRECISA DE UM ATO EXPLÍCITO DO USUÁRIO
-- ---------------------------------------------------------------------------
-- DEFEITO CORRIGIDO: create_partner_application chamava o registro de aceites
-- INCONDICIONALMENTE. O checkbox vivia apenas no estado do React e não
-- chegava ao servidor. Uma chamada anon direta, sem ato de aceite algum,
-- produzia registros afirmativos de aceite jurídico — fabricação de
-- consentimento.
--
-- DESENHO NOVO
-- O cliente envia SOMENTE os identificadores dos documentos que o usuário
-- aceitou explicitamente:
--     "acceptances": [ { "legal_document_id": "<uuid>" }, ... ]
-- Versão e hash vindos do cliente NÃO são autoridade e são ignorados. O
-- servidor resolve por conta própria o documento vigente de cada tipo
-- obrigatório, exige correspondência exata, e persiste valores derivados do
-- banco. Aceite de documento antigo NÃO é convertido em aceite do atual.

CREATE FUNCTION public.m1_resolver_aceites(p_acceptances jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_ids      uuid[];
  v_tipo     text;
  v_doc      public.legal_documents%ROWTYPE;
  v_docs     jsonb := '[]'::jsonb;
  v_item     jsonb;
  v_id       uuid;
  v_exigidos text[] := public.m1_doc_types_solicitacao();
BEGIN
  IF p_acceptances IS NULL OR pg_catalog.jsonb_typeof(p_acceptances) <> 'array' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_required');
  END IF;

  -- Extrai os ids, recusando elementos malformados.
  v_ids := ARRAY[]::uuid[];
  FOR v_item IN SELECT * FROM pg_catalog.jsonb_array_elements(p_acceptances) LOOP
    IF pg_catalog.jsonb_typeof(v_item) <> 'object' OR (v_item->>'legal_document_id') IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_invalid');
    END IF;
    BEGIN
      v_id := (v_item->>'legal_document_id')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_invalid');
    END;
    IF v_id = ANY (v_ids) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_duplicate');
    END IF;
    v_ids := pg_catalog.array_append(v_ids, v_id);
  END LOOP;

  -- Conjunto EXATO: nem faltando, nem sobrando.
  IF pg_catalog.array_length(v_ids, 1) IS DISTINCT FROM pg_catalog.array_length(v_exigidos, 1) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason',
      CASE WHEN coalesce(pg_catalog.array_length(v_ids,1),0) < pg_catalog.array_length(v_exigidos,1)
           THEN 'acceptance_required' ELSE 'acceptance_unexpected' END);
  END IF;

  -- Para cada tipo obrigatório, o servidor resolve o vigente e exige que o
  -- id enviado seja exatamente esse.
  FOREACH v_tipo IN ARRAY v_exigidos LOOP
    SELECT * INTO v_doc FROM public.current_legal_document(v_tipo);

    IF v_doc.id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'legal_document_unavailable',
                                           'doc_type', v_tipo);
    END IF;

    IF NOT (v_doc.id = ANY (v_ids)) THEN
      -- O id enviado não é o vigente: pode ser versão antiga exibida antes de
      -- uma republicação, documento de outro tipo, ou id inexistente. Em
      -- todos os casos a UI precisa recarregar os termos.
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_stale',
                                           'doc_type', v_tipo);
    END IF;

    -- Valores DERIVADOS DO BANCO. Nada do cliente entra aqui.
    v_docs := v_docs || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'legal_document_id', v_doc.id,
      'doc_type',          v_doc.doc_type,
      'version',           v_doc.version,
      'content_hash',      v_doc.content_hash));
  END LOOP;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'docs', v_docs);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_resolver_aceites(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_resolver_aceites(jsonb) FROM service_role;

COMMENT ON FUNCTION public.m1_resolver_aceites(jsonb) IS
  'Valida os ids de documentos aceitos contra os vigentes resolvidos pelo servidor. Versao e hash do cliente nao sao autoridade.';

-- Persiste os aceites a partir dos documentos JÁ RESOLVIDOS pelo servidor.
CREATE FUNCTION public.m1_persistir_aceites(
  p_application_id uuid,
  p_docs           jsonb,
  p_evidence       jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_doc jsonb;
  v_n   integer := 0;
BEGIN
  FOR v_doc IN SELECT * FROM pg_catalog.jsonb_array_elements(p_docs) LOOP
    INSERT INTO public.legal_acceptances
      (subject_type, subject_id, partner_application_id, legal_document_id,
       context, origin, evidence)
    VALUES
      ('partner_application', p_application_id, p_application_id,
       (v_doc->>'legal_document_id')::uuid,
       'partner_application', 'server',
       p_evidence || pg_catalog.jsonb_build_object(
         'doc_type',         v_doc->>'doc_type',
         'doc_version',      v_doc->>'version',
         'doc_content_hash', v_doc->>'content_hash',
         'acceptance_mode',  'explicit_user_action'));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_persistir_aceites(uuid, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_persistir_aceites(uuid, jsonb, jsonb) FROM service_role;

-- A função antiga, que registrava sem ato explícito, deixa de existir.
DROP FUNCTION IF EXISTS public.m1_registrar_aceites_preauth(uuid, jsonb);

-- ---------------------------------------------------------------------------
-- B2 — APLICAÇÃO NÃO VERIFICADA NÃO PODE TRAVAR O CNPJ PARA SEMPRE
-- ---------------------------------------------------------------------------
-- DEFEITO CORRIGIDO: a coerência anterior era uma equivalência estrita, o que
-- tornava 'withdrawn' impossível antes da verificação de e-mail. Com o índice
-- parcial incluindo pending_email_verification, um e-mail digitado errado
-- travava o CNPJ indefinidamente, sem caminho de saída.
--
-- A correção NÃO falsifica email_verified_at: o estado terminal 'withdrawn'
-- passa a ser estruturalmente possível com email_verified_at NULL.

ALTER TABLE public.partner_applications
  DROP CONSTRAINT partner_applications_email_verificado_coerente;

ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_email_verificado_coerente
    CHECK (
      CASE status
        -- Antes de confirmar, nunca há carimbo.
        WHEN 'pending_email_verification' THEN email_verified_at IS NULL
        -- Abandono pode ocorrer antes OU depois da confirmação.
        WHEN 'withdrawn' THEN true
        -- Todos os demais estados exigem e-mail confirmado.
        ELSE email_verified_at IS NOT NULL
      END
    );

-- Motivo do abandono, para auditoria legível.
ALTER TABLE public.partner_applications
  ADD COLUMN withdrawn_at     timestamptz,
  ADD COLUMN withdrawn_by     uuid,
  ADD COLUMN withdrawn_reason text;

ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_withdrawn_coerente
    CHECK ((status = 'withdrawn') = (withdrawn_at IS NOT NULL)),
  ADD CONSTRAINT partner_applications_withdrawn_reason
    CHECK (withdrawn_reason IS NULL OR length(btrim(withdrawn_reason)) BETWEEN 3 AND 2000);

-- Liberação administrativa: única via para uma aplicação não verificada e
-- inalcançável. Exige administrador, motivo e trava de linha; é auditada; e
-- não existe caminho público, de modo que conhecer o CNPJ alheio não permite
-- liberar a solicitação de outra empresa.
CREATE FUNCTION public.admin_withdraw_partner_application(
  p_application_id uuid,
  p_reason         text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app public.partner_applications%ROWTYPE;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_reason IS NULL OR pg_catalog.length(pg_catalog.btrim(p_reason)) < 3 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reason_required');
  END IF;

  SELECT * INTO v_app
    FROM public.partner_applications
   WHERE id = p_application_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF v_app.status IN ('approved','rejected','withdrawn') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_terminal');
  END IF;

  UPDATE public.partner_applications
     SET status           = 'withdrawn',
         withdrawn_at     = pg_catalog.now(),
         withdrawn_by     = auth.uid(),
         withdrawn_reason = pg_catalog.btrim(p_reason)
   WHERE id = p_application_id;

  -- Tokens vivos morrem junto: nada sobra utilizável.
  UPDATE public.partner_application_tokens
     SET invalidated_at = pg_catalog.now()
   WHERE application_id = p_application_id
     AND consumed_at IS NULL AND invalidated_at IS NULL;

  PERFORM public.m1_auditar('partner_application.withdrawn', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('status','withdrawn'),
                            pg_catalog.jsonb_build_object('status', v_app.status),
                            pg_catalog.jsonb_build_object('reason', pg_catalog.btrim(p_reason)));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'withdrawn');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_withdraw_partner_application(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_withdraw_partner_application(uuid, text) TO authenticated, service_role;

-- Desistência pelo próprio titular: só depois do claim, quando a posse da
-- solicitação está efetivamente provada por auth.uid().
CREATE FUNCTION public.withdraw_my_partner_application(p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app public.partner_applications%ROWTYPE;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_app
    FROM public.partner_applications
   WHERE account_user_id = v_uid
     AND status IN ('under_review','changes_requested')
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  UPDATE public.partner_applications
     SET status           = 'withdrawn',
         withdrawn_at     = pg_catalog.now(),
         withdrawn_by     = v_uid,
         withdrawn_reason = nullif(pg_catalog.btrim(coalesce(p_reason,'')), '')
   WHERE id = v_app.id;

  UPDATE public.partner_application_tokens
     SET invalidated_at = pg_catalog.now()
   WHERE application_id = v_app.id
     AND consumed_at IS NULL AND invalidated_at IS NULL;

  PERFORM public.m1_auditar('partner_application.withdrawn', v_app.id, 'applicant',
                            pg_catalog.jsonb_build_object('status','withdrawn'),
                            pg_catalog.jsonb_build_object('status', v_app.status));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'withdrawn');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.withdraw_my_partner_application(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.withdraw_my_partner_application(text) TO authenticated, service_role;
