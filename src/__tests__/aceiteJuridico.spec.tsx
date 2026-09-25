import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * B4 frontend — aceite atado ao ID exato do documento vigente.
 *
 * A prova central: estado de aceite antigo + documento novo carregado
 * NUNCA vira aceite implícito.
 */
const rpcMock = vi.fn();
const fetchMock = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      getSession: vi.fn(async () => ({ data: { session: null } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
      signUp: vi.fn(),
      signInWithPassword: vi.fn(),
    },
  },
  supabaseConfigurado: true,
}));

import ParceirosCadastro from "../pages/parceiros/ParceirosCadastro";

const DOC_A = { legal_document_id: "aaaa-1", doc_type: "truthfulness_declaration",
  version: "v1", title: "Declaração de veracidade", content: "texto", content_url: null };
const DOC_B = { legal_document_id: "bbbb-1", doc_type: "document_analysis_authorization",
  version: "v1", title: "Autorização de análise", content: "texto", content_url: null };
const DOC_A_V2 = { ...DOC_A, legal_document_id: "aaaa-2", version: "v2" };

function termosOk(docs: unknown[]) {
  return { data: { ok: true, documents: docs }, error: null };
}

const montar = () => render(<MemoryRouter><ParceirosCadastro /></MemoryRouter>);

async function preencher() {
  fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "12.345.678/0001-95" } });
  fireEvent.change(screen.getByLabelText(/razão social/i), { target: { value: "Super Teste LTDA" } });
  fireEvent.change(screen.getByLabelText(/e-mail de contato/i), { target: { value: "a@b.com.br" } });
  fireEvent.change(screen.getByLabelText(/^cidade/i), { target: { value: "Vila Velha" } });
  fireEvent.change(screen.getByLabelText(/nome completo/i), { target: { value: "Maria Souza" } });
  fireEvent.change(screen.getByLabelText(/^cpf/i), { target: { value: "529.982.247-25" } });
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

describe("B4 — estados de carregamento e erro", () => {
  it("durante o carregamento, o envio fica bloqueado", async () => {
    rpcMock.mockImplementation(() => new Promise(() => {}));
    montar();
    await waitFor(() => expect(screen.getByText(/carregando os termos/i)).toBeDefined());
    const botao = screen.getByRole("button", { name: /enviar solicitação/i }) as HTMLButtonElement;
    expect(botao.disabled).toBe(true);
    expect(screen.queryAllByRole("checkbox").length).toBe(0);
  });

  it("com erro de carga, o envio fica bloqueado e ha como tentar de novo", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    const botao = screen.getByRole("button", { name: /enviar solicitação/i }) as HTMLButtonElement;
    expect(botao.disabled).toBe(true);
    expect(screen.queryAllByRole("checkbox").length).toBe(0);
    expect(screen.getByRole("button", { name: /tentar novamente/i })).toBeDefined();
  });

  it("carregados os termos, cada documento tem aceite proprio", async () => {
    rpcMock.mockImplementation(async (nome: string) =>
      nome === "get_partner_application_terms" ? termosOk([DOC_A, DOC_B]) : { data: { ok: true }, error: null }
    );
    montar();
    await waitFor(() => expect(screen.getAllByRole("checkbox").length).toBe(2));
    expect(screen.getByLabelText(/aceito: declaração de veracidade/i)).toBeDefined();
    expect(screen.getByLabelText(/aceito: autorização de análise/i)).toBeDefined();
    const botao = screen.getByRole("button", { name: /enviar solicitação/i }) as HTMLButtonElement;
    expect(botao.disabled).toBe(false);
  });
});

describe("B4 — aceite pré-Auth atado ao ID", () => {
  it("nao chama a RPC quando os termos falham ao carregar", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    await preencher();
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(fetchMock).not.toHaveBeenCalled());
  });

  it("exige aceite de TODOS os documentos", async () => {
    rpcMock.mockImplementation(async (nome: string) =>
      nome === "get_partner_application_terms" ? termosOk([DOC_A, DOC_B]) : { data: { ok: true }, error: null }
    );
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        ok: true,
        application_id: "app-1",
        status: "pending_email_verification",
      }),
    });
    montar();
    await waitFor(() => expect(screen.getByLabelText(/aceito: declaração/i)).toBeDefined());
    await preencher();
    fireEvent.click(screen.getByLabelText(/aceito: declaração/i));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(screen.getByText(/aceitar todos os termos/i)).toBeDefined());
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("envia SOMENTE os ids aceitos, sem versao nem hash", async () => {
    rpcMock.mockImplementation(async (nome: string) =>
      nome === "get_partner_application_terms"
        ? termosOk([DOC_A, DOC_B])
        : { data: { ok: true, application_id: "app-1", status: "pending_email_verification" }, error: null }
    );
    montar();
    await waitFor(() => expect(screen.getByLabelText(/aceito: declaração/i)).toBeDefined());
    await preencher();
    fireEvent.click(screen.getByLabelText(/aceito: declaração/i));
    fireEvent.click(screen.getByLabelText(/aceito: autorização/i));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/public/partner-application/create");
    const payload = JSON.parse(String(init.body)) as Record<string, unknown>;
    expect(payload.acceptances).toEqual([
      { legal_document_id: "aaaa-1" },
      { legal_document_id: "bbbb-1" },
    ]);
    const bruto = JSON.stringify(payload.acceptances);
    expect(bruto).not.toContain("version");
    expect(bruto).not.toContain("content_hash");
  });

  it("acceptance_stale recarrega os termos e DESCARTA o aceite anterior", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ ok: false, reason: "acceptance_stale" }),
    });
    let rodada = 0;
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_partner_application_terms") {
        rodada += 1;
        return termosOk(rodada === 1 ? [DOC_A, DOC_B] : [DOC_A_V2, DOC_B]);
      }
      return { data: { ok: false, reason: "acceptance_stale" }, error: null };
    });
    montar();
    await waitFor(() => expect(screen.getByLabelText(/aceito: declaração/i)).toBeDefined());
    await preencher();
    fireEvent.click(screen.getByLabelText(/aceito: declaração/i));
    fireEvent.click(screen.getByLabelText(/aceito: autorização/i));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));

    await waitFor(() => expect(screen.getByText(/termos foram atualizados/i)).toBeDefined());
    // Versão nova exibida e NENHUM checkbox marcado: o aceite antigo não
    // sobreviveu à troca de documento.
    await waitFor(() => expect(screen.getByText(/versão v2/i)).toBeDefined());
    for (const cb of screen.getAllByRole("checkbox")) {
      expect((cb as HTMLInputElement).checked).toBe(false);
    }
  });

  it("apos recarregar, um novo envio leva o ID NOVO", async () => {
    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ ok: false, reason: "acceptance_stale" }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          ok: true,
          application_id: "app-1",
          status: "pending_email_verification",
        }),
      });
    let rodada = 0;
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_partner_application_terms") {
        rodada += 1;
        return termosOk(rodada === 1 ? [DOC_A, DOC_B] : [DOC_A_V2, DOC_B]);
      }
      if (rodada === 1) return { data: { ok: false, reason: "acceptance_stale" }, error: null };
      return { data: { ok: true, application_id: "app-1", status: "pending_email_verification" }, error: null };
    });
    montar();
    await waitFor(() => expect(screen.getByLabelText(/aceito: declaração/i)).toBeDefined());
    await preencher();
    fireEvent.click(screen.getByLabelText(/aceito: declaração/i));
    fireEvent.click(screen.getByLabelText(/aceito: autorização/i));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(screen.getByText(/versão v2/i)).toBeDefined());

    fireEvent.click(screen.getByLabelText(/aceito: declaração/i));
    fireEvent.click(screen.getByLabelText(/aceito: autorização/i));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    const [, init] = fetchMock.mock.calls[1] as [string, RequestInit];
    const payload = JSON.parse(String(init.body)) as Record<string, unknown>;
    expect(payload.acceptances).toEqual([
      { legal_document_id: "aaaa-2" },
      { legal_document_id: "bbbb-1" },
    ]);
  });
});
