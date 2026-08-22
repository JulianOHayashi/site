import { describe, it, expect } from "vitest";
import {
  PRICING_RULE_V1,
  computeNichePricing,
  interpretarPrecoPublico,
  formatarCentavos,
} from "../domain/pricing/contractPricing";

/**
 * R5 — Valores canônicos do primeiro lançamento e parser estrito.
 * Os mesmos números são provados no SQL autoritativo (suíte 130).
 */
const NICHOS: Array<[string, number]> = [
  ["supermarket", 24],
  ["pharmacy", 12],
  ["womens_clothing", 12],
  ["mens_clothing", 12],
  ["womens_footwear", 12],
  ["mens_footwear", 12],
];

describe("R5 — valores canônicos", () => {
  const comum = computeNichePricing(PRICING_RULE_V1, "pharmacy", 12, false);
  const superm = computeNichePricing(PRICING_RULE_V1, "supermarket", 24, false);

  it("não fidelizado 12 = R$ 19.999,00", () =>
    expect(comum.economicValueCents).toBe(1_999_900));
  it("não fidelizado 24 = R$ 35.587,00", () =>
    expect(superm.economicValueCents).toBe(3_558_700));
  it("fidelizado 12 = R$ 15.588,00", () =>
    expect(
      computeNichePricing(PRICING_RULE_V1, "pharmacy", 12, true).economicValueCents
    ).toBe(1_558_800));
  it("fidelizado 24 = R$ 31.176,00", () =>
    expect(
      computeNichePricing(PRICING_RULE_V1, "supermarket", 24, true).economicValueCents
    ).toBe(3_117_600));
  it("pool comum = R$ 13.999,30", () =>
    expect(comum.contractualPoolCents).toBe(1_399_930));
  it("devido comum = R$ 5.999,70", () =>
    expect(comum.bdflowDueCents).toBe(599_970));
  it("pool supermercado = R$ 26.690,25", () =>
    expect(superm.contractualPoolCents).toBe(2_669_025));
  it("devido supermercado = R$ 8.896,75", () =>
    expect(superm.bdflowDueCents).toBe(889_675));

  const formacao = NICHOS.map(([c, q]) =>
    computeNichePricing(PRICING_RULE_V1, c, q, false)
  );
  const soma = (f: (p: (typeof formacao)[number]) => number) =>
    formacao.reduce((a, p) => a + f(p), 0);

  it("formação completa: econômico R$ 135.582,00", () =>
    expect(soma((p) => p.economicValueCents)).toBe(13_558_200));
  it("formação completa: pools R$ 96.686,75", () =>
    expect(soma((p) => p.contractualPoolCents)).toBe(9_668_675));
  it("formação completa: devido R$ 38.895,25", () =>
    expect(soma((p) => p.bdflowDueCents)).toBe(3_889_525));

  it("invariante econômico = pool + devido em todas as combinações", () => {
    for (const [c, q] of NICHOS) {
      for (const fid of [true, false]) {
        const p = computeNichePricing(PRICING_RULE_V1, c, q, fid);
        expect(p.economicValueCents).toBe(p.contractualPoolCents + p.bdflowDueCents);
      }
    }
  });
  it("supermercado 75% e demais 70%", () => {
    for (const [c, q] of NICHOS) {
      expect(computeNichePricing(PRICING_RULE_V1, c, q, false).poolBps).toBe(
        c === "supermarket" ? 7500 : 7000
      );
    }
  });
  it("o bloco vigente é de 12 unidades", () => {
    expect(PRICING_RULE_V1.blockUnits).toBe(12);
    // Sob um bloco de 10, o nicho comum de 12 custaria 19.999 + 2 x 1.299.
    expect(
      computeNichePricing(PRICING_RULE_V1, "pharmacy", 12, false).economicValueCents
    ).not.toBe(1_999_900 + 2 * 129_900);
  });
});

describe("R5 — parser estrito da vitrine", () => {
  const bloco = (fid: boolean, over?: Record<string, unknown>) => ({
    ok: true,
    pricing_rule_version: 1,
    niche_code: "pharmacy",
    nominal_quantity: 12,
    fidelized: fid,
    currency: "BRL",
    economic_value_cents: fid ? 1_558_800 : 1_999_900,
    pool_bps: 7000,
    contractual_pool_cents: fid ? 1_091_160 : 1_399_930,
    bdflow_due_cents: fid ? 467_640 : 599_970,
    ...over,
  });
  const resposta = () => ({
    ok: true,
    pricing_rule_version: 1,
    currency: "BRL",
    niches: [
      {
        niche_code: "pharmacy",
        display_name: "Farmácia",
        nominal_quantity: 12,
        founding: bloco(false),
        fidelized: bloco(true),
      },
    ],
  });

  it("resposta canônica é aceita", () => {
    const r = interpretarPrecoPublico(resposta());
    expect(r?.[0].founding.economicValueCents).toBe(1_999_900);
  });
  it("ok=false é rejeitado", () => {
    expect(interpretarPrecoPublico({ ok: false, reason: "x" })).toBeNull();
  });
  it("invariante quebrada pelo servidor é rejeitada", () => {
    const r = resposta();
    r.niches[0].founding.bdflow_due_cents = 1;
    expect(interpretarPrecoPublico(r)).toBeNull();
  });
  it("centavos não inteiros são rejeitados", () => {
    const r = resposta();
    r.niches[0].founding.economic_value_cents = 19_999.5;
    expect(interpretarPrecoPublico(r)).toBeNull();
  });
  it("bloco com ok=false é rejeitado", () => {
    const r = resposta();
    (r.niches[0].founding as Record<string, unknown>).ok = false;
    expect(interpretarPrecoPublico(r)).toBeNull();
  });
  it("lista ausente é rejeitada", () => {
    expect(interpretarPrecoPublico({ ok: true, currency: "BRL" })).toBeNull();
  });
});

describe("R5 — formatação", () => {
  it("centavos inteiros viram BRL sem ponto flutuante", () => {
    expect(formatarCentavos(1_999_900)).toBe("R$ 19.999,00");
    expect(formatarCentavos(1_399_930)).toBe("R$ 13.999,30");
    expect(formatarCentavos(889_675)).toBe("R$ 8.896,75");
    expect(formatarCentavos(5)).toBe("R$ 0,05");
  });
});
