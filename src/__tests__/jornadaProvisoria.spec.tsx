import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * B9 — jornada da conta provisória: retorno de login, correções,
 * documentos e upload privado com versionamento.
 */
const rpcMock = vi.fn();
const fromMock = vi.fn();
const uploadMock = vi.fn(async () => ({ data: { path: "p" }, error: null }));
const removeMock = vi.fn(async () => ({ data: null, error: null }));
const signInMock = vi.fn(async () => ({ data: {}, error: null }));

const SOL = {
  application_id: "app-1", status: "changes_requested", company_review_status: "pending",
  authority_review_status: "pending", account_kind: "provisional", cnpj: "12345678000195",
  legal_name: "Super Teste LTDA", city: "Vila Velha", uf: "ES", created_at: "2026-08-01T10:00:00Z",
};

const CORRECOES = [{
  id: "corr-1", application_id: "app-1", scope: "documents",
  message: "Envie o contrato social atualizado.", requested_at: "2026-08-02T10:00:00Z",
  response_message: null, responded_at: null,
}];

const DOCS = [
  { id: "doc-2", application_id: "app-1", doc_type: "contrato_social",
    storage_bucket: "partner-application-docs", storage_path: "app-1/contrato_social/2-x.pdf",
    original_filename: "contrato-v2.pdf", mime_type: "application/pdf", byte_size: 10,
    review_status: "received", review_notes: null, created_at: "2026-08-03T10:00:00Z",
    superseded_at: null, superseded_by_document_id: null },
  { id: "doc-1", application_id: "app-1", doc_type: "contrato_social",
    storage_bucket: "partner-application-docs", storage_path: "app-1/contrato_social/1-y.pdf",
    original_filename: "contrato-v1.pdf", mime_type: "application/pdf", byte_size: 9,
    review_status: "rejected", review_notes: "ilegível", created_at: "2026-08-01T10:00:00Z",
    superseded_at: "2026-08-03T10:00:00Z", superseded_by_document_id: "doc-2" },
];

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    from: (t: string) => fromMock(t),
    storage: {
      from: () => ({
        upload: (...a: unknown[]) => uploadMock(...(a as [])),
        remove: (...a: unknown[]) => removeMock(...(a as [])),
        createSignedUrl: vi.fn(async () => ({ data: { signedUrl: "https://x/y" }, error: null })),
      }),
    },
    auth: {
      getSession: vi.fn(async () => ({ data: { session: { access_token: "t", user: { id: "u1" } } } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
      signInWithPassword: (...a: unknown[]) => signInMock(...(a as [])),
    },
  },
  supabaseConfigurado: true,
}));

import SolicitacaoStatus from "../pages/parceiros/SolicitacaoStatus";
import Parceiros from "../pages/Parceiros";

function tabela(dados: unknown[]) {
  const encadeado: Record<string, unknown> = {};
  encadeado.select = () => encadeado;
  encadeado.eq = () => encadeado;
  encadeado.order = async () => ({ data: dados, error: null });
  return encadeado;
}

beforeEach(() => {
  rpcMock.mockReset(); fromMock.mockReset(); uploadMock.mockClear();
  removeMock.mockClear(); signInMock.mockClear(); localStorage.clear();
  rpcMock.mockImplementation(async (nome: string) => {
    if (nome === "get_my_partner_application") return { data: SOL, error: null };
    return { data: { ok: true }, error: null };
  });
  fromMock.mockImplementation((t: string) =>
    tabela(t === "partner_application_corrections" ? CORRECOES : DOCS)
  );
});
afterEach(() => cleanup());

const montar = () => render(<MemoryRouter><SolicitacaoStatus /></MemoryRouter>);

describe("B9 — status e correcoes", () => {
  it("mostra estado, empresa e regiao", async () => {
    montar();
    await waitFor(() => expect(screen.getByText("Super Teste LTDA")).toBeDefined());
    // O rótulo aparece no estado e no título da seção de correções.
    expect(screen.getAllByText(/correções solicitadas/i).length).toBeGreaterThan(0);
    expect(screen.getByText("12345678000195")).toBeDefined();
  });

  it("lista correcao real e permite responder", async () => {
    montar();
    await waitFor(() => expect(screen.getByText(/contrato social atualizado/i)).toBeDefined());
    fireEvent.change(screen.getByLabelText(/responder/i), { target: { value: "Segue anexo." } });
    fireEvent.click(screen.getByRole("button", { name: /enviar resposta/i }));
    await waitFor(() => {
      const chamadas = rpcMock.mock.calls.filter(
        (c) => c[0] === "respond_partner_application_correction"
      );
      expect(chamadas.length).toBe(1);
      expect((chamadas[0][1] as { p_message: string }).p_message).toBe("Segue anexo.");
    });
  });

  it("nao envia resposta vazia", async () => {
    montar();
    await waitFor(() => expect(screen.getByLabelText(/responder/i)).toBeDefined());
    fireEvent.click(screen.getByRole("button", { name: /enviar resposta/i }));
    await waitFor(() => expect(screen.getByText(/escreva uma resposta/i)).toBeDefined());
    expect(rpcMock.mock.calls.filter((c) => c[0] === "respond_partner_application_correction").length).toBe(0);
  });
});

describe("B9 — documentos e versionamento", () => {
  it("separa versao atual de historico", async () => {
    montar();
    await waitFor(() => expect(screen.getByText(/contrato-v2\.pdf/i)).toBeDefined());
    expect(screen.getByText(/versões anteriores/i)).toBeDefined();
    expect(screen.getByText(/contrato-v1\.pdf/i)).toBeDefined();
    expect(screen.getByText(/substituído/i)).toBeDefined();
  });

  it("upload gera caminho NOVO e registra metadado", async () => {
    montar();
    await waitFor(() => expect(screen.getByLabelText(/arquivo/i)).toBeDefined());
    const arquivo = new File(["x"], "novo.pdf", { type: "application/pdf" });
    fireEvent.change(screen.getByLabelText(/arquivo/i), { target: { files: [arquivo] } });
    fireEvent.click(screen.getByRole("button", { name: /enviar documento/i }));

    await waitFor(() => expect(uploadMock).toHaveBeenCalledTimes(1));
    const caminho = (uploadMock.mock.calls[0] as unknown as [string])[0];
    expect(caminho.startsWith("app-1/contrato_social/")).toBe(true);
    // Jamais reaproveita o path de um documento ja registrado.
    expect(DOCS.some((d) => d.storage_path === caminho)).toBe(false);

    await waitFor(() => {
      const reg = rpcMock.mock.calls.filter((c) => c[0] === "register_partner_application_document");
      expect(reg.length).toBe(1);
      expect((reg[0][1] as { p_storage_path: string }).p_storage_path).toBe(caminho);
    });
  });

  // M1-C3: a limpeza pelo cliente foi REMOVIDA. O DELETE direto do
  // solicitante era superfície de corrida contra a RPC de registro; o objeto
  // órfão fica no bucket, sem metadado, e não é reaproveitável.
  it("falha no registro NAO chama storage.remove", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_my_partner_application") return { data: SOL, error: null };
      if (nome === "register_partner_application_document")
        return { data: { ok: false, reason: "invalid_document" }, error: null };
      return { data: { ok: true }, error: null };
    });
    montar();
    await waitFor(() => expect(screen.getByLabelText(/arquivo/i)).toBeDefined());
    fireEvent.change(screen.getByLabelText(/arquivo/i), {
      target: { files: [new File(["x"], "ruim.pdf", { type: "application/pdf" })] },
    });
    fireEvent.click(screen.getByRole("button", { name: /enviar documento/i }));
    await waitFor(() => expect(screen.getByText(/documento inválido/i)).toBeDefined());
    expect(removeMock).not.toHaveBeenCalled();
  });

  it("erro exibido nao vaza SQL, constraint nem bucket", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_my_partner_application") return { data: SOL, error: null };
      return { data: null, error: { message: 'duplicate key value violates unique constraint "pad_storage_path_uk"' } };
    });
    montar();
    await waitFor(() => expect(screen.getByLabelText(/responder/i)).toBeDefined());
    fireEvent.change(screen.getByLabelText(/responder/i), { target: { value: "resposta" } });
    fireEvent.click(screen.getByRole("button", { name: /enviar resposta/i }));
    await waitFor(() => expect(screen.getByText(/não foi possível concluir/i)).toBeDefined());
    const txt = document.body.textContent ?? "";
    expect(txt).not.toContain("constraint");
    expect(txt).not.toContain("pad_storage_path_uk");
    expect(txt).not.toContain("partner-application-docs");
  });
});

describe("B9 — retorno de login da conta provisoria", () => {
  it("login com next interno volta a /parceiros/solicitacao", async () => {
    render(
      <MemoryRouter initialEntries={["/parceiros?next=%2Fparceiros%2Fsolicitacao"]}>
        <Routes>
          <Route path="/parceiros" element={<Parceiros />} />
          <Route path="/parceiros/solicitacao" element={<div data-testid="destino">acompanhamento</div>} />
          <Route path="/parceiros/painel" element={<div data-testid="painel">painel</div>} />
        </Routes>
      </MemoryRouter>
    );
    await waitFor(() => expect(screen.getByTestId("destino")).toBeDefined());
    expect(screen.queryByTestId("painel")).toBeNull();
  });

  it("next externo e ignorado e cai no painel", async () => {
    render(
      <MemoryRouter initialEntries={["/parceiros?next=" + encodeURIComponent("/\\evil.com")]}>
        <Routes>
          <Route path="/parceiros" element={<Parceiros />} />
          <Route path="/parceiros/painel" element={<div data-testid="painel">painel</div>} />
          <Route path="*" element={<div data-testid="fora">fora</div>} />
        </Routes>
      </MemoryRouter>
    );
    await waitFor(() => expect(screen.getByTestId("painel")).toBeDefined());
    expect(screen.queryByTestId("fora")).toBeNull();
  });

  it("next para fora de /parceiros e ignorado", async () => {
    render(
      <MemoryRouter initialEntries={["/parceiros?next=%2Fadmin"]}>
        <Routes>
          <Route path="/parceiros" element={<Parceiros />} />
          <Route path="/parceiros/painel" element={<div data-testid="painel">painel</div>} />
          <Route path="/admin" element={<div data-testid="admin">admin</div>} />
        </Routes>
      </MemoryRouter>
    );
    await waitFor(() => expect(screen.getByTestId("painel")).toBeDefined());
    expect(screen.queryByTestId("admin")).toBeNull();
  });
});
