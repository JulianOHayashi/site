-- ---------------------------------------------------------------------------
-- P0-3 — Autoridade econômica v1.4 (contratos congelados)
--
-- Migration ADITIVA. Nenhuma migration histórica é editada. Nenhuma linha
-- existente é reescrita, reprecificada ou backfilled.
--
-- POR QUE UMA TABELA, E NÃO UM AJUSTE DE FÓRMULA
--
-- Nem a fórmula V1 (bloco + unidade extra) nem o modelo V2 (razão exata sobre
-- o econômico) reproduzem os centavos congelados. Prova aritmética:
--
--   fidelizado V2 = quantidade × 1.299,00
--     supermercado (24) = 31.176,00  — o contrato exige 28.176,00
--     demais       (12) = 15.588,00  — o contrato exige 16.188,00
--
-- E o caso fidelizado exige a MESMA parcela operacional de R$ 4.200,00 para
-- 24 e para 12 unidades. Nenhuma função de quantidade satisfaz 24x = 12x com
-- x > 0: o valor fidelizado não é proporcional à quantidade. Forçar os
-- valores congelados por qualquer fórmula por unidade exigiria centavos
-- fracionários ou alterar o contrato.
--
-- Por isso a v1.4 é uma TABELA DETERMINÍSTICA de centavos inteiros, indexada
-- por pricing_rule_version + categoria comercial + fidelidade. É a forma
-- honesta de representar valores negociados, não calculados.
--
-- LINHAGEM DE VERSÃO — correção do operador
--
-- `pricing_rule_version` JÁ EXISTE em commercial_exclusivity_orders (NOT NULL,
-- FK para commercial_pricing_rules) e em commercial_checkout_intents. Não se
-- cria uma segunda coluna genérica de versão: a v1.4 entra como
-- pricing_rule_version = 3, e o rótulo legal/econômico fica numa coluna
-- própria, contract_economics_version = 'SF-v1.4', porque versão TÉCNICA de
-- regra e versão LEGAL de economia são coisas diferentes e podem divergir.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- 1. Tabela da autoridade: centavos inteiros, sem fórmula
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.commercial_pricing_schedule (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_rule_version      integer NOT NULL
                            REFERENCES public.commercial_pricing_rules(version),
  -- Rótulo legal da economia congelada que originou estes números.
  contract_economics_version text   NOT NULL,
  -- Categoria COMERCIAL, não o código do nicho: o contrato distingue
  -- supermercado (24 unidades) dos demais (12 unidades cada).
  commercial_category       text    NOT NULL,
  fidelized                 boolean NOT NULL,

  economic_value_cents              bigint NOT NULL,
  mei_consideration_cents           bigint NOT NULL,
  smallflags_qa_cents               bigint NOT NULL,
  smallflags_main_fee_cents         bigint NOT NULL,
  -- Persistida, não derivada em tempo de leitura: é um valor contratual que
  -- aparece nos instrumentos, e o CHECK abaixo garante que não divirja.
  smallflags_total_remuneration_cents bigint NOT NULL,

  created_at                timestamptz NOT NULL DEFAULT now(),
  notes                     text,

  CONSTRAINT cps_categoria_valida
    CHECK (commercial_category IN ('supermarket', 'common')),
  CONSTRAINT cps_valores_nao_negativos
    CHECK (economic_value_cents > 0
           AND mei_consideration_cents >= 0
           AND smallflags_qa_cents >= 0
           AND smallflags_main_fee_cents >= 0
           AND smallflags_total_remuneration_cents >= 0),
  -- As duas invariantes centrais do contrato, impostas pelo banco.
  CONSTRAINT cps_invariante_economica
    CHECK (economic_value_cents
           = mei_consideration_cents + smallflags_qa_cents + smallflags_main_fee_cents),
  CONSTRAINT cps_invariante_remuneracao
    CHECK (smallflags_total_remuneration_cents
           = smallflags_qa_cents + smallflags_main_fee_cents),
  CONSTRAINT cps_chave_unica
    UNIQUE (pricing_rule_version, commercial_category, fidelized)
);

COMMENT ON TABLE public.commercial_pricing_schedule IS
  'Centavos contratuais exatos por versao de regra de preco, categoria '
  'comercial e fidelidade. Tabela, nao formula: os valores v1.4 foram '
  'negociados e nao sao reproduziveis por nenhuma funcao de quantidade.';
COMMENT ON COLUMN public.commercial_pricing_schedule.smallflags_qa_cents IS
  'Parcela QA, propria da SmallFlags. Nunca e contraprestacao do MEI, credito '
  'de usuario, saldo da parceira nem oitava participacao.';
COMMENT ON COLUMN public.commercial_pricing_schedule.contract_economics_version IS
  'Rotulo legal da economia congelada (ex.: SF-v1.4), distinto da versao '
  'tecnica da regra de preco.';

ALTER TABLE public.commercial_pricing_schedule ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_pricing_schedule FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commercial_pricing_schedule TO service_role;

-- ===========================================================================
-- 2. Modelo de precisão 'explicit_schedule'
-- ===========================================================================
--
-- O CHECK anterior admitia só 'basis_points' e 'exact_ratio'. É ampliado,
-- preservando integralmente as duas regras existentes.

ALTER TABLE public.commercial_pricing_rules
  DROP CONSTRAINT cpr_modelo_precisao_valido;
ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_modelo_precisao_valido
  CHECK (pool_precision_model IN ('basis_points', 'exact_ratio', 'explicit_schedule'));

ALTER TABLE public.commercial_pricing_rules
  DROP CONSTRAINT cpr_modelo_coerente;
ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_modelo_coerente
  CHECK (
    (pool_precision_model = 'basis_points'
      AND pool_bps_supermarket IS NOT NULL AND pool_bps_common IS NOT NULL)
    OR (pool_precision_model = 'exact_ratio'
      AND pool_bps_supermarket IS NULL AND pool_bps_common IS NULL)
    -- No modelo de tabela, os campos de fórmula não participam do cálculo.
    OR (pool_precision_model = 'explicit_schedule'
      AND pool_bps_supermarket IS NULL AND pool_bps_common IS NULL)
  );

-- ===========================================================================
-- 3. pricing_rule_version = 3 é a v1.4, com os oito valores congelados
-- ===========================================================================
--
-- Fonte: SMALLFLAGS_SEIS_CONTRATOS_PRESENCIAIS_SF-0001_A_SF-0006_MINUTA_v1_4,
-- SHA-256 03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73,
-- conferido contra o manifesto oficial de congelamento.

DO $v14$
BEGIN
  IF EXISTS (SELECT 1 FROM public.commercial_pricing_rules WHERE version = 3) THEN
    RAISE NOTICE 'pricing_rule_version 3 ja existe: nada a fazer';
    RETURN;
  END IF;

  -- A versão anterior deixa de ser a ativa, mas permanece legível e
  -- reproduzível por version explícita.
  UPDATE public.commercial_pricing_rules
     SET status = 'superseded'
   WHERE status = 'active';

  INSERT INTO public.commercial_pricing_rules
    (version, status, block_units, block_price_cents, extra_unit_price_cents,
     fidelized_unit_price_cents, pool_bps_supermarket, pool_bps_common,
     pool_precision_model, effective_from, notes)
  VALUES
    (3, 'active',
     -- Campos de fórmula preservados por compatibilidade de schema; NÃO são
     -- usados no modelo de tabela. Zerá-los produziria um preço falso caso
     -- alguém os lesse por engano, então repetem os valores herdados.
     12, 1999900, 129900, 129900,
     NULL, NULL,
     'explicit_schedule', now(),
     'SF-v1.4: economia congelada dos contratos v1.4. Valores negociados em '
     'centavos inteiros, nao reproduziveis por formula por unidade.');

  INSERT INTO public.commercial_pricing_schedule
    (pricing_rule_version, contract_economics_version, commercial_category,
     fidelized, economic_value_cents, mei_consideration_cents,
     smallflags_qa_cents, smallflags_main_fee_cents,
     smallflags_total_remuneration_cents, notes)
  VALUES
    (3, 'SF-v1.4', 'supermarket', false, 2999900, 2385432, 12168, 602300, 614468,
     'v1.4 supermercado 24 unidades, nao fidelizado'),
    (3, 'SF-v1.4', 'common',      false, 1999900, 1192716,  6084, 801100, 807184,
     'v1.4 demais nichos 12 unidades, nao fidelizado'),
    (3, 'SF-v1.4', 'supermarket', true,  2817600, 2385432, 12168, 420000, 432168,
     'v1.4 supermercado 24 unidades, fidelizado'),
    (3, 'SF-v1.4', 'common',      true,  1618800, 1192716,  6084, 420000, 426084,
     'v1.4 demais nichos 12 unidades, fidelizado');
END
$v14$;

-- ===========================================================================
-- 4. Cálculo: UMA função, mesma assinatura, nova fonte quando v1.4
-- ===========================================================================
--
-- Manter uma única função é o que garante que interface, intenção de
-- checkout, venda manual, finalização e preço público resolvam do mesmo
-- lugar. Os ramos V1 e V2 permanecem palavra por palavra como estavam.

CREATE OR REPLACE FUNCTION public.calculate_niche_contract_pricing(
  p_niche_code text,
  p_fidelized boolean,
  p_pricing_version integer DEFAULT NULL::integer
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
    SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE status = 'active';
  ELSE
    SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE version = p_pricing_version;
  END IF;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  SELECT contracted_quantity INTO v_qty
    FROM public.commercial_niches WHERE code = p_niche_code AND is_active;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_niche');
  END IF;

  -- Seis posições canônicas: supermercado usa a matriz de supermercado; os
  -- outros cinco usam a comum. OUTROS não é categorizado aqui de propósito —
  -- a fonte congelada não estabelece sua categoria de preço.
  v_cat := CASE WHEN p_niche_code = 'supermarket' THEN 'supermarket' ELSE 'common' END;

  -- -------------------------------------------------------------------------
  -- v1.4: tabela determinística. Falha fechada se a combinação não existir,
  -- em vez de cair numa fórmula que produziria um valor não contratado.
  -- -------------------------------------------------------------------------
  IF v_rule.pool_precision_model = 'explicit_schedule' THEN
    SELECT * INTO v_sched FROM public.commercial_pricing_schedule
      WHERE pricing_rule_version = v_rule.version
        AND commercial_category = v_cat
        AND fidelized = p_fidelized;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_schedule_missing',
        'pricing_rule_version', v_rule.version, 'commercial_category', v_cat,
        'fidelized', p_fidelized);
    END IF;

    -- CONTRATO DE RETORNO PRESERVADO. As chaves abaixo sao as mesmas que os
    -- consumidores ja leem (create_commercial_checkout_intent,
    -- admin_register_manual_commercial_order, preco publico). A v1.4 apenas
    -- ACRESCENTA a decomposicao; renomear qualquer chave existente quebraria
    -- os consumidores, inclusive payment_method, que e NOT NULL no destino.
    RETURN pg_catalog.jsonb_build_object(
      'ok', true,
      'pricing_rule_version', v_rule.version,
      'pool_precision_model', v_rule.pool_precision_model,
      'niche_code', p_niche_code,
      'niche_category', v_cat,
      'nominal_quantity', v_qty,
      'fidelized', p_fidelized,
      'currency', 'BRL',
      -- Sem pontos-base no modelo de tabela: nao ha razao honesta a declarar.
      'pool_bps', NULL::integer,
      'display_pool_percent', NULL::text,
      'display_bdflow_percent', NULL::text,
      'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
      -- Acrescimos da v1.4.
      'contract_economics_version', v_sched.contract_economics_version,
      'economic_value_cents', v_sched.economic_value_cents,
      -- Campos de compatibilidade preservados, de modo que
      -- economic_value_cents = contractual_pool_cents + bdflow_due_cents
      -- continue valendo. ATENÇÃO: sob v1.4, contractual_pool_cents NÃO é
      -- "dinheiro devido aos MEIs" — ele contém a QA, que é da SmallFlags.
      'contractual_pool_cents',
        v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents,
      'bdflow_due_cents', v_sched.smallflags_main_fee_cents,
      -- Decomposição explícita da v1.4.
      'mei_consideration_cents', v_sched.mei_consideration_cents,
      'smallflags_qa_cents', v_sched.smallflags_qa_cents,
      'smallflags_main_fee_cents', v_sched.smallflags_main_fee_cents,
      'smallflags_total_remuneration_cents', v_sched.smallflags_total_remuneration_cents
    );
  END IF;

  -- -------------------------------------------------------------------------
  -- V1 e V2: comportamento original, intacto.
  -- -------------------------------------------------------------------------
  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  IF v_rule.pool_precision_model = 'exact_ratio' THEN
    SELECT * INTO v_ratio FROM public.commercial_pool_share_ratios
      WHERE pricing_rule_version = v_rule.version AND niche_category = v_cat;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pool_ratio_unavailable');
    END IF;
    v_pool := (v_economic * v_ratio.pool_numerator) / v_ratio.pool_denominator;
    v_disp_pool := v_ratio.display_pool_percent;
    v_disp_bdf  := v_ratio.display_bdflow_percent;
  ELSE
    v_bps := CASE WHEN v_cat = 'supermarket'
                  THEN v_rule.pool_bps_supermarket ELSE v_rule.pool_bps_common END;
    v_pool := (v_economic * v_bps) / 10000;
  END IF;

  -- Contrato V1/V2 reproduzido LITERALMENTE, chave por chave.
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
    'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END);
END;
$$;

-- ===========================================================================
-- 5. Campos de snapshot v1.4 no pedido
-- ===========================================================================
--
-- NÃO se cria pricing_version: a linhagem técnica é a pricing_rule_version
-- que já existe. Acrescenta-se o rótulo legal e a decomposição econômica.
--
-- Todos nullable: linhas V1/V2 históricas permanecem NULL, sem backfill de
-- fatos jurídicos inventados.

ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS contract_economics_version          text,
  ADD COLUMN IF NOT EXISTS mei_consideration_cents             bigint,
  ADD COLUMN IF NOT EXISTS smallflags_qa_cents                 bigint,
  ADD COLUMN IF NOT EXISTS smallflags_main_fee_cents           bigint,
  ADD COLUMN IF NOT EXISTS smallflags_total_remuneration_cents bigint,
  -- Dinheiro de TERCEIROS destinado aos MEIs. Campo novo de propósito:
  -- `cash_user_pool_funding_cents` tem semântica V2 e não é reinterpretado.
  ADD COLUMN IF NOT EXISTS mei_cash_funding_cents              bigint;

COMMENT ON COLUMN public.commercial_exclusivity_orders.contract_economics_version IS
  'Rotulo legal da economia congelada (ex.: SF-v1.4). NULL em pedidos '
  'historicos V1/V2, que seguem a semantica original.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.bdflow_due_cents IS
  'Parcela operacional PRINCIPAL da SmallFlags, SEM a QA. Sob v1.4 a '
  'remuneracao total da SmallFlags e smallflags_total_remuneration_cents.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.contractual_pool_cents IS
  'Compatibilidade: economic_value_cents = contractual_pool_cents + '
  'bdflow_due_cents. Sob v1.4 NAO significa dinheiro devido apenas aos MEIs: '
  'contem a parcela QA, que pertence a SmallFlags.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.mei_cash_funding_cents IS
  'Dinheiro de terceiros destinado aos MEIs na modalidade dinheiro. Igual a '
  'mei_consideration_cents em cash; zero em beneficio direto, onde a '
  'contraprestacao e entregue como beneficio, nao em dinheiro.';

-- ---------------------------------------------------------------------------
-- 5.1 CHECK de financiamento V2: preservado, com aplicabilidade por VERSÃO
-- ---------------------------------------------------------------------------
--
-- A regra não é removida nem enfraquecida: passa a declarar que vale para
-- pricing_rule_version <= 2, isto é, exatamente os pedidos V1/V2. Sob v1.4
-- ela seria falsa, porque exige que o benefício direto pague apenas
-- bdflow_due_cents, enquanto o contrato congelado exige também a QA.

ALTER TABLE public.commercial_exclusivity_orders
  DROP CONSTRAINT ceo_financiamento_v2_coerente;

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_financiamento_v2_coerente
  CHECK (
    pricing_rule_version >= 3     -- v1.4 e posteriores: ver o CHECK abaixo
    OR benefit_settlement_mode IS NULL
    OR (benefit_settlement_mode = 'direct_benefits'
        AND cash_user_pool_funding_cents = 0
        AND total_monetary_funding_required_cents = bdflow_due_cents)
    OR (benefit_settlement_mode = 'cash'
        AND cash_user_pool_funding_cents = contractual_pool_cents
        AND total_monetary_funding_required_cents = bdflow_due_cents + contractual_pool_cents)
  );

COMMENT ON CONSTRAINT ceo_financiamento_v2_coerente
  ON public.commercial_exclusivity_orders IS
  'Coerencia de financiamento V1/V2, aplicavel a pricing_rule_version <= 2. '
  'A v1.4 tem regra propria em ceo_financiamento_v14_coerente.';

-- ---------------------------------------------------------------------------
-- 5.2 CHECK de financiamento v1.4
-- ---------------------------------------------------------------------------
--
-- BENEFÍCIO DIRETO: a parceira entrega a contraprestação do MEI como benefício
-- utilizável e paga em dinheiro a remuneração INTEIRA da SmallFlags, QA
-- inclusa. Nenhum dinheiro de terceiros transita.
--
-- DINHEIRO: a parceira paga o econômico integral, e o dinheiro de terceiros
-- destinado aos MEIs fica distinguível da remuneração da SmallFlags.
--
-- A QA é sempre remuneração monetária da SmallFlags e nunca vira financiamento
-- do MEI — é o que mei_cash_funding_cents = mei_consideration_cents garante,
-- em vez de mei_consideration_cents + smallflags_qa_cents.
--
-- NOT VALID: nenhuma linha histórica é revalidada; pedidos v1.4 nascem
-- conformes.

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_financiamento_v14_coerente
  CHECK (
    pricing_rule_version < 3
    OR benefit_settlement_mode IS NULL
    OR (
      -- Decomposição obrigatória sob v1.4.
      mei_consideration_cents IS NOT NULL
      AND smallflags_qa_cents IS NOT NULL
      AND smallflags_main_fee_cents IS NOT NULL
      AND smallflags_total_remuneration_cents IS NOT NULL
      AND mei_cash_funding_cents IS NOT NULL
      AND smallflags_total_remuneration_cents
          = smallflags_qa_cents + smallflags_main_fee_cents
      AND economic_value_cents
          = mei_consideration_cents + smallflags_qa_cents + smallflags_main_fee_cents
      -- Compatibilidade com o snapshot herdado.
      AND contractual_pool_cents = mei_consideration_cents + smallflags_qa_cents
      AND bdflow_due_cents = smallflags_main_fee_cents
      AND (
        (benefit_settlement_mode = 'direct_benefits'
          AND mei_cash_funding_cents = 0
          AND total_monetary_funding_required_cents
              = smallflags_total_remuneration_cents)
        OR
        (benefit_settlement_mode = 'cash'
          -- A QA NÃO entra aqui: ela é remuneração, não dinheiro de terceiros.
          AND mei_cash_funding_cents = mei_consideration_cents
          AND total_monetary_funding_required_cents = economic_value_cents)
      )
    )
  ) NOT VALID;

COMMENT ON CONSTRAINT ceo_financiamento_v14_coerente
  ON public.commercial_exclusivity_orders IS
  'Coerencia economica e de financiamento sob a autoridade v1.4 '
  '(pricing_rule_version >= 3).';

-- ---------------------------------------------------------------------------
-- 5.3 Imutabilidade do snapshot econômico v1.4
-- ---------------------------------------------------------------------------
--
-- O trigger `pedido_imutavel` já protege economic_value_cents,
-- contractual_pool_cents, bdflow_due_cents e pricing_rule_version. Os campos
-- novos precisam da mesma proteção, acrescentada sem reescrever o trigger
-- histórico.

CREATE OR REPLACE FUNCTION public.ceo_snapshot_v14_imutavel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF NEW.contract_economics_version          IS DISTINCT FROM OLD.contract_economics_version
  OR NEW.mei_consideration_cents             IS DISTINCT FROM OLD.mei_consideration_cents
  OR NEW.smallflags_qa_cents                 IS DISTINCT FROM OLD.smallflags_qa_cents
  OR NEW.smallflags_main_fee_cents           IS DISTINCT FROM OLD.smallflags_main_fee_cents
  OR NEW.smallflags_total_remuneration_cents IS DISTINCT FROM OLD.smallflags_total_remuneration_cents
  OR NEW.mei_cash_funding_cents              IS DISTINCT FROM OLD.mei_cash_funding_cents THEN
    -- Só bloqueia quando já havia snapshot: preencher de NULL uma única vez
    -- é a própria criação do snapshot, não uma reescrita.
    IF OLD.contract_economics_version IS NOT NULL THEN
      RAISE EXCEPTION
        'pedido_imutavel: snapshot economico v1.4 e imutavel (id=%).', OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ceo_snapshot_v14_imutavel ON public.commercial_exclusivity_orders;
CREATE TRIGGER ceo_snapshot_v14_imutavel
  BEFORE UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_snapshot_v14_imutavel();

-- ===========================================================================
-- 6. Intenção de checkout: mesma linhagem de versão
-- ===========================================================================
--
-- A intenção já carrega pricing_rule_version. Acrescenta-se o rótulo legal e
-- a decomposição, para que o pedido finalizado copie o que a intenção
-- congelou, em vez de recalcular.

ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN IF NOT EXISTS contract_economics_version          text,
  ADD COLUMN IF NOT EXISTS mei_consideration_cents             bigint,
  ADD COLUMN IF NOT EXISTS smallflags_qa_cents                 bigint,
  ADD COLUMN IF NOT EXISTS smallflags_main_fee_cents           bigint,
  ADD COLUMN IF NOT EXISTS smallflags_total_remuneration_cents bigint,
  ADD COLUMN IF NOT EXISTS mei_cash_funding_cents              bigint;

COMMENT ON COLUMN public.commercial_checkout_intents.contract_economics_version IS
  'Rotulo legal da economia congelada na reserva. NULL em intencoes V1/V2.';

-- ===========================================================================
-- 7. Propagação da autoridade para TODO caminho de gravação
-- ===========================================================================
--
-- Os consumidores auditados — create_commercial_checkout_intent,
-- admin_register_manual_commercial_order, finalize_commercial_order_from_intent,
-- get_public_niche_pricing, get_public_formation_economics — já derivam do
-- JSON de calculate_niche_contract_pricing ou copiam o snapshot. Nenhum
-- duplica constante.
--
-- Ainda assim, eles montam `total_monetary_funding_required_cents` pela regra
-- V2 (bdflow_due + cash_user_pool). Sob v1.4 essa regra é outra. Em vez de
-- reescrever três funções longas — e deixar que um caminho futuro escape —
-- um trigger resolve da MESMA autoridade no momento da inserção.
--
-- Efeito: existe uma única autoridade econômica no servidor, e é
-- estruturalmente impossível um pedido v1.4 nascer com números que não
-- venham dela.

CREATE OR REPLACE FUNCTION public.ceo_aplicar_autoridade_v14()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
$$;

DROP TRIGGER IF EXISTS ceo_aplicar_autoridade_v14 ON public.commercial_exclusivity_orders;
CREATE TRIGGER ceo_aplicar_autoridade_v14
  BEFORE INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_aplicar_autoridade_v14();

-- Mesma resolução para a intenção de checkout, de modo que o que a reserva
-- congela já seja o que o pedido vai copiar.
CREATE OR REPLACE FUNCTION public.cci_aplicar_autoridade_v14()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
$$;

DROP TRIGGER IF EXISTS cci_aplicar_autoridade_v14 ON public.commercial_checkout_intents;
CREATE TRIGGER cci_aplicar_autoridade_v14
  BEFORE INSERT ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.cci_aplicar_autoridade_v14();

-- ===========================================================================
-- 8. CHECKs da intenção de checkout, escopados por versão
-- ===========================================================================
--
-- `cci_total_monetario` e `cci_financiamento_coerente` codificam a regra V2:
-- o total monetário é a parcela operacional mais o pool em dinheiro. Sob v1.4
-- a regra é outra — em benefício direto o total é a remuneração INTEIRA da
-- SmallFlags, QA inclusa, e em dinheiro é o econômico integral.
--
-- As regras V2 não são removidas nem enfraquecidas: passam a declarar que
-- valem para pricing_rule_version <= 2, e a v1.4 ganha regra própria.
-- `cci_invariante_economica` continua valendo nas duas versões, porque sob
-- v1.4 user_pool = MEI + QA e bdflow_ops = parcela principal, de modo que a
-- soma continua sendo o econômico.

ALTER TABLE public.commercial_checkout_intents
  DROP CONSTRAINT cci_total_monetario;
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_total_monetario
  CHECK (
    pricing_rule_version >= 3
    OR total_monetary_funding_required_cents
       = bdflow_ops_investment_cents + cash_user_pool_funding_cents
  );

ALTER TABLE public.commercial_checkout_intents
  DROP CONSTRAINT cci_financiamento_coerente;
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_financiamento_coerente
  CHECK (
    pricing_rule_version >= 3
    OR (benefit_settlement_mode = 'direct_benefits' AND cash_user_pool_funding_cents = 0)
    OR (benefit_settlement_mode = 'cash' AND cash_user_pool_funding_cents = user_pool_cents)
  );

COMMENT ON CONSTRAINT cci_total_monetario ON public.commercial_checkout_intents IS
  'Regra V1/V2, aplicavel a pricing_rule_version <= 2. A v1.4 tem regra '
  'propria em cci_financiamento_v14_coerente.';

ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_financiamento_v14_coerente
  CHECK (
    pricing_rule_version < 3
    OR (
      mei_consideration_cents IS NOT NULL
      AND smallflags_qa_cents IS NOT NULL
      AND smallflags_main_fee_cents IS NOT NULL
      AND smallflags_total_remuneration_cents IS NOT NULL
      AND mei_cash_funding_cents IS NOT NULL
      AND smallflags_total_remuneration_cents
          = smallflags_qa_cents + smallflags_main_fee_cents
      AND economic_value_cents
          = mei_consideration_cents + smallflags_qa_cents + smallflags_main_fee_cents
      AND user_pool_cents = mei_consideration_cents + smallflags_qa_cents
      AND bdflow_ops_investment_cents = smallflags_main_fee_cents
      AND (
        (benefit_settlement_mode = 'direct_benefits'
          AND mei_cash_funding_cents = 0
          AND cash_user_pool_funding_cents = 0
          AND total_monetary_funding_required_cents
              = smallflags_total_remuneration_cents)
        OR
        (benefit_settlement_mode = 'cash'
          AND mei_cash_funding_cents = mei_consideration_cents
          AND cash_user_pool_funding_cents = user_pool_cents
          AND total_monetary_funding_required_cents = economic_value_cents)
      )
    )
  ) NOT VALID;
