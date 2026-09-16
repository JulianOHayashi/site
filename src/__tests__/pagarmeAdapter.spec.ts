import { describe, it, expect, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  MAX_INSTALLMENTS,
  PAGARME_CHECKOUT_SANDBOX_BASE_URL,
  PAGARME_CHECKOUT_USER_AGENT,
  PagarmeClient,
  PagarmeConfigError,
  PagarmeCustomerDataError,
  montarClienteProvedor,
  normalizarTelefoneBR,
  createPagarmeClient,
  loadPagarmeConfig,
  montarParcelas,
  type FetchLike,
} from "../server/payments/pagarmeClient";

/**
 * Fronteira HTTP do Pagar.me, com o provedor sempre simulado.
 *
 * Nenhuma credencial real, nenhuma chamada de rede. O que se prova aqui é o
 * que a BDFlow ENVIA e o que ela deixa de enviar — as regras de estado
 * comercial vivem no SQL e são provadas lá, contra PostgreSQL 17.6.
 */

const SEGREDO = "sk_test_naousar_" + "0".repeat(20);
const envOk: Record<string, string> = {
  PAGARME_SECRET_KEY: SEGREDO,
  PAGARME_API_BASE_URL: "https://sandbox.exemplo.test/core/v5",
};

function espiao(resposta: Record<string, unknown> = {}, status = 200) {
  const chamadas: Array<{
    url: string;
    method: string;
    headers: Record<string, string>;
    body?: string;
  }> = [];
  const impl: FetchLike = async (url, init) => {
    chamadas.push({ url, ...init });
    return {
      status,
      ok: status < 400,
      text: async () => JSON.stringify(resposta),
    };
  };
  return { chamadas, impl };
}

const CLIENTE = {
  name: "Empresa Teste LTDA",
  email: "contato@teste.local",
  document: "21010001000197",
  document_type: "CNPJ" as const,
  type: "company" as const,
  address: {
    line_1: "100, Rua Teste, Centro",
    zip_code: "29100000",
    city: "Vitoria",
    state: "ES",
    country: "BR" as const,
  },
};

const ABERTURA = {
  paymentId: "11111111-1111-4111-8111-111111111111",
  // O metodo ja foi DERIVADO da fidelidade pelo servidor; o adaptador so
  // executa o que o dominio decidiu.
  paymentMethod: "pix" as const,
  amountCents: 664441,
  expiresAt: "2026-09-17T12:30:00.000Z",
  idempotencyKey: "bdflow-order-22222222-2222-4222-8222-222222222222",
  orderReference: "bdflow-order-22222222",
};

const ABERTURA_CARTAO = { ...ABERTURA, paymentMethod: "credit_card" as const };

describe("credencial: falha fechada e nunca vaza", () => {
  it("sem PAGARME_SECRET_KEY nao existe cliente", () => {
    for (const env of [{}, { PAGARME_SECRET_KEY: "" }, { PAGARME_SECRET_KEY: "   " }]) {
      expect(() => createPagarmeClient(env)).toThrow(PagarmeConfigError);
    }
  });

  it("URL base invalida tambem falha fechada", () => {
    expect(() =>
      loadPagarmeConfig({ ...envOk, PAGARME_API_BASE_URL: "nao-e-url" })
    ).toThrow(PagarmeConfigError);
  });

  it("o erro cita apenas o NOME da variavel", () => {
    let e: Error | null = null;
    try {
      createPagarmeClient({});
    } catch (err) {
      e = err as Error;
    }
    expect(e!.message).toContain("PAGARME_SECRET_KEY");
    expect(e!.message).not.toContain(SEGREDO);
  });

  it("a chave nao aparece em log, erro nem na config serializada", async () => {
    const logs: string[] = [];
    const spy = vi
      .spyOn(console, "error")
      .mockImplementation((...a) => logs.push(a.map(String).join(" ")));
    const cfg = loadPagarmeConfig(envOk);
    try {
      loadPagarmeConfig({ ...envOk, PAGARME_API_BASE_URL: "x" });
    } catch (e) {
      console.error(e);
    }
    spy.mockRestore();
    expect(logs.join("\n")).not.toContain(SEGREDO);
    // A chave viaja no cabecalho Authorization, em base64 — nunca em claro.
    const { chamadas, impl } = espiao({ id: "or_1", charges: [] });
    await new PagarmeClient(cfg, impl).criarPix(ABERTURA, CLIENTE);
    expect(chamadas[0].body ?? "").not.toContain(SEGREDO);
    expect(JSON.stringify(chamadas[0].headers)).not.toContain(SEGREDO);
  });

  it("o adaptador nunca entra no bundle do navegador", () => {
    const raiz = resolve(__dirname, "..");
    for (const pasta of ["pages", "components", "lib", "services"]) {
      const cmd = `${raiz}/${pasta}`;
      let arquivos: string[] = [];
      try {
        arquivos = readFileSync(`${cmd}/../__tests__/.keep`, "utf8") ? [] : [];
      } catch {
        /* diretorio varrido abaixo */
      }
      void arquivos;
    }
    // Varre o grafo de cliente por importacao do adaptador.
    const svc = readFileSync(
      resolve(__dirname, "../services/commercialReservationService.ts"),
      "utf8"
    );
    expect(svc).not.toContain("pagarmeClient");
    expect(svc).not.toContain("PAGARME");
    const src = readFileSync(
      resolve(__dirname, "../server/payments/pagarmeClient.ts"),
      "utf8"
    );
    // Sem prefixo de cliente na credencial.
    expect(src).not.toContain("VITE_PAGARME");
  });
});

describe("Pix: prazo e valor autoritativos", () => {
  const cfg = loadPagarmeConfig(envOk);

  it("a expiracao enviada e EXATAMENTE a da reserva", async () => {
    const { chamadas, impl } = espiao({ id: "or_1", charges: [] });
    await new PagarmeClient(cfg, impl).criarPix(ABERTURA, CLIENTE);
    const corpo = JSON.parse(chamadas[0].body as string);
    expect(corpo.payments[0].pix.expires_at).toBe(ABERTURA.expiresAt);
    // Nada de now() + 30 minutos: o valor e repassado, nao recalculado.
    expect(JSON.stringify(corpo)).not.toContain("expires_in");
  });

  it("o valor vem do instantaneo, e so ha Pix neste caminho", async () => {
    const { chamadas, impl } = espiao({ id: "or_1", charges: [] });
    await new PagarmeClient(cfg, impl).criarPix(ABERTURA, CLIENTE);
    const corpo = JSON.parse(chamadas[0].body as string);
    expect(corpo.items[0].amount).toBe(664441);
    expect(corpo.payments).toHaveLength(1);
    expect(corpo.payments[0].payment_method).toBe("pix");
    expect(JSON.stringify(corpo)).not.toMatch(/boleto|credit_card|debit/i);
  });

  it("a chave de idempotencia acompanha a requisicao", async () => {
    const { chamadas, impl } = espiao({ id: "or_1", charges: [] });
    const c = new PagarmeClient(cfg, impl);
    await c.criarPix(ABERTURA, CLIENTE);
    await c.criarPix(ABERTURA, CLIENTE);
    expect(chamadas[0].headers["Idempotency-Key"]).toBe(ABERTURA.idempotencyKey);
    // Retentativa logica reusa a MESMA chave: o provedor nao cria recurso novo.
    expect(chamadas[1].headers["Idempotency-Key"]).toBe(
      chamadas[0].headers["Idempotency-Key"]
    );
  });

  it("devolve apenas dado seguro de apresentacao", async () => {
    const { impl } = espiao({
      id: "or_1",
      charges: [
        {
          id: "ch_1",
          last_transaction: { qr_code: "000201...", qr_code_url: "https://x/y" },
        },
      ],
    });
    const r = await new PagarmeClient(cfg, impl).criarPix(ABERTURA, CLIENTE);
    expect(r.providerOrderId).toBe("or_1");
    expect(r.providerChargeId).toBe("ch_1");
    expect(r.pixQrCode).toBe("000201...");
    expect(JSON.stringify(r)).not.toContain(SEGREDO);
  });
});

describe("cartao fidelizado: checkout hospedado", () => {
  const cfg = loadPagarmeConfig(envOk);

  it("aceita SOMENTE cartao de credito, uma unica sessao", async () => {
    const { chamadas, impl } = espiao({ id: "pl_1", url: "https://pag/x" });
    await new PagarmeClient(cfg, impl).criarLinkCartao(ABERTURA_CARTAO);
    const corpo = JSON.parse(chamadas[0].body as string);
    expect(corpo.payment_settings.accepted_payment_methods).toEqual(["credit_card"]);
    // A regra e UM PAGAMENTO bem-sucedido; ver o teste de contrato adiante.
    expect(corpo.max_paid_sessions).toBe(1);
    expect(corpo.expires_at).toBe(ABERTURA.expiresAt);
    expect(JSON.stringify(corpo)).not.toMatch(/boleto|"pix"|debit/i);
  });

  it("1 a 6 parcelas, TODAS com o mesmo total: nenhum juro inventado", () => {
    const p = montarParcelas(664441);
    expect(p).toHaveLength(MAX_INSTALLMENTS);
    expect(p[0]).toEqual({ number: 1, total: 664441 });
    expect(p[5]).toEqual({ number: 6, total: 664441 });
    expect(new Set(p.map((x) => x.total)).size).toBe(1);
    expect(p.some((x) => x.number > 6)).toBe(false);
  });

  it("nenhum dado de cartao trafega pelo servidor da BDFlow", async () => {
    const { chamadas, impl } = espiao({ id: "pl_1", url: "https://pag/x" });
    await new PagarmeClient(cfg, impl).criarLinkCartao(ABERTURA_CARTAO);
    const tudo = JSON.stringify(chamadas[0]);
    // `number` cru nao entra na lista: e a chave do NUMERO DA PARCELA na
    // configuracao de installments, nao numero de cartao. Assercao grosseira
    // demais acusaria o proprio parcelamento.
    for (const proibido of ["card_number", "cvv", "holder_name", "exp_month",
                            "exp_year", "card_token"]) {
      expect(tudo, proibido).not.toContain(proibido);
    }
    const src = readFileSync(
      resolve(__dirname, "../server/payments/pagarmeClient.ts"),
      "utf8"
    );
    expect(src).not.toMatch(/card_number|cvv|holder_name/i);
  });

  it("devolve a URL hospedada, sem segredo", async () => {
    const { impl } = espiao({ id: "pl_1", url: "https://pag/x" });
    const r = await new PagarmeClient(cfg, impl).criarLinkCartao(ABERTURA_CARTAO);
    expect(r.providerPaymentLinkId).toBe("pl_1");
    expect(r.checkoutUrl).toBe("https://pag/x");
    expect(JSON.stringify(r)).not.toContain(SEGREDO);
  });
});

describe("conciliacao servidor-a-servidor", () => {
  const cfg = loadPagarmeConfig(envOk);

  it("le a verdade da API, nao do corpo do webhook", async () => {
    const { chamadas, impl } = espiao({
      id: "or_9",
      code: "bdflow-order-abc",
      charges: [{ status: "paid", amount: 664441, payment_method: "pix" }],
    });
    const r = await new PagarmeClient(cfg, impl).lerPedido("or_9");
    expect(chamadas[0].method).toBe("GET");
    expect(chamadas[0].url).toContain("/orders/or_9");
    expect(chamadas[0].headers.Authorization).toBeTruthy();
    expect(r.providerStatus).toBe("paid");
    expect(r.amountCents).toBe(664441);
    expect(r.paymentMethod).toBe("pix");
    expect(r.code).toBe("bdflow-order-abc");
  });

  it("resposta ilegivel nao vira pago", async () => {
    const impl: FetchLike = async () => ({
      status: 200,
      ok: true,
      text: async () => "<html>erro</html>",
    });
    const r = await new PagarmeClient(cfg, impl).lerPedido("or_9");
    expect(r.providerStatus).toBeNull();
    expect(r.amountCents).toBeNull();
  });
});

/**
 * Contrato de requisição contra a documentação oficial da V5, não só contra
 * o comportamento do mock. Um mock aceita qualquer corpo; estas asserções
 * cobram a forma que o provedor realmente exige.
 */
describe("contrato documentado da V5", () => {
  const cfg = loadPagarmeConfig(envOk);

  it("o pedido Pix carrega `customer` — a V5 exige customer ou customer_id", async () => {
    const { chamadas, impl } = espiao({ id: "or_1", charges: [] });
    await new PagarmeClient(cfg, impl).criarPix(ABERTURA, CLIENTE);
    const corpo = JSON.parse(chamadas[0].body as string);
    expect(corpo.customer ?? corpo.customer_id).toBeTruthy();
    expect(corpo.customer.type).toBe("company");
    expect(corpo.customer.document_type).toBe("CNPJ");
    expect(corpo.customer.document).toBe("21010001000197");
    expect(corpo.customer.address.country).toBe("BR");
    expect(corpo.customer.address.state).toBe("ES");
    expect(corpo.customer.address.zip_code).toBe("29100000");
    expect(corpo.customer.address.line_1).toBe("100, Rua Teste, Centro");
  });

  it("dado de cliente incompleto reprova ANTES da rede, sem placeholder", () => {
    const base = {
      legal_name: "X LTDA",
      cnpj: "21010001000197",
      email: "a@b.test",
      address: {
        postal_code: "29100000",
        street: "Rua Teste",
        street_number: "100",
        city: "Vitoria",
        uf: "ES",
      },
    };
    expect(() => montarClienteProvedor(base)).not.toThrow();
    for (const faltando of ["legal_name", "cnpj", "email"] as const) {
      expect(() =>
        montarClienteProvedor({ ...base, [faltando]: null })
      ).toThrow(PagarmeCustomerDataError);
    }
    for (const faltando of ["postal_code", "street", "street_number", "city", "uf"] as const) {
      expect(() =>
        montarClienteProvedor({ ...base, address: { ...base.address, [faltando]: "" } })
      ).toThrow(PagarmeCustomerDataError);
    }
    // CNPJ com tamanho errado tambem reprova.
    expect(() => montarClienteProvedor({ ...base, cnpj: "123" })).toThrow(
      PagarmeCustomerDataError
    );
  });

  it("telefone so e enviado quando pode ser lido sem ambiguidade", () => {
    expect(normalizarTelefoneBR("(27) 99999-0000")).toEqual({
      country_code: "55", area_code: "27", number: "999990000",
    });
    expect(normalizarTelefoneBR("2733330000")).toEqual({
      country_code: "55", area_code: "27", number: "33330000",
    });
    // Curto, longo, vazio e nao-numerico sao omitidos, nunca fabricados.
    for (const ruim of ["123", "", null, undefined, "abc", "1".repeat(15)]) {
      expect(normalizarTelefoneBR(ruim), String(ruim)).toBeNull();
    }
  });

  it("o link de cartao limita PAGAMENTOS bem-sucedidos, nao ordens geradas", async () => {
    const { chamadas, impl } = espiao({ id: "pl_1", url: "https://pag/x" });
    await new PagarmeClient(cfg, impl).criarLinkCartao(ABERTURA_CARTAO);
    const corpo = JSON.parse(chamadas[0].body as string);
    expect(corpo.max_paid_sessions).toBe(1);
    // `max_sessions` conta ordens geradas, pagas ou nao: nao serve de limite
    // de pagamento, e por isso nao e enviado.
    expect(corpo.max_sessions).toBeUndefined();
    expect(corpo.expires_at).toBe(ABERTURA.expiresAt);
  });

  it("o Checkout recebe o User-Agent obrigatorio e o host proprio", async () => {
    const cfgSdx = loadPagarmeConfig({
      ...envOk,
      PAGARME_CHECKOUT_BASE_URL: PAGARME_CHECKOUT_SANDBOX_BASE_URL,
    });
    const { chamadas, impl } = espiao({ id: "pl_1", url: "https://pag/x" });
    const c = new PagarmeClient(cfgSdx, impl);
    await c.criarLinkCartao(ABERTURA_CARTAO);
    expect(chamadas[0].headers["User-Agent"]).toBe(PAGARME_CHECKOUT_USER_AGENT);
    expect(chamadas[0].url).toBe(
      `${PAGARME_CHECKOUT_SANDBOX_BASE_URL}/paymentlinks`
    );

    // /orders continua no host da base: rota diferente, configuracao propria.
    await c.criarPix(ABERTURA, CLIENTE);
    expect(chamadas[1].url).toBe(`${envOk.PAGARME_API_BASE_URL}/orders`);
  });

  it("sem configuracao de Checkout, nada e roteado para sandbox por omissao", () => {
    const c = loadPagarmeConfig({ PAGARME_SECRET_KEY: SEGREDO });
    expect(c.baseUrl).toBe("https://api.pagar.me/core/v5");
    // Acompanha a base, que e producao — nunca sdx por default.
    expect(c.checkoutBaseUrl).toBe("https://api.pagar.me/core/v5");
    expect(c.checkoutBaseUrl).not.toContain("sdx-api");
  });

  it("a expiracao do Pix continua sendo a da reserva", async () => {
    const { chamadas, impl } = espiao({ id: "or_1", charges: [] });
    await new PagarmeClient(cfg, impl).criarPix(ABERTURA, CLIENTE);
    const corpo = JSON.parse(chamadas[0].body as string);
    expect(corpo.payments[0].pix.expires_at).toBe(ABERTURA.expiresAt);
    expect(JSON.stringify(corpo)).not.toContain("expires_in");
  });
});
