/**
 * Convites de manager — lógica PURA.
 *
 * Regras vigentes (substituem regras anteriores conflitantes):
 *  • validade fixa de 48 HORAS CORRIDAS desde a criação (não 4 dias);
 *  • cada link é individual, aleatório, revogável e de USO ÚNICO,
 *    inclusive quando criado em lote;
 *  • e-mail do destinatário NÃO é obrigatório (o link pode ser enviado
 *    por WhatsApp ou qualquer outro canal);
 *  • o convite vincula à EMPRESA, nunca a uma filial permanente;
 *  • ABRIR o link não o consome: só o backend o marca como utilizado,
 *    atomicamente, ao concluir o cadastro do manager.
 */

import {
  INVITATION_TTL_HOURS,
  type CreateInvitationBatchInput,
  type InvitationVisualState,
  type ManagerInvitation,
} from "./types";

/** Expiração prevista = criação + 48h (usada só quando o backend não envia). */
export function expiresAtFromCreation(createdAtIso: string): string | null {
  const t = Date.parse(createdAtIso);
  if (Number.isNaN(t)) return null;
  return new Date(t + INVITATION_TTL_HOURS * 3600_000).toISOString();
}

/**
 * Estado visual do convite.
 *
 * Precedência: revogado > utilizado > expirado > não utilizado.
 * "Utilizado" nunca é sobrescrito por expiração — o histórico é preservado.
 * A expiração por tempo é derivada de `expiresAt` (autoridade do backend);
 * `agora` é injetado para não tratar o relógio do navegador como verdade
 * absoluta em testes e para permitir correção de skew no futuro.
 */
export function invitationVisualState(
  invitation: Pick<ManagerInvitation, "status" | "expiresAt">,
  agora: Date = new Date()
): InvitationVisualState {
  if (invitation.status === "revoked") return "revoked";
  if (invitation.status === "used") return "used";
  if (invitation.status === "expired") return "expired";

  if (invitation.expiresAt) {
    const exp = Date.parse(invitation.expiresAt);
    if (!Number.isNaN(exp) && exp <= agora.getTime()) return "expired";
  }
  return "not_used";
}

/** Horas inteiras restantes (nunca negativas). `null` sem `expiresAt`. */
export function hoursRemaining(
  expiresAt: string | null,
  agora: Date = new Date()
): number | null {
  if (!expiresAt) return null;
  const exp = Date.parse(expiresAt);
  if (Number.isNaN(exp)) return null;
  const ms = exp - agora.getTime();
  if (ms <= 0) return 0;
  return Math.floor(ms / 3600_000);
}

/** Rótulo PT-BR do estado do convite (texto exigido pela especificação). */
export function invitationStateLabel(
  invitation: Pick<ManagerInvitation, "status" | "expiresAt" | "usedAt">,
  agora: Date = new Date()
): string {
  const estado = invitationVisualState(invitation, agora);
  switch (estado) {
    case "revoked":
      return "Revogado";
    case "used":
      return "Utilizado";
    case "expired":
      return "Expirado — este convite não foi utilizado";
    case "not_used": {
      const h = hoursRemaining(invitation.expiresAt, agora);
      if (h === null) return "Não utilizado";
      if (h === 0) return "Não utilizado — expira em menos de 1 hora";
      return `Não utilizado — expira em ${h} ${h === 1 ? "hora" : "horas"}`;
    }
  }
}

/** Classe visual coerente com a paleta atual do Site. */
export function invitationStateTone(estado: InvitationVisualState): string {
  switch (estado) {
    case "not_used":
      return "bg-amarelo/25 text-tinta";
    case "used":
      return "bg-[#E8F7EE] text-[#0B7A3E]";
    case "expired":
      return "bg-papel2 text-tinta/60";
    case "revoked":
      return "bg-magenta/10 text-magenta";
  }
}

/** Convite pode ser revogado? Só quando ainda não utilizado nem revogado. */
export function canRevokeInvitation(
  invitation: Pick<ManagerInvitation, "status" | "expiresAt">,
  agora: Date = new Date()
): boolean {
  return invitationVisualState(invitation, agora) === "not_used";
}

/** Convite pode receber substituto? Quando expirado ou revogado. */
export function canReplaceInvitation(
  invitation: Pick<ManagerInvitation, "status" | "expiresAt">,
  agora: Date = new Date()
): boolean {
  const estado = invitationVisualState(invitation, agora);
  return estado === "expired" || estado === "revoked";
}

// ---------------------------------------------------------------------------
// Lote
// ---------------------------------------------------------------------------

export type BatchQuantityCheck =
  | { ok: true; quantity: number }
  | { ok: false; motivo: string };

/**
 * Valida que a quantidade é um inteiro POSITIVO e SEGURO.
 *
 * NÃO impõe teto de negócio (o limite real pertence ao backend). Rejeita
 * zero, negativos, decimais, infinito, NaN e inteiros inseguros
 * (> Number.MAX_SAFE_INTEGER), evitando travamento por overflow.
 */
export function validateBatchQuantity(raw: unknown): BatchQuantityCheck {
  const n =
    typeof raw === "number"
      ? raw
      : typeof raw === "string" && raw.trim() !== ""
        ? Number(raw)
        : Number.NaN;

  if (!Number.isSafeInteger(n)) {
    return { ok: false, motivo: "Informe um número inteiro válido de convites." };
  }
  if (n <= 0) {
    return { ok: false, motivo: "A quantidade deve ser maior que zero." };
  }
  return { ok: true, quantity: n };
}

/**
 * Nº de páginas de identificação, com PAGE_SIZE itens por página.
 * Proteção de RENDERIZAÇÃO (não é limite de lote).
 */
export const LABELS_PAGE_SIZE = 20;

export function labelPageCount(quantity: number): number {
  if (!Number.isSafeInteger(quantity) || quantity <= 0) return 0;
  return Math.ceil(quantity / LABELS_PAGE_SIZE);
}

/**
 * Posições (1-based) visíveis numa página, calculadas SOB DEMANDA — nunca
 * materializando um array do tamanho total do lote.
 */
export function labelPositionsForPage(
  quantity: number,
  page: number
): number[] {
  if (!Number.isSafeInteger(quantity) || quantity <= 0) return [];
  const inicio = (page - 1) * LABELS_PAGE_SIZE + 1;
  if (inicio > quantity) return [];
  const fim = Math.min(page * LABELS_PAGE_SIZE, quantity);
  const posicoes: number[] = [];
  for (let i = inicio; i <= fim; i++) posicoes.push(i);
  return posicoes;
}

/**
 * Monta o input de criação a partir de rótulos ESPARSOS (Map posição→texto),
 * enviando somente as posições efetivamente preenchidas. Nunca gera um array
 * do tamanho de `quantity`.
 */
export function buildBatchInput(
  quantity: number,
  sparseLabels: ReadonlyMap<number, string>
): CreateInvitationBatchInput {
  const labels: Array<{ position: number; label: string }> = [];
  for (const [position, label] of sparseLabels) {
    const texto = label.trim();
    if (texto && position >= 1 && position <= quantity) {
      labels.push({ position, label: texto });
    }
  }
  labels.sort((a, b) => a.position - b.position);
  return { quantity, labels };
}

/** Lista numerada para copiar todos os links logo após a geração. */
export function formatInvitationList(
  invitations: readonly ManagerInvitation[]
): string {
  return invitations
    .map((inv, i) => {
      const rotulo = inv.label ? ` (${inv.label})` : "";
      return `${i + 1}.${rotulo} ${inv.url ?? "[link indisponível]"}`;
    })
    .join("\n");
}
