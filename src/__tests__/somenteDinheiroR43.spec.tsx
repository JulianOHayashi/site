import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";


/**
 * R4.3 — habilitação SOMENTE DINHEIRO (Cenário A), na tela.
 * A resposta pública foi gerada do banco local com a migration
 * 20261116210000 (versão 4 ativada só dentro de transação revertida, com
 * fixtures [QA FICTICIO]): o navegador é testado contra o formato real.
 */
const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");
const fixture = (nome: string) =>
  JSON.parse(lerFonte(`src/__tests__/fixtures/${nome}`)) as Record<string, unknown>;
const SO_DINHEIRO = fixture("preco-publico-sf-v15-r43-somente-dinheiro-20261116.json");
const SF_V15_A = fixture("preco-publico-sf-v15-r3-cenarioA-20261113.json");

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));
vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/commercialTerritory", () => ({
  obterTerritorio: () => ({ uf: "ES", cidade: "Vitória" }),
}));

import { interpretarPrecoPublico } from "../domain/pricing/contractPricing";
import { permiteCheckoutSF15, modalidadesHabilitadas } from "../domain/pricing/pricingGateSF15";
import PainelPreco from "../components/commercial/PainelPreco";
import OpportunityCard from "../components/commercial/OpportunityCard";
import type { CommercialOpportunity } from "../domain/commercial/types";
import RevisaoContratacao from "../pages/RevisaoContratacao";
import { mensagemFalhaReserva } from "../domain/commercial/reservaMensagens";

beforeEach(() => rpcMock.mockReset());
afterEach(cleanup);

const comHabilitadas = (base: Record<string, unknown>, hab: unknown) => {
  const c = JSON.parse(JSON.stringify(base)) as { niches: Record<string, Record<string, unknown>>[] };
  for (const n of c.niches) for (const k of ["founding", "fidelized"]) n[k].enabled_settlement_modes = hab;
  return c;
};

describe("R4.3 — modalidades habilitadas pelo servidor", () => {
  it("lê somente DINHEIRO e libera o checkout com o preço do Cenário A", () => {
    const lista = interpretarPrecoPublico(SO_DINHEIRO)!;
    expect(lista).toHaveLength(6);
    const sm = lista.find((p) => p.nicheCode === "supermarket")!;
    expect(modalidadesHabilitadas(sm.founding)).toEqual(["cash"]);
    expect(sm.founding.settlementModes!.cash!.economicValueCents).toBe(3281732);
    expect(sm.fidelized.settlementModes!.cash!.economicValueCents).toBe(2805432);
    expect(permiteCheckoutSF15(lista)).toBe(true);
  });

  it("servidor anterior (sem a chave) = as duas; DINHEIRO sem preço continua bloqueando", () => {
    const lista = interpretarPrecoPublico(SF_V15_A)!;
    expect(modalidadesHabilitadas(lista[0].founding)).toEqual(["direct_benefits", "cash"]);
    const semDinheiro = comHabilitadas(SO_DINHEIRO, ["cash"]);
    for (const n of semDinheiro.niches) (n.founding.settlement_modes as Record<string, unknown>).cash = null;
    const l2 = interpretarPrecoPublico(semDinheiro);
    expect(l2 === null || !permiteCheckoutSF15(l2)).toBe(true);
  });

  it.each([[["pix"]], [["cash", "cash"]], [[]], ["cash"]])("lista inválida %j falha fechada", (hab) => {
    expect(interpretarPrecoPublico(comHabilitadas(SO_DINHEIRO, hab))).toBeNull();
  });

  it("vitrine: valor em dinheiro em destaque e benefício direto indisponível", async () => {
    rpcMock.mockResolvedValue({ data: SO_DINHEIRO, error: null });
    render(<MemoryRouter><PainelPreco nicheCode="supermarket" /></MemoryRouter>);
    expect((await screen.findByTestId("condicao-novo")).textContent).toMatch(/novo anunciante\s*, em dinheiro/);
    expect(screen.getAllByText("R$ 32.817,32").length).toBeGreaterThan(0);
    expect(screen.getByTestId("beneficio-direto-indisponivel")).toBeTruthy();
    expect(screen.getByTestId("total-modalidades").textContent).toMatch(/somente em dinheiro/);
  });

  it("card de oportunidade destaca o total DINHEIRO, não o benefício direto", () => {
    const preco = interpretarPrecoPublico(SO_DINHEIRO)!.find((p) => p.nicheCode === "supermarket")!;
    const oportunidade: CommercialOpportunity = {
      id: "fixture", exclusivityId: "fixture", nicheCode: "supermarket",
      displayName: "Supermercado", contractedQuantity: 24, status: "available",
      sortOrder: 1, acceptsSegment: false, requiresSegment: false, segment: null,
    };
    render(<MemoryRouter><OpportunityCard opportunity={oportunidade} precoVigente={preco} /></MemoryRouter>);
    const total = screen.getByTestId("valor-total");
    expect(within(total).getByText("R$ 32.817,32")).toBeTruthy();
    expect(total.textContent).toContain("em dinheiro");
    expect(screen.getByTestId("alternativa-dinheiro").textContent).toMatch(/Somente DINHEIRO/);
    expect(screen.getByTestId("destaque-beneficio-direto").textContent).not.toMatch(/pode cumprir essa parte com benefícios/);
  });

  it("preço de renovação fidelizada usa DINHEIRO, não benefício direto", async () => {
    rpcMock.mockResolvedValue({ data: SO_DINHEIRO, error: null });
    render(<MemoryRouter><PainelPreco nicheCode="supermarket" /></MemoryRouter>);
    const fidelizada = await screen.findByTestId("condicao-fidelizada");
    expect(fidelizada.textContent).toContain("R$ 28.054,32");
    expect(fidelizada.textContent).not.toContain("R$ 28.176,00");
  });

  it("checkout oferece só DINHEIRO", async () => {
    rpcMock.mockResolvedValue({ data: SO_DINHEIRO, error: null });
    render(
      <MemoryRouter initialEntries={["/checkout?nicho=supermarket"]}>
        <Routes><Route path="/checkout" element={<RevisaoContratacao />} /></Routes>
      </MemoryRouter>,
    );
    await screen.findByTestId("somente-dinheiro");
    await waitFor(() => {
      const linha = screen.getByText("Valor econômico da contratação nesta modalidade").parentElement;
      expect(linha?.textContent).toContain("R$ 32.817,32");
      expect(linha?.textContent).not.toContain("R$ 32.939,00");
      expect(screen.queryByText("Pool contratual total (MEIs + QA)")).toBeNull();
      const radios = screen.getAllByRole("radio") as HTMLInputElement[];
      expect(radios.map((r) => r.value)).toEqual(["cash"]);
      expect(radios[0].checked).toBe(true);
    });
  });

  it("recusa do servidor tem mensagem própria, sem texto do banco", () => {
    expect(mensagemFalhaReserva("settlement_mode_not_enabled")).toMatch(/somente na forma em dinheiro/);
  });
});
