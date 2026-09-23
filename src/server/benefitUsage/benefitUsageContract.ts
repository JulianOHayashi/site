/**
 * CONTRATO DE USO DE BENEFÍCIO — validadores e montagem de corpo.
 *
 * Puro e sem segredo: nada aqui assina, faz rede ou toca ambiente. Existe
 * separado para que o formato exigido pelo App possa ser provado em teste sem
 * chave nenhuma, e para que o navegador possa reusar os MESMOS validadores de
 * localizador sem arrastar `node:crypto` junto.
 */

/** UUID em qualquer versão, minúsculo ou maiúsculo. */
export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Segredo cru do token: exatamente 64 hexadecimais MINÚSCULOS. */
export const RAW_SECRET_RE = /^[0-9a-f]{64}$/;

/** UF brasileira. */
export const UF_RE = /^[A-Z]{2}$/;

export function ehUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

/**
 * Maiúsculas NÃO são aceitas: o App emite minúsculo, e normalizar aqui
 * esconderia um locator que veio de outro lugar.
 */
export function ehSegredoCru(v: unknown): v is string {
  return typeof v === "string" && RAW_SECRET_RE.test(v);
}

export type ValidatorRole = "partner_owner" | "partner_manager";

export function ehPapelValidador(v: unknown): v is ValidatorRole {
  return v === "partner_owner" || v === "partner_manager";
}

/** Pacote autoritativo devolvido pela RPC do Site. Nunca vem do navegador. */
export type BenefitUsageAuthority = {
  company_id: string;
  unit_id: string;
  partner_network_bridge_id: string;
  partner_branch_bridge_id: string;
  validator_bridge_id: string;
  validator_role: ValidatorRole;
  snapshot_presentation_version: number;
  snapshot_partner_display_name: string;
  snapshot_branch_display_name: string;
  snapshot_branch_city_name: string;
  snapshot_branch_state_code: string;
  snapshot_branch_location_label: string;
};

export class BenefitUsageError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(code: string, status: number, message?: string) {
    // A mensagem NUNCA interpola entrada do usuário: o segredo cru circula
    // nesta mesma pilha, e uma mensagem "amigável" é o jeito clássico de ele
    // acabar num log.
    super(message ?? code);
    this.name = "BenefitUsageError";
    this.code = code;
    this.status = status;
  }
}

/**
 * Confere e tipa o retorno da RPC. Qualquer campo fora do contrato nega:
 * pacote incompleto não vira requisição parcial ao App.
 */
export function interpretarAutoridade(data: unknown): BenefitUsageAuthority {
  if (!data || typeof data !== "object") {
    throw new BenefitUsageError("authority_unavailable", 502);
  }
  const o = data as Record<string, unknown>;
  if (o.ok !== true) throw new BenefitUsageError("authority_unavailable", 502);
  if (o.authorized !== true) throw new BenefitUsageError("not_authorized", 403);

  const textos = [
    "snapshot_partner_display_name",
    "snapshot_branch_display_name",
    "snapshot_branch_city_name",
    "snapshot_branch_location_label",
  ] as const;
  const uuids = [
    "company_id",
    "unit_id",
    "partner_network_bridge_id",
    "partner_branch_bridge_id",
    "validator_bridge_id",
  ] as const;

  for (const k of uuids) {
    if (!ehUuid(o[k])) throw new BenefitUsageError("authority_malformed", 502);
  }
  for (const k of textos) {
    if (typeof o[k] !== "string" || (o[k] as string).trim() === "") {
      throw new BenefitUsageError("authority_malformed", 502);
    }
  }
  if (!ehPapelValidador(o.validator_role)) {
    throw new BenefitUsageError("authority_malformed", 502);
  }
  if (typeof o.snapshot_branch_state_code !== "string" ||
      !UF_RE.test(o.snapshot_branch_state_code)) {
    throw new BenefitUsageError("authority_malformed", 502);
  }
  if (o.snapshot_presentation_version !== 1) {
    throw new BenefitUsageError("authority_malformed", 502);
  }
  return o as unknown as BenefitUsageAuthority;
}

// ---------------------------------------------------------------------------
// Corpos exigidos pelo App
// ---------------------------------------------------------------------------

export type OpenTokenBody = {
  public_lookup_id: string;
  raw_token_secret: string;
  partner_network_bridge_id: string;
};

export type CreateRequestBody = {
  public_lookup_id: string;
  raw_token_secret: string;
  request_correlation_id: string;
  partner_network_bridge_id: string;
  partner_branch_bridge_id: string;
  validator_bridge_id: string;
  validator_role: ValidatorRole;
  physical_photo_id_checked: true;
  snapshot_presentation_version: 1;
  snapshot_partner_display_name: string;
  snapshot_branch_display_name: string;
  snapshot_branch_location_label: string;
  snapshot_branch_city_name: string;
  snapshot_branch_state_code: string;
};

export function montarOpenTokenBody(
  publicLookupId: string,
  rawSecret: string,
  autoridade: BenefitUsageAuthority
): OpenTokenBody {
  return {
    public_lookup_id: publicLookupId,
    raw_token_secret: rawSecret,
    partner_network_bridge_id: autoridade.partner_network_bridge_id,
  };
}

export function montarCreateRequestBody(
  publicLookupId: string,
  rawSecret: string,
  requestCorrelationId: string,
  autoridade: BenefitUsageAuthority
): CreateRequestBody {
  return {
    public_lookup_id: publicLookupId,
    raw_token_secret: rawSecret,
    request_correlation_id: requestCorrelationId,
    // Todo campo de identidade e de apresentação sai da AUTORIDADE, jamais do
    // corpo recebido do navegador.
    partner_network_bridge_id: autoridade.partner_network_bridge_id,
    partner_branch_bridge_id: autoridade.partner_branch_bridge_id,
    validator_bridge_id: autoridade.validator_bridge_id,
    validator_role: autoridade.validator_role,
    physical_photo_id_checked: true,
    snapshot_presentation_version: 1,
    snapshot_partner_display_name: autoridade.snapshot_partner_display_name,
    snapshot_branch_display_name: autoridade.snapshot_branch_display_name,
    snapshot_branch_location_label: autoridade.snapshot_branch_location_label,
    snapshot_branch_city_name: autoridade.snapshot_branch_city_name,
    snapshot_branch_state_code: autoridade.snapshot_branch_state_code,
  };
}

// ---------------------------------------------------------------------------
// Código manual digitado no balcão
//
// O App é a autoridade sobre o código: o Site não faz hash, não faz HMAC, não
// consulta tabela do App, não resolve expiração e não implementa uso único.
// Ele transporta o código tal como foi digitado e prova QUEM está validando.
// ---------------------------------------------------------------------------

/** Forma aceita no cliente: 8 alfanuméricos maiúsculos, já normalizados. */
export const DISPLAY_CODE_RE = /^[A-Z0-9]{8}$/;

/**
 * Normalização de apresentação: o balconista digita `ABCD-7K2M`, o contrato
 * viaja como `ABCD7K2M`. Só isso — nenhuma tentativa de adivinhar se o código
 * existe, porque essa resposta é do App.
 */
export function normalizarDisplayCode(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const limpo = v.trim().toUpperCase().replace(/[-\s]/g, "");
  return DISPLAY_CODE_RE.test(limpo) ? limpo : null;
}

export function ehDisplayCode(v: unknown): v is string {
  return typeof v === "string" && DISPLAY_CODE_RE.test(v);
}

export type CreateRequestByCodeBody = {
  display_code: string;
  request_correlation_id: string;
  partner_network_bridge_id: string;
  partner_branch_bridge_id: string;
  validator_bridge_id: string;
  validator_role: ValidatorRole;
  physical_photo_id_checked: true;
  snapshot_presentation_version: 1;
  snapshot_partner_display_name: string;
  snapshot_branch_display_name: string;
  snapshot_branch_location_label: string;
  snapshot_branch_city_name: string;
  snapshot_branch_state_code: string;
};

/**
 * Corpo do código manual. Identidade e apresentação saem TODAS da autoridade
 * derivada no servidor; do navegador vem apenas o código.
 *
 * Note o que NÃO existe aqui: `public_lookup_id` e `raw_token_secret` são do
 * fluxo de QR e não têm significado neste. Misturar os dois seria converter
 * um código de balcão em portador de token, que é outra coisa.
 */
export function montarCreateRequestByCodeBody(
  displayCode: string,
  requestCorrelationId: string,
  autoridade: BenefitUsageAuthority
): CreateRequestByCodeBody {
  return {
    display_code: displayCode,
    request_correlation_id: requestCorrelationId,
    partner_network_bridge_id: autoridade.partner_network_bridge_id,
    partner_branch_bridge_id: autoridade.partner_branch_bridge_id,
    validator_bridge_id: autoridade.validator_bridge_id,
    validator_role: autoridade.validator_role,
    physical_photo_id_checked: true,
    snapshot_presentation_version: 1,
    snapshot_partner_display_name: autoridade.snapshot_partner_display_name,
    snapshot_branch_display_name: autoridade.snapshot_branch_display_name,
    snapshot_branch_location_label: autoridade.snapshot_branch_location_label,
    snapshot_branch_city_name: autoridade.snapshot_branch_city_name,
    snapshot_branch_state_code: autoridade.snapshot_branch_state_code,
  };
}