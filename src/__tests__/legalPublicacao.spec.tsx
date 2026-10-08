import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));

import LegalIndice from "../pages/legal/LegalIndice";
import LegalAcordoMestre from "../pages/legal/LegalAcordoMestre";
import ConteudoLegal from "../components/legal/ConteudoLegal";
import {
  obterDocumentoVigente,
  obterDocumentoPorVersao,
} from "../services/legalDocumentService";

/**
 * CAMADA DE PUBLICAÇÃO LEGAL.
 *
 * O que estes testes protegem: que a página pública só mostre documento
 * efetivamente publicado, que versão e hash exibidos sejam os persistidos,
 * que uma versão histórica continue recuperável depois de publicada a
 * seguinte, e que conteúdo de banco nunca vire HTML executável.
 *
 * O que NÃO provam: autorização de servidor. As RPCs são simuladas. Quem
 * recusa rascunho de verdade é o filtro de status dentro das funções
 * SECURITY DEFINER, no banco.
 */

const HASH_V1 = "a".repeat(64);
const HASH_V2 = "b".repeat(64);

const MESTRE_V1 = {
  doc_type: "master_agreement",
  version: "QA-STAGING-MASTER-DRAFT-v0.9.8",
  title: "[QA STAGING] Acordo Mestre de Parceria Comercial",
  content: "# Acordo\n\n**1.1.** Cláusula de teste.",
  content_url: null,
  content_hash: HASH_V1,
  is_material_change: false,
  effective_from: "2026-10-05T00:00:00Z",
  effective_to: null,
};

const PEDIDO = {
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

function montar(ui: React.ReactNode, rota = "/legal") {
  return render(<MemoryRouter initialEntries={[rota]}>{ui}</MemoryRouter>);
}

const comRotas = (rota: string) =>
  montar(
    <Routes>
      <Route path="/legal" element={<LegalIndice />} />
      <Route path="/legal/acordo-mestre-parceiros" element={<LegalAcordoMestre />} />
    </Routes>,
    rota
  );

beforeEach(() => vi.clearAllMocks());
afterEach(() => cleanup());

/* 1, 4 ------------------------------------------------------------------ */
describe("rota pública do Mestre", () => {
  it("renderiza a versão publicada corrente com versão e hash persistidos", async () => {
    rpcMock.mockResolvedValue({ data: [PEDIDO, MESTRE_V1], error: null });
    comRotas("/legal/acordo-mestre-parceiros");

    expect(await screen.findByText(MESTRE_V1.version)).toBeDefined();
    // O hash exibido é o persistido, não um recalculado no navegador.
    expect(screen.getByText(HASH_V1)).toBeDefined();
    expect(screen.getByText(/vigente desde/i)).toBeDefined();
    expect(screen.getByRole("heading", { level: 1 }).textContent).toContain("Acordo Mestre");
  });

  it("o índice lista o documento publicado e liga à página dele", async () => {
    rpcMock.mockResolvedValue({ data: [MESTRE_V1], error: null });
    comRotas("/legal");
    const link = await screen.findByRole("link", { name: MESTRE_V1.title });
    expect(link.getAttribute("href")).toBe("/legal/acordo-mestre-parceiros");
    expect(screen.getByText(MESTRE_V1.version)).toBeDefined();
  });
});

/* 2 --------------------------------------------------------------------- */
describe("rascunho não é exposto publicamente", () => {
  it("a RPC pública só devolve publicados; nada de rascunho chega à tela", async () => {
    // get_current_legal_documents filtra status no servidor: um rascunho
    // simplesmente não vem na resposta.
    rpcMock.mockResolvedValue({ data: [PEDIDO], error: null });
    comRotas("/legal/acordo-mestre-parceiros");

    expect(
      await screen.findByText(/nenhuma versão do acordo mestre está publicada/i)
    ).toBeDefined();
    expect(screen.queryByText(/rascunho|draft/i)).toBeNull();
  });

  it("versão exata inexistente publicamente não vira conteúdo", async () => {
    rpcMock.mockResolvedValue({ data: [], error: null });
    const r = await obterDocumentoPorVersao("master_agreement", "rascunho-v0");
    expect(r.tipo).toBe("ausente");
  });
});

/* 3, 7 ------------------------------------------------------------------ */
describe("versão histórica permanece recuperável", () => {
  it("?versao= exibe a versão pedida, inclusive arquivada, e avisa que é histórica", async () => {
    rpcMock.mockImplementation(async (fn: string, args?: Record<string, unknown>) => {
      if (fn === "get_legal_document_version") {
        expect(args?.p_doc_type).toBe("master_agreement");
        return {
          data: [{ ...MESTRE_V1, status: "archived", published_at: "2026-10-05T00:00:00Z" }],
          error: null,
        };
      }
      return { data: [], error: null };
    });
    comRotas(`/legal/acordo-mestre-parceiros?versao=${MESTRE_V1.version}`);

    expect(await screen.findByText(MESTRE_V1.version)).toBeDefined();
    expect(screen.getByText("Versão histórica")).toBeDefined();
    expect(screen.getByText(/mantida para consulta de contratos/i)).toBeDefined();
    expect(screen.getByText(HASH_V1)).toBeDefined();
  });

  it("publicar uma versão nova NÃO troca o conteúdo da versão antiga pedida", async () => {
    // A vigente passa a ser a v2; a consulta por versão exata continua
    // devolvendo a v1, com o hash da v1.
    rpcMock.mockImplementation(async (fn: string, args?: Record<string, unknown>) => {
      if (fn === "get_legal_document_version" && args?.p_version === MESTRE_V1.version) {
        return { data: [{ ...MESTRE_V1, status: "archived" }], error: null };
      }
      return {
        data: [{ ...MESTRE_V1, version: "v2", content_hash: HASH_V2 }],
        error: null,
      };
    });

    const vigente = await obterDocumentoVigente("master_agreement");
    const historica = await obterDocumentoPorVersao("master_agreement", MESTRE_V1.version);

    expect(vigente.tipo).toBe("ok");
    expect(historica.tipo).toBe("ok");
    if (vigente.tipo === "ok" && historica.tipo === "ok") {
      expect(vigente.documento.version).toBe("v2");
      expect(vigente.documento.contentHash).toBe(HASH_V2);
      // A antiga NÃO foi reescrita.
      expect(historica.documento.version).toBe(MESTRE_V1.version);
      expect(historica.documento.contentHash).toBe(HASH_V1);
    }
  });
});

/* 5 --------------------------------------------------------------------- */
describe("ausência e falha são estados distintos e fail-closed", () => {
  it("falha de consulta NÃO é apresentada como ausência de documento", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "network" } });
    comRotas("/legal/acordo-mestre-parceiros");

    expect(await screen.findByText(/não foi possível carregar o acordo mestre/i)).toBeDefined();
    expect(screen.getByText(/falha de consulta, não a ausência/i)).toBeDefined();
    expect(screen.queryByText(/nenhuma versão do acordo mestre está publicada/i)).toBeNull();
  });

  it("sem Mestre publicado a página degrada sem inventar texto", async () => {
    rpcMock.mockResolvedValue({ data: [], error: null });
    const { container } = comRotas("/legal/acordo-mestre-parceiros");
    expect(
      await screen.findByText(/nenhuma versão do acordo mestre está publicada/i)
    ).toBeDefined();
    expect(container.textContent).not.toMatch(/cláusula|parceira declara/i);
  });

  it("o índice distingue falha de lista vazia", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    comRotas("/legal");
    expect(await screen.findByText(/não foi possível carregar os documentos/i)).toBeDefined();
    expect(screen.queryByText(/nenhum documento publicado/i)).toBeNull();
  });
});

/* 10 -------------------------------------------------------------------- */
describe("conteúdo do banco nunca vira HTML executável", () => {
  it("marcação perigosa é exibida como texto literal", () => {
    const veneno =
      '<script>window.__invadido = true</script>\n\n<img src=x onerror="window.__invadido=true">\n\n**negrito ok**';
    const { container } = render(<ConteudoLegal markdown={veneno} />);

    expect(container.querySelector("script")).toBeNull();
    expect(container.querySelector("img")).toBeNull();
    expect((window as unknown as Record<string, unknown>).__invadido).toBeUndefined();
    // O texto aparece, literal.
    expect(container.textContent).toContain("<script>");
    // E o subconjunto reconhecido continua funcionando.
    expect(container.querySelector("strong")?.textContent).toBe("negrito ok");
  });

  it("a página do Mestre não usa dangerouslySetInnerHTML", () => {
    for (const f of [
      "../pages/legal/LegalAcordoMestre.tsx",
      "../pages/legal/LegalIndice.tsx",
      "../components/legal/ConteudoLegal.tsx",
    ]) {
      const src = readFileSync(resolve(__dirname, f), "utf8");
      // Procura USO como prop JSX, não a menção em comentário — o próprio
      // ConteudoLegal explica por que não usa.
      expect(src).not.toMatch(/dangerouslySetInnerHTML\s*=/);
    }
  });

  it("a página pública não chama RPC de escrita", async () => {
    rpcMock.mockResolvedValue({ data: [MESTRE_V1], error: null });
    comRotas("/legal/acordo-mestre-parceiros");
    await screen.findByText(MESTRE_V1.version);
    const chamadas = rpcMock.mock.calls.map((c) => c[0] as string);
    const LEITURA = ["get_current_legal_documents", "get_legal_document_version"];
    expect(chamadas.every((n) => LEITURA.includes(n))).toBe(true);
  });
});

/* 8, 9 ------------------------------------------------------------------ */
describe("modelo comercial: seis posições, não sete", () => {
  const MIGRATION = readFileSync(
    resolve(__dirname, "../../supabase/migrations/20261005120000_legal_master_agreement_publication.sql"),
    "utf8"
  );

  it("a migration acrescenta master_agreement sem remover tipo algum", () => {
    for (const t of [
      "privacy_notice",
      "provisional_account_terms",
      "truthfulness_declaration",
      "document_analysis_authorization",
      "representation_declaration",
      "future_commercial_terms",
      "commercial_order_terms",
      "master_agreement",
    ]) {
      expect(MIGRATION).toContain(`'${t}'`);
    }
  });

  it("a formação de referência continua seis nichos e 84 unidades", async () => {
    const { FORMACAO_REFERENCIA, TOTAL_UNIDADES_REFERENCIA } = await import(
      "../content/institucional"
    );
    expect(FORMACAO_REFERENCIA).toHaveLength(6);
    expect(TOTAL_UNIDADES_REFERENCIA).toBe(84);
    // Supermercado é UMA posição comercial, com 24 unidades. As duas etapas
    // operacionais do App não criam uma sétima posição no Site.
    const sm = FORMACAO_REFERENCIA.filter((n) => /supermercado/i.test(n.nome));
    expect(sm).toHaveLength(1);
    expect(sm[0].unidades).toBe(24);
  });

  it("o seed de staging não cria posição comercial nem toca linhas sandbox", () => {
    const seed = readFileSync(
      resolve(__dirname, "../../supabase/seeds/20261005_staging_only_master_agreement_qa.sql"),
      "utf8"
    );
    // Só insere em legal_documents; nada de UPDATE/DELETE em linha existente.
    expect(seed).not.toMatch(/\bUPDATE\s+public\.legal_documents/i);
    expect(seed).not.toMatch(/\bDELETE\s+FROM/i);
    expect(seed).not.toMatch(/commercial_exclusivity_orders|commercial_opportunities/i);
    // E é inequivocamente de QA.
    expect(seed).toContain("QA-STAGING-MASTER-DRAFT-v0.9.8");
    expect(seed).toContain("NÃO ASSINÁVEL");
  });
});
