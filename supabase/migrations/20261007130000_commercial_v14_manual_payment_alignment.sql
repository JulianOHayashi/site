-- ============================================================================
-- P0-3 (complemento) — ALINHAMENTO DO CAMINHO MANUAL À AUTORIDADE v1.4
--
-- MOTIVO
-- A migration 20261007120000 instituiu a agenda explícita v1.4 como única
-- autoridade de economia contratual. Nela, a remuneração que efetivamente
-- pertence à SmallFlags é
--
--     smallflags_total_remuneration_cents = smallflags_main_fee_cents
--                                         + smallflags_qa_cents
--
-- porque a parcela de QA, embora fique DENTRO de contractual_pool_cents, é
-- definitivamente da SmallFlags — nunca direito do MEI, crédito de usuário,
-- saldo de parceiro, nem uma oitava participação.
--
-- O caminho do PROVEDOR já cobra o valor certo: open_commercial_payment_attempt
-- lê total_monetary_funding_required_cents do instantâneo imutável do pedido,
-- e prov_confirm_commercial_payment exige igualdade exata com ele.
--
-- O caminho MANUAL (admin_confirm_manual_bdflow_payment) continuava comparando
-- com bdflow_due_cents. Sob a V2 isso era correto e idêntico, porque a V2 não
-- separava parcela de QA alguma. Sob a v1.4 passa a subcobrar exatamente
-- smallflags_qa_cents: 12.168 no supermercado e 6.084 no nicho comum.
--
-- O QUE MUDA
-- Apenas o valor ESPERADO na conferência, e apenas para pricing_rule_version
-- >= 3. A regra continua sendo a mesma de sempre — "pago" é o que é devido à
-- SmallFlags, e o pool do usuário NÃO é cobrado nem custodiado — só que sob a
-- v1.4 o devido à SmallFlags inclui a parcela de QA.
--
-- O QUE NÃO MUDA
-- - Pedidos V1 e V2 seguem conferidos contra bdflow_due_cents, byte por byte
--   como sempre foram. Nada é reprecificado, nada é retroativo.
-- - Nenhum valor novo é constante nesta função: ela lê o instantâneo imutável
--   do próprio pedido, exatamente como o caminho do provedor.
-- - Sob o modo cash a SmallFlags continua NÃO custodiando o pool: o esperado é
--   a remuneração da SmallFlags, não total_monetary_funding_required_cents
--   (que no modo cash inclui o pool do usuário).
-- - Assinatura, permissões, SECURITY DEFINER, search_path, idempotência,
--   auditoria e imutabilidade pós-confirmação: intocados.
--
-- SEM push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_confirm_manual_bdflow_payment(
  p_order_id uuid,
  p_amount_cents bigint,
  p_payment_external_ref text DEFAULT NULL::text,
  p_justification text DEFAULT NULL::text)
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
$function$;

-- ============================================================================
-- P0-3 (complemento 2) — O RETORNO DA VENDA MANUAL DEVE SER O QUE FOI GRAVADO
--
-- MOTIVO
-- A autoridade v1.4 é aplicada por trigger BEFORE INSERT (ceo_aplicar_autoridade_v14),
-- de modo que nenhum caminho de escrita — presente ou futuro — consiga gravar
-- número fora da autoridade. Efeito colateral: a função calculava o
-- financiamento ANTES do trigger (v_bdflow + v_cash, semântica V2) e devolvia
-- esse pré-valor ao chamador, enquanto a linha efetivamente gravada já trazia
-- o valor resolvido pela autoridade.
--
-- Sob direct_benefits v1.4 a divergência é exatamente a parcela de QA:
-- a função devolvia 602.300 e a linha gravada exigia 614.468. Um painel
-- administrativo mostraria ao operador um valor que o pedido não cobra.
--
-- CORREÇÃO ESTRUTURAL
-- O RETURNING passa a trazer as colunas de financiamento COMO GRAVADAS, e são
-- elas que alimentam a auditoria e o objeto de retorno. A função deixa de ter
-- opinião própria sobre o financiamento: quem decide é a autoridade, e o
-- retorno apenas relata. Isso extingue a classe inteira de divergência
-- pré/pós-trigger em vez de corrigir um caso.
--
-- O QUE NÃO MUDA
-- - Assinatura, permissões, SECURITY DEFINER, search_path: intocados.
-- - O INSERT continua idêntico; V1/V2 seguem gravando e relatando o mesmo que
--   sempre gravaram e relataram, porque para pricing_rule_version < 3 o
--   trigger não toca em nada.
-- - Nenhuma constante monetária nova nesta função.
-- ============================================================================

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

  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = p_company_id AND status = 'signed';
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
$function$

;
