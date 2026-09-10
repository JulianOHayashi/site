import { describe, it, expect } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import {
  inspectBridgeConfig,
  createProvisioningTransport,
  BlockedProvisioningTransport,
  ProvisioningBlockedError,
  PROVISIONING_ENV_VARS,
  type ClaimedProvisioningMessage,
} from "../server/provisioning/bridgeAdapter";
import { GatewayConfigError } from "../server/provisioning/gatewaySigner";
import { SignedGatewayProvisioningTransport } from "../server/provisioning/gatewayTransport";

/**
 * R11 — fronteira da ponte Site -> App.
 *
 * O QUE MUDOU E POR QUE
 * Antes esta fronteira devolvia SEMPRE o sentinela bloqueado, mesmo com o
 * ambiente completo: nao havia camada de assinatura, e configurar nao
 * substituia um contrato inexistente. Com o gateway de uso de beneficio
 * congelado, a camada de assinatura existe e a selecao passa a distinguir tres
 * casos — nada configurado, tudo valido, e configuracao quebrada.
 *
 * O que NAO mudou: nenhum contrato e inventado, nenhuma chave vaza, e o
 * despacho de provisionamento comercial continua falhando explicitamente,
 * porque o gateway nao expoe rota de provisionamento.
 */

/** Valor propositalmente INVALIDO: nao e uma Ed25519 PKCS#8 em base64. */
const CHAVE_INVALIDA = "chave-de-assinatura-super-secreta-123456";

const par = generateKeyPairSync("ed25519");
const CHAVE_VALIDA_B64 = par.privateKey
  .export({ format: "der", type: "pkcs8" })
  .toString("base64");

const envQuebrado = {
  BDFLOW_APP_BRIDGE_URL: "https://app.exemplo/bridge",
  BDFLOW_APP_BRIDGE_KEY_ID: "kid-1",
  BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE_INVALIDA,
  BDFLOW_APP_BRIDGE_ISSUER: "bdflow-site-gate3-http",
  BDFLOW_APP_BRIDGE_AUDIENCE: "bdflow-app-gateway",
};

const envValido = {
  ...envQuebrado,
  BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE_VALIDA_B64,
};

const mensagem: ClaimedProvisioningMessage = {
  ok: true,
  message_id: "msg-1",
  correlation_id: "corr-1",
  environment: "local",
  schema_version: "bdflow.commercial_provisioning.v2",
  payload: { partners: [] },
  payload_hash: "a".repeat(64),
  attempt: 1,
};

describe("R11 — fronteira de adaptador da ponte Site->App", () => {
  it("ambiente vazio: nao configurado e bloqueado", () => {
    const s = inspectBridgeConfig({});
    expect(s.configured).toBe(false);
    expect(s.blocked).toBe(true);
    expect(s.blockedReason).toBe("BLOCKED_APP_REPOSITORY");
    expect(s.missing).toEqual([...PROVISIONING_ENV_VARS]);
  });

  it("ambiente completo: deixa de estar bloqueado por ausencia", () => {
    const s = inspectBridgeConfig(envValido);
    expect(s.configured).toBe(true);
    expect(s.blocked).toBe(false);
    expect(s.missing).toEqual([]);
  });

  it("relata apenas NOMES de variaveis, nunca valores", () => {
    const s = inspectBridgeConfig({
      BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE_INVALIDA,
    });
    expect(JSON.stringify(s)).not.toContain(CHAVE_INVALIDA);
  });

  it("sem nenhuma variavel, o transporte e o sentinela bloqueado", () => {
    expect(createProvisioningTransport({})).toBeInstanceOf(
      BlockedProvisioningTransport
    );
  });

  it("configuracao completa e valida seleciona o transporte assinado", () => {
    expect(createProvisioningTransport(envValido)).toBeInstanceOf(
      SignedGatewayProvisioningTransport
    );
  });

  it("configuracao presente mas quebrada FALHA, nao vira bloqueio silencioso", () => {
    // Esconder erro de configuracao atras de "App indisponivel" mandaria
    // alguem procurar defeito no lugar errado.
    expect(() => createProvisioningTransport(envQuebrado)).toThrow(
      GatewayConfigError
    );
    expect(() => createProvisioningTransport(envQuebrado)).toThrow(
      /BDFLOW_APP_BRIDGE_SIGNING_KEY/
    );
  });

  it("nem o erro de configuracao nem o de despacho vazam a chave", async () => {
    let erroConfig: Error | null = null;
    try {
      createProvisioningTransport(envQuebrado);
    } catch (e) {
      erroConfig = e as Error;
    }
    expect(erroConfig!.message).not.toContain(CHAVE_INVALIDA);

    const t = createProvisioningTransport(envValido);
    let erro: Error | null = null;
    try {
      await t.dispatch(mensagem);
    } catch (e) {
      erro = e as Error;
    }
    expect(erro).not.toBeNull();
    expect(erro!.message).not.toContain(CHAVE_VALIDA_B64);
    expect(erro!.message).toContain("msg-1");
  });

  it("o sentinela bloqueado FALHA ao despachar, nunca vira no-op", async () => {
    // Sem esta assercao, neutralizar o throw de BlockedProvisioningTransport
    // passaria despercebido — e um transporte que "conclui" sem enviar nada e
    // exatamente o defeito mais caro que esta fronteira existe para impedir.
    const t = createProvisioningTransport({});
    expect(t).toBeInstanceOf(BlockedProvisioningTransport);
    await expect(t.dispatch(mensagem)).rejects.toBeInstanceOf(
      ProvisioningBlockedError
    );
    await expect(t.dispatch(mensagem)).rejects.toThrow(/BLOCKED_APP_REPOSITORY/);
    await expect(t.dispatch(mensagem)).rejects.toThrow(/msg-1/);
  });

  it("despachar provisionamento FALHA: o gateway nao tem essa rota", async () => {
    const t = createProvisioningTransport(envValido);
    await expect(t.dispatch(mensagem)).rejects.toBeInstanceOf(
      ProvisioningBlockedError
    );
    await expect(t.dispatch(mensagem)).rejects.toThrow(
      /sem rota de provisionamento comercial/
    );
  });

  it("o sentinela continua sem assinatura e sem cliente HTTP", () => {
    const t = createProvisioningTransport({}) as unknown as Record<
      string,
      unknown
    >;
    expect(typeof t.sign).toBe("undefined");
    expect(typeof t.fetch).toBe("undefined");
    expect(Object.keys(t)).toEqual(["name"]);
  });
});
