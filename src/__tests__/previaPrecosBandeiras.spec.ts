import { describe, expect, it } from "vitest";
import { previaIndividualSF15 } from "../domain/pricing/previewSF15";

const preco = (nicheCode: string, founding: number, fidelized: number, version = 3) => ({
  nicheCode,
  founding: { pricingRuleVersion: version, economicValueCents: founding },
  fidelized: { pricingRuleVersion: version, economicValueCents: fidelized },
});

describe("SF-v1.5 — prévia individual nas oportunidades, sem totais públicos", () => {
  it("supermercado exibe somente preço individual proposto", () => {
    expect(previaIndividualSF15(preco("supermarket", 2999900, 2817600))).toEqual({
      novoCentavos: 3293900,
      fidelizadoReutilizacaoCentavos: 2817600,
      bandeirasNovas: 84,
      custoProducaoIncluidoCentavos: 294000,
    });
  });
  it.each(["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"])(
    "%s usa preços individuais comuns", (code) => {
      expect(previaIndividualSF15(preco(code, 1999900, 1618800))).toEqual({
        novoCentavos: 2293900,
        fidelizadoReutilizacaoCentavos: 1618800,
        bandeirasNovas: 84,
        custoProducaoIncluidoCentavos: 294000,
      });
    },
  );
  it("desaparece quando a SF-v1.5 estiver ativa no servidor", () => {
    expect(previaIndividualSF15(preco("supermarket", 3293900, 2817600, 4))).toBeNull();
  });
  it("não apresenta valores em caso de resposta inesperada da SF-v1.4", () => {
    expect(previaIndividualSF15(preco("supermarket", 1, 2817600))).toBeNull();
    expect(previaIndividualSF15(preco("pharmacy", 1999900, 1))).toBeNull();
    expect(previaIndividualSF15(preco("unknown", 1999900, 1618800))).toBeNull();
  });
  it("o contrato público dos valores propostos não inclui totalização", () => {
    const proposta = previaIndividualSF15(preco("supermarket", 2999900, 2817600));
    expect(proposta).not.toBeNull();
    expect(Object.keys(proposta!)).toEqual([
      "novoCentavos", "fidelizadoReutilizacaoCentavos", "bandeirasNovas",
      "custoProducaoIncluidoCentavos",
    ]);
  });
});
