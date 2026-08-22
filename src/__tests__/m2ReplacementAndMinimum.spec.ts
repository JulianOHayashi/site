/**
 * BLOCO 7 — Provas da substituição (testes 32-37) e do mínimo contratual
 * por etapa correspondente (testes 38-44).
 */
import { describe, test, expect } from "vitest";
import {
  planReplacement,
  slotHistoryIsValid,
  type SlotAssignment,
  type StageOutcome,
} from "../domain/operational/replacementPolicy";
import {
  evaluateStage,
  evaluateAllStages,
  userPenaltyFromStageBreach,
  STAGE_MINIMUM_POLICY_V1,
} from "../domain/operational/stageMinimumPolicy";
import {
  CANONICAL_SCHEDULE_V1,
  scheduleForGroup,
} from "../domain/operational/schedulePolicy";

const M = CANONICAL_SCHEDULE_V1;

// Vaga 07 do grupo 3, ocupada desde a etapa 1 pelo usuário A.
const vaga: SlotAssignment = {
  assignmentId: "atrib-1",
  group: 3,
  slot: 7,
  userId: "usuario-A",
  fromStage: 1,
  releasedAtStage: null,
  status: "current",
};

// A cumpriu e recebeu as etapas 1 e 2; a etapa 3 está em andamento.
const resultadosA: StageOutcome[] = [
  { stage: 1, approved: true, benefitReleased: true },
  { stage: 2, approved: true, benefitReleased: true },
];

describe("substituição no meio do ciclo de 28 dias", () => {
  const plano = planReplacement({
    matrix: M,
    assignment: vaga,
    currentStage: 3,
    currentStageStarted: true,
    outgoingOutcomes: resultadosA,
    incomingUserId: "usuario-B",
    newAssignmentId: "atrib-2",
  });

  test("T32 usuário que sai conserva o histórico cumprido", () => {
    expect(plano.outgoing.retainedStages).toContain(1);
    expect(plano.outgoing.retainedStages).toContain(2);
    expect(plano.outgoing.retainedBenefits.map((b) => b.stage)).toEqual([1, 2]);
  });
  test("T33 futuros não conquistados são cancelados (sem apagar histórico)", () => {
    expect(plano.outgoing.cancelledFutureStages.map((c) => c.stage)).toEqual([
      4, 5, 6, 7,
    ]);
    // A etapa 3, em andamento e não aprovada, não é concedida ao novo usuário
    // nem sai do histórico do que saiu.
    expect(plano.incoming.grantedStages.map((g) => g.stage)).not.toContain(3);
  });
  test("T34 usuário que entra NÃO recebe nenhuma etapa passada", () => {
    expect(plano.incoming.fromStage).toBe(4);
    expect(plano.incoming.grantedStages.map((g) => g.stage)).toEqual([4, 5, 6, 7]);
    for (const g of plano.incoming.grantedStages) {
      expect(g.stage).toBeGreaterThanOrEqual(plano.incoming.fromStage);
    }
  });
  test("T35 usuário que entra não herda benefícios do que saiu", () => {
    expect(plano.incoming.inheritsBenefits).toBe(false);
    expect(plano.incoming.inheritsHours).toBe(false);
    expect(plano.incoming.inheritsDocuments).toBe(false);
    expect(plano.incoming.inheritsStageCompletion).toBe(false);
    const recebidasPeloNovo = new Set(
      plano.incoming.grantedStages.map((g) => g.stage)
    );
    for (const b of plano.outgoing.retainedBenefits) {
      expect(recebidasPeloNovo.has(b.stage)).toBe(false);
    }
  });
  test("T36 a vaga tem histórico, mas só um ocupante corrente", () => {
    const historico: SlotAssignment[] = [
      { ...vaga, status: "replaced", releasedAtStage: 4 },
      {
        assignmentId: "atrib-2",
        group: 3,
        slot: 7,
        userId: "usuario-B",
        fromStage: 4,
        releasedAtStage: null,
        status: "current",
      },
    ];
    expect(slotHistoryIsValid(historico)).toBe(true);
    expect(historico.filter((h) => h.status === "current")).toHaveLength(1);
    // Dois ocupantes correntes é inválido.
    expect(
      slotHistoryIsValid([
        { ...historico[0], status: "current" },
        historico[1],
      ])
    ).toBe(false);
  });
  test("T37 quem saiu segue elegível a ciclos futuros", () => {
    expect(plano.outgoing.eligibleForFutureCycles).toBe(true);
  });
  test("o cronograma do grupo NÃO é recalculado", () => {
    const agendaAntes = scheduleForGroup(M, 3);
    const agendaDepois = scheduleForGroup(M, 3);
    expect(agendaDepois).toEqual(agendaAntes);
    // O novo ocupante segue exatamente a agenda fixa da vaga.
    for (const g of plano.incoming.grantedStages) {
      expect(g.benefit).toBe(agendaAntes[g.stage - 1]);
    }
  });
  test("substituição antes de a etapa começar inclui a própria etapa", () => {
    const p = planReplacement({
      matrix: M,
      assignment: vaga,
      currentStage: 3,
      currentStageStarted: false,
      outgoingOutcomes: resultadosA,
      incomingUserId: "usuario-C",
      newAssignmentId: "atrib-3",
    });
    expect(p.incoming.fromStage).toBe(3);
    expect(p.incoming.grantedStages.map((g) => g.stage)).toEqual([3, 4, 5, 6, 7]);
  });
  test("só o ocupante corrente pode ser substituído", () => {
    expect(() =>
      planReplacement({
        matrix: M,
        assignment: { ...vaga, status: "replaced" },
        currentStage: 3,
        currentStageStarted: true,
        outgoingOutcomes: [],
        incomingUserId: "usuario-D",
        newAssignmentId: "atrib-4",
      })
    ).toThrow();
  });
});

describe("mínimo contratual por etapa correspondente", () => {
  const comum = (n: number, stage = 2) =>
    evaluateStage({ stage, benefitType: "pharmacy", approvedCount: n });
  const superm = (n: number, stage = 1) =>
    evaluateStage({ stage, benefitType: "supermarket_stage_1", approvedCount: n });

  test("T38 nicho comum com 12 aprovados = PASS", () => {
    expect(comum(12).result).toBe("pass");
    expect(comum(12).nominalTarget).toBe(12);
  });
  test("T39 nicho comum com 10 aprovados = PASS (piso)", () => {
    expect(comum(10).result).toBe("pass");
    expect(comum(10).contractualMinimum).toBe(10);
  });
  test("T40 nicho comum com 9 aprovados = ABAIXO DO MÍNIMO", () => {
    expect(comum(9).result).toBe("below_minimum");
  });
  test("T41 supermercado com 24 aprovados = PASS", () => {
    expect(superm(24).result).toBe("pass");
    expect(superm(24).nominalTarget).toBe(24);
  });
  test("T42 supermercado com 20 aprovados = PASS (piso)", () => {
    expect(superm(20).result).toBe("pass");
    expect(superm(20).contractualMinimum).toBe(20);
  });
  test("T43 supermercado com 19 aprovados = ABAIXO DO MÍNIMO", () => {
    expect(superm(19).result).toBe("below_minimum");
  });
  test("T44 uma etapa NÃO compensa outra", () => {
    const r = evaluateAllStages([
      { stage: 2, benefitType: "pharmacy", approvedCount: 9 },
      { stage: 5, benefitType: "pharmacy", approvedCount: 12 },
    ]);
    expect(r.anyBreach).toBe(true);
    expect(r.breaches).toHaveLength(1);
    expect(r.breaches[0].stage).toBe(2);
    // A média (10,5) passaria no piso — a política NÃO usa média.
    const media = (9 + 12) / 2;
    expect(media).toBeGreaterThanOrEqual(STAGE_MINIMUM_POLICY_V1.minimumCommon);
    expect(r.perStage[0].result).toBe("below_minimum");
  });
  test("as duas etapas de supermercado usam o piso 20/24", () => {
    expect(
      evaluateStage({
        stage: 6,
        benefitType: "supermarket_stage_2",
        approvedCount: 20,
      }).contractualMinimum
    ).toBe(20);
  });
  test("o relatório carimba política, etapa e momento da medição", () => {
    const r = comum(11, 4);
    expect(r.policyVersion).toBe(1);
    expect(r.stage).toBe(4);
    expect(r.benefitType).toBe("pharmacy");
    expect(new Date(r.measuredAt).toString()).not.toBe("Invalid Date");
  });
  test("a tolerância futura de ~5% NÃO está ativa", () => {
    // Sob 5% de tolerância, 12 nominais aceitariam 11,4 -> 11 aprovados.
    // A política vigente exige 10 como piso numérico explícito, não derivado.
    expect(STAGE_MINIMUM_POLICY_V1.minimumCommon).toBe(10);
    expect(STAGE_MINIMUM_POLICY_V1.minimumSupermarket).toBe(20);
  });
  test("etapa abaixo do mínimo não pune usuários individuais", () => {
    expect(userPenaltyFromStageBreach()).toBeNull();
  });
});
