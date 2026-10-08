import { supabase } from "../lib/supabase";

/**
 * Acesso canônico a documentos legais publicados.
 *
 * POR QUE UM SERVIÇO, E NÃO LEITURA DIRETA NOS COMPONENTES
 *
 * Documento legal tem duas propriedades que não podem depender de disciplina
 * de quem escreve a tela: rascunho nunca pode vazar, e versão e hash andam
 * sempre juntos. Centralizando aqui, essas garantias passam a ser do tipo, e
 * não de um `select` que alguém repetiu num componente novo.
 *
 * O QUE ESTA CAMADA NÃO FAZ
 *
 * Não escreve. Não aceita. Não decide autorização. As RPCs usadas são
 * SECURITY DEFINER com filtro de status no servidor; o navegador não é
 * autoridade sobre o que é publicado. Se alguém adicionar aqui uma função que
 * muta, está no arquivo errado.
 *
 * REUSO DO MODELO EXISTENTE
 *
 * `get_current_legal_documents()` já existia, já é concedida a `anon` e já
 * filtra `status='published'` mais vigência. Não se cria modelo paralelo:
 * esta camada a reusa e só acrescenta a leitura de versão exata, que o banco
 * não oferecia.
 */

/** Tipos publicáveis. Espelha o CHECK de `legal_documents.doc_type`. */
export type LegalDocType =
  | "privacy_notice"
  | "provisional_account_terms"
  | "truthfulness_declaration"
  | "document_analysis_authorization"
  | "representation_declaration"
  | "future_commercial_terms"
  | "commercial_order_terms"
  | "master_agreement";

export type LegalDocument = {
  docType: LegalDocType;
  version: string;
  title: string;
  /** Conteúdo textual. Pode ser nulo quando o documento vive numa URL. */
  content: string | null;
  contentUrl: string | null;
  /** SHA-256 persistido. Versão e hash sempre viajam juntos. */
  contentHash: string | null;
  status: "published" | "archived";
  isMaterialChange: boolean;
  effectiveFrom: string | null;
  effectiveTo: string | null;
  publishedAt: string | null;
};

/**
 * Resultado explícito. `indisponivel` é falha de consulta e `ausente` é
 * resposta boa sem documento: confundir os dois faria a página dizer "não há
 * Acordo publicado" diante de uma queda de rede, o que é falso e grave numa
 * página legal.
 */
export type ResultadoLegal =
  | { tipo: "ok"; documento: LegalDocument }
  | { tipo: "ausente" }
  | { tipo: "indisponivel" };

type LinhaRpc = {
  doc_type?: unknown;
  version?: unknown;
  title?: unknown;
  content?: unknown;
  content_url?: unknown;
  content_hash?: unknown;
  status?: unknown;
  is_material_change?: unknown;
  effective_from?: unknown;
  effective_to?: unknown;
  published_at?: unknown;
};

const texto = (v: unknown): string | null =>
  typeof v === "string" && v.length > 0 ? v : null;

/**
 * Converte a linha da RPC em documento. Devolve null quando falta algo sem o
 * que a página não deveria renderizar — tipo, versão ou título —, em vez de
 * exibir um documento legal pela metade.
 */
function converter(linha: LinhaRpc): LegalDocument | null {
  const docType = texto(linha.doc_type);
  const version = texto(linha.version);
  const title = texto(linha.title);
  if (!docType || !version || !title) return null;

  // `get_current_legal_documents` não devolve status: ela só retorna vigentes,
  // que são por definição publicados.
  const status = linha.status === "archived" ? "archived" : "published";

  return {
    docType: docType as LegalDocType,
    version,
    title,
    content: texto(linha.content),
    contentUrl: texto(linha.content_url),
    contentHash: texto(linha.content_hash),
    status,
    isMaterialChange: linha.is_material_change === true,
    effectiveFrom: texto(linha.effective_from),
    effectiveTo: texto(linha.effective_to),
    publishedAt: texto(linha.published_at),
  };
}

/** Documento vigente de um tipo. Usa a RPC pública que já existia. */
export async function obterDocumentoVigente(
  docType: LegalDocType
): Promise<ResultadoLegal> {
  if (!supabase) return { tipo: "indisponivel" };
  const { data, error } = await supabase.rpc("get_current_legal_documents");
  if (error) return { tipo: "indisponivel" };
  if (!Array.isArray(data)) return { tipo: "indisponivel" };

  const linha = (data as LinhaRpc[]).find((d) => d.doc_type === docType);
  if (!linha) return { tipo: "ausente" };

  const documento = converter(linha);
  return documento ? { tipo: "ok", documento } : { tipo: "ausente" };
}

/** Todos os documentos vigentes, para o índice da área legal. */
export async function listarDocumentosVigentes(): Promise<
  { tipo: "ok"; documentos: LegalDocument[] } | { tipo: "indisponivel" }
> {
  if (!supabase) return { tipo: "indisponivel" };
  const { data, error } = await supabase.rpc("get_current_legal_documents");
  if (error || !Array.isArray(data)) return { tipo: "indisponivel" };

  const documentos = (data as LinhaRpc[])
    .map(converter)
    .filter((d): d is LegalDocument => d !== null);
  return { tipo: "ok", documentos };
}

/**
 * Versão EXATA, inclusive arquivada.
 *
 * É o que sustenta um link para um contrato antigo: publicar a versão
 * seguinte não pode trocar, na página, o texto que alguém já aceitou. A RPC
 * recusa rascunho no servidor, então nem um pedido direto o alcança.
 */
export async function obterDocumentoPorVersao(
  docType: LegalDocType,
  version: string
): Promise<ResultadoLegal> {
  if (!supabase) return { tipo: "indisponivel" };
  if (version.trim().length === 0) return { tipo: "ausente" };

  const { data, error } = await supabase.rpc("get_legal_document_version", {
    p_doc_type: docType,
    p_version: version,
  });
  if (error) return { tipo: "indisponivel" };

  const linha = Array.isArray(data) ? (data[0] as LinhaRpc | undefined) : undefined;
  if (!linha) return { tipo: "ausente" };

  const documento = converter(linha);
  return documento ? { tipo: "ok", documento } : { tipo: "ausente" };
}
