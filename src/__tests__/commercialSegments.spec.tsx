import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * POSIÇÕES COMERCIAIS × SEGMENTO (migration 20261103120000, auditoria 14).
 *
 * Do lado do navegador, prova que:
 *   - a vitrine aceita EXATAMENTE seis posições/84 unidades, no conjunto novo
 *     (Calçados + Outros) ou no anterior (transição) — nunca uma mistura;
 *   - Calçados é uma única opção; Supermercado não oferece segmento;
 *   - Outros não avança sem segmento; o segmento escolhido segue até a reserva;
 *   - solicitar segmento não listado não reserva nem aprova nada;
 *   - nenhuma decisão de aprovação, disponibilidade ou exclusividade é tomada
 *     no navegador: tudo vai ao servidor e a tela mostra a resposta.
 * As regras em si são provadas no banco pela suíte SQL 270.
 */

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));
vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/commercialTerritory", () => ({
  obterTerritorio: () => ({ uf: "ES", city: "Vitória" }),
}));
const vinculosMock = vi.fn();
vi.mock("../services/partnerApplicationService", () => ({
  obterVinculosParceiro: () => vinculosMock(),
}));
vi.mock("../services/paymentAvailabilityService", () => ({
  obterDisponibilidadePagamento: async () => ({ tipo: "disponivel" }),
}));
vi.mock("../pages/comercial/EtapasContratacao", () => ({
  default: () => <p>Etapas da contratação</p>,
}));

import { parseFormationResponse } from "../services/commercialResponse";
import {
  NICHES,
  nicheCodeFromSlug,
  positionAcceptsSegment,
  positionRequiresSegment,
} from "../domain/commercial/niches";
import { FORMACAO_REFERENCIA, TOTAL_UNIDADES_REFERENCIA } from "../content/institucional";
import { reservarOportunidade } from "../services/commercialReservationService";
import { joinFutureQueue } from "../services/commercialFutureInterestService";
import {
  adminDecidirSolicitacao,
  solicitarSegmento,
} from "../services/commercialSegmentService";
import OportunidadeDetalhe from "../pages/OportunidadeDetalhe";
import RevisaoContratacao from "../pages/RevisaoContratacao";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const SEG_PET = "22222222-2222-4222-8222-222222222222";
const SEG_PAP = "33333333-3333-4333-8333-333333333333";

const ATUAL: Array<[string, number, number]> = [
  ["supermarket", 24, 1],
  ["pharmacy", 12, 2],
  ["womens_clothing", 12, 3],
  ["mens_clothing", 12, 4],
  ["footwear", 12, 5],
  ["others", 12, 6],
];
const ANTERIOR: Array<[string, number, number]> = [
  ["supermarket", 24, 1],
  ["pharmacy", 12, 2],
  ["womens_clothing", 12, 3],
  ["mens_clothing", 12, 4],
  ["womens_footwear", 12, 5],
  ["mens_footwear", 12, 6],
];
const ELEGIVEIS = new Set(["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]);

function formacao(
  posicoes: Array<[string, number, number]> = ATUAL,
  extra: (code: string) => Record<string, unknown> = (code) =>
    posicoes === ANTERIOR
      ? {}
      : { accepts_segment: ELEGIVEIS.has(code), requires_segment: code === "others", segment: null }
) {
  return {
    region_available: true,
    exclusivity_available: true,
    region: {
      region_id: "r1", region_name: "Grande Vitória", region_slug: "grande-vitoria",
      uf: "ES", is_active: true, city_name: "Vitória",
    },
    exclusivity: {
      id: "e1", region_id: "r1", sequence_number: 1, status: "forming",
      is_current: true, planned_start_at: null,
    },
    summary: {
      total_opportunities: 6, contracted_opportunities: 0, total_units: 84,
      contracted_units: 0, formation_percent: 0, is_complete: false,
    },
    opportunities: posicoes.map(([code, qty, sort]) => ({
      id: "o-" + code, exclusivity_id: "e1", niche_code: code,
      display_name: code, contracted_quantity: qty, status: "available",
      sort_order: sort, ...extra(code),
    })),
  };
}

function blocoPreco(niche: string, qtd: number, fidelized: boolean) {
  return {
    ok: true, pricing_rule_version: 3, pool_precision_model: "explicit_schedule",
    niche_code: niche, niche_category: niche === "supermarket" ? "supermarket" : "common",
    nominal_quantity: qtd, fidelized, currency: "BRL", pool_bps: null,
    display_pool_percent: null, display_bdflow_percent: null,
    payment_method: fidelized ? "credit_card" : "pix",
    contract_economics_version: "SF-v1.4",
    economic_value_cents: 1_999_900, contractual_pool_cents: 1_198_800,
    bdflow_due_cents: 801_100, mei_consideration_cents: 1_192_716,
    smallflags_qa_cents: 6_084, smallflags_main_fee_cents: 801_100,
    smallflags_total_remuneration_cents: 807_184,
    ordinary_participation_value_cents: 14_199,
    direct_benefit_deliverable_cents: 1_192_716,
    funding_direct_benefits_cents: 807_184, funding_cash_cents: 1_999_900,
  };
}
const PRECOS = {
  ok: true, pricing_rule_version: 3, currency: "BRL",
  niches: ATUAL.map(([code, qty]) => ({
    niche_code: code, display_name: code === "others" ? "Outros" : code,
    nominal_quantity: qty, founding: blocoPreco(code, qty, false),
    fidelized: blocoPreco(code, qty, true),
  })),
};
const SEGMENTOS = {
  ok: true,
  segments: [
    { id: SEG_PET, code: "pet_shop", name: "Pet shop", description: null, overlaps_niche_code: null },
    { id: SEG_PAP, code: "papelaria", name: "Papelaria", description: null, overlaps_niche_code: null },
  ],
};

let respostaFormacao: unknown = formacao();
beforeEach(() => {
  respostaFormacao = formacao();
  rpcMock.mockReset();
  rpcMock.mockImplementation(async (nome: string) => {
    switch (nome) {
      case "get_current_commercial_formation":
        return { data: respostaFormacao, error: null };
      case "get_public_niche_pricing":
        return { data: PRECOS, error: null };
      case "list_commercial_segments":
        return { data: SEGMENTOS, error: null };
      case "get_my_commercial_future_interest":
        return { data: { ok: true, mode: "none" }, error: null };
      case "request_commercial_segment":
        return { data: { ok: true, already: false, request_id: "req-1", status: "pending" }, error: null };
      case "create_commercial_checkout_intent":
        return {
          data: {
            ok: true, already: false, intent_id: "i1", opportunity_id: "o-others",
            reserved_until: "2026-11-03T15:30:00Z", reservation_minutes: 30,
            niche_code: "others", segment_code: "pet_shop", segment_name: "Pet shop",
            nominal_quantity: 12, fidelized: false, payment_method: "pix",
            benefit_settlement_mode: "direct_benefits", economic_value_cents: 1_999_900,
            user_pool_cents: 1_198_800, bdflow_ops_investment_cents: 801_100,
            cash_user_pool_funding_cents: 0, total_monetary_funding_required_cents: 807_184,
          },
          error: null,
        };
      default:
        return { data: { ok: false, reason: "unexpected" }, error: null };
    }
  });
  vinculosMock.mockResolvedValue({
    tipo: "ok",
    vinculos: [{ company_id: COMPANY, role: "partner_owner", member_status: "active" }],
  });
});
afterEach(() => cleanup());

const chamadas = (nome: string) => rpcMock.mock.calls.filter((c) => c[0] === nome);

// ---------------------------------------------------------------------------
describe("estrutura comercial: seis posições, 84 unidades", () => {
  it("Calçados é UMA opção e Outros é a sexta posição", () => {
    const codigos = NICHES.map((n) => n.code);
    expect(codigos).toEqual(["supermarket", "pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]);
    expect(codigos.filter((c) => c.includes("footwear"))).toEqual(["footwear"]);
    expect(NICHES.find((n) => n.code === "footwear")!.displayName).toBe("Calçados");
  });

  it("referência institucional soma 84 com Calçados e Outros", () => {
    expect(FORMACAO_REFERENCIA.map((f) => f.nome)).toEqual([
      "Supermercado", "Farmácia", "Roupas femininas", "Roupas masculinas", "Calçados", "Outros",
    ]);
    expect(TOTAL_UNIDADES_REFERENCIA).toBe(84);
  });

  it("Supermercado nunca aceita segmento; as quatro elegíveis e Outros aceitam", () => {
    expect(positionAcceptsSegment("supermarket")).toBe(false);
    for (const c of ["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"] as const) {
      expect(positionAcceptsSegment(c)).toBe(true);
    }
    expect(positionRequiresSegment("others")).toBe(true);
    expect(positionRequiresSegment("footwear")).toBe(false);
  });

  it("links antigos de calçados F/M continuam resolvendo", () => {
    expect(nicheCodeFromSlug("womens-footwear")).toBe("womens_footwear");
    expect(nicheCodeFromSlug("footwear")).toBe("footwear");
    expect(nicheCodeFromSlug("others")).toBe("others");
  });
});

// ---------------------------------------------------------------------------
describe("parser da formação: conjunto atual OU anterior, nunca mistura", () => {
  it("aceita o conjunto novo com as chaves de segmento", () => {
    const f = parseFormationResponse(formacao());
    expect(f.opportunities).toHaveLength(6);
    expect(f.opportunities.reduce((a, o) => a + o.contractedQuantity, 0)).toBe(84);
    const outros = f.opportunities.find((o) => o.nicheCode === "others")!;
    expect(outros.requiresSegment).toBe(true);
    expect(f.opportunities.find((o) => o.nicheCode === "supermarket")!.acceptsSegment).toBe(false);
  });

  it("aceita o conjunto anterior (backend ainda sem a migration)", () => {
    const f = parseFormationResponse(formacao(ANTERIOR));
    expect(f.opportunities.map((o) => o.nicheCode)).toContain("mens_footwear");
    expect(f.opportunities.every((o) => !o.acceptsSegment)).toBe(true);
  });

  it("recusa mistura dos dois conjuntos", () => {
    const mistura = formacao([...ATUAL.slice(0, 5), ["mens_footwear", 12, 6]]);
    expect(() => parseFormationResponse(mistura)).toThrow();
  });

  it("recusa posição de 12 com quantidade diferente e supermercado com segmento", () => {
    const errada = formacao(ATUAL.map(([c, q, s]) => [c, c === "others" ? 13 : q, s] as [string, number, number]));
    expect(() => parseFormationResponse(errada)).toThrow();
    const superSeg = formacao(ATUAL, (code) => ({
      accepts_segment: code === "supermarket" || ELEGIVEIS.has(code),
      requires_segment: code === "others",
    }));
    expect(() => parseFormationResponse(superSeg)).toThrow();
  });

  it("recusa sete posições", () => {
    const sete = formacao([...ATUAL, ["womens_footwear", 12, 7]]);
    expect(() => parseFormationResponse(sete)).toThrow();
  });
});

// ---------------------------------------------------------------------------
describe("serviços: o navegador só envia a escolha", () => {
  it("reserva sem segmento mantém a chamada de três argumentos", async () => {
    await reservarOportunidade({ companyId: COMPANY, nicheCode: "pharmacy", benefitSettlementMode: "direct_benefits" });
    expect(chamadas("create_commercial_checkout_intent")[0][1]).toEqual({
      p_company_id: COMPANY, p_niche_code: "pharmacy", p_benefit_settlement_mode: "direct_benefits",
    });
  });

  it("reserva com segmento envia só o identificador; o resto vem do servidor", async () => {
    const r = await reservarOportunidade({
      companyId: COMPANY, nicheCode: "others", benefitSettlementMode: "direct_benefits", segmentId: SEG_PET,
    });
    expect(chamadas("create_commercial_checkout_intent")[0][1]).toEqual({
      p_company_id: COMPANY, p_niche_code: "others",
      p_benefit_settlement_mode: "direct_benefits", p_segment_id: SEG_PET,
    });
    expect(r.tipo === "ok" && r.reserva.segmentName).toBe("Pet shop");
  });

  it("fila futura preserva o segmento escolhido", async () => {
    rpcMock.mockResolvedValueOnce({ data: { ok: true, mode: "preorder", status: "waiting", target_sequence_number: 2, segment_name: "Papelaria" }, error: null });
    const r = await joinFutureQueue({ companyId: COMPANY, nicheCode: "pharmacy", segmentId: SEG_PAP });
    expect(rpcMock.mock.calls[0][1]).toEqual({ p_company_id: COMPANY, p_niche_code: "pharmacy", p_segment_id: SEG_PAP });
    expect(r.tipo === "preorder" && r.segmentName).toBe("Papelaria");
  });

  it("solicitar segmento chama SOMENTE a RPC de solicitação", async () => {
    const r = await solicitarSegmento({ companyId: COMPANY, label: "Ótica", intendedNicheCode: "others" });
    expect(r.tipo).toBe("ok");
    expect(rpcMock.mock.calls.map((c) => c[0])).toEqual(["request_commercial_segment"]);
  });

  it("aprovação é pedida ao servidor; o navegador não decide", async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { message: "not_authorized" } });
    const r = await adminDecidirSolicitacao("req-1", {
      decisao: "approve", novo: { code: "otica", displayName: "Ótica", classificationKey: "otica" },
    });
    expect(rpcMock.mock.calls[0][0]).toBe("admin_decide_commercial_segment_request");
    expect(r).toEqual({ tipo: "erro", codigo: "not_authorized" });
  });
});

// ---------------------------------------------------------------------------
const detalhe = (slug: string) =>
  render(
    <MemoryRouter initialEntries={[`/oportunidades/${slug}`]}>
      <Routes>
        <Route path="/oportunidades/:nicheSlug" element={<OportunidadeDetalhe />} />
      </Routes>
    </MemoryRouter>
  );

describe("detalhe da oportunidade", () => {
  it("Supermercado não oferece segmento", async () => {
    detalhe("supermarket");
    await screen.findByRole("heading", { name: "Supermercado" });
    await screen.findByText("Solicitar contratação");
    expect(screen.queryByTestId("seletor-segmento")).toBeNull();
    expect(chamadas("list_commercial_segments")).toHaveLength(0);
  });

  it("Outros não avança sem segmento e leva o segmento ao checkout", async () => {
    detalhe("others");
    expect(await screen.findByRole("button", { name: "Escolha o segmento para continuar" })).toHaveProperty("disabled", true);
    fireEvent.click(await screen.findByRole("radio", { name: /Pet shop/ }));
    const link = await screen.findByRole("link", { name: "Solicitar contratação" });
    expect(link.getAttribute("href")).toBe(`/checkout?nicho=others&segmento=${SEG_PET}`);
    expect(screen.getByTestId("resumo-segmento").textContent).toMatch(/Outros.*Pet shop.*12 unidades/);
  });

  it("posição elegível pode ser contratada como ela mesma ou como Outros", async () => {
    detalhe("pharmacy");
    const link = await screen.findByRole("link", { name: "Solicitar contratação" });
    expect(link.getAttribute("href")).toBe("/checkout?nicho=pharmacy");
    fireEvent.click(screen.getByRole("radio", { name: /como Outros/ }));
    fireEvent.click(await screen.findByRole("radio", { name: /Papelaria/ }));
    expect(screen.getByRole("link", { name: "Solicitar contratação" }).getAttribute("href"))
      .toBe(`/checkout?nicho=pharmacy&segmento=${SEG_PAP}`);
  });

  it("segmento que já ocupa outra posição aparece indisponível", async () => {
    respostaFormacao = formacao(ATUAL, (code) => ({
      accepts_segment: ELEGIVEIS.has(code), requires_segment: code === "others",
      segment: code === "pharmacy" ? { code: "pet_shop", name: "Pet shop" } : null,
    }));
    detalhe("others");
    const pet = await screen.findByRole("radio", { name: /Pet shop/ });
    expect((pet as HTMLInputElement).disabled).toBe(true);
    expect((screen.getByRole("radio", { name: /Papelaria/ }) as HTMLInputElement).disabled).toBe(false);
  });

  it("reserva de outra empresa sem segmento público: vitrine não quebra e avisa que o servidor confirma", async () => {
    // A formação pública não divulga o segmento de reserva não paga
    // (segment: null mesmo com a posição reservada).
    respostaFormacao = formacao(ATUAL, (code) => ({
      accepts_segment: ELEGIVEIS.has(code), requires_segment: code === "others",
      segment: null,
      ...(code === "pharmacy" ? { status: "reserved" } : {}),
    }));
    detalhe("others");
    const pet = await screen.findByRole("radio", { name: /Pet shop/ });
    expect((pet as HTMLInputElement).disabled).toBe(false);
    expect(screen.getByTestId("aviso-disponibilidade-segmento").textContent)
      .toMatch(/confirmada no momento da reserva/);
    expect(chamadas("create_commercial_checkout_intent")).toHaveLength(0);
  });

  it("solicitação de segmento não listado não reserva nada", async () => {
    detalhe("others");
    fireEvent.click(await screen.findByRole("button", { name: "Meu segmento não está na lista" }));
    fireEvent.change(screen.getByLabelText(/Qual é o segmento/), { target: { value: "Ótica" } });
    fireEvent.click(screen.getByRole("button", { name: "Enviar para análise" }));
    expect(await screen.findByText("Solicitação enviada para análise da SmallFlags.")).toBeDefined();
    expect(chamadas("request_commercial_segment")[0][1]).toMatchObject({
      p_company_id: COMPANY, p_label: "Ótica", p_intended_niche_code: "others",
    });
    expect(chamadas("create_commercial_checkout_intent")).toHaveLength(0);
  });

  it("quem não é responsável não solicita segmento", async () => {
    vinculosMock.mockResolvedValue({
      tipo: "ok", vinculos: [{ company_id: COMPANY, role: "partner_manager", member_status: "active" }],
    });
    detalhe("others");
    fireEvent.click(await screen.findByRole("button", { name: "Meu segmento não está na lista" }));
    expect(await screen.findByText(/Entre como responsável da empresa para solicitar/)).toBeDefined();
    expect(screen.queryByRole("button", { name: "Enviar para análise" })).toBeNull();
  });

  it("link antigo de calçados leva a Calçados quando o servidor já unificou", async () => {
    render(
      <MemoryRouter initialEntries={["/oportunidades/mens-footwear"]}>
        <Routes>
          <Route path="/oportunidades/:nicheSlug" element={<OportunidadeDetalhe />} />
        </Routes>
      </MemoryRouter>
    );
    expect(await screen.findByRole("heading", { name: "Calçados" })).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
const checkout = (rota: string) =>
  render(
    <MemoryRouter initialEntries={[rota]}>
      <Routes>
        <Route path="/checkout" element={<RevisaoContratacao />} />
      </Routes>
    </MemoryRouter>
  );

describe("checkout com segmento", () => {
  it("Outros sem segmento não pode ser reservado", async () => {
    checkout("/checkout?nicho=others");
    expect(await screen.findByText("Escolha o segmento da sua empresa para a posição Outros.")).toBeDefined();
    expect(screen.queryByRole("button", { name: "Reservar por 30 minutos" })).toBeNull();
  });

  it("Supermercado com segmento na URL é bloqueado antes do servidor", async () => {
    checkout(`/checkout?nicho=supermarket&segmento=${SEG_PET}`);
    expect(await screen.findByText("A posição Supermercado não pode ser substituída.")).toBeDefined();
    expect(chamadas("create_commercial_checkout_intent")).toHaveLength(0);
  });

  it("exibe o segmento antes de confirmar e o envia na reserva", async () => {
    checkout(`/checkout?nicho=others&segmento=${SEG_PET}`);
    expect((await screen.findByTestId("segmento-escolhido")).textContent).toMatch(/Pet shop.*12 unidades/);
    fireEvent.click(await screen.findByRole("button", { name: "Reservar por 30 minutos" }));
    await waitFor(() => expect(chamadas("create_commercial_checkout_intent")).toHaveLength(1));
    expect(chamadas("create_commercial_checkout_intent")[0][1]).toMatchObject({ p_segment_id: SEG_PET });
    expect((await screen.findByTestId("segmento-reservado")).textContent).toContain("Pet shop");
  });

  it("recusa do servidor vira mensagem fixa, sem texto do banco", async () => {
    rpcMock.mockImplementation(async (nome: string) =>
      nome === "create_commercial_checkout_intent"
        ? { data: { ok: false, reason: "segment_already_in_exclusivity" }, error: null }
        : nome === "get_public_niche_pricing"
          ? { data: PRECOS, error: null }
          : { data: SEGMENTOS, error: null }
    );
    checkout(`/checkout?nicho=pharmacy&segmento=${SEG_PAP}`);
    fireEvent.click(await screen.findByRole("button", { name: "Reservar por 30 minutos" }));
    expect(await screen.findByText(
      "Esse segmento já está contratado ou reservado em outra posição desta exclusividade. Escolha outro segmento ou aguarde."
    )).toBeDefined();
    // a recusa não vira reserva: nada de resumo de reserva nem passo de contrato
    expect(screen.queryByTestId("segmento-reservado")).toBeNull();
  });
});
