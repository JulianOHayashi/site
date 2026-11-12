import type { PublicNichePricing } from "./contractPricing";

/**
 * Simulação editorial SF-v1.5, EXCLUSIVAMENTE para apresentação por posição.
 *
 * Não é autoridade de preço. Só aparece se o backend comprovar que a SF-v1.4
 * (versão 3) ainda está vigente e que os valores de referência são os esperados.
 * Na futura ativação da versão 4 esta simulação desaparece; preços oficiais
 * continuam vindo exclusivamente do servidor.
 *
 * Não há totalização de preços de anunciantes nem de formação nesta API.
 */
type Parcela = Pick<PublicNichePricing["founding"], "pricingRuleVersion" | "economicValueCents">;
export type PrecoVigenteParaProposta = {
  nicheCode: string;
  founding: Parcela;
  fidelized: Parcela;
};

export type PreviaIndividualSF15 = {
  novoCentavos: number;
  fidelizadoReutilizacaoCentavos: number;
  bandeirasNovas: 84;
  custoProducaoIncluidoCentavos: 294000;
};

const POSICOES = new Set([
  "supermarket", "pharmacy", "womens_clothing", "mens_clothing",
  "footwear", "others",
]);

const REFERENCIA = {
  supermarket: { atualNovo: 2999900, atualFidelizado: 2817600, propostoNovo: 3293900, propostoFidelizado: 2817600 },
  common: { atualNovo: 1999900, atualFidelizado: 1618800, propostoNovo: 2293900, propostoFidelizado: 1618800 },
} as const;

export function previaIndividualSF15(preco: PrecoVigenteParaProposta): PreviaIndividualSF15 | null {
  if (!POSICOES.has(preco.nicheCode)) return null;
  if (preco.founding.pricingRuleVersion !== 3 || preco.fidelized.pricingRuleVersion !== 3) return null;
  const esperado = preco.nicheCode === "supermarket" ? REFERENCIA.supermarket : REFERENCIA.common;
  if (preco.founding.economicValueCents !== esperado.atualNovo ||
      preco.fidelized.economicValueCents !== esperado.atualFidelizado) return null;
  return {
    novoCentavos: esperado.propostoNovo,
    fidelizadoReutilizacaoCentavos: esperado.propostoFidelizado,
    bandeirasNovas: 84,
    custoProducaoIncluidoCentavos: 294000,
  };
}
