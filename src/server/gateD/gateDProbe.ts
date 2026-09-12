/**
 * SONDA GATE D — prova criptográfica Site -> App. TEMPORÁRIA, SÓ PREVIEW.
 *
 * O QUE ESTA SONDA PROVA
 * Que a chave Ed25519 que a Vercel guarda assina uma requisição que o gateway
 * do App aceita na camada de assinatura/confiança, e que o mesmo JWS enviado
 * de novo é recusado como replay.
 *
 * POR QUE ASSINA UMA VEZ SÓ
 * Chamar o cliente duas vezes geraria dois JTI e duas assinaturas diferentes
 * — duas requisições legítimas, e prova nenhuma. Replay é o MESMO envelope
 * chegando outra vez. Por isso a assinatura acontece uma única vez e os
 * mesmos bytes viajam duas vezes.
 *
 * O QUE ELA NÃO FAZ
 * Não abre nem consome benefício: o locator e a ponte são fixtures
 * sinteticamente inválidos, então a primeira chamada é rejeitada por regra de
 * negócio DEPOIS de passar pela autenticação — que é exatamente o ponto.
 * Não chama `create_request`. Não escreve no banco do Site. Não liga feature
 * gate. O único efeito remoto pretendido é a entrada do JTI da sonda no
 * registro antirreplay do App.
 *
 * CÓDIGO DIAGNÓSTICO, ISOLADO DO FLUXO DE PRODUTO. Precisa ser removido antes
 * do candidato final — ver o requisito de limpeza do Gate D.
 */

import {
  GATEWAY_CONTENT_TYPE,
  GATEWAY_SIGNATURE_HEADER,
  loadGatewayConfig,
  signGatewayRequest,
  type SignedGatewayRequest,
} from "../provisioning/gatewaySigner.js";

/**
 * Fixtures FIXOS no código. Nada aqui vem do chamador: a sonda não aceita
 * ação, URL, locator, ponte, segredo, JTI, correlação, issuer, audience nem
 * kid. Um diagnóstico que aceitasse qualquer um desses viraria um oráculo de
 * assinatura — alguém com acesso ao endpoint mandaria o Site assinar o que
 * quisesse.
 */
const SONDA_PUBLIC_LOOKUP_ID = "00000000-0000-0000-0000-000000000001";
const SONDA_RAW_TOKEN_SECRET = "0".repeat(64);
const SONDA_PARTNER_NETWORK_BRIDGE_ID = "00000000-0000-0000-0000-000000000002";

export type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string }
) => Promise<{ status: number; ok: boolean; text: () => Promise<string> }>;

export type RespostaSonda = { http_status: number; code: string | null };

export type ResultadoSonda = {
  ok: true;
  gate: "D";
  first: RespostaSonda;
  second: RespostaSonda;
  same_signed_request_reused: boolean;
};

export class SondaIndisponivelError extends Error {
  readonly code = "not_available";
  constructor() {
    super("not_available");
    this.name = "SondaIndisponivelError";
  }
}

export class SondaConfigError extends Error {
  readonly code = "gateway_not_configured";
  constructor() {
    super("gateway_not_configured");
    this.name = "SondaConfigError";
  }
}

/**
 * Extrai da resposta do App apenas um rótulo curto e seguro.
 *
 * Não devolve o corpo, nem mensagem, nem stack: a resposta pode ecoar o que
 * foi enviado. O filtro de charset é deliberado — só maiúsculas, dígitos e
 * separadores simples atravessam, então nem um `code` inesperado consegue
 * carregar payload.
 */
export function extrairCodigoSeguro(texto: string): string | null {
  let v: unknown;
  try {
    v = JSON.parse(texto);
  } catch {
    return null;
  }
  if (!v || typeof v !== "object") return null;
  const o = v as Record<string, unknown>;
  for (const chave of ["code", "error_code", "status", "reason"]) {
    const bruto = o[chave];
    if (typeof bruto !== "string") continue;
    const limpo = bruto.trim();
    if (limpo === "" || limpo.length > 64) continue;
    if (!/^[A-Za-z0-9_.:-]+$/.test(limpo)) continue;
    return limpo;
  }
  return null;
}

type EnvioRegistrado = {
  url: string;
  body: string;
  assinatura: string;
  contentType: string;
};

/**
 * `assinar` é injetável apenas para o teste contar as chamadas. Em execução
 * real é `signGatewayRequest`, a única implementação Ed25519 do Site.
 */
export async function executarSondaGateD(
  env: Record<string, string | undefined>,
  deps: {
    fetchImpl: FetchLike;
    assinar?: (p: Parameters<typeof signGatewayRequest>[0]) => SignedGatewayRequest;
  }
): Promise<ResultadoSonda> {
  // PORTA 1 — só Preview. Antes de carregar configuração, antes de assinar,
  // antes de qualquer rede.
  if (env.VERCEL_ENV !== "preview") {
    throw new SondaIndisponivelError();
  }

  let config;
  try {
    config = loadGatewayConfig(env);
  } catch {
    // Falha fechada sem detalhe: o erro de configuração cita nomes de
    // variável, e este endpoint não devolve nem isso.
    throw new SondaConfigError();
  }

  const assinar = deps.assinar ?? signGatewayRequest;

  // ASSINATURA ÚNICA.
  const req = assinar({
    config,
    action: "benefit_usage.open_token",
    body: {
      public_lookup_id: SONDA_PUBLIC_LOOKUP_ID,
      raw_token_secret: SONDA_RAW_TOKEN_SECRET,
      partner_network_bridge_id: SONDA_PARTNER_NETWORK_BRIDGE_ID,
    },
  });

  // Congelados em memória: é isto, byte a byte, que vai nas duas vezes.
  const url = req.url;
  const bodyText = req.bodyText;
  const jws = req.jws;
  const headers: Record<string, string> = {
    "Content-Type": GATEWAY_CONTENT_TYPE,
    [GATEWAY_SIGNATURE_HEADER]: jws,
  };

  const enviados: EnvioRegistrado[] = [];
  const enviar = async (): Promise<RespostaSonda> => {
    enviados.push({
      url,
      body: bodyText,
      assinatura: headers[GATEWAY_SIGNATURE_HEADER],
      contentType: headers["Content-Type"],
    });
    const res = await deps.fetchImpl(url, {
      method: "POST",
      headers: { ...headers },
      body: bodyText,
    });
    let texto = "";
    try {
      texto = await res.text();
    } catch {
      texto = "";
    }
    return { http_status: res.status, code: extrairCodigoSeguro(texto) };
  };

  const first = await enviar();
  const second = await enviar();

  // Verificado, não afirmado: a bandeira sai da comparação real dos dois
  // envios. Declará-la `true` por construção seria a sonda testemunhando a si
  // mesma.
  const a = enviados[0];
  const b = enviados[1];
  const same_signed_request_reused =
    enviados.length === 2 &&
    a.url === b.url &&
    a.body === b.body &&
    a.assinatura === b.assinatura &&
    a.contentType === b.contentType;

  return { ok: true, gate: "D", first, second, same_signed_request_reused };
}
