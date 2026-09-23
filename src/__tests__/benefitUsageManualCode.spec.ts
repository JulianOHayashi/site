import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { generateKeyPairSync } from "node:crypto";
import {
  montarCreateRequestByCodeBody,
  normalizarDisplayCode,
  interpretarAutoridade,
} from "../server/benefitUsage/benefitUsageContract";
import { executarCodigoManual } from "../server/benefitUsage/manualCodeHandler";
import { BenefitUsageGatewayClient } from "../server/benefitUsage/benefitUsageGatewayClient";
import { loadGatewayConfig } from "../server/provisioning/gatewaySigner";
import type { FetchLike } from "../server/benefitUsage/benefitUsageGatewayClient";

/**
 * Código manual do balcão.
 *
 * O App é a autoridade sobre o código. O que se prova aqui é o que o Site
 * envia, o que ele deriva sozinho e, sobretudo, o que ele se recusa a
 * carregar do navegador.
 */

const par = generateKeyPairSync("ed25519");
const envGw: Record<string, string> = {
  BDFLOW_APP_BRIDGE_URL: "https://app.exemplo.test/functions/v1",
  BDFLOW_APP_BRIDGE_KEY_ID: "kid-manual",
  BDFLOW_APP_BRIDGE_SIGNING_KEY: par.privateKey
    .export({ format: "der", type: "pkcs8" })
    .toString("base64"),
  BDFLOW_APP_BRIDGE_ISSUER: "bdflow-site-gate3-http",
  BDFLOW_APP_BRIDGE_AUDIENCE: "bdflow-app-gateway",
};

const UNIT = "66666666-7777-4888-8999-aaaaaaaaaaaa";
const CODIGO = "ABCD7K2M";
const ASSINATURA = "X-BDFlow-Gateway-Signature";

const AUTORIDADE_RPC = {
  ok: true,
  authorized: true,
  company_id: "aaaaaaaa-1111-4111-8111-111111111111",
  unit_id: UNIT,
  partner_network_bridge_id: "bbbbbbbb-2222-4222-8222-222222222222",
  partner_branch_bridge_id: "cccccccc-3333-4333-8333-333333333333",
  validator_bridge_id: "dddddddd-4444-4444-8444-444444444444",
  validator_role: "partner_owner",
  snapshot_presentation_version: 1,
  snapshot_partner_display_name: "Mercado Litoral",
  snapshot_branch_display_name: "Loja Centro",
  snapshot_branch_city_name: "Vitória",
  snapshot_branch_state_code: "ES",
  snapshot_branch_location_label: "Vitória/ES",
};

function dbFalso(over: Record<string, unknown> = {}) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const db = {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      if (fn === "get_my_benefit_usage_authority") {
        return { data: over.autoridade ?? AUTORIDADE_RPC, error: null };
      }
      return { data: null, error: { message: "rpc inesperada" } };
    },
  };
  return { db, chamadas };
}

function gatewayFalso(over: { corpo?: unknown; ok?: boolean } = {}) {
  const envios: Array<{ url: string; headers: Record<string, string>; body: string }> = [];
  const impl: FetchLike = async (url, init) => {
    envios.push({ url, headers: init.headers, body: init.body });
    const ok = over.ok !== false;
    return {
      status: ok ? 200 : 409,
      ok,
      text: async () =>
        JSON.stringify(over.corpo ?? { status: "awaiting_user_confirmation" }),
    };
  };
  return { envios, cliente: new BenefitUsageGatewayClient(loadGatewayConfig(envGw), impl) };
}

function deps(over: Record<string, unknown> = {}, gw = gatewayFalso()) {
  const { db, chamadas } = dbFalso(over);
  return {
    d: {
      criarDbDoUsuario: () => db,
      gateway: gw.cliente,
      novoCorrelationId: () => "99999999-0000-4000-8000-000000000000",
    },
    chamadas,
    envios: gw.envios,
  };
}

const entrada = {
  displayCode: CODIGO,
  unitId: UNIT,
  physicalPhotoIdChecked: true,
};

function envelope(e: { headers: Record<string, string> }) {
  return JSON.parse(
    Buffer.from(e.headers[ASSINATURA].split(".")[1], "base64url").toString("utf8")
  );
}

beforeEach(() => vi.restoreAllMocks());

describe("normalizacao do codigo, sem adivinhar se existe", () => {
  it("aceita a forma de oito alfanumericos, com ou sem hifen", () => {
    for (const v of ["ABCD7K2M", "abcd7k2m", "ABCD-7K2M", " abcd-7k2m ", "AB CD7K2M"]) {
      expect(normalizarDisplayCode(v), v).toBe("ABCD7K2M");
    }
  });

  it("recusa qualquer outra forma", () => {
    for (const v of ["ABCD7K2", "ABCD7K2MX", "ABCD-7K2!", "", null, 12345678, "        "]) {
      expect(normalizarDisplayCode(v), String(v)).toBeNull();
    }
  });
});

describe("corpo enviado ao gateway", () => {
  it("1 e 2. o corpo canonico carrega codigo, correlacao, pontes e snapshots", async () => {
    const x = deps();
    await executarCodigoManual(entrada, "jwt", x.d);
    const corpo = JSON.parse(x.envios[0].body);
    expect(Object.keys(corpo).sort()).toEqual(
      [
        "display_code",
        "request_correlation_id",
        "partner_network_bridge_id",
        "partner_branch_bridge_id",
        "validator_bridge_id",
        "validator_role",
        "physical_photo_id_checked",
        "snapshot_presentation_version",
        "snapshot_partner_display_name",
        "snapshot_branch_display_name",
        "snapshot_branch_location_label",
        "snapshot_branch_city_name",
        "snapshot_branch_state_code",
      ].sort()
    );
    expect(corpo.display_code).toBe(CODIGO);
    expect(corpo.physical_photo_id_checked).toBe(true);
    expect(corpo.snapshot_presentation_version).toBe(1);
    expect(corpo.partner_network_bridge_id).toBe(
      AUTORIDADE_RPC.partner_network_bridge_id
    );
    expect(corpo.validator_role).toBe("partner_owner");
    expect(corpo.snapshot_branch_location_label).toBe("Vitória/ES");
  });

  it("3. o corpo NAO carrega portador de QR", async () => {
    const x = deps();
    await executarCodigoManual(entrada, "jwt", x.d);
    const texto = x.envios[0].body;
    expect(texto).not.toContain("public_lookup_id");
    expect(texto).not.toContain("raw_token_secret");
  });

  it("4 e 5. pontes e snapshots forjados pelo navegador nao chegam ao gateway", async () => {
    const x = deps();
    const forjado = {
      ...entrada,
      partner_network_bridge_id: "00000000-0000-4000-8000-000000000000",
      validator_bridge_id: "00000000-0000-4000-8000-000000000002",
      validator_role: "partner_owner",
      snapshot_partner_display_name: "Loja Falsa",
      snapshot_branch_state_code: "SP",
      request_correlation_id: "11111111-1111-4111-8111-111111111111",
      company_id: "00000000-0000-4000-8000-000000000009",
    } as never;
    await executarCodigoManual(forjado, "jwt", x.d);
    const corpo = JSON.parse(x.envios[0].body);
    expect(corpo.partner_network_bridge_id).toBe(
      AUTORIDADE_RPC.partner_network_bridge_id
    );
    expect(corpo.snapshot_partner_display_name).toBe("Mercado Litoral");
    expect(corpo.snapshot_branch_state_code).toBe("ES");
    expect(JSON.stringify(corpo)).not.toContain("Loja Falsa");
    expect(JSON.stringify(corpo)).not.toContain("00000000-0000-4000-8000-000000000000");
  });

  it("6. a autoridade do Site vem SO do p_unit_id", async () => {
    const x = deps();
    await executarCodigoManual(entrada, "jwt", x.d);
    const rpc = x.chamadas.find((c) => c.fn === "get_my_benefit_usage_authority");
    expect(rpc).toBeTruthy();
    expect(Object.keys(rpc!.args)).toEqual(["p_unit_id"]);
    expect(rpc!.args.p_unit_id).toBe(UNIT);
  });

  it("7. o fluxo manual NAO chama prepare_benefit_validation", async () => {
    const x = deps();
    await executarCodigoManual(entrada, "jwt", x.d);
    expect(x.chamadas.map((c) => c.fn)).toEqual(["get_my_benefit_usage_authority"]);
    const src = readFileSync(
      resolve(__dirname, "../server/benefitUsage/manualCodeHandler.ts"),
      "utf8"
    );
    // Nem por engano, nem em import: a RPC legada hasheia o token no Site.
    expect(src.replace(/\/\*[\s\S]*?\*\/|\/\/.*/g, "")).not.toContain(
      "prepare_benefit_validation"
    );
  });

  it("12 e 13. a correlacao e do servidor e nao ha retentativa automatica", async () => {
    const x = deps();
    const r = await executarCodigoManual(entrada, "jwt", x.d);
    expect(r.request_correlation_id).toBe("99999999-0000-4000-8000-000000000000");
    expect(JSON.parse(x.envios[0].body).request_correlation_id).toBe(
      r.request_correlation_id
    );
    // Uma submissao, um envio.
    expect(x.envios).toHaveLength(1);
  });
});

describe("portas antes da rede", () => {
  it("8. sem sessao nao chega ao gateway", async () => {
    const x = deps();
    await expect(
      executarCodigoManual(entrada, null, x.d)
    ).rejects.toMatchObject({ code: "not_authenticated", status: 401 });
    expect(x.envios).toHaveLength(0);
  });

  it("9. validador nao autorizado nao chega ao gateway", async () => {
    const x = deps({ autoridade: { ok: true, authorized: false, reason: "not_authorized" } });
    await expect(
      executarCodigoManual(entrada, "jwt", x.d)
    ).rejects.toMatchObject({ code: "not_authorized", status: 403 });
    expect(x.envios).toHaveLength(0);
  });

  it("10. sem conferencia do documento nada e enviado", async () => {
    for (const v of [false, undefined, "true", 1]) {
      const x = deps();
      await expect(
        executarCodigoManual({ ...entrada, physicalPhotoIdChecked: v }, "jwt", x.d)
      ).rejects.toMatchObject({ code: "photo_id_check_required" });
      expect(x.envios).toHaveLength(0);
    }
  });

  it("11. codigo malformado nem consulta autoridade", async () => {
    for (const v of ["ABC", "", null, "ABCD-7K2!", "A".repeat(20)]) {
      const x = deps();
      await expect(
        executarCodigoManual({ ...entrada, displayCode: v }, "jwt", x.d)
      ).rejects.toMatchObject({ code: "invalid_display_code", status: 400 });
      expect(x.chamadas).toHaveLength(0);
      expect(x.envios).toHaveLength(0);
    }
  });

  it("recusa do App nao vira sucesso", async () => {
    const gw = gatewayFalso({ ok: false });
    const x = deps({}, gw);
    await expect(
      executarCodigoManual(entrada, "jwt", x.d)
    ).rejects.toMatchObject({ code: "request_denied", status: 409 });
  });
});

describe("assinatura e resposta", () => {
  it("acao, rota e versao de apresentacao sao exatas", async () => {
    const x = deps();
    await executarCodigoManual(entrada, "jwt", x.d);
    const env = envelope(x.envios[0]);
    expect(env.action).toBe("benefit_usage.create_request_by_code");
    expect(env.gateway_path).toBe("/v1/benefit-usage/code/request");
    expect(env.http_method).toBe("POST");
    expect(env.presentation_contract_version).toBe(1);
    expect(env.issuer).toBe("bdflow-site-gate3-http");
    expect(env.audience).toBe("bdflow-app-gateway");
    expect(env.protocol_version).toBe("bdflow-gateway/1");
    expect(env.gateway_path).not.toContain("/functions/");
    expect(x.envios[0].url).toBe(
      "https://app.exemplo.test/functions/v1/v1/benefit-usage/code/request"
    );
  });

  it("14 e 15. a resposta ao navegador nao vaza ponte nem material de assinatura", async () => {
    const x = deps();
    const r = await executarCodigoManual(entrada, "jwt", x.d);
    const texto = JSON.stringify(r);
    expect(Object.keys(r).sort()).toEqual(
      [
        "ok",
        "status",
        "request_correlation_id",
        "partner_display_name",
        "branch_display_name",
        "branch_location_label",
        "app_status",
      ].sort()
    );
    expect(texto).not.toContain(AUTORIDADE_RPC.partner_network_bridge_id);
    expect(texto).not.toContain(AUTORIDADE_RPC.validator_bridge_id);
    expect(texto).not.toContain(envGw.BDFLOW_APP_BRIDGE_SIGNING_KEY);
    expect(texto).not.toContain("eyJ");
    // O codigo digitado tambem nao volta.
    expect(texto).not.toContain(CODIGO);
  });

  it("16. o codigo nunca aparece em log nem em erro", async () => {
    const logs: string[] = [];
    const spy = vi
      .spyOn(console, "error")
      .mockImplementation((...a) => logs.push(a.map(String).join(" ")));
    const x = deps({ autoridade: { ok: true, authorized: false } });
    try {
      await executarCodigoManual(entrada, "jwt", x.d);
    } catch (e) {
      console.error(e);
    }
    spy.mockRestore();
    expect(logs.join("\n")).not.toContain(CODIGO);

    for (const f of [
      "../server/benefitUsage/manualCodeHandler.ts",
      "../../api/benefit-usage/code/request.ts",
    ]) {
      const src = readFileSync(resolve(__dirname, f), "utf8");
      expect(src, f).not.toMatch(/console\.|logger\./);
    }
  });
});

describe("fronteira navegador/servidor", () => {
  it("o servico de navegador envia tres campos e nada de autoridade", () => {
    const src = readFileSync(
      resolve(__dirname, "../services/benefitUsageService.ts"),
      "utf8"
    );
    const envio = src.slice(
      src.indexOf("enviarUsoDeBeneficioPorCodigo"),
      src.length
    );
    const corpo = envio.slice(envio.indexOf("body: JSON.stringify"), envio.indexOf("});"));
    expect(corpo).toContain("display_code");
    expect(corpo).toContain("unit_id");
    expect(corpo).toContain("physical_photo_id_checked");
    for (const proibido of [
      "bridge_id", "validator_role", "company_id", "snapshot_", "correlation",
    ]) {
      expect(corpo, proibido).not.toContain(proibido);
    }
  });

  it("a tela nao guarda o codigo nem o coloca na URL", () => {
    const src = readFileSync(
      resolve(__dirname, "../pages/portal/PortalValidar.tsx"),
      "utf8"
    );
    expect(src).not.toMatch(/localStorage|sessionStorage/);
    expect(src).not.toMatch(/useSearchParams|searchParams|\?qt=/);
    expect(src).not.toMatch(/console\.|logger\./);
    // O caminho legado saiu desta tela.
    expect(src).not.toContain("prepararValidacaoBeneficio");
  });

  it("nenhum codigo de navegador importa assinante, cliente de gateway ou cripto", () => {
    for (const f of [
      "../pages/portal/PortalValidar.tsx",
      "../services/benefitUsageService.ts",
    ]) {
      const src = readFileSync(resolve(__dirname, f), "utf8");
      expect(src, f).not.toMatch(/gatewaySigner|benefitUsageGatewayClient|manualCodeHandler/);
      expect(src, f).not.toMatch(/node:crypto/);
    }
  });

  it("o builder puro deriva tudo da autoridade", () => {
    const a = interpretarAutoridade(AUTORIDADE_RPC);
    const b = montarCreateRequestByCodeBody(CODIGO, "corr-1", a);
    expect(b.display_code).toBe(CODIGO);
    expect(b.request_correlation_id).toBe("corr-1");
    expect(b.validator_bridge_id).toBe(a.validator_bridge_id);
    expect(b.snapshot_branch_city_name).toBe("Vitória");
    expect(b).not.toHaveProperty("public_lookup_id");
    expect(b).not.toHaveProperty("raw_token_secret");
  });
});