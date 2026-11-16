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
  /**
   * Dinheiro exigível na modalidade DINHEIRO. `null` só na versão >= 4 (R3)
   * quando o preço dessa modalidade ainda não foi aprovado no servidor: a
   * modalidade não é contratável e nada é estimado no navegador.
   */
  fundingCashCents: number | null;
  /** Descritores de exibição da V2. Nunca autoridade de cálculo. */
  displayPoolPercent?: string;
  displayBdflowPercent?: string;
  /** Trilho de pagamento derivado da fidelidade, no servidor. */
  paymentMethod?: "pix" | "credit_card";
  /**
   * Política de QA declarada pelo servidor (R3, versão >= 4):
   * `in_kind_direct_benefits_only` = QA existe só no benefício direto, em
   * produtos para testes locais; não existe QA em dinheiro nem na modalidade
   * DINHEIRO. `null` nas versões históricas (a SF-v1.4 mantém a QA monetária).
   */
  qaPolicy: QaPolicy | null;
  /**
   * Composição POR MODALIDADE, como o servidor publica (R3). `null` nas
   * versões históricas. `cash: null` = preço da modalidade DINHEIRO ainda não
   * aprovado: nada é presumido e a contratação não é liberada.
   */
  settlementModes: SettlementModes | null;
  /**
   * Produção de bandeiras (SF-v1.5), como o servidor declara. `null` quando a
   * economia vigente não prevê produção (SF-v1.4 e anteriores): nada é
   * presumido nem calculado no navegador.
   */
  flagProduction: FlagProduction | null;
};

/**
 * Fatos de produção de bandeiras de uma condição comercial.
 *
 * `newFlagUnits` é a quantidade de PEÇAS FÍSICAS (84 por anunciante novo). Não
 * é a quantidade comercial do nicho (24 ou 12): as duas nunca se confundem.
 * `flagProductionChargeCents` é a parte do preço que corresponde ao custo
 * nominal de fabricação; ela já está dentro da parcela operacional principal
 * da SmallFlags e nunca é somada de novo.
 */
export type QaPolicy = "in_kind_direct_benefits_only";

/** Composição contratual de UMA modalidade (centavos do servidor). */
export type SettlementModeTerms = {
  economicValueCents: number;
  meiConsiderationCents: number;
  /** Parte dos participantes cumprida em benefícios diretos. */
  meiInKindCents: number;
  /** Parte dos participantes financiada em dinheiro. */
  meiCashCents: number;
  smallflagsMainFeeCents: number;
  /** QA em produtos para testes locais (só benefício direto). */
  qaInKindCents: number;
  /** Sempre 0: não existe QA em dinheiro. */
  qaCashCents: number;
  /** Componente de outra natureza, só no dinheiro e só com fundamento aprovado. */
  cashAdjustmentCents: number;
  totalMonetaryFundingRequiredCents: number;
  ordinaryParticipationValueCents: number;
};

export type SettlementModes = {
  directBenefits: SettlementModeTerms;
  cash: SettlementModeTerms | null;
  /**
   * R4.3: modalidades VENDIDAS nesta versão, publicadas pelo servidor
   * (`enabled_settlement_modes`). Ausente = as duas (servidor anterior).
   * O site só oferece as habilitadas; o banco recusa as demais.
   */
  habilitadas?: readonly ("direct_benefits" | "cash")[];
};

export type FlagProduction = {
  newFlagUnits: number;
  flagUnitReferenceCents: number;
  flagProductionChargeCents: number;
  /** Fidelizado: o preço pressupõe reutilização verificada das peças. */
  reuseRequired: boolean;
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
    qaPolicy: null,
    settlementModes: null,
    // A V1 não tinha produção de bandeiras: nada a declarar.
    flagProduction: null,
  };
}

export type PublicNichePricing = {
  nicheCode: string;
  displayName: string;
  nominalQuantity: number;
  founding: NichePricing;
  fidelized: NichePricing;
};

/**
 * Composição de uma modalidade (R3). Impõe as MESMAS invariantes do CHECK do
 * servidor: QA só em produtos e só no benefício direto; nenhuma QA em
 * dinheiro; nenhum centavo atribuído duas vezes.
 */
function interpretarModalidade(
  data: unknown,
  modo: "direct_benefits" | "cash",
): SettlementModeTerms | null {
  if (!data || typeof data !== "object") return null;
  const o = data as Record<string, unknown>;
  if (o.benefit_settlement_mode !== modo) return null;
  const n = (k: string): number | null => {
    const v = o[k];
    const x = typeof v === "string" ? Number(v) : v;
    if (typeof x !== "number" || !Number.isFinite(x) || !Number.isInteger(x) || x < 0) return null;
    return x;
  };
  const t = {
    economicValueCents: n("economic_value_cents"),
    meiConsiderationCents: n("mei_consideration_cents"),
    meiInKindCents: n("mei_in_kind_cents"),
    meiCashCents: n("mei_cash_cents"),
    smallflagsMainFeeCents: n("smallflags_main_fee_cents"),
    qaInKindCents: n("qa_in_kind_cents"),
    qaCashCents: n("qa_cash_cents"),
    cashAdjustmentCents: n("cash_adjustment_cents"),
    totalMonetaryFundingRequiredCents: n("total_monetary_funding_required_cents"),
    ordinaryParticipationValueCents: n("ordinary_participation_value_cents"),
  };
  if (Object.values(t).some((v) => v === null)) return null;
  const m = t as SettlementModeTerms;
  if (m.economicValueCents <= 0 || m.ordinaryParticipationValueCents <= 0) return null;
  if (m.qaCashCents !== 0) return null;
  if (modo === "direct_benefits") {
    if (m.meiInKindCents !== m.meiConsiderationCents || m.meiCashCents !== 0) return null;
    if (m.cashAdjustmentCents !== 0) return null;
    if (m.economicValueCents !== m.meiConsiderationCents + m.smallflagsMainFeeCents + m.qaInKindCents) return null;
    if (m.totalMonetaryFundingRequiredCents !== m.smallflagsMainFeeCents) return null;
  } else {
    if (m.qaInKindCents !== 0 || m.meiInKindCents !== 0) return null;
    if (m.meiCashCents !== m.meiConsiderationCents) return null;
    if (m.economicValueCents !== m.meiConsiderationCents + m.smallflagsMainFeeCents + m.cashAdjustmentCents) return null;
    if (m.totalMonetaryFundingRequiredCents !== m.economicValueCents) return null;
  }
  return m;
}

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
  // R3 (versão >= 4): o dinheiro da modalidade DINHEIRO pode ainda não ter
  // preço aprovado (null); nas versões históricas ele é sempre o econômico.
  const r3 = versao >= 4;
  if (entregavel === null || fundingDirect === null) return null;
  if (!r3 && (fundingCash === null || fundingCash !== economic)) return null;
  if (r3 && o.funding_cash_cents !== null && fundingCash === null) return null;

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
    if (taxa !== due) return null;
    if (econVer === null) return null;
    if (r3) {
      // R3: a remuneração MONETÁRIA da SmallFlags é a parcela principal; a QA
      // (só em produtos, só no benefício direto) fica fora dela e fora do
      // dinheiro devido. As chaves legadas descrevem o benefício direto.
      if (remun !== taxa) return null;
      if (entregavel !== mei) return null;
      if (fundingDirect !== taxa) return null;
    } else {
      // SF-v1.4 (histórico preservado): QA dentro da remuneração monetária;
      // só a contraprestação do MEI pode ser cumprida como benefício.
      if (remun !== taxa + qa) return null;
      if (versao >= 3 && entregavel !== mei) return null;
      if (versao >= 3 && fundingDirect !== remun) return null;
    }
  } else {
    // V1/V2: o pool inteiro era a parcela entregável; o pagamento em benefício
    // direto correspondia ao devido operacional histórico.
    if (entregavel !== pool || fundingDirect !== due) return null;
  }

  // A chave `qa_settlement_mode` (R2) foi substituída pela política e pelos
  // blocos por modalidade da R3. Um servidor que ainda a envie está fora do
  // contrato atual: falha fechada.
  if ("qa_settlement_mode" in o) return null;

  // R3: política de QA e composição POR MODALIDADE, só na versão >= 4.
  let qaPolicy: QaPolicy | null = null;
  let settlementModes: SettlementModes | null = null;
  if (r3) {
    if (o.qa_policy !== "in_kind_direct_benefits_only") return null;
    const modos = o.settlement_modes as Record<string, unknown> | null | undefined;
    if (!modos || typeof modos !== "object") return null;
    const direto = interpretarModalidade(modos.direct_benefits, "direct_benefits");
    if (!direto) return null;
    if (!("cash" in modos)) return null;
    const dinheiro = modos.cash === null ? null : interpretarModalidade(modos.cash, "cash");
    if (modos.cash !== null && !dinheiro) return null;
    // As chaves legadas e o bloco do benefício direto descrevem o MESMO fato.
    if (!temDecomposicao || taxa === null) return null;
    if (direto.economicValueCents !== economic || direto.meiConsiderationCents !== mei
        || direto.smallflagsMainFeeCents !== taxa || direto.qaInKindCents !== qa
        || direto.totalMonetaryFundingRequiredCents !== fundingDirect) return null;
    if (dinheiro) {
      // Mesmos participantes e mesma parcela principal: a retirada da QA não
      // vira remuneração por inferência.
      if (dinheiro.meiConsiderationCents !== mei || dinheiro.smallflagsMainFeeCents !== taxa) return null;
      if (dinheiro.ordinaryParticipationValueCents !== direto.ordinaryParticipationValueCents) return null;
      if (fundingCash !== dinheiro.totalMonetaryFundingRequiredCents) return null;
    } else if (fundingCash !== null) {
      return null;
    }
    // R4.3: modalidades habilitadas. Valor fora do contrato: falha fechada.
    const hab = o.enabled_settlement_modes;
    let habilitadas: ("direct_benefits" | "cash")[];
    if (hab === undefined || hab === null) {
      habilitadas = ["direct_benefits", "cash"];
    } else if (Array.isArray(hab) && hab.length >= 1 && hab.length <= 2
               && hab.every((x) => x === "direct_benefits" || x === "cash")
               && new Set(hab).size === hab.length) {
      habilitadas = hab as ("direct_benefits" | "cash")[];
    } else {
      return null;
    }
    qaPolicy = "in_kind_direct_benefits_only";
    settlementModes = { directBenefits: direto, cash: dinheiro, habilitadas };
  } else if ("qa_policy" in o || "settlement_modes" in o) {
    // Versões históricas não têm QA por modalidade.
    return null;
  }

  // Produção de bandeiras: tudo ou nada, e coerente com a regra do servidor.
  const pecas = inteiro("new_flag_units");
  const unitario = inteiro("flag_unit_reference_cents");
  const fabricacao = inteiro("flag_production_charge_cents");
  const algumaChave = ["new_flag_units", "flag_unit_reference_cents",
    "flag_production_charge_cents", "flag_reuse_required"].some((k) => k in o);
  let flagProduction: FlagProduction | null = null;
  if (algumaChave) {
    if (pecas === null || unitario === null || fabricacao === null) return null;
    if (typeof o.flag_reuse_required !== "boolean") return null;
    if (!temDecomposicao || taxa === null) return null;
    if (pecas < 0 || unitario <= 0 || fabricacao !== pecas * unitario) return null;
    if (fabricacao > taxa) return null;
    // Fidelizado: zero peças novas e reutilização exigida. Não fidelizado:
    // peças novas e nenhuma reutilização.
    if (esperaFidelizado !== o.flag_reuse_required) return null;
    if (esperaFidelizado ? pecas !== 0 : pecas <= 0) return null;
    flagProduction = {
      newFlagUnits: pecas,
      flagUnitReferenceCents: unitario,
      flagProductionChargeCents: fabricacao,
      reuseRequired: o.flag_reuse_required,
    };
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
    qaPolicy,
    settlementModes,
    flagProduction,
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
