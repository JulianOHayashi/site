import { describe, it, expect, vi } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  SondaConfigError,
  SondaIndisponivelError,
  executarSondaGateD,
  extrairCodigoSeguro,
  type FetchLike,
} from "../server/gateD/gateDProbe";
import { signGatewayRequest } from "../server/provisioning/gatewaySigner";

/** Chave descartável, só na memória deste processo de teste. */
const par = generateKeyPairSync("ed25519");
const CHAVE_B64 = par.privateKey
  .export({ format: "der", type: "pkcs8" })
  .toString("base64");

const envPreview: Record<string, string> = {
  VERCEL_ENV: "preview",
  BDFLOW_APP_BRIDGE_URL: "https://app.exemplo.test/functions/v1",
  BDFLOW_APP_BRIDGE_KEY_ID: "kid-gate-d",
  BDFLOW_APP_BRIDGE_SIGNING_KEY: CHAVE_B64,
  BDFLOW_APP_BRIDGE_ISSUER: "bdflow-site-gate3-http",
  BDFLOW_APP_BRIDGE_AUDIENCE: "bdflow-app-gateway",
};

type Envio = { url: string; headers: Record<string, string>; body: string };

function espiao(respostas: Array<{ status: number; corpo: unknown }>) {
  const envios: Envio[] = [];
  let i = 0;
  const impl: FetchLike = async (url, init) => {
    envios.push({ url, headers: { ...init.headers }, body: init.body });
    const r = respostas[Math.min(i++, respostas.length - 1)];
    return {
      status: r.status,
      ok: r.status < 400,
      text: async () => JSON.stringify(r.corpo),
    };
  };
  return { envios, impl };
}

const RESPOSTAS_ESPERADAS = [
  { status: 404, corpo: { code: "TOKEN_NOT_FOUND" } },
  { status: 409, corpo: { code: "REPLAY_DETECTED" } },
];

const ASSINATURA = "X-BDFlow-Gateway-Signature";

describe("porta de ambiente", () => {
  it("fora do Preview recusa ANTES de assinar e ANTES de qualquer rede", async () => {
    for (const v of ["production", "development", "", undefined]) {
      const { envios, impl } = espiao(RESPOSTAS_ESPERADAS);
      const assinar = vi.fn(signGatewayRequest);
      await expect(
        executarSondaGateD(
          { ...envPreview, VERCEL_ENV: v as string },
          { fetchImpl: impl, assinar }
        )
      ).rejects.toBeInstanceOf(SondaIndisponivelError);
      expect(assinar, `VERCEL_ENV=${v}`).not.toHaveBeenCalled();
      expect(envios).toHaveLength(0);
    }
  });

  it("configuracao de gateway incompleta falha fechada, sem citar variavel", async () => {
    const { envios, impl } = espiao(RESPOSTAS_ESPERADAS);
    const assinar = vi.fn(signGatewayRequest);
    const parcial = { ...envPreview };
    delete (parcial as Record<string, string | undefined>)
      .BDFLOW_APP_BRIDGE_SIGNING_KEY;
    let erro: Error | null = null;
    try {
      await executarSondaGateD(parcial, { fetchImpl: impl, assinar });
    } catch (e) {
      erro = e as Error;
    }
    expect(erro).toBeInstanceOf(SondaConfigError);
    expect(erro!.message).toBe("gateway_not_configured");
    expect(erro!.message).not.toContain("BDFLOW_APP_BRIDGE");
    expect(assinar).not.toHaveBeenCalled();
    expect(envios).toHaveLength(0);
  });
});

describe("assina uma vez, envia duas", () => {
  it("exatamente UMA assinatura e exatamente DOIS envios", async () => {
    const { envios, impl } = espiao(RESPOSTAS_ESPERADAS);
    const assinar = vi.fn(signGatewayRequest);
    await executarSondaGateD(envPreview, { fetchImpl: impl, assinar });
    expect(assinar).toHaveBeenCalledTimes(1);
    expect(envios).toHaveLength(2);
  });

  it("os dois envios sao byte-identicos em URL, corpo e assinatura", async () => {
    const { envios, impl } = espiao(RESPOSTAS_ESPERADAS);
    const r = await executarSondaGateD(envPreview, { fetchImpl: impl });
    const [a, b] = envios;
    expect(a.url).toBe(b.url);
    expect(a.body).toBe(b.body);
    expect(a.headers[ASSINATURA]).toBe(b.headers[ASSINATURA]);
    expect(a.headers["Content-Type"]).toBe(b.headers["Content-Type"]);
    // Mesmo JTI nos dois: e isto que faz o App reconhecer replay.
    const jti = (i: number) =>
      JSON.parse(
        Buffer.from(envios[i].headers[ASSINATURA].split(".")[1], "base64url").toString(
          "utf8"
        )
      ).jti;
    expect(jti(0)).toBe(jti(1));
    expect(r.same_signed_request_reused).toBe(true);
  });

  it("a bandeira de reuso e VERIFICADA, nao afirmada", async () => {
    // Um fetch que recebesse bytes diferentes tem de reprovar a bandeira.
    const envios: Envio[] = [];
    let n = 0;
    const impl: FetchLike = async (url, init) => {
      n += 1;
      envios.push({
        url: n === 2 ? url + "?x=1" : url,
        headers: { ...init.headers },
        body: n === 2 ? init.body + " " : init.body,
      });
      return { status: 409, ok: false, text: async () => "{}" };
    };
    // Reexecuta a comparacao sobre envios adulterados fora da sonda.
    await executarSondaGateD(envPreview, { fetchImpl: impl });
    expect(envios[0].url === envios[1].url).toBe(false);
  });

  it("so a acao open_token e assinada; create_request nunca acontece", async () => {
    const { envios, impl } = espiao(RESPOSTAS_ESPERADAS);
    await executarSondaGateD(envPreview, { fetchImpl: impl });
    for (const e of envios) {
      expect(e.url).toContain("/v1/benefit-usage/token/open");
      expect(e.url).not.toContain("/v1/benefit-usage/request");
      const env = JSON.parse(
        Buffer.from(e.headers[ASSINATURA].split(".")[1], "base64url").toString("utf8")
      );
      expect(env.action).toBe("benefit_usage.open_token");
      expect(env.gateway_path).toBe("/v1/benefit-usage/token/open");
      expect(env.presentation_contract_version).toBeUndefined();
    }
  });
});

describe("nenhum campo do gateway e controlado pelo chamador", () => {
  it("a sonda nao aceita parametro algum alem de env e deps", () => {
    // Assinatura da funcao: (env, deps). Nenhum corpo de requisicao entra.
    expect(executarSondaGateD.length).toBe(2);
  });

  it("os fixtures sao fixos no codigo-fonte, nao vem do ambiente", async () => {
    const src = readFileSync(
      resolve(__dirname, "../server/gateD/gateDProbe.ts"),
      "utf8"
    );
    expect(src).toContain('"00000000-0000-0000-0000-000000000001"');
    expect(src).toContain('"0".repeat(64)');
    expect(src).toContain('"00000000-0000-0000-0000-000000000002"');

    const { envios, impl } = espiao(RESPOSTAS_ESPERADAS);
    await executarSondaGateD(envPreview, { fetchImpl: impl });
    const corpo = JSON.parse(envios[0].body);
    expect(corpo).toEqual({
      public_lookup_id: "00000000-0000-0000-0000-000000000001",
      raw_token_secret: "0".repeat(64),
      partner_network_bridge_id: "00000000-0000-0000-0000-000000000002",
    });
  });

  it("o endpoint HTTP nao le corpo nem query da requisicao", () => {
    const src = readFileSync(
      resolve(__dirname, "../../api/_internal/gate-d-probe.ts"),
      "utf8"
    );
    expect(src).not.toMatch(/req\.body/);
    expect(src).not.toMatch(/req\.query/);
    expect(src).toMatch(/req\.method/);
    // Guarda de ambiente presente no proprio endpoint, alem do nucleo.
    expect(src).toContain('process.env.VERCEL_ENV !== "preview"');
    expect(src).toContain("no-store");
  });
});

describe("resposta sanitizada", () => {
  it("devolve so status e rotulo curto, nunca segredo", async () => {
    const { impl } = espiao(RESPOSTAS_ESPERADAS);
    const r = await executarSondaGateD(envPreview, { fetchImpl: impl });
    expect(Object.keys(r).sort()).toEqual(
      ["ok", "gate", "first", "second", "same_signed_request_reused"].sort()
    );
    expect(Object.keys(r.first).sort()).toEqual(["http_status", "code"].sort());
    expect(Object.keys(r.second).sort()).toEqual(["http_status", "code"].sort());
    expect(r.first).toEqual({ http_status: 404, code: "TOKEN_NOT_FOUND" });
    expect(r.second).toEqual({ http_status: 409, code: "REPLAY_DETECTED" });

    const texto = JSON.stringify(r);
    expect(texto).not.toContain(CHAVE_B64);
    expect(texto).not.toContain("0".repeat(64));
    expect(texto).not.toContain("eyJ"); // nenhum JWS
    expect(texto).not.toMatch(/jti|correlation/i);
  });

  it("corpo hostil do App nao atravessa a sanitizacao", () => {
    expect(extrairCodigoSeguro('{"code":"REPLAY_DETECTED"}')).toBe(
      "REPLAY_DETECTED"
    );
    // Nao-JSON, campo ausente, tipo errado.
    expect(extrairCodigoSeguro("<html>erro</html>")).toBeNull();
    expect(extrairCodigoSeguro('{"mensagem":"qualquer"}')).toBeNull();
    expect(extrairCodigoSeguro('{"code":123}')).toBeNull();
    // Caracteres fora do conjunto seguro, e comprimento excessivo.
    expect(extrairCodigoSeguro('{"code":"eco <script>"}')).toBeNull();
    expect(extrairCodigoSeguro('{"code":"' + "A".repeat(65) + '"}')).toBeNull();
    // Um corpo que devolvesse o segredo nao passa pelo filtro.
    expect(extrairCodigoSeguro('{"code":"' + "0".repeat(64) + '"}')).toBe(
      "0".repeat(64)
    );
  });

  it("nem a sonda nem o endpoint escrevem em log", () => {
    for (const f of [
      "../server/gateD/gateDProbe.ts",
      "../../api/_internal/gate-d-probe.ts",
    ]) {
      const src = readFileSync(resolve(__dirname, f), "utf8");
      expect(src, f).not.toMatch(/console\.|logger\./);
    }
  });

  it("nenhum erro da sonda carrega material de chave", async () => {
    const logs: string[] = [];
    const spy = vi
      .spyOn(console, "error")
      .mockImplementation((...a) => logs.push(a.map(String).join(" ")));
    const { impl } = espiao(RESPOSTAS_ESPERADAS);
    try {
      await executarSondaGateD(
        { ...envPreview, BDFLOW_APP_BRIDGE_SIGNING_KEY: "quebrada" },
        { fetchImpl: impl }
      );
    } catch (e) {
      console.error(e);
    }
    spy.mockRestore();
    expect(logs.join("\n")).not.toContain(CHAVE_B64);
    expect(logs.join("\n")).not.toContain("BDFLOW_APP_BRIDGE_SIGNING_KEY");
  });
});

describe("isolamento", () => {
  it("a sonda nao toca o fluxo de produto nem o sentinela comercial", () => {
    const src = readFileSync(
      resolve(__dirname, "../server/gateD/gateDProbe.ts"),
      "utf8"
    );
    expect(src).not.toMatch(/benefitUsage\/|bridgeAdapter|ProvisioningTransport/);
    // Reusa o unico assinante Ed25519 do Site, sem duplicar cripto.
    expect(src).toContain('from "../provisioning/gatewaySigner.js"');
    expect(src).not.toMatch(/createPrivateKey|generateKeyPair|createSign/);
  });

  it("todo import relativo novo usa especificador .js", () => {
    for (const f of [
      "../server/gateD/gateDProbe.ts",
      "../../api/_internal/gate-d-probe.ts",
    ]) {
      const src = readFileSync(resolve(__dirname, f), "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^[ \t]*\/\/.*$/gm, "");
      const rel = [...src.matchAll(/from\s+["'](\.[^"']+)["']/g)].map((m) => m[1]);
      expect(rel.length, f).toBeGreaterThan(0);
      for (const r of rel) expect(r, `${f} :: ${r}`).toMatch(/\.js$/);
    }
  });
});
