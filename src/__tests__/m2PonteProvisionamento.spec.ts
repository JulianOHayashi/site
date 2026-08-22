import { describe, it, expect } from "vitest";
import {
  inspectBridgeConfig,
  createProvisioningTransport,
  BlockedProvisioningTransport,
  ProvisioningBlockedError,
  PROVISIONING_ENV_VARS,
  type ClaimedProvisioningMessage,
} from "../server/provisioning/bridgeAdapter";

/**
 * R11 — a fronteira da ponte precisa FALHAR EXPLICITAMENTE enquanto o
 * repositório do App não puder ser inspecionado. Nenhum contrato inventado.
 */
const CHAVE = "chave-de-assinatura-super-secreta-123456";
const envCompleto = {
  BDFLOW_APP_BRIDGE_URL: "https://app.exemplo/bridge",
  BDFLOW_APP_BRIDGE_KEY_ID: "kid-1",
  BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE,
  BDFLOW_APP_BRIDGE_ISSUER: "site",
  BDFLOW_APP_BRIDGE_AUDIENCE: "app",
};

const mensagem: ClaimedProvisioningMessage = {
  ok: true,
  message_id: "msg-1",
  correlation_id: "corr-1",
  environment: "local",
  schema_version: "bdflow.commercial_provisioning.v1",
  payload: { partners: [] },
  payload_hash: "a".repeat(64),
  attempt: 1,
};

describe("R11 — fronteira de adaptador bloqueada", () => {
  it("ambiente vazio: não configurado e bloqueado", () => {
    const s = inspectBridgeConfig({});
    expect(s.configured).toBe(false);
    expect(s.blocked).toBe(true);
    expect(s.blockedReason).toBe("BLOCKED_APP_REPOSITORY");
    expect(s.missing).toEqual([...PROVISIONING_ENV_VARS]);
  });

  it("ambiente COMPLETO continua bloqueado (config não substitui contrato)", () => {
    const s = inspectBridgeConfig(envCompleto);
    expect(s.configured).toBe(true);
    expect(s.blocked).toBe(true);
  });

  it("relata apenas NOMES de variáveis, nunca valores", () => {
    const s = inspectBridgeConfig({ BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE });
    expect(JSON.stringify(s)).not.toContain(CHAVE);
  });

  it("o transporte é sempre o sentinela bloqueado", () => {
    expect(createProvisioningTransport({})).toBeInstanceOf(
      BlockedProvisioningTransport
    );
    expect(createProvisioningTransport(envCompleto)).toBeInstanceOf(
      BlockedProvisioningTransport
    );
  });

  it("despachar FALHA explicitamente, sem inventar contrato", async () => {
    const t = createProvisioningTransport(envCompleto);
    await expect(t.dispatch(mensagem)).rejects.toBeInstanceOf(
      ProvisioningBlockedError
    );
    await expect(t.dispatch(mensagem)).rejects.toThrow(/BLOCKED_APP_REPOSITORY/);
  });

  it("o erro não vaza a chave de assinatura", async () => {
    const t = createProvisioningTransport(envCompleto);
    let erro: Error | null = null;
    try {
      await t.dispatch(mensagem);
    } catch (e) {
      erro = e as Error;
    }
    expect(erro).not.toBeNull();
    expect(erro!.message).not.toContain(CHAVE);
    expect(erro!.message).toContain("msg-1");
  });

  it("nenhuma assinatura ou rede é executada nesta camada", () => {
    // O sentinela não expõe método de assinatura nem cliente HTTP.
    const t = createProvisioningTransport(envCompleto) as unknown as Record<
      string,
      unknown
    >;
    expect(typeof t.sign).toBe("undefined");
    expect(typeof t.fetch).toBe("undefined");
    expect(Object.keys(t)).toEqual(["name"]);
  });
});
