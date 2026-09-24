/**
 * ASSINATURA Ed25519 DO GATEWAY Site -> App.
 *
 * ESTE MÓDULO É EXCLUSIVAMENTE DE SERVIDOR. Ele importa `node:crypto` e lê a
 * chave privada do ambiente do processo. Nunca deve ser alcançável a partir de
 * componente React, do bundle do navegador nem de variável `VITE_*` — e é por
 * isso que a chave usa `BDFLOW_APP_BRIDGE_SIGNING_KEY`, sem prefixo de
 * cliente.
 *
 * O QUE É ASSINADO
 * A assinatura é DESTACADA: o corpo HTTP vai como JSON no corpo da requisição,
 * e o JWS compacto no cabeçalho carrega um ENVELOPE que contém o SHA-256 do
 * corpo. Assim o gateway do App verifica, com uma única assinatura, quem
 * chamou, qual rota lógica, qual ação, qual janela de validade, qual JTI
 * antirreplay e qual corpo exato.
 *
 * OS BYTES SÃO PRODUZIDOS UMA VEZ SÓ
 * `JSON.stringify` não garante a mesma saída em duas chamadas independentes se
 * o objeto for tocado no meio, e o hash precisa cobrir exatamente os bytes que
 * viajam. Por isso o corpo é serializado UMA vez, o hash é calculado sobre
 * esses bytes, e são ESSES bytes que o transporte envia.
 *
 * SEGREDO
 * Nenhuma função deste arquivo devolve, registra ou interpola material de
 * chave. Erros de configuração citam o NOME da variável e nada mais.
 */

import {
  createHash,
  createPrivateKey,
  randomUUID,
  sign as assinarBytes,
  type KeyObject,
} from "node:crypto";

// ---------------------------------------------------------------------------
// Contrato congelado do gateway
// ---------------------------------------------------------------------------

export const GATEWAY_PROTOCOL_VERSION = "bdflow-gateway/1";
export const GATEWAY_SIGNATURE_HEADER = "X-BDFlow-Gateway-Signature";
export const GATEWAY_CONTENT_TYPE = "application/json; charset=utf-8";
export const GATEWAY_JWS_ALG = "Ed25519";

/** Máximo aceito pelo gateway do App. */
export const GATEWAY_MAX_LIFETIME_SECONDS = 90;
/** Vida útil usada no transporte: curta, com folga sobre o máximo. */
export const GATEWAY_LIFETIME_SECONDS = 60;

/**
 * Ação -> rota lógica CANÔNICA.
 *
 * A URL de implantação pode conter o prefixo de Edge Function do Supabase, mas
 * o `gateway_path` assinado é sempre a rota lógica abaixo. Assinar o caminho
 * de implantação amarraria a assinatura à hospedagem em vez de amarrá-la ao
 * contrato.
 */
export const GATEWAY_ACTIONS = {
  "benefit_usage.open_token": "/v1/benefit-usage/token/open",
  "benefit_usage.create_request": "/v1/benefit-usage/request",
  "benefit_usage.get_request_status": "/v1/benefit-usage/request/status",
  // Código manual digitado no balcão. O App continua sendo a autoridade sobre
  // o código: o Site não resolve, não expira e não consome nada.
  "benefit_usage.create_request_by_code": "/v1/benefit-usage/code/request",
} as const;

export type GatewayAction = keyof typeof GATEWAY_ACTIONS;

/** Versão do contrato de apresentação, exigida apenas em create_request. */
export const PRESENTATION_CONTRACT_VERSION = 1;

export const GATEWAY_ENV_VARS = [
  "BDFLOW_APP_BRIDGE_URL",
  "BDFLOW_APP_BRIDGE_KEY_ID",
  "BDFLOW_APP_BRIDGE_SIGNING_KEY",
  "BDFLOW_APP_BRIDGE_ISSUER",
  "BDFLOW_APP_BRIDGE_AUDIENCE",
] as const;

export type GatewayEnvVar = (typeof GATEWAY_ENV_VARS)[number];

// ---------------------------------------------------------------------------
// Erro de configuração — falha fechada, sem valor nenhum na mensagem
// ---------------------------------------------------------------------------

export class GatewayConfigError extends Error {
  readonly code = "GATEWAY_CONFIG_INVALID";
  /** Apenas NOMES de variáveis. */
  readonly variables: string[];
  constructor(motivo: string, variables: string[]) {
    super(
      `Configuração do gateway Site->App inválida (${motivo}): ` +
        `${variables.join(", ")}. Nenhuma requisição foi enviada.`
    );
    this.name = "GatewayConfigError";
    this.variables = [...variables];
  }
}

// ---------------------------------------------------------------------------
// Configuração validada
// ---------------------------------------------------------------------------

export type GatewayConfig = {
  readonly baseUrl: string;
  readonly keyId: string;
  readonly issuer: string;
  readonly audience: string;
  /**
   * KeyObject do Node. Não é serializável para JSON e não expõe bytes: mesmo
   * um `JSON.stringify` acidental da configuração não vaza a chave.
   */
  readonly signingKey: KeyObject;
};

/** Quantas das cinco variáveis estão presentes e não vazias. */
export function gatewayVarsPresentes(
  env: Record<string, string | undefined>
): GatewayEnvVar[] {
  return GATEWAY_ENV_VARS.filter((k) => {
    const v = env[k];
    return typeof v === "string" && v.trim() !== "";
  });
}

/**
 * Valida as cinco variáveis e importa a chave privada.
 *
 * FORMATO DA CHAVE: `BDFLOW_APP_BRIDGE_SIGNING_KEY` é a DER PKCS#8 de uma
 * chave privada Ed25519, codificada em base64. Um único formato documentado —
 * aceitar vários seria convidar ambiguidade justamente onde ela custa caro.
 */
export function loadGatewayConfig(
  env: Record<string, string | undefined>
): GatewayConfig {
  const presentes = new Set<string>(gatewayVarsPresentes(env));
  const ausentes = GATEWAY_ENV_VARS.filter((k) => !presentes.has(k));
  if (ausentes.length > 0) {
    throw new GatewayConfigError("variáveis ausentes ou vazias", [...ausentes]);
  }

  const baseUrl = (env.BDFLOW_APP_BRIDGE_URL as string).trim();
  let url: URL;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new GatewayConfigError("URL malformada", ["BDFLOW_APP_BRIDGE_URL"]);
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new GatewayConfigError("esquema de URL não suportado", [
      "BDFLOW_APP_BRIDGE_URL",
    ]);
  }

  const keyId = (env.BDFLOW_APP_BRIDGE_KEY_ID as string).trim();
  const issuer = (env.BDFLOW_APP_BRIDGE_ISSUER as string).trim();
  const audience = (env.BDFLOW_APP_BRIDGE_AUDIENCE as string).trim();

  const signingKey = importarChaveEd25519(
    env.BDFLOW_APP_BRIDGE_SIGNING_KEY as string
  );

  return {
    baseUrl: baseUrl.replace(/\/+$/, ""),
    keyId,
    issuer,
    audience,
    signingKey,
  };
}

/**
 * base64 -> PKCS#8 DER -> KeyObject Ed25519.
 *
 * Toda falha vira a MESMA mensagem, citando só o nome da variável: a exceção
 * original do OpenSSL pode conter fragmentos do material apresentado, e isso
 * não pode chegar a log algum.
 */
function importarChaveEd25519(valor: string): KeyObject {
  const falhar = () =>
    new GatewayConfigError(
      "chave de assinatura não é uma Ed25519 PKCS#8 DER em base64",
      ["BDFLOW_APP_BRIDGE_SIGNING_KEY"]
    );

  let der: Buffer;
  try {
    const limpo = valor.trim();
    der = Buffer.from(limpo, "base64");
    // Buffer.from ignora lixo silenciosamente; um round-trip vazio ou curto
    // demais denuncia entrada que não era base64 de uma PKCS#8.
    if (der.length < 16) throw new Error("curta demais");
  } catch {
    throw falhar();
  }

  let chave: KeyObject;
  try {
    chave = createPrivateKey({ key: der, format: "der", type: "pkcs8" });
  } catch {
    throw falhar();
  }

  if (chave.asymmetricKeyType !== "ed25519") {
    throw falhar();
  }
  return chave;
}

// ---------------------------------------------------------------------------
// Envelope assinado
// ---------------------------------------------------------------------------

export type GatewayEnvelope = {
  protocol_version: string;
  action: GatewayAction;
  issuer: string;
  audience: string;
  key_id: string;
  issued_at: number;
  not_before: number;
  expires_at: number;
  jti: string;
  request_correlation_id: string;
  http_method: "POST";
  gateway_path: string;
  body_sha256: string;
  presentation_contract_version?: number;
};

export type SignedGatewayRequest = {
  /** URL de implantação efetivamente chamada. */
  readonly url: string;
  /** Rota lógica canônica, que é a assinada. */
  readonly gatewayPath: string;
  readonly action: GatewayAction;
  /** Os bytes EXATOS que devem ser enviados — os mesmos que foram hasheados. */
  readonly bodyText: string;
  readonly headers: Readonly<Record<string, string>>;
  /** JWS compacto: header.payload.signature */
  readonly jws: string;
  readonly envelope: Readonly<GatewayEnvelope>;
};

function base64url(b: Buffer): string {
  return b.toString("base64url");
}

export function sha256Hex(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/**
 * Monta e assina uma requisição do gateway.
 *
 * `nowSeconds` e `correlationId` são injetáveis apenas para tornar o teste
 * determinístico; em produção vêm do relógio e de `randomUUID`.
 */
export function signGatewayRequest(params: {
  config: GatewayConfig;
  action: GatewayAction;
  body: unknown;
  nowSeconds?: number;
  correlationId?: string;
  lifetimeSeconds?: number;
}): SignedGatewayRequest {
  const { config, action } = params;
  const gatewayPath = GATEWAY_ACTIONS[action];
  if (!gatewayPath) {
    throw new GatewayConfigError("ação desconhecida", ["BDFLOW_APP_BRIDGE_URL"]);
  }

  const vida = params.lifetimeSeconds ?? GATEWAY_LIFETIME_SECONDS;
  if (!Number.isInteger(vida) || vida <= 0 || vida > GATEWAY_MAX_LIFETIME_SECONDS) {
    throw new GatewayConfigError("janela de validade fora do limite", [
      "BDFLOW_APP_BRIDGE_URL",
    ]);
  }

  // ---- os bytes do corpo, produzidos UMA vez ----
  const bodyText = JSON.stringify(params.body ?? {});
  const bodyBytes = Buffer.from(bodyText, "utf8");
  const bodySha256 = sha256Hex(bodyBytes);

  const emitidoEm = Math.floor(params.nowSeconds ?? Date.now() / 1000);
  const envelope: GatewayEnvelope = {
    protocol_version: GATEWAY_PROTOCOL_VERSION,
    action,
    issuer: config.issuer,
    audience: config.audience,
    key_id: config.keyId,
    issued_at: emitidoEm,
    not_before: emitidoEm,
    expires_at: emitidoEm + vida,
    jti: randomUUID(),
    request_correlation_id: params.correlationId ?? randomUUID(),
    http_method: "POST",
    gateway_path: gatewayPath,
    body_sha256: bodySha256,
  };
  // As duas criações de solicitação carregam a versão do contrato de
  // apresentação; `open_token` não, e continua não carregando.
  if (action === "benefit_usage.create_request"
      || action === "benefit_usage.create_request_by_code") {
    envelope.presentation_contract_version = PRESENTATION_CONTRACT_VERSION;
  }

  const header = { alg: GATEWAY_JWS_ALG, kid: config.keyId };
  const entradaAssinatura =
    base64url(Buffer.from(JSON.stringify(header), "utf8")) +
    "." +
    base64url(Buffer.from(JSON.stringify(envelope), "utf8"));

  // Ed25519 no Node: algoritmo NULO, a curva já determina o hash interno.
  const assinatura = assinarBytes(
    null,
    Buffer.from(entradaAssinatura, "ascii"),
    config.signingKey
  );
  const jws = `${entradaAssinatura}.${base64url(assinatura)}`;

  return {
    url: `${config.baseUrl}${gatewayPath}`,
    gatewayPath,
    action,
    bodyText,
    headers: Object.freeze({
      "Content-Type": GATEWAY_CONTENT_TYPE,
      [GATEWAY_SIGNATURE_HEADER]: jws,
    }),
    jws,
    envelope: Object.freeze(envelope),
  };
}