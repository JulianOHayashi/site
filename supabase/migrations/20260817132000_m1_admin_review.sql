-- ===========================================================================
-- M1 — ADMIN FOUNDATION: ANÁLISE DA APLICAÇÃO
-- ===========================================================================
-- Ações administrativas sensíveis são autorizadas SERVER-SIDE por
-- public.is_site_admin(). Esconder botão no frontend não é controle.
--
-- Empresa e autoridade do representante são analisadas SEPARADAMENTE:
-- rejeitar o representante não rejeita a empresa, e é possível indicar
-- outro representante sem criar nova aplicação empresarial.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Helper interno: exige administrador
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.m1_exigir_admin()
RETURNS void
LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_site_admin() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_exigir_admin() FROM PUBLIC;

-- ===========================================================================
-- 1. admin_list_partner_applications
-- ===========================================================================
CREATE FUNCTION public.admin_list_partner_applications(
  p_status text DEFAULT NULL,
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_itens jsonb;
BEGIN
  PERFORM public.m1_exigir_admin();

  SELECT coalesce(pg_catalog.jsonb_agg(x ORDER BY x->>'created_at' DESC), '[]'::jsonb)
    INTO v_itens
    FROM (
      SELECT pg_catalog.jsonb_build_object(
               'application_id', a.id,
               'cnpj', a.cnpj,
               'legal_name', a.legal_name,
               'city', a.city,
               'uf', a.uf,
               'status', a.status,
               'company_review_status', a.company_review_status,
               'authority_review_status', a.authority_review_status,
               'created_at', a.created_at,
               'representative', (
                  SELECT pg_catalog.jsonb_build_object(
                           'id', r.id, 'full_name', r.full_name,
                           'authority_status', r.authority_status)
                    FROM public.partner_application_representatives r
                   WHERE r.application_id = a.id AND r.is_current)
             ) AS x
        FROM public.partner_applications a
       WHERE p_status IS NULL OR a.status = p_status
       ORDER BY a.created_at DESC
       LIMIT least(coalesce(p_limit, 50), 200)
      OFFSET greatest(coalesce(p_offset, 0), 0)
    ) s;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'items', v_itens);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_partner_applications(text, integer, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_list_partner_applications(text, integer, integer) TO authenticated, service_role;

-- ===========================================================================
-- 2. admin_review_partner_company — análise DA EMPRESA
-- ===========================================================================
CREATE FUNCTION public.admin_review_partner_company(
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
  v_anterior text;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_decision NOT IN ('approved','rejected','changes_requested') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  SELECT company_review_status INTO v_anterior
    FROM public.partner_applications
   WHERE id = p_application_id
     AND status IN ('under_review','changes_requested')
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  UPDATE public.partner_applications
     SET company_review_status = p_decision
   WHERE id = p_application_id;

  PERFORM public.m1_auditar('partner_application.company_reviewed', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('company_review_status', p_decision),
                            pg_catalog.jsonb_build_object('company_review_status', v_anterior),
                            pg_catalog.jsonb_build_object('reason', p_reason));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'company_review_status', p_decision);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_review_partner_company(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_review_partner_company(uuid, text, text) TO authenticated, service_role;

-- ===========================================================================
-- 3. admin_review_partner_authority — análise DA AUTORIDADE, separada
-- ===========================================================================
CREATE FUNCTION public.admin_review_partner_authority(
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
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_decision NOT IN ('approved','rejected','changes_requested') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  SELECT r.id, r.authority_status INTO v_rep_id, v_anterior
    FROM public.partner_application_representatives r
    JOIN public.partner_applications a ON a.id = r.application_id
   WHERE r.application_id = p_application_id
     AND r.is_current
     AND a.status IN ('under_review','changes_requested')
   FOR UPDATE OF r;

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

REVOKE EXECUTE ON FUNCTION public.admin_review_partner_authority(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_review_partner_authority(uuid, text, text) TO authenticated, service_role;

-- ===========================================================================
-- 4. admin_replace_partner_representative
-- ===========================================================================
-- Trocar o representante NÃO cria nova aplicação empresarial. O anterior
-- vira histórico; a análise da empresa permanece como está.
CREATE FUNCTION public.admin_replace_partner_representative(
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
BEGIN
  PERFORM public.m1_exigir_admin();

  IF NOT EXISTS (SELECT 1 FROM public.partner_applications
                  WHERE id = p_application_id
                    AND status IN ('under_review','changes_requested')) THEN
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
      RAISE EXCEPTION 'invalid_representative' USING ERRCODE = 'check_violation';
  END;

  -- A autoridade volta a ser 'pending': é outra pessoa a ser analisada.
  UPDATE public.partner_applications
     SET authority_review_status = 'pending'
   WHERE id = p_application_id;

  PERFORM public.m1_auditar('partner_application.representative_replaced', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('representative_id', v_novo_id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'representative_id', v_novo_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_replace_partner_representative(uuid, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_replace_partner_representative(uuid, jsonb) TO authenticated, service_role;

-- ===========================================================================
-- 5. admin_request_partner_correction
-- ===========================================================================
CREATE FUNCTION public.admin_request_partner_correction(
  p_application_id uuid,
  p_scope          text,
  p_message        text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_id    uuid;
  v_email text;
BEGIN
  PERFORM public.m1_exigir_admin();

  SELECT contact_email INTO v_email
    FROM public.partner_applications
   WHERE id = p_application_id
     AND status IN ('under_review','changes_requested')
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  BEGIN
    INSERT INTO public.partner_application_corrections
      (application_id, scope, message, requested_by)
    VALUES (p_application_id, p_scope, pg_catalog.btrim(p_message), auth.uid())
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_correction');
  END;

  UPDATE public.partner_applications
     SET status = 'changes_requested'
   WHERE id = p_application_id;

  PERFORM public.m1_enfileirar_email(
    v_email, 'partner_application_correction_requested',
    pg_catalog.jsonb_build_object('application_id', p_application_id, 'scope', p_scope),
    p_application_id, 'pac:' || v_id::text);

  PERFORM public.m1_auditar('partner_application.correction_requested', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('correction_id', v_id, 'scope', p_scope));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'correction_id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_request_partner_correction(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_request_partner_correction(uuid, text, text) TO authenticated, service_role;

-- ===========================================================================
-- 6. admin_decide_partner_application — decisão terminal
-- ===========================================================================
-- Aprovar exige que AMBAS as análises estejam aprovadas. Rejeitar exige
-- motivo. A aprovação NÃO promove ninguém a partner_owner: promoção é M2.
CREATE FUNCTION public.admin_decide_partner_application(
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
  v_app public.partner_applications%ROWTYPE;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_decision NOT IN ('approved','rejected') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  IF p_decision = 'rejected'
     AND (p_reason IS NULL OR pg_catalog.length(pg_catalog.btrim(p_reason)) < 3) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reason_required');
  END IF;

  SELECT * INTO v_app
    FROM public.partner_applications
   WHERE id = p_application_id
     AND status IN ('under_review','changes_requested')
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_reviewable');
  END IF;

  IF p_decision = 'approved'
     AND (v_app.company_review_status <> 'approved' OR v_app.authority_review_status <> 'approved') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reviews_incomplete');
  END IF;

  UPDATE public.partner_applications
     SET status          = p_decision,
         decided_at      = pg_catalog.now(),
         decided_by      = auth.uid(),
         decision_reason = nullif(pg_catalog.btrim(coalesce(p_reason,'')), '')
   WHERE id = p_application_id;

  PERFORM public.m1_enfileirar_email(
    v_app.contact_email, 'partner_application_decided',
    pg_catalog.jsonb_build_object('application_id', p_application_id, 'decision', p_decision),
    p_application_id, 'pad:' || p_application_id::text || ':' || p_decision);

  PERFORM public.m1_auditar('partner_application.decided', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('status', p_decision),
                            pg_catalog.jsonb_build_object('status', v_app.status),
                            pg_catalog.jsonb_build_object('reason', p_reason));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', p_decision);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_decide_partner_application(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_decide_partner_application(uuid, text, text) TO authenticated, service_role;

-- ===========================================================================
-- 7. admin_open_partner_reconsideration — 1 vez, 10 dias
-- ===========================================================================
-- Preferencialmente por administrador diferente do que decidiu. A regra é
-- registrada e auditada; o bloqueio duro fica para o bloco jurídico.
CREATE FUNCTION public.admin_open_partner_reconsideration(p_application_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_app      public.partner_applications%ROWTYPE;
  v_mesmo    boolean;
BEGIN
  PERFORM public.m1_exigir_admin();

  SELECT * INTO v_app
    FROM public.partner_applications
   WHERE id = p_application_id AND status = 'rejected'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_rejected');
  END IF;

  IF v_app.reconsideration_count >= 1 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_reconsidered');
  END IF;

  IF v_app.decided_at + interval '10 days' < pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'deadline_expired');
  END IF;

  -- Reabrir devolve a aplicacao a um estado NAO TERMINAL. Se, no intervalo,
  -- o mesmo CNPJ ja iniciou outra solicitacao viva, a reabertura violaria a
  -- unicidade parcial. Recusamos com motivo explicito em vez de deixar a
  -- constraint estourar.
  IF EXISTS (
    SELECT 1 FROM public.partner_applications o
     WHERE o.cnpj = v_app.cnpj
       AND o.id <> v_app.id
       AND o.status IN ('pending_email_verification','under_review','changes_requested')
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'cnpj_has_active_application');
  END IF;

  v_mesmo := (v_app.decided_by IS NOT DISTINCT FROM auth.uid());

  UPDATE public.partner_applications
     SET status                   = 'under_review',
         decided_at               = NULL,
         decided_by               = NULL,
         decision_reason          = NULL,
         reconsideration_count    = 1,
         reconsideration_deadline = pg_catalog.now() + interval '10 days',
         reconsidered_by          = auth.uid()
   WHERE id = p_application_id;

  PERFORM public.m1_auditar('partner_application.reconsideration_opened', p_application_id, 'admin',
                            pg_catalog.jsonb_build_object('status','under_review'),
                            pg_catalog.jsonb_build_object('status','rejected'),
                            pg_catalog.jsonb_build_object('mesmo_admin_da_decisao', v_mesmo));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'under_review',
                                       'mesmo_admin_da_decisao', v_mesmo);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_open_partner_reconsideration(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_open_partner_reconsideration(uuid) TO authenticated, service_role;

-- ===========================================================================
-- 8. admin_review_partner_document
-- ===========================================================================
CREATE FUNCTION public.admin_review_partner_document(
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
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_decision NOT IN ('accepted','rejected') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  SELECT application_id INTO v_app_id
    FROM public.partner_application_documents
   WHERE id = p_document_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
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
