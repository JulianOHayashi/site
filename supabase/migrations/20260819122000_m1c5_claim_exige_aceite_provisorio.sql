-- ===========================================================================
-- M1-C5c — O CLAIM VERIFICA (NÃO FABRICA) O ACEITE DA CONTA PROVISÓRIA
-- ===========================================================================
-- Distinção que o desenho anterior não fazia:
--
--   CONTA SUPABASE AUTH CRIADA  ≠  CONTA PROVISÓRIA BDFLOW ATIVADA
--
-- A criação da conta Auth não implica aceite de nada. Antes de a solicitação
-- ganhar titular e entrar em análise, o usuário autenticado precisa ter
-- aceitado explicitamente os documentos da etapa de conta provisória.
--
-- CONTRATO DA FUNÇÃO PROTEGIDA (inspecionado, não alterado)
--   record_legal_acceptance(p_doc_type text, p_declared_data jsonb)
--     * exige auth.uid();
--     * aceita SOMENTE 'privacy_notice' e 'provisional_account_terms';
--     * resolve o documento vigente por conta própria;
--     * grava subject_type='auth_user', subject_id=auth.uid(),
--       linked_auth_user_id e auth_user_id = auth.uid();
--     * context fixo 'provisional_account';
--     * persiste doc_type, version e content_hash derivados do banco;
--     * é idempotente pelo índice parcial uq_legal_acceptances_ativo.
--
-- Esse contrato atende exatamente ao que precisamos. O claim apenas VERIFICA
-- o resultado do ato explícito do usuário; ele NUNCA registra aceite.
-- ===========================================================================

CREATE FUNCTION public.m1_doc_types_conta_provisoria()
RETURNS text[]
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT ARRAY['privacy_notice','provisional_account_terms'];
$$;

REVOKE EXECUTE ON FUNCTION public.m1_doc_types_conta_provisoria() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_doc_types_conta_provisoria() FROM service_role;

-- Verificação: existe aceite ATIVO do usuário para o documento VIGENTE de
-- cada tipo exigido? Aceite de versão anterior NÃO conta e NÃO é promovido.
CREATE FUNCTION public.m1_verificar_aceites_conta(p_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tipo text;
  v_doc  public.legal_documents%ROWTYPE;
  v_ok   boolean;
BEGIN
  IF p_user IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  FOREACH v_tipo IN ARRAY public.m1_doc_types_conta_provisoria() LOOP
    SELECT * INTO v_doc FROM public.current_legal_document(v_tipo);
    IF v_doc.id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
               'reason', 'legal_document_unavailable', 'doc_type', v_tipo);
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.legal_acceptances a
       WHERE a.subject_type      = 'auth_user'
         AND a.subject_id        = p_user
         AND a.legal_document_id = v_doc.id
         AND a.context           = 'provisional_account'
         AND a.revoked_at IS NULL
    ) INTO v_ok;

    IF NOT v_ok THEN
      -- Cobre os três casos: nenhum aceite, aceite parcial, e aceite de uma
      -- versão que deixou de ser a vigente.
      RETURN pg_catalog.jsonb_build_object('ok', false,
               'reason', 'provisional_terms_required', 'doc_type', v_tipo);
    END IF;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_verificar_aceites_conta(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_verificar_aceites_conta(uuid) FROM service_role;

-- Consulta de apoio para a UI saber o que ainda falta aceitar.
CREATE FUNCTION public.get_provisional_account_terms()
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tipo  text;
  v_doc   public.legal_documents%ROWTYPE;
  v_uid   uuid := auth.uid();
  v_itens jsonb := '[]'::jsonb;
  v_ac    boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  FOREACH v_tipo IN ARRAY public.m1_doc_types_conta_provisoria() LOOP
    SELECT * INTO v_doc FROM public.current_legal_document(v_tipo);
    IF v_doc.id IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'legal_document_unavailable');
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.legal_acceptances a
       WHERE a.subject_type='auth_user' AND a.subject_id=v_uid
         AND a.legal_document_id=v_doc.id AND a.context='provisional_account'
         AND a.revoked_at IS NULL) INTO v_ac;

    v_itens := v_itens || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'legal_document_id', v_doc.id,
      'doc_type',          v_doc.doc_type,
      'version',           v_doc.version,
      'title',             v_doc.title,
      'content',           v_doc.content,
      'content_url',       v_doc.content_url,
      'already_accepted',  v_ac));
  END LOOP;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'documents', v_itens);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_provisional_account_terms() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_provisional_account_terms() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- claim: exige o aceite verificado
-- ---------------------------------------------------------------------------
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
  v_legal      jsonb;
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

  -- Identidade: mesma caixa postal verificada. Token NÃO é consumido aqui.
  SELECT pg_catalog.lower(pg_catalog.btrim(u.email)) INTO v_email_auth
    FROM auth.users u WHERE u.id = v_uid;

  IF v_email_auth IS DISTINCT FROM v_app.contact_email THEN
    PERFORM public.m1_auditar('partner_application.claim_email_mismatch', v_app.id, 'applicant',
                              NULL, NULL, pg_catalog.jsonb_build_object('motivo','email_mismatch'));
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'email_mismatch');
  END IF;

  -- ETAPA JURÍDICA DA CONTA PROVISÓRIA. Apenas verificação: o aceite tem de
  -- ter sido criado por ato explícito do usuário via record_legal_acceptance.
  -- O token NÃO é consumido quando falta aceite, para que o titular legítimo
  -- possa aceitar e voltar com o mesmo link.
  v_legal := public.m1_verificar_aceites_conta(v_uid);
  IF (v_legal->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
             'reason', v_legal->>'reason', 'doc_type', v_legal->>'doc_type');
  END IF;

  UPDATE public.partner_application_tokens SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;

  UPDATE public.partner_applications
     SET account_user_id   = v_uid,
         account_linked_at = pg_catalog.now(),
         account_kind      = 'provisional',
         status            = 'under_review'
   WHERE id = v_app.id;

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

REVOKE EXECUTE ON FUNCTION public.claim_partner_application_account(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.claim_partner_application_account(text) TO authenticated, service_role;
