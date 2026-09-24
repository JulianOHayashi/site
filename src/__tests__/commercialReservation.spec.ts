import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Reserva comercial — lado navegador.
 *
 * O que estes testes travam é a FRONTEIRA, não a regra: a regra vive no SQL e
 * é provada em `supabase/tests/210_commercial_reservation.sql`, contra um
 * PostgreSQL de verdade. Aqui provamos que o navegador não tem por onde
 * mandar preço, fidelidade, método, quantidade, oportunidade ou expiração, e
 * que a tela só exibe o que o servidor devolveu.
 */

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));

import { reservarOportunidade } from "../services/commercialReservationService";

const RESPOSTA_OK = {
  ok: true,
  already: false,
  intent_id: "11111111-1111-4111-8111-111111111111",
  status: "draft",
  opportunity_id: "22222222-2222-4222-8222-222222222222",
  exclusivity_id: "33333333-3333-4333-8333-333333333333",
  region_id: "44444444-4444-4444-8444-444444444444",
  reserved_until: "2026-09-15T12:30:00.000Z",
  reservation_minutes: 30,
  niche_code: "pharmacy",
  nominal_quantity: 12,
  fidelized: false,
  payment_method: "pix",
  benefit_settlement_mode: "direct_benefits",
  currency: "BRL",
  economic_value_cents: 1999900,
  user_pool_cents: 1335459,
  bdflow_ops_investment_cents: 664441,
  cash_user_pool_funding_cents: 0,
  total_monetary_funding_required_cents: 664441,
  participant_target: 84,
};

beforeEach(() => rpcMock.mockReset());

describe("o navegador envia o mínimo e nada de autoridade", () => {
  it("manda exatamente empresa, nicho e modo de liquidação", async () => {
    rpcMock.mockResolvedValue({ data: RESPOSTA_OK, error: null });
    await reservarOportunidade({
      companyId: "c-1",
      nicheCode: "pharmacy",
      benefitSettlementMode: "direct_benefits",
    });
    expect(rpcMock).toHaveBeenCalledTimes(1);
    const [fn, args] = rpcMock.mock.calls[0] as [string, Record<string, unknown>];
    expect(fn).toBe("create_commercial_checkout_intent");
    expect(Object.keys(args).sort()).toEqual(
      ["p_company_id", "p_niche_code", "p_benefit_settlement_mode"].sort()
    );
  });

  it("não existe caminho para enviar preço, fidelidade, método, quantidade ou expiração", () => {
    const src = readFileSync(
      resolve(__dirname, "../services/commercialReservationService.ts"),
      "utf8"
    );
    // O corpo enviado é só o objeto de três chaves acima.
    const envio = src.slice(src.indexOf("supabase.rpc("), src.indexOf("if (error)"));
    for (const proibido of [
      "economic_value",
      "user_pool",
      "bdflow_ops",
      "fidelized",
      "payment_method",
      "nominal_quantity",
      "reserved_until",
      "opportunity_id",
    ]) {
      expect(envio, proibido).not.toContain(proibido);
    }
    // E nada de armazenamento local como autoridade.
    expect(src).not.toMatch(/localStorage|sessionStorage/);
  });

  it("os valores exibidos vêm da RESPOSTA, não de cálculo local", async () => {
    rpcMock.mockResolvedValue({ data: RESPOSTA_OK, error: null });
    const r = await reservarOportunidade({
      companyId: "c-1",
      nicheCode: "pharmacy",
      benefitSettlementMode: "direct_benefits",
    });
    expect(r.tipo).toBe("ok");
    if (r.tipo !== "ok") return;
    expect(r.reserva.reservedUntil).toBe("2026-09-15T12:30:00.000Z");
    expect(r.reserva.reservationMinutes).toBe(30);
    expect(r.reserva.economicValueCents).toBe(1999900);
    expect(r.reserva.userPoolCents).toBe(1335459);
    expect(r.reserva.paymentMethod).toBe("pix");
    expect(r.reserva.fidelized).toBe(false);
    expect(r.reserva.nominalQuantity).toBe(12);
  });

  it("retomada idempotente chega marcada como already", async () => {
    rpcMock.mockResolvedValue({
      data: { ...RESPOSTA_OK, already: true },
      error: null,
    });
    const r = await reservarOportunidade({
      companyId: "c-1",
      nicheCode: "pharmacy",
      benefitSettlementMode: "direct_benefits",
    });
    expect(r.tipo === "ok" && r.reserva.already).toBe(true);
  });

  it("recusa do servidor NUNCA vira sucesso na tela", async () => {
    for (const motivo of [
      "not_authenticated",
      "not_company_owner",
      "opportunity_reserved",
      "opportunity_unavailable",
      "region_not_operating",
      "no_current_exclusivity",
    ]) {
      rpcMock.mockResolvedValue({ data: { ok: false, reason: motivo }, error: null });
      const r = await reservarOportunidade({
        companyId: "c-1",
        nicheCode: "pharmacy",
        benefitSettlementMode: "direct_benefits",
      });
      expect(r.tipo, motivo).toBe("erro");
      if (r.tipo === "erro") expect(r.codigo).toBe(motivo);
    }
  });

  it("erro de transporte falha fechado", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    const r = await reservarOportunidade({
      companyId: "c-1",
      nicheCode: "pharmacy",
      benefitSettlementMode: "direct_benefits",
    });
    expect(r).toEqual({ tipo: "erro", codigo: "rpc_error" });
  });
});

describe("a tela de revisão não inventa nem promete", () => {
  const src = readFileSync(
    resolve(__dirname, "../pages/RevisaoContratacao.tsx"),
    "utf8"
  );

  it("exibe o prazo devolvido pelo servidor, sem relógio próprio", () => {
    expect(src).toContain("reserva.reservedUntil");
    expect(src).toContain("reserva.reservationMinutes");
    // Nenhum timer de navegador decidindo expiração.
    expect(src).not.toMatch(/setInterval|setTimeout|Date\.now\(\)/);
  });

  it("não promete pagamento nem contrato", () => {
    expect(src).toContain("Reserva não é pagamento nem contrato");
    // Com o Pagar.me integrado (20260917120000), a promessa correta passou a
    // ser que a reserva não cobra nada; o pagamento só ocorre depois, pelo
    // fluxo de EtapasContratacao.
    expect(src).toContain("Nenhum valor foi cobrado.");
    expect(src).toContain("A reserva não cobra valores.");
    // Sem Pix falso, sem formulário de cartão.
    expect(src).not.toMatch(/QR|qrcode|card_number|numero do cartao|cvv/i);
  });

  it("não usa armazenamento do navegador como autoridade", () => {
    expect(src).not.toMatch(/localStorage|sessionStorage/);
  });

  it("o botão de reserva só existe havendo vínculo; sem ele, o caminho é o cadastro", () => {
    expect(src).toContain("Reservar por 30 minutos");
    expect(src).toContain("/parceiros/cadastro");
  });
});
