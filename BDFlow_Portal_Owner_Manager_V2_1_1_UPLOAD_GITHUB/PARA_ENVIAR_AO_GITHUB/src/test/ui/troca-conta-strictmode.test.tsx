import { describe, it, expect, vi, beforeEach } from "vitest";
import { StrictMode } from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Routes, Route } from "react-router-dom";

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

const sessionMock = vi.fn();
vi.mock("../../hooks/usePortalSiteAuth", () => ({
  usePortalSiteAuth: () => sessionMock(),
}));

import PortalLogin from "../../pages/portal/PortalLogin";

const CONVITE = "/portal/convites/ABC?y=2";
const loginTroca = `/portal/login?next=${encodeURIComponent(CONVITE)}&switch_account=1`;

function renderStrict(entrada: string) {
  return render(
    <StrictMode>
      <MemoryRouter initialEntries={[entrada]}>
        <Routes>
          <Route path="/portal/login" element={<PortalLogin />} />
        </Routes>
      </MemoryRouter>
    </StrictMode>
  );
}

beforeEach(() => {
  signOutMock.mockReset();
  signInMock.mockReset();
  sessionMock.mockReset();
  sessionMock.mockReturnValue({
    session: { user: { email: "errado@x.com" } },
    carregando: false,
  });
});

describe("V2.1 — troca de conta sob React.StrictMode", () => {
  it("chama signOut({scope:'local'}) EXATAMENTE UMA vez (sem duplicação por StrictMode)", async () => {
    signOutMock.mockResolvedValue({ error: null });
    renderStrict(loginTroca);
    await waitFor(() =>
      expect(screen.getByText(/A sessão anterior foi encerrada/i)).toBeInTheDocument()
    );
    expect(signOutMock).toHaveBeenCalledTimes(1);
    expect(signOutMock).toHaveBeenCalledWith({ scope: "local" });
  });

  it("após falha, a retentativa manual ainda funciona (chama signOut de novo)", async () => {
    signOutMock.mockResolvedValueOnce({ error: { message: "network" } });
    renderStrict(loginTroca);
    const retry = await screen.findByRole("button", {
      name: /Tentar encerrar sessão novamente/i,
    });
    expect(signOutMock).toHaveBeenCalledTimes(1); // 1 automática (falhou)
    signOutMock.mockResolvedValueOnce({ error: null });
    await userEvent.click(retry);
    await waitFor(() =>
      expect(screen.getByLabelText(/E-mail/i)).toBeInTheDocument()
    );
    expect(signOutMock).toHaveBeenCalledTimes(2); // 1 automática + 1 retentativa
  });
});
