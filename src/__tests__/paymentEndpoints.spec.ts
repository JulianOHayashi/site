import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import {
  PaymentError,
  WEBHOOK_MAX_BYTES,
  conciliarWebhook,
  criarPagamento,
  exigirParcelas,
  extrairIdentificadorProvedor,
  type Db,
} from "../server/payments/paymentCore";
import { PagarmeClient, loadPagarmeConfig, type FetchLike } from "../server/payments/pagarmeClient";

/**
 * Fronteira dos endpoints de pagamento, com o provedor sempre simulado.
 *
 * As regras de estado comercial vivem no SQL e são provadas em
 * `supabase/tests/230_commercial_payments.sql`, contra PostgreSQL 17.6. Aqui
 * se prova o que o HTTP faz e, sobretudo, o que ele se recusa a fazer.
 */

const SEGREDO = "sk_test_naousar_" + "0".repeat(20);
const ENV_PROVEDOR = {
  PAGARME_SECRET_KEY: SEGREDO,
  PAGARME_API_BASE_URL: "https://sandbox.exemplo.test/core/v5",
};
const ORDER = "11111111-1111-4111-8111-111111111111";
const PAY = "22222222-2222-4222-8222-222222222222";
const IDEM = "bdflow-order-" + ORDER;
const ATE = "2026-09-18T12:30:00.000Z";

function aberturaPix(over: Record<string, unknown> = {}) {
  return {
    ok: true, already: false, payment_id: PAY, status: "created",
    payment_method: "pix", amount_cents: 664441, expires_at: ATE,
    idempotency_key: IDEM, ...over,
  };
}

function dbFalso(abertura: unknown, over: Record<string, unknown> = {}) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const db: Db = {
    rpc: async (fn, args) => {
      chamadas.push({ fn, args });
      if (fn === "open_commercial_payment_attempt") return { data: abertura, error: null };
      if (fn === "prov_record_payment_identifiers") return { data: { ok: true }, error: null };
      if (fn === "prov_find_commercial_payment_by_provider_order") {
        return { data: over.lookup ?? { ok: true, payment_id: PAY }, error: null };
      }
      if (fn === "prov_confirm_commercial_payment") {
        return { data: over.confirm ?? { ok: true, status: "paid" }, error: null };
      }
      return { data: null, error: { message: "rpc inesperada" } };
    },
  };
  return { db, chamadas };
}

function provedorFalso(resposta: Record<string, unknown> = {}, ok = true) {
  const envios: Array<{ url: string; method: string; body?: string; headers: Record<string, string> }> = [];
  const impl: FetchLike = async (url, init) => {
    envios.push({ url, ...init });
    return { status: ok ? 200 : 500, ok, text: async () => JSON.stringify(resposta) };
  };
  return { envios, cliente: new PagarmeClient(loadPagarmeConfig(ENV_PROVEDOR), impl) };
}

function deps(abertura: unknown, prov = provedorFalso({ id: "or_1", charges: [] }), over = {}) {
  const { db, chamadas } = dbFalso(abertura, over);
  return {
    d: {
      criarDbDoUsuario: () => db,
      dbPrivilegiado: () => db,
      provedor: () => prov.cliente,
    },
    chamadas,
    envios: prov.envios,
  };
}

beforeEach(() => vi.restoreAllMocks());

describe("autorizacao antes de qualquer chamada ao provedor", () => {
  it("anonimo e recusado sem tocar o provedor", async () => {
    const x = deps(aberturaPix());
    await expect(
      criarPagamento({ orderId: ORDER }, null, x.d)
    ).rejects.toMatchObject({ code: "not_authenticated", status: 401 });
    expect(x.envios).toHaveLength(0);
  });

  it("gerente e titular alheio sao recusados pela RPC, sem tocar o provedor", async () => {
    for (const motivo of ["not_company_owner"]) {
      const x = deps({ ok: false, reason: motivo });
      await expect(
        criarPagamento({ orderId: ORDER }, "jwt", x.d)
      ).rejects.toMatchObject({ code: motivo, status: 403 });
      expect(x.envios).toHaveLength(0);
    }
  });

  it("estado comercial errado ou reserva expirada NAO chama o provedor", async () => {
    for (const motivo of [
      "reservation_expired",
      "intent_not_awaiting_payment",
      "opportunity_not_payment_pending",
      "master_agreement_missing",
      "order_not_signed",
      "already_paid",
    ]) {
      const x = deps({ ok: false, reason: motivo });
      await expect(
        criarPagamento({ orderId: ORDER }, "jwt", x.d)
      ).rejects.toMatchObject({ code: motivo });
      expect(x.envios, motivo).toHaveLength(0);
    }
  });

  it("identificador de pedido malformado reprova antes de tudo", async () => {
    const x = deps(aberturaPix());
    await expect(
      criarPagamento({ orderId: "nao-e-uuid" }, "jwt", x.d)
    ).rejects.toMatchObject({ code: "invalid_order", status: 400 });
    expect(x.chamadas).toHaveLength(0);
  });
});

describe("Pix do nao fidelizado", () => {
  it("cria Pix com valor e prazo do servidor e devolve so o seguro", async () => {
    const prov = provedorFalso({
      id: "or_1",
      charges: [{ id: "ch_1", last_transaction: { qr_code: "000201", qr_code_url: "https://x" } }],
    });
    const x = deps(aberturaPix(), prov);
    const r = await criarPagamento({ orderId: ORDER }, "jwt", x.d);

    expect(r.payment_method).toBe("pix");
    expect(r.amount_cents).toBe(664441);
    expect(r.expires_at).toBe(ATE);
    expect(r.pix_copy_paste).toBe("000201");
    expect(r).not.toHaveProperty("checkout_url");

    const corpo = JSON.parse(x.envios[0].body as string);
    // Prazo autoritativo repassado, nunca recalculado.
    expect(corpo.payments[0].pix.expires_at).toBe(ATE);
    expect(JSON.stringify(corpo)).not.toContain("expires_in");
    expect(corpo.items[0].amount).toBe(664441);
    // Nenhum segredo na resposta ao navegador.
    expect(JSON.stringify(r)).not.toContain(SEGREDO);
  });

  it("no Pix nao ha controle de cartao nem parcelas", async () => {
    const x = deps(aberturaPix());
    const r = await criarPagamento({ orderId: ORDER, installments: 3 }, "jwt", x.d);
    expect(r).not.toHaveProperty("installments");
    expect(r).not.toHaveProperty("checkout_url");
  });
});

describe("cartao do fidelizado", () => {
  const abertura = aberturaPix({ payment_method: "credit_card" });

  it("0 e 7 parcelas sao recusadas; 1..6 passam", () => {
    for (const ruim of [0, 7, -1, 1.5, "3", null, undefined]) {
      expect(() => exigirParcelas(ruim), String(ruim)).toThrow(PaymentError);
    }
    for (const bom of [1, 2, 3, 4, 5, 6]) {
      expect(exigirParcelas(bom)).toBe(bom);
    }
  });

  it("parcela invalida reprova ANTES de chamar o provedor", async () => {
    const x = deps(abertura);
    await expect(
      criarPagamento({ orderId: ORDER, installments: 7 }, "jwt", x.d)
    ).rejects.toMatchObject({ code: "invalid_installments" });
    expect(x.envios).toHaveLength(0);
  });

  it("link hospedado: so cartao, uma sessao, e TODAS as parcelas com o mesmo total", async () => {
    const prov = provedorFalso({ id: "pl_1", url: "https://pag/x" });
    const x = deps(abertura, prov);
    const r = await criarPagamento({ orderId: ORDER, installments: 6 }, "jwt", x.d);

    expect(r.checkout_url).toBe("https://pag/x");
    expect(r).not.toHaveProperty("pix_copy_paste");

    const corpo = JSON.parse(x.envios[0].body as string);
    expect(corpo.payment_settings.accepted_payment_methods).toEqual(["credit_card"]);
    expect(corpo.max_sessions).toBe(1);
    expect(corpo.expires_at).toBe(ATE);
    expect(JSON.stringify(corpo)).not.toMatch(/boleto|"pix"|debit/i);

    const parcelas = corpo.payment_settings.credit_card_settings.installments;
    expect(parcelas).toHaveLength(6);
    // Juros ZERO para o comprador: todo total e o total contratual.
    expect(parcelas.every((p: { total: number }) => p.total === 664441)).toBe(true);
    expect(parcelas.map((p: { number: number }) => p.number)).toEqual([1, 2, 3, 4, 5, 6]);
    // Nenhuma taxa ou MDR aparece no corpo enviado.
    expect(JSON.stringify(corpo)).not.toMatch(/mdr|interest|juros|fee_/i);
  });
});

describe("idempotencia", () => {
  it("a chave estavel acompanha a criacao", async () => {
    const x = deps(aberturaPix());
    await criarPagamento({ orderId: ORDER }, "jwt", x.d);
    expect(x.envios[0].headers["Idempotency-Key"]).toBe(IDEM);
  });

  it("segundo clique devolve a MESMA tentativa sem criar recurso novo", async () => {
    const x = deps(
      aberturaPix({ already: true, status: "pending", provider_charge_id: "ch_1" })
    );
    const r = await criarPagamento({ orderId: ORDER }, "jwt", x.d);
    expect(r.already).toBe(true);
    expect(r.payment_id).toBe(PAY);
    // Nenhuma chamada ao provedor: o recurso ja existe.
    expect(x.envios).toHaveLength(0);
  });

  it("falha do provedor nao abre segunda tentativa", async () => {
    const prov = provedorFalso({}, false);
    const x = deps(aberturaPix(), prov);
    await expect(
      criarPagamento({ orderId: ORDER }, "jwt", x.d)
    ).rejects.toMatchObject({ code: "payment_provider_failed" });
    // O registro local permanece: a retentativa reusa a mesma chave.
    expect(x.chamadas.filter((c) => c.fn === "prov_record_payment_identifiers")).toHaveLength(0);
  });

  it("credencial do provedor ausente falha fechada, sem requisicao sem autenticacao", async () => {
    const { db } = dbFalso(aberturaPix());
    await expect(
      criarPagamento({ orderId: ORDER }, "jwt", {
        criarDbDoUsuario: () => db,
        dbPrivilegiado: () => db,
        provedor: () => {
          throw new (class extends Error {
            code = "payment_provider_not_configured";
          })();
        },
      })
    ).rejects.toMatchObject({ code: "payment_provider_not_configured", status: 503 });
  });
});

describe("webhook: sinal, nunca autoridade", () => {
  const forjado = JSON.stringify({
    type: "order.paid",
    data: { id: "or_1", status: "paid", amount: 999999, payment_method: "pix" },
  });

  it("do corpo sai APENAS o identificador", () => {
    expect(extrairIdentificadorProvedor(JSON.parse(forjado))).toBe("or_1");
    expect(extrairIdentificadorProvedor({ data: { id: "<script>" } })).toBeNull();
    expect(extrairIdentificadorProvedor("texto")).toBeNull();
    expect(extrairIdentificadorProvedor(null)).toBeNull();
  });

  it("corpo forjado dizendo pago NAO produz pago: o valor vem da API", async () => {
    // O provedor devolve a verdade: ainda pendente.
    const prov = provedorFalso({
      id: "or_1", code: IDEM,
      charges: [{ status: "pending", amount: 664441, payment_method: "pix" }],
    });
    const x = deps(aberturaPix(), prov, {
      confirm: { ok: false, reason: "provider_status_not_paid" },
    });
    const r = await conciliarWebhook(forjado, {
      dbPrivilegiado: x.d.dbPrivilegiado,
      provedor: x.d.provedor,
    });
    expect(r.ok).toBe(false);
    expect(r.code).toBe("provider_status_not_paid");

    // O que foi enviado a RPC veio da API, nao do corpo forjado.
    const conf = x.chamadas.find((c) => c.fn === "prov_confirm_commercial_payment");
    expect(conf!.args.p_provider_status).toBe("pending");
    expect(conf!.args.p_provider_amount_cents).toBe(664441);
    expect(conf!.args.p_provider_amount_cents).not.toBe(999999);
  });

  it("divergencia de valor, metodo ou referencia nao paga", async () => {
    for (const motivo of ["amount_mismatch", "method_mismatch", "reference_mismatch"]) {
      const prov = provedorFalso({
        id: "or_1", code: IDEM,
        charges: [{ status: "paid", amount: 1, payment_method: "pix" }],
      });
      const x = deps(aberturaPix(), prov, { confirm: { ok: false, reason: motivo } });
      const r = await conciliarWebhook(forjado, {
        dbPrivilegiado: x.d.dbPrivilegiado,
        provedor: x.d.provedor,
      });
      expect(r.ok, motivo).toBe(false);
      expect(r.code).toBe(motivo);
    }
  });

  it("provedor inalcancavel nao paga", async () => {
    const prov = provedorFalso({}, false);
    const x = deps(aberturaPix(), prov);
    await expect(
      conciliarWebhook(forjado, {
        dbPrivilegiado: x.d.dbPrivilegiado,
        provedor: x.d.provedor,
      })
    ).rejects.toMatchObject({ code: "provider_unreachable" });
  });

  it("conciliacao verificada paga, e o reenvio e idempotente", async () => {
    const prov = provedorFalso({
      id: "or_1", code: IDEM,
      charges: [{ status: "paid", amount: 664441, payment_method: "pix" }],
    });
    const x = deps(aberturaPix(), prov, { confirm: { ok: true, status: "paid" } });
    const r = await conciliarWebhook(forjado, {
      dbPrivilegiado: x.d.dbPrivilegiado,
      provedor: x.d.provedor,
    });
    expect(r).toMatchObject({ ok: true, code: "paid", payment_id: PAY });

    const y = deps(aberturaPix(), prov, {
      confirm: { ok: true, already: true, status: "paid" },
    });
    const r2 = await conciliarWebhook(forjado, {
      dbPrivilegiado: y.d.dbPrivilegiado,
      provedor: y.d.provedor,
    });
    expect(r2.code).toBe("already_paid");
  });

  it("pagamento tardio devolve late_unreconciled, sem contratar", async () => {
    const prov = provedorFalso({
      id: "or_1", code: IDEM,
      charges: [{ status: "paid", amount: 664441, payment_method: "pix" }],
    });
    const x = deps(aberturaPix(), prov, {
      confirm: { ok: false, reason: "late_payment_unreconciled" },
    });
    const r = await conciliarWebhook(forjado, {
      dbPrivilegiado: x.d.dbPrivilegiado,
      provedor: x.d.provedor,
    });
    expect(r).toMatchObject({ ok: false, code: "late_payment_unreconciled" });
  });

  it("pagamento desconhecido nao vaza nada e nao muda estado", async () => {
    const prov = provedorFalso({ id: "or_1", charges: [] });
    const x = deps(aberturaPix(), prov, { lookup: { ok: false, reason: "not_found" } });
    const r = await conciliarWebhook(forjado, {
      dbPrivilegiado: x.d.dbPrivilegiado,
      provedor: x.d.provedor,
    });
    expect(r).toEqual({ ok: true, code: "unknown_payment" });
    expect(x.chamadas.some((c) => c.fn === "prov_confirm_commercial_payment")).toBe(false);
  });

  it("corpo gigante ou malformado e recusado sem parsear", async () => {
    const x = deps(aberturaPix());
    await expect(
      conciliarWebhook("x".repeat(WEBHOOK_MAX_BYTES + 1), {
        dbPrivilegiado: x.d.dbPrivilegiado,
        provedor: x.d.provedor,
      })
    ).rejects.toMatchObject({ code: "payload_too_large", status: 413 });
    await expect(
      conciliarWebhook("{nao-e-json", {
        dbPrivilegiado: x.d.dbPrivilegiado,
        provedor: x.d.provedor,
      })
    ).rejects.toMatchObject({ code: "malformed_payload", status: 400 });
  });
});

describe("isolamento de credencial", () => {
  it("nenhum codigo de navegador alcanca o provedor ou a chave de servico", () => {
    const raiz = resolve(__dirname, "..");
    const proibidos = [
      /from\s+["'].*server\/payments\//,
      /PAGARME_SECRET_KEY/,
      /SUPABASE_SERVICE_ROLE_KEY/,
      /sk_test|sk_live/,
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

  it("os endpoints nao devolvem objeto completo do provedor", () => {
    for (const f of ["../../api/payments/create.ts", "../../api/payments/webhook.ts"]) {
      const src = readFileSync(resolve(__dirname, f), "utf8");
      expect(src).not.toMatch(/console\.|logger\./);
      expect(src).not.toMatch(/VITE_PAGARME/);
      expect(src).toContain("no-store");
    }
  });
});
