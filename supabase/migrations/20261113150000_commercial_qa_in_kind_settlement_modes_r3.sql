-- ===========================================================================
-- R3 — QA EXCLUSIVAMENTE EM PRODUTOS NO BENEFÍCIO DIRETO; SEM QA NO DINHEIRO
--
-- Migration PREPARATÓRIA, não aplicada. Depende de 20261112120000 (SF-v1.5,
-- também não aplicada). Não ativa versão, não grava preço da modalidade
-- DINHEIRO, não altera nenhuma linha histórica.
--
-- DECISÃO COMERCIAL (responsável do projeto, 13/11/2026):
--   * A QA existe exclusivamente para testes locais de benefícios diretos,
--     com produtos disponibilizados pela rede anunciante.
--   * Não existe QA em dinheiro.
--   * Na modalidade integralmente monetária não há testes com produtos:
--     não existe QA nessa modalidade.
--
-- O QUE MUDA (só versão >= 4; a versão 3 / SF-v1.4 mantém a interpretação
-- histórica — QA como remuneração monetária — por estar codificada por versão):
--   A. regra de preço ganha `qa_policy`; a versão 4 recebe
--      'in_kind_direct_benefits_only';
--   B. termos de liquidação POR MODALIDADE (commercial_settlement_terms): a
--      composição deixa de ser propriedade só da regra e passa a depender de
--      versão × categoria × fidelidade × modalidade;
--   C. intenção e pedido v4 resolvem e congelam a composição da modalidade;
--      CHECK versionado; a v1.4 continua com o seu CHECK, re-escopado a v3;
--   D. pagamento: um único invariante — valor confirmado = total monetário
--      exigível do snapshot do pedido — nos três caminhos de confirmação;
--   E. reutilização de bandeiras revalidada na criação e na confirmação;
--   F. instrumento: modelo precisa declarar o modelo de liquidação da versão;
--   G. ativação só pela função autorizada, com pré-condições no gatilho;
--   H. autoatendimento (checkout) bloqueado no banco abaixo da versão mínima.
--
-- DEPENDE DE DECISÃO (não implementado por escolha arbitrária):
--   * preço da modalidade DINHEIRO na versão 4 (Cenário A: sem a QA; Cenário
--     B: preço mantido com componente de outra natureza, expressamente
--     aprovado). Os termos de DINHEIRO NÃO são criados aqui. Sem eles a
--     versão 4 não ativa e nenhuma reserva em dinheiro nasce sob ela.
--     Scripts de cada cenário: supabase/ops/20261113_sf_v15_dinheiro_cenario_{a,b}.sql
-- ===========================================================================

-- ===========================================================================
-- A. POLÍTICA DE QA POR VERSÃO
-- ---------------------------------------------------------------------------
-- NULL = interpretação histórica da versão (V1/V2 sem QA; SF-v1.4 com QA
-- monetária). Nenhuma linha histórica é tocada: ADD COLUMN sem DEFAULT não
-- reescreve linhas e não dispara gatilhos.
-- ===========================================================================
ALTER TABLE public.commercial_pricing_rules
  ADD COLUMN qa_policy text;
ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_qa_policy_valida
  CHECK (qa_policy IS NULL OR qa_policy = 'in_kind_direct_benefits_only');
ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_qa_policy_so_v4
  CHECK (qa_policy IS NULL OR version >= 4);
COMMENT ON COLUMN public.commercial_pricing_rules.qa_policy IS
  'R3: in_kind_direct_benefits_only = QA so em produtos, so no beneficio '
  'direto; inexistente no dinheiro. NULL nas versoes historicas (SF-v1.4: QA '
  'monetaria, preservada).';

-- A versão 4 está 'prepared': editável pelo próprio gatilho cpr_protect.
UPDATE public.commercial_pricing_rules
   SET qa_policy = 'in_kind_direct_benefits_only'
 WHERE version = 4 AND status = 'prepared';

DO $verifica_politica$
BEGIN
  IF (SELECT qa_policy FROM public.commercial_pricing_rules WHERE version = 4)
       IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    RAISE EXCEPTION 'r3_pre_condicao: versao 4 ausente ou fora de prepared';
  END IF;
END $verifica_politica$;

-- ===========================================================================
-- B. TERMOS DE LIQUIDAÇÃO POR MODALIDADE (versão >= 4)
-- ---------------------------------------------------------------------------
-- Uma linha por versão × categoria × fidelidade × modalidade. Centavos
-- explícitos, nunca derivados no navegador.
--
--   mei_consideration_cents   contraprestação dos participantes (igual nas duas)
--   mei_in_kind_cents         parte cumprida em benefícios diretos
--   mei_cash_cents            parte financiada em dinheiro
--   smallflags_main_fee_cents parcela operacional principal (dinheiro)
--   qa_in_kind_cents          QA em produtos (só benefício direto)
--   qa_cash_cents             sempre 0 (não existe QA em dinheiro)
--   cash_adjustment_cents     componente de OUTRA natureza, só no dinheiro e
--                             só com fundamento aprovado (Cenário B). Nunca
--                             é QA renomeada: o fundamento é obrigatório.
--   total_monetary_funding_required_cents  dinheiro exigível da anunciante
--
-- Invariantes (CHECK):
--   direto:  mei_in_kind = mei; mei_cash = 0; ajuste = 0;
--            econômico = mei + principal + qa_in_kind; dinheiro = principal
--   dinheiro: qa_in_kind = 0; mei_in_kind = 0; mei_cash = mei;
--            econômico = mei + principal + ajuste; dinheiro = econômico
-- A parcela principal é a MESMA da agenda nas duas modalidades (gatilho):
-- retirar a QA nunca aumenta a remuneração da SmallFlags por inferência.
-- ===========================================================================
CREATE TABLE public.commercial_settlement_terms (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_rule_version       integer NOT NULL
                             REFERENCES public.commercial_pricing_rules(version),
  contract_economics_version text    NOT NULL,
  commercial_category        text    NOT NULL,
  fidelized                  boolean NOT NULL,
  benefit_settlement_mode    text    NOT NULL,
  economic_value_cents       bigint  NOT NULL,
  mei_consideration_cents    bigint  NOT NULL,
  mei_in_kind_cents          bigint  NOT NULL,
  mei_cash_cents             bigint  NOT NULL,
  smallflags_main_fee_cents  bigint  NOT NULL,
  qa_in_kind_cents           bigint  NOT NULL,
  qa_cash_cents              bigint  NOT NULL DEFAULT 0,
  cash_adjustment_cents      bigint  NOT NULL DEFAULT 0,
  cash_adjustment_basis      text,
  total_monetary_funding_required_cents bigint NOT NULL,
  ordinary_participation_value_cents    bigint NOT NULL,
  decision_reference         text    NOT NULL,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  notes                      text,
  CONSTRAINT cst_versao_com_politica CHECK (pricing_rule_version >= 4),
  CONSTRAINT cst_categoria_valida CHECK (commercial_category IN ('supermarket', 'common')),
  CONSTRAINT cst_modalidade_valida CHECK (benefit_settlement_mode IN ('direct_benefits', 'cash')),
  CONSTRAINT cst_nao_negativos CHECK (
    economic_value_cents > 0 AND mei_consideration_cents >= 0
    AND mei_in_kind_cents >= 0 AND mei_cash_cents >= 0
    AND smallflags_main_fee_cents >= 0 AND qa_in_kind_cents >= 0
    AND cash_adjustment_cents >= 0 AND total_monetary_funding_required_cents >= 0
    AND ordinary_participation_value_cents > 0),
  -- Não existe QA em dinheiro, em nenhuma modalidade.
  CONSTRAINT cst_sem_qa_em_dinheiro CHECK (qa_cash_cents = 0),
  CONSTRAINT cst_ajuste_fundamentado CHECK (
    (cash_adjustment_cents = 0 AND cash_adjustment_basis IS NULL)
    OR (cash_adjustment_cents > 0 AND cash_adjustment_basis IS NOT NULL
        AND length(btrim(cash_adjustment_basis)) >= 20)),
  CONSTRAINT cst_decisao_registrada CHECK (length(btrim(decision_reference)) >= 10),
  CONSTRAINT cst_beneficio_direto CHECK (
    benefit_settlement_mode <> 'direct_benefits'
    OR (mei_in_kind_cents = mei_consideration_cents
        AND mei_cash_cents = 0
        AND cash_adjustment_cents = 0
        AND economic_value_cents
            = mei_consideration_cents + smallflags_main_fee_cents + qa_in_kind_cents
        AND total_monetary_funding_required_cents = smallflags_main_fee_cents)),
  CONSTRAINT cst_dinheiro CHECK (
    benefit_settlement_mode <> 'cash'
    OR (qa_in_kind_cents = 0
        AND mei_in_kind_cents = 0
        AND mei_cash_cents = mei_consideration_cents
        AND economic_value_cents
            = mei_consideration_cents + smallflags_main_fee_cents + cash_adjustment_cents
        AND total_monetary_funding_required_cents = economic_value_cents)),
  CONSTRAINT cst_chave_unica
    UNIQUE (pricing_rule_version, commercial_category, fidelized, benefit_settlement_mode)
);

COMMENT ON TABLE public.commercial_settlement_terms IS
  'R3: composicao contratual por modalidade (versao >= 4). QA so em produtos '
  'no beneficio direto; inexistente no dinheiro. Imutavel fora de prepared.';

ALTER TABLE public.commercial_settlement_terms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_settlement_terms FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_settlement_terms TO service_role;

-- Coerência com a agenda e com a política, e escrita só com a versão em
-- 'prepared' (mesmo critério da agenda SF-v1.5).
CREATE FUNCTION public.commercial_settlement_terms_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_status text;
  v_rule   public.commercial_pricing_rules%ROWTYPE;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT status INTO v_status FROM public.commercial_pricing_rules
     WHERE version = OLD.pricing_rule_version;
    IF v_status IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'settlement_terms_imutaveis: termos da versao % (%) nao mudam',
        OLD.pricing_rule_version, v_status USING ERRCODE = 'check_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
  END IF;

  SELECT * INTO v_rule FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_rule.status IS DISTINCT FROM 'prepared' THEN
    RAISE EXCEPTION 'settlement_terms_imutaveis: termos so sao escritos com a versao em prepared (versao %, %)',
      NEW.pricing_rule_version, v_rule.status USING ERRCODE = 'check_violation';
  END IF;
  IF v_rule.qa_policy IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    RAISE EXCEPTION 'settlement_terms_sem_politica: versao % sem politica de QA', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = NEW.pricing_rule_version
     AND commercial_category = NEW.commercial_category
     AND fidelized = NEW.fidelized;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'settlement_terms_sem_agenda: versao %, %, fidelizado=%',
      NEW.pricing_rule_version, NEW.commercial_category, NEW.fidelized
      USING ERRCODE = 'check_violation';
  END IF;

  -- Participantes, principal e rótulo legal vêm da agenda, nas duas
  -- modalidades. A retirada da QA não aumenta a parcela principal.
  IF NEW.contract_economics_version IS DISTINCT FROM v_sched.contract_economics_version
     OR NEW.mei_consideration_cents IS DISTINCT FROM v_sched.mei_consideration_cents
     OR NEW.ordinary_participation_value_cents IS DISTINCT FROM v_sched.ordinary_participation_value_cents
     OR NEW.smallflags_main_fee_cents IS DISTINCT FROM v_sched.smallflags_main_fee_cents THEN
    RAISE EXCEPTION 'settlement_terms_divergem_da_agenda: participantes, principal e versao economica sao os da agenda'
      USING ERRCODE = 'check_violation';
  END IF;
  -- Benefício direto: a QA em produtos e o econômico são os da agenda.
  IF NEW.benefit_settlement_mode = 'direct_benefits'
     AND (NEW.qa_in_kind_cents IS DISTINCT FROM v_sched.smallflags_qa_cents
          OR NEW.economic_value_cents IS DISTINCT FROM v_sched.economic_value_cents) THEN
    RAISE EXCEPTION 'settlement_terms_divergem_da_agenda: QA em produtos e valor do beneficio direto sao os da agenda'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_settlement_terms_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cst_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_settlement_terms
  FOR EACH ROW EXECUTE FUNCTION public.commercial_settlement_terms_protect();
CREATE TRIGGER cst_protect_truncate
  BEFORE TRUNCATE ON public.commercial_settlement_terms
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- Benefício direto da versão 4: decidido (QA em produtos). Derivado da agenda
-- preparada, sem nenhum número novo.
INSERT INTO public.commercial_settlement_terms
  (pricing_rule_version, contract_economics_version, commercial_category, fidelized,
   benefit_settlement_mode, economic_value_cents, mei_consideration_cents,
   mei_in_kind_cents, mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents,
   qa_cash_cents, cash_adjustment_cents, cash_adjustment_basis,
   total_monetary_funding_required_cents, ordinary_participation_value_cents,
   decision_reference, notes)
SELECT s.pricing_rule_version, s.contract_economics_version, s.commercial_category, s.fidelized,
       'direct_benefits', s.economic_value_cents, s.mei_consideration_cents,
       s.mei_consideration_cents, 0, s.smallflags_main_fee_cents, s.smallflags_qa_cents,
       0, 0, NULL,
       s.smallflags_main_fee_cents, s.ordinary_participation_value_cents,
       'R3 2026-11-13: QA exclusivamente em produtos no beneficio direto '
       '(decisao comercial do responsavel do projeto)',
       'Beneficio direto SF-v1.5: participantes em beneficios, QA em produtos, '
       'parcela principal em dinheiro.'
  FROM public.commercial_pricing_schedule s
 WHERE s.pricing_rule_version = 4;

-- DINHEIRO da versão 4: NÃO criado. Preço pendente (Cenário A ou B).

-- Termos aplicáveis a uma condição, ou NULL (falha fechada no chamador).
CREATE FUNCTION public.commercial_settlement_terms_for(
  p_version integer, p_niche_code text, p_fidelized boolean, p_mode text)
RETURNS public.commercial_settlement_terms
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT t.* FROM public.commercial_settlement_terms t
   WHERE t.pricing_rule_version = p_version
     AND t.commercial_category = CASE WHEN p_niche_code = 'supermarket' THEN 'supermarket'
                                      WHEN p_niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others')
                                        THEN 'common' END
     AND t.fidelized = p_fidelized
     AND t.benefit_settlement_mode = p_mode;
$$;
REVOKE ALL ON FUNCTION public.commercial_settlement_terms_for(integer, text, boolean, text) FROM PUBLIC, anon, authenticated, service_role;

-- Bloco público por modalidade. NULL = modalidade ainda sem preço aprovado.
CREATE FUNCTION public.commercial_settlement_mode_json(p_t public.commercial_settlement_terms)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT CASE WHEN p_t.id IS NULL THEN NULL ELSE pg_catalog.jsonb_build_object(
    'benefit_settlement_mode', p_t.benefit_settlement_mode,
    'economic_value_cents', p_t.economic_value_cents,
    'mei_consideration_cents', p_t.mei_consideration_cents,
    'mei_in_kind_cents', p_t.mei_in_kind_cents,
    'mei_cash_cents', p_t.mei_cash_cents,
    'smallflags_main_fee_cents', p_t.smallflags_main_fee_cents,
    'qa_in_kind_cents', p_t.qa_in_kind_cents,
    'qa_cash_cents', p_t.qa_cash_cents,
    'cash_adjustment_cents', p_t.cash_adjustment_cents,
    'total_monetary_funding_required_cents', p_t.total_monetary_funding_required_cents,
    'ordinary_participation_value_cents', p_t.ordinary_participation_value_cents) END;
$$;
REVOKE ALL ON FUNCTION public.commercial_settlement_mode_json(public.commercial_settlement_terms) FROM PUBLIC, anon, authenticated, service_role;

-- ===========================================================================
-- C. INTENÇÃO E PEDIDO: composição da modalidade, congelada
-- ---------------------------------------------------------------------------
-- Colunas novas, NULL em toda linha histórica (versão < 4). Colunas antigas
-- mantêm o significado, com a correspondência da versão 4 declarada:
--   smallflags_qa_cents                = QA em produtos (0 no dinheiro)
--   smallflags_total_remuneration_cents = remuneração MONETÁRIA = principal
--   contractual_pool / user_pool       = participantes + QA em produtos
--   bdflow_due / bdflow_ops_investment = principal + ajuste aprovado
--   (econômico = pool + devido continua valendo para todas as versões)
-- ===========================================================================
ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN settlement_terms_id   uuid REFERENCES public.commercial_settlement_terms(id),
  ADD COLUMN qa_policy             text,
  ADD COLUMN mei_in_kind_cents     bigint,
  ADD COLUMN qa_in_kind_cents      bigint,
  ADD COLUMN qa_cash_cents         bigint,
  ADD COLUMN cash_adjustment_cents bigint;
ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN settlement_terms_id   uuid REFERENCES public.commercial_settlement_terms(id),
  ADD COLUMN qa_policy             text,
  ADD COLUMN mei_in_kind_cents     bigint,
  ADD COLUMN qa_in_kind_cents      bigint,
  ADD COLUMN qa_cash_cents         bigint,
  ADD COLUMN cash_adjustment_cents bigint;

COMMENT ON COLUMN public.commercial_exclusivity_orders.qa_in_kind_cents IS
  'R3: QA em produtos para testes locais (so beneficio direto, versao >= 4). '
  'Nunca cobrada em dinheiro, nunca dos participantes. NULL nas versoes historicas.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.qa_cash_cents IS
  'R3: QA em dinheiro. Sempre 0 na versao >= 4. NULL nas versoes historicas '
  '(na SF-v1.4 a QA monetaria esta em smallflags_qa_cents, preservada).';

-- A SF-v1.4 conserva o seu CHECK, re-escopado à versão 3 (expressão idêntica).
ALTER TABLE public.commercial_exclusivity_orders DROP CONSTRAINT ceo_financiamento_v14_coerente;
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_financiamento_v14_coerente
  CHECK ((pricing_rule_version >= 4) OR (pricing_rule_version < 3) OR (benefit_settlement_mode IS NULL) OR ((mei_consideration_cents IS NOT NULL) AND (smallflags_qa_cents IS NOT NULL) AND (smallflags_main_fee_cents IS NOT NULL) AND (smallflags_total_remuneration_cents IS NOT NULL) AND (mei_cash_funding_cents IS NOT NULL) AND (smallflags_total_remuneration_cents = (smallflags_qa_cents + smallflags_main_fee_cents)) AND (economic_value_cents = ((mei_consideration_cents + smallflags_qa_cents) + smallflags_main_fee_cents)) AND (contractual_pool_cents = (mei_consideration_cents + smallflags_qa_cents)) AND (bdflow_due_cents = smallflags_main_fee_cents) AND (((benefit_settlement_mode = 'direct_benefits'::text) AND (mei_cash_funding_cents = 0) AND (total_monetary_funding_required_cents = smallflags_total_remuneration_cents)) OR ((benefit_settlement_mode = 'cash'::text) AND (mei_cash_funding_cents = mei_consideration_cents) AND (total_monetary_funding_required_cents = economic_value_cents))))) NOT VALID;
COMMENT ON CONSTRAINT ceo_financiamento_v14_coerente ON public.commercial_exclusivity_orders IS
  'SF-v1.4 (pricing_rule_version = 3): QA monetaria nas duas modalidades, '
  'interpretacao historica preservada. Versao >= 4: ceo_liquidacao_modalidade_v15.';

ALTER TABLE public.commercial_checkout_intents DROP CONSTRAINT cci_financiamento_v14_coerente;
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_financiamento_v14_coerente
  CHECK ((pricing_rule_version >= 4) OR (pricing_rule_version < 3) OR ((mei_consideration_cents IS NOT NULL) AND (smallflags_qa_cents IS NOT NULL) AND (smallflags_main_fee_cents IS NOT NULL) AND (smallflags_total_remuneration_cents IS NOT NULL) AND (mei_cash_funding_cents IS NOT NULL) AND (smallflags_total_remuneration_cents = (smallflags_qa_cents + smallflags_main_fee_cents)) AND (economic_value_cents = ((mei_consideration_cents + smallflags_qa_cents) + smallflags_main_fee_cents)) AND (user_pool_cents = (mei_consideration_cents + smallflags_qa_cents)) AND (bdflow_ops_investment_cents = smallflags_main_fee_cents) AND (((benefit_settlement_mode = 'direct_benefits'::text) AND (mei_cash_funding_cents = 0) AND (cash_user_pool_funding_cents = 0) AND (total_monetary_funding_required_cents = smallflags_total_remuneration_cents)) OR ((benefit_settlement_mode = 'cash'::text) AND (mei_cash_funding_cents = mei_consideration_cents) AND (cash_user_pool_funding_cents = user_pool_cents) AND (total_monetary_funding_required_cents = economic_value_cents))))) NOT VALID;

-- Versão >= 4: a composição tem de ser a da modalidade escolhida.
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_liquidacao_modalidade_v15 CHECK (
    pricing_rule_version IS NULL OR pricing_rule_version < 4 OR (
      benefit_settlement_mode IS NOT NULL AND settlement_terms_id IS NOT NULL
      AND qa_policy = 'in_kind_direct_benefits_only'
      AND mei_consideration_cents IS NOT NULL AND smallflags_main_fee_cents IS NOT NULL
      AND smallflags_qa_cents IS NOT NULL AND smallflags_total_remuneration_cents IS NOT NULL
      AND mei_cash_funding_cents IS NOT NULL AND cash_user_pool_funding_cents IS NOT NULL
      AND total_monetary_funding_required_cents IS NOT NULL
      AND mei_in_kind_cents IS NOT NULL AND qa_in_kind_cents IS NOT NULL
      AND qa_cash_cents IS NOT NULL AND cash_adjustment_cents IS NOT NULL
      AND qa_cash_cents = 0
      AND smallflags_qa_cents = qa_in_kind_cents
      AND smallflags_total_remuneration_cents = smallflags_main_fee_cents
      AND economic_value_cents = mei_consideration_cents + smallflags_main_fee_cents
                                 + qa_in_kind_cents + cash_adjustment_cents
      AND contractual_pool_cents = mei_consideration_cents + qa_in_kind_cents
      AND bdflow_due_cents = smallflags_main_fee_cents + cash_adjustment_cents
      AND ((benefit_settlement_mode = 'direct_benefits'
            AND mei_in_kind_cents = mei_consideration_cents
            AND mei_cash_funding_cents = 0 AND cash_user_pool_funding_cents = 0
            AND cash_adjustment_cents = 0
            AND total_monetary_funding_required_cents = smallflags_main_fee_cents)
        OR (benefit_settlement_mode = 'cash'
            AND qa_in_kind_cents = 0 AND mei_in_kind_cents = 0
            AND mei_cash_funding_cents = mei_consideration_cents
            AND cash_user_pool_funding_cents = contractual_pool_cents
            AND total_monetary_funding_required_cents = economic_value_cents))));
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_liquidacao_v15_so_versao_4 CHECK (
    pricing_rule_version >= 4 OR (
      settlement_terms_id IS NULL AND qa_policy IS NULL AND mei_in_kind_cents IS NULL
      AND qa_in_kind_cents IS NULL AND qa_cash_cents IS NULL AND cash_adjustment_cents IS NULL));

ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_liquidacao_modalidade_v15 CHECK (
    pricing_rule_version IS NULL OR pricing_rule_version < 4 OR (
      benefit_settlement_mode IS NOT NULL AND settlement_terms_id IS NOT NULL
      AND qa_policy = 'in_kind_direct_benefits_only'
      AND mei_consideration_cents IS NOT NULL AND smallflags_main_fee_cents IS NOT NULL
      AND smallflags_qa_cents IS NOT NULL AND smallflags_total_remuneration_cents IS NOT NULL
      AND mei_cash_funding_cents IS NOT NULL
      AND mei_in_kind_cents IS NOT NULL AND qa_in_kind_cents IS NOT NULL
      AND qa_cash_cents IS NOT NULL AND cash_adjustment_cents IS NOT NULL
      AND qa_cash_cents = 0
      AND smallflags_qa_cents = qa_in_kind_cents
      AND smallflags_total_remuneration_cents = smallflags_main_fee_cents
      AND economic_value_cents = mei_consideration_cents + smallflags_main_fee_cents
                                 + qa_in_kind_cents + cash_adjustment_cents
      AND user_pool_cents = mei_consideration_cents + qa_in_kind_cents
      AND bdflow_ops_investment_cents = smallflags_main_fee_cents + cash_adjustment_cents
      AND ((benefit_settlement_mode = 'direct_benefits'
            AND mei_in_kind_cents = mei_consideration_cents
            AND mei_cash_funding_cents = 0 AND cash_user_pool_funding_cents = 0
            AND cash_adjustment_cents = 0
            AND total_monetary_funding_required_cents = smallflags_main_fee_cents)
        OR (benefit_settlement_mode = 'cash'
            AND qa_in_kind_cents = 0 AND mei_in_kind_cents = 0
            AND mei_cash_funding_cents = mei_consideration_cents
            AND cash_user_pool_funding_cents = user_pool_cents
            AND total_monetary_funding_required_cents = economic_value_cents))));
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_liquidacao_v15_so_versao_4 CHECK (
    pricing_rule_version >= 4 OR (
      settlement_terms_id IS NULL AND qa_policy IS NULL AND mei_in_kind_cents IS NULL
      AND qa_in_kind_cents IS NULL AND qa_cash_cents IS NULL AND cash_adjustment_cents IS NULL));

-- Resolução da intenção (INSERT) e recálculo na troca de modalidade (UPDATE,
-- só em 'draft': fora dele cci_proteger_snapshot já recusa). Qualquer outra
-- mudança nos valores congelados é recusada. Roda depois de
-- cci_aplicar_autoridade_v14, que deixa a versão >= 4 para este gatilho.
CREATE FUNCTION public.cci_liquidar_modalidade_v15()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_rule public.commercial_pricing_rules%ROWTYPE;
  v_t    public.commercial_settlement_terms%ROWTYPE;
BEGIN
  IF NEW.pricing_rule_version IS NULL OR NEW.pricing_rule_version < 4 THEN
    RETURN NEW;  -- histórico: cci_liquidacao_v15_so_versao_4 barra campos novos
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.pricing_rule_version IS DISTINCT FROM OLD.pricing_rule_version
       OR NEW.fidelized IS DISTINCT FROM OLD.fidelized
       OR NEW.niche_code IS DISTINCT FROM OLD.niche_code THEN
      RAISE EXCEPTION 'liquidacao_congelada: versao, fidelidade e posicao da intencao nao mudam'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.benefit_settlement_mode IS NOT DISTINCT FROM OLD.benefit_settlement_mode THEN
      IF NEW.contract_economics_version IS DISTINCT FROM OLD.contract_economics_version
         OR NEW.economic_value_cents IS DISTINCT FROM OLD.economic_value_cents
         OR NEW.mei_consideration_cents IS DISTINCT FROM OLD.mei_consideration_cents
         OR NEW.smallflags_qa_cents IS DISTINCT FROM OLD.smallflags_qa_cents
         OR NEW.smallflags_main_fee_cents IS DISTINCT FROM OLD.smallflags_main_fee_cents
         OR NEW.smallflags_total_remuneration_cents IS DISTINCT FROM OLD.smallflags_total_remuneration_cents
         OR NEW.user_pool_cents IS DISTINCT FROM OLD.user_pool_cents
         OR NEW.bdflow_ops_investment_cents IS DISTINCT FROM OLD.bdflow_ops_investment_cents
         OR NEW.mei_cash_funding_cents IS DISTINCT FROM OLD.mei_cash_funding_cents
         OR NEW.cash_user_pool_funding_cents IS DISTINCT FROM OLD.cash_user_pool_funding_cents
         OR NEW.total_monetary_funding_required_cents IS DISTINCT FROM OLD.total_monetary_funding_required_cents
         OR NEW.settlement_terms_id IS DISTINCT FROM OLD.settlement_terms_id
         OR NEW.qa_policy IS DISTINCT FROM OLD.qa_policy
         OR NEW.mei_in_kind_cents IS DISTINCT FROM OLD.mei_in_kind_cents
         OR NEW.qa_in_kind_cents IS DISTINCT FROM OLD.qa_in_kind_cents
         OR NEW.qa_cash_cents IS DISTINCT FROM OLD.qa_cash_cents
         OR NEW.cash_adjustment_cents IS DISTINCT FROM OLD.cash_adjustment_cents THEN
        RAISE EXCEPTION 'liquidacao_congelada: valores da intencao so mudam pela troca de modalidade, recalculados pelo servidor'
          USING ERRCODE = 'check_violation';
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  SELECT * INTO v_rule FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_rule.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'pricing_rule_not_published: versao % nao esta vigente (%)',
      NEW.pricing_rule_version, v_rule.status USING ERRCODE = 'check_violation';
  END IF;
  IF v_rule.qa_policy IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    RAISE EXCEPTION 'liquidacao_sem_politica: versao % sem politica de QA', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.benefit_settlement_mode IS NULL THEN
    RAISE EXCEPTION 'liquidacao_sem_modalidade' USING ERRCODE = 'check_violation';
  END IF;

  v_t := public.commercial_settlement_terms_for(
           NEW.pricing_rule_version, NEW.niche_code, NEW.fidelized, NEW.benefit_settlement_mode);
  IF v_t.id IS NULL THEN
    RAISE EXCEPTION 'settlement_terms_unavailable: modalidade % sem preco aprovado (versao %)',
      NEW.benefit_settlement_mode, NEW.pricing_rule_version USING ERRCODE = 'check_violation';
  END IF;

  NEW.contract_economics_version          := v_t.contract_economics_version;
  NEW.economic_value_cents                := v_t.economic_value_cents;
  NEW.mei_consideration_cents             := v_t.mei_consideration_cents;
  NEW.smallflags_qa_cents                 := v_t.qa_in_kind_cents;
  NEW.smallflags_main_fee_cents           := v_t.smallflags_main_fee_cents;
  NEW.smallflags_total_remuneration_cents := v_t.smallflags_main_fee_cents;
  NEW.user_pool_cents                     := v_t.mei_consideration_cents + v_t.qa_in_kind_cents;
  NEW.bdflow_ops_investment_cents         := v_t.smallflags_main_fee_cents + v_t.cash_adjustment_cents;
  NEW.mei_cash_funding_cents              := v_t.mei_cash_cents;
  NEW.cash_user_pool_funding_cents        := CASE WHEN v_t.benefit_settlement_mode = 'cash'
                                                  THEN NEW.user_pool_cents ELSE 0 END;
  NEW.total_monetary_funding_required_cents := v_t.total_monetary_funding_required_cents;
  NEW.settlement_terms_id                 := v_t.id;
  NEW.qa_policy                           := v_rule.qa_policy;
  NEW.mei_in_kind_cents                   := v_t.mei_in_kind_cents;
  NEW.qa_in_kind_cents                    := v_t.qa_in_kind_cents;
  NEW.qa_cash_cents                       := v_t.qa_cash_cents;
  NEW.cash_adjustment_cents               := v_t.cash_adjustment_cents;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cci_liquidar_modalidade_v15() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cci_liquidar_modalidade_v15
  BEFORE INSERT OR UPDATE ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.cci_liquidar_modalidade_v15();

-- Pedido: cópia exata da intenção (checkout) ou resolução da autoridade
-- (venda manual). Divergência entre o que o chamador manda e a intenção é
-- recusada, não silenciada.
CREATE FUNCTION public.ceo_liquidar_modalidade_v15()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_rule public.commercial_pricing_rules%ROWTYPE;
  v_t    public.commercial_settlement_terms%ROWTYPE;
  v_i    public.commercial_checkout_intents%ROWTYPE;
BEGIN
  IF NEW.pricing_rule_version IS NULL OR NEW.pricing_rule_version < 4 THEN
    RETURN NEW;
  END IF;
  SELECT * INTO v_rule FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_rule.status IS NULL OR v_rule.status = 'prepared' THEN
    RAISE EXCEPTION 'pricing_rule_not_published: versao % ainda nao e vigente', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_rule.qa_policy IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    RAISE EXCEPTION 'liquidacao_sem_politica: versao % sem politica de QA', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.benefit_settlement_mode IS NULL THEN
    RAISE EXCEPTION 'liquidacao_sem_modalidade: pedido v% exige modalidade', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.checkout_intent_id IS NOT NULL THEN
    SELECT * INTO v_i FROM public.commercial_checkout_intents WHERE id = NEW.checkout_intent_id;
    IF NOT FOUND
       OR v_i.pricing_rule_version IS DISTINCT FROM NEW.pricing_rule_version
       OR v_i.fidelized IS DISTINCT FROM NEW.fidelized
       OR v_i.niche_code IS DISTINCT FROM NEW.niche_code
       OR v_i.benefit_settlement_mode IS DISTINCT FROM NEW.benefit_settlement_mode
       OR v_i.settlement_terms_id IS NULL THEN
      RAISE EXCEPTION 'liquidacao_divergente_da_intencao: modalidade, versao ou condicao do pedido diferem da reserva'
        USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.economic_value_cents IS NOT NULL AND NEW.economic_value_cents <> v_i.economic_value_cents)
       OR (NEW.total_monetary_funding_required_cents IS NOT NULL
           AND NEW.total_monetary_funding_required_cents <> v_i.total_monetary_funding_required_cents)
       OR (NEW.smallflags_qa_cents IS NOT NULL AND NEW.smallflags_qa_cents <> v_i.smallflags_qa_cents)
       OR (NEW.mei_cash_funding_cents IS NOT NULL AND NEW.mei_cash_funding_cents <> v_i.mei_cash_funding_cents) THEN
      RAISE EXCEPTION 'liquidacao_divergente_da_intencao: valores do pedido diferem do que a reserva congelou'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.contract_economics_version          := v_i.contract_economics_version;
    NEW.economic_value_cents                := v_i.economic_value_cents;
    NEW.mei_consideration_cents             := v_i.mei_consideration_cents;
    NEW.smallflags_qa_cents                 := v_i.smallflags_qa_cents;
    NEW.smallflags_main_fee_cents           := v_i.smallflags_main_fee_cents;
    NEW.smallflags_total_remuneration_cents := v_i.smallflags_total_remuneration_cents;
    NEW.contractual_pool_cents              := v_i.user_pool_cents;
    NEW.bdflow_due_cents                    := v_i.bdflow_ops_investment_cents;
    NEW.mei_cash_funding_cents              := v_i.mei_cash_funding_cents;
    NEW.cash_user_pool_funding_cents        := v_i.cash_user_pool_funding_cents;
    NEW.total_monetary_funding_required_cents := v_i.total_monetary_funding_required_cents;
    NEW.settlement_terms_id                 := v_i.settlement_terms_id;
    NEW.qa_policy                           := v_i.qa_policy;
    NEW.mei_in_kind_cents                   := v_i.mei_in_kind_cents;
    NEW.qa_in_kind_cents                    := v_i.qa_in_kind_cents;
    NEW.qa_cash_cents                       := v_i.qa_cash_cents;
    NEW.cash_adjustment_cents               := v_i.cash_adjustment_cents;
    RETURN NEW;
  END IF;

  v_t := public.commercial_settlement_terms_for(
           NEW.pricing_rule_version, NEW.niche_code, NEW.fidelized, NEW.benefit_settlement_mode);
  IF v_t.id IS NULL THEN
    RAISE EXCEPTION 'settlement_terms_unavailable: modalidade % sem preco aprovado (versao %)',
      NEW.benefit_settlement_mode, NEW.pricing_rule_version USING ERRCODE = 'check_violation';
  END IF;
  NEW.contract_economics_version          := v_t.contract_economics_version;
  NEW.economic_value_cents                := v_t.economic_value_cents;
  NEW.mei_consideration_cents             := v_t.mei_consideration_cents;
  NEW.smallflags_qa_cents                 := v_t.qa_in_kind_cents;
  NEW.smallflags_main_fee_cents           := v_t.smallflags_main_fee_cents;
  NEW.smallflags_total_remuneration_cents := v_t.smallflags_main_fee_cents;
  NEW.contractual_pool_cents              := v_t.mei_consideration_cents + v_t.qa_in_kind_cents;
  NEW.bdflow_due_cents                    := v_t.smallflags_main_fee_cents + v_t.cash_adjustment_cents;
  NEW.mei_cash_funding_cents              := v_t.mei_cash_cents;
  NEW.cash_user_pool_funding_cents        := CASE WHEN v_t.benefit_settlement_mode = 'cash'
                                                  THEN NEW.contractual_pool_cents ELSE 0 END;
  NEW.total_monetary_funding_required_cents := v_t.total_monetary_funding_required_cents;
  NEW.settlement_terms_id                 := v_t.id;
  NEW.qa_policy                           := v_rule.qa_policy;
  NEW.mei_in_kind_cents                   := v_t.mei_in_kind_cents;
  NEW.qa_in_kind_cents                    := v_t.qa_in_kind_cents;
  NEW.qa_cash_cents                       := v_t.qa_cash_cents;
  NEW.cash_adjustment_cents               := v_t.cash_adjustment_cents;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.ceo_liquidar_modalidade_v15() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ceo_liquidar_modalidade_v15
  BEFORE INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_liquidar_modalidade_v15();

-- Composição congelada no pedido: nada muda depois do INSERT.
CREATE FUNCTION public.ceo_liquidacao_v15_imutavel()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF NEW.settlement_terms_id IS DISTINCT FROM OLD.settlement_terms_id
     OR NEW.qa_policy IS DISTINCT FROM OLD.qa_policy
     OR NEW.mei_in_kind_cents IS DISTINCT FROM OLD.mei_in_kind_cents
     OR NEW.qa_in_kind_cents IS DISTINCT FROM OLD.qa_in_kind_cents
     OR NEW.qa_cash_cents IS DISTINCT FROM OLD.qa_cash_cents
     OR NEW.cash_adjustment_cents IS DISTINCT FROM OLD.cash_adjustment_cents
     OR (OLD.pricing_rule_version >= 4 AND (
           NEW.benefit_settlement_mode IS DISTINCT FROM OLD.benefit_settlement_mode
           OR NEW.total_monetary_funding_required_cents IS DISTINCT FROM OLD.total_monetary_funding_required_cents
           OR NEW.cash_user_pool_funding_cents IS DISTINCT FROM OLD.cash_user_pool_funding_cents
           OR NEW.mei_cash_funding_cents IS DISTINCT FROM OLD.mei_cash_funding_cents)) THEN
    RAISE EXCEPTION 'pedido_imutavel: liquidacao por modalidade e imutavel (id=%)', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.ceo_liquidacao_v15_imutavel() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ceo_liquidacao_v15_imutavel
  BEFORE UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_liquidacao_v15_imutavel();

-- Conferência do pedido contra os termos (usada pelo instrumento e pela
-- auditoria). Não confia em nenhuma coluna isolada.
CREATE FUNCTION public.commercial_order_settlement_check(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_o public.commercial_exclusivity_orders%ROWTYPE;
  v_t public.commercial_settlement_terms%ROWTYPE;
BEGIN
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;
  IF v_o.pricing_rule_version IS NULL OR v_o.pricing_rule_version < 4 THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'applies', false);
  END IF;
  SELECT * INTO v_t FROM public.commercial_settlement_terms WHERE id = v_o.settlement_terms_id;
  IF NOT FOUND
     OR v_t.pricing_rule_version <> v_o.pricing_rule_version
     OR v_t.fidelized <> v_o.fidelized
     OR v_t.benefit_settlement_mode IS DISTINCT FROM v_o.benefit_settlement_mode
     OR v_t.commercial_category <> (CASE WHEN v_o.niche_code = 'supermarket' THEN 'supermarket' ELSE 'common' END) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'settlement_terms_mismatch', 'order_id', v_o.id);
  END IF;
  IF v_o.economic_value_cents <> v_t.economic_value_cents
     OR v_o.mei_consideration_cents IS DISTINCT FROM v_t.mei_consideration_cents
     OR v_o.mei_in_kind_cents IS DISTINCT FROM v_t.mei_in_kind_cents
     OR v_o.mei_cash_funding_cents IS DISTINCT FROM v_t.mei_cash_cents
     OR v_o.smallflags_main_fee_cents IS DISTINCT FROM v_t.smallflags_main_fee_cents
     OR v_o.qa_in_kind_cents IS DISTINCT FROM v_t.qa_in_kind_cents
     OR v_o.qa_cash_cents IS DISTINCT FROM v_t.qa_cash_cents
     OR v_o.cash_adjustment_cents IS DISTINCT FROM v_t.cash_adjustment_cents
     OR v_o.total_monetary_funding_required_cents IS DISTINCT FROM v_t.total_monetary_funding_required_cents THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'settlement_snapshot_diverges_from_terms', 'order_id', v_o.id);
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'applies', true,
    'settlement_terms_id', v_t.id, 'benefit_settlement_mode', v_t.benefit_settlement_mode);
END $$;
REVOKE ALL ON FUNCTION public.commercial_order_settlement_check(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ===========================================================================
-- D. PAGAMENTO: UM ÚNICO INVARIANTE
-- ---------------------------------------------------------------------------
-- O valor recebido e confirmado é o total monetário exigível do snapshot
-- imutável do pedido — nos três caminhos (provedor, admin_confirm_commercial_
-- funding, admin_confirm_manual_bdflow_payment). Vale só na TRANSIÇÃO para
-- 'confirmed': nenhuma linha histórica é revalidada nem reescrita.
-- ===========================================================================
CREATE FUNCTION public.ceo_pagamento_confere_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF NEW.payment_status = 'confirmed'
     AND (TG_OP = 'INSERT' OR OLD.payment_status IS DISTINCT FROM 'confirmed') THEN
    IF NEW.total_monetary_funding_required_cents IS NULL THEN
      RAISE EXCEPTION 'pagamento_sem_snapshot_monetario: pedido % sem total exigivel', NEW.id
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.payment_amount_cents IS DISTINCT FROM NEW.total_monetary_funding_required_cents THEN
      RAISE EXCEPTION 'pagamento_divergente_do_snapshot: confirmado %, exigivel % (pedido %)',
        NEW.payment_amount_cents, NEW.total_monetary_funding_required_cents, NEW.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.ceo_pagamento_confere_snapshot() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ceo_pagamento_confere_snapshot
  BEFORE INSERT OR UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_pagamento_confere_snapshot();

-- A tentativa no provedor nasce com o valor do snapshot, nunca com outro.
CREATE FUNCTION public.cp_valor_confere_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_total bigint;
BEGIN
  SELECT total_monetary_funding_required_cents INTO v_total
    FROM public.commercial_exclusivity_orders WHERE id = NEW.commercial_order_id;
  IF v_total IS NULL OR NEW.amount_cents IS DISTINCT FROM v_total THEN
    RAISE EXCEPTION 'pagamento_divergente_do_snapshot: tentativa %, exigivel %', NEW.amount_cents, v_total
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cp_valor_confere_pedido() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cp_valor_confere_pedido
  BEFORE INSERT ON public.commercial_payments
  FOR EACH ROW EXECUTE FUNCTION public.cp_valor_confere_pedido();

-- ===========================================================================
-- E. REUTILIZAÇÃO DE BANDEIRAS REVALIDADA NA CRIAÇÃO E NA CONFIRMAÇÃO (A1)
-- ---------------------------------------------------------------------------
-- A intenção validou a inspeção; o pedido a COPIA. Entre um e outro (e até a
-- confirmação do pagamento) o conjunto pode ser retirado ou receber inspeção
-- mais nova. Vale só o estado efetivo naquele momento.
-- ===========================================================================
CREATE FUNCTION public.ceo_revalidar_reutilizacao_bandeiras()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_s public.commercial_flag_sets%ROWTYPE;
  v_ultima uuid;
  v_res text;
BEGIN
  IF NEW.flag_reuse_inspection_id IS NULL OR NEW.status = 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND NOT (NEW.payment_status = 'confirmed'
                               AND OLD.payment_status IS DISTINCT FROM 'confirmed') THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_s FROM public.commercial_flag_sets WHERE id = NEW.flag_reuse_set_id;
  IF NOT FOUND OR v_s.status <> 'active' OR v_s.company_id <> NEW.company_id
     OR v_s.fidelity_identity IS DISTINCT FROM
        public.commercial_fidelity_identity(NEW.niche_code, NEW.segment_id) THEN
    RAISE EXCEPTION 'flag_reuse_stale: conjunto % nao esta ativo para esta empresa e identidade', NEW.flag_reuse_set_id
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT id, conservation_result INTO v_ultima, v_res
    FROM public.commercial_flag_set_inspections
   WHERE flag_set_id = v_s.id
   ORDER BY inspected_at DESC, created_at DESC
   LIMIT 1;
  IF v_ultima IS DISTINCT FROM NEW.flag_reuse_inspection_id OR v_res IS DISTINCT FROM 'reusable' THEN
    RAISE EXCEPTION 'flag_reuse_stale: inspecao % nao e a vigente e aprovada do conjunto', NEW.flag_reuse_inspection_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.ceo_revalidar_reutilizacao_bandeiras() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ceo_revalidar_reutilizacao_bandeiras
  AFTER INSERT OR UPDATE OF payment_status ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_revalidar_reutilizacao_bandeiras();

-- ===========================================================================
-- H. AUTOATENDIMENTO BLOQUEADO NO BANCO (a trava do navegador vira reforço)
-- ---------------------------------------------------------------------------
-- Nenhuma reserva (intenção de checkout) nasce sob versão abaixo da mínima.
-- Mínima 4: a SF-v1.4 não é vendida pelo autoatendimento, nem por chamada
-- direta à RPC; a SF-v1.5 só depois da ativação autorizada. Venda manual
-- administrativa não passa por aqui (decisão registrada no relatório).
-- ===========================================================================
CREATE TABLE public.commercial_checkout_gate (
  singleton                boolean PRIMARY KEY DEFAULT true,
  min_pricing_rule_version integer NOT NULL,
  reason                   text    NOT NULL,
  updated_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ccg_singleton CHECK (singleton),
  CONSTRAINT ccg_reason CHECK (length(btrim(reason)) >= 10),
  CONSTRAINT ccg_versao CHECK (min_pricing_rule_version >= 1)
);
ALTER TABLE public.commercial_checkout_gate ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_checkout_gate FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO public.commercial_checkout_gate (min_pricing_rule_version, reason)
VALUES (4, 'R3 2026-11-13: autoatendimento so com a SF-v1.5 ativada pelo procedimento autorizado');

CREATE FUNCTION public.commercial_checkout_gate_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'checkout_gate_imutavel: o portao nao e apagado' USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_checkout_gate_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ccg_protect
  BEFORE UPDATE OR DELETE ON public.commercial_checkout_gate
  FOR EACH ROW EXECUTE FUNCTION public.commercial_checkout_gate_protect();
CREATE TRIGGER ccg_protect_truncate
  BEFORE TRUNCATE ON public.commercial_checkout_gate
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

CREATE FUNCTION public.cci_portao_autoatendimento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_min integer;
BEGIN
  SELECT min_pricing_rule_version INTO v_min FROM public.commercial_checkout_gate;
  IF v_min IS NULL OR NEW.pricing_rule_version IS NULL OR NEW.pricing_rule_version < v_min THEN
    RAISE EXCEPTION 'checkout_bloqueado: autoatendimento indisponivel para a versao % (minima %)',
      NEW.pricing_rule_version, v_min USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cci_portao_autoatendimento() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cci_portao_autoatendimento
  BEFORE INSERT ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.cci_portao_autoatendimento();

-- R3: cci_aplicar_autoridade_v14 deixa a versao >= 4 para o gatilho de modalidade (v3 identica).
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
  -- R3: a versao >= 4 tem composicao POR MODALIDADE, resolvida por
  -- *_liquidar_modalidade_v15. Aqui so a SF-v1.4 (versao 3), intacta.
  IF NEW.pricing_rule_version >= 4 THEN
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

-- R3: ceo_aplicar_autoridade_v14 deixa a versao >= 4 para o gatilho de modalidade (v3 identica).
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
  -- R3: a versao >= 4 tem composicao POR MODALIDADE, resolvida por
  -- *_liquidar_modalidade_v15. Aqui so a SF-v1.4 (versao 3), intacta.
  IF NEW.pricing_rule_version >= 4 THEN
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

-- ===========================================================================
-- D (cont.). Pagamento manual alinhado ao snapshot (A5)
-- ===========================================================================
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

  -- R3 / A5: UM invariante para os três caminhos de confirmação. O valor
  -- confirmado é o total monetário EXIGÍVEL do snapshot imutável do pedido
  -- (o mesmo que o provedor cobra e admin_confirm_commercial_funding confere).
  -- Antes, sob a versão >= 3, conferia-se a remuneração da SmallFlags: no
  -- modo dinheiro isso marcava como pago um pedido que também exigia as
  -- contraprestações dos participantes.
  v_esperado := v_ord.total_monetary_funding_required_cents;
  IF v_esperado IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'funding_snapshot_missing');
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

-- ===========================================================================
-- F. INSTRUMENTO: o modelo declara o modelo de liquidação que redige (A6)
-- ---------------------------------------------------------------------------
-- NULL = redação histórica (SF-v1.4, QA monetária). Um pedido só é
-- individualizado por modelo cujo settlement_model é a política de QA da sua
-- versão: pedido v4 nunca usa minuta v1.4, e pedido v3 nunca usa minuta R3.
-- Nenhum modelo existente é alterado.
-- ===========================================================================
ALTER TABLE public.commercial_instrument_templates
  ADD COLUMN settlement_model text;
ALTER TABLE public.commercial_instrument_templates
  ADD CONSTRAINT cit_settlement_model_valido
  CHECK (settlement_model IS NULL OR settlement_model = 'in_kind_direct_benefits_only');
COMMENT ON COLUMN public.commercial_instrument_templates.settlement_model IS
  'R3: modelo de liquidacao que a redacao implementa. in_kind_direct_benefits_only '
  '= QA so em produtos no beneficio direto. NULL = redacao historica (SF-v1.4).';

-- ===========================================================================
-- G. ATIVAÇÃO SÓ PELO PROCEDIMENTO AUTORIZADO, COM PRÉ-CONDIÇÕES NO BANCO
-- ---------------------------------------------------------------------------
-- A2 pré-requisitos, A3 UPDATE direto, A4 QA, A5 pagamento manual, A6
-- contratos. O gatilho cpr_protect exige, na transição prepared -> active de
-- versão >= 4, (1) registro de ativação na MESMA transação, gravado por
-- admin_activate_pricing_rule, e (2) a pré-verificação aprovada. A superação
-- da versão vigente também só ocorre dentro de uma ativação registrada.
-- ===========================================================================
CREATE TABLE public.commercial_pricing_activation_log (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_rule_version    integer NOT NULL REFERENCES public.commercial_pricing_rules(version),
  authorization_reference text    NOT NULL,
  preflight               jsonb   NOT NULL,
  actor                   text    NOT NULL DEFAULT session_user,
  txid                    bigint  NOT NULL DEFAULT txid_current(),
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cpal_autorizacao CHECK (length(btrim(authorization_reference)) >= 10)
);
ALTER TABLE public.commercial_pricing_activation_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_pricing_activation_log FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.commercial_pricing_activation_log_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  RAISE EXCEPTION 'activation_log_imutavel: registro de ativacao nao muda nem e apagado'
    USING ERRCODE = 'check_violation';
END $$;
REVOKE ALL ON FUNCTION public.commercial_pricing_activation_log_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cpal_protect
  BEFORE UPDATE OR DELETE ON public.commercial_pricing_activation_log
  FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_log_protect();
CREATE TRIGGER cpal_protect_truncate
  BEFORE TRUNCATE ON public.commercial_pricing_activation_log
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- Pré-verificação: devolve TODAS as pendências, não só a primeira.
CREATE FUNCTION public.commercial_pricing_activation_preflight(p_version integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
    IF NOT EXISTS (SELECT 1 FROM public.commercial_instrument_templates t
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
        ('commercial_payments', 'cp_valor_confere_pedido')) AS x(tabela, nome)
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
END $$;
REVOKE ALL ON FUNCTION public.commercial_pricing_activation_preflight(integer) FROM PUBLIC, anon, authenticated, service_role;

-- Único caminho de ativação. Só o dono do banco executa.
CREATE FUNCTION public.admin_activate_pricing_rule(
  p_version integer, p_authorization_reference text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
    (pricing_rule_version, authorization_reference, preflight)
  VALUES (p_version, btrim(p_authorization_reference), v_pre);

  SELECT version INTO v_anterior FROM public.commercial_pricing_rules WHERE status = 'active';
  UPDATE public.commercial_pricing_rules SET status = 'superseded'
   WHERE status = 'active' AND version < p_version;
  UPDATE public.commercial_pricing_rules SET status = 'active', effective_from = pg_catalog.now()
   WHERE version = p_version;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'activated_version', p_version,
    'superseded_version', v_anterior);
END $$;
REVOKE ALL ON FUNCTION public.admin_activate_pricing_rule(integer, text) FROM PUBLIC, anon, authenticated, service_role;

-- G (cont.). cpr_protect com a trava de ativação
CREATE OR REPLACE FUNCTION public.commercial_pricing_rules_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_pre jsonb;
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
  -- R3 (A2/A3/A4/A5/A6): versão >= 4 só fica vigente pela ativação
  -- registrada NESTA transação e com a pré-verificação aprovada; a versão
  -- vigente só é superada dentro de uma ativação registrada.
  IF OLD.status = 'prepared' AND NEW.status = 'active' AND OLD.version >= 4 THEN
    IF NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log l
                    WHERE l.pricing_rule_version = OLD.version
                      AND l.txid = pg_catalog.txid_current()) THEN
      RAISE EXCEPTION 'ativacao_nao_autorizada: versao % so e ativada por admin_activate_pricing_rule', OLD.version
        USING ERRCODE = 'check_violation';
    END IF;
    v_pre := public.commercial_pricing_activation_preflight(OLD.version);
    IF (v_pre->>'ok')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'ativacao_pre_requisitos_pendentes: %', v_pre->'failures'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF OLD.status = 'active' AND NEW.status = 'superseded'
     AND NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log l
                      WHERE l.pricing_rule_version > OLD.version
                        AND l.txid = pg_catalog.txid_current()) THEN
    RAISE EXCEPTION 'superacao_nao_autorizada: versao % so e superada pela ativacao registrada de versao posterior', OLD.version
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
END $$;

-- ===========================================================================
-- I. PREÇO PÚBLICO POR MODALIDADE (versão >= 4)
-- ===========================================================================
CREATE FUNCTION public.commercial_settlement_public_v15(
  p_version integer, p_qa_policy text, p_niche_code text, p_fidelized boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_d public.commercial_settlement_terms%ROWTYPE;
  v_c public.commercial_settlement_terms%ROWTYPE;
BEGIN
  v_d := public.commercial_settlement_terms_for(p_version, p_niche_code, p_fidelized, 'direct_benefits');
  v_c := public.commercial_settlement_terms_for(p_version, p_niche_code, p_fidelized, 'cash');
  RETURN pg_catalog.jsonb_build_object(
    'qa_policy', p_qa_policy,
    'settlement_modes', pg_catalog.jsonb_build_object(
      'direct_benefits', public.commercial_settlement_mode_json(v_d),
      'cash', public.commercial_settlement_mode_json(v_c)),
    -- Remuneração MONETÁRIA da SmallFlags: a parcela principal, sem a QA.
    'smallflags_total_remuneration_cents', v_d.smallflags_main_fee_cents,
    'funding_direct_benefits_cents', v_d.total_monetary_funding_required_cents,
    'funding_cash_cents', v_c.total_monetary_funding_required_cents,
    'qa_in_kind_deliverable_cents', v_d.qa_in_kind_cents);
END $$;
REVOKE ALL ON FUNCTION public.commercial_settlement_public_v15(integer, text, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
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
         'flag_reuse_required', p_fidelized) END
    -- R3: versão >= 4 publica a composição POR MODALIDADE. As chaves legadas
    -- descrevem o benefício direto (referência da agenda); a modalidade sem
    -- preço aprovado vem como null e não é contratável.
    || CASE WHEN v_rule.version >= 4 THEN public.commercial_settlement_public_v15(
         v_rule.version, v_rule.qa_policy, p_niche_code, p_fidelized)
       ELSE '{}'::jsonb END;
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
$function$;

-- J. Resposta da reserva com a composição da modalidade
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
    'flag_reuse', (p_i.flag_reuse_set_id IS NOT NULL))
  -- R3: composição da modalidade (NULL nas versões históricas).
  || pg_catalog.jsonb_build_object(
    'qa_policy', p_i.qa_policy,
    'settlement_terms_id', p_i.settlement_terms_id,
    'mei_in_kind_cents', p_i.mei_in_kind_cents,
    'mei_cash_funding_cents', p_i.mei_cash_funding_cents,
    'qa_in_kind_cents', p_i.qa_in_kind_cents,
    'qa_cash_cents', p_i.qa_cash_cents,
    'cash_adjustment_cents', p_i.cash_adjustment_cents);
$function$;

-- F (cont.). Construtor do instrumento: modelo × política (A6)
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
      'cash_adjustment_cents', v_o.cash_adjustment_cents);
    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'qa_policy', 'contract_economics_authority',
      'settlement_terms_id', 'contract_economics_authority',
      'mei_in_kind_cents', 'contract_economics_authority',
      'mei_cash_funding_cents', 'contract_economics_authority',
      'qa_in_kind_cents', 'contract_economics_authority',
      'qa_cash_cents', 'contract_economics_authority',
      'cash_adjustment_cents', 'contract_economics_authority');
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
$function$;

-- ===========================================================================
-- Z. AUTOVERIFICAÇÃO: SF-v1.4 vigente e intacta; SF-v1.5 preparada, com
-- benefício direto R3 e SEM preço de dinheiro; checkout travado no banco.
-- ===========================================================================
DO $verifica_r3$
BEGIN
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 3) <> 'active'
     OR (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared'
     OR (SELECT qa_policy FROM public.commercial_pricing_rules WHERE version = 3) IS NOT NULL THEN
    RAISE EXCEPTION 'r3_verificacao: estado das regras inesperado';
  END IF;
  IF (SELECT string_agg(format('%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
            economic_value_cents, mei_consideration_cents, smallflags_qa_cents,
            smallflags_main_fee_cents), ';' ORDER BY commercial_category, fidelized)
        FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 3)
     IS DISTINCT FROM
     'common/false/1999900/1192716/6084/801100;common/true/1618800/1192716/6084/420000;'
     || 'supermarket/false/2999900/2385432/12168/602300;supermarket/true/2817600/2385432/12168/420000' THEN
    RAISE EXCEPTION 'r3_verificacao: agenda SF-v1.4 alterada';
  END IF;
  IF (SELECT string_agg(format('%s/%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
            economic_value_cents, mei_in_kind_cents, qa_in_kind_cents, qa_cash_cents,
            total_monetary_funding_required_cents), ';' ORDER BY commercial_category, fidelized)
        FROM public.commercial_settlement_terms
       WHERE pricing_rule_version = 4 AND benefit_settlement_mode = 'direct_benefits')
     IS DISTINCT FROM
     'common/false/2293900/1192716/6084/0/1095100;common/true/1618800/1192716/6084/0/420000;'
     || 'supermarket/false/3293900/2385432/12168/0/896300;supermarket/true/2817600/2385432/12168/0/420000' THEN
    RAISE EXCEPTION 'r3_verificacao: termos do beneficio direto divergem da agenda';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms WHERE benefit_settlement_mode = 'cash') THEN
    RAISE EXCEPTION 'r3_verificacao: preco de dinheiro nao pode nascer nesta migration';
  END IF;
  IF (SELECT min_pricing_rule_version FROM public.commercial_checkout_gate) <> 4 THEN
    RAISE EXCEPTION 'r3_verificacao: portao do autoatendimento';
  END IF;
  IF (public.commercial_pricing_activation_preflight(4)->>'ok')::boolean THEN
    RAISE EXCEPTION 'r3_verificacao: a versao 4 nao pode estar apta a ativar';
  END IF;
END $verifica_r3$;
