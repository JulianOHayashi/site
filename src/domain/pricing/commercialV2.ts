/**
 * COMERCIAL V2 — espelho local da precificação.
 *
 * O navegador NUNCA é autoridade de preço. Este módulo interpreta o que a RPC
 * devolveu e permite provar as invariantes localmente.
 *
 * PREÇO (inalterado entre V1 e V2):
 *   não fidelizado -> primeiras 12 unidades = R$ 19.999,00 (bloco fechado)
 *                     cada unidade acima de 12 = R$ 1.299,00
 *   fidelizado     -> toda unidade = R$ 1.299,00, sem bloco
 *
 * A regra antiga de 10 unidades é histórica e está morta. Não existe em
 * código, teste, migration ou UI.
 *
 * O QUE MUDA NA V2: a repartição do valor econômico.
 *
 * POR QUE PONTOS-BASE NÃO SERVEM
 * A V1 guarda a participação do pool em pontos-base inteiros (7500 / 7000).
 * Os valores aprovados da V2 não cabem ali:
 *
 *   supermercado  2.554.305 / 3.558.700 = 71,7763508...%
 *   comum         1.335.459 / 1.999.900 = 66,7762888...%
 *
 * Arredondar para 7178/6678 produziria centavos diferentes dos aprovados.
 * A V2 guarda a participação como RAZÃO EXATA DE INTEIROS, cujo numerador e
 * denominador são o próprio par (pool, valor econômico) do contrato de
 * referência não fidelizado — assim a razão reproduz os centavos aprovados
 * por construção, e a mesma razão deriva o fidelizado.
 *
 * ARITMÉTICA
 * Tudo em centavos inteiros. Multiplica ANTES de dividir. Ponto flutuante
 * nunca é autoridade: os percentuais são descritores de exibição, guardados
 * como texto aprovado, e não participam de cálculo algum.
 */

export type NicheCategory = "supermarket" | "common";

export type PoolShareRatio = {
  category: NicheCategory;
  /** Par de referência: (pool, econômico) do contrato não fidelizado. */
  numerator: number;
  denominator: number;
  /** Descritor de exibição APROVADO. Nunca é autoridade de cálculo. */
  displayPoolPercent: string;
  displayBdflowPercent: string;
};

export const PRICING_RULE_VERSION_V1 = 1;
export const PRICING_RULE_VERSION_V2 = 2;

export const FOUNDING_BLOCK_UNITS = 12;
export const FOUNDING_BLOCK_PRICE_CENTS = 1_999_900;
export const EXTRA_UNIT_PRICE_CENTS = 129_900;
export const FIDELIZED_UNIT_PRICE_CENTS = 129_900;

export const V2_POOL_SHARES: Record<NicheCategory, PoolShareRatio> = {
  supermarket: {
    category: "supermarket",
    numerator: 2_554_305,
    denominator: 3_558_700,
    displayPoolPercent: "aprox. 71,7763%",
    displayBdflowPercent: "aprox. 28,2237%",
  },
  common: {
    category: "common",
    numerator: 1_335_459,
    denominator: 1_999_900,
    displayPoolPercent: "aprox. 66,7763%",
    displayBdflowPercent: "aprox. 33,2237%",
  },
};

export function categoryForNiche(nicheCode: string): NicheCategory {
  return nicheCode === "supermarket" ? "supermarket" : "common";
}

/** Preço econômico. Idêntico em V1 e V2 — a V2 não mexe em preço. */
export function economicValueCentsV2(quantity: number, fidelized: boolean): number {
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw new Error("quantidade nominal invalida");
  }
  if (fidelized) return quantity * FIDELIZED_UNIT_PRICE_CENTS;
  const extras = Math.max(0, quantity - FOUNDING_BLOCK_UNITS);
  return FOUNDING_BLOCK_PRICE_CENTS + extras * EXTRA_UNIT_PRICE_CENTS;
}

/**
 * Pool em centavos pela razão exata, com divisão inteira por piso.
 *
 * O piso é decisão contratual, não estilo: garante que o pool nunca exceda a
 * participação da categoria, e o centavo fracionário que sobra fica do lado
 * BDFlow/operação/investimentos. Para os contratos de referência a divisão é
 * exata e não há sobra.
 */
export function userPoolCentsV2(economicValueCents: number, category: NicheCategory): number {
  if (!Number.isInteger(economicValueCents) || economicValueCents < 0) {
    throw new Error("valor economico deve ser inteiro em centavos");
  }
  const r = V2_POOL_SHARES[category];
  // Multiplicação antes da divisão. Os produtos aqui ficam bem abaixo de
  // Number.MAX_SAFE_INTEGER para qualquer contrato desta formação.
  const produto = economicValueCents * r.numerator;
  if (!Number.isSafeInteger(produto)) {
    throw new Error("produto excede a faixa segura de inteiros");
  }
  return Math.floor(produto / r.denominator);
}

export type PaymentMethod = "pix" | "credit_card";
export type BenefitSettlementMode = "direct_benefits" | "cash";

export const BENEFIT_SETTLEMENT_MODES: readonly BenefitSettlementMode[] = [
  "direct_benefits",
  "cash",
] as const;

/**
 * Forma de pagamento DERIVA da fidelidade, no servidor.
 *
 * Não é escolha do navegador e não é oferecida como par selecionável. Um
 * pedido não fidelizado de supermercado tem bloco fundador de 12 unidades
 * mais 12 extras — e mesmo assim é UM pagamento em Pix: o bloco é regra de
 * preço, não fronteira de trilho de pagamento.
 */
export function paymentMethodForFidelity(fidelized: boolean): PaymentMethod {
  return fidelized ? "credit_card" : "pix";
}

export type CommercialComposition = {
  pricingRuleVersion: number;
  nicheCode: string;
  category: NicheCategory;
  nominalQuantity: number;
  fidelized: boolean;
  currency: "BRL";
  economicValueCents: number;
  userPoolCents: number;
  bdflowOpsInvestmentCents: number;
  paymentMethod: PaymentMethod;
  displayPoolPercent: string;
  displayBdflowPercent: string;
};

export function computeCommercialCompositionV2(
  nicheCode: string,
  quantity: number,
  fidelized: boolean
): CommercialComposition {
  const category = categoryForNiche(nicheCode);
  const economic = economicValueCentsV2(quantity, fidelized);
  const pool = userPoolCentsV2(economic, category);
  const share = V2_POOL_SHARES[category];
  return {
    pricingRuleVersion: PRICING_RULE_VERSION_V2,
    nicheCode,
    category,
    nominalQuantity: quantity,
    fidelized,
    currency: "BRL",
    economicValueCents: economic,
    userPoolCents: pool,
    // Invariante por construção: econômico = pool + BDFlow/operação.
    bdflowOpsInvestmentCents: economic - pool,
    paymentMethod: paymentMethodForFidelity(fidelized),
    displayPoolPercent: share.displayPoolPercent,
    displayBdflowPercent: share.displayBdflowPercent,
  };
}

/** Financiamento monetário, derivado do modo de liquidação. */
export type FundingBreakdown = {
  benefitSettlementMode: BenefitSettlementMode;
  userPoolCents: number;
  bdflowOpsInvestmentCents: number;
  cashUserPoolFundingCents: number;
  commercialChargeCents: number;
};

/**
 * Modo de liquidação muda apenas QUANTO precisa passar por trilho de
 * pagamento — nunca o valor econômico, o pool nem a fidelidade.
 */
export function fundingForSettlementMode(
  composition: Pick<CommercialComposition, "userPoolCents" | "bdflowOpsInvestmentCents">,
  mode: BenefitSettlementMode
): FundingBreakdown {
  const cash = mode === "cash" ? composition.userPoolCents : 0;
  return {
    benefitSettlementMode: mode,
    userPoolCents: composition.userPoolCents,
    bdflowOpsInvestmentCents: composition.bdflowOpsInvestmentCents,
    cashUserPoolFundingCents: cash,
    commercialChargeCents: composition.bdflowOpsInvestmentCents + cash,
  };
}

/** Formação completa de referência (seis nichos, não fidelizada). */
export const FORMATION_NICHES: ReadonlyArray<{ code: string; quantity: number }> = [
  { code: "supermarket", quantity: 24 },
  { code: "pharmacy", quantity: 12 },
  { code: "womens_clothing", quantity: 12 },
  { code: "mens_clothing", quantity: 12 },
  { code: "womens_footwear", quantity: 12 },
  { code: "mens_footwear", quantity: 12 },
];

export const PARTICIPANT_TARGET_V2 = 84;

export type FormationEconomics = {
  participantTarget: number;
  economicValueCents: number;
  userPoolCents: number;
  bdflowOpsInvestmentCents: number;
  perCompleteUserCents: number;
};

export function formationEconomicsV2(): FormationEconomics {
  let economic = 0;
  let pool = 0;
  for (const n of FORMATION_NICHES) {
    const c = computeCommercialCompositionV2(n.code, n.quantity, false);
    economic += c.economicValueCents;
    pool += c.userPoolCents;
  }
  return {
    participantTarget: PARTICIPANT_TARGET_V2,
    economicValueCents: economic,
    userPoolCents: pool,
    bdflowOpsInvestmentCents: economic - pool,
    // Fecha exatamente porque a política de resíduos distribui os centavos
    // restantes. Ver residualAllocation.ts.
    perCompleteUserCents: pool / PARTICIPANT_TARGET_V2,
  };
}
