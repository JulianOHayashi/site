import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";

// --- Mock do cliente Supabase do SITE ---
const signOutMock = vi.fn();
const signInMock = vi.fn();
vi.mock("../../lib/supabase", () => ({
  supabase: {
    auth: {
      signOut: (opts: unknown) => signOutMock(opts),
      signInWithPassword: (c: unknown) => signInMock(c),
    },
  },
  supabaseConfigurado: true,
}));

// --- Mock do hook de sessão: começa com sessão "incorreta" aberta ---
const sessionMock = vi.fn();
vi.mock("../../hooks/usePortalSiteAuth", () => ({
  usePortalSiteAuth: () => sessionMock(),
}));

import PortalLogin from "../../pages/portal/PortalLogin";

function DestinoFake() {
  const loc = useLocation();
  return <div>NO_CONVITE{loc.pathname}{loc.search}</div>;
}

function renderLogin(entrada: string) {
  return render(
    <MemoryRouter initialEntries={[entrada]}>
      <Routes>
        <Route path="/portal/login" element={<PortalLogin />} />
        <Route path="/portal/convites/:token" element={<DestinoFake />} />
        <Route path="/portal/dashboard" element={<div>NO_DASHBOARD</div>} />
      </Routes>
    </MemoryRouter>
  );
}

const CONVITE = "/portal/convites/ABC?y=2";
const loginTroca = `/portal/login?next=${encodeURIComponent(CONVITE)}&switch_account=1`;

beforeEach(() => {
  signOutMock.mockReset();
  signInMock.mockReset();
  sessionMock.mockReset();
  // Sessão "incorreta" já autenticada.
  sessionMock.mockReturnValue({
    session: { user: { email: "errado@x.com" } },
    carregando: false,
  });
});

describe("CORREÇÃO 5.2 — Troca segura de conta", () => {
  it("'Trocar de conta' chama signOut com escopo local", async () => {
    signOutMock.mockResolvedValue({ error: null });
    renderLogin(loginTroca);
    await waitFor(() => expect(signOutMock).toHaveBeenCalled());
    expect(signOutMock).toHaveBeenCalledWith({ scope: "local" });
  });

  it("a sessão incorreta NÃO redireciona de volta ao convite", async () => {
    signOutMock.mockResolvedValue({ error: null });
    renderLogin(loginTroca);
    // Após encerrar, mostra o formulário — nunca navega ao convite sozinho.
    await waitFor(() =>
      expect(screen.getByText(/A sessão anterior foi encerrada/i)).toBeInTheDocument()
    );
    expect(screen.queryByText(/NO_CONVITE/)).toBeNull();
    expect(screen.getByLabelText(/E-mail/i)).toBeInTheDocument();
  });

  it("retorna ao convite SOMENTE após nova autenticação, preservando pathname+search", async () => {
    signOutMock.mockResolvedValue({ error: null });
    signInMock.mockResolvedValue({ error: null });
    renderLogin(loginTroca);
    await screen.findByText(/A sessão anterior foi encerrada/i);

    await userEvent.type(screen.getByLabelText(/E-mail/i), "certo@x.com");
    await userEvent.type(screen.getByLabelText(/Senha/i), "segredo123");
    // Botão de submit do formulário (o Header também tem um "Entrar").
    const submit = document.querySelector('form button[type="submit"]') as HTMLButtonElement;
    await userEvent.click(submit);

    // Só agora volta ao convite, com a rota completa preservada.
    expect(await screen.findByText("NO_CONVITE/portal/convites/ABC?y=2")).toBeInTheDocument();
  });

  it("falha no signOut bloqueia o formulário e oferece nova tentativa", async () => {
    signOutMock.mockResolvedValueOnce({ error: { message: "network" } });
    renderLogin(loginTroca);
    expect(
      await screen.findByText(/Não foi possível encerrar a sessão anterior/i)
    ).toBeInTheDocument();
    // Formulário bloqueado: sem campos de login visíveis.
    expect(screen.queryByLabelText(/E-mail/i)).toBeNull();
    // Botão de nova tentativa disponível.
    const retry = screen.getByRole("button", { name: /Tentar encerrar sessão novamente/i });
    // Segunda tentativa bem-sucedida libera o formulário.
    signOutMock.mockResolvedValueOnce({ error: null });
    await userEvent.click(retry);
    await waitFor(() => expect(screen.getByLabelText(/E-mail/i)).toBeInTheDocument());
  });
});

describe("CORREÇÃO 5 — fluxo normal preservado (sem switch_account)", () => {
  it("sessão já autenticada segue o comportamento normal (redireciona ao next seguro)", async () => {
    sessionMock.mockReturnValue({
      session: { user: { email: "ok@x.com" } },
      carregando: false,
    });
    renderLogin(`/portal/login?next=${encodeURIComponent(CONVITE)}`);
    // Sem switch_account, a sessão existente redireciona normalmente ao next.
    expect(await screen.findByText("NO_CONVITE/portal/convites/ABC?y=2")).toBeInTheDocument();
    expect(signOutMock).not.toHaveBeenCalled();
  });
});
