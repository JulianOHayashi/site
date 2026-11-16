-- ===========================================================================
-- ROLLBACK da R4.1 (20261113200000) -> estado exato da R4 (20261113180000).
-- Recusado se já existir aprovação de lançamento, procedimento de QA ou
-- registro de ativação (dados que só existem com a R4.1). As 5 funções são
-- restauradas com o texto exato da R4 (pg_get_functiondef do banco R4).
-- ===========================================================================
BEGIN;
DO $guarda$
BEGIN
  IF EXISTS (SELECT 1 FROM public.commercial_pricing_activation_approvals)
     OR EXISTS (SELECT 1 FROM public.commercial_qa_operational_procedures)
     OR EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log)
     OR (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared' THEN
    RAISE EXCEPTION 'rollback_r41_recusado: ja ha aprovacao de lancamento, procedimento de QA ou ativacao registrados';
  END IF;
END $guarda$;

CREATE OR REPLACE FUNCTION public.commercial_activation_guard_fingerprint()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT pg_catalog.jsonb_build_object(
    'functions', (
      SELECT pg_catalog.jsonb_object_agg(p.oid::regprocedure::text,
               pg_catalog.md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text
                              || '|' || coalesce(pg_catalog.array_to_string(p.proconfig, ','), '')))
        FROM pg_catalog.pg_proc p
       WHERE p.pronamespace = 'public'::regnamespace
         AND p.proname = ANY (ARRAY[
           'admin_activate_pricing_rule', 'commercial_pricing_activation_preflight',
           'commercial_pricing_rules_protect', 'commercial_activation_called_by_procedure',
           'commercial_activation_guard_fingerprint', 'commercial_pricing_activation_log_guard',
           'commercial_pricing_activation_log_protect', 'commercial_settlement_terms_protect',
           'cci_liquidar_modalidade_v15', 'ceo_liquidar_modalidade_v15', 'ceo_liquidacao_v15_imutavel',
           'ceo_pagamento_confere_snapshot', 'cp_valor_confere_pedido',
           'ceo_revalidar_reutilizacao_bandeiras', 'commercial_flag_set_lock_for_inspection',
           'cci_portao_autoatendimento', 'admin_confirm_manual_bdflow_payment',
           'commercial_build_instrument_snapshot', 'commercial_order_settlement_check',
           'commercial_instrument_template_approvals_protect'])),
    'triggers', (
      SELECT pg_catalog.jsonb_object_agg(t.tgrelid::regclass::text || '.' || t.tgname, t.tgenabled::text)
        FROM pg_catalog.pg_trigger t
       WHERE NOT t.tgisinternal
         AND t.tgname = ANY (ARRAY[
           'cpr_protect', 'cps_protect', 'cst_protect', 'cpal_protect', 'cpal_somente_pelo_procedimento',
           'cci_liquidar_modalidade_v15', 'cci_portao_autoatendimento', 'cci_proteger_snapshot_trg',
           'cci_validar_producao_bandeiras', 'ceo_liquidar_modalidade_v15', 'ceo_liquidacao_v15_imutavel',
           'ceo_pagamento_confere_snapshot', 'ceo_revalidar_reutilizacao_bandeiras',
           'ceo_validar_producao_bandeiras', 'ceo_emitir_instrumento', 'ceo_instrumento_imutavel',
           'cp_valor_confere_pedido', 'cfi_bloquear_conjunto', 'citap_protect'])));
$function$

;

CREATE OR REPLACE FUNCTION public.commercial_pricing_activation_log_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF NOT public.commercial_activation_called_by_procedure() THEN
    RAISE EXCEPTION 'activation_log_somente_pelo_procedimento: registro de ativacao so e gravado por admin_activate_pricing_rule'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.guard_fingerprint IS DISTINCT FROM public.commercial_activation_guard_fingerprint() THEN
    RAISE EXCEPTION 'activation_log_impressao_divergente: impressao digital das guardas nao confere'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.actor      := session_user;
  NEW.txid       := pg_catalog.txid_current();
  NEW.created_at := pg_catalog.now();
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.admin_activate_pricing_rule(p_version integer, p_authorization_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_pre     jsonb;
  v_anterior integer;
BEGIN
  IF p_authorization_reference IS NULL OR length(btrim(p_authorization_reference)) < 10 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'authorization_reference_required');
  END IF;
  v_pre := public.commercial_pricing_activation_preflight(p_version);
  IF (v_pre->>'ok')::boolean IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'activation_preconditions_pending', 'failures', v_pre->'failures');
  END IF;

  INSERT INTO public.commercial_pricing_activation_log
    (pricing_rule_version, authorization_reference, preflight, guard_fingerprint)
  VALUES (p_version, btrim(p_authorization_reference), v_pre,
          public.commercial_activation_guard_fingerprint());

  SELECT version INTO v_anterior FROM public.commercial_pricing_rules WHERE status = 'active';
  UPDATE public.commercial_pricing_rules SET status = 'superseded'
   WHERE status = 'active' AND version < p_version;
  UPDATE public.commercial_pricing_rules SET status = 'active', effective_from = pg_catalog.now()
   WHERE version = p_version;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'activated_version', p_version,
    'superseded_version', v_anterior,
    'guard_fingerprint_md5', pg_catalog.md5(public.commercial_activation_guard_fingerprint()::text));
END $function$

;

CREATE OR REPLACE FUNCTION public.commercial_pricing_activation_preflight(p_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_rule    public.commercial_pricing_rules%ROWTYPE;
  v_falhas  text[] := ARRAY[]::text[];
  v_econ    text;
  v_cat     text;
  v_fid     boolean;
  v_modo    text;
  v_n       integer;
  v_nichos  integer;
  v_gatilho record;
BEGIN
  SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE version = p_version;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'version', p_version,
      'failures', pg_catalog.to_jsonb(ARRAY['rule_not_found']));
  END IF;
  IF v_rule.status <> 'prepared' THEN
    v_falhas := v_falhas || ('rule_not_prepared:' || v_rule.status);
  END IF;

  -- A4: política de QA e termos das DUAS modalidades, coerentes.
  IF v_rule.qa_policy IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    v_falhas := v_falhas || 'qa_policy_missing'::text;
  END IF;
  SELECT count(*) INTO v_n FROM public.commercial_pricing_schedule WHERE pricing_rule_version = p_version;
  IF v_n <> 4 THEN
    v_falhas := v_falhas || ('schedule_incomplete:' || v_n);
  END IF;
  SELECT max(contract_economics_version) INTO v_econ
    FROM public.commercial_pricing_schedule WHERE pricing_rule_version = p_version;
  FOREACH v_cat IN ARRAY ARRAY['supermarket', 'common'] LOOP
    FOREACH v_fid IN ARRAY ARRAY[false, true] LOOP
      FOREACH v_modo IN ARRAY ARRAY['direct_benefits', 'cash'] LOOP
        IF NOT EXISTS (SELECT 1 FROM public.commercial_settlement_terms t
                        WHERE t.pricing_rule_version = p_version AND t.commercial_category = v_cat
                          AND t.fidelized = v_fid AND t.benefit_settlement_mode = v_modo) THEN
          v_falhas := v_falhas || format('settlement_terms_missing:%s/%s/%s', v_cat,
                                         CASE WHEN v_fid THEN 'fidelizado' ELSE 'novo' END, v_modo);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  -- A6: minuta assinável que redige o modelo de liquidação, para as duas
  -- condições de fidelidade; e atividade contratada aprovada no catálogo da
  -- economia da versão, para toda posição ativa (A2).
  FOREACH v_fid IN ARRAY ARRAY[false, true] LOOP
    -- R4: minuta assinável COM aprovação jurídica do mesmo conteúdo, para a
    -- economia da versão, o modelo de liquidação e as DUAS modalidades.
    IF NOT EXISTS (SELECT 1 FROM public.commercial_instrument_templates t
                     JOIN public.commercial_instrument_template_approvals a
                       ON a.template_id = t.id
                      AND a.content_sha256 = t.source_hash
                      AND a.contract_economics_version = v_econ
                      AND a.settlement_model = v_rule.qa_policy
                      AND a.applies_to_fidelized = v_fid
                      AND a.settlement_modes @> ARRAY['direct_benefits', 'cash']::text[]
                    WHERE t.lifecycle_status = 'signable' AND t.applies_to_fidelized = v_fid
                      AND t.settlement_model IS NOT DISTINCT FROM v_rule.qa_policy
                      AND v_rule.qa_policy IS NOT NULL) THEN
      v_falhas := v_falhas || format('instrument_template_missing:%s',
                                     CASE WHEN v_fid THEN 'fidelizado' ELSE 'novo' END);
    END IF;
  END LOOP;
  SELECT count(*) INTO v_nichos FROM public.commercial_niches WHERE is_active;
  SELECT count(DISTINCT c.niche_code) INTO v_n
    FROM public.commercial_contract_activity_catalog c
    JOIN public.commercial_niches n ON n.code = c.niche_code AND n.is_active
   WHERE c.catalog_version = v_econ AND c.status = 'approved';
  IF v_econ IS NULL OR v_n < v_nichos THEN
    v_falhas := v_falhas || format('activity_catalog_incomplete:%s/%s', v_n, v_nichos);
  END IF;

  -- A1, A3, A5, A6: as travas do banco precisam estar LIGADAS. Um gatilho
  -- desativado (ALTER TABLE ... DISABLE TRIGGER) impede a ativação.
  FOR v_gatilho IN
    SELECT x.tabela, x.nome, t.tgenabled
      FROM (VALUES
        ('commercial_pricing_rules', 'cpr_protect'),
        ('commercial_pricing_schedule', 'cps_protect'),
        ('commercial_settlement_terms', 'cst_protect'),
        ('commercial_checkout_intents', 'cci_liquidar_modalidade_v15'),
        ('commercial_checkout_intents', 'cci_portao_autoatendimento'),
        ('commercial_checkout_intents', 'cci_proteger_snapshot_trg'),
        ('commercial_checkout_intents', 'cci_validar_producao_bandeiras'),
        ('commercial_exclusivity_orders', 'ceo_liquidar_modalidade_v15'),
        ('commercial_exclusivity_orders', 'ceo_liquidacao_v15_imutavel'),
        ('commercial_exclusivity_orders', 'ceo_pagamento_confere_snapshot'),
        ('commercial_exclusivity_orders', 'ceo_revalidar_reutilizacao_bandeiras'),
        ('commercial_exclusivity_orders', 'ceo_validar_producao_bandeiras'),
        ('commercial_exclusivity_orders', 'ceo_emitir_instrumento'),
        ('commercial_exclusivity_orders', 'ceo_instrumento_imutavel'),
        ('commercial_payments', 'cp_valor_confere_pedido'),
        ('commercial_pricing_activation_log', 'cpal_protect'),
        ('commercial_pricing_activation_log', 'cpal_somente_pelo_procedimento'),
        ('commercial_flag_set_inspections', 'cfi_bloquear_conjunto'),
        ('commercial_instrument_template_approvals', 'citap_protect')) AS x(tabela, nome)
      LEFT JOIN pg_catalog.pg_trigger t
        ON t.tgname = x.nome
       AND t.tgrelid = pg_catalog.to_regclass('public.' || x.tabela)
  LOOP
    IF v_gatilho.tgenabled IS NULL OR v_gatilho.tgenabled = 'D' THEN
      v_falhas := v_falhas || ('guard_trigger_disabled:' || v_gatilho.nome);
    END IF;
  END LOOP;

  -- Reserva viva sob a versão anterior seria finalizada com o preço antigo.
  SELECT count(*) INTO v_n FROM public.commercial_checkout_intents
   WHERE status IN ('draft', 'awaiting_contract')
     AND reserved_until IS NOT NULL AND reserved_until > pg_catalog.now();
  IF v_n > 0 THEN
    v_falhas := v_falhas || ('live_reservations:' || v_n);
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', coalesce(array_length(v_falhas, 1), 0) = 0,
    'version', p_version,
    'failures', pg_catalog.to_jsonb(v_falhas));
END $function$

;

CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot(p_order_id uuid, p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o      public.commercial_exclusivity_orders%ROWTYPE;
  v_c      public.site_partner_companies%ROWTYPE;
  v_u      public.site_partner_units%ROWTYPE;
  v_a      public.commercial_master_agreements%ROWTYPE;
  v_rep    public.partner_application_representatives%ROWTYPE;
  v_ace    public.legal_acceptances%ROWTYPE;
  v_t      public.commercial_instrument_templates%ROWTYPE;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_ativ   jsonb;
  v_snap   jsonb;
  v_prov   jsonb;
  v_faltam text[] := ARRAY[]::text[];
  v_campo  text;
  v_spec   public.commercial_advertising_specs%ROWTYPE;
  v_reg    public.commercial_regions%ROWTYPE;
  v_exc    public.commercial_exclusivities%ROWTYPE;
  v_ativ_ef jsonb;
  v_qa_policy text;
  v_liq    jsonb;
  v_apr    public.commercial_instrument_template_approvals%ROWTYPE;
BEGIN
  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE id = p_template_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_unavailable');
  END IF;
  IF v_t.lifecycle_status <> 'signable' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_not_signable',
      'lifecycle_status', v_t.lifecycle_status, 'template_code', v_t.template_code);
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF coalesce(v_o.fidelized, false) <> v_t.applies_to_fidelized THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_fidelity_mismatch',
      'order_fidelized', coalesce(v_o.fidelized, false),
      'template_applies_to_fidelized', v_t.applies_to_fidelized);
  END IF;

  -- OUTROS dormente: nicho fora do catalogo canonico nao individualiza nada.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_niches n
                  WHERE n.code = v_o.niche_code AND n.is_active) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_niche_not_canonical',
      'niche_code', v_o.niche_code);
  END IF;

  -- D9: a minuta vigente não identifica posição × segmento nem tem atividade
  -- contratada por segmento. Até a revisão jurídica, pedido com segmento (ou
  -- na posição Outros) não individualiza instrumento — falha fechado.
  IF v_o.segment_id IS NOT NULL OR v_o.niche_code = 'others' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_segment_activity_unavailable',
      'niche_code', v_o.niche_code,
      'segment_code', v_o.segment_code_snapshot);
  END IF;

  SELECT * INTO v_c FROM public.site_partner_companies WHERE id = v_o.company_id;
  SELECT * INTO v_a FROM public.commercial_master_agreements
   WHERE id = v_o.master_agreement_id;
  SELECT * INTO v_rep FROM public.partner_application_representatives
   WHERE application_id = v_c.source_application_id AND is_current;
  IF v_o.legal_acceptance_id IS NOT NULL THEN
    SELECT * INTO v_ace FROM public.legal_acceptances WHERE id = v_o.legal_acceptance_id;
  END IF;

  -- ---- UNIDADE DE EXECUCAO: persistida e revalidada, nunca "a primeira".
  IF v_o.execution_unit_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_selected', 'order_id', v_o.id);
  END IF;
  SELECT * INTO v_u FROM public.site_partner_units WHERE id = v_o.execution_unit_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_found');
  END IF;
  IF v_u.company_id IS DISTINCT FROM v_o.company_id THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_owned_by_company');
  END IF;
  IF v_u.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_active', 'status', v_u.status);
  END IF;

  -- ---- TOMADOR DE NFS-e: tem de ser o CNPJ da contratante no MVP fundador.
  IF v_o.nfse_taker_cnpj IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'nfse_taker_not_persisted');
  END IF;
  IF pg_catalog.regexp_replace(v_o.nfse_taker_cnpj, '[^0-9]', '', 'g')
       IS DISTINCT FROM
       pg_catalog.regexp_replace(v_c.cnpj, '[^0-9]', '', 'g') THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'alternate_nfse_taker_not_supported',
      'persisted_taker', v_o.nfse_taker_cnpj);
  END IF;

  -- ---- ECONOMIA: da autoridade, incluindo o valor da participacao.
  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = v_o.pricing_rule_version
     AND contract_economics_version = v_o.contract_economics_version
     AND commercial_category = CASE WHEN v_o.niche_code = 'supermarket'
                                    THEN 'supermarket' ELSE 'common' END
     AND fidelized = coalesce(v_o.fidelized, false);
  IF NOT FOUND OR v_sched.ordinary_participation_value_cents IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'contract_economics_authority_unavailable',
      'pricing_rule_version', v_o.pricing_rule_version);
  END IF;

  -- ---- R3 / A6: a minuta precisa redigir o modelo de liquidacao da versao,
  -- e o pedido precisa conferir com os termos da modalidade escolhida.
  SELECT qa_policy INTO v_qa_policy FROM public.commercial_pricing_rules
   WHERE version = v_o.pricing_rule_version;
  IF v_t.settlement_model IS DISTINCT FROM v_qa_policy THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_settlement_model_mismatch',
      'template_code', v_t.template_code,
      'template_settlement_model', v_t.settlement_model,
      'pricing_qa_policy', v_qa_policy);
  END IF;
  IF v_o.pricing_rule_version >= 4 THEN
    v_liq := public.commercial_order_settlement_check(v_o.id);
    IF (v_liq->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_liq;
    END IF;
    -- R4: aprovação jurídica DESTE conteúdo, para ESTA economia, modelo,
    -- modalidade e fidelidade. Qualquer divergência falha fechada.
    SELECT * INTO v_apr FROM public.commercial_instrument_template_approvals a
     WHERE a.template_id = v_t.id AND a.contract_economics_version = v_o.contract_economics_version;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_approval_missing',
        'template_code', v_t.template_code, 'contract_economics_version', v_o.contract_economics_version);
    END IF;
    IF v_apr.content_sha256 IS DISTINCT FROM v_t.source_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_content_mismatch', 'template_code', v_t.template_code);
    END IF;
    IF v_apr.settlement_model IS DISTINCT FROM v_qa_policy THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_settlement_model_mismatch', 'template_code', v_t.template_code);
    END IF;
    IF NOT (v_o.benefit_settlement_mode = ANY (v_apr.settlement_modes)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_settlement_mode_not_covered',
        'template_code', v_t.template_code, 'benefit_settlement_mode', v_o.benefit_settlement_mode);
    END IF;
    IF v_apr.applies_to_fidelized IS DISTINCT FROM coalesce(v_o.fidelized, false) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_fidelity_mismatch', 'template_code', v_t.template_code);
    END IF;
  END IF;

  -- ---- ATIVIDADE CONTRATADA: do catalogo. Bloqueada em producao.
  v_ativ := public.commercial_approved_contract_activity(
              v_o.niche_code, v_o.contract_economics_version);
  IF (v_ativ->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_ativ;
  END IF;

  v_snap := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'company_legal_name', v_c.legal_name,
    'company_cnpj', v_c.cnpj,
    'company_trade_name', v_c.trade_name,
    'representative_full_name', v_rep.full_name,
    'representative_cpf', v_rep.cpf,
    'representative_role_title', v_rep.role_title,
    'representative_authority_status', v_rep.authority_status,
    'city', v_c.city,
    'uf', v_c.uf,
    'region_id', v_o.region_id,
    'exclusivity_id', v_o.exclusivity_id,
    'nfse_taker_cnpj', v_o.nfse_taker_cnpj,
    'execution_unit_id', v_u.id,
    'execution_unit_name', v_u.name,
    'execution_unit_city', v_u.city,
    'execution_unit_uf', v_u.uf,
    'execution_unit_company_id', v_u.company_id,
    'activity_description', v_ativ->>'activity_description',
    'activity_code', v_ativ->>'activity_code',
    'activity_catalog_id', v_ativ->>'activity_catalog_id',
    'activity_source_hash', v_ativ->>'source_hash',
    'niche_code', v_o.niche_code,
    'nominal_quantity', v_o.nominal_quantity,
    'benefit_settlement_mode', v_o.benefit_settlement_mode,
    'master_agreement_id', v_a.id,
    'master_legal_document_id', v_a.legal_document_id,
    'master_agreement_version', v_a.agreement_version,
    'master_document_hash', v_a.document_hash,
    'order_id', v_o.id,
    'pricing_rule_version', v_o.pricing_rule_version,
    'contract_economics_version', v_o.contract_economics_version,
    'economic_value_cents', v_o.economic_value_cents,
    'mei_consideration_cents', v_o.mei_consideration_cents,
    'smallflags_qa_cents', v_o.smallflags_qa_cents,
    'smallflags_main_fee_cents', v_o.smallflags_main_fee_cents,
    'smallflags_total_remuneration_cents', v_o.smallflags_total_remuneration_cents,
    'total_monetary_funding_required_cents', v_o.total_monetary_funding_required_cents,
    'participation_value_cents', v_sched.ordinary_participation_value_cents,
    'acceptance_actor_id', coalesce(v_ace.linked_auth_user_id, v_o.registered_by),
    'acceptance_at', coalesce(v_ace.accepted_at, v_o.signed_at)));

  -- Proveniencia por REGISTRO CANONICO, nao por "veio do chamador".
  v_prov := pg_catalog.jsonb_build_object(
    'company_legal_name', 'site_company',
    'company_cnpj', 'site_company',
    'company_trade_name', 'site_company',
    'city', 'site_company',
    'uf', 'site_company',
    'nfse_taker_cnpj', 'site_company',
    'representative_full_name', 'site_representative',
    'representative_cpf', 'site_representative',
    'representative_role_title', 'site_representative',
    'representative_authority_status', 'site_representative',
    'execution_unit_id', 'site_unit',
    'execution_unit_name', 'site_unit',
    'execution_unit_city', 'site_unit',
    'execution_unit_uf', 'site_unit',
    'execution_unit_company_id', 'site_unit',
    'activity_description', 'commercial_activity_authority',
    'activity_code', 'commercial_activity_authority',
    'activity_catalog_id', 'commercial_activity_authority',
    'activity_source_hash', 'commercial_activity_authority',
    'participation_value_cents', 'contract_economics_authority',
    'economic_value_cents', 'contract_economics_authority',
    'mei_consideration_cents', 'contract_economics_authority',
    'smallflags_qa_cents', 'contract_economics_authority',
    'smallflags_main_fee_cents', 'contract_economics_authority',
    'smallflags_total_remuneration_cents', 'contract_economics_authority',
    'total_monetary_funding_required_cents', 'contract_economics_authority',
    'contract_economics_version', 'contract_economics_authority',
    'pricing_rule_version', 'contract_economics_authority',
    'master_agreement_id', 'master_agreement',
    'master_legal_document_id', 'master_agreement',
    'master_agreement_version', 'master_agreement',
    'master_document_hash', 'master_agreement',
    'acceptance_actor_id', 'legal_acceptance',
    'acceptance_at', 'legal_acceptance',
    'order_id', 'commercial_order',
    'region_id', 'commercial_order',
    'exclusivity_id', 'commercial_order',
    'niche_code', 'commercial_order',
    'nominal_quantity', 'commercial_order',
    'benefit_settlement_mode', 'commercial_order');

  -- ---- V2 (publicidade visual em veiculos): SO para modelo que exige
  -- especificacao tecnica. O modelo v1.4 nao exige e segue identico.
  -- Sem especificacao APROVADA para a modalidade, falha fechada.
  IF v_t.requires_advertising_spec THEN
    SELECT * INTO v_spec FROM public.commercial_advertising_specs
     WHERE modality = v_t.advertising_modality
       AND lifecycle_status = 'approved';
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'commercial_advertising_spec_not_approved',
        'modality', v_t.advertising_modality, 'template_code', v_t.template_code);
    END IF;
    SELECT * INTO v_reg FROM public.commercial_regions WHERE id = v_o.region_id;
    SELECT * INTO v_exc FROM public.commercial_exclusivities WHERE id = v_o.exclusivity_id;
    v_ativ_ef := public.commercial_order_effective_activity(v_o.id);

    v_snap := v_snap || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'advertising_modality', v_spec.modality,
      'advertising_spec_id', v_spec.id,
      'advertising_spec_code', v_spec.spec_code,
      'advertising_spec_version', v_spec.spec_version,
      'advertising_spec_source_hash', v_spec.source_hash,
      'artwork_reference_width_mm', v_spec.artwork_reference_width_mm,
      'artwork_reference_height_mm', v_spec.artwork_reference_height_mm,
      'region_name', v_reg.name,
      'region_uf', v_reg.uf,
      'exclusivity_sequence_number', v_exc.sequence_number,
      'position_code', v_ativ_ef->>'position_code',
      'effective_activity_kind', v_ativ_ef->>'kind',
      'effective_activity_identity', v_ativ_ef->>'identity',
      'fidelized', v_o.fidelized,
      'exclusivity_period_days', v_o.exclusivity_period_days,
      'expected_operation_start', v_o.expected_operation_start));

    -- SF-v1.5: fatos de produção de bandeiras do PEDIDO (snapshot imutável).
    -- Ausentes sob a SF-v1.4; um modelo que os exija falha fechado ali.
    v_snap := v_snap || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'flag_production_new_units', v_o.flag_production_new_units,
      'flag_unit_reference_cents', v_o.flag_unit_reference_cents,
      'flag_production_charge_cents', v_o.flag_production_charge_cents,
      'flag_reuse_set_id', v_o.flag_reuse_set_id,
      'flag_reuse_inspection_id', v_o.flag_reuse_inspection_id));

    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'advertising_modality', 'advertising_spec_authority',
      'advertising_spec_id', 'advertising_spec_authority',
      'advertising_spec_code', 'advertising_spec_authority',
      'advertising_spec_version', 'advertising_spec_authority',
      'advertising_spec_source_hash', 'advertising_spec_authority',
      'artwork_reference_width_mm', 'advertising_spec_authority',
      'artwork_reference_height_mm', 'advertising_spec_authority',
      'region_name', 'commercial_region',
      'region_uf', 'commercial_region',
      'exclusivity_sequence_number', 'commercial_exclusivity',
      'position_code', 'commercial_order',
      'effective_activity_kind', 'commercial_order',
      'effective_activity_identity', 'commercial_order',
      'fidelized', 'commercial_order',
      'exclusivity_period_days', 'commercial_order',
      'expected_operation_start', 'commercial_order');
    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'flag_production_new_units', 'contract_economics_authority',
      'flag_unit_reference_cents', 'contract_economics_authority',
      'flag_production_charge_cents', 'contract_economics_authority',
      'flag_reuse_set_id', 'flag_inventory_authority',
      'flag_reuse_inspection_id', 'flag_inventory_authority');
  END IF;

  -- R3: composicao da modalidade, explicita no instrumento (versao >= 4).
  IF v_o.pricing_rule_version >= 4 THEN
    v_snap := v_snap || pg_catalog.jsonb_build_object(
      'qa_policy', v_qa_policy,
      'settlement_terms_id', v_o.settlement_terms_id,
      'mei_in_kind_cents', v_o.mei_in_kind_cents,
      'mei_cash_funding_cents', v_o.mei_cash_funding_cents,
      'qa_in_kind_cents', v_o.qa_in_kind_cents,
      'qa_cash_cents', v_o.qa_cash_cents,
      'cash_adjustment_cents', v_o.cash_adjustment_cents,
      'instrument_legal_approval_id', v_apr.id,
      'instrument_legal_approval_reference', v_apr.legal_approval_reference,
      'instrument_legal_content_sha256', v_apr.content_sha256,
      'instrument_legal_settlement_modes', pg_catalog.to_jsonb(v_apr.settlement_modes));
    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'qa_policy', 'contract_economics_authority',
      'settlement_terms_id', 'contract_economics_authority',
      'mei_in_kind_cents', 'contract_economics_authority',
      'mei_cash_funding_cents', 'contract_economics_authority',
      'qa_in_kind_cents', 'contract_economics_authority',
      'qa_cash_cents', 'contract_economics_authority',
      'cash_adjustment_cents', 'contract_economics_authority',
      'instrument_legal_approval_id', 'instrument_legal_approval',
      'instrument_legal_approval_reference', 'instrument_legal_approval',
      'instrument_legal_content_sha256', 'instrument_legal_approval',
      'instrument_legal_settlement_modes', 'instrument_legal_approval');
  END IF;

  -- Falha fechada nomeando CADA fato material ausente.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_snap ? v_campo) THEN
      v_faltam := v_faltam || v_campo;
    END IF;
  END LOOP;
  IF array_length(v_faltam, 1) >= 1 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'instrument_snapshot_material_fact_missing',
      'missing_fields', pg_catalog.to_jsonb(v_faltam),
      'template_code', v_t.template_code);
  END IF;

  -- Nenhum fato do snapshot pode ter vindo de fora das autoridades: toda chave
  -- material tem de ter proveniencia declarada.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_prov ? v_campo) THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'instrument_snapshot_provenance_undeclared',
        'field', v_campo);
    END IF;
  END LOOP;

  v_snap := v_snap || pg_catalog.jsonb_build_object(
    'instrument_template_code', v_t.template_code,
    'instrument_template_version', v_t.template_version,
    'instrument_template_date', v_t.template_date,
    'instrument_template_source_hash', v_t.source_hash,
    'field_provenance', v_prov);

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'template_id', v_t.id,
    'template_version', v_t.template_version,
    'template_date', v_t.template_date,
    'template_source_hash', v_t.source_hash,
    'snapshot', v_snap,
    'snapshot_hash',
      pg_catalog.encode(extensions.digest(v_snap::text, 'sha256'), 'hex'));
END;
$function$

;

ALTER TABLE public.commercial_pricing_activation_log
  DROP COLUMN activation_approval_id,
  DROP COLUMN approval_document_sha256,
  DROP COLUMN guard_catalog_sha256,
  DROP COLUMN guard_manifest_id,
  DROP COLUMN executor_db_role,
  DROP COLUMN executor_jwt_sub,
  DROP COLUMN executor_application_name,
  DROP COLUMN executor_client_addr;
COMMENT ON COLUMN public.commercial_pricing_activation_log.actor IS NULL;

DROP TABLE public.commercial_pricing_activation_approvals;
DROP TABLE public.commercial_qa_operational_procedures;
DROP TABLE public.commercial_guard_manifests;
DROP FUNCTION public.commercial_pricing_activation_approvals_protect();
DROP FUNCTION public.commercial_qa_operational_procedures_protect();
DROP FUNCTION public.commercial_guard_manifests_protect();
DROP FUNCTION public.commercial_guard_integrity_failures();
DROP FUNCTION public.commercial_guard_catalog();
DROP FUNCTION public.commercial_guard_function_entry(regprocedure);
COMMIT;
