/**
 * ESPELHO LOCAL da precificação comercial.
 *
 * O navegador NUNCA é autoridade de preço: este módulo apenas interpreta e
 * formata o que a RPC devolveu, e permite provar as invariantes localmente.
 * O valor exibido vem sempre de get_public_niche_pricing().
 *
 * A regra vigente para contratação nova é recebida da autoridade server-side;
 * este módulo NÃO reconstrói a SF-v1.4. As fórmulas V1 abaixo existem somente
 * para leitura/reprodução histórica e testes de compatibilidade.
 */

export type PricingRule = {
  version: number;
  blockUnits: number;
  blockPriceCents: number;
  extraUnitPriceCents: number;
  fidelizedUnitPriceCents: number;
  poolBpsSupermarket: number;
  poolBpsCommon: number;
};

/** Espelha a versão 1 da migration. */
export const PRICING_RULE_V1: PricingRule = {
  version: 1,
  blockUnits: 12,
  blockPriceCents: 1_999_900,
  extraUnitPriceCents: 129_900,
  fidelizedUnitPriceCents: 129_900,
  poolBpsSupermarket: 7500,
  poolBpsCommon: 7000,
};

export type NichePricing = {
  pricingRuleVersion: number;
  nicheCode: string;
  nominalQuantity: number;
  fidelized: boolean;
  currency: "BRL";
  economicValueCents: number;
  /**
   * Pontos-base do pool. Existe SOMENTE na V1.
   *
   * Na V2 é null de propósito: a participação passou a ser razão exata de
   * inteiros porque nenhum valor inteiro de pontos-base reproduz os centavos
   * aprovados. Preencher aqui um número plausível seria inventar autoridade.
   */
  poolBps: number | null;
  /**
   * Pool contratual INTEIRO. Sob a SF-v1.4 ele inclui a parcela QA da
   * SmallFlags, portanto NÃO é, por si, dinheiro do usuário/MEI. Quem precisa
   * do que é efetivamente do MEI usa `meiConsiderationCents`. Mantido com este
   * nome por compatibilidade com os consumidores existentes.
   */
  contractualPoolCents: number;
  bdflowDueCents: number;
  /**
   * Decomposição explícita da SF-v1.4. `null` sob V1/V2, onde a parcela QA não
   * existia — fingir mei = pool e qa = 0 ali seria inventar história.
   */
  contractEconomicsVersion: string | null;
  meiConsiderationCents: number | null;
  smallflagsQaCents: number | null;
  smallflagsMainFeeCents: number | null;
  smallflagsTotalRemunerationCents: number | null;
  /**
   * Financiamento por modalidade, sempre resolvido pela autoridade do servidor.
   * A UI apenas exibe estes valores; nunca deriva cobrança de pool/fee local.
   */
  directBenefitDeliverableCents: number;
  fundingDirectBenefitsCents: number;
  fundingCashCents: number;
  /** Descritores de exibição da V2. Nunca autoridade de cálculo. */
  displayPoolPercent?: string;
  displayBdflowPercent?: string;
  /** Trilho de pagamento derivado da fidelidade, no servidor. */
  paymentMethod?: "pix" | "credit_card";
};

export function poolBpsForNiche(rule: PricingRule, nicheCode: string): number {
  return nicheCode === "supermarket" ? rule.poolBpsSupermarket : rule.poolBpsCommon;
}

export function economicValueCents(
  rule: PricingRule,
  quantity: number,
  fidelized: boolean
): number {
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw new Error("quantidade nominal invalida");
  }
  if (fidelized) return quantity * rule.fidelizedUnitPriceCents;
  const extras = Math.max(0, quantity - rule.blockUnits);
  return rule.blockPriceCents + extras * rule.extraUnitPriceCents;
}

export function computeNichePricing(
  rule: PricingRule,
  nicheCode: string,
  quantity: number,
  fidelized: boolean
): NichePricing {
  const economic = economicValueCents(rule, quantity, fidelized);
  const bps = poolBpsForNiche(rule, nicheCode);
  const pool = Math.floor((economic * bps) / 10_000);
  return {
    pricingRuleVersion: rule.version,
    nicheCode,
    nominalQuantity: quantity,
    fidelized,
    currency: "BRL",
    economicValueCents: economic,
    poolBps: bps,
    contractualPoolCents: pool,
    bdflowDueCents: economic - pool,
    // Este é o cálculo da V1 por pontos-base. A parcela de QA não existia na
    // V1, então a decomposição é NULL — e não mei = pool, qa = 0, que afirmaria
    // sobre a V1 um fato que só nasceu na SF-v1.4.
    contractEconomicsVersion: null,
    meiConsiderationCents: null,
    smallflagsQaCents: null,
    smallflagsMainFeeCents: null,
    smallflagsTotalRemunerationCents: null,
    directBenefitDeliverableCents: pool,
    fundingDirectBenefitsCents: economic - pool,
    fundingCashCents: economic,
  };
}

export type PublicNichePricing = {
  nicheCode: string;
  displayName: string;
  nominalQuantity: number;
  founding: NichePricing;
  fidelized: NichePricing;
};

/** Parser ESTRITO: formato inesperado devolve null e a UI omite o preço. */
function interpretarBloco(data: unknown, esperaFidelizado: boolean): NichePricing | null {
  if (!data || typeof data !== "object") return null;
  const o = data as Record<string, unknown>;
  if (o.ok !== true) return null;
  const inteiro = (k: string): number | null => {
    const v = o[k];
    const n = typeof v === "string" ? Number(v) : v;
    if (typeof n !== "number" || !Number.isFinite(n) || !Number.isInteger(n)) return null;
    return n;
  };
  const economic = inteiro("economic_value_cents");
  const pool = inteiro("contractual_pool_cents");
  const due = inteiro("bdflow_due_cents");
  const versao = inteiro("pricing_rule_version");
  const qtd = inteiro("nominal_quantity");
  const entregavel = inteiro("direct_benefit_deliverable_cents");
  const fundingDirect = inteiro("funding_direct_benefits_cents");
  const fundingCash = inteiro("funding_cash_cents");
  if (economic === null || pool === null || due === null) return null;
  if (versao === null || qtd === null) return null;
  // Essas três chaves fazem parte do contrato atual da autoridade. Se o
  // backend ainda não estiver migrado, a UI falha fechada em vez de recompor.
  if (entregavel === null || fundingDirect === null || fundingCash === null) return null;
  if (fundingCash !== economic) return null;

  // pool_bps é exigido na V1 e PROIBIDO na V2. Um retorno que traga
  // pontos-base sob a V2 está misturando modelos e falha fechado.
  const bps = o.pool_bps === null || o.pool_bps === undefined ? null : inteiro("pool_bps");
  if (versao <= 1 && bps === null) return null;
  if (versao >= 2 && bps !== null) return null;

  const metodo = o.payment_method;
  if (metodo !== undefined && metodo !== null && metodo !== "pix" && metodo !== "credit_card") {
    return null;
  }
  // Coerência do trilho: fidelizado é cartão, não fidelizado é Pix.
  if (typeof metodo === "string") {
    const esperado = esperaFidelizado ? "credit_card" : "pix";
    if (metodo !== esperado) return null;
  }
  // Invariante do contrato: econômico = pool + devido.
  if (economic !== pool + due) return null;
  if (typeof o.fidelized !== "boolean" || o.fidelized !== esperaFidelizado) return null;
  if (typeof o.niche_code !== "string") return null;

  // Decomposição v1.4. Opcional: só a autoridade ativa a devolve. Quando vem,
  // as duas parcelas TÊM de somar o pool, e a remuneração da SmallFlags tem de
  // ser taxa principal + QA. Divergência falha fechado em vez de exibir número
  // incoerente.
  const mei = inteiro("mei_consideration_cents");
  const qa = inteiro("smallflags_qa_cents");
  const taxa = inteiro("smallflags_main_fee_cents");
  const remun = inteiro("smallflags_total_remuneration_cents");
  const econVer = typeof o.contract_economics_version === "string"
    ? o.contract_economics_version
    : null;
  const temDecomposicao = mei !== null && qa !== null;
  if (versao >= 3 && !temDecomposicao) return null;
  if (temDecomposicao) {
    if (mei + qa !== pool) return null;
    if (taxa === null || remun === null) return null;
    if (remun !== taxa + qa) return null;
    if (taxa !== due) return null;
    if (econVer === null) return null;
    // Sob SF-v1.4, somente a contraprestação do MEI pode ser cumprida como
    // benefício. QA continua dinheiro da SmallFlags.
    if (versao >= 3 && entregavel !== mei) return null;
    if (versao >= 3 && fundingDirect !== remun) return null;
  } else {
    // V1/V2: o pool inteiro era a parcela entregável; o pagamento em benefício
    // direto correspondia ao devido operacional histórico.
    if (entregavel !== pool || fundingDirect !== due) return null;
  }

  return {
    pricingRuleVersion: versao,
    nicheCode: o.niche_code,
    nominalQuantity: qtd,
    fidelized: o.fidelized,
    currency: "BRL",
    economicValueCents: economic,
    poolBps: bps,
    contractualPoolCents: pool,
    bdflowDueCents: due,
    contractEconomicsVersion: temDecomposicao ? econVer : null,
    meiConsiderationCents: temDecomposicao ? mei : null,
    smallflagsQaCents: temDecomposicao ? qa : null,
    smallflagsMainFeeCents: temDecomposicao ? taxa : null,
    smallflagsTotalRemunerationCents: temDecomposicao ? remun : null,
    directBenefitDeliverableCents: entregavel,
    fundingDirectBenefitsCents: fundingDirect,
    fundingCashCents: fundingCash,
    displayPoolPercent: typeof o.display_pool_percent === "string" ? o.display_pool_percent : undefined,
    displayBdflowPercent:
      typeof o.display_bdflow_percent === "string" ? o.display_bdflow_percent : undefined,
    paymentMethod: typeof metodo === "string" ? (metodo as "pix" | "credit_card") : undefined,
  };
}

export function interpretarPrecoPublico(data: unknown): PublicNichePricing[] | null {
  if (!data || typeof data !== "object") return null;
  const o = data as Record<string, unknown>;
  if (o.ok !== true || !Array.isArray(o.niches)) return null;

  const lista: PublicNichePricing[] = [];
  for (const item of o.niches) {
    if (!item || typeof item !== "object") return null;
    const n = item as Record<string, unknown>;
    if (
      typeof n.niche_code !== "string" ||
      typeof n.display_name !== "string" ||
      typeof n.nominal_quantity !== "number"
    ) {
      return null;
    }
    const founding = interpretarBloco(n.founding, false);
    const fidelized = interpretarBloco(n.fidelized, true);
    if (!founding || !fidelized) return null;
    lista.push({
      nicheCode: n.niche_code,
      displayName: n.display_name,
      nominalQuantity: n.nominal_quantity,
      founding,
      fidelized,
    });
  }
  return lista;
}

/**
 * Economia agregada da formação completa, COMO O SERVIDOR DIZ.
 *
 * O navegador não recalcula isto. Antes desta versão a vitrine computava a
 * economia V2 localmente e, depois da SF-v1.4 entrar em vigor, passou a exibir
 * números que o servidor já não reconhecia.
 */
export type FormationEconomicsServer = {
  pricingRuleVersion: number;
  participantTarget: number;
  economicValueCents: number;
  /** Pool INTEIRO. Inclui a parcela QA da SmallFlags; não é dinheiro do MEI. */
  contractualPoolCents: number;
  bdflowOpsInvestmentCents: number;
  /** Decomposição explícita. `null` sob V1/V2. */
  contractEconomicsVersion: string | null;
  meiConsiderationCents: number | null;
  smallflagsQaCents: number | null;
  /** Por MEI completo, sobre a contraprestação dos MEIs — não sobre o pool. */
  perCompleteMeiBaseCents: number | null;
  meiRemainderCents: number | null;
};

/** Parser ESTRITO: formato inesperado devolve null e a UI omite os valores. */
export function interpretarEconomiaFormacao(
  data: unknown
): FormationEconomicsServer | null {
  if (!data || typeof data !== "object") return null;
  const o = data as Record<string, unknown>;
  if (o.ok !== true) return null;
  const inteiro = (k: string): number | null => {
    const v = o[k];
    const n = typeof v === "string" ? Number(v) : v;
    if (typeof n !== "number" || !Number.isFinite(n) || !Number.isInteger(n)) return null;
    return n;
  };
  const versao = inteiro("pricing_rule_version");
  const alvo = inteiro("participant_target");
  const economico = inteiro("economic_value_cents");
  const pool = inteiro("user_pool_cents");
  const devido = inteiro("bdflow_ops_investment_cents");
  if (versao === null || alvo === null || alvo <= 0) return null;
  if (economico === null || pool === null || devido === null) return null;
  // Invariante do contrato: econômico = pool + devido.
  if (economico !== pool + devido) return null;

  const mei = inteiro("mei_consideration_cents");
  const qa = inteiro("smallflags_qa_cents");
  const porMei = inteiro("per_complete_mei_base_cents");
  const restoMei = inteiro("mei_remainder_cents");
  const econVer = typeof o.contract_economics_version === "string"
    ? o.contract_economics_version
    : null;
  const temDecomposicao = mei !== null && qa !== null;
  if (versao >= 3 && !temDecomposicao) return null;
  if (temDecomposicao) {
    // As duas parcelas somam o pool, e o valor por MEI deriva da parcela dos
    // MEIs. Qualquer incoerência falha fechado.
    if (mei + qa !== pool) return null;
    if (porMei === null || restoMei === null) return null;
    if (porMei * alvo + restoMei !== mei) return null;
    if (econVer === null) return null;
  }

  return {
    pricingRuleVersion: versao,
    participantTarget: alvo,
    economicValueCents: economico,
    contractualPoolCents: pool,
    bdflowOpsInvestmentCents: devido,
    contractEconomicsVersion: temDecomposicao ? econVer : null,
    meiConsiderationCents: temDecomposicao ? mei : null,
    smallflagsQaCents: temDecomposicao ? qa : null,
    perCompleteMeiBaseCents: temDecomposicao ? porMei : null,
    meiRemainderCents: temDecomposicao ? restoMei : null,
  };
}

/** Centavos inteiros -> BRL, sem aritmética de ponto flutuante. */
export function formatarCentavos(cents: number): string {
  const sinal = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const inteiros = Math.floor(abs / 100);
  const centavos = abs % 100;
  return `${sinal}R$ ${inteiros.toLocaleString("pt-BR")},${String(centavos).padStart(2, "0")}`;
}
