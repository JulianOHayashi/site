import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { PartnerManagerSummary, ManagerInvitation } from "../../domain/portal/types";

const contextoMock = vi.fn();
vi.mock("../../hooks/usePortalContext", () => ({
  usePortalContext: () => contextoMock(),
}));

// Serviços mockados — controlam a lista de managers/convites por teste.
const listManagersMock = vi.fn();
const listInvitationsMock = vi.fn();
vi.mock("../../services/partnerTeamService", async (orig) => {
  const real = (await orig()) as any;
  return {
    ...real,
    listManagers: () => listManagersMock(),
    listInvitations: () => listInvitationsMock(),
  };
});

import PortalEquipe from "../../pages/portal/PortalEquipe";
import { readyState } from "./fixtures";

function mgr(over: Partial<PartnerManagerSummary>): PartnerManagerSummary {
  return {
    memberId: "m1",
    name: "Fulano",
    role: "partner_manager",
    status: "active",
    joinedAt: null,
    lastOperationalActivityAt: null,
    validationsCount: null,
    ...over,
  };
}

beforeEach(() => {
  contextoMock.mockReset();
  listManagersMock.mockReset();
  listInvitationsMock.mockReset();
  listInvitationsMock.mockResolvedValue({ ok: true, data: [] as ManagerInvitation[] });
  contextoMock.mockReturnValue({
    state: readyState("partner_owner", { canManageManagers: true, canInviteManagers: true }),
    email: "o@x.com",
    recarregar: vi.fn(),
  });
});

function renderEquipe() {
  return render(
    <MemoryRouter initialEntries={["/portal/equipe"]}>
      <PortalEquipe />
    </MemoryRouter>
  );
}

describe("CORREÇÃO 4 — Suspensão reversível", () => {
  it("manager ATIVO mostra 'Suspender' e não 'Reativar'", async () => {
    listManagersMock.mockResolvedValue({ ok: true, data: [mgr({ status: "active" })] });
    renderEquipe();
    await waitFor(() =>
      expect(screen.getByText(/Fulano/i)).toBeInTheDocument()
    );
    expect(screen.getByRole("button", { name: /^Suspender acesso$/i })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^Reativar acesso$/i })).toBeNull();
  });

  it("manager SUSPENSO mostra 'Reativar' e não 'Suspender'", async () => {
    listManagersMock.mockResolvedValue({ ok: true, data: [mgr({ status: "suspended" })] });
    renderEquipe();
    await waitFor(() => expect(screen.getByText(/Fulano/i)).toBeInTheDocument());
    expect(screen.getByRole("button", { name: /^Reativar acesso$/i })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^Suspender acesso$/i })).toBeNull();
  });

  it("manager ARQUIVADO não recebe suspender/reativar/revogar", async () => {
    listManagersMock.mockResolvedValue({ ok: true, data: [mgr({ status: "archived" })] });
    renderEquipe();
    await waitFor(() => expect(screen.getByText(/Fulano/i)).toBeInTheDocument());
    expect(screen.queryByRole("button", { name: /Suspender acesso/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /Reativar acesso/i })).toBeNull();
    expect(
      screen.queryByRole("button", { name: /Revogar acesso por desligamento/i })
    ).toBeNull();
  });

  it("manager EM ANÁLISE não apresenta suspensão como se estivesse ativo", async () => {
    listManagersMock.mockResolvedValue({
      ok: true,
      data: [mgr({ status: "pending_admin_review" })],
    });
    renderEquipe();
    await waitFor(() => expect(screen.getByText(/Fulano/i)).toBeInTheDocument());
    expect(screen.queryByRole("button", { name: /^Suspender acesso$/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /^Reativar acesso$/i })).toBeNull();
    expect(screen.getByText(/análise administrativa/i)).toBeInTheDocument();
  });
});
