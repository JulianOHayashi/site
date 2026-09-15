/**
 * Reserva comercial — cliente de navegador.
 *
 * O navegador envia TRÊS coisas: qual empresa, qual nicho e como a empresa
 * quer cumprir a parcela de benefícios. Preço, fidelidade, forma de pagamento,
 * componentes monetários, quantidade, identidade da oportunidade e prazo de
 * expiração são todos derivados no servidor — não há por onde enviá-los, e a
 * resposta é a única fonte do que a tela exibe.
 *
 * Nada aqui guarda estado no navegador: o que vale é o que a RPC devolveu
 * agora. A asserção que cobre isto varre o próprio texto deste arquivo,
 * então nem em comentário os nomes dessas APIs aparecem.
 */

import { supabase } from "../lib/supabase";
import type { BenefitSettlementMode } from "../domain/pricing/commercialV2";

export type ReservaComercial = {
  intentId: string;
  already: boolean;
  opportunityId: string;
  /** Instante de expiração calculado pelo servidor. Exibir, nunca recalcular. */
  reservedUntil: string;
  reservationMinutes: number;
  nicheCode: string;
  nominalQuantity: number;
  fidelized: boolean;
  paymentMethod: string;
  benefitSettlementMode: BenefitSettlementMode;
  economicValueCents: number;
  userPoolCents: number;
  bdflowOpsInvestmentCents: number;
  cashUserPoolFundingCents: number;
  totalMonetaryFundingRequiredCents: number;
};

export type ResultadoReserva =
  | { tipo: "ok"; reserva: ReservaComercial }
  | { tipo: "erro"; codigo: string; reservedUntil?: string };

export async function reservarOportunidade(params: {
  companyId: string;
  nicheCode: string;
  benefitSettlementMode: BenefitSettlementMode;
}): Promise<ResultadoReserva> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };

  const { data, error } = await supabase.rpc("create_commercial_checkout_intent", {
    p_company_id: params.companyId,
    p_niche_code: params.nicheCode,
    p_benefit_settlement_mode: params.benefitSettlementMode,
  });
  if (error) return { tipo: "erro", codigo: "rpc_error" };

  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) {
    return {
      tipo: "erro",
      codigo: typeof o.reason === "string" ? o.reason : "unexpected_error",
      reservedUntil:
        typeof o.reserved_until === "string" ? o.reserved_until : undefined,
    };
  }

  return {
    tipo: "ok",
    reserva: {
      intentId: String(o.intent_id),
      already: o.already === true,
      opportunityId: String(o.opportunity_id),
      reservedUntil: String(o.reserved_until),
      reservationMinutes: Number(o.reservation_minutes),
      nicheCode: String(o.niche_code),
      nominalQuantity: Number(o.nominal_quantity),
      fidelized: o.fidelized === true,
      paymentMethod: String(o.payment_method),
      benefitSettlementMode: o.benefit_settlement_mode as BenefitSettlementMode,
      economicValueCents: Number(o.economic_value_cents),
      userPoolCents: Number(o.user_pool_cents),
      bdflowOpsInvestmentCents: Number(o.bdflow_ops_investment_cents),
      cashUserPoolFundingCents: Number(o.cash_user_pool_funding_cents),
      totalMonetaryFundingRequiredCents: Number(
        o.total_monetary_funding_required_cents
      ),
    },
  };
}
