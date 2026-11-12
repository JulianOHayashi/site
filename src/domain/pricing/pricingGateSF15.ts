import type { PublicNichePricing } from "./contractPricing";

/** Somente a autoridade SF-v1.5 ativa permite abrir o checkout. */
export function permiteCheckoutSF15(precos: readonly PublicNichePricing[]): boolean {
  return precos.length === 6 && precos.every(p =>
    p.founding.pricingRuleVersion === 4 &&
    p.fidelized.pricingRuleVersion === 4
  );
}
