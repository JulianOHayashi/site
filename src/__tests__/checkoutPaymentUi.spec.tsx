import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, fireEvent } from "@testing-library/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Etapas de contrato e pagamento do /checkout.
 *
 * A tela é provada pelo que ela EXIBE a partir do servidor e pelo que ela se
 * recusa a exibir. As regras vivem no SQL e nos endpoints, provados em
 * `230_commercial_payments.sql` e `paymentEndpoints.spec.ts`.
 */

const rpcMock = vi.fn();
const fetchMock = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      getSession: vi.fn(async () => ({ data: { session: { access_token: "t" } } })),
    },
  },
  supabaseConfigurado: true,
}));

import EtapasContratacao from "../pages/comercial/EtapasContratacao";

const INTENT = "11111111-1111-4111-8111-111111111111";
const ORDER = "22222222-2222-4222-8222-222222222222";
const PAY = "33333333-3333-4333-8333-333333333333";
const TOTAL = 664441;

const TERMOS = {
  doc_type: "commercial_order_terms",
  version: "v1-teste",
  title: "Termos do pedido comercial",
  content: "CONTEUDO DE TESTE (nao juridico)",
  content_url: null,
};

function respostaPagamento(over: Record<string, unknown> = {}) {
  return {
    ok: true,
    payment_id: PAY,
    status: "pending",
    payment_method: "pix",
    amount_cents: TOTAL,
    expires_at: "2026-09-18T12:30:00.000Z",
    pix_copy_paste: "00020126...",
    pix_qr_code_url: null,
    ...over,
  };
}

function montarRpc(over: Record<string, unknown> = {}) {
  rpcMock.mockImplementation(async (fn: string) => {
    if (fn === "get_current_legal_documents") {
      return { data: over.termos ?? [TERMOS], error: null };
    }
    if (fn === "advance_checkout_intent_to_contract") {
      return { data: { ok: true, status: "awaiting_contract" }, error: null };
    }
    if (fn === "accept_commercial_order_terms") {
      return { data: { ok: true, acceptance_id: "a-1" }, error: null };
    }
    if (fn === "finalize_commercial_order_from_intent") {
      return { data: over.finalize ?? { ok: true, order_id: ORDER }, error: null };
    }
    if (fn === "get_my_commercial_payment_status") {
      return { data: over.status ?? { ok: true, status: "pending" }, error: null };
    }
    return { data: null, error: { message: "rpc inesperada" } };
  });
}

beforeEach(() => {
  rpcMock.mockReset();
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  fetchMock.mockResolvedValue({
    ok: true,
    json: async () => respostaPagamento(),
  });
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function montar(fidelizado = false) {
  return render(
    <EtapasContratacao intentId={INTENT} amountCents={TOTAL} fidelizado={fidelizado} />
  );
}

describe("estados bloqueados: falham fechados", () => {
  it("sem termos publicados, a tela para e nao fabrica contrato", async () => {
    montarRpc({ termos: [] });
    montar();
    await screen.findByText(/Contratação indisponível no momento/i);
    expect(screen.getByText(/ainda não foram publicados/i)).toBeTruthy();
    // Nenhum aceite, nenhum pagamento.
    expect(screen.queryByRole("checkbox")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("sem contrato-quadro, bloqueia sem contornar a exigencia", async () => {
    montarRpc({ finalize: { ok: false, reason: "master_agreement_missing" } });
    montar();
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir para o pagamento/i }));
    await screen.findByText(/Contrato-quadro pendente/i);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("termos e aceite", () => {
  it("exibe o conteudo e a versao exatos devolvidos pelo servidor", async () => {
    montarRpc();
    montar();
    await screen.findByText("Termos do pedido comercial");
    // A versao aparece no cabecalho E no rotulo do aceite, de proposito:
    // quem clica precisa ver qual versao esta aceitando.
    expect(screen.getAllByText(/v1-teste/i).length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText(/CONTEUDO DE TESTE/i)).toBeTruthy();
  });

  it("sem aceite explicito o botao fica desabilitado", async () => {
    montarRpc();
    montar();
    const botao = await screen.findByRole("button", {
      name: /Aceitar e ir para o pagamento/i,
    });
    expect((botao as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByRole("checkbox"));
    expect((botao as HTMLButtonElement).disabled).toBe(false);
  });

  it("o navegador nao envia id, versao nem hash do documento", async () => {
    montarRpc();
    montar();
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir/i }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const aceite = rpcMock.mock.calls.find(
      (c) => c[0] === "accept_commercial_order_terms"
    );
    expect(Object.keys(aceite![1] as object)).toEqual(["p_intent_id"]);
  });
});

describe("Pix", () => {
  it("mostra copia-e-cola e prazo, e nenhum controle de cartao", async () => {
    montarRpc();
    montar(false);
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir/i }));

    await screen.findByText(/Aguardando pagamento/i);
    expect(screen.getByText("00020126...")).toBeTruthy();
    expect(screen.getByRole("button", { name: /Copiar código Pix/i })).toBeTruthy();
    // Nada de cartao nesta superficie.
    expect(screen.queryByText(/sem juros/i)).toBeNull();
    expect(screen.queryByText(/checkout seguro do cartão/i)).toBeNull();

    // O corpo enviado nao carrega valor, metodo nem prazo.
    const corpo = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    expect(Object.keys(corpo)).toEqual(["order_id"]);
  });
});

describe("cartao fidelizado", () => {
  it("oferece 1x a 6x, todas sem juros, com o total contratual fixo", async () => {
    montarRpc();
    montar(true);
    await screen.findByText("Termos do pedido comercial");

    const opcoes = screen.getAllByRole("radio");
    expect(opcoes).toHaveLength(6);
    expect(screen.queryByLabelText(/^7x/)).toBeNull();
    // Cada parcela acima de 1x e anunciada sem juros.
    expect(screen.getAllByText(/sem juros/i)).toHaveLength(5);
    // O total exibido e SEMPRE o contratual.
    expect(screen.getByText(/Total: R\$\s*6\.644,41/)).toBeTruthy();
  });

  it("envia a parcela escolhida e redireciona so para a URL do servidor", async () => {
    montarRpc();
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () =>
        respostaPagamento({
          payment_method: "credit_card",
          pix_copy_paste: undefined,
          checkout_url: "https://provedor.exemplo/checkout/abc",
        }),
    });
    montar(true);
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getAllByRole("radio")[5]);
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir/i }));

    await screen.findByText(/checkout seguro do cartão/i);
    const link = screen.getByRole("link", { name: /checkout seguro do cartão/i });
    expect(link.getAttribute("href")).toBe("https://provedor.exemplo/checkout/abc");
    const corpo = JSON.parse(fetchMock.mock.calls[0][1].body as string);
    expect(corpo.installments).toBe(6);
    // Nenhum Pix nesta superficie.
    expect(screen.queryByText(/Copiar código Pix/i)).toBeNull();
  });
});

describe("estado do pagamento vem do banco", () => {
  it("pago so aparece quando o estado LOCAL diz pago", async () => {
    montarRpc({ status: { ok: true, status: "paid" } });
    montar();
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir/i }));
    // Enquanto o endpoint devolve `pending`, a tela NAO diz pago.
    await screen.findByText(/Aguardando pagamento/i);
    expect(screen.queryByText(/Pagamento confirmado/i)).toBeNull();
  });

  it("retorno do provedor por si so nao confirma nada", () => {
    const src = readFileSync(
      resolve(__dirname, "../pages/comercial/EtapasContratacao.tsx"),
      "utf8"
    );
    // Nenhum parametro de URL decide pagamento.
    expect(src).not.toMatch(/success=true|searchParams|URLSearchParams/);
    // O estado exibido vem do status devolvido pelas RPCs.
    expect(src).toContain('p.status === "paid"');
  });

  it("tardio e neutro: nem falhou, nem contratado", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => respostaPagamento({ status: "late_unreconciled" }),
    });
    montarRpc();
    montar();
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir/i }));
    await screen.findByText(/Pagamento em conferência/i);
    expect(screen.getByText(/não foi contratada automaticamente/i)).toBeTruthy();
    expect(screen.queryByText(/falhou/i)).toBeNull();
  });

  it("expirado explica que e preciso reservar de novo, sem apagar historico", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => respostaPagamento({ status: "expired" }),
    });
    montarRpc();
    montar();
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /Aceitar e ir/i }));
    await screen.findByText(/Prazo encerrado/i);
    expect(screen.getByText(/reservá-la\s*novamente/i)).toBeTruthy();
    expect(screen.getByText(/histórico de contratação foi preservado/i)).toBeTruthy();
  });
});

describe("isolamento", () => {
  it("a tela nao guarda estado no navegador nem toca o provedor direto", () => {
    for (const f of [
      "../pages/comercial/EtapasContratacao.tsx",
      "../services/commercialContractService.ts",
    ]) {
      const src = readFileSync(resolve(__dirname, f), "utf8");
      expect(src, f).not.toMatch(/localStorage|sessionStorage/);
      expect(src, f).not.toMatch(/PAGARME|sk_test|sk_live|api\.pagar\.me/);
    }
  });
});
