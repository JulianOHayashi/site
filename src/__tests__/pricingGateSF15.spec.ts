import { describe, expect, it } from "vitest";
import { permiteCheckoutSF15 } from "../domain/pricing/pricingGateSF15";
import type { PublicNichePricing, SettlementModeTerms } from "../domain/pricing/contractPricing";

const termo = {} as SettlementModeTerms;
const bloco = (version: number, dinheiro: boolean, politica: boolean) => ({
  pricingRuleVersion: version,
  qaPolicy: politica ? "in_kind_direct_benefits_only" : null,
  settlementModes: politica ? { directBenefits: termo, cash: dinheiro ? termo : null } : null,
});
const item = (version: number, dinheiro = true, politica = true) => ({
  founding: bloco(version, dinheiro, politica),
  fidelized: bloco(version, dinheiro, politica),
}) as unknown as PublicNichePricing;

describe("checkout: preço histórico não pode ser ofertado com SF-v1.5 em preparação", () => {
  it("bloqueia versão 3 vigente e lista vazia",()=> {
    expect(permiteCheckoutSF15(Array(6).fill(item(3)))).toBe(false);
    expect(permiteCheckoutSF15([])).toBe(false);
  });
  it("bloqueia versões mistas ou formação incompleta",()=> {
    expect(permiteCheckoutSF15([...Array(5).fill(item(4)), item(3)])).toBe(false);
    expect(permiteCheckoutSF15(Array(5).fill(item(4)))).toBe(false);
  });
  it("só permite versão 4 com as duas modalidades definidas nas seis posições",()=>{
    expect(permiteCheckoutSF15(Array(6).fill(item(4)))).toBe(true);
  });
  it("R3: versão 4 sem preço aprovado do DINHEIRO continua bloqueada",()=>{
    expect(permiteCheckoutSF15(Array(6).fill(item(4, false)))).toBe(false);
    expect(permiteCheckoutSF15([...Array(5).fill(item(4)), item(4, false)])).toBe(false);
    const meio = { founding: bloco(4, true, true), fidelized: bloco(4, false, true) } as unknown as PublicNichePricing;
    expect(permiteCheckoutSF15([...Array(5).fill(item(4)), meio])).toBe(false);
  });
  it("R3: versão 4 sem política de QA declarada pelo servidor continua bloqueada",()=>{
    expect(permiteCheckoutSF15(Array(6).fill(item(4, true, false)))).toBe(false);
  });
});
