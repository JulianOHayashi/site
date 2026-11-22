import type { PublicNichePricing, NichePricing } from "./contractPricing";
import { previaIndividualSF15 } from "./previewSF15";

/**
 * Exibição informativa por posição comercial; não cria preço ou cobrança.
 *
 * Regra R3 (decisão comercial de 13/11/2026), aplicada à SF-v1.5:
 *   * "MEIs" = contraprestação POTENCIAL dos participantes do App, igual nas
 *     duas modalidades (em benefícios no direto, em dinheiro no DINHEIRO);
 *   * a parcela principal da SmallFlags é a sua remuneração MONETÁRIA;
 *   * a QA existe SÓ no benefício direto, em produtos para testes locais —
 *     nunca em dinheiro, nunca dos participantes, inexistente no DINHEIRO.
 * Um pool que contém QA nunca é anunciado como benefício dos MEIs.
 */
export type ParcelaPorContratacao = {
  /** Valor total na modalidade BENEFÍCIO DIRETO (referência da agenda). */
  valorEconomicoCentavos: number;
  contraprestacaoMEIsCentavos: number;
  /** Parcela principal da SmallFlags, devida em dinheiro. */
  principalSmallFlagsCentavos: number;
  /** Remuneração MONETÁRIA da SmallFlags (R3: igual à parcela principal). */
  remuneracaoSmallFlagsCentavos: number;
  /** QA em produtos para testes locais — só no benefício direto. */
  qaEmProdutosCentavos: number;
  /**
   * Custo NOMINAL de produção das bandeiras já contido no valor total (nunca
   * somado de novo). `null` = não declarado de forma validada: nada é exibido.
   */
  fabricacaoIncluidaCentavos: number | null;
  /**
   * PEÇAS FÍSICAS novas desta condição (84 no anunciante novo, 0 na renovação
   * fidelizada). Não é a quantidade comercial (24/12) nem as participações.
   * `null` = não declarado de forma validada.
   */
  bandeirasFisicasNovas: number | null;
  /**
   * Modalidade integralmente em DINHEIRO (sem QA). `null` = preço dessa
   * modalidade ainda não aprovado: nada é estimado.
   */
  dinheiro: { valorEconomicoCentavos: number; ajusteCentavos: number } | null;
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
  // R3: parcela principal (dinheiro), sem a QA.
  v15NovoPrincipal: 896300,
  v15FidelizadoPrincipal: 420000,
};
const COMUM = {
  quantidadeComercial: 12,
  participacoes: 84 as const,
  mei: 1192716,
  qa: 6084,
  v15NovoEconomico: 2293900,
  v15FidelizadoEconomico: 1618800,
  v15NovoPrincipal: 1095100,
  v15FidelizadoPrincipal: 420000,
};
const POSICOES_COMUNS = new Set(["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]);

/** SF-v1.4 vigente (versão 3): interpretação histórica, QA monetária. */
function validaBlocoV14(p: NichePricing, mei: number, qa: number): boolean {
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

/** SF-v1.5 vigente (versão 4): regra R3, composição por modalidade. */
function validaBlocoR3(p: NichePricing, mei: number, qa: number): boolean {
  const m = p.settlementModes;
  if (p.qaPolicy !== "in_kind_direct_benefits_only" || !m) return false;
  const d = m.directBenefits;
  if (p.meiConsiderationCents !== mei || p.smallflagsQaCents !== qa) return false;
  if (p.smallflagsMainFeeCents === null || p.smallflagsTotalRemunerationCents === null) return false;
  if (p.smallflagsTotalRemunerationCents !== p.smallflagsMainFeeCents) return false;
  if (d.meiConsiderationCents !== mei || d.qaInKindCents !== qa || d.qaCashCents !== 0) return false;
  if (d.ordinaryParticipationValueCents !== VALOR_POR_PARTICIPACAO) return false;
  if (p.economicValueCents !== mei + p.smallflagsMainFeeCents + qa) return false;
  if (p.fundingDirectBenefitsCents !== p.smallflagsMainFeeCents) return false;
  if (m.cash) {
    const c = m.cash;
    if (c.meiCashCents !== mei || c.qaInKindCents !== 0 || c.qaCashCents !== 0) return false;
    if (c.smallflagsMainFeeCents !== p.smallflagsMainFeeCents) return false;
    if (c.economicValueCents !== mei + c.smallflagsMainFeeCents + c.cashAdjustmentCents) return false;
    if (p.fundingCashCents !== c.economicValueCents) return false;
  } else if (p.fundingCashCents !== null) {
    return false;
  }
  return true;
}

function parcela(economico: number, mei: number, qa: number, principal: number,
                 producao: { pecas: number; centavos: number } | null,
                 dinheiro: ParcelaPorContratacao["dinheiro"]): ParcelaPorContratacao {
  return {
    valorEconomicoCentavos: economico,
    contraprestacaoMEIsCentavos: mei,
    principalSmallFlagsCentavos: principal,
    remuneracaoSmallFlagsCentavos: principal,
    qaEmProdutosCentavos: qa,
    fabricacaoIncluidaCentavos: producao ? producao.centavos : null,
    bandeirasFisicasNovas: producao ? producao.pecas : null,
    dinheiro,
  };
}

/**
 * Produção declarada pelo servidor (versão 4), já validada pelo parser
 * (peças × referência = cobrança, cobrança ≤ parcela principal, fidelizado
 * sem peças novas e com reutilização). Só a QUANTIDADE e o TOTAL nominal saem
 * daqui: a referência por peça nunca é repassada à apresentação.
 */
function producaoDeclarada(b: NichePricing): { pecas: number; centavos: number } | null {
  const f = b.flagProduction;
  return f ? { pecas: f.newFlagUnits, centavos: f.flagProductionChargeCents } : null;
}

/** Fail-closed: sem dados econômicos completos da RPC, não expõe discriminação estimada.
 * Na versão 3, somente os preços propostos são simulados, com a composição
 * congelada e reconciliada à SF-v1.4 real; o DINHEIRO da prévia é o Cenário A
 * aprovado (participantes + parcela principal, sem QA, sem ajuste), conferido
 * contra a mesma composição. Na versão 4, tudo vem da RPC.
 */
export function beneficiosPorOportunidade(p: PublicNichePricing): BeneficiosPorOportunidade | null {
  const regra = p.nicheCode === "supermarket" ? SUPERMERCADO :
    POSICOES_COMUNS.has(p.nicheCode) ? COMUM : null;
  if (!regra || p.nominalQuantity !== regra.quantidadeComercial) return null;
  if (regra.participacoes * VALOR_POR_PARTICIPACAO !== regra.mei) return null;

  if (p.founding.pricingRuleVersion === 3 && p.fidelized.pricingRuleVersion === 3) {
    if (!validaBlocoV14(p.founding, regra.mei, regra.qa) || !validaBlocoV14(p.fidelized, regra.mei, regra.qa)) return null;
    const previa = previaIndividualSF15(p);
    if (!previa ||
        previa.novoCentavos !== regra.v15NovoEconomico ||
        previa.fidelizadoReutilizacaoCentavos !== regra.v15FidelizadoEconomico ||
        previa.novoCentavos - regra.mei - regra.qa !== regra.v15NovoPrincipal ||
        previa.fidelizadoReutilizacaoCentavos - regra.mei - regra.qa !== regra.v15FidelizadoPrincipal) return null;
    // Cenário A: DINHEIRO = participantes + parcela principal; sem QA, ajuste 0.
    if (previa.dinheiroNovoCentavos !== regra.mei + regra.v15NovoPrincipal ||
        previa.dinheiroFidelizadoCentavos !== regra.mei + regra.v15FidelizadoPrincipal) return null;
    return {
      estado: "previa",
      participacoesPotenciais: regra.participacoes,
      valorPorParticipacaoCentavos: VALOR_POR_PARTICIPACAO,
      novo: parcela(previa.novoCentavos, regra.mei, regra.qa, regra.v15NovoPrincipal,
                    { pecas: previa.bandeirasNovas, centavos: previa.custoProducaoIncluidoCentavos },
                    { valorEconomicoCentavos: previa.dinheiroNovoCentavos, ajusteCentavos: 0 }),
      // Renovação fidelizada da prévia: reutilização das peças, nenhuma nova.
      fidelizado: parcela(previa.fidelizadoReutilizacaoCentavos, regra.mei, regra.qa,
                          regra.v15FidelizadoPrincipal, { pecas: 0, centavos: 0 },
                          { valorEconomicoCentavos: previa.dinheiroFidelizadoCentavos, ajusteCentavos: 0 }),
    };
  }

  if (p.founding.pricingRuleVersion === 4 && p.fidelized.pricingRuleVersion === 4) {
    if (!validaBlocoR3(p.founding, regra.mei, regra.qa) || !validaBlocoR3(p.fidelized, regra.mei, regra.qa)) return null;
    // É proibido inventar quantia de fabricação: ela só existe quando o servidor
    // a declara (flagProduction validado pelo parser); senão fica `null`.
    const dinheiro = (b: NichePricing): ParcelaPorContratacao["dinheiro"] => {
      const c = b.settlementModes!.cash;
      return c ? { valorEconomicoCentavos: c.economicValueCents, ajusteCentavos: c.cashAdjustmentCents } : null;
    };
    return {
      estado: "vigente",
      participacoesPotenciais: regra.participacoes,
      valorPorParticipacaoCentavos: VALOR_POR_PARTICIPACAO,
      novo: parcela(p.founding.economicValueCents, regra.mei, regra.qa,
                    p.founding.smallflagsMainFeeCents!, producaoDeclarada(p.founding), dinheiro(p.founding)),
      fidelizado: parcela(p.fidelized.economicValueCents, regra.mei, regra.qa,
                          p.fidelized.smallflagsMainFeeCents!, producaoDeclarada(p.fidelized), dinheiro(p.fidelized)),
    };
  }
  return null;
}
