/**
 * ADAPTADOR PAGAR.ME V5 — EXCLUSIVAMENTE DE SERVIDOR.
 *
 * Lê `PAGARME_SECRET_KEY` do ambiente do processo. A variável não tem prefixo
 * `VITE_`, logo é invisível ao build do cliente por construção, não por
 * disciplina. Nenhuma função daqui devolve, registra ou interpola a chave.
 *
 * O QUE ESTE ARQUIVO NÃO FAZ
 * Não escolhe método de pagamento, não calcula valor, não decide prazo e não
 * inventa juros. Tudo isso já foi decidido pelo servidor antes de chegar
 * aqui: o método vem da fidelidade, o valor vem do instantâneo contratual e o
 * prazo vem do `reserved_until` da reserva.
 *
 * PARCELAMENTO
 * De 1 a 6 parcelas, TODAS com o mesmo total contratual — nenhum acréscimo é
 * aplicado ao parceiro. Isso significa que a BDFlow absorve o custo do
 * parcelamento. A política final de taxas/juros está registrada como decisão
 * futura nos handoffs; enquanto ela não existir, preservar o total é a única
 * opção que não inventa uma taxa.
 */

import { createHash, randomUUID } from "node:crypto";

export const PAGARME_API_FAMILY = "/core/v5";
export const PAGARME_DEFAULT_BASE_URL = "https://api.pagar.me/core/v5";

/** Teto de parcelas da regra comercial, não do provedor. */
export const MAX_INSTALLMENTS = 6;
export const MIN_INSTALLMENTS = 1;

export class PagarmeConfigError extends Error {
  readonly code = "payment_provider_not_configured";
  constructor(variavel: string) {
    // Só o NOME da variável. O valor nunca entra em mensagem de erro.
    super(`Credencial do provedor ausente ou invalida: ${variavel}`);
    this.name = "PagarmeConfigError";
  }
}

export type PagarmeConfig = {
  readonly baseUrl: string;
  /** Presente só na memória do processo; nunca serializada. */
  readonly secretKey: string;
};

export type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body?: string }
) => Promise<{ status: number; ok: boolean; text: () => Promise<string> }>;

export function loadPagarmeConfig(
  env: Record<string, string | undefined>
): PagarmeConfig {
  const secret = (env.PAGARME_SECRET_KEY ?? "").trim();
  if (secret === "") throw new PagarmeConfigError("PAGARME_SECRET_KEY");

  const base = (env.PAGARME_API_BASE_URL ?? PAGARME_DEFAULT_BASE_URL).trim();
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    throw new PagarmeConfigError("PAGARME_API_BASE_URL");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new PagarmeConfigError("PAGARME_API_BASE_URL");
  }
  return { baseUrl: base.replace(/\/+$/, ""), secretKey: secret };
}

/**
 * Configuração de parcelas: 1..6, todas com o MESMO total.
 * Derivada do valor imutável; nenhum acréscimo, nenhuma taxa inventada.
 */
export function montarParcelas(
  amountCents: number
): Array<{ number: number; total: number }> {
  const saida: Array<{ number: number; total: number }> = [];
  for (let n = MIN_INSTALLMENTS; n <= MAX_INSTALLMENTS; n += 1) {
    saida.push({ number: n, total: amountCents });
  }
  return saida;
}

export type AberturaPagamento = {
  paymentId: string;
  paymentMethod: "pix" | "credit_card";
  amountCents: number;
  /** Prazo autoritativo: o `reserved_until` da reserva, em ISO. */
  expiresAt: string;
  idempotencyKey: string;
  orderReference: string;
};

export type ResultadoProvedor = {
  readonly ok: boolean;
  readonly status: number;
  readonly providerOrderId: string | null;
  readonly providerChargeId: string | null;
  readonly providerPaymentLinkId: string | null;
  /** Pix: copia-e-cola e QR. Cartão: URL hospedada. Nunca segredo. */
  readonly pixQrCode: string | null;
  readonly pixQrCodeUrl: string | null;
  readonly checkoutUrl: string | null;
};

function autorizacao(cfg: PagarmeConfig): string {
  // Basic com a chave como usuário e senha vazia, como a V5 espera.
  return `Basic ${Buffer.from(`${cfg.secretKey}:`).toString("base64")}`;
}

function extrairSeguro(corpo: unknown): ResultadoProvedor["providerOrderId"] {
  if (!corpo || typeof corpo !== "object") return null;
  const v = (corpo as Record<string, unknown>).id;
  return typeof v === "string" ? v : null;
}

export class PagarmeClient {
  readonly provider = "pagarme";
  private readonly cfg: PagarmeConfig;
  private readonly fetchImpl: FetchLike;

  constructor(cfg: PagarmeConfig, fetchImpl?: FetchLike) {
    this.cfg = cfg;
    this.fetchImpl = fetchImpl ?? (globalThis.fetch as unknown as FetchLike);
  }

  private async chamar(
    caminho: string,
    metodo: string,
    corpo: unknown,
    idempotencyKey?: string
  ): Promise<{ status: number; ok: boolean; json: Record<string, unknown> | null }> {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      Authorization: autorizacao(this.cfg),
    };
    // A MESMA chave em toda retentativa lógica: o provedor não cria recurso
    // novo a cada clique do navegador.
    if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;

    const res = await this.fetchImpl(`${this.cfg.baseUrl}${caminho}`, {
      method: metodo,
      headers,
      ...(corpo === undefined ? {} : { body: JSON.stringify(corpo) }),
    });
    const texto = await res.text();
    let json: Record<string, unknown> | null = null;
    try {
      const v = texto.length > 0 ? JSON.parse(texto) : null;
      json = v && typeof v === "object" ? (v as Record<string, unknown>) : null;
    } catch {
      json = null;
    }
    return { status: res.status, ok: res.ok, json };
  }

  /** Pix do não fidelizado. Expiração exata da reserva, nunca recalculada. */
  async criarPix(a: AberturaPagamento): Promise<ResultadoProvedor> {
    const r = await this.chamar(
      "/orders",
      "POST",
      {
        code: a.orderReference,
        items: [
          {
            amount: a.amountCents,
            description: "Exclusividade comercial BDFlow",
            quantity: 1,
          },
        ],
        payments: [
          {
            payment_method: "pix",
            // `expires_at` exato: o prazo do provedor nunca sobrevive à
            // reserva, senão a oportunidade seria vendida duas vezes.
            pix: { expires_at: a.expiresAt },
          },
        ],
      },
      a.idempotencyKey
    );
    const charge = Array.isArray(r.json?.charges)
      ? ((r.json?.charges as unknown[])[0] as Record<string, unknown> | undefined)
      : undefined;
    const tx = charge?.last_transaction as Record<string, unknown> | undefined;
    return {
      ok: r.ok,
      status: r.status,
      providerOrderId: extrairSeguro(r.json),
      providerChargeId: typeof charge?.id === "string" ? charge.id : null,
      providerPaymentLinkId: null,
      pixQrCode: typeof tx?.qr_code === "string" ? tx.qr_code : null,
      pixQrCodeUrl: typeof tx?.qr_code_url === "string" ? tx.qr_code_url : null,
      checkoutUrl: null,
    };
  }

  /**
   * Cartão do fidelizado: checkout HOSPEDADO. Nenhum dado sensível do meio
   * de pagamento passa pelo servidor da BDFlow. A asserção que cobre isto
   * varre o próprio texto deste arquivo, então nem em comentário os nomes
   * desses campos aparecem.
   */
  async criarLinkCartao(a: AberturaPagamento): Promise<ResultadoProvedor> {
    const r = await this.chamar(
      "/paymentlinks",
      "POST",
      {
        name: "Exclusividade comercial BDFlow",
        type: "order",
        // Um único pagamento bem-sucedido: o link não é reutilizável.
        max_sessions: 1,
        expires_in: undefined,
        expires_at: a.expiresAt,
        payment_settings: {
          // Cartão de crédito APENAS. Sem boleto, sem Pix, sem débito.
          accepted_payment_methods: ["credit_card"],
          credit_card_settings: {
            operation_type: "auth_and_capture",
            installments: montarParcelas(a.amountCents),
          },
        },
        cart_settings: {
          items: [
            {
              amount: a.amountCents,
              name: "Exclusividade comercial BDFlow",
              default_quantity: 1,
            },
          ],
        },
      },
      a.idempotencyKey
    );
    return {
      ok: r.ok,
      status: r.status,
      providerOrderId: null,
      providerChargeId: null,
      providerPaymentLinkId: extrairSeguro(r.json),
      pixQrCode: null,
      pixQrCodeUrl: null,
      checkoutUrl: typeof r.json?.url === "string" ? r.json.url : null,
    };
  }

  /**
   * CONCILIAÇÃO servidor-a-servidor. O corpo do webhook é apenas um sinal;
   * a verdade é lida aqui, da API, com a chave secreta.
   */
  async lerPedido(providerOrderId: string): Promise<{
    ok: boolean;
    status: number;
    providerStatus: string | null;
    amountCents: number | null;
    paymentMethod: string | null;
    code: string | null;
  }> {
    const r = await this.chamar(
      `/orders/${encodeURIComponent(providerOrderId)}`,
      "GET",
      undefined
    );
    const charge = Array.isArray(r.json?.charges)
      ? ((r.json?.charges as unknown[])[0] as Record<string, unknown> | undefined)
      : undefined;
    return {
      ok: r.ok,
      status: r.status,
      providerStatus: typeof charge?.status === "string" ? charge.status : null,
      amountCents: typeof charge?.amount === "number" ? charge.amount : null,
      paymentMethod:
        typeof charge?.payment_method === "string" ? charge.payment_method : null,
      code: typeof r.json?.code === "string" ? r.json.code : null,
    };
  }
}

export function createPagarmeClient(
  env: Record<string, string | undefined>,
  fetchImpl?: FetchLike
): PagarmeClient {
  return new PagarmeClient(loadPagarmeConfig(env), fetchImpl);
}

/** Fingerprint estável, para log sem expor identificador do provedor. */
export function referenciaResumida(valor: string): string {
  return createHash("sha256").update(valor).digest("hex").slice(0, 12);
}

export function novaCorrelacao(): string {
  return randomUUID();
}
