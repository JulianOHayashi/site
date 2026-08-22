/**
 * BLOCO 9 — Aprovação MANUAL de etapa e liberação de benefício (ciclo inicial).
 *
 * No primeiro ciclo o fundador/admin decide manualmente se o usuário cumpriu
 * a etapa correspondente e libera o benefício DAQUELA etapa. A decisão é
 * modelada com honestidade como aprovação administrativa manual — sessões,
 * documentos e evidências NÃO são forjados para satisfazer o sistema.
 *
 * Regras congeladas:
 *   - a liberação é específica de etapa/usuário/ciclo: aprovar farmácia
 *     libera SOMENTE o benefício de farmácia, nunca os sete;
 *   - idempotente: repetir a mesma aprovação não altera nada e não sobrescreve;
 *   - sem sobrescrita silenciosa de decisão anterior divergente;
 *   - toda decisão carrega ator, momento, motivo e a ORIGEM
 *     'initial_launch_manual';
 *   - a automação futura deve invocar a MESMA transição de domínio, trocando
 *     apenas a origem — sem substituir o schema.
 *
 * O ciclo de vida do entitlement (locked -> available -> ...) é autoridade do
 * App; este módulo descreve a transição de forma portável e testável.
 */
import type { BenefitType } from "./benefitTypes";

export const MANUAL_APPROVAL_POLICY_VERSION = 1;

export type EntitlementStatus =
  | "locked"
  | "available"
  | "validation_pending"
  | "used"
  | "cancelled";

export type DecisionSource =
  | "initial_launch_manual"
  | "automated_evidence_review";

export type Entitlement = {
  entitlementId: string;
  userId: string;
  cycleId: string;
  stage: number;
  benefitType: BenefitType;
  assignedAmountCents: number;
  status: EntitlementStatus;
};

export type StageApproval = {
  cycleId: string;
  userId: string;
  stage: number;
  approved: boolean;
  actorId: string;
  decidedAt: string;
  reason: string;
  source: DecisionSource;
};

export type ReleaseOutcome = {
  policyVersion: number;
  changed: Entitlement[];
  unchanged: Entitlement[];
  already: boolean;
  rejectedReason?: string;
};

export class ManualApprovalError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ManualApprovalError";
  }
}

/**
 * Aplica a aprovação de UMA etapa: apenas o entitlement daquele
 * usuário/ciclo/etapa passa de locked para available.
 */
export function applyStageApprovalRelease(
  entitlements: Entitlement[],
  approval: StageApproval
): ReleaseOutcome {
  if (!approval.approved) {
    return {
      policyVersion: MANUAL_APPROVAL_POLICY_VERSION,
      changed: [],
      unchanged: entitlements,
      already: false,
      rejectedReason: "etapa não aprovada: nenhum benefício é liberado",
    };
  }
  if (!approval.actorId || !approval.reason.trim()) {
    throw new ManualApprovalError("ator e motivo são obrigatórios");
  }

  const alvo = entitlements.filter(
    (e) =>
      e.userId === approval.userId &&
      e.cycleId === approval.cycleId &&
      e.stage === approval.stage
  );
  if (alvo.length === 0) {
    throw new ManualApprovalError("não há benefício para esta etapa/usuário");
  }

  const changed: Entitlement[] = [];
  const unchanged: Entitlement[] = [];
  let already = true;

  for (const e of entitlements) {
    const eAlvo = alvo.includes(e);
    if (!eAlvo) {
      unchanged.push(e);
      continue;
    }
    if (e.status === "locked") {
      changed.push({ ...e, status: "available" });
      already = false;
    } else {
      // Já liberado/consumido: NÃO sobrescreve silenciosamente.
      unchanged.push(e);
    }
  }

  return {
    policyVersion: MANUAL_APPROVAL_POLICY_VERSION,
    changed,
    unchanged,
    already,
  };
}

/** Somente estes campos são exibidos no cartão individual do benefício. */
export type BenefitCard = {
  amountCents: number;
  currency: "BRL";
  partnerNetworkBridgeId: string;
  benefitType: BenefitType;
  stage: number;
  status: EntitlementStatus;
  availableFrom: string | null;
};

/**
 * O App NÃO exibe saldo agregado de carteira: cada benefício é um cartão
 * individual. Esta função existe para tornar a regra testável.
 */
export function aggregateWalletBalance(): null {
  return null;
}
