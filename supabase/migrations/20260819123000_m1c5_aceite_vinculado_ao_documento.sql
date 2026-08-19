-- ===========================================================================
-- M1-C5d — ACEITE VINCULADO AO DOCUMENTO EXATO QUE O USUÁRIO VIU
-- ===========================================================================
-- CORRIDA CORRIGIDA
--   1. a tela carrega privacy_notice A;
--   2. o usuário marca explicitamente A;
--   3. antes da chamada, privacy_notice B passa a ser o vigente;
--   4. o frontend chamava record_legal_acceptance('privacy_notice');
--   5. a função protegida resolve o VIGENTE, isto é, B;
--   6. B ficava registrado como aceito;
--   7. o claim via B aceito e passava.
--
-- O usuário nunca viu nem aceitou B. A janela é curta, mas o efeito é um
-- aceite jurídico que ninguém deu.
--
-- SOLUÇÃO
-- Wrapper fino que recebe também o legal_document_id EXATO cuja caixa foi
-- marcada. Ele continua usando a função protegida como implementação
-- canônica — ela não é modificada nem tem o ACL afrouxado — e impõe a
-- pós-condição: o documento efetivamente persistido tem de ser o esperado.
-- Se divergir, a subtransação é revertida e NADA daquela chamada permanece.
--
-- O único vínculo vindo do cliente é o id. version e content_hash continuam
-- sem valor de autoridade.
-- ===========================================================================

CREATE FUNCTION public.record_bound_legal_acceptance(
  p_doc_type          text,
  p_legal_document_id uuid,
  p_client_evidence   jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_acceptance_id  uuid;
  v_persisted_doc  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF p_doc_type IS NULL OR p_legal_document_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_invalid');
  END IF;

  IF NOT (p_doc_type = ANY (public.m1_doc_types_conta_provisoria())) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_invalid');
  END IF;

  BEGIN
    -- Implementação canônica, inalterada.
    v_acceptance_id := public.record_legal_acceptance(p_doc_type, p_client_evidence);

    SELECT a.legal_document_id INTO v_persisted_doc
      FROM public.legal_acceptances a
     WHERE a.id = v_acceptance_id;

    -- PÓS-CONDIÇÃO: o documento persistido é o que o usuário viu?
    IF v_persisted_doc IS DISTINCT FROM p_legal_document_id THEN
      -- Reverte a subtransação inteira: o aceite do documento errado some.
      RAISE EXCEPTION 'acceptance_stale' USING ERRCODE = 'P0001';
    END IF;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM = 'acceptance_stale' THEN
        RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_stale');
      END IF;
      -- Recusas da própria função protegida (tipo não permitido, sem versão
      -- vigente, evidência inválida) chegam aqui com mensagem própria, que
      -- não é repassada crua ao cliente.
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_failed');
    WHEN OTHERS THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_failed');
  END;

  RETURN pg_catalog.jsonb_build_object('ok', true,
                                       'acceptance_id', v_acceptance_id,
                                       'legal_document_id', v_persisted_doc);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_bound_legal_acceptance(text, uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_bound_legal_acceptance(text, uuid, jsonb) FROM service_role;
GRANT  EXECUTE ON FUNCTION public.record_bound_legal_acceptance(text, uuid, jsonb) TO authenticated;

COMMENT ON FUNCTION public.record_bound_legal_acceptance(text, uuid, jsonb) IS
  'Aceite atado ao legal_document_id exato exibido ao usuario. Usa record_legal_acceptance como implementacao canonica e reverte se o documento persistido divergir do esperado.';
