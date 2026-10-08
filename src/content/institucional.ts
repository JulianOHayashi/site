/**
 * Fatos comerciais públicos usados pelas páginas institucionais.
 *
 * Fonte: formação comercial de referência vigente (seis nichos, 84 unidades)
 * e a primeira região comercial ativa. Não são métricas de negócio: são a
 * composição contratual de uma exclusividade. Cada nicho é contratado
 * integralmente — unidades de um nicho não são vendidas separadamente.
 */
export const FORMACAO_REFERENCIA = [
  { nome: "Supermercado", unidades: 24 },
  { nome: "Farmácia", unidades: 12 },
  { nome: "Roupas femininas", unidades: 12 },
  { nome: "Roupas masculinas", unidades: 12 },
  { nome: "Calçados femininos", unidades: 12 },
  { nome: "Calçados masculinos", unidades: 12 },
] as const;

export const TOTAL_UNIDADES_REFERENCIA = FORMACAO_REFERENCIA.reduce(
  (soma, n) => soma + n.unidades,
  0
);

export const REGIAO_ATIVA = {
  nome: "Grande Vitória",
  uf: "ES",
  cidades: ["Vitória", "Vila Velha", "Serra", "Cariacica", "Viana"],
} as const;

/**
 * Quadro financeiro congelado das minutas v1.4 (primeira compra, não fidelizado).
 *
 * Fonte: SMALLFLAGS_SEIS_CONTRATOS_PRESENCIAIS_SF-0001_A_SF-0006_MINUTA_v1_4,
 * SHA-256 03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73,
 * conferido contra o manifesto oficial.
 *
 * Em CENTAVOS, porque dinheiro em ponto flutuante não fecha. Não é tabela de
 * preço pública: é a referência congelada contra a qual o pedido é conferido.
 * A parcela QA pertence à SmallFlags e está DENTRO do pool — nunca é direito
 * do MEI.
 */
export const QUADRO_V14 = {
  templateVersion: "1.4",
  templateHash: "03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73",
  supermercado: {
    quantidade: 24,
    valorEconomicoCents: 2_999_900,
    meiCents: 2_385_432,
    qaCents: 12_168,
    operacionalCents: 602_300,
  },
  demaisPosicoes: {
    quantidade: 12,
    valorEconomicoCents: 1_999_900,
    meiCents: 1_192_716,
    qaCents: 6_084,
    operacionalCents: 801_100,
  },
} as const;
