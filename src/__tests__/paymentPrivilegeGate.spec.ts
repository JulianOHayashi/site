import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import {
  conciliarWebhook,
  extrairIdentificadorProvedor,
  type Db,
} from "../server/payments/paymentCore";
import { PagarmeClient, loadPagarmeConfig, type FetchLike } from "../server/payments/pagarmeClient";

/**
 * Portão de segurança da autoridade privilegiada.
 *
 * A pergunta que estes testes respondem é uma só: introduzir
 * SUPABASE_SERVICE_ROLE_KEY em duas rotas serverless públicas dá a um
 * chamador não confiável autoridade arbitrária de banco?
 *
 * A resposta tem de ser não, e por construção — não por disciplina de quem
 * escreve a próxima linha.
 */

const ENV = {
  PAGARME_SECRET_KEY: "sk_test_naousar_" + "0".repeat(20),
  PAGARME_API_BASE_URL: "https://sandbox.exemplo.test/core/v5",
};

const RAIZ = resolve(__dirname, "..");
const NUCLEO = readFileSync(resolve(RAIZ, "server/payments/paymentCore.ts"), "utf8");
const CREATE = readFileSync(resolve(__dirname, "../../api/payments/create.ts"), "utf8");
const WEBHOOK = readFileSync(resolve(__dirname, "../../api/payments/webhook.ts"), "utf8");

function provedor(resposta: Record<string, unknown>, ok = true) {
  const impl: FetchLike = async () => ({
    status: ok ? 200 : 500,
    ok,
    text: async () => JSON.stringify(resposta),
  });
  return new PagarmeClient(loadPagarmeConfig(ENV), impl);
}

function dbEspiao(over: Record<string, unknown> = {}) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const db: Db = {
    rpc: async (fn, args) => {
      chamadas.push({ fn, args });
      if (fn === "prov_find_commercial_payment_by_provider_order") {
        return { data: over.lookup ?? { ok: true, payment_id: "pay-A" }, error: null };
      }
      if (fn === "prov_confirm_commercial_payment") {
        return { data: over.confirm ?? { ok: false, reason: "amount_mismatch" }, error: null };
      }
      return { data: null, error: { message: "rpc inesperada" } };
    },
  };
  return { db, chamadas };
}

describe("nao existe despachante privilegiado generico", () => {
  it("todo nome de RPC e literal no codigo, nunca dado de requisicao", () => {
    const nomes = [...NUCLEO.matchAll(/\.rpc\(\s*("([a-z_]+)"|\n\s*"([a-z_]+)")/g)].map(
      (m) => m[2] ?? m[3]
    );
    expect(nomes.sort()).toEqual(
      [
        "open_commercial_payment_attempt",
        "prov_confirm_commercial_payment",
        "prov_find_commercial_payment_by_provider_order",
        "prov_record_payment_identifiers",
      ].sort()
    );
    // Nenhuma chamada com nome vindo de variavel.
    expect(NUCLEO).not.toMatch(/\.rpc\(\s*[a-zA-Z_$][\w$]*\s*,/);
  });

  it("nenhum acesso a tabela, SQL cru ou caminho REST arbitrario", () => {
    for (const [nome, src] of [
      ["paymentCore", NUCLEO],
      ["create", CREATE],
      ["webhook", WEBHOOK],
    ] as const) {
      // `.from(` do Supabase abriria tabela arbitraria. Buffer.from nao conta.
      expect(src.replace(/Buffer\.from/g, ""), nome).not.toMatch(/\.from\(/);
      expect(src, nome).not.toMatch(/\.select\(|\.insert\(|\.update\(|\.delete\(/);
      expect(src, nome).not.toMatch(/rest\/v1|\/rpc\/\$\{|execute_sql|raw\(/);
    }
  });

  it("a chave de servico nunca e escolhida por dado de requisicao", () => {
    for (const [nome, src] of [["create", CREATE], ["webhook", WEBHOOK]] as const) {
      // Vem so de process.env, nunca de corpo, query ou cabecalho.
      expect(src, nome).toMatch(/process\.env\.SUPABASE_SERVICE_ROLE_KEY/);
      expect(src, nome).not.toMatch(/req\.(body|query|headers)[^;]*SERVICE_ROLE/);
    }
  });
});

describe("ordem obrigatoria: usuario primeiro, privilegio depois", () => {
  it("a abertura como USUARIO precede a persistencia privilegiada", () => {
    const iUser = NUCLEO.indexOf('dbUser.rpc("open_commercial_payment_attempt"');
    const iPriv = NUCLEO.indexOf('dbPriv.rpc("prov_record_payment_identifiers"');
    expect(iUser).toBeGreaterThan(0);
    expect(iPriv).toBeGreaterThan(iUser);
    // O cliente privilegiado so e instanciado depois da abertura.
    expect(NUCLEO.indexOf("deps.dbPrivilegiado()")).toBeGreaterThan(iUser);
  });

  it("o id do pagamento privilegiado vem da RPC do usuario, nao do corpo", () => {
    const bloco = NUCLEO.slice(
      NUCLEO.indexOf('dbPriv.rpc("prov_record_payment_identifiers"'),
      NUCLEO.indexOf("payment_record_failed")
    );
    expect(bloco).toContain("p_payment_id: a.payment_id");
    // Nada do input do navegador entra aqui.
    expect(bloco).not.toMatch(/input\.|corpo\.|req\./);
  });

  it("o navegador so controla pedido e parcela; o resto e derivado", () => {
    // O endpoint le exatamente dois campos do corpo.
    const leitura = CREATE.slice(CREATE.indexOf("criarPagamento("), CREATE.indexOf("bearer(req.headers)"));
    expect(leitura).toContain("orderId: corpo.order_id");
    expect(leitura).toContain("installments: corpo.installments");
    for (const proibido of [
      "company_id", "amount", "payment_method", "fidelized",
      "reserved_until", "expires_at", "provider_order_id", "status",
    ]) {
      expect(leitura, proibido).not.toContain(proibido);
    }
  });
});

describe("webhook: superficie publica, autoridade nenhuma", () => {
  const corpoForjado = JSON.stringify({
    type: "order.paid",
    data: { id: "or_atacante", status: "paid", amount: 99999999, payment_method: "pix" },
  });

  it("o atacante NAO escolhe qual pagamento local marcar", () => {
    // O unico dado do corpo que atravessa e o identificador do provedor.
    const extrator = NUCLEO.slice(
      NUCLEO.indexOf("export function extrairIdentificadorProvedor"),
      NUCLEO.indexOf("export type WebhookResult")
    );
    expect(extrator).not.toMatch(/payment_id|amount|status|payment_method/);
    // E o p_payment_id da confirmacao vem do lookup do servidor.
    const conf = NUCLEO.slice(
      NUCLEO.indexOf('db.rpc("prov_confirm_commercial_payment"'),
      NUCLEO.indexOf("reconciliation_failed")
    );
    expect(conf).toContain("p_payment_id: l.payment_id");
    expect(conf).not.toMatch(/corpo|body|providerOrderId/);
  });

  it("identificador fora do formato esperado nem chega ao banco", async () => {
    for (const ruim of [
      { data: { id: "../../etc/passwd" } },
      { data: { id: "or'; drop table x; --" } },
      { data: { id: "a".repeat(65) } },
      { data: { id: 123 } },
      {},
    ]) {
      expect(extrairIdentificadorProvedor(ruim)).toBeNull();
    }
  });

  it("corpo forjado com valor gigante NAO paga: o valor vem da API", async () => {
    const { db, chamadas } = dbEspiao();
    const r = await conciliarWebhook(corpoForjado, {
      dbPrivilegiado: () => db,
      provedor: () =>
        provedor({
          id: "or_atacante",
          code: "bdflow-order-A",
          charges: [{ status: "paid", amount: 664441, payment_method: "pix" }],
        }),
    });
    expect(r.ok).toBe(false);
    const conf = chamadas.find((c) => c.fn === "prov_confirm_commercial_payment");
    // 664441 veio da API; 99999999 do corpo forjado foi descartado.
    expect(conf!.args.p_provider_amount_cents).toBe(664441);
    expect(conf!.args.p_provider_amount_cents).not.toBe(99999999);
  });

  it("sem confirmacao do provedor nao ha mutacao alguma", async () => {
    const { db, chamadas } = dbEspiao();
    await expect(
      conciliarWebhook(corpoForjado, {
        dbPrivilegiado: () => db,
        provedor: () => provedor({}, false),
      })
    ).rejects.toMatchObject({ code: "provider_unreachable" });
    // Nem o lookup chegou a acontecer: o GET vem antes.
    expect(chamadas).toHaveLength(0);
  });

  it("pagamento valido do pedido A nao e reaproveitado contra o pedido B", async () => {
    // O lookup resolve o identificador do provedor para o pagamento DELE.
    // Nao existe caminho que pareie provedor-A com pagamento-B.
    const { db, chamadas } = dbEspiao({
      lookup: { ok: true, payment_id: "pay-A" },
      confirm: { ok: false, reason: "reference_mismatch" },
    });
    const r = await conciliarWebhook(corpoForjado, {
      dbPrivilegiado: () => db,
      provedor: () =>
        provedor({
          id: "or_atacante",
          code: "bdflow-order-B",
          charges: [{ status: "paid", amount: 664441, payment_method: "pix" }],
        }),
    });
    expect(r.code).toBe("reference_mismatch");
    const conf = chamadas.find((c) => c.fn === "prov_confirm_commercial_payment");
    expect(conf!.args.p_payment_id).toBe("pay-A");
  });

  it("recurso desconhecido nao vaza existencia nem muda estado", async () => {
    const { db, chamadas } = dbEspiao({ lookup: { ok: false, reason: "not_found" } });
    const r = await conciliarWebhook(corpoForjado, {
      dbPrivilegiado: () => db,
      provedor: () =>
        provedor({ id: "or_atacante", code: "x", charges: [{ status: "paid", amount: 1, payment_method: "pix" }] }),
    });
    expect(r).toEqual({ ok: true, code: "unknown_payment" });
    expect(chamadas.some((c) => c.fn === "prov_confirm_commercial_payment")).toBe(false);
  });
});

describe("segredo nao sai por erro, log nem bundle", () => {
  it("as superficies de pagamento nao registram nada", () => {
    for (const [nome, src] of [
      ["paymentCore", NUCLEO], ["create", CREATE], ["webhook", WEBHOOK],
    ] as const) {
      expect(src, nome).not.toMatch(/console\.|logger\./);
    }
  });

  it("o erro devolvido ao chamador e so um codigo curto", () => {
    for (const [nome, src] of [["create", CREATE], ["webhook", WEBHOOK]] as const) {
      expect(src, nome).not.toMatch(/e\.message|err\.stack|String\(e\)|JSON\.stringify\(e/);
      expect(src, nome).toMatch(/code: e\.code/);
      expect(src, nome).toContain("no-store");
    }
  });

  it("nenhum arquivo de navegador toca provedor ou chave privilegiada", () => {
    const proibidos = [
      /from\s+["'].*server\/payments\//,
      /PAGARME_SECRET_KEY/,
      /SUPABASE_SERVICE_ROLE_KEY/,
      /sk_test|sk_live/,
      /api\.pagar\.me/,
    ];
    const varrer = (dir: string): string[] => {
      const out: string[] = [];
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const p = resolve(dir, e.name);
        if (e.isDirectory()) out.push(...varrer(p));
        else if (/\.tsx?$/.test(e.name)) out.push(p);
      }
      return out;
    };
    for (const pasta of ["pages", "components", "lib", "services", "hooks", "domain"]) {
      let arquivos: string[] = [];
      try {
        arquivos = varrer(resolve(RAIZ, pasta));
      } catch {
        continue;
      }
      for (const a of arquivos) {
        if (a.includes("__tests__")) continue;
        const src = readFileSync(a, "utf8");
        for (const re of proibidos) expect(re.test(src), `${a} :: ${re}`).toBe(false);
      }
    }
  });
});

describe("grants declarados nas migrations", () => {
  const m34 = readFileSync(
    resolve(__dirname, "../../supabase/migrations/20260917120000_commercial_payments_pagarme.sql"),
    "utf8"
  );
  const m35 = readFileSync(
    resolve(__dirname, "../../supabase/migrations/20260918120000_commercial_payment_lookup_status.sql"),
    "utf8"
  );

  it("nenhuma RPC de provedor e concedida a anon ou authenticated", () => {
    for (const [nome, sql] of [["m34", m34], ["m35", m35]] as const) {
      // Nao pode existir GRANT de prov_* para papel de navegador.
      expect(sql, nome).not.toMatch(/GRANT\s+EXECUTE[^;]*prov_[^;]*TO[^;]*\b(anon|authenticated)\b/);
      expect(sql, nome).toMatch(/REVOKE EXECUTE[^;]*prov_[^;]*FROM[^;]*anon/);
    }
  });

  it("as prov_* recusam nao-service_role tambem no corpo, e nao so por grant", () => {
    const guarda = /auth\.role\(\), current_user::text\) <> 'service_role'/g;
    expect((m34.match(guarda) ?? []).length).toBeGreaterThanOrEqual(3);
    expect((m35.match(guarda) ?? []).length).toBeGreaterThanOrEqual(1);
  });

  it("so as operacoes seguras do titular sao expostas a authenticated", () => {
    for (const segura of [
      "open_commercial_payment_attempt",
      "get_my_commercial_payment_status",
    ]) {
      const sql = segura.startsWith("open") ? m34 : m35;
      expect(sql).toMatch(
        new RegExp(`GRANT\\s+EXECUTE ON FUNCTION public\\.${segura}\\(uuid\\)\\s*\\n?\\s*TO authenticated`)
      );
    }
  });
});
