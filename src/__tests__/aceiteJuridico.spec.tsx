import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

const rpcMock = vi.fn();
const fetchMock = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      getSession: vi.fn(async () => ({ data: { session: null } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
      signOut: vi.fn(async () => ({ error: null })),
    },
  },
  supabaseConfigurado: true,
}));

import ParceirosCadastro from "../pages/parceiros/ParceirosCadastro";

const montar = () => render(<MemoryRouter><ParceirosCadastro /></MemoryRouter>);

async function preencher() {
  fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "12.345.678/0001-95" } });
  fireEvent.change(screen.getByLabelText(/razão social/i), { target: { value: "Super Teste LTDA" } });
  fireEvent.change(screen.getByLabelText(/e-mail de contato/i), { target: { value: "a@b.com.br" } });
  fireEvent.change(screen.getByLabelText(/^cidade/i), { target: { value: "Vila Velha" } });
  fireEvent.change(screen.getByLabelText(/nome completo/i), { target: { value: "Maria Souza" } });
  fireEvent.change(screen.getByLabelText(/^cpf/i), { target: { value: "529.982.247-25" } });
  fireEvent.change(screen.getByLabelText(/cargo \/ função do responsável/i), {
    target: { value: "Sócia-administradora" },
  });
}

beforeEach(() => {
  rpcMock.mockReset();
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  localStorage.clear();
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

describe("aceites jurídicos depois do cadastro", () => {
  it("cadastro inicial não exibe checkbox jurídico", () => {
    montar();
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    expect(
      screen.getByText(/documentos jurídicos de onboarding serão apresentados depois/i)
    ).toBeDefined();
    expect(screen.getByRole("button", { name: /enviar solicitação/i })).toBeDefined();
  });

  it("cadastro não depende de get_partner_application_terms", async () => {
    montar();
    await preencher();
    expect(rpcMock).not.toHaveBeenCalledWith("get_partner_application_terms", expect.anything());
  });

  it("envia conjunto vazio de aceites no pré-auth", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        ok: true,
        application_id: "app-1",
        status: "pending_email_verification",
      }),
    });

    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/public/partner-application/create");

    const payload = JSON.parse(String(init.body)) as Record<string, unknown>;
    expect(payload.acceptances).toEqual([]);
  });

  it("depois do envio informa que o próximo passo é confirmar o e-mail", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        ok: true,
        application_id: "app-1",
        status: "pending_email_verification",
      }),
    });

    montar();
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));

    expect(await screen.findByRole("heading", { name: /confirme seu e-mail/i })).toBeDefined();
  });
});
