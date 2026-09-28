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
