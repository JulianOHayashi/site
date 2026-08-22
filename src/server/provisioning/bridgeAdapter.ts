/**
 * R11 — FRONTEIRA DE ADAPTADOR da ponte Site -> App (camadas 2 e 3).
 *
 * ESTADO: BLOCKED_APP_REPOSITORY.
 *
 * O repositório do App não está disponível, então o contrato real da API do
 * App NÃO PODE ser inspecionado. Por decisão explícita, este módulo:
 *   * define a fronteira e os tipos que o worker precisa;
 *   * NÃO inventa endpoint, formato de envelope, cabeçalhos, códigos de erro
 *     nem algoritmo de verificação do lado do App;
 *   * NÃO assina nada e NÃO faz rede;
 *   * falha de forma explícita se alguém tentar despachar sem que o contrato
 *     tenha sido preenchido a partir do App real.
 *
 * Camadas:
 *   1. banco/outbox               -> IMPLEMENTADA (migration 20260822128000)
 *   2. worker assinado (Ed25519)  -> ESTA FRONTEIRA, bloqueada
 *   3. transporte HTTP            -> ESTA FRONTEIRA, bloqueada
 *   4. resposta/binding do App    -> BLOCKED_APP_REPOSITORY
 *   5. E2E real                   -> BLOCKED_APP_REPOSITORY
 *
 * Quando o App existir: implementar `ProvisioningTransport` contra o contrato
 * REAL, sem alterar a camada 1 nem as RPCs prov_*.
 */

/** Mensagem entregue pelo `prov_claim_provisioning_message`. */
export type ClaimedProvisioningMessage = {
  ok: true;
  message_id: string;
  /** Também é o JTI antirreplay. */
  correlation_id: string;
  environment: "local" | "staging" | "production";
  schema_version: string;
  payload: Record<string, unknown>;
  payload_hash: string;
  attempt: number;
};

/** Resultado soberano do App, registrado por `prov_record_provisioning_result`. */
export type ProvisioningOutcome =
  | { accepted: true; operationalCycleId: string }
  | { accepted: false; rejectionCode: string; error?: string };

/**
 * Contrato que o worker assinado precisará implementar. Deliberadamente
 * sem implementação concreta: qualquer endpoint, envelope ou cabeçalho
 * escrito agora seria invenção.
 */
export interface ProvisioningTransport {
  readonly name: string;
  dispatch(message: ClaimedProvisioningMessage): Promise<ProvisioningOutcome>;
}

export class ProvisioningBlockedError extends Error {
  readonly code = "BLOCKED_APP_REPOSITORY";
  constructor(detalhe: string) {
    super(
      `Ponte Site->App bloqueada (BLOCKED_APP_REPOSITORY): ${detalhe}. ` +
        "O contrato real da API do App não pode ser inspecionado; " +
        "camadas 2 a 5 permanecem pendentes."
    );
    this.name = "ProvisioningBlockedError";
  }
}

/**
 * Transporte-sentinela: existe para que a fronteira seja tipada e testável
 * sem que ninguém possa, por engano, "concluir" a ponte com um contrato
 * imaginado. Qualquer despacho falha de forma explícita e auditável.
 */
export class BlockedProvisioningTransport implements ProvisioningTransport {
  readonly name = "blocked-app-repository";
  async dispatch(
    message: ClaimedProvisioningMessage
  ): Promise<ProvisioningOutcome> {
    throw new ProvisioningBlockedError(
      `mensagem ${message.message_id} não pode ser despachada`
    );
  }
}

/** Nomes das variáveis do worker — NUNCA valores. */
export const PROVISIONING_ENV_VARS = [
  "BDFLOW_APP_BRIDGE_URL",
  "BDFLOW_APP_BRIDGE_KEY_ID",
  "BDFLOW_APP_BRIDGE_SIGNING_KEY",
  "BDFLOW_APP_BRIDGE_ISSUER",
  "BDFLOW_APP_BRIDGE_AUDIENCE",
] as const;

export type BridgeConfigStatus = {
  configured: boolean;
  /** Apenas os NOMES das variáveis ausentes. */
  missing: string[];
  /** Sempre bloqueado enquanto o App não puder ser inspecionado. */
  blocked: true;
  blockedReason: "BLOCKED_APP_REPOSITORY";
};

/**
 * Reporta presença/ausência de configuração sem NUNCA devolver valores.
 * Mesmo com tudo configurado, o resultado permanece bloqueado: configuração
 * presente não substitui o contrato real do App.
 */
export function inspectBridgeConfig(
  env: Record<string, string | undefined>
): BridgeConfigStatus {
  const missing = PROVISIONING_ENV_VARS.filter((k) => {
    const v = env[k];
    return typeof v !== "string" || v.trim() === "";
  });
  return {
    configured: missing.length === 0,
    missing: [...missing],
    blocked: true,
    blockedReason: "BLOCKED_APP_REPOSITORY",
  };
}

/**
 * Seleção de transporte. Enquanto o App estiver indisponível, devolve sempre
 * o sentinela bloqueado — inclusive com ambiente completo.
 */
export function createProvisioningTransport(
  _env: Record<string, string | undefined>
): ProvisioningTransport {
  return new BlockedProvisioningTransport();
}
