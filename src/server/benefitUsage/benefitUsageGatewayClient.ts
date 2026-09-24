/**
 * CLIENTE DO GATEWAY DE USO DE BENEFÍCIO. SERVER-ONLY.
 *
 * Domínio PRÓPRIO, deliberadamente separado de `provisioning/`. Uso de
 * benefício e provisionamento comercial compartilham a primitiva de
 * assinatura e nada mais: um é operação de balcão, o outro é asserção
 * contratual. Amarrá-los ao mesmo transporte faria a mudança de um quebrar o
 * outro.
 *
 * A criptografia NÃO é reimplementada aqui: `signGatewayRequest` de
 * `../provisioning/gatewaySigner` é a única implementação Ed25519 do Site.
 */

import {
  GATEWAY_CONTENT_TYPE,
  GATEWAY_SIGNATURE_HEADER,
  loadGatewayConfig,
  signGatewayRequest,
  type GatewayAction,
  type GatewayConfig,
} from "../provisioning/gatewaySigner.js";
import type {
  CreateRequestBody,
  CreateRequestByCodeBody,
  GetRequestStatusBody,
  OpenTokenBody,
} from "./benefitUsageContract.js";

export type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string }
) => Promise<{ status: number; ok: boolean; text: () => Promise<string> }>;

export type GatewayCallResult = {
  readonly ok: boolean;
  readonly status: number;
  readonly body: Record<string, unknown> | null;
};

export class BenefitUsageGatewayClient {
  readonly name = "bdflow-app-gateway/benefit-usage";
  private readonly config: GatewayConfig;
  private readonly fetchImpl: FetchLike;

  constructor(config: GatewayConfig, fetchImpl?: FetchLike) {
    this.config = config;
    this.fetchImpl = fetchImpl ?? (globalThis.fetch as unknown as FetchLike);
  }

  private async chamar(
    action: GatewayAction,
    body:
      | OpenTokenBody
      | CreateRequestBody
      | CreateRequestByCodeBody
      | GetRequestStatusBody,
    correlationId: string
  ): Promise<GatewayCallResult> {
    const req = signGatewayRequest({
      config: this.config,
      action,
      body,
      correlationId,
    });
    const res = await this.fetchImpl(req.url, {
      method: "POST",
      headers: {
        "Content-Type": GATEWAY_CONTENT_TYPE,
        [GATEWAY_SIGNATURE_HEADER]: req.jws,
      },
      // Os MESMOS bytes que foram hasheados e assinados.
      body: req.bodyText,
    });
    const texto = await res.text();
    let parsed: Record<string, unknown> | null = null;
    try {
      const v = texto.length > 0 ? JSON.parse(texto) : null;
      parsed = v && typeof v === "object" ? (v as Record<string, unknown>) : null;
    } catch {
      // Resposta ilegível é tratada como falha, nunca como sucesso. O texto
      // cru NÃO é propagado: pode ecoar o corpo enviado.
      parsed = null;
    }
    return { ok: res.ok, status: res.status, body: parsed };
  }

  /** POST /v1/benefit-usage/token/open */
  openToken(body: OpenTokenBody, correlationId: string) {
    return this.chamar("benefit_usage.open_token", body, correlationId);
  }

  /** POST /v1/benefit-usage/request */
  createRequest(body: CreateRequestBody, correlationId: string) {
    return this.chamar("benefit_usage.create_request", body, correlationId);
  }

  /** POST /v1/benefit-usage/request/status */
  getRequestStatus(body: GetRequestStatusBody, correlationId: string) {
    return this.chamar("benefit_usage.get_request_status", body, correlationId);
  }

  /**
   * POST /v1/benefit-usage/code/request — código manual do balcão.
   *
   * Usa o MESMO `signGatewayRequest`: continua existindo uma única
   * implementação Ed25519 no Site.
   */
  createRequestByCode(body: CreateRequestByCodeBody, correlationId: string) {
    return this.chamar("benefit_usage.create_request_by_code", body, correlationId);
  }
}

export function createBenefitUsageGatewayClient(
  env: Record<string, string | undefined>,
  fetchImpl?: FetchLike
): BenefitUsageGatewayClient {
  return new BenefitUsageGatewayClient(loadGatewayConfig(env), fetchImpl);
}