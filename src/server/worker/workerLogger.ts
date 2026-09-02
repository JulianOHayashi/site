/**
 * R16 — LOGGING ESTRUTURADO COM REDAÇÃO.
 *
 * A redação aqui não é cosmética. O worker manipula segredo cunhado, chave de
 * service_role e senha SMTP; um log descuidado os leva para onde ninguém mais
 * controla — arquivo, agregador, ticket de suporte.
 *
 * DESENHO: ALLOWLIST, NÃO BLOCKLIST.
 * Só campos explicitamente permitidos são emitidos. Uma blocklist falharia no
 * primeiro campo novo que alguém acrescentasse.
 */

export type NivelLog = "info" | "warn" | "error";

/** Campos operacionais seguros. Nenhum deles carrega segredo ou corpo. */
export type EventoLog = {
  event: string;
  notification_id?: string;
  template_key?: string;
  outcome?: string;
  attempt?: number;
  duration_ms?: number;
  provider?: string;
  /** Presença do id do provedor, não o valor, quando ele puder ser sensível. */
  has_provider_message_id?: boolean;
  recipient_fingerprint?: string;
  error_code?: string;
  count?: number;
};

const CAMPOS_PERMITIDOS: ReadonlySet<string> = new Set([
  "event",
  "notification_id",
  "template_key",
  "outcome",
  "attempt",
  "duration_ms",
  "provider",
  "has_provider_message_id",
  "recipient_fingerprint",
  "error_code",
  "count",
]);

/**
 * Impressão digital não reversível do destinatário, para correlacionar sem
 * registrar o endereço. Usa apenas o domínio e um resumo curto do local part.
 */
export function fingerprintDestinatario(endereco: string): string {
  const at = endereco.lastIndexOf("@");
  if (at <= 0) return "invalid";
  const dominio = endereco.slice(at + 1).toLowerCase();
  const local = endereco.slice(0, at);
  let h = 0;
  for (let i = 0; i < local.length; i++) {
    h = (h * 31 + local.charCodeAt(i)) >>> 0;
  }
  return `${h.toString(16).padStart(8, "0")}@${dominio}`;
}

export type Sink = (linha: string) => void;

/**
 * Cria o logger. `segredos` são valores conhecidos que devem ser mascarados
 * caso escapem para dentro de uma string — segunda barreira, depois da
 * allowlist.
 */
export function criarWorkerLogger(
  sink: Sink = (l) => console.log(l),
  segredos: Array<string | undefined> = []
) {
  const conhecidos = segredos.filter(
    (s): s is string => typeof s === "string" && s.length >= 8
  );

  const mascarar = (texto: string): string => {
    let saida = texto;
    for (const s of conhecidos) saida = saida.split(s).join("[REDIGIDO]");
    return saida;
  };

  const emitir = (nivel: NivelLog, evento: EventoLog): void => {
    const seguro: Record<string, unknown> = { level: nivel, ts: new Date().toISOString() };
    for (const [k, v] of Object.entries(evento)) {
      // Allowlist: campo desconhecido é DESCARTADO, não sanitizado.
      if (!CAMPOS_PERMITIDOS.has(k)) continue;
      if (v === undefined) continue;
      seguro[k] = typeof v === "string" ? mascarar(v).slice(0, 300) : v;
    }
    sink(JSON.stringify(seguro));
  };

  return {
    info: (e: EventoLog) => emitir("info", e),
    warn: (e: EventoLog) => emitir("warn", e),
    error: (e: EventoLog) => emitir("error", e),

    /**
     * Converte uma exceção em campos seguros. NÃO registra a mensagem crua
     * nem o stack: ambos podem conter credencial, corpo de e-mail ou o
     * segredo cunhado, dependendo de onde a exceção nasceu.
     */
    erroSeguro(e: unknown): { error_code: string } {
      if (e && typeof e === "object" && "code" in e && typeof e.code === "string") {
        return { error_code: mascarar(e.code).slice(0, 100) };
      }
      if (e instanceof Error) return { error_code: e.name };
      return { error_code: "unknown_error" };
    },
  };
}

export type WorkerLogger = ReturnType<typeof criarWorkerLogger>;
