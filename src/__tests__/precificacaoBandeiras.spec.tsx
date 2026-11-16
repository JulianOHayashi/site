import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, fireEvent } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * SF-v1.5 — produção de bandeiras e reutilização por fidelização, na TELA.
 *
 * As respostas do servidor usadas aqui foram geradas do banco local com a
 * migration 20261112120000 (versão 4 ativada só dentro de uma transação
 * revertida): o navegador é testado contra o formato real da autoridade.
 *
 * O navegador não calcula fabricação, preço nem quantidade de bandeiras:
 * exibe o que o servidor declara e falha fechado se a declaração for
 * incoerente.
 */

const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");
const semComentarios = (src: string) =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
const fixture = (nome: string) =>
  JSON.parse(lerFonte(`src/__tests__/fixtures/${nome}`)) as Record<string, unknown>;

// R3: a versão 4 publica a composição por modalidade. A resposta vem do banco
// LOCAL com a migration R3 e o preço do DINHEIRO no Cenário B FICTÍCIO (o
// econômico publicado mantido), só para exercitar a vitrine; não é decisão.
// A antiga resposta sem política de QA (preco-publico-sf-v15-20261112.json)
// é recusada pelo parser R3 — provado em "declarações incoerentes".
const SF_V15 = fixture("preco-publico-sf-v15-r3-cenarioB-20261113.json");
const SF_V15_A = fixture("preco-publico-sf-v15-r3-cenarioA-20261113.json");
const SF_V15_PRE_R3 = fixture("preco-publico-sf-v15-20261112.json");
const SF_V14 = fixture("preco-publico-sf-v14-20261112.json");

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));
vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/commercialTerritory", () => ({
  obterTerritorio: () => ({ uf: "ES", cidade: "Vitória" }),
}));

import {
  interpretarPrecoPublico,
  formatarCentavos,
} from "../domain/pricing/contractPricing";
import PainelPreco from "../components/commercial/PainelPreco";
import ReferenciaOperacional from "../components/commercial/ReferenciaOperacional";
import { reservarOportunidade } from "../services/commercialReservationService";
import { mensagemFalhaReserva } from "../domain/commercial/reservaMensagens";
import RevisaoContratacao from "../pages/RevisaoContratacao";

type Nicho = { niche_code: string; founding: Record<string, unknown>; fidelized: Record<string, unknown> };
const nichos = (r: Record<string, unknown>) => r.niches as Nicho[];
const comBloco = (
  base: Record<string, unknown>,
  codigo: string,
  qual: "founding" | "fidelized",
  muda: Record<string, unknown>,
) => ({
  ...base,
  niches: nichos(base).map((n) =>
    n.niche_code === codigo ? { ...n, [qual]: { ...n[qual], ...muda } } : n,
  ),
});

beforeEach(() => rpcMock.mockReset());
afterEach(() => cleanup());

describe("SF-v1.5 — preço público com produção de bandeiras", () => {
  const lista = interpretarPrecoPublico(SF_V15)!;
  const por = (c: string) => lista.find((p) => p.nicheCode === c)!;

  it("resposta real do servidor é aceita para as seis posições", () => {
    expect(lista).not.toBeNull();
    expect(lista.map((p) => p.nicheCode).sort()).toEqual(
      ["footwear", "mens_clothing", "others", "pharmacy", "supermarket", "womens_clothing"],
    );
  });

  it("não fidelizado: supermercado R$ 32.939,00 e comum R$ 22.939,00", () => {
    expect(por("supermarket").founding.economicValueCents).toBe(3_293_900);
    for (const c of ["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]) {
      expect(por(c).founding.economicValueCents).toBe(2_293_900);
    }
  });

  it("fidelizado com reutilização: supermercado R$ 28.176,00 e comum R$ 16.188,00", () => {
    expect(por("supermarket").fidelized.economicValueCents).toBe(2_817_600);
    for (const c of ["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]) {
      expect(por(c).fidelized.economicValueCents).toBe(1_618_800);
    }
  });

  it("primeira contratação exige 84 bandeiras: R$ 35,00 × 84 = R$ 2.940,00", () => {
    for (const p of lista) {
      expect(p.founding.flagProduction).toEqual({
        newFlagUnits: 84,
        flagUnitReferenceCents: 3_500,
        flagProductionChargeCents: 294_000,
        reuseRequired: false,
      });
    }
  });

  it("84 bandeiras não é a quantidade comercial (24 ou 12)", () => {
    expect(por("supermarket").nominalQuantity).toBe(24);
    expect(por("supermarket").founding.flagProduction!.newFlagUnits).toBe(84);
    expect(por("pharmacy").nominalQuantity).toBe(12);
    expect(por("pharmacy").founding.flagProduction!.newFlagUnits).toBe(84);
  });

  it("seis anunciantes novos: 504 bandeiras e R$ 17.640,00; formação R$ 147.634,00", () => {
    const pecas = lista.reduce((s, p) => s + p.founding.flagProduction!.newFlagUnits, 0);
    const fabricacao = lista.reduce((s, p) => s + p.founding.flagProduction!.flagProductionChargeCents, 0);
    const total = lista.reduce((s, p) => s + p.founding.economicValueCents, 0);
    expect(pecas).toBe(504);
    expect(fabricacao).toBe(1_764_000);
    expect(total).toBe(14_763_400);
  });

  it("seis fidelizados com reutilização: zero bandeiras e R$ 109.116,00", () => {
    const pecas = lista.reduce((s, p) => s + p.fidelized.flagProduction!.newFlagUnits, 0);
    const total = lista.reduce((s, p) => s + p.fidelized.economicValueCents, 0);
    expect(pecas).toBe(0);
    expect(total).toBe(10_911_600);
    for (const p of lista) {
      expect(p.fidelized.flagProduction!.reuseRequired).toBe(true);
      expect(p.fidelized.flagProduction!.flagProductionChargeCents).toBe(0);
    }
  });

  it("adicional está DENTRO da parcela principal, uma única vez", () => {
    const s = por("supermarket").founding;
    expect(s.economicValueCents).toBe(
      s.meiConsiderationCents! + s.smallflagsQaCents! + s.smallflagsMainFeeCents!,
    );
    expect(s.smallflagsMainFeeCents! - s.flagProduction!.flagProductionChargeCents).toBe(602_300);
    // R3: no benefício direto, o dinheiro é só a parcela principal; a QA é
    // cumprida em produtos e nunca entra na cobrança.
    expect(s.fundingDirectBenefitsCents).toBe(896_300);
    expect(s.smallflagsTotalRemunerationCents).toBe(896_300);
    expect(s.settlementModes!.directBenefits.qaInKindCents).toBe(12_168);
    expect(s.settlementModes!.directBenefits.qaCashCents).toBe(0);
  });

  it("MEI, QA e R$ 141,99 por participação preservados (588 × 14.199 = 8.349.012)", () => {
    const mei = lista.reduce((s, p) => s + p.founding.meiConsiderationCents!, 0);
    const qa = lista.reduce((s, p) => s + p.founding.smallflagsQaCents!, 0);
    expect(mei).toBe(588 * 14_199);
    expect(mei).toBe(8_349_012);
    expect(qa).toBe(42_588);
    expect(lista.reduce((s, p) => s + p.fidelized.meiConsiderationCents!, 0)).toBe(8_349_012);
  });

  it("SF-v1.4 vigente não traz fatos de bandeira e nada é presumido", () => {
    const v14 = interpretarPrecoPublico(SF_V14)!;
    expect(v14).not.toBeNull();
    for (const p of v14) {
      expect(p.founding.flagProduction).toBeNull();
      expect(p.fidelized.flagProduction).toBeNull();
    }
    expect(v14.find((p) => p.nicheCode === "supermarket")!.founding.economicValueCents).toBe(2_999_900);
  });
});

describe("SF-v1.5 — declarações incoerentes falham fechado", () => {
  it.each([
    ["fabricação diferente de peças × unitário", "founding", { flag_production_charge_cents: 293_999 }],
    ["fidelizado com peças novas", "fidelized", { new_flag_units: 84, flag_production_charge_cents: 294_000 }],
    ["não fidelizado marcado como reutilização", "founding", { flag_reuse_required: true }],
    ["não fidelizado sem peças", "founding", { new_flag_units: 0, flag_production_charge_cents: 0 }],
    ["fabricação maior que a parcela principal", "founding", { new_flag_units: 400, flag_production_charge_cents: 1_400_000 }],
    ["declaração parcial (sem unitário)", "founding", { flag_unit_reference_cents: undefined }],
    ["reutilização sem booleano", "fidelized", { flag_reuse_required: "sim" }],
  ] as const)("%s", (_nome, qual, muda) => {
    expect(interpretarPrecoPublico(comBloco(SF_V15, "pharmacy", qual, muda))).toBeNull();
  });

  it("R3: resposta v4 sem política de QA por modalidade (pré-R3) é recusada", () => {
    expect(interpretarPrecoPublico(SF_V15_PRE_R3)).toBeNull();
  });
});

describe("SF-v1.5 — vitrine", () => {
  // Merge com a apresentação comercial R2 (aprovada): a vitrine menciona a
  // produção e a reutilização das bandeiras, mas não usa o custo de
  // fabricação como argumento de venda. Os valores continuam na revisão.
  it("menciona a produção das bandeiras na composição, sem expor o custo de fabricação", async () => {
    rpcMock.mockResolvedValue({ data: SF_V15, error: null });
    render(<MemoryRouter><PainelPreco nicheCode="supermarket" /></MemoryRouter>);
    const comp = await screen.findByTestId("composicao-tecnica");
    // Texto do patch P0 do proprietário (16/11/2026).
    expect(comp.textContent).toMatch(/inclui a produção inicial das bandeiras\s+da marca/);
    expect(document.body.textContent).not.toContain(formatarCentavos(294_000));
    expect(screen.queryByTestId("fabricacao-bandeiras")).toBeNull();
    expect(screen.getAllByText(formatarCentavos(3_293_900)).length).toBeGreaterThan(0);
  });

  it("explica a reutilização na renovação, sem prometer reposição gratuita", async () => {
    rpcMock.mockResolvedValue({ data: SF_V15, error: null });
    render(<MemoryRouter><PainelPreco nicheCode="pharmacy" /></MemoryRouter>);
    const comp = await screen.findByTestId("composicao-tecnica");
    // Texto do patch P0 do proprietário (16/11/2026).
    expect(comp.textContent).toMatch(/a reutilização depende de inspeção/);
    expect(comp.textContent).toMatch(/mudar a frase ou a arte não elimina a fidelidade/);
    expect(comp.textContent).toMatch(/reposição por dano continua\s+sujeita à política específica, ainda não liberada/);
    expect(document.body.textContent).not.toMatch(/gratuit/i);
  });

  it("sob a SF-v1.4 vigente o painel mostra só a prévia e nenhum valor de bandeira", async () => {
    rpcMock.mockResolvedValue({ data: SF_V14, error: null });
    render(<MemoryRouter><PainelPreco nicheCode="supermarket" /></MemoryRouter>);
    await screen.findByTestId("aviso-previa");
    expect(document.body.textContent).not.toContain(formatarCentavos(2_999_900));
    expect(document.body.textContent).not.toContain(formatarCentavos(294_000));
  });

  it("o navegador não reconstrói fabricação nem quantidade de bandeiras", () => {
    for (const arq of [
      "src/components/commercial/PainelPreco.tsx",
      "src/pages/RevisaoContratacao.tsx",
      "src/services/commercialReservationService.ts",
    ]) {
      const fonte = semComentarios(lerFonte(arq));
      expect(fonte).not.toMatch(/3[_]?500/);
      expect(fonte).not.toMatch(/294[_.]?000/);
      expect(fonte).not.toMatch(/\b84\s*\*/);
      expect(fonte).not.toMatch(/\*\s*84\b/);
    }
  });
});

describe("SF-v1.5 — revisão da contratação (/checkout)", () => {
  const montarCheckout = (rota: string) =>
    render(
      <MemoryRouter initialEntries={[rota]}>
        <Routes>
          <Route path="/checkout" element={<RevisaoContratacao />} />
        </Routes>
      </MemoryRouter>,
    );

  it("mostra R$ 32.939,00 e a fabricação de 84 bandeiras dentro da parcela principal", async () => {
    rpcMock.mockResolvedValue({ data: SF_V15, error: null });
    montarCheckout("/checkout?nicho=supermarket");
    await waitFor(() => expect(screen.getAllByText("R$ 32.939,00").length).toBeGreaterThan(0));
    const linha = screen.getByText("dos quais, fabricação de 84 bandeiras (R$ 35,00 cada)");
    expect(linha.parentElement!.textContent).toContain("R$ 2.940,00");
    expect(screen.getAllByText("R$ 8.963,00").length).toBeGreaterThan(0);
    expect(screen.getAllByText("R$ 23.854,32").length).toBeGreaterThan(0);
    expect(screen.getAllByText("R$ 121,68").length).toBeGreaterThan(0);
  });

  it("R3: cobrança direta R$ 8.963,00 (sem QA) e em dinheiro R$ 32.939,00 (cenário B de teste), fabricação uma vez", async () => {
    rpcMock.mockResolvedValue({ data: SF_V15, error: null });
    montarCheckout("/checkout?nicho=supermarket");
    await screen.findByText("Contraprestação cumprida em benefício direto");
    const cobranca = () => screen.getByText("Valor financeiro da cobrança").parentElement as HTMLElement;
    expect(cobranca().textContent).toContain("R$ 8.963,00");
    expect(cobranca().textContent).not.toContain("R$ 9.084,68");
    fireEvent.click(screen.getByRole("radio", { name: /Dinheiro real/ }));
    expect(cobranca().textContent).toContain("R$ 32.939,00");
    expect(cobranca().textContent).not.toContain("R$ 35.879,00");
  });

  it("R3: no cenário A de teste o dinheiro cobra o valor da modalidade, sem QA (R$ 32.817,32)", async () => {
    rpcMock.mockResolvedValue({ data: SF_V15_A, error: null });
    montarCheckout("/checkout?nicho=supermarket");
    await screen.findByText("Contraprestação cumprida em benefício direto");
    const cobranca = () => screen.getByText("Valor financeiro da cobrança").parentElement as HTMLElement;
    expect(cobranca().textContent).toContain("R$ 8.963,00");
    fireEvent.click(screen.getByRole("radio", { name: /Dinheiro real/ }));
    expect(cobranca().textContent).toContain("R$ 32.817,32");
    expect(screen.getByText("Valor total nesta forma").parentElement!.textContent).toContain("R$ 32.817,32");
    expect(screen.getByText(/Nesta forma não há QA nem testes com produtos/)).toBeDefined();
  });

  it("sob a SF-v1.4 vigente a revisão não mostra bandeiras", async () => {
    rpcMock.mockResolvedValue({ data: SF_V14, error: null });
    montarCheckout("/checkout?nicho=supermarket");
    await waitFor(() => expect(screen.getAllByText("R$ 29.999,00").length).toBeGreaterThan(0));
    expect(screen.queryByText(/bandeiras/)).toBeNull();
  });
});

describe("SF-v1.5 — reserva", () => {
  const base = {
    ok: true, already: false, intent_id: "i-1", status: "draft", opportunity_id: "o-1",
    reserved_until: "2026-11-12T15:30:00Z", reservation_minutes: 30, niche_code: "supermarket",
    segment_code: null, segment_name: null, nominal_quantity: 24, payment_method: "pix",
    benefit_settlement_mode: "direct_benefits", currency: "BRL", user_pool_cents: 2_397_600,
    bdflow_ops_investment_cents: 896_300, cash_user_pool_funding_cents: 0,
  };

  it("reserva não fidelizada traz 84 peças e a fabricação já incluída no total", async () => {
    rpcMock.mockResolvedValue({
      data: { ...base, fidelized: false, economic_value_cents: 3_293_900,
        total_monetary_funding_required_cents: 908_468, new_flag_units: 84,
        flag_unit_reference_cents: 3_500, flag_production_charge_cents: 294_000, flag_reuse: false },
      error: null,
    });
    const r = await reservarOportunidade({ companyId: "c", nicheCode: "supermarket", benefitSettlementMode: "direct_benefits" });
    expect(r.tipo).toBe("ok");
    if (r.tipo !== "ok") return;
    expect(r.reserva.flagProduction).toEqual({
      newFlagUnits: 84, flagUnitReferenceCents: 3_500, flagProductionChargeCents: 294_000, reuse: false,
    });
    // O valor cobrado é o do servidor; nada é somado no navegador.
    expect(r.reserva.totalMonetaryFundingRequiredCents).toBe(908_468);
  });

  it("reserva fidelizada com reutilização: zero peças, zero fabricação", async () => {
    rpcMock.mockResolvedValue({
      data: { ...base, fidelized: true, payment_method: "credit_card", economic_value_cents: 2_817_600,
        total_monetary_funding_required_cents: 432_168, new_flag_units: 0,
        flag_unit_reference_cents: 3_500, flag_production_charge_cents: 0, flag_reuse: true },
      error: null,
    });
    const r = await reservarOportunidade({ companyId: "c", nicheCode: "supermarket", benefitSettlementMode: "direct_benefits" });
    expect(r.tipo === "ok" && r.reserva.flagProduction).toEqual({
      newFlagUnits: 0, flagUnitReferenceCents: 3_500, flagProductionChargeCents: 0, reuse: true,
    });
  });

  it("reserva sob SF-v1.4 não tem fatos de produção", async () => {
    rpcMock.mockResolvedValue({
      data: { ...base, fidelized: false, economic_value_cents: 2_999_900,
        total_monetary_funding_required_cents: 614_468, new_flag_units: null,
        flag_unit_reference_cents: null, flag_production_charge_cents: null, flag_reuse: false },
      error: null,
    });
    const r = await reservarOportunidade({ companyId: "c", nicheCode: "supermarket", benefitSettlementMode: "direct_benefits" });
    expect(r.tipo === "ok" && r.reserva.flagProduction).toBeNull();
  });

  it.each(["flag_reuse_not_verified", "flag_replacement_policy_pending"])(
    "recusa %s chega como motivo, sem preço",
    async (motivo) => {
      rpcMock.mockResolvedValue({ data: { ok: false, reason: motivo, detail: "x" }, error: null });
      const r = await reservarOportunidade({ companyId: "c", nicheCode: "supermarket", benefitSettlementMode: "direct_benefits" });
      expect(r).toEqual({ tipo: "erro", codigo: motivo, reservedUntil: undefined });
    },
  );

  it("mensagens não prometem reposição gratuita nem anunciam cobrança", () => {
    const naoVerificado = mensagemFalhaReserva("flag_reuse_not_verified")!;
    const reposicao = mensagemFalhaReserva("flag_replacement_policy_pending")!;
    expect(naoVerificado).toContain("inspeção de conservação");
    expect(reposicao).toContain("política de reposição ainda está em definição");
    for (const m of [naoVerificado, reposicao]) {
      expect(m).toContain("Nada foi reservado nem cobrado");
      expect(m).not.toMatch(/gratuit|R\$/i);
    }
    expect(mensagemFalhaReserva("motivo_desconhecido")).toBeNull();
  });
});

describe("Referência operacional — sete participações potenciais", () => {
  it("reconcilia o texto legado: sete participações, duas no supermercado", () => {
    render(<ReferenciaOperacional />);
    expect(
      screen.getByText(
        "Sete participações potenciais por usuário: duas no supermercado e uma em cada uma das outras cinco posições",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(/Seis benefícios/)).toBeNull();
  });

  it("84 usuários e as capacidades comerciais continuam inalterados", () => {
    render(<ReferenciaOperacional />);
    expect(screen.getByText("84 usuários-produto na operação de referência")).toBeTruthy();
    expect(screen.getByText("Supermercado: capacidade de 24")).toBeTruthy();
    expect(screen.getByText("Demais nichos: capacidade de 12 cada")).toBeTruthy();
  });
});
