import { describe, expect, it } from "vitest";
import { permiteCheckoutSF15 } from "../domain/pricing/pricingGateSF15";
import type { PublicNichePricing } from "../domain/pricing/contractPricing";

const item = (version: number) => ({
  founding: { pricingRuleVersion: version },
  fidelized: { pricingRuleVersion: version },
}) as PublicNichePricing;

describe("checkout: preço histórico não pode ser ofertado com SF-v1.5 em preparação", () => {
  it("bloqueia versão 3 vigente e lista vazia",()=> {
    expect(permiteCheckoutSF15(Array(6).fill(item(3)))).toBe(false);
    expect(permiteCheckoutSF15([])).toBe(false);
  });
  it("bloqueia versões mistas ou formação incompleta",()=> {
    expect(permiteCheckoutSF15([...Array(5).fill(item(4)), item(3)])).toBe(false);
    expect(permiteCheckoutSF15(Array(5).fill(item(4)))).toBe(false);
  });
  it("só permite versão 4 confirmada para todas as seis posições",()=>{
    expect(permiteCheckoutSF15(Array(6).fill(item(4)))).toBe(true);
  });
});