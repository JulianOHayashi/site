/** PRÉVIA EDITORIAL, NÃO AUTORITATIVA, DA PROPOSTA SF-v1.5.
 * Fonte: decisões do operador de 12/11/2026 e agenda proposta.
 * Não usar no checkout, na cobrança, no contrato ou em RPCs.
 */
export const PREVIA_SF15 = {
  versao: "SF-v1.5 (proposta)",
  custoUnitarioBandeiraCentavos: 3500,
  bandeirasPorAnuncianteNovo: 84,
  participacaoAprovadaCentavos: 14199,
  qaFormacaoCentavos: 42588,
  meiFormacaoCentavos: 8349012,
  nichos: [
    { nome: "Supermercado", unidadesComerciais: 24, novoCentavos: 3293900, fidelizadoCentavos: 2817600 },
    { nome: "Farmácia", unidadesComerciais: 12, novoCentavos: 2293900, fidelizadoCentavos: 1618800 },
    { nome: "Roupas femininas", unidadesComerciais: 12, novoCentavos: 2293900, fidelizadoCentavos: 1618800 },
    { nome: "Roupas masculinas", unidadesComerciais: 12, novoCentavos: 2293900, fidelizadoCentavos: 1618800 },
    { nome: "Calçados", unidadesComerciais: 12, novoCentavos: 2293900, fidelizadoCentavos: 1618800 },
    { nome: "Outros", unidadesComerciais: 12, novoCentavos: 2293900, fidelizadoCentavos: 1618800 },
  ],
} as const;

export const resumoPrevia = {
  novosCentavos: PREVIA_SF15.nichos.reduce((s, n) => s + n.novoCentavos, 0),
  fidelizadosCentavos: PREVIA_SF15.nichos.reduce((s, n) => s + n.fidelizadoCentavos, 0),
  custoProducaoCentavos: PREVIA_SF15.custoUnitarioBandeiraCentavos *
    PREVIA_SF15.bandeirasPorAnuncianteNovo * PREVIA_SF15.nichos.length,
  bandeirasNovas: PREVIA_SF15.bandeirasPorAnuncianteNovo * PREVIA_SF15.nichos.length,
} as const;
