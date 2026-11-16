import type { PublicNichePricing } from "./contractPricing";
import { beneficiosPorOportunidade, type ParcelaPorContratacao } from "./beneficiosAppPorOportunidade";
import { modalidadesDefinidas } from "./pricingGateSF15";

/**
 * Modelo de APRESENTAÇÃO comercial de uma oportunidade.
 *
 * Não é autoridade de preço: tudo vem de `beneficiosPorOportunidade`, que
 * valida a resposta de `get_public_niche_pricing` e falha fechado. Este
 * módulo só organiza os números para a leitura de um empresário, separando
 * três conceitos que não podem se confundir:
 *
 *   1. valor econômico total da contratação (o preço);
 *   2. modalidade de cumprimento da contraprestação dos participantes
 *      (benefício direto em produtos OU dinheiro);
 *   3. meio de pagamento (Pix, cartão), que pertence ao checkout vigente.
 *
 * Regra R3 (13/11/2026): a QA existe só no benefício direto, em produtos para
 * testes locais; não existe QA em dinheiro nem na modalidade DINHEIRO. Por
 * isso o valor total do DINHEIRO pode diferir do benefício direto (Cenário A)
 * ou não (Cenário B) — decisão pendente. A igualdade entre as modalidades só é
 * afirmada quando o servidor publica as duas com o MESMO valor.
 *
 * A contratação só é liberada quando o servidor declara a versão vigente e as
 * DUAS modalidades com composição aprovada — o mesmo critério da guarda do
 * checkout (`permiteCheckoutSF15`) e, antes dela, do próprio banco.
 */

export type CondicaoApresentada = {
  /** Valor total na modalidade BENEFÍCIO DIRETO. */
  valorTotalCentavos: number;
  /** Parcela da SmallFlags, devida em dinheiro (nas duas modalidades). */
  parcelaSmallFlagsCentavos: number;
  /** Produtos para testes locais de qualidade — só no benefício direto. */
  qaEmProdutosCentavos: number;
  /** Valor total na modalidade DINHEIRO; `null` = ainda não aprovado. */
  valorDinheiroCentavos: number | null;
};

export type ApresentacaoOportunidade = {
  /**
   * "previa": SF-v1.5 proposta enquanto a SF-v1.4 está vigente no servidor —
   * informativa, NÃO contratável. "vigente": autoridade ativa do servidor.
   */
  estado: "previa" | "vigente";
  /** As duas modalidades têm composição aprovada no servidor (vigente). */
  modalidadesDefinidas: boolean;
  /**
   * `true` só quando o servidor publica DINHEIRO com o mesmo valor total do
   * benefício direto nas duas condições. Pendente ou diferente: `false`.
   */
  mesmoValorNasDuasFormas: boolean;
  /**
   * R4.3: o servidor vende o benefício direto nesta versão? Na prévia (não
   * contratável) as duas formas são apresentadas como informação.
   */
  beneficioDiretoHabilitado: boolean;
  /** Só a autoridade vigente com as modalidades habilitadas definidas permite contratação. */
  contratavel: boolean;
  /** Primeira contratação (anunciante novo). */
  novo: CondicaoApresentada & {
    /** A primeira contratação inclui a produção das bandeiras da marca. */
    incluiProducaoDeBandeiras: boolean;
  };
  /** Renovação fidelizada: condição definida pelo servidor, nunca escolhida. */
  fidelizado: CondicaoApresentada;
  /** Contraprestação POTENCIAL dos participantes do App — igual nas duas condições e modalidades. */
  participantes: {
    contraprestacaoPotencialCentavos: number;
    participacoesPotenciais: number;
    valorPorParticipacaoCentavos: number;
  };
  /** QA em produtos (só benefício direto): da SmallFlags, nunca dos participantes. */
  qaEmProdutosCentavos: number;
};

function condicao(c: ParcelaPorContratacao): CondicaoApresentada {
  return {
    valorTotalCentavos: c.valorEconomicoCentavos,
    parcelaSmallFlagsCentavos: c.principalSmallFlagsCentavos,
    qaEmProdutosCentavos: c.qaEmProdutosCentavos,
    valorDinheiroCentavos: c.dinheiro ? c.dinheiro.valorEconomicoCentavos : null,
  };
}

/**
 * Monta a apresentação, ou `null` se a resposta do servidor não permitir uma
 * apresentação íntegra. `null` significa: não exibir valor nenhum.
 */
export function apresentacaoOportunidade(
  preco: PublicNichePricing | null | undefined,
): ApresentacaoOportunidade | null {
  if (!preco) return null;
  const b = beneficiosPorOportunidade(preco);
  if (!b) return null;

  const mei = b.novo.contraprestacaoMEIsCentavos;
  // A parcela dos participantes é a mesma nas duas condições.
  if (b.fidelizado.contraprestacaoMEIsCentavos !== mei) return null;
  if (b.participacoesPotenciais * b.valorPorParticipacaoCentavos !== mei) return null;
  for (const c of [b.novo, b.fidelizado]) {
    // Benefício direto: participantes + parcela da SmallFlags + QA em produtos,
    // sem soma dupla; a QA é a mesma nas duas condições e menor que a parcela.
    if (c.valorEconomicoCentavos !== mei + c.principalSmallFlagsCentavos + c.qaEmProdutosCentavos) return null;
    if (c.remuneracaoSmallFlagsCentavos !== c.principalSmallFlagsCentavos) return null;
    if (c.qaEmProdutosCentavos !== b.novo.qaEmProdutosCentavos) return null;
    if (c.qaEmProdutosCentavos >= c.principalSmallFlagsCentavos) return null;
    // Dinheiro: sem QA; participantes + mesma parcela + componente aprovado.
    if (c.dinheiro) {
      if (c.dinheiro.ajusteCentavos < 0) return null;
      if (c.dinheiro.valorEconomicoCentavos !== mei + c.principalSmallFlagsCentavos + c.dinheiro.ajusteCentavos) return null;
    }
  }
  // Renovação fidelizada nunca custa mais que a primeira contratação.
  if (b.fidelizado.valorEconomicoCentavos > b.novo.valorEconomicoCentavos) return null;

  const definidas = b.estado === "vigente" && modalidadesDefinidas(preco);
  const mesmoValor = [b.novo, b.fidelizado].every(
    (c) => c.dinheiro !== null && c.dinheiro.valorEconomicoCentavos === c.valorEconomicoCentavos,
  );
  return {
    estado: b.estado,
    modalidadesDefinidas: definidas,
    beneficioDiretoHabilitado: b.estado !== "vigente"
      || (preco.founding.settlementModes?.habilitadas?.includes("direct_benefits") ?? true),
    mesmoValorNasDuasFormas: mesmoValor,
    contratavel: definidas,
    novo: { ...condicao(b.novo), incluiProducaoDeBandeiras: true },
    fidelizado: condicao(b.fidelizado),
    participantes: {
      contraprestacaoPotencialCentavos: mei,
      participacoesPotenciais: b.participacoesPotenciais,
      valorPorParticipacaoCentavos: b.valorPorParticipacaoCentavos,
    },
    qaEmProdutosCentavos: b.novo.qaEmProdutosCentavos,
  };
}
