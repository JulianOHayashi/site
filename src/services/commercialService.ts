import { supabase } from "../lib/supabase";
import type { CommercialFormationResponse } from "../domain/commercial/types";
import {
  parseFormationResponse,
  CommercialError,
} from "./commercialResponse";
import {
  interpretarPrecoPublico,
  interpretarEconomiaFormacao,
  type PublicNichePricing,
  type FormationEconomicsServer,
} from "../domain/pricing/contractPricing";

/**
 * Serviço comercial — única porta de entrada para as RPCs de leitura.
 *
 * NÃO acessa tabelas diretamente, NÃO calcula status como autoridade, NÃO
 * altera dados. Apenas chama a RPC, delega a validação ao parser PURO
 * (commercialResponse) e normaliza erros — nunca expõe a mensagem técnica
 * do Supabase ao visitante.
 *
 * Taxonomia de erros (kinds), conforme o contrato da Fase 1:
 *   • not_configured      — cliente Supabase ausente/sem env;
 *   • network_error       — falha de comunicação com a RPC;
 *   • unexpected_response — a resposta violou o contrato (parser);
 *   • region_unavailable / formation_unavailable — AUSÊNCIA de região ativa
 *     ou de exclusividade atual. Estas duas NÃO são lançadas como exceção:
 *     são respostas comerciais VÁLIDAS, entregues com os flags
 *     regionAvailable/exclusivityAvailable em false, e renderizadas pela UI
 *     como "Região indisponível" / "Exclusividade indisponível". Os kinds
 *     permanecem definidos para completude da taxonomia.
 */
export { CommercialError } from "./commercialResponse";
export type { CommercialErrorKind } from "./commercialResponse";

/**
 * Resolve a formação comercial atual para UF + cidade.
 * Lança CommercialError com kind apropriado em falha real de serviço/contrato.
 */
export async function fetchCurrentFormation(
  uf: string,
  city: string
): Promise<CommercialFormationResponse> {
  if (!supabase) {
    throw new CommercialError("not_configured");
  }

  let data: unknown;
  try {
    const res = await supabase.rpc("get_current_commercial_formation", {
      p_uf: uf,
      p_city: city,
    });
    if (res.error) {
      // Não propaga a mensagem técnica do Supabase para a UI.
      throw new CommercialError("network_error", res.error.message);
    }
    data = res.data;
  } catch (e) {
    if (e instanceof CommercialError) throw e;
    throw new CommercialError("network_error");
  }

  // Validação de contrato (pura, testável): pode lançar unexpected_response.
  return parseFormationResponse(data);
}

/**
 * Preço vigente da vitrine — SEMPRE calculado no servidor.
 * Contrato violado ou resposta inesperada vira unexpected_response e a UI
 * omite os valores (fail-closed), em vez de exibir número inventado.
 */
export async function fetchPublicPricing(): Promise<PublicNichePricing[]> {
  if (!supabase) {
    throw new CommercialError("not_configured");
  }
  let data: unknown;
  try {
    const res = await supabase.rpc("get_public_niche_pricing", {});
    if (res.error) {
      throw new CommercialError("network_error", res.error.message);
    }
    data = res.data;
  } catch (e) {
    if (e instanceof CommercialError) throw e;
    throw new CommercialError("network_error");
  }
  const lista = interpretarPrecoPublico(data);
  if (lista === null) {
    throw new CommercialError("unexpected_response");
  }
  return lista;
}

/**
 * Economia agregada da formação completa — SEMPRE do servidor.
 *
 * Antes disto a vitrine calculava a economia V2 no próprio navegador. Quando a
 * SF-v1.4 passou a ser a autoridade ativa, a página seguiu exibindo os números
 * da V2: pool de 9.231.600 e R$ 1.099,00 por usuário, contra os 8.391.600 e
 * R$ 993,93 que o servidor passou a reconhecer. Recalcular preço no navegador
 * é justamente o que o handoff proíbe, e esta função fecha essa porta.
 *
 * Contrato violado vira unexpected_response e a UI omite os valores
 * (fail-closed), em vez de exibir número inventado.
 */
export async function fetchFormationEconomics(): Promise<FormationEconomicsServer> {
  if (!supabase) {
    throw new CommercialError("not_configured");
  }
  let data: unknown;
  try {
    const res = await supabase.rpc("get_public_formation_economics", {});
    if (res.error) {
      throw new CommercialError("network_error", res.error.message);
    }
    data = res.data;
  } catch (e) {
    if (e instanceof CommercialError) throw e;
    throw new CommercialError("network_error");
  }
  const economia = interpretarEconomiaFormacao(data);
  if (economia === null) {
    throw new CommercialError("unexpected_response");
  }
  return economia;
}
