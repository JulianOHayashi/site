-- ============================================================================
-- P0-1 — IMPOSIÇÃO SERVER-SIDE DO ACORDO MESTRE NA FINALIZAÇÃO
--
-- DEFEITO CORRIGIDO (comprovado em runtime, com duas sessões)
-- Os dois caminhos que criam pedido — a finalização pelo titular e a venda
-- manual administrativa — liam o Acordo Mestre vigente SEM travar a linha:
--
--     SELECT * INTO v_agree FROM public.commercial_master_agreements
--      WHERE company_id = ... AND status = 'signed';
--
-- Em READ COMMITTED isso abre uma janela real. Demonstração executada:
--   t0  sessão A (finalização) lê o Mestre e vê status = 'signed'; guarda PASSA
--   t1  sessão B revoga o Mestre (status = 'superseded') e COMMITA
--   t2  sessão A insere o pedido usando o v_agree capturado em t0 e COMMITA
--
-- Resultado: pedido assinado amarrado a um Acordo Mestre que, no instante do
-- commit, já não estava mais vigente. Nada no esquema impedia isso — a única
-- amarra entre pedido e Mestre é a FK
-- commercial_exclusivity_orders_master_agreement_id_fkey, que garante
-- EXISTÊNCIA e nunca STATUS. Não há CHECK nem trigger de apoio.
--
-- CORREÇÃO
-- A leitura passa a ser `FOR UPDATE`, no mesmo comando que filtra
-- status = 'signed'. Em READ COMMITTED isso fecha a janela nas duas ordens
-- possíveis, e fecha fail-closed:
--
--   - Se a finalização chega primeiro, ela trava a linha. A revogação
--     concorrente BLOQUEIA até o commit da finalização. O pedido nasce contra
--     um Mestre que estava vigente e permaneceu vigente até o commit.
--   - Se a revogação commita primeiro, o FOR UPDATE reavalia a linha após
--     liberar o lock. O filtro status = 'signed' deixa de casar, NOT FOUND
--     dispara e a função devolve 'master_agreement_missing'. Nenhum pedido é
--     criado.
--
-- O índice único parcial cma_vigente_idx — UNIQUE (company_id) WHERE
-- status = 'signed' — garante que a linha travada é a única candidata, de modo
-- que o lock não é ambíguo nem depende de ordenação.
--
-- O QUE NÃO MUDA
-- - Nenhuma regra de elegibilidade nova. Quem podia contratar continua podendo;
--   o que deixa de existir é a janela de corrida.
-- - Linhas históricas com legal_document_id NULL seguem preservadas, exatamente
--   como a trigger cma_coerencia_legal determina. Esta migration NÃO passa a
--   exigir o vínculo canônico: isso é decisão de política, registrada no
--   relatório e deliberadamente não tomada aqui.
-- - Assinatura, permissões, SECURITY DEFINER, search_path, idempotência,
--   auditoria e todo o restante do corpo das duas funções: intocados.
--
-- NOTA SOBRE VERIFICAÇÃO REDUNDANTE DESCARTADA
-- Reconferir aqui doc_type, status e hash do documento legal do Mestre seria
-- teatro: cma_coerencia_legal já impõe isso na escrita do Mestre, e
-- legal_documents_protect torna impossível um documento publicado regredir a
-- rascunho ou ter content_hash alterado. Nenhuma asserção foi escrita para
-- provar o que o esquema já torna inalcançável.
--
-- Sem push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.finalize_commercial_order_from_intent(p_intent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_i     public.commercial_checkout_intents%ROWTYPE;
  v_opp   public.commercial_opportunities%ROWTYPE;
  v_ace   public.legal_acceptances%ROWTYPE;
  v_doc   public.legal_documents%ROWTYPE;
  v_agree public.commercial_master_agreements%ROWTYPE;
  v_comp  public.site_partner_companies%ROWTYPE;
  v_nome  text;
  v_exist uuid;
  v_id    uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_i FROM public.commercial_checkout_intents
   WHERE id = p_intent_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_found');
  END IF;
  IF NOT public.m2_is_company_owner(v_i.company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  -- Idempotência: a mesma intenção já finalizada devolve o mesmo pedido.
  SELECT id INTO v_exist FROM public.commercial_exclusivity_orders
   WHERE checkout_intent_id = v_i.id AND status <> 'cancelled';
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'order_id', v_exist, 'intent_status', v_i.status);
  END IF;

  SELECT * INTO v_comp
    FROM public.site_partner_companies
   WHERE id = v_i.company_id
   FOR UPDATE;

  SELECT id INTO v_exist
    FROM public.commercial_exclusivity_orders
   WHERE exclusivity_id = v_i.exclusivity_id
     AND company_id = v_i.company_id
     AND status <> 'cancelled'
   LIMIT 1;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'company_already_contracted_in_exclusivity',
      'existing_order_id', v_exist);
  END IF;

  IF v_i.status <> 'awaiting_contract' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_awaiting_contract',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
  END IF;

  -- ---- aceite exato: do titular, desta intenção, do contexto e tipo certos
  SELECT a.* INTO v_ace
    FROM public.legal_acceptances a
    JOIN public.legal_documents d ON d.id = a.legal_document_id
   WHERE a.subject_type = 'commercial_checkout_intent'
     AND a.subject_id = v_i.id
     AND a.commercial_checkout_intent_id = v_i.id
     AND a.context = 'commercial_contract'
     AND a.linked_auth_user_id = v_uid
     AND a.revoked_at IS NULL
     AND d.doc_type = 'commercial_order_terms'
     AND d.status = 'published'
     AND d.effective_from <= pg_catalog.now()
     AND (d.effective_to IS NULL OR d.effective_to > pg_catalog.now())
   ORDER BY a.accepted_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'terms_not_accepted');
  END IF;

  SELECT * INTO v_doc FROM public.legal_documents WHERE id = v_ace.legal_document_id;

  -- O aceite tem de ter acontecido DENTRO da reserva viva.
  IF v_ace.accepted_at > v_i.reserved_until THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_outside_reservation');
  END IF;

  -- ---- acordo mestre vigente: obrigatório, e não fabricado aqui
  -- P0-1: FOR UPDATE fecha a janela de corrida contra revogação
  -- concorrente. Ver o cabeçalho desta migration.
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = v_i.company_id AND status = 'signed'
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  -- ---- oportunidade ainda reservada para ESTA intenção
  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = v_i.opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;
  IF v_opp.status <> 'reserved'
     OR v_opp.reserved_until IS NULL
     OR v_opp.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired',
                                         'opportunity_status', v_opp.status);
  END IF;

  -- v_comp já foi carregada com FOR UPDATE acima.

  -- Signatário: identidade canônica do titular ativo, não texto de formulário.
  SELECT m.full_name INTO v_nome FROM public.site_company_members m
   WHERE m.company_id = v_i.company_id AND m.auth_user_id = v_uid
     AND m.role = 'partner_owner' AND m.status = 'active';
  IF v_nome IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     benefit_settlement_mode, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     status, expected_operation_start, registered_by,
     legal_acceptance_id, checkout_intent_id)
  VALUES
    (v_i.exclusivity_id, v_i.opportunity_id, v_i.company_id, v_agree.id, v_i.niche_code,
     v_i.region_id, v_i.nominal_quantity, v_i.pricing_rule_version, v_i.fidelized,
     v_i.currency,
     -- CÓPIA do instantâneo reservado, centavo a centavo.
     v_i.economic_value_cents,
     -- pool_bps e NULO sob a V2 e a intencao nao guarda bps algum: nao ha
     -- ponto-base honesto a gravar, e inventar um seria autoridade falsa.
     NULL::integer,
     v_i.user_pool_cents, v_i.bdflow_ops_investment_cents,
     v_i.benefit_settlement_mode, v_i.cash_user_pool_funding_cents,
     v_i.total_monetary_funding_required_cents,
     v_i.benefit_distribution_policy_version,
     v_doc.version,
     'bdflow:legal_acceptance/' || v_ace.id::text,
     v_doc.content_hash,
     v_ace.accepted_at, v_nome,
     'signed', (pg_catalog.now() + interval '30 days')::date, v_uid,
     v_ace.id, v_i.id)
  RETURNING id INTO v_id;

  -- A oportunidade sai da reserva e entra em pendência de pagamento, o mesmo
  -- estado canônico a que a venda manual sempre levou.
  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL,
         updated_at = pg_catalog.now()
   WHERE id = v_opp.id;

  UPDATE public.commercial_checkout_intents
     SET status = 'awaiting_payment_provider' WHERE id = v_i.id;

  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  SELECT v_comp.cnpj, r.uf, public.commercial_city_key(v_comp.city),
         v_i.niche_code, v_id
    FROM public.commercial_regions r WHERE r.id = v_i.region_id
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.finalized_by_owner', v_id, 'owner',
    pg_catalog.jsonb_build_object('intent_id', v_i.id,
                                  'legal_acceptance_id', v_ace.id,
                                  'master_agreement_id', v_agree.id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'order_id', v_id, 'intent_status', 'awaiting_payment_provider',
    'opportunity_status', 'payment_pending',
    'legal_acceptance_id', v_ace.id, 'document_version', v_doc.version,
    'content_hash', v_doc.content_hash,
    'economic_value_cents', v_i.economic_value_cents,
    'user_pool_cents', v_i.user_pool_cents,
    'bdflow_ops_investment_cents', v_i.bdflow_ops_investment_cents);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_register_manual_commercial_order(p_opportunity_id uuid, p_company_id uuid, p_order_version text, p_signed_at timestamp with time zone, p_signatory_name text, p_expected_operation_start date, p_benefit_settlement_mode text, p_document_reference text DEFAULT NULL::text, p_document_hash text DEFAULT NULL::text, p_external_signature_ref text DEFAULT NULL::text, p_exclusivity_period_days integer DEFAULT 28)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_opp      public.commercial_opportunities%ROWTYPE;
  v_excl     public.commercial_exclusivities%ROWTYPE;
  v_company  public.site_partner_companies%ROWTYPE;
  v_agree    public.commercial_master_agreements%ROWTYPE;
  v_region   public.commercial_regions%ROWTYPE;
  v_existing public.commercial_exclusivity_orders%ROWTYPE;
  v_city     jsonb;
  v_city_key text;
  v_cnpj     text;
  v_fidel    boolean;
  v_pricing  jsonb;
  v_versao   integer;
  -- Valores COMO GRAVADOS, lidos de volta após o trigger da autoridade.
  v_eco_grav    bigint;
  v_pool_grav   bigint;
  v_bdflow_grav bigint;
  v_cash_grav   bigint;
  v_total_grav  bigint;
  v_econ_versao text;
  v_pool     bigint;
  v_bdflow   bigint;
  v_cash     bigint;
  v_id       uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- A ÚNICA escolha comercial aceita de fora. Preço, fidelidade, versão da
  -- tabela e forma de pagamento continuam derivados aqui.
  IF p_benefit_settlement_mode IS NULL
     OR p_benefit_settlement_mode NOT IN ('direct_benefits','cash') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_settlement_mode');
  END IF;

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signature_date');
  END IF;
  IF p_document_reference IS NULL AND p_document_hash IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_evidence_required');
  END IF;

  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = p_opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  SELECT * INTO v_existing FROM public.commercial_exclusivity_orders
   WHERE opportunity_id = p_opportunity_id AND status <> 'cancelled';
  IF FOUND THEN
    IF v_existing.company_id = p_company_id THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                           'order_id', v_existing.id);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_taken');
  END IF;

  SELECT * INTO v_excl FROM public.commercial_exclusivities
   WHERE id = v_opp.exclusivity_id;
  IF v_excl.status NOT IN ('forming','formed','start_scheduled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exclusivity_closed');
  END IF;

  SELECT * INTO v_company FROM public.site_partner_companies
   WHERE id = p_company_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_invalid');
  END IF;

  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.exclusivity_id = v_opp.exclusivity_id
                AND o.company_id = p_company_id AND o.status <> 'cancelled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_already_in_exclusivity');
  END IF;

  -- P0-1: FOR UPDATE fecha a janela de corrida contra revogação
  -- concorrente. Ver o cabeçalho desta migration.
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = p_company_id AND status = 'signed'
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  v_city := public.m2_resolve_company_fidelity_city(p_company_id, v_region.id);
  IF (v_city->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_city->>'reason');
  END IF;
  v_city_key := v_city->>'city_key';
  v_cnpj     := public.somente_digitos(v_company.cnpj);

  v_fidel := public.is_fidelized_context(
      v_cnpj, v_region.uf, v_company.city, v_opp.niche_code);

  v_pricing := public.calculate_niche_contract_pricing(v_opp.niche_code, v_fidel);
  IF (v_pricing->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_pricing->>'reason');
  END IF;

  v_versao := (v_pricing->>'pricing_rule_version')::int;
  v_pool   := (v_pricing->>'contractual_pool_cents')::bigint;
  v_bdflow := (v_pricing->>'bdflow_due_cents')::bigint;
  v_cash   := CASE WHEN p_benefit_settlement_mode = 'cash' THEN v_pool ELSE 0 END;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     benefit_settlement_mode, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     external_signature_ref, status,
     expected_operation_start, exclusivity_period_days, registered_by)
  VALUES
    (v_opp.exclusivity_id, v_opp.id, p_company_id, v_agree.id, v_opp.niche_code,
     v_region.id, v_opp.contracted_quantity,
     v_versao, v_fidel, 'BRL',
     (v_pricing->>'economic_value_cents')::bigint,
     -- NULL sob a V2: não existe ponto-base honesto, e inventar um seria
     -- gravar autoridade falsa só para satisfazer um formato antigo.
     CASE WHEN v_versao >= 2 THEN NULL ELSE (v_pricing->>'pool_bps')::int END,
     v_pool, v_bdflow,
     p_benefit_settlement_mode, v_cash, v_bdflow + v_cash,
     CASE WHEN v_versao >= 2 THEN 2 ELSE NULL END,
     pg_catalog.btrim(p_order_version),
     nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_document_hash,'')), ''),
     p_signed_at, pg_catalog.btrim(p_signatory_name),
     nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
     'signed',
     p_expected_operation_start, p_exclusivity_period_days, auth.uid())
  -- Lê de volta o que a AUTORIDADE gravou, não o que esta função supôs antes
  -- do trigger. Sob V1/V2 estes valores são idênticos aos pré-calculados.
  RETURNING id,
            economic_value_cents,
            contractual_pool_cents,
            bdflow_due_cents,
            cash_user_pool_funding_cents,
            total_monetary_funding_required_cents,
            contract_economics_version
       INTO v_id, v_eco_grav, v_pool_grav, v_bdflow_grav, v_cash_grav,
            v_total_grav, v_econ_versao;

  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL
   WHERE id = v_opp.id;

  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  VALUES (v_cnpj, v_region.uf, v_city_key, v_opp.niche_code, v_id)
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.manually_registered', v_id, 'admin',
    pg_catalog.jsonb_build_object(
      'pricing_rule_version', v_versao,
      'benefit_settlement_mode', p_benefit_settlement_mode,
      'payment_method', v_pricing->>'payment_method',
      'economic_value_cents', v_eco_grav,
      'contract_economics_version', v_econ_versao,
      'total_monetary_funding_required_cents', v_total_grav),
    NULL,
    pg_catalog.jsonb_build_object('opportunity_id', p_opportunity_id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'order_id', v_id,
    'pricing_rule_version', v_versao,
    'fidelized', v_fidel,
    'payment_method', v_pricing->>'payment_method',
    'benefit_settlement_mode', p_benefit_settlement_mode,
    'economic_value_cents', v_eco_grav,
    'user_pool_cents', v_pool_grav,
    'bdflow_ops_investment_cents', v_bdflow_grav,
    'cash_user_pool_funding_cents', v_cash_grav,
    'total_monetary_funding_required_cents', v_total_grav,
    -- NULL em pedido V1/V2: só a v1.4 tem rótulo legal de economia.
    'contract_economics_version', v_econ_versao);
END;
$function$;
