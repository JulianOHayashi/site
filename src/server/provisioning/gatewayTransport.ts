/**
 * TRANSPORTE HTTP ASSINADO Site -> App. EXCLUSIVAMENTE DE SERVIDOR.
 *
 * Envia exatamente os bytes que foram assinados, com a assinatura destacada em
 * `X-BDFlow-Gateway-Signature`.
 *
 * O QUE NÃO VAI JUNTO
 * Nenhum `Authorization`, nenhuma service-role key, nenhuma credencial de
 * banco. A autoridade desta chamada é a assinatura Ed25519 e nada mais — somar
 * um bearer seria criar um segundo mecanismo de confiança para a mesma
 * operação, exatamente o que o gateway de uso de benefício evita.
 */

import {
  GATEWAY_ACTIONS,
  GATEWAY_SIGNATURE_HEADER,
  loadGatewayConfig,
  signGatewayRequest,
  type GatewayAction,
  type GatewayConfig,
  type SignedGatewayRequest,
} from "./gatewaySigner";
import {
  ProvisioningBlockedError,
  type ClaimedProvisioningMessage,
  type ProvisioningOutcome,
  type ProvisioningTransport,
} from "./bridgeAdapter";

export type GatewayResponse = {
  readonly status: number;
  readonly ok: boolean;
  readonly body: unknown;
  /** Correlação enviada, para rastrear sem reabrir o envelope. */
  readonly requestCorrelationId: string;
};

export type FetchLike = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body: string;
  }
) => Promise<{ status: number; ok: boolean; text: () => Promise<string> }>;

/**
 * Cliente das DUAS rotas congeladas do gateway do App.
 *
 * `fetchImpl` existe para teste; em produção é o `fetch` global do runtime de
 * servidor. O navegador nunca instancia isto.
 */
export class SignedGatewayClient {
  readonly name = "bdflow-app-gateway";
  private readonly config: GatewayConfig;
  private readonly fetchImpl: FetchLike;

  constructor(config: GatewayConfig, fetchImpl?: FetchLike) {
    this.config = config;
    this.fetchImpl = fetchImpl ?? (globalThis.fetch as unknown as FetchLike);
  }

  /** Requisição assinada, sem enviar. Útil para auditoria e teste. */
  prepare(action: GatewayAction, body: unknown): SignedGatewayRequest {
    return signGatewayRequest({ config: this.config, action, body });
  }

  private async enviar(
    action: GatewayAction,
    body: unknown
  ): Promise<GatewayResponse> {
    const req = this.prepare(action, body);
    const res = await this.fetchImpl(req.url, {
      method: "POST",
      headers: { ...req.headers },
      // Os MESMOS bytes que foram hasheados e assinados.
      body: req.bodyText,
    });
    const texto = await res.text();
    let parsed: unknown = texto;
    try {
      parsed = texto.length > 0 ? JSON.parse(texto) : null;
    } catch {
      /* resposta não-JSON é devolvida como texto */
    }
    return {
      status: res.status,
      ok: res.ok,
      body: parsed,
      requestCorrelationId: req.envelope.request_correlation_id,
    };
  }

  /** POST /v1/benefit-usage/token/open */
  openBenefitUsageToken(body: unknown): Promise<GatewayResponse> {
    return this.enviar("benefit_usage.open_token", body);
  }

  /** POST /v1/benefit-usage/request */
  createBenefitUsageRequest(body: unknown): Promise<GatewayResponse> {
    return this.enviar("benefit_usage.create_request", body);
  }
}

/**
 * Transporte concreto atrás da fronteira do `bridgeAdapter`.
 *
 * ATENÇÃO — LACUNA DELIBERADA E DECLARADA
 * O contrato congelado do gateway expõe DUAS rotas, ambas de uso de benefício.
 * NÃO existe rota de provisionamento comercial nele. Portanto este transporte
 * está assinado, configurado e pronto — mas `dispatch()` de uma mensagem de
 * provisionamento ainda falha de forma explícita, porque inventar aqui um
 * `/v1/provisioning` seria fabricar contrato, que é precisamente o que esta
 * fronteira existe para impedir.
 *
 * Quando o App publicar a rota de provisionamento, basta acrescentá-la a
 * `GATEWAY_ACTIONS` e implementar o corpo aqui: a camada de assinatura já
 * está pronta e testada.
 */
export class SignedGatewayProvisioningTransport implements ProvisioningTransport {
  readonly name = "bdflow-app-gateway";
  readonly client: SignedGatewayClient;

  constructor(config: GatewayConfig, fetchImpl?: FetchLike) {
    this.client = new SignedGatewayClient(config, fetchImpl);
  }

  async dispatch(
    message: ClaimedProvisioningMessage
  ): Promise<ProvisioningOutcome> {
    throw new ProvisioningBlockedError(
      `mensagem ${message.message_id} nao pode ser despachada: o contrato do ` +
        `gateway expoe apenas ${Object.keys(GATEWAY_ACTIONS).join(" e ")}, ` +
        "sem rota de provisionamento comercial"
    );
  }
}

/**
 * Constrói o cliente assinado a partir do ambiente do processo.
 * Falha fechada: configuração incompleta ou inválida levanta
 * `GatewayConfigError` em vez de degradar para requisição sem assinatura.
 */
export function createSignedGatewayClient(
  env: Record<string, string | undefined>,
  fetchImpl?: FetchLike
): SignedGatewayClient {
  return new SignedGatewayClient(loadGatewayConfig(env), fetchImpl);
}

export { GATEWAY_SIGNATURE_HEADER };
