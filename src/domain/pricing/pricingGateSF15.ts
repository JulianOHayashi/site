import type { PublicNichePricing, NichePricing } from "./contractPricing";

/**
 * Toda modalidade HABILITADA pelo servidor (R4.3) tem composição aprovada e
 * publicada sob a regra R3 (QA só em produtos no benefício direto; sem QA no
 * dinheiro). Com as duas habilitadas (padrão), sem o preço do DINHEIRO nada
 * é contratável — como antes. Somente DINHEIRO: basta o preço do DINHEIRO.
 */
function modalidadesDefinidasNoBloco(b: NichePricing): boolean {
  if (b.qaPolicy !== "in_kind_direct_benefits_only" || b.settlementModes === null) return false;
  const m = b.settlementModes;
  const hab = m.habilitadas ?? AS_DUAS;
  return hab.length > 0 && hab.every((x) => (x === "cash" ? m.cash !== null : true));
}

const AS_DUAS: readonly ("direct_benefits" | "cash")[] = ["direct_benefits", "cash"];

/** Modalidades oferecidas na contratação (as habilitadas pelo servidor). */
export function modalidadesHabilitadas(b: NichePricing): readonly ("direct_benefits" | "cash")[] {
  if (!b.settlementModes) return [];
  return b.settlementModes.habilitadas ?? AS_DUAS;
}

export function modalidadesDefinidas(p: PublicNichePricing): boolean {
  return modalidadesDefinidasNoBloco(p.founding) && modalidadesDefinidasNoBloco(p.fidelized);
}

/**
 * Somente a autoridade SF-v1.5 ativa, com as duas modalidades definidas pelo
 * servidor nas seis posições, permite abrir o checkout. É reforço: o banco já
 * recusa reserva abaixo da versão mínima e modalidade sem preço aprovado.
 */
export function permiteCheckoutSF15(precos: readonly PublicNichePricing[]): boolean {
  return precos.length === 6 && precos.every(p =>
    p.founding.pricingRuleVersion === 4 &&
    p.fidelized.pricingRuleVersion === 4 &&
    modalidadesDefinidas(p)
  );
}
