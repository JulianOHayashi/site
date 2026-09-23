import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, fireEvent } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * R12 — PortalValidar do lado Site.
 *
 * Provas centrais:
 *   1. sem autorização de validador, nenhum formulário é oferecido;
 *   2. erro NUNCA vira permissão nem "validado";
 *   3. enviar NÃO afirma que o benefício foi validado ou consumido — o
 *      desfecho é do App, e só o usuário confirma lá.
 *
 * A tela migrou do caminho legado (`prepare_benefit_validation`) para o
 * código manual do balcão, que vai ao gateway do App. As asserções sobre a
 * RPC legada e sobre BLOCKED_APP_REPOSITORY saíram com ela; as de
 * AUTORIZAÇÃO ficaram todas.
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
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => ({
      ok: true,
      status: "request_created",
      request_correlation_id: "corr-1",
      app_status: "awaiting_user_confirmation",
    }),
  });
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const fetchMock = vi.fn();

function montar() {
  return render(
    <MemoryRouter initialEntries={["/portal/validar"]}>
      <PortalValidar />
    </MemoryRouter>
  );
}

const elegivel = {
  get_my_partner_context: comVinculo,
  get_my_validator_context: {
    data: { ok: true, eligible: true, role: "partner_owner", units: [UNIDADE] },
    error: null,
  },
};

/** Preenche código e confirmação do documento, o mínimo para submeter. */
async function preencher(codigo = "ABCD-7K2M") {
  const campo = await screen.findByLabelText(/Código do benefício/i);
  fireEvent.change(campo, { target: { value: codigo } });
  fireEvent.click(screen.getByRole("checkbox"));
  return campo as HTMLInputElement;
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

  it("o campo de código aparece e formata como XXXX-XXXX", async () => {
    responder(elegivel);
    montar();
    const campo = (await screen.findByLabelText(
      /Código do benefício/i
    )) as HTMLInputElement;
    fireEvent.change(campo, { target: { value: "abcd7k2m" } });
    expect(campo.value).toBe("ABCD-7K2M");
    // Lixo e excesso são descartados na exibição.
    fireEvent.change(campo, { target: { value: "ab!cd 7k2m zzz" } });
    expect(campo.value).toBe("ABCD-7K2M");
  });

  it("NAO ha preenchimento por parametro de URL", async () => {
    responder(elegivel);
    render(
      <MemoryRouter initialEntries={["/portal/validar?qt=ABCD7K2M"]}>
        <PortalValidar />
      </MemoryRouter>
    );
    const campo = (await screen.findByLabelText(
      /Código do benefício/i
    )) as HTMLInputElement;
    // Um código de benefício não sobrevive no histórico do navegador.
    expect(campo.value).toBe("");
    expect(screen.queryByText("ABCD7K2M")).toBeNull();
  });

  it("a unidade selecionada e preservada e enviada", async () => {
    responder(elegivel);
    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const corpo = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    expect(corpo.unit_id).toBe("u1");
  });
});

describe("R12 — enviar não é validar", () => {
  it("sem conferencia do documento o botao fica desabilitado", async () => {
    responder(elegivel);
    montar();
    const campo = await screen.findByLabelText(/Código do benefício/i);
    fireEvent.change(campo, { target: { value: "ABCD7K2M" } });
    const botao = screen.getByRole("button", { name: /Enviar solicitação/i });
    expect((botao as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByRole("checkbox"));
    expect((botao as HTMLButtonElement).disabled).toBe(false);
  });

  it("codigo incompleto mantem o envio bloqueado", async () => {
    responder(elegivel);
    montar();
    const campo = await screen.findByLabelText(/Código do benefício/i);
    fireEvent.change(campo, { target: { value: "ABC" } });
    fireEvent.click(screen.getByRole("checkbox"));
    expect(
      (screen.getByRole("button", { name: /Enviar solicitação/i }) as HTMLButtonElement)
        .disabled
    ).toBe(true);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("submete ao endpoint do Site, com o codigo canonico e nada de autoridade", async () => {
    responder(elegivel);
    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(fetchMock.mock.calls[0][0]).toBe("/api/benefit-usage/code/request");
    const corpo = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    expect(Object.keys(corpo).sort()).toEqual(
      ["display_code", "unit_id", "physical_photo_id_checked"].sort()
    );
    expect(corpo.display_code).toBe("ABCD7K2M");
    expect(corpo.physical_photo_id_checked).toBe(true);
  });

  it("sucesso diz SOLICITACAO ENVIADA, nunca benefício validado", async () => {
    responder(elegivel);
    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));

    await screen.findByText(/Solicitação enviada ao aplicativo/i);
    expect(
      screen.getByText(/confirmar ou recusar no aplicativo BDFlow/i)
    ).toBeDefined();
    expect(screen.getByText(/só é consumido depois dessa confirmação/i)).toBeDefined();
    // As três afirmações proibidas neste momento.
    expect(screen.queryByText(/benefício validado/i)).toBeNull();
    expect(screen.queryByText(/benefício consumido/i)).toBeNull();
    expect(screen.queryByText(/validação concluída/i)).toBeNull();
  });

  it("falha do gateway NUNCA vira sucesso", async () => {
    responder(elegivel);
    fetchMock.mockResolvedValue({
      ok: false,
      json: async () => ({ ok: false, code: "request_denied" }),
    });
    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));
    await screen.findByText(/aplicativo recusou esta solicitação/i);
    expect(screen.queryByText(/Solicitação enviada ao aplicativo/i)).toBeNull();
  });

  it("nao autorizado aparece como recusa, sem oferecer conclusao", async () => {
    responder(elegivel);
    fetchMock.mockResolvedValue({
      ok: false,
      json: async () => ({ ok: false, code: "not_authorized" }),
    });
    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));
    await screen.findByText(/não está autorizado a validar nesta unidade/i);
  });
});