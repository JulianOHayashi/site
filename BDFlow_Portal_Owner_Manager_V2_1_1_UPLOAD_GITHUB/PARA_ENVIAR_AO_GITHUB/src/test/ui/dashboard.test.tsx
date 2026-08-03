import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

// Mock do contexto do portal — controla papel/capacidades por teste.
const contextoMock = vi.fn();
vi.mock("../../hooks/usePortalContext", () => ({
  usePortalContext: () => contextoMock(),
}));

import PortalDashboard from "../../pages/portal/PortalDashboard";
import { readyState } from "./fixtures";

function renderDashboard() {
  return render(
    <MemoryRouter initialEntries={["/portal/dashboard"]}>
      <PortalDashboard />
    </MemoryRouter>
  );
}

beforeEach(() => contextoMock.mockReset());

describe("CORREÇÃO/estrutura — Dashboard por papel", () => {
  it("owner vê seções administrativas esperadas", async () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_owner", { canViewCompanyTransactions: false }),
      email: "owner@x.com",
      recarregar: vi.fn(),
    });
    renderDashboard();
    // Aguarda os subpainéis assíncronos (unidades/convites) assentarem.
    await waitFor(() =>
      expect(screen.getByRole("heading", { name: /Matriz e filiais/i })).toBeInTheDocument()
    );
    // "Equipe e convites" aparece no menu (link) e no heading da seção.
    expect(
      screen.getByRole("heading", { name: /Equipe e convites/i })
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /Equipe e convites/i })
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: /Transações e validações da empresa/i })
    ).toBeInTheDocument();
  });

  it("manager NÃO vê equipe, convites, filiais administrativas, financeiro ou transações gerais", () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_manager", { canValidateBenefits: true }),
      email: "manager@x.com",
      recarregar: vi.fn(),
    });
    renderDashboard();
    expect(screen.queryByText(/Equipe e convites/i)).toBeNull();
    expect(screen.queryByText(/Matriz e filiais/i)).toBeNull();
    expect(
      screen.queryByText(/Transações e validações da empresa/i)
    ).toBeNull();
    expect(screen.queryByText(/financeiro/i)).toBeNull();
    // Reduzido: mostra painel operacional
    expect(screen.getByText(/Painel operacional/i)).toBeInTheDocument();
  });

  it("nenhum papel recebe o CTA 'Cadastre sua empresa parceira'", () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_owner"),
      email: "o@x.com",
      recarregar: vi.fn(),
    });
    const { unmount } = renderDashboard();
    expect(screen.queryByText(/Cadastre sua empresa parceira/i)).toBeNull();
    unmount();
    contextoMock.mockReturnValue({
      state: readyState("partner_manager"),
      email: "m@x.com",
      recarregar: vi.fn(),
    });
    renderDashboard();
    expect(screen.queryByText(/Cadastre sua empresa parceira/i)).toBeNull();
  });
});
