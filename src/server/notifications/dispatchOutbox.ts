/**
 * R13 — Laço de despacho do outbox de E-MAIL, sobre a semântica CANÔNICA do M1.
 *
 * Usa exclusivamente as operações de serviço já existentes no M1:
 *   svc_mint_partner_application_token  -> segredo do onboarding
 *   svc_mint_manager_invite_token       -> segredo do convite (R4)
 *   svc_mark_notification_sent / _failed / svc_reschedule_notification
 *
 * A máquina de estados da baseline NÃO é redesenhada aqui: o worker apenas
 * invoca as transições que ela já permite.
 *
 * O segredo é cunhado NO DESPACHO, circula apenas em memória, entra no corpo
 * da mensagem e NUNCA vai para log, erro persistido ou fila.
 *
 * Este módulo é server-side e não é importado pelo bundle do navegador.
 */
import {
  sanitizeForLog,
  type EmailTransport,
  type EmailMessage,
} from "./emailProvider";

/** Resultado da cunhagem canônica (contrato jsonb {ok,...} do M1). */
export type MintOutcome =
  | {
      ok: true;
      token: string;
      recipient: string;
      purpose: string;
      attempt: number;
      expires_in_seconds: number;
    }
  | { ok: false; reason: string };

/** Evento pendente selecionado pelo worker. */
export type PendingNotification = {
  id: string;
  channel: string;
  template_key: string;
  template_data: Record<string, unknown>;
  recipient_address: string | null;
  idempotency_key: string;
};

/**
 * Porta para as RPCs canônicas. A implementação concreta (supabase-js com
 * service_role) vive fora deste módulo para mantê-lo testável.
 */
export interface CanonicalOutboxGateway {
  listPending(channel: string, limit: number): Promise<PendingNotification[]>;
  /** svc_mint_partner_application_token */
  mintApplicationToken(notificationId: string): Promise<MintOutcome>;
  /** svc_mint_manager_invite_token */
  mintManagerInviteToken(notificationId: string): Promise<MintOutcome>;
  /** svc_mark_notification_sent */
  markSent(
    notificationId: string,
    provider: string,
    providerMessageId: string
  ): Promise<void>;
  /** svc_mark_notification_failed */
  markFailed(
    notificationId: string,
    errorCode: string,
    errorMessage: string
  ): Promise<void>;
  /** svc_reschedule_notification (delay como intervalo em minutos) */
  reschedule(notificationId: string, delayMinutes: number): Promise<void>;
}

export type DispatchSummary = {
  processed: number;
  sent: number;
  failed: number;
  skipped: number;
};

/** Espera exponencial: 1, 2, 4... até 60 minutos. */
export function retryDelayMinutes(attempt: number): number {
  return Math.min(60, 2 ** Math.max(0, attempt - 1));
}

/**
 * Templates que exigem segredo cunhado no despacho, e por qual operação
 * canônica. Template desconhecido NÃO recebe segredo.
 */
const MINT_POR_TEMPLATE: Record<string, "application" | "manager_invite"> = {
  partner_application_email_verification: "application",
  partner_application_account_claim: "application",
  manager_invite: "manager_invite",
};

export async function dispatchPending(
  gateway: CanonicalOutboxGateway,
  transport: EmailTransport,
  options: { channel?: string; max?: number } = {}
): Promise<DispatchSummary> {
  const channel = options.channel ?? "email";
  const max = options.max ?? 25;
  const resumo: DispatchSummary = { processed: 0, sent: 0, failed: 0, skipped: 0 };

  const pendentes = await gateway.listPending(channel, max);

  for (const evento of pendentes) {
    resumo.processed++;
    let segredo: string | undefined;
    let tentativa = 1;

    const tipoMint = MINT_POR_TEMPLATE[evento.template_key];
    if (tipoMint) {
      const mint =
        tipoMint === "application"
          ? await gateway.mintApplicationToken(evento.id)
          : await gateway.mintManagerInviteToken(evento.id);

      if (!mint.ok) {
        // lease_held, not_due_yet, stale_for_state, max_attempts,
        // not_dispatchable: o M1 já decidiu; o worker não insiste.
        resumo.skipped++;
        continue;
      }
      segredo = mint.token;
      tentativa = mint.attempt;
    }

    const mensagem: EmailMessage = {
      to: evento.recipient_address ?? "",
      templateKey: evento.template_key,
      data: {
        ...evento.template_data,
        // O segredo entra APENAS no corpo enviado.
        ...(segredo ? { token: segredo } : {}),
      },
      idempotencyKey: evento.idempotency_key,
    };

    const resultado = await transport.send(mensagem);
    if (resultado.ok) {
      await gateway.markSent(
        evento.id,
        resultado.provider,
        resultado.providerMessageId
      );
      resumo.sent++;
    } else {
      // Nunca deixa segredo vazar para a coluna de erro.
      await gateway.markFailed(
        evento.id,
        resultado.errorCode,
        sanitizeForLog(resultado.errorMessage, [segredo])
      );
      await gateway.reschedule(evento.id, retryDelayMinutes(tentativa));
      resumo.failed++;
    }
  }

  return resumo;
}
