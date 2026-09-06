/**
 * ESPELHO LOCAL da precificação comercial.
 *
 * O navegador NUNCA é autoridade de preço: este módulo apenas interpreta e
 * formata o que a RPC devolveu, e permite provar as invariantes localmente.
 * O valor exibido vem sempre de get_public_niche_pricing().
 *
 * Regra vigente: não fidelizado -> primeiras 12 unidades = R$ 19.999,00 e
 * cada unidade acima de 12 = R$ 1.299,00; fidelizado -> toda unidade
 * R$ 1.299,00. Centavos INTEIROS.
 *
 * Os pools de 75%/70% pertencem à V1 e são HISTÓRICOS. A política vigente é
 * a Comercial V2, em src/domain/pricing/commercialV2.ts, que usa razão exata
 * de inteiros. Este módulo continua calculando a V1 para que os pedidos
 * antigos permaneçam legíveis e reproduzíveis.
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
  contractualPoolCents: number;
  bdflowDueCents: number;
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
  if (economic === null || pool === null || due === null) return null;
  if (versao === null || qtd === null) return null;

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

/** Centavos inteiros -> BRL, sem aritmética de ponto flutuante. */
export function formatarCentavos(cents: number): string {
  const sinal = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const inteiros = Math.floor(abs / 100);
  const centavos = abs % 100;
  return `${sinal}R$ ${inteiros.toLocaleString("pt-BR")},${String(centavos).padStart(2, "0")}`;
}
