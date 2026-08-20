import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * B5 frontend — contrato de upload (M1-C3).
 *
 * A ordem importa: caminho novo → upload → registro.
 *
 * A limpeza pelo cliente foi REMOVIDA: o DELETE direto do solicitante era
 * uma superfície de mutação concorrente contra a RPC de registro. Órfão
 * eventual é aceito no M1.
 */
const rpcMock = vi.fn();
const fromMock = vi.fn();
const uploadMock = vi.fn();
const removeMock = vi.fn(async () => ({ data: null, error: null }));
const ordem: string[] = [];

const SOL = { application_id: "app-1", status: "changes_requested",
  company_review_status: "pending", authority_review_status: "pending",
  account_kind: "provisional", cnpj: "12345678000195", legal_name: "Super Teste LTDA",
  city: "Vila Velha", uf: "ES", created_at: "2026-08-01T10:00:00Z" };

const DOC_ATUAL = { id: "doc-2", application_id: "app-1", doc_type: "contrato_social",
  storage_bucket: "partner-application-docs", storage_path: "app-1/contrato_social/ATUAL.pdf",
  original_filename: "contrato-v2.pdf", mime_type: "application/pdf", byte_size: 10,
  review_status: "accepted", review_notes: null, created_at: "2026-08-03T10:00:00Z",
  superseded_at: null, superseded_by_document_id: null };

const DOC_HIST = { ...DOC_ATUAL, id: "doc-1", storage_path: "app-1/contrato_social/HISTORICO.pdf",
  original_filename: "contrato-v1.pdf", review_status: "rejected",
  superseded_at: "2026-08-03T10:00:00Z", superseded_by_document_id: "doc-2" };

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    from: (t: string) => fromMock(t),
    storage: {
      from: () => ({
        upload: (...a: unknown[]) => { ordem.push("upload"); return uploadMock(...(a as [])); },
        remove: (...a: unknown[]) => { ordem.push("remove"); return removeMock(...(a as [])); },
        createSignedUrl: vi.fn(async () => ({ data: { signedUrl: "https://x" }, error: null })),
      }),
    },
    auth: {
      getSession: vi.fn(async () => ({ data: { session: { access_token: "t", user: { id: "u1" } } } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
    },
  },
  supabaseConfigurado: true,
}));

import SolicitacaoStatus from "../pages/parceiros/SolicitacaoStatus";

function tabela(dados: unknown[]) {
  const o: Record<string, unknown> = {};
  o.select = () => o; o.eq = () => o;
  o.order = async () => ({ data: dados, error: null });
  return o;
}

const registros = () => rpcMock.mock.calls.filter((c) => c[0] === "register_partner_application_document");

beforeEach(() => {
  rpcMock.mockReset(); fromMock.mockReset(); uploadMock.mockReset(); removeMock.mockClear();
  ordem.length = 0; localStorage.clear();
  uploadMock.mockResolvedValue({ data: { path: "p" }, error: null });
  rpcMock.mockImplementation(async (nome: string) => {
    if (nome === "get_my_partner_application") return { data: SOL, error: null };
    return { data: { ok: true, document_id: "novo", supersedes: "doc-2" }, error: null };
  });
  fromMock.mockImplementation((t: string) =>
    tabela(t === "partner_application_documents" ? [DOC_ATUAL, DOC_HIST] : [])
  );
});
afterEach(() => cleanup());

async function enviarArquivo() {
  render(<MemoryRouter><SolicitacaoStatus /></MemoryRouter>);
  await waitFor(() => expect(screen.getByLabelText(/arquivo/i)).toBeDefined());
  fireEvent.change(screen.getByLabelText(/arquivo/i), {
    target: { files: [new File(["x"], "novo.pdf", { type: "application/pdf" })] },
  });
  fireEvent.click(screen.getByRole("button", { name: /enviar documento/i }));
}

describe("A — sucesso", () => {
  it("upload vem ANTES do registro, com o mesmo caminho unico", async () => {
    await enviarArquivo();
    await waitFor(() => expect(registros().length).toBe(1));
    expect(ordem[0]).toBe("upload");
    const caminhoUpload = uploadMock.mock.calls[0][0] as string;
    const caminhoRegistro = (registros()[0][1] as { p_storage_path: string }).p_storage_path;
    expect(caminhoRegistro).toBe(caminhoUpload);
    expect(caminhoUpload.startsWith("app-1/contrato_social/")).toBe(true);
    // Nunca o caminho de um documento já registrado.
    expect(caminhoUpload).not.toBe(DOC_ATUAL.storage_path);
    expect(caminhoUpload).not.toBe(DOC_HIST.storage_path);
  });
});

describe("B — falha no upload", () => {
  it("nao registra metadado nem apaga nada", async () => {
    uploadMock.mockResolvedValue({ data: null, error: { message: "falhou" } });
    await enviarArquivo();
    await waitFor(() => expect(screen.getByText(/não foi possível enviar o arquivo/i)).toBeDefined());
    expect(registros().length).toBe(0);
    expect(removeMock).not.toHaveBeenCalled();
  });
});

describe("C — falha no registro (M1-C3: sem limpeza pelo cliente)", () => {
  // O comportamento anterior — limpar o caminho da tentativa — foi REMOVIDO.
  // O DELETE direto do solicitante criava uma corrida contra a própria RPC de
  // registro. O objeto órfão fica no bucket; não tem metadado, não aparece na
  // UI e não é reaproveitável.
  it("NAO chama storage.remove e mostra erro seguro", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_my_partner_application") return { data: SOL, error: null };
      return { data: { ok: false, reason: "storage_object_not_found" }, error: null };
    });
    await enviarArquivo();
    await waitFor(() => expect(screen.getByText(/arquivo não foi encontrado/i)).toBeDefined());
    expect(removeMock).not.toHaveBeenCalled();
    expect(ordem).toEqual(["upload"]);
  });

  it("NAO apaga o documento corrente nem o historico", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_my_partner_application") return { data: SOL, error: null };
      return { data: { ok: false, reason: "invalid_document" }, error: null };
    });
    await enviarArquivo();
    await waitFor(() => expect(screen.getByText(/documento inválido/i)).toBeDefined());
    expect(removeMock).not.toHaveBeenCalled();
    // Corrente e histórico seguem exibidos.
    expect(screen.getByText(/contrato-v2\.pdf/)).toBeDefined();
    expect(screen.getByText(/contrato-v1\.pdf/)).toBeDefined();
  });
});

describe("D — histórico separado do corrente", () => {
  it("distingue versao atual de versoes anteriores", async () => {
    render(<MemoryRouter><SolicitacaoStatus /></MemoryRouter>);
    await waitFor(() => expect(screen.getByText(/contrato-v2\.pdf/)).toBeDefined());
    expect(screen.getByText(/atuais/i)).toBeDefined();
    expect(screen.getByText(/versões anteriores/i)).toBeDefined();
    expect(screen.getByText(/substituído/i)).toBeDefined();
    // Nenhum controle de substituir/apagar em item histórico.
    expect(screen.queryByRole("button", { name: /remover/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /substituir documento/i })).toBeNull();
  });
});

describe("E — reenvio", () => {
  it("cada tentativa gera um caminho diferente", async () => {
    await enviarArquivo();
    await waitFor(() => expect(uploadMock).toHaveBeenCalledTimes(1));
    cleanup();
    await enviarArquivo();
    await waitFor(() => expect(uploadMock).toHaveBeenCalledTimes(2));
    const p1 = uploadMock.mock.calls[0][0] as string;
    const p2 = uploadMock.mock.calls[1][0] as string;
    expect(p1).not.toBe(p2);
    expect(p2).not.toBe(DOC_ATUAL.storage_path);
  });
});
