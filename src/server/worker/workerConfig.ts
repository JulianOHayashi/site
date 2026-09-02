/**
 * R16 — CONFIGURAÇÃO DO WORKER.
 *
 * Estritamente server-side. Nada aqui é lido pelo navegador, e segredo sob
 * prefixo público é REJEITADO em vez de aceito com aviso: aceitar
 * `VITE_SMTP_PASSWORD` seria embutir a senha no bundle.
 *
 * Nenhuma coerção silenciosa. Valor inválido produz erro com código próprio e
 * mensagem sanitizada — o nome da variável e o limite, nunca o valor.
 */

import { BATCH_SIZE_MINIMO, RECOVERY_RESERVE_PADRAO } from "./supabaseOutboxGateway";

export class WorkerConfigError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "WorkerConfigError";
    this.code = code;
  }
}

/** Modos de transporte realmente implementados e testados. */
export type SmtpMode = "implicit_tls" | "starttls" | "plaintext_local_only";

export type StagingRecipientPolicy =
  | { kind: "override"; address: string }
  | { kind: "allowlist"; addresses: readonly string[] };

export type WorkerConfig = {
  environment: "development" | "staging" | "production";
  supabaseUrl: string;
  supabaseServiceKey: string;
  siteBaseUrl: string;
  smtp: {
    host: string;
    port: number;
    mode: SmtpMode;
    username?: string;
    password?: string;
    fromAddress: string;
    fromName?: string;
    connectTimeoutMs: number;
    readTimeoutMs: number;
  };
  batchSize: number;
  recoveryReserve: number;
  pollIntervalMs: number;
  /** Presente e obrigatório em staging; ausente em produção. */
  stagingRecipient?: StagingRecipientPolicy;
};

export type FonteEnv = Record<string, string | undefined>;

function exigir(env: FonteEnv, nome: string): string {
  const v = env[nome];
  if (typeof v !== "string" || v.trim().length === 0) {
    throw new WorkerConfigError("missing_required_env", `variável ausente: ${nome}`);
  }
  return v.trim();
}

function inteiro(env: FonteEnv, nome: string, padrao: number, min: number, max: number): number {
  const bruto = env[nome];
  if (bruto === undefined || bruto.trim() === "") return padrao;
  const n = Number(bruto);
  if (!Number.isInteger(n)) {
    throw new WorkerConfigError("invalid_integer_env", `${nome} deve ser inteiro`);
  }
  if (n < min || n > max) {
    throw new WorkerConfigError(
      "integer_env_out_of_range",
      `${nome} deve estar entre ${min} e ${max}`
    );
  }
  return n;
}

/**
 * Recusa segredo declarado sob prefixo exposto ao navegador. Esta é a
 * barreira que impede a chave de service_role de entrar no bundle.
 */
export function rejeitarSegredosPublicos(env: FonteEnv): void {
  const sensiveis = ["SERVICE_ROLE", "SERVICE_KEY", "SMTP_PASSWORD", "SMTP_PASS", "SECRET"];
  for (const chave of Object.keys(env)) {
    const publico = chave.startsWith("VITE_") || chave.startsWith("NEXT_PUBLIC_");
    if (!publico) continue;
    if (sensiveis.some((s) => chave.toUpperCase().includes(s))) {
      throw new WorkerConfigError(
        "secret_under_public_prefix",
        `segredo sob prefixo público não é permitido: ${chave}`
      );
    }
  }
}

/** Valida a base pública do Site. É a ÚNICA origem permitida nos links. */
export function validarSiteBaseUrl(
  bruto: string,
  environment: WorkerConfig["environment"]
): string {
  let u: URL;
  try {
    u = new URL(bruto);
  } catch {
    throw new WorkerConfigError("invalid_site_base_url", "SITE_BASE_URL malformada");
  }
  const localPermitido =
    environment === "development" &&
    (u.hostname === "localhost" || u.hostname === "127.0.0.1");

  if (u.protocol !== "https:" && !localPermitido) {
    throw new WorkerConfigError(
      "insecure_site_base_url",
      "SITE_BASE_URL deve usar https fora de desenvolvimento"
    );
  }
  if (u.username || u.password) {
    throw new WorkerConfigError(
      "site_base_url_has_credentials",
      "SITE_BASE_URL não pode conter credenciais"
    );
  }
  // Normaliza sem barra final, para concatenação previsível de rotas.
  return u.origin + (u.pathname === "/" ? "" : u.pathname.replace(/\/$/, ""));
}

function enderecoSimples(rotulo: string, valor: string): string {
  if (/[\r\n\0\s<>,;]/.test(valor) || !valor.includes("@")) {
    throw new WorkerConfigError("invalid_email_address", `${rotulo} inválido`);
  }
  return valor;
}

/**
 * Política de destinatário em staging.
 *
 * FAIL-CLOSED: em staging, sem override e sem allowlist, o worker NÃO SOBE.
 * Sem isso, um smoke de staging apontado para o banco real enviaria e-mail a
 * clientes de verdade — e o erro só apareceria depois da entrega.
 *
 * Produção NÃO herda override: se `STAGING_RECIPIENT_OVERRIDE` estiver
 * definida com `ENVIRONMENT=production`, é erro de configuração, não um
 * atalho conveniente.
 */
export function resolverPoliticaDestinatario(
  env: FonteEnv,
  environment: WorkerConfig["environment"]
): StagingRecipientPolicy | undefined {
  const override = env.STAGING_RECIPIENT_OVERRIDE?.trim();
  const allowlistBruta = env.STAGING_RECIPIENT_ALLOWLIST?.trim();

  if (environment === "production") {
    if (override || allowlistBruta) {
      throw new WorkerConfigError(
        "staging_policy_in_production",
        "política de destinatário de staging não pode ser usada em produção"
      );
    }
    return undefined;
  }

  if (environment === "development") {
    if (override) return { kind: "override", address: enderecoSimples("override", override) };
    return undefined;
  }

  // staging: exatamente uma das duas, obrigatoriamente.
  if (override && allowlistBruta) {
    throw new WorkerConfigError(
      "staging_policy_ambiguous",
      "defina override OU allowlist, não ambos"
    );
  }
  if (override) {
    return { kind: "override", address: enderecoSimples("override", override) };
  }
  if (allowlistBruta) {
    const enderecos = allowlistBruta
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
      .map((s) => enderecoSimples("allowlist", s));
    if (enderecos.length === 0) {
      throw new WorkerConfigError("staging_allowlist_empty", "allowlist de staging vazia");
    }
    return { kind: "allowlist", addresses: Object.freeze(enderecos) };
  }

  throw new WorkerConfigError(
    "staging_recipient_safety_missing",
    "staging exige STAGING_RECIPIENT_OVERRIDE ou STAGING_RECIPIENT_ALLOWLIST"
  );
}

export function carregarWorkerConfig(env: FonteEnv): WorkerConfig {
  rejeitarSegredosPublicos(env);

  const amb = exigir(env, "ENVIRONMENT");
  if (amb !== "development" && amb !== "staging" && amb !== "production") {
    throw new WorkerConfigError("invalid_environment", "ENVIRONMENT inválido");
  }
  const environment = amb;

  const supabaseUrl = exigir(env, "SUPABASE_URL");
  try {
    const u = new URL(supabaseUrl);
    if (u.protocol !== "https:" && environment !== "development") {
      throw new WorkerConfigError("insecure_supabase_url", "SUPABASE_URL deve usar https");
    }
  } catch (e) {
    if (e instanceof WorkerConfigError) throw e;
    throw new WorkerConfigError("invalid_supabase_url", "SUPABASE_URL malformada");
  }

  const supabaseServiceKey = exigir(env, "SUPABASE_SERVICE_ROLE_KEY");
  const siteBaseUrl = validarSiteBaseUrl(exigir(env, "SITE_BASE_URL"), environment);

  const modoBruto = exigir(env, "SMTP_MODE");
  if (
    modoBruto !== "implicit_tls" &&
    modoBruto !== "starttls" &&
    modoBruto !== "plaintext_local_only"
  ) {
    throw new WorkerConfigError("invalid_smtp_mode", "SMTP_MODE não suportado");
  }
  const mode = modoBruto as SmtpMode;

  if (mode === "plaintext_local_only" && environment !== "development") {
    throw new WorkerConfigError(
      "plaintext_smtp_forbidden",
      "SMTP em texto claro só é permitido em desenvolvimento"
    );
  }

  const host = exigir(env, "SMTP_HOST");
  if (/[\r\n\0\s]/.test(host)) {
    throw new WorkerConfigError("invalid_smtp_host", "SMTP_HOST inválido");
  }
  const port = inteiro(env, "SMTP_PORT", mode === "implicit_tls" ? 465 : 587, 1, 65535);

  const username = env.SMTP_USERNAME?.trim() || undefined;
  const password = env.SMTP_PASSWORD?.trim() || undefined;

  if ((username && !password) || (!username && password)) {
    throw new WorkerConfigError(
      "incomplete_smtp_credentials",
      "SMTP_USERNAME e SMTP_PASSWORD devem ser fornecidos juntos"
    );
  }
  // Credencial só trafega sobre transporte cifrado aprovado.
  if (username && mode === "plaintext_local_only") {
    throw new WorkerConfigError(
      "auth_over_plaintext_forbidden",
      "autenticação SMTP exige transporte cifrado"
    );
  }

  const batchSize = inteiro(env, "WORKER_BATCH_SIZE", 10, 0, 500);
  if (batchSize < BATCH_SIZE_MINIMO) {
    throw new WorkerConfigError(
      "batch_size_below_minimum",
      `WORKER_BATCH_SIZE deve ser >= ${BATCH_SIZE_MINIMO}`
    );
  }
  const recoveryReserve = inteiro(
    env,
    "WORKER_RECOVERY_RESERVE",
    RECOVERY_RESERVE_PADRAO,
    0,
    500
  );
  if (recoveryReserve < 1) {
    throw new WorkerConfigError(
      "recovery_reserve_below_minimum",
      "WORKER_RECOVERY_RESERVE deve ser >= 1"
    );
  }
  if (recoveryReserve >= batchSize) {
    throw new WorkerConfigError(
      "recovery_reserve_exceeds_batch",
      "WORKER_RECOVERY_RESERVE deve ser < WORKER_BATCH_SIZE"
    );
  }

  return {
    environment,
    supabaseUrl,
    supabaseServiceKey,
    siteBaseUrl,
    smtp: {
      host,
      port,
      mode,
      username,
      password,
      fromAddress: enderecoSimples("SMTP_FROM_ADDRESS", exigir(env, "SMTP_FROM_ADDRESS")),
      fromName: env.SMTP_FROM_NAME?.trim() || undefined,
      connectTimeoutMs: inteiro(env, "SMTP_CONNECT_TIMEOUT_MS", 15_000, 1_000, 120_000),
      readTimeoutMs: inteiro(env, "SMTP_READ_TIMEOUT_MS", 30_000, 1_000, 300_000),
    },
    batchSize,
    recoveryReserve,
    pollIntervalMs: inteiro(env, "WORKER_POLL_INTERVAL_MS", 30_000, 1_000, 600_000),
    stagingRecipient: resolverPoliticaDestinatario(env, environment),
  };
}

/**
 * Aplica a política de destinatário ANTES de o endereço chegar ao envelope.
 *
 * `{ enviar: false }` significa zero transmissão — o worker não tenta, não
 * marca enviado e não inventa destinatário alternativo.
 */
export function aplicarPoliticaDestinatario(
  original: string,
  politica: StagingRecipientPolicy | undefined
): { enviar: true; destino: string } | { enviar: false; motivo: string } {
  if (!politica) return { enviar: true, destino: original };

  if (politica.kind === "override") {
    // O destinatário original NUNCA é usado como destino SMTP.
    return { enviar: true, destino: politica.address };
  }

  const permitido = politica.addresses.some(
    (a) => a.toLowerCase() === original.toLowerCase()
  );
  return permitido
    ? { enviar: true, destino: original }
    : { enviar: false, motivo: "recipient_not_in_staging_allowlist" };
}
