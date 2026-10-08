import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));

import EtapasContratacao from "../pages/comercial/EtapasContratacao";
import { obterMestreRegente } from "../services/commercialContractService";

/**
 * C1 e C2 da auditoria de 2026-10-05.
 *
 * C1: o caminho canônico de publicação precisa alcançar master_agreement.
 * C2: o Mestre assinado por uma empresa precisa corresponder, de forma
 *     verificável pelo servidor, a uma publicação pública concreta.
 *
 * As asserções de SQL leem a migration: o banco não é executado aqui. Elas
 * provam o CONTRATO escrito, não o comportamento em execução — isso só a
 * aceitação autenticada em staging prova.
 */

const MIG = readFileSync(
  resolve(
    __dirname,
    "../../supabase/migrations/20261005140000_legal_master_canonical_publication_and_linkage.sql"
  ),
  "utf8"
);

const TERMOS = {
  doc_type: "commercial_order_terms",
  version: "sandbox-2026-09-17-v1",
  title: "Termos do Pedido Comercial",
  content: "Termos.",
  content_url: null,
  content_hash: "c".repeat(64),
  is_material_change: false,
  effective_from: "2026-09-17T00:00:00Z",
  effective_to: null,
};

const MESTRE_OK = {
  ok: true,
  legal_document_id: "ld-1",
  version: "QA-STAGING-MASTER-DRAFT-v0.9.8",
  title: "Acordo Mestre de Parceria Comercial",
  content_hash: "d".repeat(64),
  status: "published",
  signed_at: "2026-10-01T00:00:00Z",
};

function montarRpc(mestre: unknown = MESTRE_OK) {
  rpcMock.mockImplementation(async (fn: string) => {
    if (fn === "get_current_legal_documents") return { data: [TERMOS], error: null };
    if (fn === "get_governing_master_for_intent") return { data: mestre, error: null };
    return { data: null, error: { message: "rpc inesperada" } };
  });
}

const montar = () =>
  render(
    <MemoryRouter>
      <EtapasContratacao intentId="i-1" amountCents={1999900} fidelizado={false} />
    </MemoryRouter>
  );

beforeEach(() => vi.clearAllMocks());
afterEach(() => cleanup());

/* C1 -------------------------------------------------------------------- */
describe("C1 — caminho canônico de publicação", () => {
  it("admin_publish_legal_document aceita master_agreement", () => {
    const i = MIG.indexOf("IF v_tipo NOT IN (");
    expect(i).toBeGreaterThan(-1);
    const allowlist = MIG.slice(i, MIG.indexOf("doc_type_not_allowed", i));
    expect(allowlist).toContain("'master_agreement'");
  });

  it("todos os tipos anteriores continuam aceitos, nenhum removido", () => {
    const i = MIG.indexOf("IF v_tipo NOT IN (");
    const allowlist = MIG.slice(i, MIG.indexOf("doc_type_not_allowed", i));
    for (const t of [
      "privacy_notice",
      "provisional_account_terms",
      "truthfulness_declaration",
      "document_analysis_authorization",
      "representation_declaration",
      "future_commercial_terms",
      "commercial_order_terms",
    ]) {
      expect(allowlist).toContain(`'${t}'`);
    }
  });

  it("preserva assinatura, exigência de admin, idempotência e auditoria", () => {
    expect(MIG).toContain("CREATE OR REPLACE FUNCTION public.admin_publish_legal_document");
    // Não-admin continua barrado pela mesma guarda de antes.
    expect(MIG).toContain("PERFORM public.m1_exigir_admin();");
    expect(MIG).toContain("SECURITY DEFINER");
    // Republicar a mesma versão com o mesmo hash não cria linha.
    expect(MIG).toContain("'already', true");
    expect(MIG).toContain("version_already_exists");
    expect(MIG).toContain("legal_document.published");
    // Sem GRANT novo: os concedidos originalmente seguem valendo.
    expect(MIG).not.toMatch(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.admin_publish_legal_document/i);
  });

  it("não edita migration histórica", () => {
    const historica = readFileSync(
      resolve(
        __dirname,
        "../../supabase/migrations/20260916120000_commercial_order_terms_and_finalization.sql"
      ),
      "utf8"
    );
    // A allowlist original permanece como estava: a correção é aditiva.
    const trecho = historica.slice(historica.indexOf("IF v_tipo NOT IN"));
    expect(trecho.slice(0, 400)).not.toContain("master_agreement");
  });
});

/* C2 — relação no banco ------------------------------------------------- */
describe("C2 — vínculo verificável no servidor", () => {
  it("há FK explícita de commercial_master_agreements para legal_documents", () => {
    expect(MIG).toMatch(
      /ADD COLUMN IF NOT EXISTS legal_document_id uuid\s+REFERENCES public\.legal_documents\(id\)/
    );
  });

  it("a coluna é nullable para preservar linhas históricas, sem reescrevê-las", () => {
    expect(MIG).not.toMatch(/legal_document_id uuid[^;]*NOT NULL/);
    expect(MIG).toContain("RETURN NEW; -- linha histórica, sem vínculo: preservada.");
    // Nada de UPDATE em massa nas linhas existentes.
    expect(MIG).not.toMatch(/UPDATE public\.commercial_master_agreements\s+SET legal_document_id/i);
  });

  it("versão e hash não podem divergir do documento apontado", () => {
    expect(MIG).toContain("agreement_version (%) diverge da versao publicada");
    expect(MIG).toContain("document_hash diverge do hash publicado");
    expect(MIG).toContain("nao e um master_agreement");
    // Rascunho nunca rege contrato assinado.
    expect(MIG).toContain("nao pode reger assinatura");
    expect(MIG).toContain("CREATE TRIGGER cma_coerencia_legal");
  });

  it("registrar assinatura com versão não publicada falha fechado", () => {
    expect(MIG).toContain("master_agreement_version_not_published");
    expect(MIG).toContain("document_hash_mismatch");
    // O hash gravado vem da fonte, não do parâmetro.
    expect(MIG).toContain("v_doc.content_hash,");
  });

  it("publicar Mestre novo não reescreve o vínculo de uma assinatura anterior", () => {
    // A linha anterior só muda de status; legal_document_id permanece.
    const trecho = MIG.slice(MIG.indexOf("SET status = 'superseded'"));
    expect(trecho.slice(0, 200)).not.toContain("legal_document_id");
    // O comportamento, não a frase do comentário: a atualização de supersessão
    // altera só status e superseded_at.
    const i = MIG.indexOf("SET status = 'superseded'");
    const update = MIG.slice(i, MIG.indexOf(";", i));
    expect(update).toContain("superseded_at");
    expect(update).not.toContain("legal_document_id");
    expect(update).not.toContain("agreement_version");
    expect(update).not.toContain("document_hash");
  });

  it("a leitura do Mestre regente exige titular ativo e falha fechada", () => {
    expect(MIG).toContain("get_governing_master_for_intent");
    expect(MIG).toContain("'not_company_owner'");
    expect(MIG).toContain("'master_linkage_missing'");
    expect(MIG).toContain("'master_document_unavailable'");
    // anon não executa.
    expect(MIG).toMatch(/REVOKE EXECUTE ON FUNCTION public\.get_governing_master_for_intent\(uuid\) FROM anon/);
  });
});

/* C2 — UI ---------------------------------------------------------------- */
describe("C2 — checkout mostra a versão EXATA que rege a empresa", () => {
  it("exibe versão e hash do Mestre regente e liga à versão exata", async () => {
    montarRpc();
    montar();

    expect(await screen.findByText(/acordo mestre que rege esta contratação/i)).toBeDefined();
    expect(screen.getByText(MESTRE_OK.content_hash, { exact: false })).toBeDefined();

    const link = screen.getByRole("link", { name: /ler esta versão do acordo mestre/i });
    // Rota histórica com a versão exata, não a genérica.
    expect(link.getAttribute("href")).toBe(
      `/legal/acordo-mestre-parceiros?versao=${encodeURIComponent(MESTRE_OK.version)}`
    );
  });

  it("depois de publicado um Mestre novo, o checkout continua apontando para o regente", async () => {
    // A RPC devolve o Mestre da EMPRESA (arquivado), não o publicado hoje.
    montarRpc({ ...MESTRE_OK, status: "archived", version: "MASTER-v1", content_hash: "e".repeat(64) });
    montar();

    const link = await screen.findByRole("link", { name: /ler esta versão do acordo mestre/i });
    expect(link.getAttribute("href")).toContain("versao=MASTER-v1");
    expect(screen.getByText(/versão histórica/i)).toBeDefined();
    expect(screen.queryByText(MESTRE_OK.content_hash)).toBeNull();
  });

  it("sem vínculo, a tela avisa e o botão de contratar fica desabilitado", async () => {
    montarRpc({ ok: false, reason: "master_linkage_missing" });
    montar();

    expect(
      await screen.findByText(/não foi possível identificar a versão do acordo mestre/i)
    ).toBeDefined();
    // Fail-closed: nem marcando o aceite se contrata.
    const botoes = screen.getAllByRole("button");
    for (const b of botoes) {
      if (/avançar|contratar|finalizar/i.test(b.textContent ?? "")) {
        expect((b as HTMLButtonElement).disabled).toBe(true);
      }
    }
    expect(screen.queryByRole("link", { name: /ler esta versão/i })).toBeNull();
  });

  it("o serviço traduz cada motivo de indisponibilidade sem inventar documento", async () => {
    for (const motivo of [
      "master_agreement_missing",
      "master_linkage_missing",
      "master_document_unavailable",
      "not_company_owner",
    ]) {
      rpcMock.mockResolvedValue({ data: { ok: false, reason: motivo }, error: null });
      const r = await obterMestreRegente("i-1");
      expect(r).toEqual({ tipo: "indisponivel", motivo });
    }
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    expect(await obterMestreRegente("i-1")).toEqual({
      tipo: "indisponivel",
      motivo: "erro_consulta",
    });
  });
});
