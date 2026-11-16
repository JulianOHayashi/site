-- ===========================================================================
-- ROLLBACK de 20261113150000_commercial_qa_in_kind_settlement_modes_r3.sql
--
-- Só é permitido enquanto a R3 nunca foi usada: versão 4 'prepared', nenhum
-- registro de ativação, nenhum pedido/intenção com composição por modalidade,
-- nenhum preço de DINHEIRO gravado. Caso contrário aborta com
-- rollback_bloqueado e nada é desfeito. As funções voltam ao texto EXATO
-- anterior (pg_get_functiondef do banco-base). Ensaio:
-- scripts/db-test/r3-upgrade-check.sh (catálogo idêntico ao anterior).
-- ===========================================================================
BEGIN;

DO $guarda$
DECLARE v_motivos text[] := '{}';
BEGIN
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) IS DISTINCT FROM 'prepared' THEN
    v_motivos := v_motivos || 'versao 4 nao esta prepared (foi ativada)'::text; END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log) THEN
    v_motivos := v_motivos || 'ha registro de ativacao'::text; END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders WHERE settlement_terms_id IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.commercial_checkout_intents WHERE settlement_terms_id IS NOT NULL) THEN
    v_motivos := v_motivos || 'ha pedidos ou intencoes com composicao por modalidade'::text; END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms WHERE benefit_settlement_mode = 'cash') THEN
    v_motivos := v_motivos || 'ha preco de DINHEIRO gravado'::text; END IF;
  IF cardinality(v_motivos) > 0 THEN
    RAISE EXCEPTION 'rollback_bloqueado: %', array_to_string(v_motivos, '; ');
  END IF;
END
$guarda$;

-- 1. Gatilhos novos.
DROP TRIGGER cci_liquidar_modalidade_v15 ON public.commercial_checkout_intents;
DROP TRIGGER cci_portao_autoatendimento ON public.commercial_checkout_intents;
DROP TRIGGER ceo_liquidar_modalidade_v15 ON public.commercial_exclusivity_orders;
DROP TRIGGER ceo_liquidacao_v15_imutavel ON public.commercial_exclusivity_orders;
DROP TRIGGER ceo_pagamento_confere_snapshot ON public.commercial_exclusivity_orders;
DROP TRIGGER ceo_revalidar_reutilizacao_bandeiras ON public.commercial_exclusivity_orders;
DROP TRIGGER cp_valor_confere_pedido ON public.commercial_payments;

-- 2. Funções existentes voltam ao texto anterior (ACL preservada pelo REPLACE).
CREATE OR REPLACE FUNCTION public.commercial_pricing_rules_protect()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'pricing_rule_imutavel: regra nova nasce prepared (recebido %)', NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.status IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'pricing_rule_imutavel: regra % (%) nao pode ser apagada', OLD.version, OLD.status
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  -- UPDATE: valores nunca mudam depois de a regra sair de 'prepared'; em
  -- 'prepared' a regra ainda é editável. Só status (e effective_from na
  -- ativação) mudam nas transições.
  IF OLD.status = 'prepared' AND NEW.status = 'prepared' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.version IS DISTINCT FROM OLD.version THEN
      RAISE EXCEPTION 'pricing_rule_imutavel: id e version nao mudam'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NOT ((OLD.status = 'prepared' AND NEW.status = 'active')
          OR (OLD.status = 'active' AND NEW.status = 'superseded')) THEN
    RAISE EXCEPTION 'pricing_rule_imutavel: transicao % -> % recusada (versao %)',
      OLD.status, NEW.status, OLD.version
      USING ERRCODE = 'check_violation';
  END IF;
  IF (pg_catalog.to_jsonb(NEW) - 'status' - 'effective_from')
       IS DISTINCT FROM
     (pg_catalog.to_jsonb(OLD) - 'status' - 'effective_from') THEN
    RAISE EXCEPTION 'pricing_rule_imutavel: valores da versao % nao mudam', OLD.version
      USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'active' AND NEW.effective_from IS DISTINCT FROM OLD.effective_from THEN
    RAISE EXCEPTION 'pricing_rule_imutavel: effective_from so muda na ativacao'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.cci_aplicar_autoridade_v14()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_cat   text;
  v_sched public.commercial_pricing_schedule%ROWTYPE;
BEGIN
  IF NEW.pricing_rule_version IS NULL OR NEW.pricing_rule_version < 3 THEN
    RETURN NEW;
  END IF;
  IF NEW.contract_economics_version IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_cat := CASE WHEN NEW.niche_code = 'supermarket' THEN 'supermarket' ELSE 'common' END;

  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = NEW.pricing_rule_version
     AND commercial_category  = v_cat
     AND fidelized            = NEW.fidelized;
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'autoridade v1.4 ausente para versao=%, categoria=%, fidelizado=%',
      NEW.pricing_rule_version, v_cat, NEW.fidelized
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.contract_economics_version          := v_sched.contract_economics_version;
  NEW.economic_value_cents                := v_sched.economic_value_cents;
  NEW.mei_consideration_cents             := v_sched.mei_consideration_cents;
  NEW.smallflags_qa_cents                 := v_sched.smallflags_qa_cents;
  NEW.smallflags_main_fee_cents           := v_sched.smallflags_main_fee_cents;
  NEW.smallflags_total_remuneration_cents := v_sched.smallflags_total_remuneration_cents;
  NEW.user_pool_cents            := v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents;
  NEW.bdflow_ops_investment_cents := v_sched.smallflags_main_fee_cents;

  IF NEW.benefit_settlement_mode = 'direct_benefits' THEN
    NEW.mei_cash_funding_cents                := 0;
    NEW.cash_user_pool_funding_cents          := 0;
    NEW.total_monetary_funding_required_cents := v_sched.smallflags_total_remuneration_cents;
  ELSIF NEW.benefit_settlement_mode = 'cash' THEN
    NEW.mei_cash_funding_cents                := v_sched.mei_consideration_cents;
    NEW.cash_user_pool_funding_cents          := NEW.user_pool_cents;
    NEW.total_monetary_funding_required_cents := v_sched.economic_value_cents;
  END IF;

  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.ceo_aplicar_autoridade_v14()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_cat   text;
  v_sched public.commercial_pricing_schedule%ROWTYPE;
BEGIN
  -- Só a v1.4 em diante. Pedidos V1/V2 passam intocados.
  IF NEW.pricing_rule_version IS NULL OR NEW.pricing_rule_version < 3 THEN
    RETURN NEW;
  END IF;
  -- Snapshot já resolvido (cópia de uma intenção, por exemplo): respeitado.
  IF NEW.contract_economics_version IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_cat := CASE WHEN NEW.niche_code = 'supermarket' THEN 'supermarket' ELSE 'common' END;

  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = NEW.pricing_rule_version
     AND commercial_category  = v_cat
     AND fidelized            = NEW.fidelized;
  IF NOT FOUND THEN
    -- Falha fechada: sem valor contratado, não se inventa um.
    RAISE EXCEPTION
      'autoridade v1.4 ausente para versao=%, categoria=%, fidelizado=%',
      NEW.pricing_rule_version, v_cat, NEW.fidelized
      USING ERRCODE = 'check_violation';
  END IF;

  NEW.contract_economics_version          := v_sched.contract_economics_version;
  NEW.economic_value_cents                := v_sched.economic_value_cents;
  NEW.mei_consideration_cents             := v_sched.mei_consideration_cents;
  NEW.smallflags_qa_cents                 := v_sched.smallflags_qa_cents;
  NEW.smallflags_main_fee_cents           := v_sched.smallflags_main_fee_cents;
  NEW.smallflags_total_remuneration_cents := v_sched.smallflags_total_remuneration_cents;
  -- Compatibilidade: economic = pool + due continua valendo.
  NEW.contractual_pool_cents := v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents;
  NEW.bdflow_due_cents       := v_sched.smallflags_main_fee_cents;

  IF NEW.benefit_settlement_mode = 'direct_benefits' THEN
    -- A parceira entrega a contraprestação como benefício e paga em dinheiro
    -- a remuneração INTEIRA da SmallFlags, QA inclusa.
    NEW.mei_cash_funding_cents                := 0;
    NEW.cash_user_pool_funding_cents          := 0;
    NEW.total_monetary_funding_required_cents := v_sched.smallflags_total_remuneration_cents;
  ELSIF NEW.benefit_settlement_mode = 'cash' THEN
    -- A QA NÃO entra como dinheiro de terceiros: é remuneração da SmallFlags.
    NEW.mei_cash_funding_cents                := v_sched.mei_consideration_cents;
    NEW.cash_user_pool_funding_cents          := NEW.contractual_pool_cents;
    NEW.total_monetary_funding_required_cents := v_sched.economic_value_cents;
  END IF;

  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.admin_confirm_manual_bdflow_payment(p_order_id uuid, p_amount_cents bigint, p_payment_external_ref text DEFAULT NULL::text, p_justification text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_ord public.commercial_exclusivity_orders%ROWTYPE;
  v_esperado bigint;
BEGIN
  PERFORM public.m1_exigir_admin();

  SELECT * INTO v_ord FROM public.commercial_exclusivity_orders
   WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF v_ord.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;
  IF v_ord.status <> 'signed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_signed');
  END IF;

  -- Idempotência: já confirmado devolve o estado, sem sobrescrever.
  IF v_ord.payment_status = 'confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'payment_status', 'confirmed');
  END IF;

  -- "Pago" é o valor DEVIDO À SMALLFLAGS. O pool do usuário NÃO é cobrado nem
  -- custodiado, em nenhuma das duas eras. O que muda entre elas é apenas o que
  -- compõe esse devido — e o valor vem do instantâneo imutável do pedido,
  -- nunca de constante nesta função.
  IF v_ord.pricing_rule_version >= 3 THEN
    -- v1.4: taxa principal + parcela de QA, ambas da SmallFlags.
    v_esperado := v_ord.smallflags_total_remuneration_cents;
    IF v_esperado IS NULL THEN
      -- Falha fechada: pedido v1.4 sem instantâneo de remuneração não é
      -- conferível, e inventar valor aqui seria autoridade falsa.
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'v14_remuneration_snapshot_missing');
    END IF;
  ELSE
    -- V1/V2 históricos: exatamente como sempre foram.
    v_esperado := v_ord.bdflow_due_cents;
  END IF;

  IF p_amount_cents IS NULL OR p_amount_cents <> v_esperado THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'amount_differs_from_due',
      'expected_cents', v_esperado);
  END IF;

  UPDATE public.commercial_exclusivity_orders
     SET payment_status = 'confirmed',
         payment_confirmed_at = pg_catalog.now(),
         payment_confirmed_by = auth.uid(),
         payment_amount_cents = p_amount_cents,
         payment_external_ref = nullif(pg_catalog.btrim(coalesce(p_payment_external_ref,'')), '')
   WHERE id = p_order_id;

  UPDATE public.commercial_opportunities
     SET status = 'contracted' WHERE id = v_ord.opportunity_id;

  PERFORM public.m1_auditar('commercial_order.payment_confirmed', p_order_id, 'admin',
    pg_catalog.jsonb_build_object('payment_status','confirmed',
                                  'amount_cents', p_amount_cents),
    pg_catalog.jsonb_build_object('payment_status','pending'),
    pg_catalog.jsonb_build_object('justification', p_justification));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
                                       'payment_status', 'confirmed');
END;
$function$

;

CREATE OR REPLACE FUNCTION public.calculate_niche_contract_pricing(p_niche_code text, p_fidelized boolean, p_pricing_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_rule      public.commercial_pricing_rules%ROWTYPE;
  v_qty       integer;
  v_economic  bigint;
  v_bps       integer;
  v_pool      bigint;
  v_cat       text;
  v_ratio     public.commercial_pool_share_ratios%ROWTYPE;
  v_sched     public.commercial_pricing_schedule%ROWTYPE;
  v_disp_pool text := NULL;
  v_disp_bdf  text := NULL;
BEGIN
  IF p_pricing_version IS NULL THEN
    SELECT * INTO v_rule
      FROM public.commercial_pricing_rules
     WHERE status = 'active';
  ELSE
    SELECT * INTO v_rule
      FROM public.commercial_pricing_rules
     WHERE version = p_pricing_version;
  END IF;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  -- SF-v1.5: versão PREPARADA não é preço vigente nem consultável, nem por
  -- versão explícita. Ela só passa a existir para o público depois da
  -- ativação autorizada.
  IF v_rule.status = 'prepared' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_rule_not_published');
  END IF;

  SELECT contracted_quantity INTO v_qty
    FROM public.commercial_niches
   WHERE code = p_niche_code AND is_active;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'invalid_niche');
  END IF;

  -- Seis posições ativas. Supermercado usa sua matriz; as cinco posições de
  -- 12 unidades (inclusive Calçados e Outros, decisão D3) usam a comum.
  -- Código fora desta lista falha fechado em vez de cair numa categoria por
  -- omissão.
  v_cat := CASE WHEN p_niche_code = 'supermarket' THEN 'supermarket'
                WHEN p_niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others') THEN 'common'
                ELSE NULL END;
  IF v_cat IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_category_unavailable',
      'niche_code', p_niche_code);
  END IF;

  -- SF-v1.4 e posteriores com agenda explícita.
  IF v_rule.pool_precision_model = 'explicit_schedule' THEN
    SELECT * INTO v_sched
      FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = v_rule.version
       AND commercial_category = v_cat
       AND fidelized = p_fidelized;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false,
        'reason', 'pricing_schedule_missing',
        'pricing_rule_version', v_rule.version,
        'commercial_category', v_cat,
        'fidelized', p_fidelized);
    END IF;

    RETURN pg_catalog.jsonb_build_object(
      'ok', true,
      'pricing_rule_version', v_rule.version,
      'pool_precision_model', v_rule.pool_precision_model,
      'niche_code', p_niche_code,
      'niche_category', v_cat,
      'nominal_quantity', v_qty,
      'fidelized', p_fidelized,
      'currency', 'BRL',
      'pool_bps', NULL::integer,
      'display_pool_percent', NULL::text,
      'display_bdflow_percent', NULL::text,
      'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
      'contract_economics_version', v_sched.contract_economics_version,
      'economic_value_cents', v_sched.economic_value_cents,
      'contractual_pool_cents',
        v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents,
      'bdflow_due_cents', v_sched.smallflags_main_fee_cents,
      'mei_consideration_cents', v_sched.mei_consideration_cents,
      'smallflags_qa_cents', v_sched.smallflags_qa_cents,
      'smallflags_main_fee_cents', v_sched.smallflags_main_fee_cents,
      'smallflags_total_remuneration_cents',
        v_sched.smallflags_total_remuneration_cents,
      'ordinary_participation_value_cents',
        v_sched.ordinary_participation_value_cents,
      -- NOVO: a UI lê estas três chaves; não reconstrói financiamento.
      'direct_benefit_deliverable_cents', v_sched.mei_consideration_cents,
      'funding_direct_benefits_cents',
        v_sched.smallflags_total_remuneration_cents,
      'funding_cash_cents', v_sched.economic_value_cents
    )
    -- SF-v1.5: fatos de produção de bandeiras, só quando a economia os prevê.
    -- A SF-v1.4 continua devolvendo exatamente as mesmas chaves.
    || CASE WHEN v_sched.new_flag_units IS NULL THEN '{}'::jsonb
       ELSE pg_catalog.jsonb_build_object(
         'new_flag_units', v_sched.new_flag_units,
         'flag_unit_reference_cents', v_sched.flag_unit_reference_cents,
         'flag_production_charge_cents', v_sched.flag_production_charge_cents,
         'flag_reuse_required', p_fidelized) END;
  END IF;

  -- V1/V2 históricos: cálculo original preservado.
  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  IF v_rule.pool_precision_model = 'exact_ratio' THEN
    SELECT * INTO v_ratio
      FROM public.commercial_pool_share_ratios
     WHERE pricing_rule_version = v_rule.version
       AND niche_category = v_cat;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'pool_ratio_unavailable');
    END IF;
    v_pool := (v_economic * v_ratio.pool_numerator) / v_ratio.pool_denominator;
    v_disp_pool := v_ratio.display_pool_percent;
    v_disp_bdf := v_ratio.display_bdflow_percent;
  ELSE
    v_bps := CASE WHEN v_cat = 'supermarket'
                  THEN v_rule.pool_bps_supermarket
                  ELSE v_rule.pool_bps_common END;
    v_pool := (v_economic * v_bps) / 10000;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'pricing_rule_version', v_rule.version,
    'pool_precision_model', v_rule.pool_precision_model,
    'niche_code', p_niche_code,
    'niche_category', v_cat,
    'nominal_quantity', v_qty,
    'fidelized', p_fidelized,
    'currency', 'BRL',
    'economic_value_cents', v_economic,
    'pool_bps', v_bps,
    'contractual_pool_cents', v_pool,
    'bdflow_due_cents', v_economic - v_pool,
    'display_pool_percent', v_disp_pool,
    'display_bdflow_percent', v_disp_bdf,
    'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
    -- NOVO: mesma semântica pública, resolvida pela autoridade histórica.
    'direct_benefit_deliverable_cents', v_pool,
    'funding_direct_benefits_cents', v_economic - v_pool,
    'funding_cash_cents', v_economic
  );
END;
$function$

;

CREATE OR REPLACE FUNCTION public.cci_resposta_intencao(p_i commercial_checkout_intents, p_ja boolean)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT pg_catalog.jsonb_build_object(
    'ok', true,
    'already', p_ja,
    'intent_id', p_i.id,
    'status', p_i.status,
    'opportunity_id', p_i.opportunity_id,
    'exclusivity_id', p_i.exclusivity_id,
    'region_id', p_i.region_id,
    'reserved_until', p_i.reserved_until,
    'reservation_minutes', 30,
    'pricing_rule_version', p_i.pricing_rule_version,
    'benefit_distribution_policy_version', p_i.benefit_distribution_policy_version,
    'niche_code', p_i.niche_code,
    'segment_code', p_i.segment_code_snapshot,
    'segment_name', p_i.segment_name_snapshot,
    'nominal_quantity', p_i.nominal_quantity,
    'fidelized', p_i.fidelized,
    'payment_method', p_i.payment_method,
    'benefit_settlement_mode', p_i.benefit_settlement_mode,
    'currency', p_i.currency,
    'economic_value_cents', p_i.economic_value_cents,
    -- Pool INTEIRO, por compatibilidade: inclui a parcela QA da SmallFlags.
    'user_pool_cents', p_i.user_pool_cents,
    'contract_economics_version', p_i.contract_economics_version,
    'mei_consideration_cents', p_i.mei_consideration_cents,
    'smallflags_qa_cents', p_i.smallflags_qa_cents,
    'smallflags_main_fee_cents', p_i.smallflags_main_fee_cents,
    'smallflags_total_remuneration_cents', p_i.smallflags_total_remuneration_cents,
    'bdflow_ops_investment_cents', p_i.bdflow_ops_investment_cents,
    'cash_user_pool_funding_cents', p_i.cash_user_pool_funding_cents,
    'total_monetary_funding_required_cents', p_i.total_monetary_funding_required_cents,
    'participant_target', p_i.participant_target,
    -- SF-v1.5: fatos de produção congelados na reserva (NULL na SF-v1.4).
    'new_flag_units', p_i.flag_production_new_units,
    'flag_unit_reference_cents', p_i.flag_unit_reference_cents,
    'flag_production_charge_cents', p_i.flag_production_charge_cents,
    'flag_reuse', (p_i.flag_reuse_set_id IS NOT NULL));
$function$

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

-- 3. CHECKs da R3; os da SF-v1.4 voltam ao escopo e comentário anteriores.
ALTER TABLE public.commercial_exclusivity_orders DROP CONSTRAINT ceo_liquidacao_modalidade_v15;
ALTER TABLE public.commercial_exclusivity_orders DROP CONSTRAINT ceo_liquidacao_v15_so_versao_4;
ALTER TABLE public.commercial_checkout_intents DROP CONSTRAINT cci_liquidacao_modalidade_v15;
ALTER TABLE public.commercial_checkout_intents DROP CONSTRAINT cci_liquidacao_v15_so_versao_4;
ALTER TABLE public.commercial_exclusivity_orders DROP CONSTRAINT ceo_financiamento_v14_coerente;
ALTER TABLE public.commercial_exclusivity_orders ADD CONSTRAINT ceo_financiamento_v14_coerente CHECK (((pricing_rule_version < 3) OR (benefit_settlement_mode IS NULL) OR ((mei_consideration_cents IS NOT NULL) AND (smallflags_qa_cents IS NOT NULL) AND (smallflags_main_fee_cents IS NOT NULL) AND (smallflags_total_remuneration_cents IS NOT NULL) AND (mei_cash_funding_cents IS NOT NULL) AND (smallflags_total_remuneration_cents = (smallflags_qa_cents + smallflags_main_fee_cents)) AND (economic_value_cents = ((mei_consideration_cents + smallflags_qa_cents) + smallflags_main_fee_cents)) AND (contractual_pool_cents = (mei_consideration_cents + smallflags_qa_cents)) AND (bdflow_due_cents = smallflags_main_fee_cents) AND (((benefit_settlement_mode = 'direct_benefits'::text) AND (mei_cash_funding_cents = 0) AND (total_monetary_funding_required_cents = smallflags_total_remuneration_cents)) OR ((benefit_settlement_mode = 'cash'::text) AND (mei_cash_funding_cents = mei_consideration_cents) AND (total_monetary_funding_required_cents = economic_value_cents)))))) NOT VALID;
COMMENT ON CONSTRAINT ceo_financiamento_v14_coerente ON public.commercial_exclusivity_orders IS 'Coerencia economica e de financiamento sob a autoridade v1.4 (pricing_rule_version >= 3).';
ALTER TABLE public.commercial_checkout_intents DROP CONSTRAINT cci_financiamento_v14_coerente;
ALTER TABLE public.commercial_checkout_intents ADD CONSTRAINT cci_financiamento_v14_coerente CHECK (((pricing_rule_version < 3) OR ((mei_consideration_cents IS NOT NULL) AND (smallflags_qa_cents IS NOT NULL) AND (smallflags_main_fee_cents IS NOT NULL) AND (smallflags_total_remuneration_cents IS NOT NULL) AND (mei_cash_funding_cents IS NOT NULL) AND (smallflags_total_remuneration_cents = (smallflags_qa_cents + smallflags_main_fee_cents)) AND (economic_value_cents = ((mei_consideration_cents + smallflags_qa_cents) + smallflags_main_fee_cents)) AND (user_pool_cents = (mei_consideration_cents + smallflags_qa_cents)) AND (bdflow_ops_investment_cents = smallflags_main_fee_cents) AND (((benefit_settlement_mode = 'direct_benefits'::text) AND (mei_cash_funding_cents = 0) AND (cash_user_pool_funding_cents = 0) AND (total_monetary_funding_required_cents = smallflags_total_remuneration_cents)) OR ((benefit_settlement_mode = 'cash'::text) AND (mei_cash_funding_cents = mei_consideration_cents) AND (cash_user_pool_funding_cents = user_pool_cents) AND (total_monetary_funding_required_cents = economic_value_cents)))))) NOT VALID;

-- 4. Colunas novas (vazias nas linhas históricas; a guarda garantiu).
ALTER TABLE public.commercial_exclusivity_orders
  DROP COLUMN settlement_terms_id, DROP COLUMN qa_policy, DROP COLUMN mei_in_kind_cents,
  DROP COLUMN qa_in_kind_cents, DROP COLUMN qa_cash_cents, DROP COLUMN cash_adjustment_cents;
ALTER TABLE public.commercial_checkout_intents
  DROP COLUMN settlement_terms_id, DROP COLUMN qa_policy, DROP COLUMN mei_in_kind_cents,
  DROP COLUMN qa_in_kind_cents, DROP COLUMN qa_cash_cents, DROP COLUMN cash_adjustment_cents;
ALTER TABLE public.commercial_instrument_templates DROP COLUMN settlement_model;
ALTER TABLE public.commercial_pricing_rules DROP COLUMN qa_policy;

-- 5. Tabelas e funções novas.
DROP TABLE public.commercial_pricing_activation_log;
DROP TABLE public.commercial_checkout_gate;
DROP FUNCTION public.commercial_settlement_mode_json(public.commercial_settlement_terms);
DROP FUNCTION public.commercial_settlement_terms_for(integer, text, boolean, text);
DROP TABLE public.commercial_settlement_terms;
DROP FUNCTION public.admin_activate_pricing_rule(integer, text);
DROP FUNCTION public.commercial_pricing_activation_preflight(integer);
DROP FUNCTION public.commercial_pricing_activation_log_protect();
DROP FUNCTION public.commercial_settlement_public_v15(integer, text, text, boolean);
DROP FUNCTION public.commercial_order_settlement_check(uuid);
DROP FUNCTION public.cci_liquidar_modalidade_v15();
DROP FUNCTION public.ceo_liquidar_modalidade_v15();
DROP FUNCTION public.ceo_liquidacao_v15_imutavel();
DROP FUNCTION public.ceo_pagamento_confere_snapshot();
DROP FUNCTION public.cp_valor_confere_pedido();
DROP FUNCTION public.ceo_revalidar_reutilizacao_bandeiras();
DROP FUNCTION public.cci_portao_autoatendimento();
DROP FUNCTION public.commercial_checkout_gate_protect();
DROP FUNCTION public.commercial_settlement_terms_protect();

COMMIT;
