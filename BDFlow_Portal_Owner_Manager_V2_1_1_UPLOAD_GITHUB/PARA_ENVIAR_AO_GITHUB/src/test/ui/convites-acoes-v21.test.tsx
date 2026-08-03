import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import type { ManagerInvitation } from "../../domain/portal/types";

// Espiões dos serviços de convite/manager.
const listInvitationsMock = vi.fn();
const listManagersMock = vi.fn();
const revokeInvitationBatchMock = vi.fn();
const replaceInvitationMock = vi.fn();
const revokeInvitationMock = vi.fn();

vi.mock("../../services/partnerTeamService", async (orig) => {
  const real = (await orig()) as any;
  return {
    ...real,
    listInvitations: () => listInvitationsMock(),
    listManagers: () => listManagersMock(),
    revokeInvitationBatch: (id: string) => revokeInvitationBatchMock(id),
    replaceInvitation: (id: string) => replaceInvitationMock(id),
    revokeInvitation: (id: string) => revokeInvitationMock(id),
  };
});

import EquipeConvitesPainel from "../../components/portal/EquipeConvitesPainel";
import { capsFake } from "./fixtures";

const criado = new Date().toISOString();
const expira = new Date(Date.now() + 24 * 3600_000).toISOString();

function conv(over: Partial<ManagerInvitation>): ManagerInvitation {
  return {
    invitationId: "i1",
    batchId: "batch-AAA11111",
    label: null,
    url: null,
    createdAt: criado,
    expiresAt: expira,
    status: "not_used",
    usedAt: null,
    usedByMemberId: null,
    usedByName: null,
    ...over,
  };
}

function renderPainel() {
  return render(
    <MemoryRouter>
      <EquipeConvitesPainel capabilities={capsFake({ canInviteManagers: true, canManageManagers: true })} />
    </MemoryRouter>
  );
}

beforeEach(() => {
  listInvitationsMock.mockReset();
  listManagersMock.mockReset();
  revokeInvitationBatchMock.mockReset();
  replaceInvitationMock.mockReset();
  revokeInvitationMock.mockReset();
  listManagersMock.mockResolvedValue({ ok: true, data: [] });
  revokeInvitationBatchMock.mockResolvedValue({ ok: false, error: { code: "BACKEND_NOT_AVAILABLE" } });
  replaceInvitationMock.mockResolvedValue({ ok: false, error: { code: "BACKEND_NOT_AVAILABLE" } });
  revokeInvitationMock.mockResolvedValue({ ok: false, error: { code: "BACKEND_NOT_AVAILABLE" } });
});

describe("V2.1 — ações de convites por lote", () => {
  it("'Revogar convites disponíveis deste lote' chama o serviço com o batchId correto", async () => {
    // Lote com 1 disponível + 1 utilizado (o utilizado NÃO deve ser afetado).
    listInvitationsMock.mockResolvedValue({
      ok: true,
      data: [
        conv({ invitationId: "a", status: "not_used", batchId: "batch-AAA11111" }),
        conv({ invitationId: "b", status: "used", usedAt: criado, batchId: "batch-AAA11111" }),
      ],
    });
    renderPainel();
    const botao = await screen.findByRole("button", {
      name: /Revogar convites disponíveis deste lote/i,
    });
    await userEvent.click(botao);
    expect(revokeInvitationBatchMock).toHaveBeenCalledWith("batch-AAA11111");
  });

  it("revogar o lote não remove nem altera o convite já utilizado (backend indisponível → sem mudança)", async () => {
    listInvitationsMock.mockResolvedValue({
      ok: true,
      data: [
        conv({ invitationId: "a", status: "not_used" }),
        conv({ invitationId: "b", status: "used", usedAt: criado, usedByMemberId: "m9", usedByName: "Gerente Nove" }),
      ],
    });
    renderPainel();
    // O convite utilizado continua visível como "Utilizado" após a tentativa.
    await userEvent.click(
      await screen.findByRole("button", { name: /Revogar convites disponíveis deste lote/i })
    );
    // Sem sucesso: mensagem de indisponibilidade e o utilizado permanece.
    expect(await screen.findByText(/Nenhuma alteração foi aplicada/i)).toBeInTheDocument();
    expect(screen.getByText(/Utilizado em/i)).toBeInTheDocument();
  });

  it("'Gerar substituto' aparece para convite EXPIRADO e chama replace com o invitationId correto", async () => {
    listInvitationsMock.mockResolvedValue({
      ok: true,
      data: [conv({ invitationId: "exp1", status: "expired" })],
    });
    renderPainel();
    const btn = await screen.findByRole("button", { name: /Gerar substituto/i });
    await userEvent.click(btn);
    expect(replaceInvitationMock).toHaveBeenCalledWith("exp1");
  });

  it("'Gerar substituto' aparece para convite REVOGADO", async () => {
    listInvitationsMock.mockResolvedValue({
      ok: true,
      data: [conv({ invitationId: "rev1", status: "revoked" })],
    });
    renderPainel();
    expect(
      await screen.findByRole("button", { name: /Gerar substituto/i })
    ).toBeInTheDocument();
  });

  it("convite utilizado exibe o nome do manager e aponta para /portal/equipe/:memberId", async () => {
    listInvitationsMock.mockResolvedValue({
      ok: true,
      data: [
        conv({
          invitationId: "u1",
          status: "used",
          usedAt: criado,
          usedByMemberId: "member-77",
          usedByName: "Gerente Setenta e Sete",
        }),
      ],
    });
    renderPainel();
    const link = await screen.findByRole("link", { name: /Gerente Setenta e Sete/i });
    expect(link.getAttribute("href")).toBe("/portal/equipe/member-77");
  });
});
