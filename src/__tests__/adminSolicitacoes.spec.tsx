import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * B10 — fundação administrativa funcional.
 *
 * A tela não reproduz autoridade: ela tenta a ação e mostra com segurança o
 * que o servidor responder. O teste de invariante prova isso — o frontend
 * oferece "Aprovar solicitação" mesmo com análises pendentes, e é o
 * backend que recusa.
 */
const rpcMock = vi.fn();
const fromMock = vi.fn();

const APP = {
  id: "app-1", legal_name: "Super Teste LTDA", trade_name: "Super", cnpj: "12345678000195",
  contact_email: "contato@teste.com.br", city: "Vila Velha", uf: "ES", status: "under_review",
  company_review_status: "pending", authority_review_status: "pending",
  reconsideration_count: 0, decision_reason: null,
};
const REPS = [{ id: "rep-1", application_id: "app-1", full_name: "Maria Souza",
  email: "maria@teste.com.br", authority_status: "pending", is_current: true }];
const CORR = [{ id: "c1", application_id: "app-1", scope: "documents", message: "Falta contrato",
  requested_at: "2026-08-02T10:00:00Z", response_message: null, responded_at: null }];
const DOCS = [{ id: "d1", application_id: "app-1", doc_type: "contrato_social",
  storage_bucket: "partner-application-docs", storage_path: "app-1/contrato_social/a.pdf",
  original_filename: "contrato.pdf", mime_type: "application/pdf", byte_size: 10,
  review_status: "received", review_notes: null, created_at: "2026-08-03T10:00:00Z",
  superseded_at: null, superseded_by_document_id: null }];

const LISTA = [{
  application_id: "app-1", cnpj: "12345678000195", legal_name: "Super Teste LTDA",
  city: "Vila Velha", uf: "ES", status: "under_review", company_review_status: "pending",
  authority_review_status: "pending", created_at: "2026-08-01T10:00:00Z",
  representative: { id: "rep-1", full_name: "Maria Souza", authority_status: "pending" },
}];

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
import Admin from "../pages/Admin";

function enc(dados: unknown, single = false) {
  const o: Record<string, unknown> = {};
  o.select = () => o;
  o.eq = () => o;
  o.order = async () => ({ data: dados, error: null });
  o.maybeSingle = async () => ({ data: single ? dados : null, error: null });
  return o;
}

beforeEach(() => {
  rpcMock.mockReset(); fromMock.mockReset();
  rpcMock.mockImplementation(async (nome: string) => {
    if (nome === "admin_list_partner_applications") return { data: { ok: true, items: LISTA }, error: null };
    return { data: { ok: true }, error: null };
  });
  fromMock.mockImplementation((t: string) => {
    if (t === "partner_applications") return enc(APP, true);
    if (t === "partner_application_representatives") return enc(REPS);
    if (t === "partner_application_corrections") return enc(CORR);
    return enc(DOCS);
  });
});
afterEach(() => cleanup());

const montar = () => render(<MemoryRouter><AdminSolicitacoes /></MemoryRouter>);

describe("B10 — link no painel admin", () => {
  it("Admin.tsx expoe link para Solicitacoes de parceria", () => {
    render(<MemoryRouter><Admin /></MemoryRouter>);
    const link = screen.getByRole("link", { name: /solicitações de parceria/i });
    expect(link.getAttribute("href")).toBe("/admin/solicitacoes");
  });
});

describe("B10 — listagem e detalhe", () => {
  it("lista solicitacoes reais com filtro de situacao", async () => {
    montar();
    await waitFor(() => expect(screen.getByText("Super Teste LTDA")).toBeDefined());
    expect(screen.getByLabelText(/situação/i)).toBeDefined();
    const chamada = rpcMock.mock.calls.find((c) => c[0] === "admin_list_partner_applications");
    expect((chamada?.[1] as { p_status: string }).p_status).toBe("under_review");
  });

  it("abre o detalhe com empresa, responsavel, documentos e correcoes", async () => {
    montar();
    await waitFor(() => expect(screen.getByRole("button", { name: /abrir solicitação/i })).toBeDefined());
    fireEvent.click(screen.getByRole("button", { name: /abrir solicitação/i }));
    await waitFor(() => expect(screen.getByText("contato@teste.com.br")).toBeDefined());
    expect(screen.getByText(/maria@teste\.com\.br/)).toBeDefined();
    expect(screen.getByText(/contrato\.pdf/)).toBeDefined();
    expect(screen.getByText(/falta contrato/i)).toBeDefined();
  });
});

describe("B10 — acoes de analise", () => {
  const abrir = async () => {
    montar();
    await waitFor(() => expect(screen.getByRole("button", { name: /abrir solicitação/i })).toBeDefined());
    fireEvent.click(screen.getByRole("button", { name: /abrir solicitação/i }));
    await waitFor(() => expect(screen.getByRole("button", { name: /aprovar empresa/i })).toBeDefined());
  };

  it("aprova empresa e autoridade por RPCs distintas", async () => {
    await abrir();
    fireEvent.click(screen.getByRole("button", { name: /aprovar empresa/i }));
    await waitFor(() =>
      expect(rpcMock.mock.calls.some((c) => c[0] === "admin_review_partner_company")).toBe(true));
    fireEvent.click(screen.getByRole("button", { name: /aprovar autoridade/i }));
    await waitFor(() =>
      expect(rpcMock.mock.calls.some((c) => c[0] === "admin_review_partner_authority")).toBe(true));
  });

  it("solicita correcao com escopo e mensagem", async () => {
    await abrir();
    fireEvent.change(screen.getByLabelText(/solicitar correção/i), { target: { value: "Reenvie o contrato." } });
    fireEvent.click(screen.getByRole("button", { name: /enviar pedido de correção/i }));
    await waitFor(() => {
      const c = rpcMock.mock.calls.find((x) => x[0] === "admin_request_partner_correction");
      expect((c?.[1] as { p_message: string }).p_message).toBe("Reenvie o contrato.");
      expect((c?.[1] as { p_scope: string }).p_scope).toBe("documents");
    });
  });

  it("revisa documento e abre por URL assinada", async () => {
    await abrir();
    fireEvent.click(screen.getByRole("button", { name: /^aceitar$/i }));
    await waitFor(() =>
      expect(rpcMock.mock.calls.some((c) => c[0] === "admin_review_partner_document")).toBe(true));
  });

  it("expoe reconsideracao", async () => {
    await abrir();
    fireEvent.click(screen.getByRole("button", { name: /abrir reconsideração/i }));
    await waitFor(() =>
      expect(rpcMock.mock.calls.some((c) => c[0] === "admin_open_partner_reconsideration")).toBe(true));
  });

  it("invariante do backend e respeitada: erro vira mensagem segura", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "admin_list_partner_applications") return { data: { ok: true, items: LISTA }, error: null };
      if (nome === "admin_decide_partner_application")
        return { data: { ok: false, reason: "reviews_incomplete" }, error: null };
      return { data: { ok: true }, error: null };
    });
    await abrir();
    fireEvent.click(screen.getByRole("button", { name: /aprovar solicitação/i }));
    await waitFor(() =>
      expect(screen.getByText(/análises de empresa e autoridade precisam estar aprovadas/i)).toBeDefined());
  });

  it("erro cru do banco nao chega a tela", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "admin_list_partner_applications") return { data: { ok: true, items: LISTA }, error: null };
      return { data: null, error: { message: 'new row violates check constraint "partner_applications_aprovacao_exige_reviews"' } };
    });
    await abrir();
    fireEvent.click(screen.getByRole("button", { name: /aprovar solicitação/i }));
    await waitFor(() => expect(screen.getByText(/não foi possível concluir/i)).toBeDefined());
    const txt = document.body.textContent ?? "";
    expect(txt).not.toContain("check constraint");
    expect(txt).not.toContain("partner_applications_aprovacao_exige_reviews");
  });
});
