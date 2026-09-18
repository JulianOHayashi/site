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
  const from = vi.fn(() => ({
    select: vi.fn(() => ({
      eq: vi.fn(() => ({
        eq: vi.fn(() => ({
          in: vi.fn(async () => ({ data: [], error: null })),
        })),
      })),
    })),
  }));
  return {
    supabase: { auth, rpc: (...a: unknown[]) => rpcMock(...(a as [])), from },
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

  it("autenticado SEM contexto de parceiro e NEGADO", async () => {
    // Ausencia de solicitacao nao e autorizacao: uma conta Auth qualquer
    // satisfaria essa condicao. Antes isso liberava o portal — era fail-open.
    rpcMock.mockResolvedValue({ data: { application_id: null }, error: null });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.getByText(/portal indisponível para esta conta/i)).toBeDefined();
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("conta com vinculo nao provisorio tambem e NEGADA", async () => {
    rpcMock.mockResolvedValue({
      data: { application_id: "a1", status: "approved", account_kind: "outro" },
      error: null,
    });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("NENHUMA resposta possivel do backend M1 renderiza o portal", async () => {
    // Varredura das formas de resposta que get_my_partner_application pode
    // produzir hoje. O M1 nao emite contexto de parceiro autorizado — essa
    // promocao pertence ao M2 —, entao o portal permanece fechado.
    const respostas = [
      { application_id: null },
      { application_id: "a1", account_kind: "none", status: "pending_email_verification" },
      { application_id: "a1", account_kind: "none", status: "pending_account_setup" },
      { application_id: "a1", account_kind: "provisional", status: "under_review" },
      { application_id: "a1", account_kind: "provisional", status: "changes_requested" },
      { application_id: "a1", account_kind: "provisional", status: "approved" },
      { application_id: "a1", account_kind: "provisional", status: "rejected" },
    ];
    for (const data of respostas) {
      rpcMock.mockReset();
      rpcMock.mockResolvedValue({ data, error: null });
      const { unmount } = montar();
      await waitFor(() =>
        expect(
          screen.queryByRole("alert") ?? screen.queryByTestId("area-provisoria")
        ).not.toBeNull()
      );
      expect(screen.queryByTestId("portal")).toBeNull();
      unmount();
    }
  });

  it("SOMENTE prova positiva de parceiro autorizado liberaria o portal", async () => {
    // Contrato do guard, verificado na unidade de decisao. Hoje nenhum
    // caminho do M1 produz este contexto; quando o M2 produzir, o guard ja
    // esta escrito para ele.
    const { decidirParaTeste } = await import("../components/PortalGuard");
    expect(decidirParaTeste({ tipo: "parceiro_autorizado" })).toBe("liberado");
    expect(decidirParaTeste({ tipo: "sem_contexto_parceiro" })).toBe("sem_contexto");
    expect(decidirParaTeste({ tipo: "erro" })).toBe("erro");
    expect(decidirParaTeste({ tipo: "nao_autenticado" })).toBe("erro");
    expect(decidirParaTeste(null)).toBe("carregando");
  });
});
