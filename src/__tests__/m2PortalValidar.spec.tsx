import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * R12 — PortalValidar do lado Site.
 *
 * Provas centrais:
 *   1. sem autorização de validador, nenhum formulário é oferecido;
 *   2. erro NUNCA vira permissão nem "validado";
 *   3. encaminhar NÃO afirma que o benefício foi validado ou consumido —
 *      o desfecho é do App (BLOCKED_APP_REPOSITORY).
 */
const rpcMock = vi.fn();

vi.mock("../lib/supabase", () => {
  const auth = {
    getSession: vi.fn(async () => ({
      data: { session: { access_token: "t", user: { id: "u1" } } },
    })),
    onAuthStateChange: vi.fn(() => ({
      data: { subscription: { unsubscribe: vi.fn() } },
    })),
    signOut: vi.fn(async () => ({})),
  };
  return {
    supabase: { auth, rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
    supabaseConfigurado: true,
  };
});

import PortalValidar from "../pages/portal/PortalValidar";

const VINCULO = {
  company_id: "c1",
  trade_name: "Rede Um",
  company_status: "active",
  member_id: "m1",
  role: "partner_owner",
  member_status: "active",
};
const UNIDADE = { unit_id: "u1", name: "Matriz", branch_bridge_id: "b1" };

function responder(mapa: Record<string, unknown>) {
  rpcMock.mockImplementation(async (nome: string) =>
    nome in mapa ? mapa[nome] : { data: null, error: { message: "inesperada" } }
  );
}

const comVinculo = {
  data: { ok: true, authorized: true, memberships: [VINCULO] },
  error: null,
};

beforeEach(() => {
  rpcMock.mockReset();
  localStorage.clear();
});
afterEach(() => cleanup());

function montar(qt = "") {
  return render(
    <MemoryRouter initialEntries={[qt ? `/portal/validar?qt=${qt}` : "/portal/validar"]}>
      <PortalValidar />
    </MemoryRouter>
  );
}

describe("R12 — autorização de validador na tela", () => {
  it("validador elegível recebe o formulário com suas unidades", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: {
        data: { ok: true, eligible: true, role: "partner_owner", units: [UNIDADE] },
        error: null,
      },
    });
    montar();
    await waitFor(() =>
      expect(screen.getByText(/responsável autorizado/i)).toBeDefined()
    );
    expect(screen.getByText("Matriz")).toBeDefined();
  });

  it("inelegível NAO recebe formulário", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: {
        data: { ok: true, eligible: false },
        error: null,
      },
    });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.getByText(/não está autorizado a validar/i)).toBeDefined();
    expect(screen.queryByText(/encaminhar validação/i)).toBeNull();
  });

  it("erro no contexto de validador NAO oferece validação", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: { data: null, error: { message: "boom" } },
    });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(screen.queryByText(/encaminhar validação/i)).toBeNull();
  });

  it("conta sem rede parceira NAO valida", async () => {
    responder({
      get_my_partner_context: {
        data: { ok: true, authorized: false, memberships: [] },
        error: null,
      },
    });
    montar();
    await waitFor(() =>
      expect(screen.getByText(/não possui rede parceira ativa/i)).toBeDefined()
    );
  });

  it("preserva o código qt recebido do QR", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: {
        data: { ok: true, eligible: true, role: "partner_manager", units: [UNIDADE] },
        error: null,
      },
    });
    montar("ABC123");
    await waitFor(() => expect(screen.getByText(/gestor autorizado/i)).toBeDefined());
    expect(screen.getByDisplayValue("ABC123")).toBeDefined();
  });
});

describe("R12 — encaminhar não é validar", () => {
  it("resposta de encaminhamento declara que NAO concluiu", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: {
        data: { ok: true, eligible: true, role: "partner_owner", units: [UNIDADE] },
        error: null,
      },
      prepare_benefit_validation: {
        data: {
          ok: true,
          allowed: true,
          attempt_id: "a1",
          app_gateway: "BLOCKED_APP_REPOSITORY",
        },
        error: null,
      },
    });
    const { container } = montar("TOKEN1");
    await waitFor(() => expect(screen.getByText(/responsável autorizado/i)).toBeDefined());
    (container.querySelector("form") as HTMLFormElement).requestSubmit();

    await waitFor(() =>
      expect(screen.getByText(/ainda NÃO concluído/i)).toBeDefined()
    );
    expect(screen.getByText(/nenhum benefício foi consumido/i)).toBeDefined();
    // Em nenhum momento a tela afirma sucesso de validação.
    expect(screen.queryByText(/benefício validado/i)).toBeNull();
    expect(screen.queryByText(/validação concluída/i)).toBeNull();
  });

  it("negativa do backend aparece como negada", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: {
        data: { ok: true, eligible: true, role: "partner_manager", units: [UNIDADE] },
        error: null,
      },
      prepare_benefit_validation: {
        data: { ok: true, allowed: false, reason: "validation_denied" },
        error: null,
      },
    });
    const { container } = montar("TOKEN2");
    await waitFor(() => expect(screen.getByText(/gestor autorizado/i)).toBeDefined());
    (container.querySelector("form") as HTMLFormElement).requestSubmit();
    await waitFor(() =>
      expect(screen.getByText(/validação negada para esta unidade/i)).toBeDefined()
    );
  });

  it("erro no encaminhamento NAO afirma conclusão", async () => {
    responder({
      get_my_partner_context: comVinculo,
      get_my_validator_context: {
        data: { ok: true, eligible: true, role: "partner_owner", units: [UNIDADE] },
        error: null,
      },
      prepare_benefit_validation: { data: null, error: { message: "boom" } },
    });
    const { container } = montar("TOKEN3");
    await waitFor(() => expect(screen.getByText(/responsável autorizado/i)).toBeDefined());
    (container.querySelector("form") as HTMLFormElement).requestSubmit();
    await waitFor(() =>
      expect(
        screen.getByText(/nenhuma validação foi registrada como concluída/i)
      ).toBeDefined()
    );
  });
});
