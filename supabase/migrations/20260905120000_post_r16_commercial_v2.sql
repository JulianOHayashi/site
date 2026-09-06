-- ============================================================================
-- POST-R16 / COMERCIAL V2 — Política de pool exata em centavos, forma de
-- disponibilização de benefícios e intenção comercial neutra de provedor.
--
-- ADITIVA. Nenhum dos 27 arquivos de migration anteriores é editado, nenhuma
-- linha histórica é recalculada, e a versão 1 continua legível e válida para
-- os pedidos que a usaram.
--
-- ----------------------------------------------------------------------------
-- POR QUE pool_bps NÃO SERVE PARA A V2
--
-- A V1 guarda a participação do pool em pontos-base inteiros (7500 / 7000).
-- Os valores aprovados da V2 não são expressáveis assim:
--
--   supermercado  2.554.305 / 3.558.700 = 71,7763508...%
--   comum         1.335.459 / 1.999.900 = 66,7762888...%
--
-- Arredondar para 7178/6678 produziria centavos diferentes dos aprovados.
-- Chamar isso de "a V2" seria falso. A V2 guarda então a participação como
-- RAZÃO EXATA de inteiros, cujo numerador e denominador são o próprio par
-- (pool, valor econômico) do contrato de referência não fidelizado. Assim a
-- razão reproduz os centavos aprovados por construção, e a mesma razão deriva
-- o fidelizado por aritmética inteira — sem ponto flutuante em lugar nenhum.
--
-- Os percentuais são DESCRITORES DE EXIBIÇÃO, guardados como texto aprovado
-- ao lado dos centavos. Não são autoridade e não participam de cálculo algum.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Modelo de precisão do pool na tabela de regras
-- ----------------------------------------------------------------------------

-- V1 exige pontos-base; V2 não os usa. As colunas passam a ser opcionais para
-- que a V2 não precise inventar um valor que não a representa.
ALTER TABLE public.commercial_pricing_rules
  ALTER COLUMN pool_bps_supermarket DROP NOT NULL,
  ALTER COLUMN pool_bps_common      DROP NOT NULL;

ALTER TABLE public.commercial_pricing_rules
  ADD COLUMN pool_precision_model text NOT NULL DEFAULT 'basis_points';

ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_modelo_precisao_valido
    CHECK (pool_precision_model = ANY (ARRAY['basis_points','exact_ratio']));

-- Coerência entre o modelo declarado e as colunas preenchidas: uma regra em
-- pontos-base precisa deles; uma regra em razão exata não pode tê-los, para
-- não deixar dois valores concorrentes de participação na mesma linha.
ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_modelo_coerente CHECK (
    (pool_precision_model = 'basis_points'
       AND pool_bps_supermarket IS NOT NULL AND pool_bps_common IS NOT NULL)
    OR
    (pool_precision_model = 'exact_ratio'
       AND pool_bps_supermarket IS NULL AND pool_bps_common IS NULL)
  );

-- ----------------------------------------------------------------------------
-- 2. Razões exatas por categoria de nicho
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_pool_share_ratios (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_rule_version   integer NOT NULL
                           REFERENCES public.commercial_pricing_rules(version),
  niche_category         text    NOT NULL,
  pool_numerator         bigint  NOT NULL,
  pool_denominator       bigint  NOT NULL,
  -- Descritores de exibição aprovados. Texto, nunca usado em cálculo.
  display_pool_percent   text    NOT NULL,
  display_bdflow_percent text    NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cpsr_categoria_valida
    CHECK (niche_category = ANY (ARRAY['supermarket','common'])),
  CONSTRAINT cpsr_razao_valida
    CHECK (pool_denominator > 0
           AND pool_numerator >= 0
           AND pool_numerator <= pool_denominator),
  CONSTRAINT cpsr_unica UNIQUE (pricing_rule_version, niche_category)
);

ALTER TABLE public.commercial_pool_share_ratios ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.commercial_pool_share_ratios
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.commercial_pool_share_ratios IS
  'Participação do pool como razão exata de inteiros. Numerador e denominador '
  'são o par (pool, valor economico) do contrato de referencia nao fidelizado, '
  'de modo que a razao reproduz os centavos aprovados por construcao.';

-- ----------------------------------------------------------------------------
-- 3. Ativação da V2 — a V1 vira histórica, não some
-- ----------------------------------------------------------------------------
UPDATE public.commercial_pricing_rules
   SET status = 'superseded'
 WHERE version = 1;

INSERT INTO public.commercial_pricing_rules
  (version, status, block_units, block_price_cents, extra_unit_price_cents,
   fidelized_unit_price_cents, pool_bps_supermarket, pool_bps_common,
   pool_precision_model, notes)
VALUES
  (2, 'active', 12, 1999900, 129900, 129900, NULL, NULL, 'exact_ratio',
   'Comercial V2: preco inalterado; pool por razao exata em centavos. '
   'Formacao completa nao fidelizada: 13.558.200 economico, 9.231.600 pool, '
   '4.326.600 BDFlow/operacao/investimentos, 109.900 por usuario elegivel.');

INSERT INTO public.commercial_pool_share_ratios
  (pricing_rule_version, niche_category, pool_numerator, pool_denominator,
   display_pool_percent, display_bdflow_percent)
VALUES
  -- 2.554.305 / 3.558.700 (supermercado 24 unidades, nao fidelizado)
  (2, 'supermarket', 2554305, 3558700, '71,7763%', '28,2237%'),
  -- 1.335.459 / 1.999.900 (nicho comum 12 unidades, nao fidelizado)
  (2, 'common',      1335459, 1999900, '66,7763%', '33,2237%');

-- ----------------------------------------------------------------------------
-- 3b. Compatibilidade do snapshot de pedido com a V2
--
-- DEFEITO QUE A ATIVAÇÃO DA V2 REVELA: commercial_exclusivity_orders.pool_bps
-- é NOT NULL. Sob a V2 não existe valor de pontos-base honesto para gravar
-- ali, e a venda manual falharia na primeira tentativa. A coluna passa a ser
-- opcional, com regra explícita por versão — historicamente obrigatória,
-- ausente na V2 — em vez de receber um número inventado.
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_exclusivity_orders
  ALTER COLUMN pool_bps DROP NOT NULL;

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_pool_bps_por_versao CHECK (
    (pricing_rule_version = 1 AND pool_bps IS NOT NULL)
    OR (pricing_rule_version >= 2 AND pool_bps IS NULL)
  );

-- Campos V2 do snapshot. Nulos em linhas históricas: a forma de
-- disponibilização não existia quando elas foram criadas e inventar um valor
-- padrão seria afirmar algo que ninguém escolheu.
ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN benefit_settlement_mode text,
  ADD COLUMN cash_user_pool_funding_cents bigint,
  ADD COLUMN total_monetary_funding_required_cents bigint,
  ADD COLUMN benefit_distribution_policy_version integer;

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_modo_v2_valido CHECK (
    benefit_settlement_mode IS NULL
    OR benefit_settlement_mode = ANY (ARRAY['direct_benefits','cash'])
  );

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_financiamento_v2_coerente CHECK (
    benefit_settlement_mode IS NULL
    OR (benefit_settlement_mode = 'direct_benefits'
          AND cash_user_pool_funding_cents = 0
          AND total_monetary_funding_required_cents = bdflow_due_cents)
    OR (benefit_settlement_mode = 'cash'
          AND cash_user_pool_funding_cents = contractual_pool_cents
          AND total_monetary_funding_required_cents
                = bdflow_due_cents + contractual_pool_cents)
  );

-- A INVARIANTE ECONÔMICA JÁ EXISTE E CONTINUA VALENDO.
--
-- Uma versão anterior desta migration acrescentava aqui um
-- `ADD CONSTRAINT ceo_invariante_economica`. Era defeito: a constraint com
-- esse mesmo nome já é criada em 20260822124000_m2_contracts.sql, sobre esta
-- mesma tabela, com exatamente esta regra. PostgreSQL recusa o nome
-- duplicado e a migration inteira falharia — algo que nenhum teste de
-- TypeScript detectaria.
--
-- Nada é adicionado, renomeado ou removido: a constraint histórica continua
-- impondo economic_value_cents = contractual_pool_cents + bdflow_due_cents,
-- inclusive para as linhas V2.

-- ----------------------------------------------------------------------------
-- 4. Cálculo autoritativo — agora ciente das duas versões
--
-- A assinatura e o contrato de retorno da V1 são preservados. Acrescentam-se
-- campos da V2; consumidores antigos continuam lendo o que já liam.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_niche_contract_pricing(
  p_niche_code text,
  p_fidelized  boolean,
  p_pricing_version integer DEFAULT NULL
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

  -- Preço não muda entre V1 e V2. O que muda é a repartição.
  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  v_cat := CASE WHEN p_niche_code = 'supermarket' THEN 'supermarket' ELSE 'common' END;

  IF v_rule.pool_precision_model = 'exact_ratio' THEN
    SELECT * INTO v_ratio FROM public.commercial_pool_share_ratios
      WHERE pricing_rule_version = v_rule.version AND niche_category = v_cat;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pool_share_ratio_unavailable');
    END IF;
    -- Aritmética inteira: multiplica ANTES de dividir, para que o contrato de
    -- referência reproduza o centavo aprovado exatamente.
    v_pool      := (v_economic * v_ratio.pool_numerator) / v_ratio.pool_denominator;
    v_bps       := NULL;
    v_disp_pool := v_ratio.display_pool_percent;
    v_disp_bdf  := v_ratio.display_bdflow_percent;
  ELSE
    v_bps  := CASE WHEN p_niche_code = 'supermarket'
                   THEN v_rule.pool_bps_supermarket ELSE v_rule.pool_bps_common END;
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
    -- Invariante por construção: devido := econômico - pool.
    'bdflow_due_cents', v_economic - v_pool,
    'display_pool_percent', v_disp_pool,
    'display_bdflow_percent', v_disp_bdf,
    -- Forma de pagamento é DERIVADA da fidelidade no servidor. O navegador
    -- não escolhe: é informação de leitura.
    'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END);
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. Resumo agregado da formação — para a vitrine não recalcular no cliente
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.get_public_formation_economics()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_version    integer;
  v_economic   bigint := 0;
  v_pool       bigint := 0;
  v_n          record;
  v_p          jsonb;
  v_alvo       integer := 84;
BEGIN
  SELECT version INTO v_version
    FROM public.commercial_pricing_rules WHERE status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  FOR v_n IN
    SELECT code FROM public.commercial_niches WHERE is_active ORDER BY sort_order
  LOOP
    v_p := public.calculate_niche_contract_pricing(v_n.code, false);
    IF (v_p->>'ok')::boolean IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_unavailable');
    END IF;
    v_economic := v_economic + (v_p->>'economic_value_cents')::bigint;
    v_pool     := v_pool     + (v_p->>'contractual_pool_cents')::bigint;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'pricing_rule_version', v_version,
    'currency', 'BRL',
    'participant_target', v_alvo,
    'economic_value_cents', v_economic,
    'user_pool_cents', v_pool,
    'bdflow_ops_investment_cents', v_economic - v_pool,
    -- Divisão inteira: só é exata porque a política de resíduos distribui os
    -- centavos restantes. O valor aqui é o alvo por usuário completo.
    -- Divisão inteira. O alvo por usuário completo só fecha exatamente
    -- porque a política de resíduos distribui os centavos restantes; o
    -- resto é publicado para que ninguém precise deduzi-lo.
    'per_complete_user_base_cents', v_pool / v_alvo,
    'pool_remainder_cents', v_pool % v_alvo);
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. Forma de disponibilização dos benefícios e intenção comercial
--
-- A intenção é NEUTRA DE PROVEDOR de propósito: nenhum provedor de pagamento
-- foi selecionado. Os componentes monetários ficam separados para que o
-- adaptador futuro possa cobrar em uma transação, em split ou em duas, sem
-- redesenhar o modelo comercial.
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_checkout_intents (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             uuid    NOT NULL REFERENCES public.site_partner_companies(id),
  niche_code             text    NOT NULL REFERENCES public.commercial_niches(code),
  status                 text    NOT NULL DEFAULT 'draft',

  -- Instantâneo autoritativo, calculado no servidor.
  pricing_rule_version   integer NOT NULL
                           REFERENCES public.commercial_pricing_rules(version),
  benefit_distribution_policy_version integer NOT NULL,
  fidelized              boolean NOT NULL,
  payment_method         text    NOT NULL,
  benefit_settlement_mode text  NOT NULL,
  currency               text    NOT NULL DEFAULT 'BRL',
  nominal_quantity       integer NOT NULL,

  economic_value_cents             bigint NOT NULL,
  user_pool_cents                  bigint NOT NULL,
  bdflow_ops_investment_cents      bigint NOT NULL,
  cash_user_pool_funding_cents     bigint NOT NULL,
  total_monetary_funding_required_cents bigint NOT NULL,
  participant_target     integer NOT NULL DEFAULT 84,

  created_by             uuid    NOT NULL REFERENCES auth.users(id),
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cci_status_valido
    CHECK (status = ANY (ARRAY['draft','awaiting_contract','awaiting_payment_provider','cancelled'])),
  CONSTRAINT cci_modo_valido
    CHECK (benefit_settlement_mode = ANY (ARRAY['direct_benefits','cash'])),
  CONSTRAINT cci_metodo_valido
    CHECK (payment_method = ANY (ARRAY['pix','credit_card'])),
  -- Forma de pagamento DERIVA da fidelidade. Uma linha que contradiga isso
  -- não entra na tabela, mesmo que alguma RPC futura erre.
  CONSTRAINT cci_metodo_deriva_da_fidelidade
    CHECK ((fidelized AND payment_method = 'credit_card')
        OR (NOT fidelized AND payment_method = 'pix')),
  CONSTRAINT cci_positivos
    CHECK (economic_value_cents > 0 AND user_pool_cents >= 0
           AND bdflow_ops_investment_cents >= 0
           AND cash_user_pool_funding_cents >= 0
           AND nominal_quantity > 0 AND participant_target > 0),
  -- Invariante econômica, garantida pelo banco e não pela aplicação.
  CONSTRAINT cci_invariante_economica
    CHECK (economic_value_cents = user_pool_cents + bdflow_ops_investment_cents),
  -- Modo direto não financia o pool em dinheiro; modo dinheiro financia o
  -- pool inteiro. Nunca um valor intermediário inventado.
  CONSTRAINT cci_financiamento_coerente
    CHECK ((benefit_settlement_mode = 'direct_benefits' AND cash_user_pool_funding_cents = 0)
        OR (benefit_settlement_mode = 'cash' AND cash_user_pool_funding_cents = user_pool_cents)),
  CONSTRAINT cci_total_monetario
    CHECK (total_monetary_funding_required_cents
             = bdflow_ops_investment_cents + cash_user_pool_funding_cents)
);

CREATE INDEX cci_company_idx ON public.commercial_checkout_intents (company_id, created_at DESC);

ALTER TABLE public.commercial_checkout_intents ENABLE ROW LEVEL SECURITY;

-- Leitura pelo titular da empresa e por admin. Escrita SOMENTE por RPC.
CREATE POLICY cci_owner_select ON public.commercial_checkout_intents
  FOR SELECT TO authenticated
  USING (
    public.is_site_admin()
    OR EXISTS (
      SELECT 1 FROM public.site_company_members m
       WHERE m.company_id = commercial_checkout_intents.company_id
         AND m.auth_user_id = auth.uid()
         AND m.role = 'owner' AND m.status = 'active')
  );

REVOKE ALL ON TABLE public.commercial_checkout_intents
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_checkout_intents TO authenticated;

-- Imutabilidade do instantâneo depois que a intenção sai de 'draft': o valor
-- que o parceiro reviu não pode mudar debaixo dele.
CREATE FUNCTION public.cci_proteger_snapshot()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF OLD.status <> 'draft' THEN
    IF NEW.pricing_rule_version IS DISTINCT FROM OLD.pricing_rule_version
       OR NEW.fidelized                  IS DISTINCT FROM OLD.fidelized
       OR NEW.payment_method             IS DISTINCT FROM OLD.payment_method
       OR NEW.benefit_settlement_mode   IS DISTINCT FROM OLD.benefit_settlement_mode
       OR NEW.economic_value_cents       IS DISTINCT FROM OLD.economic_value_cents
       OR NEW.user_pool_cents            IS DISTINCT FROM OLD.user_pool_cents
       OR NEW.bdflow_ops_investment_cents IS DISTINCT FROM OLD.bdflow_ops_investment_cents
       OR NEW.cash_user_pool_funding_cents IS DISTINCT FROM OLD.cash_user_pool_funding_cents
       OR NEW.total_monetary_funding_required_cents
            IS DISTINCT FROM OLD.total_monetary_funding_required_cents
       OR NEW.nominal_quantity           IS DISTINCT FROM OLD.nominal_quantity
       OR NEW.participant_target         IS DISTINCT FROM OLD.participant_target THEN
      RAISE EXCEPTION 'commercial_checkout_intent_snapshot_immutable';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER cci_proteger_snapshot_trg
  BEFORE UPDATE ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.cci_proteger_snapshot();

-- ----------------------------------------------------------------------------
-- 7. RPC de criação da intenção
--
-- O cliente informa APENAS o nicho e a forma de disponibilização. Preço,
-- fidelidade, forma de pagamento e componentes monetários são calculados
-- aqui. Nenhum parâmetro de valor é aceito — não há como o navegador propor
-- um preço porque não existe parâmetro para isso.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.create_commercial_checkout_intent(
  p_company_id uuid,
  p_niche_code text,
  p_benefit_settlement_mode text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_company  public.site_partner_companies%ROWTYPE;
  v_fidel    boolean;
  v_p        jsonb;
  v_pool     bigint;
  v_bdflow   bigint;
  v_cash     bigint;
  v_id       uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF p_benefit_settlement_mode IS NULL
     OR p_benefit_settlement_mode NOT IN ('direct_benefits','cash') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_settlement_mode');
  END IF;

  SELECT * INTO v_company FROM public.site_partner_companies WHERE id = p_company_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_not_found');
  END IF;
  -- Só o TITULAR ativo cria intenção. Gerente de unidade não decide forma de
  -- disponibilização: é decisão da empresa, não operacional.
  IF NOT EXISTS (
    SELECT 1 FROM public.site_company_members m
     WHERE m.company_id = p_company_id AND m.auth_user_id = v_uid
       AND m.role = 'owner' AND m.status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  -- Fidelidade é contextual e do servidor: CNPJ + UF + cidade + nicho.
  v_fidel := public.is_fidelized_context(
               v_company.cnpj, v_company.uf, v_company.city, p_niche_code);

  v_p := public.calculate_niche_contract_pricing(p_niche_code, v_fidel);
  IF (v_p->>'ok')::boolean IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_unavailable');
  END IF;

  v_pool   := (v_p->>'contractual_pool_cents')::bigint;
  v_bdflow := (v_p->>'bdflow_due_cents')::bigint;
  v_cash   := CASE WHEN p_benefit_settlement_mode = 'cash' THEN v_pool ELSE 0 END;

  INSERT INTO public.commercial_checkout_intents
    (company_id, niche_code, status, pricing_rule_version,
     benefit_distribution_policy_version, fidelized, payment_method,
     benefit_settlement_mode, currency, nominal_quantity,
     economic_value_cents, user_pool_cents, bdflow_ops_investment_cents,
     cash_user_pool_funding_cents, total_monetary_funding_required_cents,
     created_by)
  VALUES
    (p_company_id, p_niche_code, 'draft', (v_p->>'pricing_rule_version')::int,
     2, v_fidel, v_p->>'payment_method',
     p_benefit_settlement_mode, 'BRL', (v_p->>'nominal_quantity')::int,
     (v_p->>'economic_value_cents')::bigint, v_pool, v_bdflow,
     v_cash, v_bdflow + v_cash,
     v_uid)
  RETURNING id INTO v_id;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'intent_id', v_id,
    'status', 'draft',
    'pricing_rule_version', (v_p->>'pricing_rule_version')::int,
    'benefit_distribution_policy_version', 2,
    'niche_code', p_niche_code,
    'nominal_quantity', (v_p->>'nominal_quantity')::int,
    'fidelized', v_fidel,
    'payment_method', v_p->>'payment_method',
    'benefit_settlement_mode', p_benefit_settlement_mode,
    'currency', 'BRL',
    'economic_value_cents', (v_p->>'economic_value_cents')::bigint,
    'user_pool_cents', v_pool,
    'bdflow_ops_investment_cents', v_bdflow,
    'cash_user_pool_funding_cents', v_cash,
    'total_monetary_funding_required_cents', v_bdflow + v_cash,
    'participant_target', 84,
    'display_pool_percent', v_p->>'display_pool_percent',
    'display_bdflow_percent', v_p->>'display_bdflow_percent');
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. ACLs — mínimo exato
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.get_public_formation_economics() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_public_formation_economics()
  TO anon, authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text)
  TO authenticated, service_role;

-- Trigger de proteção: não é chamável por role alguma do Data API.
REVOKE EXECUTE ON FUNCTION public.cci_proteger_snapshot() FROM PUBLIC;

COMMENT ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text) IS
  'Cria intencao comercial neutra de provedor. O cliente informa apenas nicho '
  'e forma de disponibilizacao; preco, fidelidade, forma de pagamento e '
  'componentes monetarios sao derivados no servidor. Nenhum provedor de '
  'pagamento e selecionado ou acionado.';

-- ============================================================================
-- 9. VENDA MANUAL CIENTE DE VERSÃO
--
-- A assinatura anterior de 10 argumentos gravava `pool_bps` a partir do
-- retorno da precificação. Sob a V2 esse campo é NULL, e a coluna deixou de
-- ser NOT NULL — mas a função também precisa registrar a FORMA DE
-- DISPONIBILIZAÇÃO escolhida pela empresa, que não existia na V1.
--
-- POR QUE A ANTIGA É REMOVIDA E NÃO APENAS SUBSTITUÍDA
-- Acrescentar um parâmetro cria uma SOBRECARGA: as duas assinaturas ficariam
-- executáveis, e a de 10 argumentos continuaria capaz de criar pedido V2 sem
-- modo de liquidação. Um contrato ambíguo em função SECURITY DEFINER é
-- exatamente o tipo de porta que ninguém lembra de fechar depois. Só uma
-- assinatura permanece.
--
-- Nenhum código em src/ chama esta RPC: a conferência foi feita antes da
-- remoção.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_register_manual_commercial_order(
  uuid, uuid, text, timestamptz, text, date, text, text, text, integer);

CREATE FUNCTION public.admin_register_manual_commercial_order(
  p_opportunity_id uuid,
  p_company_id     uuid,
  p_order_version  text,
  p_signed_at      timestamptz,
  p_signatory_name text,
  p_expected_operation_start date,
  p_benefit_settlement_mode text,
  p_document_reference text DEFAULT NULL,
  p_document_hash      text DEFAULT NULL,
  p_external_signature_ref text DEFAULT NULL,
  p_exclusivity_period_days integer DEFAULT 28
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
  RETURNING id INTO v_id;

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
      'economic_value_cents', (v_pricing->>'economic_value_cents')::bigint,
      'total_monetary_funding_required_cents', v_bdflow + v_cash),
    NULL,
    pg_catalog.jsonb_build_object('opportunity_id', p_opportunity_id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'order_id', v_id,
    'pricing_rule_version', v_versao,
    'fidelized', v_fidel,
    'payment_method', v_pricing->>'payment_method',
    'benefit_settlement_mode', p_benefit_settlement_mode,
    'economic_value_cents', (v_pricing->>'economic_value_cents')::bigint,
    'user_pool_cents', v_pool,
    'bdflow_ops_investment_cents', v_bdflow,
    'cash_user_pool_funding_cents', v_cash,
    'total_monetary_funding_required_cents', v_bdflow + v_cash);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(
  uuid,uuid,text,timestamptz,text,date,text,text,text,text,integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(
  uuid,uuid,text,timestamptz,text,date,text,text,text,text,integer) FROM anon;
GRANT  EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(
  uuid,uuid,text,timestamptz,text,date,text,text,text,text,integer) TO authenticated;

-- ----------------------------------------------------------------------------
-- 10. CONFIRMAÇÃO DE FINANCIAMENTO V2 — NEUTRA DE PROVEDOR
--
-- A RPC antiga, admin_confirm_manual_bdflow_payment, é PRESERVADA: ela
-- codifica a semântica V1, em que o valor cobrado é sempre o devido à BDFlow
-- porque o pool nunca era aportado em dinheiro. Fazê-la significar "às vezes
-- o econômico inteiro" sem auditar chamadores seria mudar o sentido de uma
-- função existente pelas costas de quem a usa.
--
-- Esta é a V2: o valor esperado sai do INSTANTÂNEO IMUTÁVEL do pedido e do
-- modo de liquidação, nunca do que o chamador diz.
--
-- NEUTRA DE PROVEDOR: não há chave Pix, QR, adquirente, webhook nem token de
-- provedor. Só a correlação externa opaca já usada pela V1.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.admin_confirm_commercial_funding(
  p_order_id     uuid,
  p_amount_cents bigint,
  p_payment_external_ref text DEFAULT NULL,
  p_justification text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_ord      public.commercial_exclusivity_orders%ROWTYPE;
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
  IF v_ord.pricing_rule_version < 2 THEN
    -- Pedido V1 continua sendo confirmado pela RPC V1. Reinterpretar um
    -- instantâneo histórico sob regra nova é reescrever o passado.
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'v1_order_use_legacy_rpc');
  END IF;

  -- IDEMPOTÊNCIA: repetir a confirmação devolve o estado sem sobrescrever
  -- valor, autor ou instante. Um provedor futuro reenviará o mesmo evento.
  IF v_ord.payment_status = 'confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'payment_status', 'confirmed',
                                         'amount_cents', v_ord.payment_amount_cents);
  END IF;

  -- O esperado vem do INSTANTÂNEO, não do chamador.
  v_esperado := v_ord.total_monetary_funding_required_cents;
  IF v_esperado IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'funding_snapshot_missing');
  END IF;

  IF p_amount_cents IS NULL OR p_amount_cents <> v_esperado THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'amount_differs_from_expected',
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

  PERFORM public.m1_auditar('commercial_order.funding_confirmed', p_order_id, 'admin',
    pg_catalog.jsonb_build_object('payment_status','confirmed',
                                  'amount_cents', p_amount_cents,
                                  'benefit_settlement_mode', v_ord.benefit_settlement_mode,
                                  'cash_user_pool_funding_cents',
                                    v_ord.cash_user_pool_funding_cents),
    pg_catalog.jsonb_build_object('payment_status','pending'),
    pg_catalog.jsonb_build_object('justification', p_justification));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false,
    'payment_status', 'confirmed',
    'amount_cents', p_amount_cents,
    'benefit_settlement_mode', v_ord.benefit_settlement_mode,
    -- Confirmar o FINANCIAMENTO não significa que dinheiro chegou a usuário
    -- algum. A liberação é do domínio operacional do App.
    'user_payout_executed', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_confirm_commercial_funding(uuid,bigint,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_confirm_commercial_funding(uuid,bigint,text,text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.admin_confirm_commercial_funding(uuid,bigint,text,text) TO authenticated;

COMMENT ON FUNCTION public.admin_confirm_commercial_funding(uuid,bigint,text,text) IS
  'Confirmacao de financiamento comercial V2, neutra de provedor. O valor '
  'esperado vem do instantaneo imutavel do pedido; o chamador nao propoe '
  'valor. Idempotente. Nao integra provedor de pagamento nem executa repasse '
  'a usuarios.';
