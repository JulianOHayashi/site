/**
 * NÚCLEO DE PAGAMENTO COMERCIAL. EXCLUSIVAMENTE DE SERVIDOR.
 *
 * Separado dos adaptadores HTTP de propósito: aqui não há `process`, `req`
 * nem `res`, então a sequência inteira — autorização, abertura local,
 * chamada ao provedor, conciliação — é provável sem servidor de pé e com o
 * provedor sempre simulado.
 *
 * DUAS IDENTIDADES DE BANCO, E A DISTINÇÃO IMPORTA
 *   `db do usuário`   anon key + Bearer da sessão do titular. Abre a
 *                     tentativa local; RLS e os grants decidem.
 *   `db privilegiado` service_role. Só grava identificadores do provedor e
 *                     concilia — as duas RPCs que o domínio marcou como
 *                     `service_role` porque não têm ator humano.
 *
 * A identidade privilegiada nunca decide autorização comercial: quem pode
 * pagar já foi decidido pela RPC que roda COMO O USUÁRIO.
 *
 * POLÍTICA DE PARCELAMENTO
 * 1 a 6 parcelas, todas com o MESMO total contratual, juros zero para o
 * comprador. O custo do provedor é despesa operacional da BDFlow e não toca
 * `economic_value_cents`, o instantâneo do pedido nem o contrato aceito.
 * Nenhuma taxa ou MDR aparece neste código.
 */

import {
  MAX_INSTALLMENTS,
  MIN_INSTALLMENTS,
  PagarmeConfigError,
  PagarmeCustomerDataError,
  montarClienteProvedor,
  type ContextoCliente,
  type PagarmeClient,
} from "./pagarmeClient.js";

export type Db = {
  rpc: (
    fn: string,
    args: Record<string, unknown>
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
};

export class PaymentError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(code: string, status: number) {
    super(code);
    this.name = "PaymentError";
    this.code = code;
    this.status = status;
  }
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type CriarPagamentoInput = {
  orderId: unknown;
  /** Só no cartão. 1..6. No Pix é ignorado — o método é derivado. */
  installments?: unknown;
};

/** Resposta ao navegador: pobre de propósito. */
export type CriarPagamentoResult = {
  ok: true;
  payment_id: string;
  status: string;
  payment_method: "pix" | "credit_card";
  amount_cents: number;
  expires_at: string;
  already: boolean;
  pix_copy_paste?: string | null;
  pix_qr_code_url?: string | null;
  checkout_url?: string | null;
  installments?: number;
};

type Abertura = {
  ok: boolean;
  reason?: string;
  already?: boolean;
  payment_id?: string;
  status?: string;
  payment_method?: "pix" | "credit_card";
  amount_cents?: number;
  expires_at?: string;
  idempotency_key?: string;
  provider_order_id?: string | null;
  provider_charge_id?: string | null;
  provider_payment_link_id?: string | null;
};

function exigirUuid(v: unknown, code: string): string {
  if (typeof v !== "string" || !UUID_RE.test(v)) throw new PaymentError(code, 400);
  return v;
}

/**
 * Parcelas escolhidas pelo comprador: 1..6 e nada além. Zero e sete reprovam
 * antes de qualquer rede.
 */
export function exigirParcelas(v: unknown): number {
  if (typeof v !== "number" || !Number.isInteger(v)) {
    throw new PaymentError("invalid_installments", 400);
  }
  if (v < MIN_INSTALLMENTS || v > MAX_INSTALLMENTS) {
    throw new PaymentError("invalid_installments", 400);
  }
  return v;
}

export async function criarPagamento(
  input: CriarPagamentoInput,
  accessToken: string | null,
  deps: {
    criarDbDoUsuario: (token: string) => Db;
    dbPrivilegiado: () => Db;
    provedor: () => PagarmeClient;
  }
): Promise<CriarPagamentoResult> {
  const orderId = exigirUuid(input.orderId, "invalid_order");
  if (!accessToken || accessToken.trim() === "") {
    throw new PaymentError("not_authenticated", 401);
  }

  // ---- 1. abertura LOCAL, como o usuário. Se o estado comercial não
  // permite, o provedor nem é contactado.
  const dbUser = deps.criarDbDoUsuario(accessToken);
  const { data, error } = await dbUser.rpc("open_commercial_payment_attempt", {
    p_order_id: orderId,
  });
  if (error) throw new PaymentError("payment_open_failed", 502);
  const a = (data ?? {}) as Abertura;
  if (a.ok !== true) {
    const motivo = typeof a.reason === "string" ? a.reason : "payment_open_failed";
    const status =
      motivo === "not_authenticated" ? 401
      : motivo === "not_company_owner" ? 403
      : motivo === "already_paid" ? 409
      : 409;
    throw new PaymentError(motivo, status);
  }
  if (!a.payment_id || !a.payment_method || !a.amount_cents || !a.expires_at
      || !a.idempotency_key) {
    throw new PaymentError("payment_open_malformed", 502);
  }

  // Parcelas só fazem sentido no cartão, e o método foi DERIVADO da
  // fidelidade pelo servidor — o navegador não escolhe entre Pix e cartão.
  const parcelas =
    a.payment_method === "credit_card" ? exigirParcelas(input.installments) : undefined;

  // ---- 2. recurso já criado no provedor? Devolve o mesmo, sem criar outro.
  // É isto que sobrevive a duplo clique, refresh e retentativa de HTTP.
  if (a.already === true &&
      (a.provider_charge_id || a.provider_payment_link_id || a.provider_order_id)) {
    return {
      ok: true, already: true,
      payment_id: a.payment_id, status: a.status ?? "pending",
      payment_method: a.payment_method, amount_cents: a.amount_cents,
      expires_at: a.expires_at,
      ...(a.payment_method === "credit_card"
        ? { checkout_url: null, installments: parcelas }
        : { pix_copy_paste: null, pix_qr_code_url: null }),
    };
  }

  // ---- 3. provedor. Falha de credencial vira erro de configuração, nunca
  // requisição sem autenticação.
  let cliente: PagarmeClient;
  try {
    cliente = deps.provedor();
  } catch (e) {
    if (e instanceof PagarmeConfigError) {
      throw new PaymentError("payment_provider_not_configured", 503);
    }
    throw new PaymentError("payment_provider_not_configured", 503);
  }

  const abertura = {
    paymentId: a.payment_id,
    paymentMethod: a.payment_method,
    // VALOR E PRAZO DO SERVIDOR. O prazo é o da reserva, tal como veio.
    amountCents: a.amount_cents,
    expiresAt: a.expires_at,
    idempotencyKey: a.idempotency_key,
    orderReference: a.idempotency_key,
  };

  let r;
  if (a.payment_method === "pix") {
    // A V5 exige `customer` na criação do pedido. O contexto vem da
    // identidade privilegiada e do dado de onboarding da própria empresa —
    // o navegador não fornece nada disso e não tem por onde fornecer.
    const { data: ctx, error: e3 } = await deps
      .dbPrivilegiado()
      .rpc("prov_get_commercial_payment_customer_context", {
        p_payment_id: a.payment_id,
      });
    if (e3) throw new PaymentError("provider_customer_lookup_failed", 502);
    const c = (ctx ?? {}) as ContextoCliente & { ok?: boolean };
    if (c.ok !== true) throw new PaymentError("provider_customer_data_incomplete", 409);

    let clienteProvedor;
    try {
      // Dado faltando reprova AQUI, antes da rede. Nada de placeholder.
      clienteProvedor = montarClienteProvedor(c);
    } catch (e) {
      if (e instanceof PagarmeCustomerDataError) {
        throw new PaymentError("provider_customer_data_incomplete", 409);
      }
      throw e;
    }
    r = await cliente.criarPix(abertura, clienteProvedor);
  } else {
    r = await cliente.criarLinkCartao(abertura);
  }

  if (!r.ok) {
    // Falha do provedor NÃO abre segunda tentativa: a chave de idempotência
    // e o registro local continuam de pé, e uma nova chamada reusa ambos.
    throw new PaymentError("payment_provider_failed", 502);
  }

  // ---- 4. só identificadores, gravados pela identidade privilegiada.
  const dbPriv = deps.dbPrivilegiado();
  const { error: e2 } = await dbPriv.rpc("prov_record_payment_identifiers", {
    p_payment_id: a.payment_id,
    p_provider_order_id: r.providerOrderId,
    p_provider_charge_id: r.providerChargeId,
    p_provider_payment_link_id: r.providerPaymentLinkId,
    p_provider_reference: abertura.orderReference,
  });
  if (e2) throw new PaymentError("payment_record_failed", 502);

  return {
    ok: true, already: false,
    payment_id: a.payment_id, status: "pending",
    payment_method: a.payment_method, amount_cents: a.amount_cents,
    expires_at: a.expires_at,
    ...(a.payment_method === "pix"
      ? { pix_copy_paste: r.pixQrCode, pix_qr_code_url: r.pixQrCodeUrl }
      : { checkout_url: r.checkoutUrl, installments: parcelas }),
  };
}

// ---------------------------------------------------------------------------
// Webhook: SINAL, nunca autoridade
// ---------------------------------------------------------------------------

/** Tamanho máximo aceito de notificação. Acima disso, recusa sem parsear. */
export const WEBHOOK_MAX_BYTES = 64 * 1024;

/**
 * Extrai do corpo APENAS o identificador do pedido no provedor. Status,
 * valor e método presentes na notificação são deliberadamente ignorados: se
 * fossem lidos, um corpo forjado poderia influenciar o resultado.
 */
export function extrairIdentificadorProvedor(corpo: unknown): string | null {
  if (!corpo || typeof corpo !== "object") return null;
  const o = corpo as Record<string, unknown>;
  const data = (o.data ?? {}) as Record<string, unknown>;
  const candidatos = [
    data.id,
    (data.order as Record<string, unknown> | undefined)?.id,
    o.order_id,
  ];
  for (const c of candidatos) {
    if (typeof c === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(c)) return c;
  }
  return null;
}

export type WebhookResult = {
  ok: boolean;
  code: string;
  payment_id?: string;
};

export async function conciliarWebhook(
  corpoBruto: string,
  deps: { dbPrivilegiado: () => Db; provedor: () => PagarmeClient }
): Promise<WebhookResult> {
  if (corpoBruto.length > WEBHOOK_MAX_BYTES) {
    throw new PaymentError("payload_too_large", 413);
  }
  let corpo: unknown;
  try {
    corpo = JSON.parse(corpoBruto);
  } catch {
    throw new PaymentError("malformed_payload", 400);
  }

  const providerOrderId = extrairIdentificadorProvedor(corpo);
  if (!providerOrderId) throw new PaymentError("unrecognized_notification", 202);

  const cliente = deps.provedor();
  // A VERDADE vem daqui: leitura servidor-a-servidor com a chave secreta.
  const p = await cliente.lerPedido(providerOrderId);
  if (!p.ok) throw new PaymentError("provider_unreachable", 502);

  const db = deps.dbPrivilegiado();
  const { data: loc, error: e1 } = await db.rpc(
    "prov_find_commercial_payment_by_provider_order",
    { p_provider_order_id: providerOrderId }
  );
  if (e1) throw new PaymentError("payment_lookup_failed", 502);
  const l = (loc ?? {}) as { ok?: boolean; payment_id?: string };
  if (l.ok !== true || !l.payment_id) {
    // Notificação de recurso que não é nosso: nada a fazer, e nada a vazar.
    return { ok: true, code: "unknown_payment" };
  }

  // A RPC canônica confere status, valor, método e referência contra o
  // registro local imutável antes de mudar qualquer estado.
  const { data: conf, error: e2 } = await db.rpc("prov_confirm_commercial_payment", {
    p_payment_id: l.payment_id,
    p_provider_status: p.providerStatus,
    p_provider_amount_cents: p.amountCents,
    p_provider_payment_method: p.paymentMethod,
    p_provider_reference: p.code,
  });
  if (e2) throw new PaymentError("reconciliation_failed", 502);
  const c = (conf ?? {}) as {
    ok?: boolean;
    reason?: string;
    status?: string;
    already?: boolean;
  };

  return c.ok === true
    ? { ok: true, code: c.already === true ? "already_paid" : "paid",
        payment_id: l.payment_id }
    : { ok: false, code: typeof c.reason === "string" ? c.reason : "not_reconciled",
        payment_id: l.payment_id };
}
