import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * M1 — conta provisória NÃO acessa o /portal do parceiro aprovado.
 *
 * Mock apenas na fronteira externa (lib/supabase); o guard e o hook reais
 * são exercitados. O tipo de conta vem do backend, não do navegador.
 */
const rpcMock = vi.fn();

vi.mock("../lib/supabase", () => {
  const auth = {
    getSession: vi.fn(async () => ({
      data: { session: { access_token: "t", user: { id: "u1" } } },
    })),
    onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
  };
  return {
    supabase: { auth, rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
    supabaseConfigurado: true,
  };
});

import PortalGuard from "../components/PortalGuard";

function montar() {
  return render(
    <MemoryRouter initialEntries={["/portal/dashboard"]}>
      <Routes>
        <Route
          path="/portal/dashboard"
          element={
            <PortalGuard>
              <div data-testid="portal">painel do parceiro</div>
            </PortalGuard>
          }
        />
        <Route path="/parceiros/solicitacao" element={<div data-testid="area-provisoria">acompanhamento</div>} />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => { rpcMock.mockReset(); localStorage.clear(); });
afterEach(() => cleanup());

describe("PortalGuard e conta provisória", () => {
  it("redireciona conta provisória para a área de acompanhamento", async () => {
    rpcMock.mockResolvedValue({
      data: { application_id: "a1", status: "under_review", account_kind: "provisional" },
      error: null,
    });
    montar();
    await waitFor(() => expect(screen.getByTestId("area-provisoria")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("libera o portal para conta que não é provisória", async () => {
    rpcMock.mockResolvedValue({ data: { application_id: null }, error: null });
    montar();
    await waitFor(() => expect(screen.getByTestId("portal")).toBeDefined());
  });

  it("não renderiza o portal enquanto o tipo de conta é desconhecido", async () => {
    rpcMock.mockImplementation(() => new Promise(() => {}));
    montar();
    await waitFor(() => expect(screen.getByText(/verificando acesso/i)).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });
});
