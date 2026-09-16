/**
 * Etapas de contrato e pagamento — cliente de navegador.
 *
 * O navegador envia o MÍNIMO: qual intenção, qual pedido e, no cartão, quantas
 * parcelas. Documento, versão, hash, valor, método, fidelidade e prazo são
 * todos derivados no servidor, e a resposta é a única fonte do que a tela
 * mostra. Nada aqui guarda estado em armazenamento do navegador.
 */

import { supabase } from "../lib/supabase";

export type TermosVigentes =
  | { tipo: "publicados"; version: string; title: string; content: string | null; contentUrl: string | null }
  | { tipo: "ausentes" };

/** Documento vigente pelo resolvedor canônico. O navegador não escolhe id nem hash. */
export async function obterTermosVigentes(): Promise<TermosVigentes> {
  if (!supabase) return { tipo: "ausentes" };
  const { data, error } = await supabase.rpc("get_current_legal_documents");
  if (error || !Array.isArray(data)) return { tipo: "ausentes" };
  const d = (data as Array<Record<string, unknown>>).find(
    (x) => x.doc_type === "commercial_order_terms"
  );
  if (!d) return { tipo: "ausentes" };
  return {
    tipo: "publicados",
    version: String(d.version ?? ""),
    title: String(d.title ?? ""),
    content: typeof d.content === "string" ? d.content : null,
    contentUrl: typeof d.content_url === "string" ? d.content_url : null,
  };
}

type Resp = Record<string, unknown>;
export type Falha = { tipo: "erro"; codigo: string };

async function rpc(fn: string, args: Record<string, unknown>): Promise<Resp | Falha> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { tipo: "erro", codigo: "rpc_error" };
  const o = (data ?? {}) as Resp;
  if (o.ok !== true) {
    return { tipo: "erro", codigo: typeof o.reason === "string" ? o.reason : "unexpected_error" };
  }
  return o;
}

/** `Resp` e um mapa aberto, entao `"tipo" in r` nao estreita. Guarda explicita. */
export function ehFalha(r: Resp | Falha): r is Falha {
  return (r as Falha).tipo === "erro";
}

export const avancarParaContrato = (intentId: string) =>
  rpc("advance_checkout_intent_to_contract", { p_intent_id: intentId });

export const aceitarTermos = (intentId: string) =>
  rpc("accept_commercial_order_terms", { p_intent_id: intentId });

export const finalizarPedido = (intentId: string) =>
  rpc("finalize_commercial_order_from_intent", { p_intent_id: intentId });

export const lerEstadoPagamento = (paymentId: string) =>
  rpc("get_my_commercial_payment_status", { p_payment_id: paymentId });

export type Pagamento = {
  paymentId: string;
  status: string;
  paymentMethod: "pix" | "credit_card";
  amountCents: number;
  expiresAt: string;
  pixCopyPaste: string | null;
  pixQrCodeUrl: string | null;
  checkoutUrl: string | null;
};

export type ResultadoPagamento =
  | { tipo: "ok"; pagamento: Pagamento }
  | Falha;

/**
 * Cria (ou recupera) o pagamento pelo endpoint de servidor. Só o pedido e,
 * no cartão, o número de parcelas. Valor, método e prazo não são enviados
 * porque o navegador não tem autoridade sobre nenhum deles.
 */
export async function criarPagamento(params: {
  orderId: string;
  installments?: number;
}): Promise<ResultadoPagamento> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { tipo: "erro", codigo: "not_authenticated" };

  let resp: Response;
  try {
    resp = await fetch("/api/payments/create", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        order_id: params.orderId,
        ...(params.installments === undefined ? {} : { installments: params.installments }),
      }),
    });
  } catch {
    return { tipo: "erro", codigo: "network_error" };
  }

  let corpo: Resp | null = null;
  try {
    corpo = (await resp.json()) as Resp;
  } catch {
    return { tipo: "erro", codigo: "unexpected_error" };
  }
  if (!resp.ok || corpo?.ok !== true) {
    return {
      tipo: "erro",
      codigo: typeof corpo?.code === "string" ? corpo.code : "unexpected_error",
    };
  }
  return {
    tipo: "ok",
    pagamento: {
      paymentId: String(corpo.payment_id),
      status: String(corpo.status),
      paymentMethod: corpo.payment_method as "pix" | "credit_card",
      amountCents: Number(corpo.amount_cents),
      expiresAt: String(corpo.expires_at),
      pixCopyPaste: typeof corpo.pix_copy_paste === "string" ? corpo.pix_copy_paste : null,
      pixQrCodeUrl: typeof corpo.pix_qr_code_url === "string" ? corpo.pix_qr_code_url : null,
      checkoutUrl: typeof corpo.checkout_url === "string" ? corpo.checkout_url : null,
    },
  };
}

/** Estados terminais da migration 34. A tela para de consultar neles. */
export const ESTADOS_TERMINAIS = [
  "paid",
  "expired",
  "cancelled",
  "failed",
  "late_unreconciled",
] as const;

export function ehTerminal(status: string): boolean {
  return (ESTADOS_TERMINAIS as readonly string[]).includes(status);
}
