import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { renderPortal, SESSAO_FALSA } from "./helpers/portalRender";

const obterVinculosParceiro = vi.fn();
vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { signOut: vi.fn() } },
}));
vi.mock("../hooks/usePortalSiteAuth", () => ({
  usePortalSiteAuth: () => SESSAO_FALSA(),
}));
vi.mock("../services/partnerApplicationService", () => ({
  obterVinculosParceiro: (...a: unknown[]) => obterVinculosParceiro(...a),
}));

import PortalDashboard from "../pages/portal/PortalDashboard";
import PortalSolicitacoes from "../pages/portal/PortalSolicitacoes";

/**
 * PRECISÃO DO PORTAL.
 *
 * Dois erros factuais que o Portal exibia e que estes testes impedem de voltar:
 *
 * 1. O card de validação dizia "integração em preparação", apesar de o fluxo
 *    QR → solicitação → confirmação no App já estar testado ponta a ponta.
 * 2. /portal/solicitacoes dizia "Nenhuma solicitação encontrada", afirmando um
 *    fato que o Portal não tem como verificar: ele não lê o histórico do App.
 *
 * E uma armadilha de usabilidade: com mais de um vínculo, a primeira empresa
 * era adotada em silêncio.
 */
const VINCULO = (id: string, nome: string) => ({
  company_id: id,
  trade_name: nome,
  company_status: "active",
  member_id: `m-${id}`,
  role: "partner_owner" as const,
  member_status: "active",
  city: "Vitória",
  uf: "ES",
});

beforeEach(() => {
  vi.clearAllMocks();
  // A dica de empresa é por sessão: sem limpar, um teste herda a escolha do anterior.
  sessionStorage.clear();
});
afterEach(() => cleanup());

function montarDashboard() {
  return renderPortal(<PortalDashboard />);
}

describe("PortalDashboard — precisão dos cards", () => {
  it("não afirma que a validação está em preparação", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [VINCULO("c1", "Empresa QA")] });
    const { container } = montarDashboard();
    await screen.findAllByText("Empresa QA");
    expect(container.textContent).not.toMatch(/integração em preparação/i);
    // O card de atalho, não o link compacto do topo do Portal.
    const card = screen
      .getByRole("heading", { name: "Validar benefício" })
      .closest("a")!;
    expect(card.textContent).toMatch(/QR code/i);
  });

  it("descreve o histórico como indisponível, não como inexistente", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [VINCULO("c1", "Empresa QA")] });
    const { container } = montarDashboard();
    await screen.findAllByText("Empresa QA");
    const card = screen.getByRole("heading", { name: "Solicitações" }).closest("a")!;
    expect(card.textContent).toMatch(/ainda não está disponível/i);
    expect(card.textContent).not.toMatch(/nenhuma/i);
  });
});

describe("PortalDashboard — escolha de empresa", () => {
  it("com um vínculo, usa-o direto e não pede escolha", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [VINCULO("c1", "Empresa QA")] });
    montarDashboard();
    expect((await screen.findAllByText("Empresa QA")).length).toBeGreaterThan(0);
    expect(screen.queryByLabelText(/escolha a empresa/i)).toBeNull();
  });

  it("com vários vínculos, não adota nenhum em silêncio", async () => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [VINCULO("c1", "Empresa Um"), VINCULO("c2", "Empresa Dois")],
    });
    const { container } = montarDashboard();
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    // Nenhuma das duas é adotada: não há empresa ativa nem atalhos.
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
    // Os cards de atalho não existem; o link compacto do topo do Portal é
    // outra coisa e continua lá.
    expect(screen.queryByRole("heading", { name: "Validar benefício" })).toBeNull();
    // As duas aparecem como opções, na ordem recebida.
    const opcoes = screen.getAllByRole("button").map((b) => b.textContent ?? "");
    expect(opcoes.some((t) => t.includes("Empresa Um"))).toBe(true);
    expect(opcoes.some((t) => t.includes("Empresa Dois"))).toBe(true);
  });
});

describe("PortalSolicitacoes", () => {
  it("explica a ausência de histórico e oferece caminho real", () => {
    const { container } = render(
      <MemoryRouter>
        <PortalSolicitacoes />
      </MemoryRouter>
    );
    expect(container.textContent).not.toMatch(/nenhuma solicitação encontrada/i);
    expect(screen.getByRole("heading", { level: 2 })).toBeDefined();
    expect(container.textContent).toMatch(/ainda não consulta o histórico/i);
    expect(container.querySelector('a[href="/portal/validar"]')).not.toBeNull();
  });
});
