import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

const contextoMock = vi.fn();
vi.mock("../../hooks/usePortalContext", () => ({
  usePortalContext: () => contextoMock(),
}));

import PortalEquipe from "../../pages/portal/PortalEquipe";
import PortalUnidades from "../../pages/portal/PortalUnidades";
import PortalMeuAcesso from "../../pages/portal/PortalMeuAcesso";
import { readyState } from "./fixtures";

beforeEach(() => contextoMock.mockReset());

function renderIn(el: React.ReactElement, path: string) {
  return render(<MemoryRouter initialEntries={[path]}>{el}</MemoryRouter>);
}

describe("Guards por papel", () => {
  it("manager NÃO abre /portal/equipe (owner-only)", () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_manager"),
      email: "m@x.com",
      recarregar: vi.fn(),
    });
    renderIn(<PortalEquipe />, "/portal/equipe");
    expect(screen.getByText(/Acesso não autorizado/i)).toBeInTheDocument();
    expect(screen.queryByText(/Gerentes/i)).toBeNull();
  });

  it("manager NÃO abre /portal/unidades (owner-only)", () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_manager"),
      email: "m@x.com",
      recarregar: vi.fn(),
    });
    renderIn(<PortalUnidades />, "/portal/unidades");
    expect(screen.getByText(/Acesso não autorizado/i)).toBeInTheDocument();
  });

  it("owner NÃO abre /portal/meu-acesso (manager-only)", () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_owner"),
      email: "o@x.com",
      recarregar: vi.fn(),
    });
    renderIn(<PortalMeuAcesso />, "/portal/meu-acesso");
    expect(screen.getByText(/Acesso não autorizado/i)).toBeInTheDocument();
  });

  it("owner abre /portal/equipe", async () => {
    contextoMock.mockReturnValue({
      state: readyState("partner_owner", { canManageManagers: true }),
      email: "o@x.com",
      recarregar: vi.fn(),
    });
    renderIn(<PortalEquipe />, "/portal/equipe");
    await waitFor(() =>
      expect(
        screen.getByRole("heading", { name: /^Equipe e convites$/i })
      ).toBeInTheDocument()
    );
  });
});

describe("CORREÇÃO 5 — Vínculo encerrado / estados de membro", () => {
  it("vínculo somente arquivado mostra 'Vínculo encerrado'", () => {
    contextoMock.mockReturnValue({
      state: {
        kind: "ready",
        membership: {
          memberId: "m1",
          role: "partner_manager",
          status: "archived",
          company: {
            companyId: "c1",
            partnerDisplayName: "Loja",
            status: "active",
            contractStatusLabel: null,
            paymentStatusLabel: null,
            nicheLabel: null,
            exclusivityStatusLabel: null,
            operationStatusLabel: null,
            notices: [],
          },
        },
        capabilities: {
          canAccessPortal: false,
          canPrepareOperation: false,
          canManageUnits: false,
          canInviteManagers: false,
          canManageManagers: false,
          canValidateBenefits: false,
          canViewCompanyTransactions: false,
          canAccessFinancial: false,
        },
        capabilitiesSource: "unavailable",
      },
      email: "m@x.com",
      recarregar: vi.fn(),
    });
    renderIn(<PortalMeuAcesso />, "/portal/meu-acesso");
    expect(screen.getByText(/Vínculo encerrado/i)).toBeInTheDocument();
  });

  it("falha de consulta NÃO vira 'sem vínculo'", () => {
    contextoMock.mockReturnValue({
      state: { kind: "error", code: "QUERY_FAILED" },
      email: null,
      recarregar: vi.fn(),
    });
    renderIn(<PortalMeuAcesso />, "/portal/meu-acesso");
    expect(
      screen.getByText(/Não foi possível carregar seu acesso/i)
    ).toBeInTheDocument();
    expect(screen.queryByText(/vínculo elegível para o Portal/i)).toBeNull();
  });
});
