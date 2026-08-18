import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * B3 — PortalGuard fail-closed.
 *
 * A prova central: ERRO DE RPC NUNCA LIBERA O PORTAL. Antes, o serviço
 * devolvia null tanto para "não tem solicitação" quanto para falha, e o
 * guard tratava os dois como "não é provisória" → liberava. Fail-open.
 */
const rpcMock = vi.fn();

vi.mock("../lib/supabase", () => {
  const auth = {
    getSession: vi.fn(async () => ({ data: { session: { access_token: "t", user: { id: "u1" } } } })),
    onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
  };
  return { supabase: { auth, rpc: (...a: unknown[]) => rpcMock(...(a as [])) }, supabaseConfigurado: true };
});

import PortalGuard from "../components/PortalGuard";

function montar() {
  return render(
    <MemoryRouter initialEntries={["/portal/dashboard"]}>
      <Routes>
        <Route
          path="/portal/dashboard"
          element={<PortalGuard><div data-testid="portal">painel do parceiro</div></PortalGuard>}
        />
        <Route path="/parceiros/solicitacao" element={<div data-testid="area-provisoria">acompanhamento</div>} />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => { rpcMock.mockReset(); localStorage.clear(); });
afterEach(() => cleanup());

describe("B3 — PortalGuard fail-closed", () => {
  it("ERRO da RPC nao renderiza o portal", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
    expect(screen.queryByTestId("area-provisoria")).toBeNull();
  });

  it("RPC que lanca excecao tambem nao renderiza o portal", async () => {
    rpcMock.mockRejectedValue(new Error("network"));
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("resposta malformada nao renderiza o portal", async () => {
    rpcMock.mockResolvedValue({ data: "nao-e-objeto", error: null });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("enquanto carrega, o portal nao aparece", async () => {
    rpcMock.mockImplementation(() => new Promise(() => {}));
    montar();
    await waitFor(() => expect(screen.getByText(/verificando acesso/i)).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("conta provisoria e redirecionada a area de acompanhamento", async () => {
    rpcMock.mockResolvedValue({
      data: { application_id: "a1", status: "under_review", account_kind: "provisional" },
      error: null,
    });
    montar();
    await waitFor(() => expect(screen.getByTestId("area-provisoria")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("conta sem solicitacao acessa o portal", async () => {
    rpcMock.mockResolvedValue({ data: { application_id: null }, error: null });
    montar();
    await waitFor(() => expect(screen.getByTestId("portal")).toBeDefined());
  });
});
