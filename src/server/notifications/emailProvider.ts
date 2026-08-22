/**
 * BLOCO 12 — Adaptador de provedor de e-mail transacional.
 *
 * REGRAS DE SEGURANÇA (verificadas por teste):
 *   * a configuração é lida em TEMPO DE EXECUÇÃO do ambiente do processo
 *     server-side — nunca importada de arquivo versionado;
 *   * NENHUM valor de configuração é impresso, registrado ou devolvido;
 *   * o segredo cunhado no despacho (ex.: token de convite) circula apenas em
 *     memória, entra no corpo da mensagem e NUNCA vai para log nem para a fila;
 *   * este módulo é server-side: não é importado pelo bundle do navegador.
 *
 * Sem credenciais reais configuradas, o despacho usa um transporte FAKE
 * explicitamente rotulado. Isso NÃO prova entrega em produção — ver
 * REAL_PROVIDER_CREDENTIAL_CONFIGURATION no relatório.
 */

export type EmailMessage = {
  to: string;
  templateKey: string;
  /** Dados do template; pode conter segredo cunhado no despacho. */
  data: Record<string, unknown>;
  idempotencyKey: string;
};

export type SendResult =
  | { ok: true; provider: string; providerMessageId: string }
  | { ok: false; provider: string; errorCode: string; errorMessage: string };

export interface EmailTransport {
  readonly name: string;
  send(message: EmailMessage): Promise<SendResult>;
}

/** Nomes das variáveis de ambiente — NUNCA os valores. */
export const EMAIL_ENV_VARS = [
  "BDFLOW_EMAIL_PROVIDER",
  "BDFLOW_EMAIL_API_KEY",
  "BDFLOW_EMAIL_FROM",
  "BDFLOW_EMAIL_API_BASE_URL",
] as const;

export type EmailConfigStatus = {
  configured: boolean;
  /** Apenas os NOMES das variáveis ausentes. */
  missing: string[];
  transportName: string;
};

type Env = Record<string, string | undefined>;

/**
 * Lê a configuração em tempo de execução e reporta apenas presença/ausência.
 * Jamais devolve, registra ou concatena valores.
 */
export function inspectEmailConfig(env: Env): EmailConfigStatus {
  const missing = EMAIL_ENV_VARS.filter((k) => {
    const v = env[k];
    return typeof v !== "string" || v.trim() === "";
  });
  return {
    configured: missing.length === 0,
    missing: [...missing],
    transportName: missing.length === 0 ? String(env.BDFLOW_EMAIL_PROVIDER) : "fake-local",
  };
}

/**
 * Transporte FAKE local, rotulado sem ambiguidade. Guarda as mensagens em
 * memória para inspeção em teste; nunca faz rede.
 */
export class FakeLocalTransport implements EmailTransport {
  readonly name = "fake-local";
  readonly sent: EmailMessage[] = [];
  private failNext: { errorCode: string; errorMessage: string } | null = null;

  failOnce(errorCode: string, errorMessage: string): void {
    this.failNext = { errorCode, errorMessage };
  }

  async send(message: EmailMessage): Promise<SendResult> {
    if (this.failNext) {
      const f = this.failNext;
      this.failNext = null;
      return { ok: false, provider: this.name, ...f };
    }
    this.sent.push(message);
    return {
      ok: true,
      provider: this.name,
      providerMessageId: `fake-${message.idempotencyKey}`,
    };
  }
}

/**
 * Transporte HTTP genérico; a chave vive só no cabeçalho da requisição.
 *
 * Os campos de configuração usam campos privados REAIS de JavaScript (#): o
 * `private` do TypeScript some na compilação e deixaria a chave visível em
 * JSON.stringify(transporte) — caminho clássico para segredo em log.
 */
export class HttpApiTransport implements EmailTransport {
  readonly name: string;
  readonly #baseUrl: string;
  readonly #apiKey: string;
  readonly #from: string;
  readonly #fetchImpl: typeof fetch;

  constructor(
    name: string,
    baseUrl: string,
    apiKey: string,
    from: string,
    fetchImpl: typeof fetch = fetch
  ) {
    this.name = name;
    this.#baseUrl = baseUrl;
    this.#apiKey = apiKey;
    this.#from = from;
    this.#fetchImpl = fetchImpl;
  }

  /** Serialização segura: nunca inclui configuração. */
  toJSON(): { name: string } {
    return { name: this.name };
  }

  async send(message: EmailMessage): Promise<SendResult> {
    try {
      const res = await this.#fetchImpl(`${this.#baseUrl}/messages`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${this.#apiKey}`,
          "idempotency-key": message.idempotencyKey,
        },
        body: JSON.stringify({
          from: this.#from,
          to: message.to,
          template: message.templateKey,
          data: message.data,
        }),
      });
      if (!res.ok) {
        return {
          ok: false,
          provider: this.name,
          errorCode: `http_${res.status}`,
          // Somente o status; o corpo pode ecoar dados sensíveis.
          errorMessage: `falha no provedor (HTTP ${res.status})`,
        };
      }
      const body = (await res.json()) as { id?: string };
      return {
        ok: true,
        provider: this.name,
        providerMessageId: String(body.id ?? message.idempotencyKey),
      };
    } catch {
      return {
        ok: false,
        provider: this.name,
        errorCode: "network_error",
        errorMessage: "falha de comunicação com o provedor",
      };
    }
  }
}

export function createEmailTransport(
  env: Env,
  fetchImpl: typeof fetch = fetch
): EmailTransport {
  const status = inspectEmailConfig(env);
  if (!status.configured) return new FakeLocalTransport();
  return new HttpApiTransport(
    String(env.BDFLOW_EMAIL_PROVIDER),
    String(env.BDFLOW_EMAIL_API_BASE_URL),
    String(env.BDFLOW_EMAIL_API_KEY),
    String(env.BDFLOW_EMAIL_FROM),
    fetchImpl
  );
}

/**
 * Sanitiza qualquer texto destinado a log/erro persistido: remove segredos
 * conhecidos e valores de configuração antes de sair do processo.
 */
export function sanitizeForLog(text: string, secrets: Array<string | undefined>): string {
  let saida = text;
  for (const s of secrets) {
    if (typeof s === "string" && s.length >= 8) {
      saida = saida.split(s).join("[REDIGIDO]");
    }
  }
  return saida.slice(0, 2000);
}
