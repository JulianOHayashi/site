import { supabase } from "../lib/supabase";
import { validarArquivo } from "./customizationImageService";

/**
 * Solicitação de alteração de frase ou arte (R4.2, migration 20261116120000).
 *
 * Reaproveita o bucket privado e as políticas de Storage da imagem de
 * personalização: o caminho vem do servidor (artwork_change_image_path),
 * upload sem upsert, registro pela RPC, que lê MIME e tamanho do Storage.
 *
 * O navegador NÃO forma preço: o valor exibido e o valor aceito são os do
 * orçamento registrado pela SmallFlags (custo do fornecedor, sem margem). O
 * aceite envia de volta exatamente esse valor; o servidor confere.
 *
 * A solicitação não troca a arte em execução: vale na próxima campanha ou,
 * na atual, só com exceção da SmallFlags. Cobrança e produção externas não
 * fazem parte deste fluxo (indisponíveis aqui).
 *
 * R4.2.1 (migration 20261116180000): o orçamento é ITEMIZADO e preso a um
 * documento do fornecedor ATESTADO pelo servidor (SHA-256 calculado sobre os
 * bytes). A leitura falha fechada se os itens não fecharem com o total ou se
 * o documento não estiver atestado e válido; o aceite devolve o SHA-256 do
 * documento. "Produção autorizada" não é prontidão para a renovação.
 */

export type StatusSolicitacao =
  | "draft" | "submitted" | "under_review" | "quoted" | "accepted"
  | "production_authorized" | "rejected" | "cancelled";
export type AlvoCampanha = "next_campaign" | "current_campaign";

export type OrcamentoArte = {
  quoteId: string;
  numero: number;
  status: "open" | "accepted" | "superseded";
  fornecedor: string;
  documentoFornecedor: string;
  escopo: string;
  pecas: number;
  /** Só com item único (preço linear); preço não linear vem nos itens. */
  custoUnitarioCentavos: number | null;
  totalFornecedorCentavos: number;
  /** Valor ao parceiro: igual ao total do fornecedor (o servidor gera). */
  valorParceiroCentavos: number;
  tetoCentavos: number;
  naoIncluidos: string[];
  itens: ItemOrcamento[];
  documento: DocumentoFornecedor;
};

export type ItemOrcamento = {
  linha: number;
  descricao: string;
  localizacaoNoDocumento: string;
  quantidade: number;
  unitarioCentavos: number;
  totalLinhaCentavos: number;
};

export type DocumentoFornecedor = {
  documentId: string;
  bucket: string;
  caminho: string;
  sha256: string;
  tamanhoBytes: number;
};

export type VersaoArte = { versionId: string; numero: number; frase: string | null; registradaEm: string };

export type SolicitacaoArte = {
  requestId: string;
  status: StatusSolicitacao;
  rowVersion: number;
  alvo: AlvoCampanha;
  frase: string | null;
  excecaoAprovada: boolean;
  valorAceitoCentavos: number | null;
  motivoEncerramento: string | null;
  versoes: VersaoArte[];
  orcamento: OrcamentoArte | null;
  /** Sequência da campanha (exclusividade) a que a alteração se destina. */
  campanhaAlvo: number | null;
  /** Pronta para a renovação (cobrança e fabricação verificadas). Hoje sempre falso. */
  pronta: boolean;
};

export type ListaSolicitacoes = {
  podeSolicitar: boolean;
  papel: "partner_owner" | "partner_member" | "site_admin";
  solicitacoes: SolicitacaoArte[];
};

export const ROTULO_STATUS: Record<StatusSolicitacao, string> = {
  draft: "Rascunho",
  submitted: "Enviada para análise",
  under_review: "Em análise pela SmallFlags",
  quoted: "Orçamento disponível",
  accepted: "Orçamento aceito",
  production_authorized: "Produção autorizada",
  rejected: "Recusada",
  cancelled: "Cancelada",
};

export const ROTULO_NAO_INCLUIDO: Record<string, string> = {
  frete: "Frete",
  criacao_de_arte: "Criação de arte",
  instalacao: "Instalação",
  tributos: "Tributos",
  servicos: "Outros serviços",
};

const ABERTOS: StatusSolicitacao[] = ["draft", "submitted", "under_review", "quoted", "accepted"];
export const estaAberta = (s: SolicitacaoArte) => ABERTOS.includes(s.status);

const MENSAGENS: Record<string, string> = {
  not_authenticated: "Sua sessão expirou. Entre novamente.",
  not_found: "Solicitação ou pedido não encontrado.",
  not_authorized: "Somente o responsável pela empresa solicita a alteração e aceita o orçamento.",
  order_cancelled: "Este pedido foi cancelado.",
  invalid_target: "Escolha a campanha da alteração.",
  invalid_phrase: "A frase precisa ter de 1 a 280 caracteres.",
  artwork_change_already_open: "Já existe uma solicitação em andamento para esta posição.",
  artwork_change_already_exists_for_campaign: "Já existe uma solicitação para a próxima campanha desta posição.",
  base_order_not_latest: "A alteração parte do pedido mais recente desta posição.",
  base_campaign_missing: "Este pedido não está ligado a uma campanha.",
  target_campaign_unavailable: "A próxima campanha desta posição já foi contratada por outra empresa.",
  supplier_document_mismatch: "O documento do orçamento mudou. Recarregue a página.",
  supplier_document_not_valid: "O documento do fornecedor não pôde ser conferido. A SmallFlags vai reenviar o orçamento.",
  artwork_version_required: "Envie a arte antes de mandar para análise.",
  stale_request: "A solicitação mudou enquanto você estava nesta tela. Recarregue para ver a situação atual.",
  invalid_status: "Esta ação não está disponível na situação atual da solicitação.",
  invalid_path: "Não foi possível registrar a arte. Tente enviar novamente.",
  invalid_sha256: "Não foi possível conferir o arquivo. Tente novamente.",
  storage_object_not_found: "O envio não foi concluído. Tente enviar novamente.",
  storage_object_not_owned: "Não foi possível registrar a arte. Tente enviar novamente.",
  invalid_metadata: "Não foi possível ler os dados da imagem. Tente outro arquivo.",
  invalid_mime: "Formato não aceito. Envie uma imagem JPG, PNG ou WebP.",
  invalid_size: "A imagem precisa ter até 10 MB.",
  path_already_registered: "Este envio já foi registrado. Recarregue a página.",
  quote_not_current: "Este orçamento não é mais o vigente. Recarregue a página.",
  accepted_total_mismatch: "O valor aceito não confere com o orçamento. Recarregue a página.",
  reason_required: "Informe o motivo do cancelamento.",
  upload_failed: "Falha ao enviar a arte. Verifique a conexão e tente novamente.",
  hash_unavailable: "Este navegador não conseguiu conferir o arquivo. Tente outro navegador.",
  not_configured: "Indisponível no momento.",
};
export function mensagemArte(motivo: string): string {
  return MENSAGENS[motivo] ?? "Não foi possível concluir agora. Tente novamente em instantes.";
}

type Resultado<T> = { tipo: "ok"; valor: T } | { tipo: "erro"; motivo: string };

async function chamar(nome: string, args: Record<string, unknown>): Promise<Resultado<Record<string, unknown>>> {
  if (!supabase) return { tipo: "erro", motivo: "not_configured" };
  const r = await supabase.rpc(nome, args);
  if (r.error || !r.data || typeof r.data !== "object") return { tipo: "erro", motivo: "unexpected" };
  const d = r.data as Record<string, unknown>;
  if (d.ok !== true) return { tipo: "erro", motivo: typeof d.reason === "string" ? d.reason : "unexpected" };
  return { tipo: "ok", valor: d };
}

const inteiro = (v: unknown): number | null => (typeof v === "number" && Number.isSafeInteger(v) ? v : null);
const texto = (v: unknown): string | null => (typeof v === "string" ? v : null);
const SHA256 = /^[0-9a-f]{64}$/;

function lerItens(v: unknown): ItemOrcamento[] | undefined {
  if (!Array.isArray(v) || v.length === 0) return undefined;
  const itens: ItemOrcamento[] = [];
  for (const x of v) {
    if (!x || typeof x !== "object") return undefined;
    const i = x as Record<string, unknown>;
    const it = {
      linha: inteiro(i.line_no), descricao: texto(i.description), localizacaoNoDocumento: texto(i.document_locator),
      quantidade: inteiro(i.quantity), unitarioCentavos: inteiro(i.unit_cost_cents), totalLinhaCentavos: inteiro(i.line_total_cents),
    };
    if (Object.values(it).some((c) => c === null) || i.kind !== "flag_pieces") return undefined;
    // Falha fechada: cada linha é quantidade x unitário.
    if (it.quantidade! <= 0 || it.unitarioCentavos! <= 0 || it.totalLinhaCentavos !== it.quantidade! * it.unitarioCentavos!) return undefined;
    itens.push(it as ItemOrcamento);
  }
  return itens;
}

function lerDocumento(v: unknown): DocumentoFornecedor | undefined {
  if (!v || typeof v !== "object") return undefined;
  const d = v as Record<string, unknown>;
  const doc = {
    documentId: texto(d.document_id), bucket: texto(d.storage_bucket), caminho: texto(d.storage_path),
    sha256: texto(d.sha256), tamanhoBytes: inteiro(d.byte_size),
  };
  if (Object.values(doc).some((c) => c === null)) return undefined;
  // Falha fechada: só documento ATESTADO pelo servidor e ainda válido.
  if (d.attested !== true || d.valid !== true || !SHA256.test(doc.sha256!)) return undefined;
  return doc as DocumentoFornecedor;
}

function lerOrcamento(q: unknown): OrcamentoArte | null | undefined {
  if (q === null || q === undefined) return null;
  if (typeof q !== "object") return undefined;
  const o = q as Record<string, unknown>;
  const campos = {
    quoteId: texto(o.quote_id), numero: inteiro(o.quote_no), status: texto(o.status),
    fornecedor: texto(o.supplier_name), documentoFornecedor: texto(o.supplier_document_reference),
    escopo: texto(o.scope), pecas: inteiro(o.pieces_count),
    totalFornecedorCentavos: inteiro(o.supplier_total_cents), valorParceiroCentavos: inteiro(o.partner_charge_cents),
    tetoCentavos: inteiro(o.cap_cents),
  };
  if (Object.values(campos).some((v) => v === null)) return undefined;
  if (!["open", "accepted", "superseded"].includes(campos.status!)) return undefined;
  // Falha fechada: o valor ao parceiro TEM de ser o custo do fornecedor.
  if (campos.valorParceiroCentavos !== campos.totalFornecedorCentavos) return undefined;
  if (campos.valorParceiroCentavos! > campos.tetoCentavos!) return undefined;
  const itens = lerItens(o.items);
  const documento = lerDocumento(o.supplier_document);
  if (!itens || !documento) return undefined;
  // Falha fechada: soma dos itens = total; soma das quantidades = peças.
  if (itens.reduce((a, i) => a + i.totalLinhaCentavos, 0) !== campos.totalFornecedorCentavos) return undefined;
  if (itens.reduce((a, i) => a + i.quantidade, 0) !== campos.pecas) return undefined;
  const unit = o.supplier_unit_cost_cents === null ? null : inteiro(o.supplier_unit_cost_cents);
  if (itens.length === 1 ? unit !== itens[0].unitarioCentavos : unit !== null) return undefined;
  const nao = Array.isArray(o.excluded_items) ? o.excluded_items.filter((x): x is string => typeof x === "string") : [];
  return {
    ...(campos as Omit<OrcamentoArte, "status" | "naoIncluidos" | "itens" | "documento" | "custoUnitarioCentavos">),
    custoUnitarioCentavos: unit, status: campos.status as OrcamentoArte["status"], naoIncluidos: nao, itens, documento,
  };
}

/** Lê as solicitações do pedido. Resposta incoerente = erro (nada é exibido). */
export async function listarSolicitacoes(orderId: string): Promise<Resultado<ListaSolicitacoes>> {
  const r = await chamar("artwork_change_requests_for_order", { p_order_id: orderId });
  if (r.tipo === "erro") return r;
  const d = r.valor;
  if (!["partner_owner", "partner_member", "site_admin"].includes(String(d.viewer_role)) || !Array.isArray(d.requests)) {
    return { tipo: "erro", motivo: "unexpected" };
  }
  const solicitacoes: SolicitacaoArte[] = [];
  for (const x of d.requests as unknown[]) {
    if (!x || typeof x !== "object") return { tipo: "erro", motivo: "unexpected" };
    const s = x as Record<string, unknown>;
    const orc = lerOrcamento(s.quote);
    const id = texto(s.request_id), st = texto(s.status), rv = inteiro(s.row_version), alvo = texto(s.target_campaign);
    if (orc === undefined || !id || !st || rv === null || !alvo || !(st in ROTULO_STATUS)
        || !["next_campaign", "current_campaign"].includes(alvo) || !Array.isArray(s.versions)) {
      return { tipo: "erro", motivo: "unexpected" };
    }
    solicitacoes.push({
      requestId: id,
      status: st as StatusSolicitacao,
      rowVersion: rv,
      alvo: alvo as AlvoCampanha,
      frase: texto(s.phrase_text),
      excecaoAprovada: s.exception_approved === true,
      valorAceitoCentavos: inteiro(s.accepted_total_cents),
      motivoEncerramento: texto(s.closed_reason),
      versoes: (s.versions as Array<Record<string, unknown>>).map((v) => ({
        versionId: String(v.version_id), numero: Number(v.version_no),
        frase: texto(v.phrase_text), registradaEm: String(v.registered_at),
      })),
      orcamento: orc,
      campanhaAlvo: inteiro(s.target_sequence_number),
      pronta: typeof s.readiness === "object" && s.readiness !== null
        && (s.readiness as Record<string, unknown>).ready === true,
    });
  }
  return {
    tipo: "ok",
    valor: {
      papel: d.viewer_role as ListaSolicitacoes["papel"],
      podeSolicitar: d.can_request === true,
      solicitacoes,
    },
  };
}

export async function criarSolicitacao(orderId: string, alvo: AlvoCampanha, frase: string): Promise<Resultado<string>> {
  const r = await chamar("artwork_change_request_create", {
    p_order_id: orderId, p_target_campaign: alvo, p_phrase_text: frase.trim() || null, p_note: null,
  });
  if (r.tipo === "erro") return r;
  return typeof r.valor.request_id === "string" ? { tipo: "ok", valor: r.valor.request_id } : { tipo: "erro", motivo: "unexpected" };
}

async function sha256Hex(arquivo: File): Promise<string | null> {
  try {
    const buf: ArrayBuffer = typeof arquivo.arrayBuffer === "function"
      ? await arquivo.arrayBuffer()
      : await new Promise<ArrayBuffer>((ok, falha) => {
          const leitor = new FileReader();
          leitor.onload = () => ok(leitor.result as ArrayBuffer);
          leitor.onerror = () => falha(leitor.error);
          leitor.readAsArrayBuffer(arquivo);
        });
    // Cópia em um Uint8Array deste contexto (ambientes com mais de um realm).
    const bytes = new Uint8Array(buf.byteLength);
    bytes.set(new Uint8Array(buf));
    const h = await globalThis.crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, "0")).join("");
  } catch {
    return null;
  }
}

/** Caminho do servidor → upload sem sobrescrever → registro da versão. */
export async function enviarArte(requestId: string, rowVersion: number, arquivo: File, frase: string): Promise<Resultado<null>> {
  if (!supabase) return { tipo: "erro", motivo: "not_configured" };
  const local = validarArquivo(arquivo);
  if (!local.ok) return { tipo: "erro", motivo: local.erro === "tipo" ? "invalid_mime" : "invalid_size" };
  const hash = await sha256Hex(arquivo);
  if (!hash) return { tipo: "erro", motivo: "hash_unavailable" };
  const caminho = await chamar("artwork_change_image_path", { p_request_id: requestId });
  if (caminho.tipo === "erro") return caminho;
  const { bucket, storage_path } = caminho.valor;
  if (typeof bucket !== "string" || typeof storage_path !== "string") return { tipo: "erro", motivo: "unexpected" };
  const envio = await supabase.storage.from(bucket).upload(storage_path, arquivo, { upsert: false, contentType: arquivo.type });
  if (envio.error) return { tipo: "erro", motivo: "upload_failed" };
  const reg = await chamar("artwork_change_register_version", {
    p_request_id: requestId, p_expected_row_version: rowVersion, p_storage_path: storage_path,
    p_sha256: hash, p_phrase_text: frase.trim() || null,
  });
  return reg.tipo === "erro" ? reg : { tipo: "ok", valor: null };
}

export async function enviarParaAnalise(requestId: string, rowVersion: number): Promise<Resultado<null>> {
  const r = await chamar("artwork_change_submit", { p_request_id: requestId, p_expected_row_version: rowVersion });
  return r.tipo === "erro" ? r : { tipo: "ok", valor: null };
}

/** Aceite: envia o valor DO SERVIDOR (orçamento), nunca um valor digitado. */
export async function aceitarOrcamento(s: SolicitacaoArte): Promise<Resultado<null>> {
  if (!s.orcamento || s.orcamento.status !== "open") return { tipo: "erro", motivo: "quote_not_current" };
  const r = await chamar("artwork_change_accept_quote", {
    p_request_id: s.requestId, p_expected_row_version: s.rowVersion,
    p_quote_id: s.orcamento.quoteId, p_accepted_total_cents: s.orcamento.valorParceiroCentavos,
    p_supplier_document_sha256: s.orcamento.documento.sha256,
  });
  return r.tipo === "erro" ? r : { tipo: "ok", valor: null };
}

/** Link temporário do documento original do fornecedor (bucket privado). */
export async function urlDocumentoFornecedor(doc: DocumentoFornecedor): Promise<Resultado<string>> {
  if (!supabase) return { tipo: "erro", motivo: "not_configured" };
  const r = await supabase.storage.from(doc.bucket).createSignedUrl(doc.caminho, 120);
  if (r.error || !r.data?.signedUrl) return { tipo: "erro", motivo: "unexpected" };
  return { tipo: "ok", valor: r.data.signedUrl };
}

export async function cancelarSolicitacao(requestId: string, rowVersion: number, motivo: string): Promise<Resultado<null>> {
  const r = await chamar("artwork_change_cancel", {
    p_request_id: requestId, p_expected_row_version: rowVersion, p_reason: motivo.trim(),
  });
  return r.tipo === "erro" ? r : { tipo: "ok", valor: null };
}
