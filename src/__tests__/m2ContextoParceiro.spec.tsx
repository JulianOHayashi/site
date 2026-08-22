import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * R3 — Contexto POSITIVO de parceiro (M2) e correção do PortalDashboard.
 *
 * Provas centrais:
 *   1. `parceiro_autorizado` só nasce de vínculo durável ativo;
 *   2. o parceiro promovido NÃO é rebaixado a "provisória" — a solicitação
 *      canônica continua com account_kind='provisional' depois da promoção;
 *   3. erro/formato inesperado do contexto NUNCA libera o Portal;
 *   4. NENHUM código vivo consulta a tabela obsoleta site_partner_members.
 */
const rpcMock = vi.fn();
const fromMock = vi.fn();

vi.mock("../lib/supabase", () => {
  const auth = {
    getSession: vi.fn(async () => ({
      data: { session: { access_token: "t", user: { id: "u1", email: "p@x.z" } } },
    })),
    onAuthStateChange: vi.fn(() => ({
      data: { subscription: { unsubscribe: vi.fn() } },
    })),
    signOut: vi.fn(async () => ({})),
  };
  return {
    supabase: {
      auth,
      rpc: (...a: unknown[]) => rpcMock(...(a as [])),
      from: (...a: unknown[]) => fromMock(...(a as [])),
    },
    supabaseConfigurado: true,
  };
});

import PortalGuard from "../components/PortalGuard";
import PortalDashboard from "../pages/portal/PortalDashboard";
import {
  interpretarContextoParceiro,
  obterContextoConta,
} from "../services/partnerApplicationService";

const VINCULO = {
  company_id: "c1",
  trade_name: "Parceiro Canonico",
  company_status: "active",
  member_id: "m1",
  role: "partner_owner",
  member_status: "active",
  city: "Vitória",
  uf: "ES",
};

/** Responde por nome de RPC, como o backend real. */
function responder(mapa: Record<string, unknown>) {
  rpcMock.mockImplementation(async (nome: string) => {
    if (nome in mapa) return mapa[nome];
    return { data: null, error: { message: "rpc inesperada: " + nome } };
  });
}

function montarGuard() {
  return render(
    <MemoryRouter initialEntries={["/portal/dashboard"]}>
      <Routes>
        <Route
          path="/portal/dashboard"
          element={
            <PortalGuard>
              <div data-testid="portal">painel</div>
            </PortalGuard>
          }
        />
        <Route
          path="/parceiros/solicitacao"
          element={<div data-testid="area-provisoria">acompanhamento</div>}
        />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => {
  rpcMock.mockReset();
  fromMock.mockReset();
  localStorage.clear();
});
afterEach(() => cleanup());

describe("R3 — parser estrito do contexto durável", () => {
  it("resposta canônica com vínculo ativo é aceita", () => {
    const r = interpretarContextoParceiro({
      ok: true,
      authorized: true,
      memberships: [VINCULO],
    });
    expect(r).not.toBeNull();
    expect(r?.[0].role).toBe("partner_owner");
  });

  it("sem vínculo devolve lista vazia (não é erro, mas não autoriza)", () => {
    expect(
      interpretarContextoParceiro({ ok: true, authorized: false, memberships: [] })
    ).toEqual([]);
  });

  const invalidos: Array<[string, unknown]> = [
    ["null", null],
    ["ok ausente", { authorized: true, memberships: [VINCULO] }],
    ["authorized string", { ok: true, authorized: "true", memberships: [] }],
    ["memberships não-lista", { ok: true, authorized: false, memberships: {} }],
    [
      "authorized=true sem vínculos",
      { ok: true, authorized: true, memberships: [] },
    ],
    [
      "authorized=false com vínculos",
      { ok: true, authorized: false, memberships: [VINCULO] },
    ],
    [
      "papel desconhecido",
      { ok: true, authorized: true, memberships: [{ ...VINCULO, role: "root" }] },
    ],
    [
      "vínculo suspenso listado",
      {
        ok: true,
        authorized: true,
        memberships: [{ ...VINCULO, member_status: "suspended" }],
      },
    ],
    [
      "empresa suspensa listada",
      {
        ok: true,
        authorized: true,
        memberships: [{ ...VINCULO, company_status: "suspended" }],
      },
    ],
  ];
  for (const [nome, dado] of invalidos) {
    it(`formato inesperado NAO autoriza: ${nome}`, () => {
      expect(interpretarContextoParceiro(dado)).toBeNull();
    });
  }
});

describe("R3 — obterContextoConta consulta o vínculo durável primeiro", () => {
  it("parceiro promovido vira parceiro_autorizado, nao provisoria", async () => {
    // A solicitação canônica CONTINUA provisional depois da promoção.
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: true, memberships: [VINCULO] },
        error: null,
      },
      get_my_partner_application: {
        data: { application_id: "a1", account_kind: "provisional" },
        error: null,
      },
    });
    const ctx = await obterContextoConta();
    expect(ctx.tipo).toBe("parceiro_autorizado");
  });

  it("sem vinculo duravel, provisoria continua provisoria", async () => {
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: false, memberships: [] },
        error: null,
      },
      get_my_partner_application: {
        data: { application_id: "a1", account_kind: "provisional" },
        error: null,
      },
    });
    expect((await obterContextoConta()).tipo).toBe("provisoria");
  });

  it("erro no contexto duravel NUNCA autoriza: mantem o veredito do M1", async () => {
    // O vínculo durável só ELEVA. Falhando, permanece o veredito canônico —
    // e todo veredito do M1 mantém o Portal fechado.
    responder({
      get_my_partner_context: { data: null, error: { message: "boom" } },
      get_my_partner_application: {
        data: { application_id: "a1", account_kind: "provisional" },
        error: null,
      },
    });
    const ctx = await obterContextoConta();
    expect(ctx.tipo).toBe("provisoria");
    expect(ctx.tipo).not.toBe("parceiro_autorizado");
  });

  it("contexto duravel corrompido NUNCA autoriza", async () => {
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: true, memberships: [] },
        error: null,
      },
      get_my_partner_application: { data: { application_id: null }, error: null },
    });
    expect((await obterContextoConta()).tipo).toBe("sem_contexto_parceiro");
  });

  it("erro da solicitacao canonica nega (semantica M1 intacta)", async () => {
    responder({
      get_my_partner_application: { data: null, error: { message: "boom" } },
    });
    expect((await obterContextoConta()).tipo).toBe("erro");
  });

  it("PROPRIEDADE: nenhuma falha do contexto duravel produz autorizacao", async () => {
    const falhas: unknown[] = [
      { data: null, error: { message: "boom" } },
      { data: null, error: null },
      { data: { ok: false }, error: null },
      { data: { ok: true, authorized: true, memberships: [] }, error: null },
      {
        data: {
          ok: true,
          authorized: true,
          memberships: [{ ...VINCULO, member_status: "revoked" }],
        },
        error: null,
      },
    ];
    for (const falha of falhas) {
      responder({
        get_my_partner_context: falha,
        get_my_partner_application: {
          data: { application_id: "a1", account_kind: "provisional" },
          error: null,
        },
      });
      expect((await obterContextoConta()).tipo).not.toBe("parceiro_autorizado");
    }
  });
});

describe("R3 — PortalGuard permanece fail-closed", () => {
  it("vinculo duravel ativo LIBERA o portal", async () => {
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: true, memberships: [VINCULO] },
        error: null,
      },
      get_my_partner_application: {
        data: { application_id: "a1", account_kind: "provisional" },
        error: null,
      },
    });
    montarGuard();
    await waitFor(() => expect(screen.getByTestId("portal")).toBeDefined());
  });

  it("sem vinculo e sem solicitacao NEGA", async () => {
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: false, memberships: [] },
        error: null,
      },
      get_my_partner_application: { data: {}, error: null },
    });
    montarGuard();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });

  it("erro do contexto NEGA o portal", async () => {
    responder({
      get_my_partner_context: { data: null, error: { message: "boom" } },
      get_my_partner_application: { data: { application_id: null }, error: null },
    });
    montarGuard();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByTestId("portal")).toBeNull();
  });
});

describe("R3 — PortalDashboard nao consulta tabela obsoleta", () => {
  it("usa a RPC de contexto e NUNCA chama .from(site_partner_members)", async () => {
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: true, memberships: [VINCULO] },
        error: null,
      },
    });
    render(
      <MemoryRouter>
        <PortalDashboard />
      </MemoryRouter>
    );
    await waitFor(() =>
      expect(screen.getByText("Parceiro Canonico")).toBeDefined()
    );
    // REGRESSÃO: nenhuma consulta direta a tabela foi feita.
    expect(fromMock).not.toHaveBeenCalled();
    const nomes = rpcMock.mock.calls.map((c) => c[0]);
    expect(nomes).toContain("get_my_partner_context");
  });

  it("erro do contexto nao inventa vinculo no painel", async () => {
    responder({
      get_my_partner_context: { data: null, error: { message: "boom" } },
    });
    render(
      <MemoryRouter>
        <PortalDashboard />
      </MemoryRouter>
    );
    await waitFor(() => expect(rpcMock).toHaveBeenCalled());
    expect(fromMock).not.toHaveBeenCalled();
    expect(screen.queryByText("Parceiro Canonico")).toBeNull();
  });
});
