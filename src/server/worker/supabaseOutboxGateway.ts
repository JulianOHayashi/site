import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CanonicalOutboxGateway,
  PendingNotification,
  MintOutcome,
} from "../notifications/dispatchOutbox";
import { R16_SUPPORTED_TEMPLATE_KEYS } from "../notifications/supportedTemplates";

/**
 * R16 — GATEWAY CONCRETO SOBRE O SUPABASE.
 *
 * DESCOBERTA NÃO É AUTORIZAÇÃO
 * `listPending` apenas encontra candidatos. Uma linha devolvida aqui NÃO
 * autoriza transmissão. A sequência obrigatória é
 *
 *     descobrir → svc_mint_* (claim atômico) → posse concedida → send
 *
 * Este arquivo simplesmente não oferece caminho alternativo.
 *
 * DESCOBERTA EM DUAS FASES
 *   FASE A — trabalho normal: `pending` e `scheduled` já vencido.
 *   FASE B — sondagem de recuperação: número LIMITADO de linhas em `sending`,
 *            para que um worker morto não deixe evento órfão para sempre.
 *
 * A fase B NÃO decide se o lease expirou. Isso é autoridade da RPC, que
 * conhece `m1_mint_lease()`. O worker apenas garante que a linha abandonada
 * volte a ser apresentada a essa autoridade:
 *
 *     sending + lease vivo    → RPC devolve lease_held → NÃO envia
 *     sending + lease vencido → RPC recupera e concede posse → PODE enviar
 *
 * Nenhuma duração de lease é replicada aqui.
 *
 * TETO DE TENTATIVAS — AUTORIDADE EXCLUSIVA DO BANCO
 * A consulta NÃO filtra por `attempt_count`. Uma versão anterior espelhava
 * `m1_mint_max_tentativas()` como constante em TypeScript, criando risco de
 * deriva: se o teto canônico subisse para 6, o filtro em 5 esconderia do
 * worker um evento ainda despachável, e ele ficaria órfão. Agora o candidato
 * é descoberto e a RPC decide — `max_attempts` faz a transição canônica para
 * `failed` sem envio.
 *
 *     R16_MAX_ATTEMPTS_AUTHORITY=DATABASE_RPC_ONLY
 *
 * SEM MÁQUINA DE ESTADOS PARALELA
 * Nenhum `UPDATE` direto em `notification_events`. Toda transição — posse,
 * enviado, falha, reagendamento — passa pelas RPCs canônicas `svc_*`,
 * governadas pelo trigger `notification_events_protect`.
 *
 * CREDENCIAL
 * O cliente aqui é criado com `service_role` e existe apenas no processo do
 * worker. A chave nunca entra em `VITE_`, `NEXT_PUBLIC_`, código de
 * navegador, bundle, log ou erro serializado.
 */

/** Colunas estritamente necessárias ao worker. Nada além disso é carregado. */
const COLUNAS_NECESSARIAS =
  "id,channel,template_key,template_data,recipient_address,idempotency_key" as const;

/**
 * Linha crua da descoberta, antes da validação. Deliberadamente NÃO inclui
 * `recipient_user_id`, `error_message`, `provider_message_id` nem
 * `correlation_*`: nada disso é necessário para enviar, e carregá-los traria
 * PII e resíduo sensível para a memória e os logs do worker.
 */
type LinhaBruta = {
  id: unknown;
  channel: unknown;
  template_key: unknown;
  template_data: unknown;
  recipient_address: unknown;
  idempotency_key: unknown;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Rejeita CR, LF e NUL — vetores de injeção de cabeçalho SMTP. */
function semControleDeLinha(valor: string): boolean {
  return !/[\r\n\0]/.test(valor);
}

function textoNaoVazio(v: unknown, max: number): v is string {
  return typeof v === "string" && v.trim().length > 0 && v.length <= max;
}

/**
 * Valida a linha ANTES de ela entrar no caminho de claim/envio.
 *
 * Fail-closed: dado malformado vindo do banco não vira e-mail. Devolve `null`
 * em vez de lançar, para que uma linha ruim não derrube o lote inteiro —
 * o chamador contabiliza e segue. Nada é convertido em string, nenhum
 * destinatário é inventado, nenhum padrão é assumido.
 */
export function validarLinha(linha: LinhaBruta): PendingNotification | null {
  if (!textoNaoVazio(linha.id, 64) || !UUID_RE.test(linha.id)) return null;
  if (linha.channel !== "email") return null;

  if (!textoNaoVazio(linha.template_key, 200)) return null;
  if (!semControleDeLinha(linha.template_key)) return null;
  // Segunda barreira: a consulta já filtra, mas não confiamos que a resposta
  // corresponda ao filtro pedido.
  if (!R16_SUPPORTED_TEMPLATE_KEYS.includes(linha.template_key)) return null;

  // Canal email exige endereço. Sem endereço válido, não há envio possível.
  if (!textoNaoVazio(linha.recipient_address, 320)) return null;
  if (!semControleDeLinha(linha.recipient_address)) return null;
  if (!linha.recipient_address.includes("@")) return null;

  if (!textoNaoVazio(linha.idempotency_key, 200)) return null;

  if (
    typeof linha.template_data !== "object" ||
    linha.template_data === null ||
    Array.isArray(linha.template_data)
  ) {
    return null;
  }

  return {
    id: linha.id,
    channel: "email",
    template_key: linha.template_key,
    template_data: linha.template_data as Record<string, unknown>,
    recipient_address: linha.recipient_address,
    idempotency_key: linha.idempotency_key,
  };
}

/** Reserva de recuperação padrão: uma vaga por consulta. */
export const RECOVERY_RESERVE_PADRAO = 1;

/** Lote mínimo. Abaixo disso não há como reservar as duas classes. */
export const BATCH_SIZE_MINIMO = 2;

/**
 * Erro de configuração do worker. A mensagem é sanitizada por construção:
 * carrega apenas nome de parâmetro e limite, nunca credencial ou dado.
 */
export class WorkerConfigError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "WorkerConfigError";
    this.code = code;
  }
}

export type CapacidadeDescoberta = {
  /** Vagas reservadas à sondagem de recuperação em CADA consulta. */
  recoveryReserve: number;
};

/**
 * Divide o lote entre trabalho normal e sondagem de recuperação.
 *
 * POR QUE NÃO HÁ ALTERNÂNCIA EM MEMÓRIA
 * Uma versão anterior alternava as classes por contador de ciclo quando
 * `batchSize = 1`. Isso tornava a liveness dependente do tempo de vida do
 * processo: um restart zeraria o contador e a garantia passaria a depender do
 * histórico do worker.
 *
 * A garantia agora é ESTRUTURAL. Com `batchSize >= 2` e
 * `1 <= recoveryReserve < batchSize`, toda consulta reserva capacidade para
 * as duas classes:
 *
 *     normalCapacity   = batchSize - recoveryReserve   >= 1
 *     recoveryCapacity = recoveryReserve               >= 1
 *
 * Nenhuma classe pode ser permanentemente privada pela outra, em qualquer
 * consulta, independentemente de reinícios.
 *
 * Valores inválidos são REJEITADOS, nunca normalizados: coagir 1 para 2
 * esconderia configuração errada em produção.
 */
export function dividirCapacidade(
  batchSize: number,
  recoveryReserve: number = RECOVERY_RESERVE_PADRAO
): { normal: number; recovery: number } {
  if (!Number.isInteger(batchSize)) {
    throw new WorkerConfigError("invalid_batch_size", "batchSize deve ser inteiro");
  }
  if (batchSize < BATCH_SIZE_MINIMO) {
    throw new WorkerConfigError(
      "batch_size_below_minimum",
      `batchSize deve ser >= ${BATCH_SIZE_MINIMO}`
    );
  }
  if (!Number.isInteger(recoveryReserve)) {
    throw new WorkerConfigError(
      "invalid_recovery_reserve",
      "recoveryReserve deve ser inteiro"
    );
  }
  if (recoveryReserve < 1) {
    throw new WorkerConfigError(
      "recovery_reserve_below_minimum",
      "recoveryReserve deve ser >= 1"
    );
  }
  if (recoveryReserve >= batchSize) {
    throw new WorkerConfigError(
      "recovery_reserve_exceeds_batch",
      "recoveryReserve deve ser < batchSize"
    );
  }
  return { normal: batchSize - recoveryReserve, recovery: recoveryReserve };
}

export type GatewayObservador = {
  onLinhaInvalida?: (info: { id: string | null; motivo: string }) => void;
};

export function createSupabaseOutboxGateway(
  client: SupabaseClient,
  observador: GatewayObservador = {},
  capacidade: CapacidadeDescoberta = { recoveryReserve: RECOVERY_RESERVE_PADRAO }
): CanonicalOutboxGateway {
  /** Mapeia e valida um conjunto de linhas cruas. */
  const mapear = (linhas: LinhaBruta[]): PendingNotification[] => {
    const validas: PendingNotification[] = [];
    for (const l of linhas) {
      const ok = validarLinha(l);
      if (ok) validas.push(ok);
      else {
        observador.onLinhaInvalida?.({
          id: typeof l?.id === "string" ? l.id : null,
          motivo: "malformed_row_rejected",
        });
      }
    }
    return validas;
  };

  return {
    async listPending(channel: string, limit: number): Promise<PendingNotification[]> {
      // Lança WorkerConfigError se o lote ou a reserva forem inválidos.
      // Falha rápido, sem coerção silenciosa.
      const { normal, recovery } = dividirCapacidade(limit, capacidade.recoveryReserve);
      const agora = new Date().toISOString();

      // ---------------------------------------------------------------
      // FASE A — TRABALHO NORMAL
      //   pending, ou scheduled cujo scheduled_for já venceu.
      //   Exclui: scheduled futuro, sending, sent, delivered, read, failed,
      //   cancelled e todo template não suportado.
      //   Sem filtro de attempt_count: o teto é autoridade da RPC.
      // ---------------------------------------------------------------
      const faseA = await client
        .from("notification_events")
        .select(COLUNAS_NECESSARIAS)
        .eq("channel", channel)
        .in("template_key", [...R16_SUPPORTED_TEMPLATE_KEYS])
        .or(`status.eq.pending,and(status.eq.scheduled,scheduled_for.lte.${agora})`)
        .order("created_at", { ascending: true })
        .order("id", { ascending: true })
        .limit(normal);

      if (faseA.error) {
        // Erro de descoberta não é erro de entrega: nada é enviado nem mutado.
        throw new Error(`outbox_discovery_failed:${faseA.error.code ?? "unknown"}`);
      }
      const normais = mapear((faseA.data ?? []) as unknown as LinhaBruta[]);

      // ---------------------------------------------------------------
      // FASE B — SONDAGEM DE RECUPERAÇÃO
      //   Linhas em `sending`, ordenadas pela transição de estado mais
      //   antiga. `updated_at` é escrito pelo próprio svc_mint_* ao tomar
      //   posse, e é a coluna que a RPC usa para avaliar o lease — por isso
      //   é a prioridade correta. Aqui ela serve APENAS para ordenar; a
      //   expiração continua sendo decidida pela RPC.
      // ---------------------------------------------------------------
      const faseB = await client
        .from("notification_events")
        .select(COLUNAS_NECESSARIAS)
        .eq("channel", channel)
        .in("template_key", [...R16_SUPPORTED_TEMPLATE_KEYS])
        .eq("status", "sending")
        .order("updated_at", { ascending: true })
        .order("id", { ascending: true })
        .limit(recovery);

      if (faseB.error) {
        throw new Error(`outbox_recovery_discovery_failed:${faseB.error.code ?? "unknown"}`);
      }
      const sondagens = mapear((faseB.data ?? []) as unknown as LinhaBruta[]);

      // Trabalho normal primeiro: a sondagem não atrasa a fila corrente.
      return [...normais, ...sondagens];
    },

    /** POSSE. RPC canônica; nenhum UPDATE direto. */
    async mintApplicationToken(notificationId: string): Promise<MintOutcome> {
      return chamarMint(client, "svc_mint_partner_application_token", notificationId);
    },

    async mintManagerInviteToken(notificationId: string): Promise<MintOutcome> {
      return chamarMint(client, "svc_mint_manager_invite_token", notificationId);
    },

    async markSent(notificationId: string, provider: string, providerMessageId: string) {
      const { error } = await client.rpc("svc_mark_notification_sent", {
        p_notification_id: notificationId,
        p_provider: provider,
        p_provider_message_id: providerMessageId,
      });
      if (error) throw new Error(`mark_sent_failed:${error.code ?? "unknown"}`);
    },

    async markFailed(notificationId: string, errorCode: string, errorMessage: string) {
      const { error } = await client.rpc("svc_mark_notification_failed", {
        p_notification_id: notificationId,
        p_error_code: errorCode,
        p_error_message: errorMessage,
      });
      if (error) throw new Error(`mark_failed_failed:${error.code ?? "unknown"}`);
    },

    async reschedule(notificationId: string, delayMinutes: number) {
      const { error } = await client.rpc("svc_reschedule_notification", {
        p_notification_id: notificationId,
        p_delay: `${delayMinutes} minutes`,
      });
      if (error) throw new Error(`reschedule_failed:${error.code ?? "unknown"}`);
    },
  };
}

/**
 * Traduz a resposta da RPC de cunhagem para `MintOutcome`.
 *
 * `{ok:false, reason}` são recusas legítimas — `lease_held`, `not_due_yet`,
 * `max_attempts`, `stale_for_state`, `not_dispatchable`. Não são erro de
 * transporte: são a decisão canônica, respeitada sem insistência. Erro de
 * rede/PostgREST vira `rpc_error`, também sem envio.
 */
async function chamarMint(
  client: SupabaseClient,
  rpc: string,
  notificationId: string
): Promise<MintOutcome> {
  const { data, error } = await client.rpc(rpc, { p_notification_id: notificationId });

  if (error) return { ok: false, reason: "rpc_error" };
  if (!data || typeof data !== "object") return { ok: false, reason: "rpc_error" };

  const r = data as Record<string, unknown>;
  if (r.ok !== true) {
    return { ok: false, reason: typeof r.reason === "string" ? r.reason : "not_dispatchable" };
  }
  if (typeof r.token !== "string" || r.token.length === 0) {
    return { ok: false, reason: "rpc_error" };
  }
  return {
    ok: true,
    token: r.token,
    recipient: typeof r.recipient === "string" ? r.recipient : "",
    purpose: typeof r.purpose === "string" ? r.purpose : "",
    attempt: typeof r.attempt === "number" ? r.attempt : 1,
    expires_in_seconds:
      typeof r.expires_in_seconds === "number" ? r.expires_in_seconds : 0,
  };
}
