import type { PublicNichePricing, NichePricing } from "./contractPricing";
import { previaIndividualSF15 } from "./previewSF15";

/** Exibição informativa por posição comercial; não cria preço ou cobrança.
 * "MEIs" = contraprestação POTENCIAL (App); QA = remuneração SmallFlags.
 * Um pool que contém QA nunca deve ser anunciado como benefício dos MEIs.
 */
export type ParcelaPorContratacao = {
  valorEconomicoCentavos: number;
  contraprestacaoMEIsCentavos: number;
  remuneracaoSmallFlagsCentavos: number;
  qaSmallFlagsCentavos: number;
  principalSmallFlagsCentavos: number;
  fabricacaoIncluidaCentavos: number | null;
};
export type BeneficiosPorOportunidade = {
  estado: "previa" | "vigente";
  participacoesPotenciais: 168 | 84;
  valorPorParticipacaoCentavos: 14199;
  novo: ParcelaPorContratacao;
  fidelizado: ParcelaPorContratacao;
};

const VALOR_POR_PARTICIPACAO = 14199 as const;
const SUPERMERCADO = {
  quantidadeComercial: 24,
  participacoes: 168 as const,
  mei: 2385432,
  qa: 12168,
  v15NovoEconomico: 3293900,
  v15FidelizadoEconomico: 2817600,
  v15NovoSmallflags: 908468,
  v15FidelizadoSmallflags: 432168,
};
const COMUM = {
  quantidadeComercial: 12,
  participacoes: 84 as const,
  mei: 1192716,
  qa: 6084,
  v15NovoEconomico: 2293900,
  v15FidelizadoEconomico: 1618800,
  v15NovoSmallflags: 1101184,
  v15FidelizadoSmallflags: 426084,
};
const POSICOES_COMUNS = new Set(["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]);

function validaBloco(p: NichePricing, mei: number, qa: number): boolean {
  return p.meiConsiderationCents === mei &&
    p.smallflagsQaCents === qa &&
    p.smallflagsTotalRemunerationCents !== null &&
    p.smallflagsMainFeeCents !== null &&
    p.contractualPoolCents === mei + qa &&
    p.smallflagsTotalRemunerationCents === p.smallflagsMainFeeCents + qa &&
    p.economicValueCents === mei + p.smallflagsTotalRemunerationCents &&
    p.fundingDirectBenefitsCents === p.smallflagsTotalRemunerationCents &&
    p.fundingCashCents === p.economicValueCents;
}

function parcela(economico:number, mei:number, qa:number, remuneracao:number, fabricacao:number|null): ParcelaPorContratacao {
  return {
    valorEconomicoCentavos: economico,
    contraprestacaoMEIsCentavos: mei,
    remuneracaoSmallFlagsCentavos: remuneracao,
    qaSmallFlagsCentavos: qa,
    principalSmallFlagsCentavos: remuneracao - qa,
    fabricacaoIncluidaCentavos: fabricacao,
  };
}

/** Fail-closed: sem dados econômicos completos da RPC, não expõe discriminação estimada.
 * Na versão 3, somente os preços propostos são simulados, com a composição
 * congelada e reconciliada à SF-v1.4 real; na versão 4, tudo vem da RPC.
 */
export function beneficiosPorOportunidade(p: PublicNichePricing): BeneficiosPorOportunidade | null {
  const regra = p.nicheCode === "supermarket" ? SUPERMERCADO :
    POSICOES_COMUNS.has(p.nicheCode) ? COMUM : null;
  if(!regra || p.nominalQuantity !== regra.quantidadeComercial) return null;
  if(regra.participacoes * VALOR_POR_PARTICIPACAO !== regra.mei) return null;
  if(!validaBloco(p.founding,regra.mei,regra.qa) || !validaBloco(p.fidelized,regra.mei,regra.qa)) return null;

  if(p.founding.pricingRuleVersion === 3 && p.fidelized.pricingRuleVersion === 3) {
    const previa=previaIndividualSF15(p);
    if(!previa ||
       previa.novoCentavos !== regra.v15NovoEconomico ||
       previa.fidelizadoReutilizacaoCentavos !== regra.v15FidelizadoEconomico ||
       previa.novoCentavos - regra.mei !== regra.v15NovoSmallflags ||
       previa.fidelizadoReutilizacaoCentavos - regra.mei !== regra.v15FidelizadoSmallflags) return null;
    return {
      estado:"previa",
      participacoesPotenciais:regra.participacoes,
      valorPorParticipacaoCentavos:VALOR_POR_PARTICIPACAO,
      novo:parcela(previa.novoCentavos,regra.mei,regra.qa,regra.v15NovoSmallflags,previa.custoProducaoIncluidoCentavos),
      fidelizado:parcela(previa.fidelizadoReutilizacaoCentavos,regra.mei,regra.qa,regra.v15FidelizadoSmallflags,0),
    };
  }

  if(p.founding.pricingRuleVersion === 4 && p.fidelized.pricingRuleVersion === 4) {
    // É proibido inventar quantia de fabricação: o parser público atual não
    // expõe esse campo separadamente na versão ativa. A remuneração é do servidor.
    return {
      estado:"vigente",
      participacoesPotenciais:regra.participacoes,
      valorPorParticipacaoCentavos:VALOR_POR_PARTICIPACAO,
      novo:parcela(p.founding.economicValueCents,regra.mei,regra.qa,p.founding.smallflagsTotalRemunerationCents!,null),
      fidelizado:parcela(p.fidelized.economicValueCents,regra.mei,regra.qa,p.fidelized.smallflagsTotalRemunerationCents!,null),
    };
  }
  return null;
}
