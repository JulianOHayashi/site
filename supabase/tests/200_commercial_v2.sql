-- ============================================================================
-- 200_commercial_v2.sql — TESTES SQL DO COMERCIAL V2
--
-- ESTADO: ESCRITO, NÃO EXECUTADO.
-- Nenhum PostgreSQL esteve disponível no ambiente onde este arquivo foi
-- redigido: sem psql, sem cluster, sem Supabase CLI, sem Docker. Portanto
--
--   COMMERCIAL_V2_SQL_EXECUTION=NOT_RUN_ENVIRONMENT_BLOCKED
--
-- Nenhuma asserção aqui foi observada passando. Ler o arquivo não é executá-lo.
-- Ao rodar contra PostgreSQL 17.6, qualquer RAISE EXCEPTION aborta a
-- transação e reprova a suíte.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Versionamento da política de precificação
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_ativas integer; v_v1 text; v_v2 text;
BEGIN
  SELECT count(*) INTO v_ativas
    FROM public.commercial_pricing_rules WHERE status = 'active';
  IF v_ativas <> 1 THEN
    RAISE EXCEPTION 'esperado exatamente 1 regra ativa, obtido %', v_ativas;
  END IF;

  SELECT status INTO v_v1 FROM public.commercial_pricing_rules WHERE version = 1;
  IF v_v1 IS DISTINCT FROM 'superseded' THEN
    RAISE EXCEPTION 'V1 deveria estar superseded, esta %', v_v1;
  END IF;

  SELECT status INTO v_v2 FROM public.commercial_pricing_rules WHERE version = 2;
  IF v_v2 IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'V2 deveria estar active, esta %', v_v2;
  END IF;
END $$;

-- A V1 preserva os pontos-base reais; a V2 não os inventa.
DO $$
DECLARE r public.commercial_pricing_rules%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.commercial_pricing_rules WHERE version = 1;
  IF r.pool_bps_supermarket <> 7500 OR r.pool_bps_common <> 7000 THEN
    RAISE EXCEPTION 'pontos-base historicos da V1 foram alterados';
  END IF;
  IF r.pool_precision_model <> 'basis_points' THEN
    RAISE EXCEPTION 'V1 deveria continuar em basis_points';
  END IF;

  SELECT * INTO r FROM public.commercial_pricing_rules WHERE version = 2;
  IF r.pool_bps_supermarket IS NOT NULL OR r.pool_bps_common IS NOT NULL THEN
    RAISE EXCEPTION 'V2 nao pode ter pontos-base: seria autoridade falsa';
  END IF;
  IF r.pool_precision_model <> 'exact_ratio' THEN
    RAISE EXCEPTION 'V2 deveria usar exact_ratio';
  END IF;
  IF r.block_units <> 12 THEN
    RAISE EXCEPTION 'bloco fundador deve ser 12 unidades, obtido %', r.block_units;
  END IF;
END $$;

-- O CHECK de coerência recusa mistura de modelos.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.commercial_pricing_rules
      (version, status, block_units, block_price_cents, extra_unit_price_cents,
       fidelized_unit_price_cents, pool_bps_supermarket, pool_bps_common,
       pool_precision_model)
    VALUES (99, 'draft', 12, 1999900, 129900, 129900, 7178, 6678, 'exact_ratio');
    RAISE EXCEPTION 'regra exact_ratio com pontos-base deveria ter sido recusada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Centavos exatos aprovados — não fidelizado
-- ----------------------------------------------------------------------------
DO $$
DECLARE p jsonb;
BEGIN
  p := public.calculate_niche_contract_pricing('supermarket', false);
  IF (p->>'economic_value_cents')::bigint <> 3558700 THEN
    RAISE EXCEPTION 'supermercado economico: esperado 3558700, obtido %',
      p->>'economic_value_cents';
  END IF;
  IF (p->>'contractual_pool_cents')::bigint <> 2554305 THEN
    RAISE EXCEPTION 'supermercado pool: esperado 2554305, obtido %',
      p->>'contractual_pool_cents';
  END IF;
  IF (p->>'bdflow_due_cents')::bigint <> 1004395 THEN
    RAISE EXCEPTION 'supermercado BDFlow: esperado 1004395, obtido %',
      p->>'bdflow_due_cents';
  END IF;
  IF p->>'pool_bps' IS NOT NULL THEN
    RAISE EXCEPTION 'V2 nao pode devolver pontos-base';
  END IF;
  IF p->>'payment_method' <> 'pix' THEN
    RAISE EXCEPTION 'nao fidelizado deve derivar pix, obtido %', p->>'payment_method';
  END IF;

  p := public.calculate_niche_contract_pricing('pharmacy', false);
  IF (p->>'economic_value_cents')::bigint <> 1999900
     OR (p->>'contractual_pool_cents')::bigint <> 1335459
     OR (p->>'bdflow_due_cents')::bigint <> 664441 THEN
    RAISE EXCEPTION 'centavos do nicho comum divergem do aprovado';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Centavos fidelizados derivados por piso da mesma razão
-- ----------------------------------------------------------------------------
DO $$
DECLARE p jsonb;
BEGIN
  p := public.calculate_niche_contract_pricing('supermarket', true);
  IF (p->>'economic_value_cents')::bigint <> 3117600
     OR (p->>'contractual_pool_cents')::bigint <> 2237699
     OR (p->>'bdflow_due_cents')::bigint <> 879901 THEN
    RAISE EXCEPTION 'supermercado fidelizado diverge: % / % / %',
      p->>'economic_value_cents', p->>'contractual_pool_cents', p->>'bdflow_due_cents';
  END IF;
  IF p->>'payment_method' <> 'credit_card' THEN
    RAISE EXCEPTION 'fidelizado deve derivar credit_card';
  END IF;

  p := public.calculate_niche_contract_pricing('pharmacy', true);
  IF (p->>'economic_value_cents')::bigint <> 1558800
     OR (p->>'contractual_pool_cents')::bigint <> 1040908
     OR (p->>'bdflow_due_cents')::bigint <> 517892 THEN
    RAISE EXCEPTION 'comum fidelizado diverge do aprovado';
  END IF;
END $$;

-- Invariante econômica em toda saída, e o pool nunca excede a razão.
DO $$
DECLARE n record; f boolean; p jsonb; num bigint; den bigint; cat text;
BEGIN
  FOR n IN SELECT code FROM public.commercial_niches WHERE is_active LOOP
    FOREACH f IN ARRAY ARRAY[false, true] LOOP
      p := public.calculate_niche_contract_pricing(n.code, f);
      IF (p->>'economic_value_cents')::bigint
         <> (p->>'contractual_pool_cents')::bigint + (p->>'bdflow_due_cents')::bigint THEN
        RAISE EXCEPTION 'invariante economica violada em % fidelizado=%', n.code, f;
      END IF;
      cat := CASE WHEN n.code = 'supermarket' THEN 'supermarket' ELSE 'common' END;
      SELECT pool_numerator, pool_denominator INTO num, den
        FROM public.commercial_pool_share_ratios
       WHERE pricing_rule_version = 2 AND niche_category = cat;
      IF (p->>'contractual_pool_cents')::bigint * den
         > (p->>'economic_value_cents')::bigint * num THEN
        RAISE EXCEPTION 'pool excedeu a razao da categoria em %', n.code;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 4. Agregado da formação
-- ----------------------------------------------------------------------------
DO $$
DECLARE f jsonb;
BEGIN
  f := public.get_public_formation_economics();
  IF (f->>'economic_value_cents')::bigint <> 13558200
     OR (f->>'user_pool_cents')::bigint <> 9231600
     OR (f->>'bdflow_ops_investment_cents')::bigint <> 4326600 THEN
    RAISE EXCEPTION 'totais da formacao divergem: % / % / %',
      f->>'economic_value_cents', f->>'user_pool_cents', f->>'bdflow_ops_investment_cents';
  END IF;
  IF (f->>'participant_target')::int <> 84 THEN
    RAISE EXCEPTION 'alvo de participantes deve ser 84';
  END IF;
  IF (f->>'per_complete_user_base_cents')::bigint <> 109900
     OR (f->>'pool_remainder_cents')::bigint <> 0 THEN
    RAISE EXCEPTION 'valor por usuario completo diverge de 109900';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Semântica de pool_bps por versão no snapshot de pedido
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_ok boolean;
BEGIN
  -- Linha V1 sem pontos-base deve ser recusada.
  SELECT true INTO v_ok FROM pg_catalog.pg_constraint
   WHERE conname = 'ceo_pool_bps_por_versao';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHECK ceo_pool_bps_por_versao ausente';
  END IF;

  SELECT true INTO v_ok FROM pg_catalog.pg_constraint
   WHERE conname = 'ceo_invariante_economica';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHECK ceo_invariante_economica ausente';
  END IF;

  SELECT true INTO v_ok FROM pg_catalog.pg_constraint
   WHERE conname = 'ceo_financiamento_v2_coerente';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CHECK ceo_financiamento_v2_coerente ausente';
  END IF;
END $$;

-- Pedidos V1 históricos não podem ter sido recalculados.
DO $$
DECLARE v_ruins integer;
BEGIN
  SELECT count(*) INTO v_ruins FROM public.commercial_exclusivity_orders
   WHERE pricing_rule_version = 1 AND pool_bps IS NULL;
  IF v_ruins > 0 THEN
    RAISE EXCEPTION '% pedidos V1 perderam pool_bps', v_ruins;
  END IF;
  SELECT count(*) INTO v_ruins FROM public.commercial_exclusivity_orders
   WHERE pricing_rule_version = 1 AND benefit_settlement_mode IS NOT NULL;
  IF v_ruins > 0 THEN
    RAISE EXCEPTION '% pedidos V1 receberam modo de liquidacao inventado', v_ruins;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 6. Intenção de checkout: valores válidos e invariantes
-- ----------------------------------------------------------------------------
DO $$
DECLARE c text;
BEGIN
  FOREACH c IN ARRAY ARRAY['cci_modo_valido','cci_metodo_deriva_da_fidelidade',
                           'cci_invariante_economica','cci_financiamento_coerente',
                           'cci_total_monetario'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = c) THEN
      RAISE EXCEPTION 'CHECK % ausente na intencao de checkout', c;
    END IF;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 7. Contrato da venda manual — assinatura única e sem parâmetro de valor
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_n integer; v_args text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'admin_register_manual_commercial_order';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'esperada UMA assinatura de venda manual, obtidas %', v_n;
  END IF;

  SELECT pg_catalog.pg_get_function_arguments(p.oid) INTO v_args
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'admin_register_manual_commercial_order';
  IF v_args !~ 'p_benefit_settlement_mode' THEN
    RAISE EXCEPTION 'venda manual sem parametro de modo de liquidacao';
  END IF;
  -- Nenhum parâmetro de valor monetário: o servidor deriva tudo.
  IF v_args ~* '(cents|price|preco|pool|amount)' THEN
    RAISE EXCEPTION 'venda manual aceita valor do chamador: %', v_args;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 8. Confirmação de financiamento V2 — existência, segurança e V1 preservada
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_def boolean; v_cfg text[];
BEGIN
  SELECT p.prosecdef, p.proconfig INTO v_def, v_cfg
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_commercial_funding';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_confirm_commercial_funding ausente';
  END IF;
  IF NOT v_def THEN
    RAISE EXCEPTION 'confirmacao de financiamento deveria ser SECURITY DEFINER';
  END IF;
  IF v_cfg IS NULL OR NOT ('search_path=pg_catalog' = ANY (v_cfg)) THEN
    RAISE EXCEPTION 'search_path nao fixado na confirmacao de financiamento';
  END IF;

  -- A RPC V1 continua existindo: pedidos históricos usam a semântica deles.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_manual_bdflow_payment') THEN
    RAISE EXCEPTION 'RPC V1 de confirmacao foi removida; historico perde caminho';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 9. Fronteiras de privilégio
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_f text;
BEGIN
  -- anon não executa nada que crie ou confirme compromisso comercial.
  FOREACH v_f IN ARRAY ARRAY['create_commercial_checkout_intent',
                             'admin_register_manual_commercial_order',
                             'admin_confirm_commercial_funding'] LOOP
    IF pg_catalog.has_function_privilege('anon',
         (SELECT p.oid FROM pg_catalog.pg_proc p
            JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = v_f LIMIT 1), 'EXECUTE') THEN
      RAISE EXCEPTION 'anon pode executar %', v_f;
    END IF;
  END LOOP;

  -- Escrita direta nas tabelas comerciais protegidas não é concedida.
  IF pg_catalog.has_table_privilege('anon', 'public.commercial_checkout_intents', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.commercial_checkout_intents', 'INSERT')
     OR pg_catalog.has_table_privilege('authenticated', 'public.commercial_checkout_intents', 'UPDATE') THEN
    RAISE EXCEPTION 'escrita direta na intencao de checkout esta concedida';
  END IF;

  IF pg_catalog.has_table_privilege('anon', 'public.commercial_pool_share_ratios', 'SELECT') THEN
    RAISE EXCEPTION 'anon le a tabela de razoes diretamente';
  END IF;

  IF NOT (SELECT relrowsecurity FROM pg_catalog.pg_class
           WHERE oid = 'public.commercial_checkout_intents'::regclass) THEN
    RAISE EXCEPTION 'RLS desabilitada na intencao de checkout';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 10. Imutabilidade do instantâneo fora de 'draft'
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                  WHERE tgname = 'cci_proteger_snapshot_trg') THEN
    RAISE EXCEPTION 'trigger de imutabilidade do snapshot ausente';
  END IF;
END $$;

ROLLBACK;

-- ============================================================================
-- FIM. Nenhuma asserção acima foi executada no ambiente de redação.
--   COMMERCIAL_V2_SQL_EXECUTION=NOT_RUN_ENVIRONMENT_BLOCKED
--   COMMERCIAL_V2_MIGRATION_PARSE=NOT_RUN_ENVIRONMENT_BLOCKED
--   COMMERCIAL_V2_SQL_REGRESSION=NOT_RUN_ENVIRONMENT_BLOCKED
-- ============================================================================
