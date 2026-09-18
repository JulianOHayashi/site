import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

const resetPasswordForEmail = vi.fn();
const updateUser = vi.fn();
const signOut = vi.fn();
const getSession = vi.fn();
const onAuthStateChange = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabaseConfigurado: true,
  supabase: {
    auth: {
      resetPasswordForEmail: (...a: unknown[]) => resetPasswordForEmail(...a),
      updateUser: (...a: unknown[]) => updateUser(...a),
      signOut: (...a: unknown[]) => signOut(...a),
      getSession: (...a: unknown[]) => getSession(...a),
      onAuthStateChange: (...a: unknown[]) => onAuthStateChange(...a),
    },
  },
}));

vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../pages/portal/portalUi", () => ({
  PortalNaoConfigurado: () => <div>não configurado</div>,
}));

import PortalForgotPassword from "../pages/portal/PortalForgotPassword";
import PortalResetPassword from "../pages/portal/PortalResetPassword";

beforeEach(() => {
  resetPasswordForEmail.mockReset();
  updateUser.mockReset();
  signOut.mockReset();
  getSession.mockReset();
  onAuthStateChange.mockReset();

  resetPasswordForEmail.mockResolvedValue({ data: {}, error: null });
  updateUser.mockResolvedValue({ data: {}, error: null });
  signOut.mockResolvedValue({ error: null });
  getSession.mockResolvedValue({
    data: { session: { access_token: "recovery-token" } },
    error: null,
  });
  onAuthStateChange.mockReturnValue({
    data: { subscription: { unsubscribe: vi.fn() } },
  });
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
  window.history.replaceState({}, "", "/");
});

describe("recuperação de senha do Portal", () => {
  it("solicita o reset apontando de volta para a rota do Site", async () => {
    render(
      <MemoryRouter>
        <PortalForgotPassword />
      </MemoryRouter>
    );

    fireEvent.change(screen.getByLabelText("E-mail"), {
      target: { value: "PARCEIRO@EXAMPLE.COM" },
    });
    fireEvent.click(screen.getByRole("button", { name: /Enviar link/i }));

    await waitFor(() => expect(resetPasswordForEmail).toHaveBeenCalledTimes(1));

    expect(resetPasswordForEmail).toHaveBeenCalledWith(
      "parceiro@example.com",
      {
        redirectTo:
          `${window.location.origin}/portal/redefinir-senha?mode=recovery`,
      }
    );
    expect(
      screen.getByText(/Se houver uma conta para este e-mail/i)
    ).toBeTruthy();
  });

  it("permite definir a nova senha somente com sessão de recuperação", async () => {
    window.history.replaceState(
      {},
      "",
      "/portal/redefinir-senha?mode=recovery"
    );

    render(
      <MemoryRouter>
        <PortalResetPassword />
      </MemoryRouter>
    );

    await screen.findByLabelText("Nova senha");

    fireEvent.change(screen.getByLabelText("Nova senha"), {
      target: { value: "NovaSenhaForte123!" },
    });
    fireEvent.change(screen.getByLabelText("Confirmar nova senha"), {
      target: { value: "NovaSenhaForte123!" },
    });
    fireEvent.click(screen.getByRole("button", { name: /Salvar nova senha/i }));

    await waitFor(() =>
      expect(updateUser).toHaveBeenCalledWith({
        password: "NovaSenhaForte123!",
      })
    );
    await waitFor(() => expect(signOut).toHaveBeenCalled());
    expect(await screen.findByText("Senha alterada")).toBeTruthy();
  });

  it("reprova link sem sessão válida", async () => {
    getSession.mockResolvedValue({ data: { session: null }, error: null });
    window.history.replaceState(
      {},
      "",
      "/portal/redefinir-senha?mode=recovery"
    );

    render(
      <MemoryRouter>
        <PortalResetPassword />
      </MemoryRouter>
    );

    expect(await screen.findByText(/Link inválido ou expirado/i)).toBeTruthy();
    expect(screen.queryByLabelText("Nova senha")).toBeNull();
  });
});
