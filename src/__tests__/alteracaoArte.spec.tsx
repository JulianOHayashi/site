import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, screen, waitFor } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderPortal, SESSAO_FALSA } from "./helpers/portalRender";

/* R4.2 — solicitação de alteração de frase ou arte (cliente). A autoridade é o
 * servidor; aqui se prova que o navegador não forma preço, não troca a arte
 * em execução e não oferece ação a quem não é owner. */
const rpc = vi.fn();
const upload = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (nome: string, args: unknown) => rpc(nome, args),
    storage: { from: (bucket: string) => ({ upload: (p: string, f: File, o: unknown) => upload(bucket, p, f, o) }) },
  },
}));
const obterVinculosParceiro = vi.fn();
vi.mock("../hooks/usePortalSiteAuth", () => ({ usePortalSiteAuth: () => SESSAO_FALSA() }));
vi.mock("../services/partnerApplicationService", async (orig) => ({
  ...(await orig<typeof import("../services/partnerApplicationService")>()),
  obterVinculosParceiro: (...a: unknown[]) => obterVinculosParceiro(...a),
}));
vi.mock("../components/Header", () => ({ default: () => null }));

import PortalPedidoAlteracaoArte from "../pages/portal/PortalPedidoAlteracaoArte";
import PortalPedidos from "../pages/portal/PortalPedidos";
import { aceitarOrcamento, enviarArte, listarSolicitacoes, mensagemArte } from "../services/artworkChangeService";
import { mensagemDeMotivo } from "../services/customizationImageService";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const ORDER = "33333333-3333-4333-8333-333333333333";
const REQ = "55555555-5555-4555-8555-555555555555";
const QUOTE = "66666666-6666-4666-8666-666666666666";
const DOC_SHA = "3".repeat(64);

function vinculo(role: "partner_owner" | "partner_manager") {
  return { tipo: "ok", vinculos: [{ company_id: COMPANY, trade_name: "Loja QA", company_status: "active",
    member_id: "m1", role, member_status: "active" }] };
}
const orcamento = (extra: Record<string, unknown> = {}) => ({
  quote_id: QUOTE, quote_no: 1, status: "open", artwork_version_id: "v1", supplier_name: "Fornecedor QA",
  supplier_document_reference: "ORC-1", scope: "40 bandeiras com a nova arte", pieces_count: 40,
  supplier_unit_cost_cents: 3500, supplier_total_cents: 140000, partner_charge_cents: 140000, cap_cents: 150000,
  excluded_items: ["frete", "criacao_de_arte", "instalacao", "tributos", "servicos"],
  items: [{ line_no: 1, kind: "flag_pieces", description: "bandeiras com a nova arte", document_locator: "p.1",
            quantity: 40, unit_cost_cents: 3500, line_total_cents: 140000 }],
  supplier_document: { document_id: "d1", storage_bucket: "supplier-quote-documents", storage_path: `${REQ}/doc`,
                       mime_type: "application/pdf", byte_size: 40960, sha256: DOC_SHA, attested: true, valid: true },
  ...extra,
});
const solicitacao = (status: string, extra: Record<string, unknown> = {}) => ({
  request_id: REQ, status, row_version: 5, target_campaign: "next_campaign", phrase_text: "Nova frase",
  exception_approved: false, accepted_total_cents: null, closed_reason: null,
  versions: [{ version_id: "v1", version_no: 1, phrase_text: "Nova frase", registered_at: "2026-11-16T10:00:00Z" }],
  quote: null, ...extra,
});
let resposta: Record<string, unknown>;

beforeEach(() => {
  vi.clearAllMocks();
  obterVinculosParceiro.mockResolvedValue(vinculo("partner_owner"));
  resposta = { ok: true, viewer_role: "partner_owner", can_request: true, requests: [] };
  rpc.mockImplementation(async (nome: string) => {
    if (nome === "artwork_change_requests_for_order") return { data: resposta, error: null };
    if (nome === "get_my_company_commercial_summary") {
      return { data: { ok: true, commercial: [{ order_id: ORDER, niche_code: "pharmacy", payment_status: "paid",
        has_customization_image: true }] }, error: null };
    }
    return { data: { ok: true, request_id: REQ }, error: null };
  });
});

afterEach(() => cleanup());

function abrir() {
  renderPortal(
    <Routes><Route path="/portal/pedidos/:orderId/alteracao-arte" element={<PortalPedidoAlteracaoArte />} /></Routes>,
    { rotas: [`/portal/pedidos/${ORDER}/alteracao-arte`] },
  );
}

describe("R4.2 — botão e regras", () => {
  it("a lista de pedidos oferece 'Solicitar alteração de frase ou arte' ao lado da imagem", async () => {
    renderPortal(<PortalPedidos />);
    const link = await screen.findByRole("link", { name: "Solicitar alteração de frase ou arte" });
    expect(link.getAttribute("href")).toBe(`/portal/pedidos/${ORDER}/alteracao-arte`);
  });

  it("a página explica: não troca a arte agora, próxima campanha, fidelidade mantida, custo do fornecedor sem margem", async () => {
    abrir();
    const regras = await screen.findByTestId("regras-alteracao");
    expect(regras.textContent).toMatch(/não troca a arte agora/);
    expect(regras.textContent).toMatch(/próxima campanha/);
    expect(regras.textContent).toMatch(/não muda a condição de anunciante fidelizado nem o valor da contratação/);
    expect(regras.textContent).toMatch(/custo comprovado do fornecedor, sem margem/);
    expect(regras.textContent).toMatch(/Frete, criação de arte, instalação, tributos/);
  });

  it("owner abre a solicitação para a próxima campanha por padrão; o navegador não envia preço", async () => {
    abrir();
    fireEvent.change(await screen.findByLabelText("Nova frase (opcional)"), { target: { value: "Frase nova" } });
    fireEvent.click(screen.getByRole("button", { name: "Abrir solicitação" }));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith("artwork_change_request_create", {
      p_order_id: ORDER, p_target_campaign: "next_campaign", p_phrase_text: "Frase nova", p_note: null,
    }));
  });

  it("manager vê a situação, mas não recebe nenhuma ação (o owner solicita e aceita)", async () => {
    obterVinculosParceiro.mockResolvedValue(vinculo("partner_manager"));
    resposta = { ok: true, viewer_role: "partner_member", can_request: false,
                 requests: [solicitacao("quoted", { quote: orcamento() })] };
    abrir();
    expect(await screen.findByTestId("somente-owner")).toBeDefined();
    expect(screen.queryByRole("button", { name: "Abrir solicitação" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Aceitar orçamento" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Cancelar solicitação" })).toBeNull();
  });
});

describe("R4.2 — orçamento e aceite", () => {
  it("mostra o custo do fornecedor como valor a pagar à parte, o teto e os itens não incluídos", async () => {
    resposta = { ok: true, viewer_role: "partner_owner", can_request: true,
                 requests: [solicitacao("quoted", { quote: orcamento() })] };
    abrir();
    expect((await screen.findByTestId("valor-parceiro")).textContent).toBe("R$ 1.400,00");
    expect(screen.getByTestId("orcamento").textContent).toMatch(/Teto aprovado.*R\$ 1\.500,00/);
    expect(screen.getByTestId("nao-incluidos").textContent).toBe(
      "Não incluídos: Frete, Criação de arte, Instalação, Tributos, Outros serviços.");
  });

  it("aceite exige confirmação e envia o valor do SERVIDOR, com a versão vista", async () => {
    resposta = { ok: true, viewer_role: "partner_owner", can_request: true,
                 requests: [solicitacao("quoted", { quote: orcamento() })] };
    abrir();
    const botao = await screen.findByRole("button", { name: "Aceitar orçamento" });
    expect((botao as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(botao);
    await waitFor(() => expect(rpc).toHaveBeenCalledWith("artwork_change_accept_quote", {
      p_request_id: REQ, p_expected_row_version: 5, p_quote_id: QUOTE, p_accepted_total_cents: 140000,
      p_supplier_document_sha256: DOC_SHA,
    }));
  });

  it("falha fechada: orçamento com valor ao parceiro diferente do custo do fornecedor não é exibido", async () => {
    resposta = { ok: true, viewer_role: "partner_owner", can_request: true,
                 requests: [solicitacao("quoted", { quote: orcamento({ partner_charge_cents: 154000 }) })] };
    const r = await listarSolicitacoes(ORDER);
    expect(r.tipo).toBe("erro");
    abrir();
    expect(await screen.findByRole("alert")).toBeDefined();
    expect(screen.queryByTestId("orcamento")).toBeNull();
  });

  it("aceitarOrcamento não chama o servidor sem orçamento aberto", async () => {
    const r = await aceitarOrcamento({ requestId: REQ, status: "under_review", rowVersion: 3, alvo: "next_campaign",
      frase: null, excecaoAprovada: false, valorAceitoCentavos: null, motivoEncerramento: null, versoes: [], orcamento: null,
      campanhaAlvo: 2, pronta: false });
    expect(r).toEqual({ tipo: "erro", motivo: "quote_not_current" });
    expect(rpc).not.toHaveBeenCalledWith("artwork_change_accept_quote", expect.anything());
  });

  it("produção autorizada: cobrança e produção externas aparecem como indisponíveis no site", async () => {
    resposta = { ok: true, viewer_role: "partner_owner", can_request: true,
                 requests: [solicitacao("production_authorized", { accepted_total_cents: 140000,
                   quote: orcamento({ status: "accepted" }) })] };
    abrir();
    expect((await screen.findByTestId("producao-autorizada")).textContent).toMatch(
      /R\$ 1\.400,00.*ainda não estão disponíveis neste site.*renovação com a nova arte fica bloqueada/);
    expect(screen.queryByRole("button", { name: "Cancelar solicitação" })).toBeNull();
  });
});

describe("R4.2.1 — orçamento itemizado e documento atestado", () => {
  it("mostra os itens do documento do fornecedor e o SHA-256 conferido pelo servidor (preço não linear)", async () => {
    resposta = { ok: true, viewer_role: "partner_owner", can_request: true,
                 requests: [solicitacao("quoted", { quote: orcamento({
                   pieces_count: 84, supplier_unit_cost_cents: null, supplier_total_cents: 277000,
                   partner_charge_cents: 277000, cap_cents: 280000,
                   items: [
                     { line_no: 1, kind: "flag_pieces", description: "faixa 1 a 50", document_locator: "p.1 l.3",
                       quantity: 50, unit_cost_cents: 3500, line_total_cents: 175000 },
                     { line_no: 2, kind: "flag_pieces", description: "faixa 51 a 84", document_locator: "p.1 l.4",
                       quantity: 34, unit_cost_cents: 3000, line_total_cents: 102000 }] }) })] };
    abrir();
    expect((await screen.findByTestId("valor-parceiro")).textContent).toBe("R$ 2.770,00");
    expect(screen.getByTestId("itens-orcamento").textContent).toMatch(/faixa 51 a 84.*34.*R\$ 30,00.*R\$ 1\.020,00/);
    expect(screen.getByTestId("documento-fornecedor").textContent).toContain(DOC_SHA);
  });

  it.each([
    ["soma dos itens diferente do total", { items: [{ line_no: 1, kind: "flag_pieces", description: "x pecas",
      document_locator: "p.1", quantity: 40, unit_cost_cents: 3500, line_total_cents: 140000 }], supplier_total_cents: 150000,
      partner_charge_cents: 150000 }],
    ["linha com quantidade x unitário diferente do total da linha", { items: [{ line_no: 1, kind: "flag_pieces",
      description: "x pecas", document_locator: "p.1", quantity: 40, unit_cost_cents: 3600, line_total_cents: 140000 }] }],
    ["documento não atestado", { supplier_document: { document_id: "d1", storage_bucket: "supplier-quote-documents",
      storage_path: `${REQ}/doc`, byte_size: 40960, sha256: DOC_SHA, attested: false, valid: false } }],
    ["orçamento sem itens", { items: [] }],
  ])("falha fechada: %s", async (_nome, extra) => {
    resposta = { ok: true, viewer_role: "partner_owner", can_request: true,
                 requests: [solicitacao("quoted", { quote: orcamento(extra) })] };
    const r = await listarSolicitacoes(ORDER);
    expect(r.tipo).toBe("erro");
  });

  it("mensagens da campanha alvo e do documento", () => {
    expect(mensagemArte("artwork_change_already_exists_for_campaign")).toMatch(/próxima campanha/);
    expect(mensagemArte("target_campaign_unavailable")).toMatch(/outra empresa/);
    expect(mensagemArte("supplier_document_mismatch")).toMatch(/Recarregue/);
  });
});

describe("R4.2 — arte e imagem travada", () => {
  it("envio da arte: caminho do servidor, upload sem sobrescrever, SHA-256 do arquivo e versão vista", async () => {
    rpc.mockImplementation(async (nome: string) => nome === "artwork_change_image_path"
      ? { data: { ok: true, bucket: "partner-customization-images", storage_path: `${ORDER}/alteracao-arte/${REQ}/x` }, error: null }
      : { data: { ok: true }, error: null });
    upload.mockResolvedValue({ error: null });
    const f = new File([new Uint8Array([1, 2, 3])], "arte.png", { type: "image/png" });
    const r = await enviarArte(REQ, 2, f, "Frase");
    expect(r).toEqual({ tipo: "ok", valor: null });
    expect(upload).toHaveBeenCalledWith("partner-customization-images", `${ORDER}/alteracao-arte/${REQ}/x`, f,
      { upsert: false, contentType: "image/png" });
    expect(rpc).toHaveBeenCalledWith("artwork_change_register_version", {
      p_request_id: REQ, p_expected_row_version: 2, p_storage_path: `${ORDER}/alteracao-arte/${REQ}/x`,
      p_sha256: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81", p_phrase_text: "Frase",
    });
  });

  it("mensagens: imagem travada aponta para a solicitação; versão desatualizada pede recarga", () => {
    expect(mensagemDeMotivo("artwork_locked_use_change_request")).toMatch(/Solicitar alteração de frase ou arte/);
    expect(mensagemArte("stale_request")).toMatch(/Recarregue/);
    expect(mensagemArte("artwork_change_already_open")).toMatch(/Já existe uma solicitação/);
  });
});
