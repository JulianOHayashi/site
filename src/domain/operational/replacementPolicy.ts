/**
 * BLOCO 7 (parte 1) — Substituição de pessoas dentro do ciclo de 28 dias.
 *
 * Grupos e cronograma são FIXOS. Pessoas podem ser substituídas: a vaga
 * (grupo + número da vaga) permanece; a agenda NÃO é recalculada.
 *
 * Usuário que sai:
 *   - conserva o histórico já cumprido e os benefícios efetivamente liberados;
 *   - participações/benefícios FUTUROS ainda não conquistados são cancelados;
 *   - nada é apagado; continua elegível a ciclos futuros (salvo bloqueio
 *     específico por fraude/regra futura, fora deste escopo).
 *
 * Usuário que entra:
 *   - ocupa a MESMA vaga;
 *   - entra somente nas etapas AINDA NÃO INICIADAS;
 *   - não herda horas, documentos, conclusão de etapa nem benefícios;
 *   - não recebe retroativamente etapas passadas.
 *
 * Se a substituição ocorre durante uma etapa já iniciada, o novo usuário
 * começa na PRÓXIMA etapa elegível.
 *
 * O histórico de ocupação da vaga é APPEND-ONLY: cada atribuição é um
 * registro novo; só existe um ocupante corrente por vaga.
 */
import type { BenefitType } from "./benefitTypes";
import { futureBenefitsForGroup, type ScheduleMatrix } from "./schedulePolicy";

export const REPLACEMENT_POLICY_VERSION = 1;

export type SlotAssignment = {
  assignmentId: string;
  group: number;
  slot: number;
  userId: string;
  /** Primeira etapa (1-indexada) em que este ocupante participa. */
  fromStage: number;
  /** Etapa em que deixou a vaga; null enquanto for o ocupante corrente. */
  releasedAtStage: number | null;
  status: "current" | "replaced";
};

export type StageOutcome = {
  stage: number;
  /** Etapa concluída e aprovada -> benefício conquistado. */
  approved: boolean;
  /** Benefício efetivamente liberado (disponível/usado) para o usuário. */
  benefitReleased: boolean;
};

export type ReplacementInput = {
  matrix: ScheduleMatrix;
  assignment: SlotAssignment;
  /** Etapa de calendário corrente (1-indexada). */
  currentStage: number;
  /** A etapa corrente já começou? Se sim, o novo entra na seguinte. */
  currentStageStarted: boolean;
  outgoingOutcomes: StageOutcome[];
  incomingUserId: string;
  newAssignmentId: string;
};

export type ReplacementPlan = {
  policyVersion: number;
  outgoing: {
    userId: string;
    /** Etapas mantidas no histórico (nunca apagadas). */
    retainedStages: number[];
    /** Benefícios mantidos por terem sido efetivamente conquistados. */
    retainedBenefits: Array<{ stage: number; benefit: BenefitType }>;
    /** Participações/benefícios futuros cancelados. */
    cancelledFutureStages: Array<{ stage: number; benefit: BenefitType }>;
    /** Continua elegível a ciclos futuros. */
    eligibleForFutureCycles: boolean;
    assignmentStatus: "replaced";
    releasedAtStage: number;
  };
  incoming: {
    userId: string;
    group: number;
    slot: number;
    fromStage: number;
    grantedStages: Array<{ stage: number; benefit: BenefitType }>;
    inheritsHours: false;
    inheritsDocuments: false;
    inheritsStageCompletion: false;
    inheritsBenefits: false;
  };
};

export function planReplacement(input: ReplacementInput): ReplacementPlan {
  const {
    matrix,
    assignment,
    currentStage,
    currentStageStarted,
    outgoingOutcomes,
    incomingUserId,
  } = input;

  if (assignment.status !== "current") {
    throw new Error("apenas o ocupante corrente pode ser substituído");
  }

  // Etapa já iniciada -> o novo usuário começa na PRÓXIMA não iniciada.
  const primeiraEtapaDoNovo = currentStageStarted ? currentStage + 1 : currentStage;

  const agenda = futureBenefitsForGroup(matrix, assignment.group, 1);
  const porEtapa = new Map(agenda.map((x) => [x.stage, x.benefit]));
  const resultado = new Map(outgoingOutcomes.map((o) => [o.stage, o]));

  const retainedStages: number[] = [];
  const retainedBenefits: Array<{ stage: number; benefit: BenefitType }> = [];
  const cancelledFutureStages: Array<{ stage: number; benefit: BenefitType }> = [];

  for (const { stage, benefit } of agenda) {
    const o = resultado.get(stage);
    // Conquistado: mantém no histórico do usuário que sai.
    if (o?.approved) {
      retainedStages.push(stage);
      if (o.benefitReleased) retainedBenefits.push({ stage, benefit });
      continue;
    }
    // Futuro não conquistado: cancelado (sem apagar histórico).
    if (stage >= primeiraEtapaDoNovo) {
      cancelledFutureStages.push({ stage, benefit });
    } else if (o) {
      // Etapa passada não aprovada permanece registrada como histórico.
      retainedStages.push(stage);
    }
  }

  const grantedStages = futureBenefitsForGroup(
    matrix,
    assignment.group,
    primeiraEtapaDoNovo
  );

  return {
    policyVersion: REPLACEMENT_POLICY_VERSION,
    outgoing: {
      userId: assignment.userId,
      retainedStages,
      retainedBenefits,
      cancelledFutureStages,
      eligibleForFutureCycles: true,
      assignmentStatus: "replaced",
      releasedAtStage: primeiraEtapaDoNovo,
    },
    incoming: {
      userId: incomingUserId,
      group: assignment.group,
      slot: assignment.slot,
      fromStage: primeiraEtapaDoNovo,
      grantedStages,
      inheritsHours: false,
      inheritsDocuments: false,
      inheritsStageCompletion: false,
      inheritsBenefits: false,
    },
  };
}

/** Só pode haver UM ocupante corrente por vaga (histórico append-only). */
export function slotHistoryIsValid(history: SlotAssignment[]): boolean {
  const correntes = history.filter((h) => h.status === "current");
  if (correntes.length > 1) return false;
  const mesmaVaga = history.every(
    (h) => h.group === history[0].group && h.slot === history[0].slot
  );
  return mesmaVaga;
}
