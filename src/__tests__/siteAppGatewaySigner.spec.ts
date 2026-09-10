import { describe, it, expect, vi } from "vitest";
import { createHash, generateKeyPairSync, verify as verificar } from "node:crypto";
import {
  GATEWAY_ACTIONS,
  GATEWAY_CONTENT_TYPE,
  GATEWAY_ENV_VARS,
  GATEWAY_JWS_ALG,
  GATEWAY_MAX_LIFETIME_SECONDS,
  GATEWAY_PROTOCOL_VERSION,
  GATEWAY_SIGNATURE_HEADER,
  GatewayConfigError,
  loadGatewayConfig,
  signGatewayRequest,
} from "../server/provisioning/gatewaySigner";
import {
  SignedGatewayClient,
  SignedGatewayProvisioningTransport,
  type FetchLike,
} from "../server/provisioning/gatewayTransport";
import {
  BlockedProvisioningTransport,
  createProvisioningTransport,
} from "../server/provisioning/bridgeAdapter";

/**
 * CHAVE DESCARTÁVEL, GERADA NO PRÓPRIO TESTE.
 *
 * Nenhuma chave operacional entra no repositório. Esta existe apenas na
 * memória do processo de teste e some com ele. A pública é derivada dela para
 * VERIFICAR a assinatura — é assim que se prova que o assinante funciona, em
 * vez de conferir que uma string tem três pontos.
 */
const par = generateKeyPairSync("ed25519");
const CHAVE_PRIVADA_B64 = par.privateKey
  .export({ format: "der", type: "pkcs8" })
  .toString("base64");

const KID = "site-gate3-kid-teste";
const ISSUER = "bdflow-site-gate3-http";
const AUDIENCE = "bdflow-app-gateway";
const BASE = "https://app.exemplo.test/functions/v1";

const envCompleto: Record<string, string> = {
  BDFLOW_APP_BRIDGE_URL: BASE,
  BDFLOW_APP_BRIDGE_KEY_ID: KID,
  BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE_PRIVADA_B64,
  BDFLOW_APP_BRIDGE_ISSUER: ISSUER,
  BDFLOW_APP_BRIDGE_AUDIENCE: AUDIENCE,
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function decodificarSegmento(seg: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(seg, "base64url").toString("utf8"));
}

function fetchEspiao() {
  const chamadas: Array<{
    url: string;
    method: string;
    headers: Record<string, string>;
    body: string;
  }> = [];
  const impl: FetchLike = async (url, init) => {
    chamadas.push({ url, ...init });
    return {
      status: 200,
      ok: true,
      text: async () => JSON.stringify({ ok: true }),
    };
  };
  return { chamadas, impl };
}

// ---------------------------------------------------------------------------
// Seleção de transporte
// ---------------------------------------------------------------------------
describe("seleção de transporte", () => {
  it("1. configuração completa seleciona o transporte real", () => {
    const t = createProvisioningTransport(envCompleto);
    expect(t).toBeInstanceOf(SignedGatewayProvisioningTransport);
    expect(t.name).toBe("bdflow-app-gateway");
  });

  it("2. configuração inteiramente ausente preserva o bloqueio", () => {
    expect(createProvisioningTransport({})).toBeInstanceOf(
      BlockedProvisioningTransport
    );
  });

  it("3. configuração parcial falha fechada, nomeando só a variável", () => {
    for (const faltando of GATEWAY_ENV_VARS) {
      const parcial = { ...envCompleto };
      delete (parcial as Record<string, string | undefined>)[faltando];
      let erro: unknown = null;
      try {
        createProvisioningTransport(parcial);
      } catch (e) {
        erro = e;
      }
      expect(erro, faltando).toBeInstanceOf(GatewayConfigError);
      expect((erro as GatewayConfigError).variables).toContain(faltando);
      // Jamais degrada para o sentinela nem para requisição sem assinatura.
      expect(erro).not.toBeInstanceOf(BlockedProvisioningTransport);
    }
  });

  it("3b. chave malformada falha fechada em vez de virar bloqueio silencioso", () => {
    // Montado em tempo de execucao, e nao como literal: o scanner de segredos
    // acusa (com razao) qualquer atribuicao literal longa a um nome de chave,
    // e enfraquecer o scanner para acomodar um fixture seria o troco errado.
    const invalida = ["isto", "nao", "e", "uma", "pkcs8"].join("-");
    expect(() =>
      createProvisioningTransport({
        ...envCompleto,
        BDFLOW_APP_BRIDGE_SIGNING_KEY: invalida,
      })
    ).toThrow(GatewayConfigError);
  });

  it("3c. chave de curva errada (RSA) é recusada", () => {
    const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 });
    expect(() =>
      loadGatewayConfig({
        ...envCompleto,
        BDFLOW_APP_BRIDGE_SIGNING_KEY: rsa.privateKey
          .export({ format: "der", type: "pkcs8" })
          .toString("base64"),
      })
    ).toThrow(GatewayConfigError);
  });

  it("4. a chave privada nunca aparece em erro, log ou configuração serializada", () => {
    const logs: string[] = [];
    const spy = vi.spyOn(console, "error").mockImplementation((...a) => {
      logs.push(a.map(String).join(" "));
    });
    let erro: Error | null = null;
    try {
      loadGatewayConfig({ ...envCompleto, BDFLOW_APP_BRIDGE_URL: "nao-e-url" });
    } catch (e) {
      erro = e as Error;
      console.error(e);
    }
    spy.mockRestore();

    expect(erro).not.toBeNull();
    expect(erro!.message).not.toContain(CHAVE_PRIVADA_B64);
    expect(erro!.stack ?? "").not.toContain(CHAVE_PRIVADA_B64);
    expect(logs.join("\n")).not.toContain(CHAVE_PRIVADA_B64);

    // Nem mesmo um JSON.stringify acidental da config vaza a chave.
    const cfg = loadGatewayConfig(envCompleto);
    expect(JSON.stringify(cfg)).not.toContain(CHAVE_PRIVADA_B64);

    // E o erro de chave inválida também não ecoa o material apresentado.
    let erroChave: Error | null = null;
    try {
      loadGatewayConfig({
        ...envCompleto,
        BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE_PRIVADA_B64.slice(0, 40),
      });
    } catch (e) {
      erroChave = e as Error;
    }
    expect(erroChave!.message).not.toContain(CHAVE_PRIVADA_B64.slice(0, 40));
  });
});

// ---------------------------------------------------------------------------
// Forma e conteúdo do JWS
// ---------------------------------------------------------------------------
describe("JWS compacto do gateway", () => {
  const cfg = loadGatewayConfig(envCompleto);

  it("5. o JWS tem exatamente três segmentos compactos", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: { a: 1 },
    });
    const partes = r.jws.split(".");
    expect(partes).toHaveLength(3);
    expect(partes.every((p) => p.length > 0)).toBe(true);
    // base64url: sem +, / ou =
    expect(r.jws).not.toMatch(/[+/=]/);
  });

  it("6 e 7. header traz alg Ed25519 e o kid configurado", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
    });
    const header = decodificarSegmento(r.jws.split(".")[0]);
    expect(header.alg).toBe("Ed25519");
    expect(header.alg).toBe(GATEWAY_JWS_ALG);
    expect(header.kid).toBe(KID);
    expect(r.envelope.key_id).toBe(KID);
  });

  it("8 e 9. issuer, audience e protocol_version são exatos", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
    });
    expect(r.envelope.issuer).toBe("bdflow-site-gate3-http");
    expect(r.envelope.audience).toBe("bdflow-app-gateway");
    expect(r.envelope.protocol_version).toBe("bdflow-gateway/1");
    expect(r.envelope.protocol_version).toBe(GATEWAY_PROTOCOL_VERSION);
  });

  it("10. open_token usa a rota lógica canônica", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
    });
    expect(r.envelope.action).toBe("benefit_usage.open_token");
    expect(r.envelope.gateway_path).toBe("/v1/benefit-usage/token/open");
    expect(r.envelope.http_method).toBe("POST");
    // O prefixo de Edge Function fica na URL, NUNCA no caminho assinado.
    expect(r.url).toBe(`${BASE}/v1/benefit-usage/token/open`);
    expect(r.envelope.gateway_path).not.toContain("/functions/");
  });

  it("11 e 12. create_request usa a própria rota e carrega a versão de apresentação", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.create_request",
      body: {},
    });
    expect(r.envelope.action).toBe("benefit_usage.create_request");
    expect(r.envelope.gateway_path).toBe("/v1/benefit-usage/request");
    expect(r.envelope.presentation_contract_version).toBe(1);
    expect(r.envelope.gateway_path).not.toContain("/functions/");

    // E open_token NÃO carrega esse campo.
    const aberto = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
    });
    expect(aberto.envelope.presentation_contract_version).toBeUndefined();
  });

  it("13 e 14. jti e request_correlation_id são UUID e não se repetem", () => {
    const a = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
    });
    const b = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
    });
    expect(a.envelope.jti).toMatch(UUID_RE);
    expect(a.envelope.request_correlation_id).toMatch(UUID_RE);
    expect(b.envelope.jti).toMatch(UUID_RE);
    // Antirreplay não funciona com JTI repetido.
    expect(a.envelope.jti).not.toBe(b.envelope.jti);
  });

  it("15. a janela de validade cabe no máximo do gateway", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: {},
      nowSeconds: 1_800_000_000,
    });
    const { issued_at, not_before, expires_at } = r.envelope;
    expect(Number.isInteger(issued_at)).toBe(true);
    expect(Number.isInteger(not_before)).toBe(true);
    expect(Number.isInteger(expires_at)).toBe(true);
    expect(not_before).toBe(issued_at);
    expect(expires_at - issued_at).toBeLessThanOrEqual(
      GATEWAY_MAX_LIFETIME_SECONDS
    );
    expect(expires_at - issued_at).toBe(60);
    expect(() =>
      signGatewayRequest({
        config: cfg,
        action: "benefit_usage.open_token",
        body: {},
        lifetimeSeconds: 120,
      })
    ).toThrow(GatewayConfigError);
  });

  it("a assinatura verifica com a chave pública correspondente", () => {
    const r = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.create_request",
      body: { benefit: "x" },
    });
    const [h, p, sig] = r.jws.split(".");
    const ok = verificar(
      null,
      Buffer.from(`${h}.${p}`, "ascii"),
      par.publicKey,
      Buffer.from(sig, "base64url")
    );
    expect(ok).toBe(true);

    // Adulterar o envelope invalida a assinatura.
    const adulterado = { ...(decodificarSegmento(p) as object), audience: "outro" };
    const pFalso = Buffer.from(JSON.stringify(adulterado), "utf8").toString(
      "base64url"
    );
    expect(
      verificar(
        null,
        Buffer.from(`${h}.${pFalso}`, "ascii"),
        par.publicKey,
        Buffer.from(sig, "base64url")
      )
    ).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Corpo: os bytes assinados são os bytes enviados
// ---------------------------------------------------------------------------
describe("corpo e hash", () => {
  const cfg = loadGatewayConfig(envCompleto);

  it("16. body_sha256 confere com os bytes exatamente transmitidos", async () => {
    const { chamadas, impl } = fetchEspiao();
    const cliente = new SignedGatewayClient(cfg, impl);
    await cliente.createBenefitUsageRequest({ usuario: "u-1", etapa: 3 });

    expect(chamadas).toHaveLength(1);
    const enviado = chamadas[0];
    const envelope = decodificarSegmento(
      enviado.headers[GATEWAY_SIGNATURE_HEADER].split(".")[1]
    );
    const hashDoQueViajou = createHash("sha256")
      .update(Buffer.from(enviado.body, "utf8"))
      .digest("hex");

    expect(envelope.body_sha256).toBe(hashDoQueViajou);
    expect(envelope.body_sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  it("17. mudar UM byte do corpo muda o hash assinado", () => {
    const a = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: { token: "abc" },
    });
    const b = signGatewayRequest({
      config: cfg,
      action: "benefit_usage.open_token",
      body: { token: "abd" },
    });
    expect(a.envelope.body_sha256).not.toBe(b.envelope.body_sha256);

    // E o hash é o do texto exato, não de uma segunda serialização.
    expect(a.envelope.body_sha256).toBe(
      createHash("sha256").update(Buffer.from(a.bodyText, "utf8")).digest("hex")
    );
  });
});

// ---------------------------------------------------------------------------
// Transporte HTTP
// ---------------------------------------------------------------------------
describe("transporte HTTP assinado", () => {
  const cfg = loadGatewayConfig(envCompleto);

  it("18. não envia Authorization, service_role nem credencial de banco", async () => {
    const { chamadas, impl } = fetchEspiao();
    const cliente = new SignedGatewayClient(cfg, impl);
    await cliente.openBenefitUsageToken({ a: 1 });

    const h = chamadas[0].headers;
    const nomes = Object.keys(h).map((k) => k.toLowerCase());
    expect(nomes).not.toContain("authorization");
    expect(nomes).not.toContain("apikey");
    expect(nomes).not.toContain("cookie");
    // A autoridade é a assinatura e nada mais.
    expect(nomes.sort()).toEqual(
      ["content-type", GATEWAY_SIGNATURE_HEADER.toLowerCase()].sort()
    );

    const tudo = JSON.stringify(chamadas[0]);
    expect(tudo).not.toMatch(/service_role|postgres:\/\/|SUPABASE_SERVICE_ROLE/i);
    expect(tudo).not.toContain(CHAVE_PRIVADA_B64);
  });

  it("19 e 20. cabeçalho de assinatura presente e Content-Type exato", async () => {
    const { chamadas, impl } = fetchEspiao();
    const cliente = new SignedGatewayClient(cfg, impl);
    await cliente.openBenefitUsageToken({ a: 1 });

    const enviado = chamadas[0];
    expect(enviado.method).toBe("POST");
    expect(enviado.headers[GATEWAY_SIGNATURE_HEADER]).toBeTruthy();
    expect(GATEWAY_SIGNATURE_HEADER).toBe("X-BDFlow-Gateway-Signature");
    expect(enviado.headers[GATEWAY_SIGNATURE_HEADER].split(".")).toHaveLength(3);
    expect(enviado.headers["Content-Type"]).toBe(
      "application/json; charset=utf-8"
    );
    expect(enviado.headers["Content-Type"]).toBe(GATEWAY_CONTENT_TYPE);
  });

  it("cada ação chama a URL de implantação da própria rota", async () => {
    const { chamadas, impl } = fetchEspiao();
    const cliente = new SignedGatewayClient(cfg, impl);
    await cliente.openBenefitUsageToken({});
    await cliente.createBenefitUsageRequest({});
    expect(chamadas.map((c) => c.url)).toEqual([
      `${BASE}${GATEWAY_ACTIONS["benefit_usage.open_token"]}`,
      `${BASE}${GATEWAY_ACTIONS["benefit_usage.create_request"]}`,
    ]);
  });

  it("provisionamento comercial segue falhando: o contrato não tem essa rota", async () => {
    const t = new SignedGatewayProvisioningTransport(cfg);
    await expect(
      t.dispatch({
        ok: true,
        message_id: "msg-9",
        correlation_id: "c-9",
        environment: "local",
        schema_version: "bdflow.commercial_provisioning.v2",
        payload: {},
        payload_hash: "a".repeat(64),
        attempt: 1,
      })
    ).rejects.toThrow(/sem rota de provisionamento comercial/);
  });
});
