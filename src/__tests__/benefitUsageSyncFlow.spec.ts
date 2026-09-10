import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { generateKeyPairSync } from "node:crypto";
import {
  capturarFragmento,
  descartarSegredoCapturado,
  interpretarLocalizacao,
  lerSegredoCapturado,
} from "../lib/benefitTokenFragment";
import {
  BenefitUsageError,
  montarCreateRequestBody,
  montarOpenTokenBody,
  interpretarAutoridade,
  type BenefitUsageAuthority,
} from "../server/benefitUsage/benefitUsageContract";
import { BenefitUsageGatewayClient } from "../server/benefitUsage/benefitUsageGatewayClient";
import { executarUsoDeBeneficio } from "../server/benefitUsage/validateHandler";
import { loadGatewayConfig } from "../server/provisioning/gatewaySigner";

const SEGREDO = "a".repeat(64);
const LOCATOR = "11111111-2222-4333-8444-555555555555";
const UNIT = "66666666-7777-4888-8999-aaaaaaaaaaaa";

/** Chave descartável: existe só na memória deste processo de teste. */
const par = generateKeyPairSync("ed25519");
const envGateway: Record<string, string> = {
  BDFLOW_APP_BRIDGE_URL: "https://app.exemplo.test/functions/v1",
  BDFLOW_APP_BRIDGE_KEY_ID: "kid-teste",
  BDFLOW_APP_BRIDGE_SIGNING_KEY: par.privateKey
    .export({ format: "der", type: "pkcs8" })
    .toString("base64"),
  BDFLOW_APP_BRIDGE_ISSUER: "bdflow-site-gate3-http",
  BDFLOW_APP_BRIDGE_AUDIENCE: "bdflow-app-gateway",
};

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

function dbFalso(over: Partial<Record<string, unknown>> = {}) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const db = {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      if (fn === "get_my_benefit_usage_authority") {
        return { data: over.autoridade ?? AUTORIDADE_RPC, error: null };
      }
      if (fn === "prepare_benefit_validation") {
        return {
          data: over.auditoria ?? { ok: true, allowed: true, attempt_id: "x" },
          error: null,
        };
      }
      return { data: null, error: { message: "rpc desconhecida" } };
    },
  };
  return { db, chamadas };
}

function gatewayFalso(over: { open?: unknown; create?: unknown } = {}) {
  const enviados: Array<{
    url: string;
    headers: Record<string, string>;
    body: string;
  }> = [];
  const cliente = new BenefitUsageGatewayClient(
    loadGatewayConfig(envGateway),
    async (url, init) => {
      enviados.push({ url, headers: init.headers, body: init.body });
      const aberto = url.endsWith("/token/open");
      const corpo = aberto
        ? (over.open ?? { usage_request_may_follow: true })
        : (over.create ?? { status: "awaiting_user_confirmation" });
      const ok = (corpo as Record<string, unknown>).__falha !== true;
      return { status: ok ? 200 : 409, ok, text: async () => JSON.stringify(corpo) };
    }
  );
  return { cliente, enviados };
}

function depsPadrao(over: Parameters<typeof dbFalso>[0] = {}, gw = gatewayFalso()) {
  const { db, chamadas } = dbFalso(over);
  return {
    deps: {
      criarDbDoUsuario: () => db,
      gateway: gw.cliente,
      novoCorrelationId: () => "99999999-0000-4000-8000-000000000000",
    },
    chamadas,
    enviados: gw.enviados,
  };
}

const entrada = {
  publicLookupId: LOCATOR,
  rawTokenSecret: SEGREDO,
  unitId: UNIT,
  physicalPhotoIdChecked: true,
};

// ---------------------------------------------------------------------------
// Navegador: locator e fragmento
// ---------------------------------------------------------------------------
describe("captura do fragmento no navegador", () => {
  beforeEach(() => descartarSegredoCapturado());

  it("1 e 2. extrai o locator do caminho e o segredo do fragmento", () => {
    const r = interpretarLocalizacao(`/beneficios/validar/${LOCATOR}`, `#${SEGREDO}`);
    expect(r).toEqual({
      tipo: "capturado",
      publicLookupId: LOCATOR,
      rawSecret: SEGREDO,
    });
  });

  it("3. o fragmento some da URL visível assim que é capturado", () => {
    const replaceState = vi.fn();
    const win = {
      location: {
        pathname: `/beneficios/validar/${LOCATOR}`,
        search: "",
        hash: `#${SEGREDO}`,
      },
      history: { replaceState },
    } as unknown as Window;

    const r = capturarFragmento(win);
    expect(r.tipo).toBe("capturado");
    expect(lerSegredoCapturado()).toBe(SEGREDO);
    expect(replaceState).toHaveBeenCalledWith(
      null,
      "",
      `/beneficios/validar/${LOCATOR}`
    );
    // O segredo NUNCA vira query string.
    expect(String(replaceState.mock.calls[0][2])).not.toContain(SEGREDO);
  });

  it("4. locator malformado é recusado", () => {
    expect(
      interpretarLocalizacao("/beneficios/validar", `#${SEGREDO}`).tipo
    ).toBe("ignorado");
    expect(
      executarUsoDeBeneficio(
        { ...entrada, publicLookupId: "nao-e-uuid" },
        "jwt",
        depsPadrao().deps
      )
    ).rejects.toMatchObject({ code: "invalid_locator" });
  });

  it("5. segredo cru malformado é recusado (tamanho, maiúsculas, ausência)", () => {
    for (const ruim of ["", "abc", "A".repeat(64), "a".repeat(63), "z".repeat(64)]) {
      expect(
        interpretarLocalizacao(`/beneficios/validar/${LOCATOR}`, `#${ruim}`).tipo
      ).toBe("invalido");
    }
  });

  it("não usa localStorage nem sessionStorage em lugar nenhum do fluxo", () => {
    const dir = resolve(__dirname, "..");
    const alvos = [
      "lib/benefitTokenFragment.ts",
      "services/benefitUsageService.ts",
      "pages/beneficios/BeneficiosValidar.tsx",
    ];
    for (const a of alvos) {
      const src = readFileSync(resolve(dir, a), "utf8");
      expect(src, a).not.toMatch(/localStorage|sessionStorage/);
    }
  });
});

// ---------------------------------------------------------------------------
// Autorização, antes de qualquer chamada ao App
// ---------------------------------------------------------------------------
describe("autorização do Site precede o gateway", () => {
  it("6. sem sessão: recusa antes de tocar o gateway", async () => {
    const { deps, enviados } = depsPadrao();
    await expect(
      executarUsoDeBeneficio(entrada, null, deps)
    ).rejects.toMatchObject({ code: "not_authenticated", status: 401 });
    expect(enviados).toHaveLength(0);
  });

  it("7 e 8. parceiro/gestor não autorizado: recusa antes do gateway", async () => {
    const { deps, enviados } = depsPadrao({
      autoridade: { ok: true, authorized: false, reason: "not_authorized" },
    });
    await expect(
      executarUsoDeBeneficio(entrada, "jwt", deps)
    ).rejects.toMatchObject({ code: "not_authorized", status: 403 });
    // A RPC nega gestor sem vínculo com a unidade pelo mesmo caminho.
    expect(enviados).toHaveLength(0);
  });

  it("9. responsável autorizado conclui as duas chamadas", async () => {
    const { deps, enviados } = depsPadrao();
    const r = await executarUsoDeBeneficio(entrada, "jwt", deps);
    expect(r.ok).toBe(true);
    expect(r.status).toBe("request_created");
    expect(enviados).toHaveLength(2);
  });

  it("15. sem confirmação do documento com foto, nada é enviado", async () => {
    for (const v of [false, undefined, "true", 1]) {
      const { deps, enviados } = depsPadrao();
      await expect(
        executarUsoDeBeneficio(
          { ...entrada, physicalPhotoIdChecked: v },
          "jwt",
          deps
        )
      ).rejects.toMatchObject({ code: "photo_id_check_required" });
      expect(enviados).toHaveLength(0);
    }
  });
});

// ---------------------------------------------------------------------------
// Autoridade derivada no servidor
// ---------------------------------------------------------------------------
describe("identidades autoritativas", () => {
  it("10. o servidor consulta a RPC passando SÓ a unidade escolhida", async () => {
    const { deps, chamadas } = depsPadrao();
    await executarUsoDeBeneficio(entrada, "jwt", deps);
    const autoridade = chamadas.find(
      (c) => c.fn === "get_my_benefit_usage_authority"
    );
    expect(autoridade).toBeTruthy();
    expect(Object.keys(autoridade!.args)).toEqual(["p_unit_id"]);
    expect(autoridade!.args.p_unit_id).toBe(UNIT);
  });

  it("11. pontes forjadas pelo navegador não alteram o que é enviado", async () => {
    const { deps, enviados } = depsPadrao();
    const forjado = {
      ...entrada,
      // Campos que um balconista poderia inventar no console:
      partner_network_bridge_id: "00000000-0000-4000-8000-000000000000",
      partner_branch_bridge_id: "00000000-0000-4000-8000-000000000001",
      validator_bridge_id: "00000000-0000-4000-8000-000000000002",
      validator_role: "partner_owner",
      snapshot_partner_display_name: "Loja Falsa",
      snapshot_branch_state_code: "SP",
    } as never;
    await executarUsoDeBeneficio(forjado, "jwt", deps);

    const criado = JSON.parse(enviados[1].body);
    expect(criado.partner_network_bridge_id).toBe(
      AUTORIDADE_RPC.partner_network_bridge_id
    );
    expect(criado.partner_branch_bridge_id).toBe(
      AUTORIDADE_RPC.partner_branch_bridge_id
    );
    expect(criado.validator_bridge_id).toBe(AUTORIDADE_RPC.validator_bridge_id);
    expect(criado.snapshot_partner_display_name).toBe("Mercado Litoral");
    expect(criado.snapshot_branch_state_code).toBe("ES");
    expect(JSON.stringify(criado)).not.toContain("Loja Falsa");
    expect(JSON.stringify(criado)).not.toContain(
      "00000000-0000-4000-8000-000000000000"
    );
  });

  it("12. mapeamento de snapshot sai da autoridade, campo a campo", () => {
    const a = interpretarAutoridade(AUTORIDADE_RPC);
    const body = montarCreateRequestBody(LOCATOR, SEGREDO, "corr", a);
    expect(body.snapshot_partner_display_name).toBe(
      AUTORIDADE_RPC.snapshot_partner_display_name
    );
    expect(body.snapshot_branch_display_name).toBe(
      AUTORIDADE_RPC.snapshot_branch_display_name
    );
    expect(body.snapshot_branch_city_name).toBe("Vitória");
    expect(body.snapshot_branch_state_code).toBe("ES");
    expect(body.snapshot_presentation_version).toBe(1);
  });

  it("13. trade_name vazio cai para legal_name (regra na RPC, provada no SQL)", () => {
    // A regra vive na migration; aqui prova-se que o SQL a expressa.
    const sql = readFileSync(
      resolve(
        __dirname,
        "../../supabase/migrations/20260909120000_benefit_usage_authority_rpc.sql"
      ),
      "utf8"
    );
    expect(sql).toContain(
      "coalesce(nullif(pg_catalog.btrim(coalesce(v_comp.trade_name, '')), ''),"
    );
    expect(sql).toContain("v_comp.legal_name)");
  });

  it("14. o rótulo de localização é exatamente cidade/UF, derivado", () => {
    const a = interpretarAutoridade(AUTORIDADE_RPC);
    expect(a.snapshot_branch_location_label).toBe(
      `${a.snapshot_branch_city_name}/${a.snapshot_branch_state_code}`
    );
    const sql = readFileSync(
      resolve(
        __dirname,
        "../../supabase/migrations/20260909120000_benefit_usage_authority_rpc.sql"
      ),
      "utf8"
    );
    expect(sql).toContain("v_unit.city || '/' || v_unit.uf");
    // Sem coluna nova para o rótulo.
    expect(sql).not.toMatch(/ADD COLUMN|ALTER TABLE/i);
  });
});

// ---------------------------------------------------------------------------
// Sequência do gateway
// ---------------------------------------------------------------------------
describe("sequência das duas chamadas", () => {
  it("16. token/open acontece antes de create_request", async () => {
    const { deps, enviados } = depsPadrao();
    await executarUsoDeBeneficio(entrada, "jwt", deps);
    expect(enviados[0].url).toContain("/v1/benefit-usage/token/open");
    expect(enviados[1].url).toContain("/v1/benefit-usage/request");
  });

  it("17. open recusado: create_request NÃO acontece e nada vira sucesso", async () => {
    for (const open of [
      { usage_request_may_follow: false },
      { __falha: true },
      {},
    ]) {
      const gw = gatewayFalso({ open });
      const { deps } = depsPadrao({}, gw);
      await expect(
        executarUsoDeBeneficio(entrada, "jwt", deps)
      ).rejects.toMatchObject({ code: "token_open_denied" });
      expect(gw.enviados).toHaveLength(1);
    }
  });

  it("18 e 19. mesmo segredo e mesma rede nas duas chamadas, sem persistir", async () => {
    const { deps, enviados, chamadas } = depsPadrao();
    await executarUsoDeBeneficio(entrada, "jwt", deps);
    const aberto = JSON.parse(enviados[0].body);
    const criado = JSON.parse(enviados[1].body);
    expect(aberto.raw_token_secret).toBe(SEGREDO);
    expect(criado.raw_token_secret).toBe(SEGREDO);
    expect(aberto.partner_network_bridge_id).toBe(
      criado.partner_network_bridge_id
    );
    // A auditoria recebe o token para HASHEAR — o Site nunca guarda o cru.
    const auditoria = chamadas.find((c) => c.fn === "prepare_benefit_validation");
    expect(auditoria).toBeTruthy();
    const sql = readFileSync(
      resolve(
        __dirname,
        "../../supabase/migrations/20260822129000_m2_benefit_validation.sql"
      ),
      "utf8"
    );
    expect(sql).toContain("token_hash     bytea       NOT NULL");
    expect(sql).toContain("v_hash := public.m1_token_hash");
  });

  it("20. request_correlation_id é UUID e é o mesmo nas duas chamadas", async () => {
    const { deps, enviados } = depsPadrao();
    const r = await executarUsoDeBeneficio(entrada, "jwt", {
      ...depsPadrao().deps,
      gateway: deps.gateway,
      criarDbDoUsuario: deps.criarDbDoUsuario,
      novoCorrelationId: undefined,
    });
    expect(r.request_correlation_id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    );
    const env0 = JSON.parse(
      Buffer.from(
        enviados[0].headers["X-BDFlow-Gateway-Signature"].split(".")[1],
        "base64url"
      ).toString("utf8")
    );
    const env1 = JSON.parse(
      Buffer.from(
        enviados[1].headers["X-BDFlow-Gateway-Signature"].split(".")[1],
        "base64url"
      ).toString("utf8")
    );
    expect(env0.request_correlation_id).toBe(env1.request_correlation_id);
  });

  it("nunca há retentativa automática com outro correlation id", async () => {
    const gw = gatewayFalso({ create: { __falha: true } });
    const { deps } = depsPadrao({}, gw);
    await expect(
      executarUsoDeBeneficio(entrada, "jwt", deps)
    ).rejects.toMatchObject({ code: "request_denied" });
    expect(gw.enviados).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// Contrato exato e vazamento
// ---------------------------------------------------------------------------
describe("contrato do App e segredo", () => {
  it("23. corpos têm exatamente os campos exigidos", () => {
    const a = interpretarAutoridade(AUTORIDADE_RPC) as BenefitUsageAuthority;
    expect(Object.keys(montarOpenTokenBody(LOCATOR, SEGREDO, a)).sort()).toEqual(
      ["partner_network_bridge_id", "public_lookup_id", "raw_token_secret"].sort()
    );
    expect(
      Object.keys(montarCreateRequestBody(LOCATOR, SEGREDO, "corr", a)).sort()
    ).toEqual(
      [
        "public_lookup_id",
        "raw_token_secret",
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
  });

  it("24. rotas lógicas e ações assinadas são exatas", async () => {
    const { deps, enviados } = depsPadrao();
    await executarUsoDeBeneficio(entrada, "jwt", deps);
    const env = (i: number) =>
      JSON.parse(
        Buffer.from(
          enviados[i].headers["X-BDFlow-Gateway-Signature"].split(".")[1],
          "base64url"
        ).toString("utf8")
      );
    expect(env(0).action).toBe("benefit_usage.open_token");
    expect(env(0).gateway_path).toBe("/v1/benefit-usage/token/open");
    expect(env(1).action).toBe("benefit_usage.create_request");
    expect(env(1).gateway_path).toBe("/v1/benefit-usage/request");
    expect(env(1).presentation_contract_version).toBe(1);
    // O prefixo de Edge Function fica na URL, nunca no caminho assinado.
    expect(env(0).gateway_path).not.toContain("/functions/");
    expect(env(0).issuer).toBe("bdflow-site-gate3-http");
    expect(env(0).audience).toBe("bdflow-app-gateway");
    expect(env(0).protocol_version).toBe("bdflow-gateway/1");
  });

  it("22. segredo e chave não aparecem em erro nem em log", async () => {
    const logs: string[] = [];
    const spyErr = vi
      .spyOn(console, "error")
      .mockImplementation((...a) => logs.push(a.map(String).join(" ")));
    const spyLog = vi
      .spyOn(console, "log")
      .mockImplementation((...a) => logs.push(a.map(String).join(" ")));

    const gw = gatewayFalso({ open: { usage_request_may_follow: false } });
    const { deps } = depsPadrao({}, gw);
    let erro: BenefitUsageError | null = null;
    try {
      await executarUsoDeBeneficio(entrada, "jwt", deps);
    } catch (e) {
      erro = e as BenefitUsageError;
      console.error(e);
    }
    spyErr.mockRestore();
    spyLog.mockRestore();

    expect(erro).not.toBeNull();
    expect(erro!.message).not.toContain(SEGREDO);
    expect(erro!.stack ?? "").not.toContain(SEGREDO);
    expect(logs.join("\n")).not.toContain(SEGREDO);
    expect(logs.join("\n")).not.toContain(
      envGateway.BDFLOW_APP_BRIDGE_SIGNING_KEY
    );
  });

  it("25. a resposta ao navegador não carrega segredo nem interno do App", async () => {
    const { deps } = depsPadrao();
    const r = await executarUsoDeBeneficio(entrada, "jwt", deps);
    const texto = JSON.stringify(r);
    expect(texto).not.toContain(SEGREDO);
    expect(texto).not.toContain(envGateway.BDFLOW_APP_BRIDGE_SIGNING_KEY);
    expect(texto).not.toContain(AUTORIDADE_RPC.validator_bridge_id);
    expect(texto).not.toContain(AUTORIDADE_RPC.partner_network_bridge_id);
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
  });

  it("21. nada de servidor é alcançável a partir de código de navegador", () => {
    // O assinante e o endpoint moram em src/server e api/. Se uma pagina,
    // componente ou lib importasse qualquer um deles, o segredo entraria no
    // bundle do cliente — por isso a proibicao e verificada no grafo, nao no
    // artefato construido.
    const raiz = resolve(__dirname, "..");
    const proibidos = [
      /from\s+["'].*server\/provisioning\/gatewaySigner/,
      /from\s+["'].*server\/provisioning\/gatewayTransport/,
      /from\s+["'].*server\/benefitUsage\/benefitUsageGatewayClient/,
      /from\s+["'].*server\/benefitUsage\/validateHandler/,
      /from\s+["'].*server\/worker\//,
      /node:crypto/,
    ];
    const varrer = (dir: string): string[] => {
      const saida: string[] = [];
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const p = resolve(dir, e.name);
        if (e.isDirectory()) saida.push(...varrer(p));
        else if (/\.tsx?$/.test(e.name)) saida.push(p);
      }
      return saida;
    };
    for (const pasta of ["pages", "components", "lib", "services"]) {
      const dir = resolve(raiz, pasta);
      if (!existsSync(dir)) continue;
      for (const arquivo of varrer(dir)) {
        if (arquivo.includes("__tests__")) continue;
        const src = readFileSync(arquivo, "utf8");
        for (const re of proibidos) {
          expect(re.test(src), `${arquivo} :: ${re}`).toBe(false);
        }
      }
    }
  });
});
