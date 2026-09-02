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
  "error_code",
  "count",
]);

/**
 * SEM IMPRESSÃO DIGITAL DE DESTINATÁRIO.
 *
 * Uma versão anterior deste arquivo emitia `recipient_fingerprint`, calculado
 * por um hash polinomial de 32 bits sobre o local part, com o domínio em
 * TEXTO CLARO — e o comentário chamava isso de "não reversível". A afirmação
 * era falsa: 32 bits são triviais de colidir e forçar, endereços de e-mail
 * têm entropia baixa, e o domínio já vazava sozinho.
 *
 * Como o despachante e o runtime não precisam correlacionar eventos por
 * destinatário, o campo foi REMOVIDO em vez de fortalecido. Menos dado
 * pessoal em log é melhor que dado pessoal ofuscado.
 *
 * Se um dia houver necessidade operacional comprovada, a construção correta é
 * HMAC-SHA-256 com chave dedicada de correlação, server-only — nunca
 * SHA-256(email) puro, MD5, SHA-1 ou hash não criptográfico, todos sujeitos a
 * ataque de dicionário sobre endereços previsíveis.
 *
 *   R16_RECIPIENT_FINGERPRINT_POLICY=OMITTED_UNLESS_REQUIRED
 */

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
