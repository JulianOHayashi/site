import { supabase } from "../lib/supabase";
import { isCommercialNicheCode, nicheByCode } from "../domain/commercial/niches";

/**
 * Imagem de personalização do PEDIDO de exclusividade (backend M2 / R7).
 *
 * Reutiliza integralmente o backend existente
 * (migration 20260822125000_m2_customization_image.sql):
 *   bucket PRIVADO `partner-customization-images` · path derivado no servidor
 *   · request_customization_image_path · register_customization_image
 *   · order_has_customization_image (gate do R9) · histórico append-only.
 *
 * Regras deste cliente, todas em defesa — a autoridade é o servidor:
 *   - o caminho vem SEMPRE de request_customization_image_path;
 *   - upload com upsert:false (nunca sobrescreve objeto);
 *   - register só depois de upload bem-sucedido;
 *   - falha no register NÃO apaga o objeto (sem DELETE no cliente, por desenho);
 *   - leitura da imagem atual por signed URL curta, nunca URL pública;
 *   - nenhuma mensagem do banco/Storage chega ao usuário;
 *   - checksum não é enviado: o backend não o verifica e não há
 *     infraestrutura confiável para isso — enviar seria um checksum de fachada.
 */

export const TIPOS_ACEITOS = ["image/jpeg", "image/png", "image/webp"] as const;
export const ACCEPT_ATTR = TIPOS_ACEITOS.join(",");
export const TAMANHO_MAXIMO = 10 * 1024 * 1024; // 10 MiB, igual ao bucket e à RPC
/** Validade da URL de exibição. Não é persistida; renova a cada carregamento. */
export const VALIDADE_URL_SEG = 300;

export type ErroArquivo = "tipo" | "vazio" | "tamanho";

/** Validação local antes de qualquer chamada. O servidor revalida tudo. */
export function validarArquivo(arquivo: File): { ok: true } | { ok: false; erro: ErroArquivo } {
  if (!(TIPOS_ACEITOS as readonly string[]).includes(arquivo.type)) return { ok: false, erro: "tipo" };
  if (arquivo.size <= 0) return { ok: false, erro: "vazio" };
  if (arquivo.size > TAMANHO_MAXIMO) return { ok: false, erro: "tamanho" };
  return { ok: true };
}

export const MENSAGEM_ARQUIVO: Record<ErroArquivo, string> = {
  tipo: "Formato não aceito. Envie uma imagem JPG, PNG ou WebP.",
  vazio: "O arquivo está vazio. Escolha outra imagem.",
  tamanho: "A imagem passa de 10 MB. Escolha um arquivo menor.",
};

/** Motivos do backend (e do cliente) → mensagens fixas e seguras. */
const MENSAGENS_MOTIVO: Record<string, string> = {
  not_authenticated: "Sua sessão expirou. Entre novamente para enviar a imagem.",
  not_found: "Pedido não encontrado.",
  not_authorized: "Apenas o responsável pela empresa pode enviar a imagem deste pedido.",
  order_cancelled: "Este pedido foi cancelado e não aceita mais imagem.",
  invalid_path: "Não foi possível registrar a imagem. Tente enviar novamente.",
  storage_object_not_found: "O envio não foi concluído. Tente enviar novamente.",
  storage_object_not_owned: "Não foi possível registrar a imagem. Tente enviar novamente.",
  invalid_metadata: "Não foi possível ler os dados da imagem. Tente outro arquivo.",
  invalid_mime: "Formato não aceito. Envie uma imagem JPG, PNG ou WebP.",
  invalid_size: "A imagem precisa ter até 10 MB.",
  upload_failed: "Falha ao enviar a imagem. Verifique a conexão e tente novamente.",
  not_configured: "Envio indisponível no momento.",
};
const MENSAGEM_INESPERADA = "Não foi possível concluir agora. Tente novamente em instantes.";

export function mensagemDeMotivo(motivo: string): string {
  return MENSAGENS_MOTIVO[motivo] ?? MENSAGEM_INESPERADA;
}

export function tamanhoLegivel(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toLocaleString("pt-BR", { maximumFractionDigits: 0 })} KB`;
  return `${(bytes / (1024 * 1024)).toLocaleString("pt-BR", { maximumFractionDigits: 1 })} MB`;
}

/* --------------------------------- pedidos --------------------------------- */

export type PedidoResumo = {
  orderId: string;
  nicho: string;
  temImagem: boolean;
  statusPagamento: string | null;
};

/**
 * Pedidos não cancelados da empresa, via get_my_company_commercial_summary.
 * O bloco `commercial` só existe para owner/admin; para manager vem null e
 * esta função devolve `sem_acesso` — a UI não oferece nada comercial.
 */
export async function listarPedidosDaEmpresa(
  companyId: string
): Promise<{ tipo: "ok"; pedidos: PedidoResumo[] } | { tipo: "sem_acesso" } | { tipo: "erro" }> {
  if (!supabase) return { tipo: "erro" };
  const { data, error } = await supabase.rpc("get_my_company_commercial_summary", {
    p_company_id: companyId,
  });
  if (error || !data || typeof data !== "object") return { tipo: "erro" };
  const o = data as { ok?: boolean; reason?: string; commercial?: unknown };
  if (o.ok !== true) return o.reason === "not_authorized" ? { tipo: "sem_acesso" } : { tipo: "erro" };
  if (o.commercial === null || o.commercial === undefined) return { tipo: "sem_acesso" };
  if (!Array.isArray(o.commercial)) return { tipo: "erro" };
  const pedidos: PedidoResumo[] = [];
  for (const item of o.commercial) {
    if (!item || typeof item !== "object") return { tipo: "erro" };
    const p = item as Record<string, unknown>;
    if (typeof p.order_id !== "string") return { tipo: "erro" };
    const codigo = typeof p.niche_code === "string" ? p.niche_code : "";
    pedidos.push({
      orderId: p.order_id,
      nicho: isCommercialNicheCode(codigo) ? nicheByCode(codigo).displayName : "Pedido de exclusividade",
      temImagem: p.has_customization_image === true,
      statusPagamento: typeof p.payment_status === "string" ? p.payment_status : null,
    });
  }
  return { tipo: "ok", pedidos };
}

/* ------------------------------ imagem atual ------------------------------- */

export type ImagemAtual = {
  url: string;
  mimeType: string;
  byteSize: number;
  registradaEm: string;
};

/**
 * Imagem CORRENTE do pedido. A RLS (coci_owner_select) já restringe a linha
 * ao owner/admin; o Storage (m2_custom_img_owner_select) restringe a signed
 * URL. Nada é persistido no navegador.
 */
export async function obterImagemAtual(
  orderId: string
): Promise<{ tipo: "ok"; imagem: ImagemAtual } | { tipo: "nenhuma" } | { tipo: "erro" }> {
  if (!supabase) return { tipo: "erro" };
  const { data, error } = await supabase
    .from("commercial_order_customization_images")
    .select("storage_bucket, storage_path, mime_type, byte_size, registered_at")
    .eq("order_id", orderId)
    .eq("is_current", true)
    .eq("status", "active")
    .maybeSingle();
  if (error) return { tipo: "erro" };
  if (!data) return { tipo: "nenhuma" };
  const linha = data as {
    storage_bucket: string;
    storage_path: string;
    mime_type: string;
    byte_size: number;
    registered_at: string;
  };
  const assinada = await supabase.storage
    .from(linha.storage_bucket)
    .createSignedUrl(linha.storage_path, VALIDADE_URL_SEG);
  if (assinada.error || !assinada.data?.signedUrl) return { tipo: "erro" };
  return {
    tipo: "ok",
    imagem: {
      url: assinada.data.signedUrl,
      mimeType: linha.mime_type,
      byteSize: linha.byte_size,
      registradaEm: linha.registered_at,
    },
  };
}

/* --------------------------------- envio ----------------------------------- */

export type ResultadoEnvio = { tipo: "ok"; imageId: string } | { tipo: "erro"; motivo: string };

/**
 * Envio (e substituição): path do servidor → upload sem upsert → registro.
 * Cada envio usa um path NOVO devolvido pelo servidor; a versão anterior vira
 * histórico no registro, e nenhum objeto antigo é sobrescrito ou apagado.
 */
export async function enviarImagemPersonalizacao(orderId: string, arquivo: File): Promise<ResultadoEnvio> {
  if (!supabase) return { tipo: "erro", motivo: "not_configured" };
  const local = validarArquivo(arquivo);
  if (!local.ok) {
    return { tipo: "erro", motivo: local.erro === "tipo" ? "invalid_mime" : "invalid_size" };
  }

  // 1. Caminho derivado no servidor.
  const pedido = await supabase.rpc("request_customization_image_path", { p_order_id: orderId });
  if (pedido.error || !pedido.data || typeof pedido.data !== "object") {
    return { tipo: "erro", motivo: "unexpected" };
  }
  const caminho = pedido.data as { ok?: boolean; reason?: string; bucket?: unknown; storage_path?: unknown };
  if (caminho.ok !== true) return { tipo: "erro", motivo: caminho.reason ?? "unexpected" };
  if (typeof caminho.bucket !== "string" || typeof caminho.storage_path !== "string") {
    return { tipo: "erro", motivo: "unexpected" };
  }

  // 2. Upload no bucket/path EXATOS do servidor, sem sobrescrever nada.
  const envio = await supabase.storage.from(caminho.bucket).upload(caminho.storage_path, arquivo, {
    upsert: false,
    contentType: arquivo.type,
  });
  if (envio.error) return { tipo: "erro", motivo: "upload_failed" };

  // 3. Registro. MIME e tamanho autoritativos vêm do Storage; estes são fallback.
  const registro = await supabase.rpc("register_customization_image", {
    p_order_id: orderId,
    p_storage_path: caminho.storage_path,
    p_mime_type: arquivo.type,
    p_byte_size: arquivo.size,
  });
  if (registro.error || !registro.data || typeof registro.data !== "object") {
    // Sem DELETE do objeto: decisão do modelo (o cliente não tem policy de DELETE).
    return { tipo: "erro", motivo: "unexpected" };
  }
  const r = registro.data as { ok?: boolean; reason?: string; image_id?: unknown };
  if (r.ok !== true) return { tipo: "erro", motivo: r.reason ?? "unexpected" };
  return { tipo: "ok", imageId: typeof r.image_id === "string" ? r.image_id : "" };
}
