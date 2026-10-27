import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

const getSession = vi.fn();
const signOut = vi.fn();
const unsubscribe = vi.fn();
const onAuthStateChange = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabase: {
    auth: {
      getSession: (...args: unknown[]) => getSession(...args),
      signOut: (...args: unknown[]) => signOut(...args),
      onAuthStateChange: (...args: unknown[]) => onAuthStateChange(...args),
    },
  },
  supabaseConfigurado: true,
}));

import SiteHeader from "../components/SiteHeader";

function montar() {
  return render(
    <MemoryRouter initialEntries={["/parceiros/confirmar"]}>
      <SiteHeader />
      <Routes>
        <Route path="/portal/login" element={<div data-testid="login">login</div>} />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => {
  getSession.mockReset();
  signOut.mockReset();
  onAuthStateChange.mockReset();
  unsubscribe.mockReset();

  getSession.mockResolvedValue({
    data: { session: { access_token: "token", user: { id: "revoked-user" } } },
  });
  onAuthStateChange.mockReturnValue({
    data: { subscription: { unsubscribe } },
  });
  signOut.mockResolvedValue({ error: null });
});

afterEach(() => cleanup());

describe("SiteHeader logout global", () => {
  it("sessao autenticada exibe Sair em vez de Entrar", async () => {
    montar();
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /^sair$/i })).toBeDefined()
    );
    expect(screen.queryByRole("link", { name: /^entrar$/i })).toBeNull();
  });

  it("Sair encerra somente a sessao local e redireciona ao login", async () => {
    montar();

    const botao = await screen.findByRole("button", { name: /^sair$/i });
    fireEvent.click(botao);

    await waitFor(() =>
      expect(signOut).toHaveBeenCalledWith({ scope: "local" })
    );
    await waitFor(() =>
      expect(screen.getByTestId("login")).toBeDefined()
    );
  });
});
