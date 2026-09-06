import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  computeCommercialCompositionV2,
  economicValueCentsV2,
  userPoolCentsV2,
  formationEconomicsV2,
  fundingForSettlementMode,
  paymentMethodForFidelity,
  V2_POOL_SHARES,
  BENEFIT_SETTLEMENT_MODES,
  FOUNDING_BLOCK_UNITS,
  PARTICIPANT_TARGET_V2,
  type BenefitSettlementMode,
} from "../domain/pricing/commercialV2";
import {
  buildResidualMatrix,
  distributeFormationV2,
  formationPoolsV2,
  poolConservationHolds,
  CANONICAL_NICHE_ORDER,
  DISTRIBUTION_POLICY_VERSION_V2,
} from "../domain/operational/residualAllocation";
import { PRICING_RULE_V1, computeNichePricing } from "../domain/pricing/contractPricing";

const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");

/** Remove comentários TS para que a asserção mire o código, não a explicação. */
const semComentariosTs = (src: string) =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

/** Remove comentários SQL de linha. */
const semComentariosSql = (src: string) => src.replace(/^\s*--.*$/gm, "");

describe("COMERCIAL V2 — preço não muda; a repartição muda", () => {
  it("regra fundadora é de 12 unidades", () => {
    expect(FOUNDING_BLOCK_UNITS).toBe(12);
    expect(economicValueCentsV2(12, false)).toBe(1_999_900);
    // 24 unidades = bloco de 12 + 12 extras a R$ 1.299,00.
    expect(economicValueCentsV2(24, false)).toBe(1_999_900 + 12 * 129_900);
  });

  it("a regra morta de 10 unidades não existe em lugar nenhum do domínio", () => {
    for (const f of [
      "src/domain/pricing/commercialV2.ts",
      "src/domain/pricing/contractPricing.ts",
      "src/domain/operational/residualAllocation.ts",
    ]) {
      const codigo = lerFonte(f)
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/(^|[^:])\/\/.*$/gm, "$1");
      expect(codigo, f).not.toMatch(/blockUnits\s*[:=]\s*10\b/);
      expect(codigo, f).not.toMatch(/FOUNDING_BLOCK_UNITS\s*=\s*10\b/);
    }
  });

  it("centavos exatos aprovados — não fidelizado", () => {
    const s = computeCommercialCompositionV2("supermarket", 24, false);
    expect(s.economicValueCents).toBe(3_558_700);
    expect(s.userPoolCents).toBe(2_554_305);
    expect(s.bdflowOpsInvestmentCents).toBe(1_004_395);

    const c = computeCommercialCompositionV2("pharmacy", 12, false);
    expect(c.economicValueCents).toBe(1_999_900);
    expect(c.userPoolCents).toBe(1_335_459);
    expect(c.bdflowOpsInvestmentCents).toBe(664_441);
  });

  it("centavos exatos aprovados — fidelizado, por piso da mesma razão", () => {
    const s = computeCommercialCompositionV2("supermarket", 24, true);
    expect(s.economicValueCents).toBe(3_117_600);
    expect(s.userPoolCents).toBe(2_237_699);
    expect(s.bdflowOpsInvestmentCents).toBe(879_901);

    const c = computeCommercialCompositionV2("pharmacy", 12, true);
    expect(c.economicValueCents).toBe(1_558_800);
    expect(c.userPoolCents).toBe(1_040_908);
    expect(c.bdflowOpsInvestmentCents).toBe(517_892);
  });

  it("a invariante econômica vale para toda saída V2", () => {
    for (const niche of CANONICAL_NICHE_ORDER) {
      for (const fid of [false, true]) {
        const q = niche === "supermarket" ? 24 : 12;
        const r = computeCommercialCompositionV2(niche, q, fid);
        expect(r.economicValueCents).toBe(r.userPoolCents + r.bdflowOpsInvestmentCents);
        // O piso nunca deixa o pool exceder a participação da categoria.
        const share = V2_POOL_SHARES[r.category];
        expect(r.userPoolCents * share.denominator).toBeLessThanOrEqual(
          r.economicValueCents * share.numerator
        );
      }
    }
  });

  it("a razão de referência reproduz o centavo aprovado sem sobra", () => {
    expect((3_558_700 * V2_POOL_SHARES.supermarket.numerator) % V2_POOL_SHARES.supermarket.denominator).toBe(0);
    expect((1_999_900 * V2_POOL_SHARES.common.numerator) % V2_POOL_SHARES.common.denominator).toBe(0);
    expect(userPoolCentsV2(3_558_700, "supermarket")).toBe(2_554_305);
    expect(userPoolCentsV2(1_999_900, "common")).toBe(1_335_459);
  });

  it("percentuais são descritores de exibição, jamais autoridade", () => {
    expect(V2_POOL_SHARES.supermarket.displayPoolPercent).toBe("aprox. 71,7763%");
    expect(V2_POOL_SHARES.common.displayPoolPercent).toBe("aprox. 66,7763%");
    // Nenhum percentual entra em cálculo: a fonte não converte esses textos.
    const codigo = lerFonte("src/domain/pricing/commercialV2.ts");
    expect(codigo).not.toMatch(/parseFloat\(|Number\(\s*.*displayPoolPercent/);
  });

  it("nenhum ponto-base falso é usado como autoridade V2", () => {
    // Comentários são removidos de propósito: eles CITAM 7178/6678 justamente
    // para registrar por que arredondar seria errado. O que não pode existir
    // é o número no CÓDIGO.
    const codigo = semComentariosTs(lerFonte("src/domain/pricing/commercialV2.ts"));
    for (const falso of ["7178", "7177", "6678", "6677"]) {
      expect(codigo, falso).not.toContain(falso);
    }
  });

  it("nenhuma aritmética monetária de ponto flutuante", () => {
    const codigo = lerFonte("src/domain/pricing/commercialV2.ts")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    expect(codigo).not.toMatch(/Math\.round|toFixed|parseFloat/);
  });

  it("a formação completa fecha nos totais aprovados", () => {
    const f = formationEconomicsV2();
    expect(f.economicValueCents).toBe(13_558_200);
    expect(f.userPoolCents).toBe(9_231_600);
    expect(f.bdflowOpsInvestmentCents).toBe(4_326_600);
    expect(f.participantTarget).toBe(84);
    expect(f.perCompleteUserCents).toBe(109_900);
  });
});

describe("COMERCIAL V2 — histórico V1 preservado", () => {
  it("o cálculo V1 explícito ainda produz os snapshots 75/70", () => {
    const s = computeNichePricing(PRICING_RULE_V1, "supermarket", 24, false);
    expect(s.poolBps).toBe(7500);
    expect(s.economicValueCents).toBe(3_558_700);
    expect(s.contractualPoolCents).toBe(Math.floor((3_558_700 * 7500) / 10_000));

    const c = computeNichePricing(PRICING_RULE_V1, "pharmacy", 12, false);
    expect(c.poolBps).toBe(7000);
    expect(c.contractualPoolCents).toBe(Math.floor((1_999_900 * 7000) / 10_000));
  });

  it("V1 e V2 produzem pools diferentes — a V2 não é a V1 renomeada", () => {
    const v1 = computeNichePricing(PRICING_RULE_V1, "supermarket", 24, false);
    const v2 = computeCommercialCompositionV2("supermarket", 24, false);
    expect(v1.contractualPoolCents).not.toBe(v2.userPoolCents);
    expect(v1.economicValueCents).toBe(v2.economicValueCents);
  });
});

describe("COMERCIAL V2 — matriz de resíduos", () => {
  const d = distributeFormationV2();

  it("84 slots de participante", () => {
    expect(d.participants).toHaveLength(84);
    expect(PARTICIPANT_TARGET_V2).toBe(84);
  });

  it("bases e restos conferem", () => {
    expect(d.baseByNiche.supermarket).toBe(30_408);
    expect(d.remainderByNiche.supermarket).toBe(33);
    for (const n of CANONICAL_NICHE_ORDER) {
      if (n === "supermarket") continue;
      expect(d.baseByNiche[n]).toBe(15_898);
      expect(d.remainderByNiche[n]).toBe(27);
    }
  });

  it("cada nicho atribui seu resíduo a slots DISTINTOS, na contagem exata", () => {
    const esperado: Record<string, number> = {
      supermarket: 33,
      pharmacy: 27,
      womens_clothing: 27,
      mens_clothing: 27,
      womens_footwear: 27,
      mens_footwear: 27,
    };
    for (const n of CANONICAL_NICHE_ORDER) {
      const slots = d.participants.filter((p) => p.byNiche[n] > d.baseByNiche[n]);
      expect(slots.length, n).toBe(esperado[n]);
      // Distintos por construção, e cada um recebe exatamente +1.
      for (const p of slots) expect(p.byNiche[n] - d.baseByNiche[n]).toBe(1);
      expect(new Set(slots.map((p) => p.participantSlot)).size).toBe(esperado[n]);
    }
  });

  it("cada participante recebe +1 de exatamente DOIS nichos distintos", () => {
    for (const p of d.participants) {
      const comResiduo = CANONICAL_NICHE_ORDER.filter(
        (n) => p.byNiche[n] === d.baseByNiche[n] + 1
      );
      expect(comResiduo.length, `slot ${p.participantSlot}`).toBe(2);
      expect(new Set(comResiduo).size).toBe(2);
      // Nunca dois centavos do mesmo nicho.
      for (const n of CANONICAL_NICHE_ORDER) {
        expect(p.byNiche[n] - d.baseByNiche[n]).toBeLessThanOrEqual(1);
      }
    }
  });

  it("todo participante completo totaliza exatamente 109.900 centavos", () => {
    for (const p of d.participants) expect(p.totalCents).toBe(109_900);
  });

  it("o total distribuído é exatamente 9.231.600 centavos", () => {
    expect(d.distributedTotalCents).toBe(9_231_600);
  });

  it("nenhum pool é excedido e nada se perde", () => {
    expect(poolConservationHolds(d)).toBe(true);
    expect(d.poolByNiche.supermarket).toBe(2_554_305);
    expect(d.poolByNiche.pharmacy).toBe(1_335_459);
  });

  it("sete benefícios por participante; as duas etapas somam o supermercado", () => {
    for (const p of d.participants) {
      expect(p.benefits).toHaveLength(7);
      const s1 = p.benefits.find((b) => b.benefitType === "supermarket_stage_1")!;
      const s2 = p.benefits.find((b) => b.benefitType === "supermarket_stage_2")!;
      expect(s1.assignedAmountCents + s2.assignedAmountCents).toBe(p.byNiche.supermarket);
      expect(s1.assignedAmountCents).toBe(Math.floor(p.byNiche.supermarket / 2));
    }
  });

  it("é determinística: duas execuções produzem a mesma matriz", () => {
    const a = distributeFormationV2();
    const b = distributeFormationV2();
    expect(JSON.stringify(a.participants)).toBe(JSON.stringify(b.participants));
    expect(a.policyVersion).toBe(DISTRIBUTION_POLICY_VERSION_V2);
  });

  it("nenhuma fonte de ordenação instável decide alocação", () => {
    const codigo = lerFonte("src/domain/operational/residualAllocation.ts")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    expect(codigo).not.toMatch(/Math\.random|Date\.now|new Date|crypto\.randomUUID/);
  });

  it("falha fechada quando os restos não somam dois por participante", () => {
    expect(() =>
      buildResidualMatrix({
        supermarket: 33,
        pharmacy: 27,
        womens_clothing: 27,
        mens_clothing: 27,
        womens_footwear: 27,
        mens_footwear: 26,
      })
    ).toThrow();
  });

  it("falha fechada quando um nicho teria de dar dois centavos ao mesmo slot", () => {
    // 85 > 84 participantes: impossível manter uma atribuição por slot.
    expect(() =>
      buildResidualMatrix({
        supermarket: 85,
        pharmacy: 27,
        womens_clothing: 27,
        mens_clothing: 27,
        womens_footwear: 1,
        mens_footwear: 1,
      })
    ).toThrow();
  });
});

describe("COMERCIAL V2 — liquidação separada da forma de pagamento", () => {
  it("os dois modos são domínios distintos, não booleano", () => {
    expect(BENEFIT_SETTLEMENT_MODES).toEqual(["direct_benefits", "cash"]);
  });

  it("não fidelizado deriva Pix; fidelizado deriva cartão", () => {
    expect(paymentMethodForFidelity(false)).toBe("pix");
    expect(paymentMethodForFidelity(true)).toBe("credit_card");
  });

  it("supermercado não fidelizado é UM pagamento em Pix, não dois trilhos", () => {
    const s = computeCommercialCompositionV2("supermarket", 24, false);
    expect(s.paymentMethod).toBe("pix");
    // O bloco de 12 é regra de preço, não fronteira de trilho.
    expect(s.economicValueCents).toBe(1_999_900 + 12 * 129_900);
  });

  it("a forma de pagamento independe do modo de liquidação", () => {
    for (const modo of BENEFIT_SETTLEMENT_MODES) {
      for (const fid of [false, true]) {
        const c = computeCommercialCompositionV2("pharmacy", 12, fid);
        const f = fundingForSettlementMode(c, modo);
        expect(c.paymentMethod).toBe(fid ? "credit_card" : "pix");
        expect(f.benefitSettlementMode).toBe(modo);
      }
    }
  });

  it("modo direto não financia o pool em dinheiro", () => {
    const c = computeCommercialCompositionV2("supermarket", 24, false);
    const f = fundingForSettlementMode(c, "direct_benefits");
    expect(f.cashUserPoolFundingCents).toBe(0);
    expect(f.commercialChargeCents).toBe(c.bdflowOpsInvestmentCents);
    expect(f.commercialChargeCents).toBe(1_004_395);
  });

  it("modo dinheiro financia o pool inteiro; a cobrança vira o econômico", () => {
    const c = computeCommercialCompositionV2("supermarket", 24, false);
    const f = fundingForSettlementMode(c, "cash");
    expect(f.cashUserPoolFundingCents).toBe(c.userPoolCents);
    expect(f.commercialChargeCents).toBe(c.economicValueCents);
    expect(f.commercialChargeCents).toBe(3_558_700);
  });

  it("mudar o modo não altera econômico, pool nem fidelidade", () => {
    const c = computeCommercialCompositionV2("pharmacy", 12, false);
    const modos: BenefitSettlementMode[] = ["direct_benefits", "cash"];
    const fs = modos.map((m) => fundingForSettlementMode(c, m));
    for (const f of fs) {
      expect(f.userPoolCents).toBe(c.userPoolCents);
      expect(f.bdflowOpsInvestmentCents).toBe(c.bdflowOpsInvestmentCents);
    }
    expect(c.economicValueCents).toBe(1_999_900);
  });
});

describe("COMERCIAL V2 — fronteira de confiança do cliente", () => {
  it("nenhuma função do domínio aceita preço, pool ou fidelidade vindos do cliente", () => {
    // As assinaturas só admitem nicho, quantidade, fidelidade derivada e modo.
    // Não existe parâmetro para injetar valor monetário.
    const codigo = lerFonte("src/domain/pricing/commercialV2.ts");
    expect(codigo).not.toMatch(/function\s+\w+\([^)]*poolCents\s*:\s*number[^)]*\)\s*:\s*CommercialComposition/);
  });

  it("a RPC de intenção não tem parâmetro de valor", () => {
    const sql = lerFonte("supabase/migrations/20260905120000_post_r16_commercial_v2.sql");
    const assinatura = sql.slice(
      sql.indexOf("CREATE FUNCTION public.create_commercial_checkout_intent"),
      sql.indexOf("RETURNS jsonb", sql.indexOf("CREATE FUNCTION public.create_commercial_checkout_intent"))
    );
    expect(assinatura).toContain("p_company_id uuid");
    expect(assinatura).toContain("p_niche_code text");
    expect(assinatura).not.toMatch(/cents/i);
    expect(assinatura).not.toMatch(/p_price|p_pool|p_fidelized|p_payment_method/i);
  });

  it("a migration não inventa pontos-base para a V2", () => {
    const sql = semComentariosSql(
      lerFonte("supabase/migrations/20260905120000_post_r16_commercial_v2.sql")
    );
    for (const falso of ["7178", "7177", "6678", "6677"]) {
      expect(sql, falso).not.toContain(falso);
    }
    // E a V2 grava NULL em pool_bps em vez de um número plausível.
    expect(sql).toMatch(/NULL,\s*NULL,\s*'exact_ratio'/);
  });

  it("nenhuma das 27 migrations históricas foi editada", () => {
    // A V2 é aditiva: o arquivo da V1 continua com a regra 75/70 intacta.
    const v1 = lerFonte("supabase/migrations/20260822123000_m2_pricing.sql");
    expect(v1).toContain("(1, 'active', 12, 1999900, 129900, 129900, 7500, 7000,");
  });
});

describe("COMERCIAL V2 — matriz 2x2 de liquidação × trilho", () => {
  const casos: Array<[BenefitSettlementMode, boolean, string, "economico" | "bdflow"]> = [
    ["direct_benefits", false, "pix", "bdflow"],
    ["cash", false, "pix", "economico"],
    ["direct_benefits", true, "credit_card", "bdflow"],
    ["cash", true, "credit_card", "economico"],
  ];

  for (const [modo, fid, trilho, cobranca] of casos) {
    it(`${modo} + ${fid ? "fidelizado" : "não fidelizado"} → ${trilho}, cobrança ${cobranca}`, () => {
      const c = computeCommercialCompositionV2("supermarket", 24, fid);
      const f = fundingForSettlementMode(c, modo);
      expect(c.paymentMethod).toBe(trilho);
      expect(f.commercialChargeCents).toBe(
        cobranca === "economico" ? c.economicValueCents : c.bdflowOpsInvestmentCents
      );
      expect(f.cashUserPoolFundingCents).toBe(modo === "cash" ? c.userPoolCents : 0);
      // A invariante econômica não depende do modo.
      expect(c.economicValueCents).toBe(c.userPoolCents + c.bdflowOpsInvestmentCents);
    });
  }

  it("centavos exatos das quatro combinações do supermercado", () => {
    const nf = computeCommercialCompositionV2("supermarket", 24, false);
    expect(fundingForSettlementMode(nf, "direct_benefits").commercialChargeCents).toBe(1_004_395);
    expect(fundingForSettlementMode(nf, "cash").commercialChargeCents).toBe(3_558_700);
    const fi = computeCommercialCompositionV2("supermarket", 24, true);
    expect(fundingForSettlementMode(fi, "direct_benefits").commercialChargeCents).toBe(879_901);
    expect(fundingForSettlementMode(fi, "cash").commercialChargeCents).toBe(3_117_600);
  });
});

describe("COMERCIAL V2 — venda manual e confirmação de financiamento", () => {
  const sql = lerFonte("supabase/migrations/20260905120000_post_r16_commercial_v2.sql");

  it("existe UMA assinatura de venda manual, com modo de liquidação", () => {
    // A de 10 argumentos é removida: duas assinaturas executáveis deixariam a
    // antiga capaz de criar pedido V2 sem modo de liquidação.
    expect(sql).toContain("DROP FUNCTION IF EXISTS public.admin_register_manual_commercial_order(");
    expect(sql).toContain("p_benefit_settlement_mode text");
  });

  it("a venda manual não aceita nenhum valor monetário do chamador", () => {
    const i = sql.indexOf("CREATE FUNCTION public.admin_register_manual_commercial_order");
    const assinatura = sql.slice(i, sql.indexOf(")\nRETURNS jsonb", i));
    expect(assinatura).not.toMatch(/cents|preco|price|p_pool|p_amount/i);
    expect(assinatura).not.toMatch(/p_fidelized|p_pricing_rule_version|p_payment_method/i);
  });

  it("grava pool_bps NULL sob a V2 em vez de inventar pontos-base", () => {
    expect(sql).toMatch(/CASE WHEN v_versao >= 2 THEN NULL ELSE \(v_pricing->>'pool_bps'\)::int END/);
  });

  it("a confirmação V2 tira o valor esperado do instantâneo, não do chamador", () => {
    expect(sql).toContain("v_esperado := v_ord.total_monetary_funding_required_cents");
    expect(sql).toContain("amount_differs_from_expected");
  });

  it("a confirmação V2 é idempotente e não sobrescreve o já confirmado", () => {
    const i = sql.indexOf("CREATE FUNCTION public.admin_confirm_commercial_funding");
    const corpo = sql.slice(i);
    const j = corpo.indexOf("IF v_ord.payment_status = 'confirmed' THEN");
    expect(j).toBeGreaterThan(-1);
    // O retorno idempotente vem ANTES de qualquer UPDATE.
    expect(j).toBeLessThan(corpo.indexOf("UPDATE public.commercial_exclusivity_orders"));
    expect(corpo).toContain("'already', true");
  });

  it("pedido V1 é recusado pela RPC V2 e a RPC V1 é preservada", () => {
    expect(sql).toContain("v1_order_use_legacy_rpc");
    // A V1 não é alterada nem removida por esta migration.
    expect(sql).not.toMatch(/DROP FUNCTION[^;]*admin_confirm_manual_bdflow_payment/);
  });

  it("confirmar financiamento não afirma repasse a usuários", () => {
    expect(sql).toContain("'user_payout_executed', false");
    for (const proibido of ["escrow", "custodia", "custódia", "segregad"]) {
      expect(sql.toLowerCase(), proibido).not.toContain(proibido.toLowerCase());
    }
  });

  it("as novas funções são SECURITY DEFINER com search_path fixo e sem anon", () => {
    for (const f of [
      "create_commercial_checkout_intent",
      "admin_register_manual_commercial_order",
      "admin_confirm_commercial_funding",
    ]) {
      const i = sql.indexOf(`CREATE FUNCTION public.${f}`);
      expect(i, f).toBeGreaterThan(-1);
      const cabecalho = sql.slice(i, i + 900);
      expect(cabecalho, f).toContain("SECURITY DEFINER");
      expect(cabecalho, f).toContain("SET search_path TO 'pg_catalog'");
      expect(sql, f).toMatch(new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${f}[\\s\\S]{0,200}FROM anon`));
    }
  });

  it("o termo canônico é benefit_settlement_mode, sem nome paralelo", () => {
    expect(sql).not.toContain("benefit_fulfillment_mode");
    expect(sql).not.toMatch(/'direct_benefit'/);
    expect(sql).toContain("benefit_settlement_mode");
    expect(sql).toContain("'direct_benefits'");
  });
});
