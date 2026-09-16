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

/**
 * Host de teste documentado para o Checkout/Payment Link. A referência de
 * `POST /paymentlinks` é explícita: conta de teste usa `sdx-api` com
 * `sk_test`. Para `/orders` a documentação descreve teste x produção pela
 * CHAVE, não pelo host — por isso a configuração é separada e o padrão de
 * produção nunca aponta para sandbox sozinho.
 */
export const PAGARME_CHECKOUT_SANDBOX_BASE_URL = "https://sdx-api.pagar.me/core/v5";

/**
 * Cabeçalho que a documentação do Checkout declara obrigatório em toda
 * requisição. Valor FIXO e não secreto — nunca derivado de entrada do
 * usuário.
 */
export const PAGARME_CHECKOUT_USER_AGENT = "pagarme-skill-generated/1.0";

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
  /** Host do Checkout/Payment Link, que a documentação trata à parte. */
  readonly checkoutBaseUrl: string;
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
  // O Checkout tem host próprio documentado para teste. Se não for
  // configurado, ele acompanha a base — e a base padrão é PRODUÇÃO, então
  // nada é roteado para sandbox por omissão.
  const checkoutBruto = (env.PAGARME_CHECKOUT_BASE_URL ?? base).trim();
  try {
    const u = new URL(checkoutBruto);
    if (u.protocol !== "https:" && u.protocol !== "http:") {
      throw new PagarmeConfigError("PAGARME_CHECKOUT_BASE_URL");
    }
  } catch {
    throw new PagarmeConfigError("PAGARME_CHECKOUT_BASE_URL");
  }

  return {
    baseUrl: base.replace(/\/+$/, ""),
    checkoutBaseUrl: checkoutBruto.replace(/\/+$/, ""),
    secretKey: secret,
  };
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

/**
 * Cliente do provedor, montado SÓ a partir de dado autoritativo do servidor.
 * Campo ausente vira falha fechada antes da rede — nunca placeholder.
 */
export type ClienteProvedor = {
  name: string;
  email: string;
  document: string;
  document_type: "CNPJ";
  type: "company";
  address: {
    line_1: string;
    line_2?: string;
    zip_code: string;
    city: string;
    state: string;
    country: "BR";
  };
  phones?: {
    mobile_phone: { country_code: string; area_code: string; number: string };
  };
};

export type ContextoCliente = {
  legal_name?: unknown;
  cnpj?: unknown;
  email?: unknown;
  phone?: unknown;
  address?: {
    postal_code?: unknown;
    street?: unknown;
    street_number?: unknown;
    complement?: unknown;
    district?: unknown;
    city?: unknown;
    uf?: unknown;
  };
};

export class PagarmeCustomerDataError extends Error {
  readonly code = "provider_customer_data_incomplete";
  constructor() {
    super("provider_customer_data_incomplete");
    this.name = "PagarmeCustomerDataError";
  }
}

const texto = (v: unknown): string | null => {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t;
};

/**
 * Telefone brasileiro só é enviado quando pode ser lido sem ambiguidade:
 * 10 ou 11 dígitos depois de remover formatação. Caso contrário, é omitido —
 * fabricar número seria pior que não mandar.
 */
export function normalizarTelefoneBR(
  bruto: unknown
): { country_code: string; area_code: string; number: string } | null {
  const t = texto(bruto);
  if (!t) return null;
  const d = t.replace(/\D/g, "").replace(/^55(?=\d{10,11}$)/, "");
  if (d.length !== 10 && d.length !== 11) return null;
  return { country_code: "55", area_code: d.slice(0, 2), number: d.slice(2) };
}

/**
 * Monta o cliente do provedor. Endereço incompleto reprova: CEP, logradouro,
 * número, cidade e UF são obrigatórios, e nenhum deles é inventado.
 */
export function montarClienteProvedor(ctx: ContextoCliente): ClienteProvedor {
  const nome = texto(ctx.legal_name);
  const email = texto(ctx.email);
  const doc = texto(ctx.cnpj)?.replace(/\D/g, "") ?? null;
  const a = ctx.address ?? {};
  const cep = texto(a.postal_code)?.replace(/\D/g, "") ?? null;
  const rua = texto(a.street);
  const num = texto(a.street_number);
  const cidade = texto(a.city);
  const uf = texto(a.uf)?.toUpperCase() ?? null;

  if (!nome || !email || !doc || doc.length !== 14 || !cep || cep.length !== 8
      || !rua || !num || !cidade || !uf || uf.length !== 2) {
    throw new PagarmeCustomerDataError();
  }

  // line_1 no formato V5: número, logradouro, bairro.
  const bairro = texto(a.district);
  const line1 = [num, rua, bairro].filter(Boolean).join(", ");
  const comp = texto(a.complement);
  const fone = normalizarTelefoneBR(ctx.phone);

  return {
    name: nome,
    email,
    document: doc,
    document_type: "CNPJ",
    type: "company",
    address: {
      line_1: line1,
      ...(comp ? { line_2: comp } : {}),
      zip_code: cep,
      city: cidade,
      state: uf,
      country: "BR",
    },
    ...(fone ? { phones: { mobile_phone: fone } } : {}),
  };
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
    idempotencyKey?: string,
    checkout = false
  ): Promise<{ status: number; ok: boolean; json: Record<string, unknown> | null }> {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      Authorization: autorizacao(this.cfg),
    };
    // A documentação do Checkout declara este cabeçalho obrigatório em toda
    // requisição. Valor fixo, não secreto, jamais derivado de entrada.
    if (checkout) headers["User-Agent"] = PAGARME_CHECKOUT_USER_AGENT;
    // A MESMA chave em toda retentativa lógica: o provedor não cria recurso
    // novo a cada clique do navegador.
    if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;

    const base = checkout ? this.cfg.checkoutBaseUrl : this.cfg.baseUrl;
    const res = await this.fetchImpl(`${base}${caminho}`, {
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

  /**
   * Pix do não fidelizado. Expiração exata da reserva, nunca recalculada.
   *
   * A V5 exige `customer` ou `customer_id` na criação do pedido; o cliente
   * vem montado de dado autoritativo do servidor e já falhou fechado se
   * estivesse incompleto.
   */
  async criarPix(
    a: AberturaPagamento,
    cliente: ClienteProvedor
  ): Promise<ResultadoProvedor> {
    const r = await this.chamar(
      "/orders",
      "POST",
      {
        code: a.orderReference,
        customer: cliente,
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
        // A regra de negócio é UM PAGAMENTO BEM-SUCEDIDO. `max_sessions`
        // limita ORDENS GERADAS, pagas ou não, e por isso não serve: um
        // comprador que tentasse e falhasse queimaria o link.
        max_paid_sessions: 1,
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
      a.idempotencyKey,
      true
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
