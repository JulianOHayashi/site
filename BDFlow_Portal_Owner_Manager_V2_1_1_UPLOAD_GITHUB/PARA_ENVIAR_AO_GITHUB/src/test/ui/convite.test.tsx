import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";
import type { ManagerInvitation } from "../../domain/portal/types";
import { PortalError } from "../../domain/portal/types";

// Sessão autenticada mockada (para alcançar telas pós-login).
const sessionMock = vi.fn();
vi.mock("../../hooks/usePortalSiteAuth", () => ({
  usePortalSiteAuth: () => sessionMock(),
}));

const getPublicInvitationMock = vi.fn();
vi.mock("../../services/partnerTeamService", async (orig) => {
  const real = (await orig()) as any;
  return { ...real, getPublicInvitation: (t: string) => getPublicInvitationMock(t) };
});

import PortalConvite from "../../pages/portal/PortalConvite";

function LoginFake() {
  const loc = useLocation();
  return <div>LOGIN next={new URLSearchParams(loc.search).get("next")}</div>;
}

function renderConvite(path = "/portal/convites/TESTE?x=1") {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/portal/convites/:token" element={<PortalConvite />} />
        <Route path="/portal/login" element={<LoginFake />} />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => {
  sessionMock.mockReset();
  getPublicInvitationMock.mockReset();
  sessionMock.mockReturnValue({ session: { user: { email: "x@x.com" } }, carregando: false });
});

describe("CORREÇÃO 6 — E-mail divergente", () => {
  it("renderiza tela de e-mail divergente sem revelar o e-mail esperado", async () => {
    getPublicInvitationMock.mockResolvedValue({
      ok: false,
      error: new PortalError("INVITATION_EMAIL_MISMATCH"),
    });
    renderConvite();
    expect(
      await screen.findByText(/Conta diferente do destinatário/i)
    ).toBeInTheDocument();
    // Não deve revelar nenhum e-mail esperado (nenhum "@" de destinatário exibido além do texto).
    expect(screen.queryByText(/destinatário@/i)).toBeNull();
    expect(
      screen.getByRole("link", { name: /Trocar de conta/i })
    ).toBeInTheDocument();
  });

  it("abrir NÃO consome o convite (sem chamada de aceite)", async () => {
    getPublicInvitationMock.mockResolvedValue({
      ok: false,
      error: new PortalError("INVITATION_EXPIRED"),
    });
    renderConvite();
    expect(await screen.findByText(/Convite expirado/i)).toBeInTheDocument();
    expect(getPublicInvitationMock).toHaveBeenCalledTimes(1);
  });
});

describe("Convite — estados e next", () => {
  it("convite expirado mostra o texto exigido", async () => {
    getPublicInvitationMock.mockResolvedValue({
      ok: false,
      error: new PortalError("INVITATION_EXPIRED"),
    });
    renderConvite();
    expect(await screen.findByText(/Convite expirado/i)).toBeInTheDocument();
  });

  it("sem sessão, preserva pathname + search em next", async () => {
    sessionMock.mockReturnValue({ session: null, carregando: false });
    const conv: ManagerInvitation = {
      invitationId: "i1",
      batchId: "b1",
      label: null,
      url: null,
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 3600_000).toISOString(),
      status: "not_used",
      usedAt: null,
      usedByMemberId: null,
      usedByName: null,
    };
    getPublicInvitationMock.mockResolvedValue({ ok: true, data: conv });
    renderConvite("/portal/convites/ABC?y=2");
    // precisa_login → botão Entrar com next preservado
    const entrar = await screen.findByRole("link", { name: /Entrar/i });
    expect(entrar.getAttribute("href")).toContain(
      encodeURIComponent("/portal/convites/ABC?y=2")
    );
  });
});
