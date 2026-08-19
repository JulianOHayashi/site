import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * B10 — substituição de representante.
 *
 * O botão anterior enviava {full_name:"", cpf:"", email:""} e eu havia
 * transformado a ausência do formulário em texto explicativo na tela. Estes
 * testes provam que agora existe coleta real e que nada é enviado sem ela.
 */
const rpcMock = vi.fn();
const fromMock = vi.fn();

const APP = { id: "app-1", legal_name: "Super Teste LTDA", trade_name: null,
  cnpj: "12345678000195", contact_email: "contato@teste.com.br", city: "Vila Velha", uf: "ES",
  status: "under_review", company_review_status: "pending", authority_review_status: "pending",
  reconsideration_count: 0, decision_reason: null };
const REPS = [{ id: "rep-1", application_id: "app-1", full_name: "Maria Souza",
  email: "maria@teste.com.br", authority_status: "pending", is_current: true }];
const LISTA = [{ application_id: "app-1", cnpj: "12345678000195", legal_name: "Super Teste LTDA",
  city: "Vila Velha", uf: "ES", status: "under_review", company_review_status: "pending",
  authority_review_status: "pending", created_at: "2026-08-01T10:00:00Z",
  representative: { id: "rep-1", full_name: "Maria Souza", authority_status: "pending" } }];

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    from: (t: string) => fromMock(t),
    storage: { from: () => ({ createSignedUrl: vi.fn(async () => ({ data: { signedUrl: "https://x" }, error: null })) }) },
    auth: {
      getSession: vi.fn(async () => ({ data: { session: { access_token: "t", user: { id: "adm" } } } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
    },
  },
  supabaseConfigurado: true,
}));

import AdminSolicitacoes from "../pages/admin/AdminSolicitacoes";

function enc(dados: unknown, single = false) {
  const o: Record<string, unknown> = {};
  o.select = () => o; o.eq = () => o;
  o.order = async () => ({ data: dados, error: null });
  o.maybeSingle = async () => ({ data: single ? dados : null, error: null });
  return o;
}

const substituicoes = () => rpcMock.mock.calls.filter((c) => c[0] === "admin_replace_partner_representative");

beforeEach(() => {
  rpcMock.mockReset(); fromMock.mockReset();
  rpcMock.mockImplementation(async (nome: string) => {
    if (nome === "admin_list_partner_applications") return { data: { ok: true, items: LISTA }, error: null };
    return { data: { ok: true, representative_id: "rep-2" }, error: null };
  });
  fromMock.mockImplementation((t: string) => {
    if (t === "partner_applications") return enc(APP, true);
    if (t === "partner_application_representatives") return enc(REPS);
    return enc([]);
  });
});
afterEach(() => cleanup());

async function abrirFormulario() {
  render(<MemoryRouter><AdminSolicitacoes /></MemoryRouter>);
  await waitFor(() => expect(screen.getByRole("button", { name: /abrir solicitação/i })).toBeDefined());
  fireEvent.click(screen.getByRole("button", { name: /abrir solicitação/i }));
  await waitFor(() => expect(screen.getByRole("button", { name: /substituir representante/i })).toBeDefined());
  fireEvent.click(screen.getByRole("button", { name: /substituir representante/i }));
  await waitFor(() => expect(screen.getByLabelText(/nome completo/i)).toBeDefined());
}

function preencher(dados: Record<string, string>) {
  for (const [rotulo, valor] of Object.entries(dados)) {
    fireEvent.change(screen.getByLabelText(new RegExp(rotulo, "i")), { target: { value: valor } });
  }
}

describe("B10 — formulario valido", () => {
  it("envia o payload exato e normalizado", async () => {
    await abrirFormulario();
    preencher({
      "nome completo": "Carlos Prado",
      "^cpf": "529.982.247-25",
      "e-mail": "carlos@Teste.com.BR",
      "telefone": "(27) 99999-8888",
      "cargo": "Diretor",
    });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));

    await waitFor(() => expect(substituicoes().length).toBe(1));
    const args = substituicoes()[0][1] as { p_application_id: string; p_payload: Record<string, string> };
    expect(args.p_application_id).toBe("app-1");
    expect(args.p_payload).toEqual({
      full_name: "Carlos Prado",
      cpf: "52998224725",
      email: "carlos@teste.com.br",
      phone: "27999998888",
      role_title: "Diretor",
    });
  });

  it("campos opcionais vazios nao viram string vazia", async () => {
    await abrirFormulario();
    preencher({
      "nome completo": "Carlos Prado",
      "^cpf": "52998224725",
      "e-mail": "carlos@teste.com.br",
    });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(substituicoes().length).toBe(1));
    const p = (substituicoes()[0][1] as { p_payload: Record<string, unknown> }).p_payload;
    expect(p.phone).toBeUndefined();
    expect(p.role_title).toBeUndefined();
  });
});

describe("B10 — formulario invalido nao chama a RPC", () => {
  it("CPF com DV errado", async () => {
    await abrirFormulario();
    preencher({ "nome completo": "Carlos Prado", "^cpf": "12345678900", "e-mail": "c@t.com.br" });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(screen.getByText(/informe um cpf válido/i)).toBeDefined());
    expect(substituicoes().length).toBe(0);
  });

  it("e-mail invalido", async () => {
    await abrirFormulario();
    preencher({ "nome completo": "Carlos Prado", "^cpf": "52998224725", "e-mail": "nao-e-email" });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(screen.getByText(/informe um e-mail válido/i)).toBeDefined());
    expect(substituicoes().length).toBe(0);
  });

  it("nome ausente", async () => {
    await abrirFormulario();
    preencher({ "^cpf": "52998224725", "e-mail": "c@t.com.br" });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(screen.getByText(/informe o nome completo/i)).toBeDefined());
    expect(substituicoes().length).toBe(0);
  });

  it("formulario vazio nao envia nada (o botao antigo enviava campos vazios)", async () => {
    await abrirFormulario();
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(screen.getByText(/informe o nome completo/i)).toBeDefined());
    expect(substituicoes().length).toBe(0);
  });
});

describe("B10 — recusa do backend", () => {
  it("mostra erro seguro e nao finge sucesso", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "admin_list_partner_applications") return { data: { ok: true, items: LISTA }, error: null };
      if (nome === "admin_replace_partner_representative")
        return { data: { ok: false, reason: "not_reviewable" }, error: null };
      return { data: { ok: true }, error: null };
    });
    await abrirFormulario();
    preencher({ "nome completo": "Carlos Prado", "^cpf": "52998224725", "e-mail": "c@t.com.br" });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(screen.getByText(/não está em análise/i)).toBeDefined());
    // O representante corrente segue o que o servidor diz; nada foi trocado
    // na tela por conta da tentativa recusada.
    expect(screen.getAllByText(/Maria Souza/).length).toBeGreaterThan(0);
    expect(screen.queryByText(/Carlos Prado/)).toBeNull();
  });

  it("erro cru do banco nao chega a tela", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "admin_list_partner_applications") return { data: { ok: true, items: LISTA }, error: null };
      return { data: null, error: { message: 'violates check constraint "par_cpf_dv"' } };
    });
    await abrirFormulario();
    preencher({ "nome completo": "Carlos Prado", "^cpf": "52998224725", "e-mail": "c@t.com.br" });
    fireEvent.click(screen.getByRole("button", { name: /^substituir$/i }));
    await waitFor(() => expect(screen.getByText(/não foi possível concluir/i)).toBeDefined());
    const txt = document.body.textContent ?? "";
    expect(txt).not.toContain("check constraint");
    expect(txt).not.toContain("par_cpf_dv");
  });
});
