/**
 * BLOCO 9 — Provas da aprovação manual de etapa e liberação específica.
 */
import { describe, test, expect } from "vitest";
import {
  applyStageApprovalRelease,
  aggregateWalletBalance,
  ManualApprovalError,
  type Entitlement,
  type StageApproval,
} from "../domain/operational/manualApprovalPolicy";
import { scheduleForGroup, CANONICAL_SCHEDULE_V1 } from "../domain/operational/schedulePolicy";

// Usuário do grupo 3: agenda WS, MS, S1, P, WC, S2, MC.
const agenda = scheduleForGroup(CANONICAL_SCHEDULE_V1, 3);
const seteBeneficios: Entitlement[] = agenda.map((benefitType, i) => ({
  entitlementId: `ent-${i + 1}`,
  userId: "usuario-A",
  cycleId: "ciclo-1",
  stage: i + 1,
  benefitType,
  assignedAmountCents: benefitType.startsWith("supermarket") ? 15_887 : 16_665,
  status: "locked",
}));

const aprovacao = (stage: number, over?: Partial<StageApproval>): StageApproval => ({
  cycleId: "ciclo-1",
  userId: "usuario-A",
  stage,
  approved: true,
  actorId: "admin-1",
  decidedAt: new Date().toISOString(),
  reason: "conferência manual do lançamento",
  source: "initial_launch_manual",
  ...over,
});

describe("liberação específica de etapa", () => {
  test("aprovar a etapa da farmácia libera SOMENTE a farmácia", () => {
    const etapaFarmacia =
      seteBeneficios.find((e) => e.benefitType === "pharmacy")!.stage;
    const r = applyStageApprovalRelease(seteBeneficios, aprovacao(etapaFarmacia));
    expect(r.changed).toHaveLength(1);
    expect(r.changed[0].benefitType).toBe("pharmacy");
    expect(r.changed[0].status).toBe("available");
    // Os outros seis continuam bloqueados.
    expect(r.unchanged).toHaveLength(6);
    expect(r.unchanged.every((e) => e.status === "locked")).toBe(true);
  });
  test("NÃO destrava os sete benefícios de uma vez", () => {
    const r = applyStageApprovalRelease(seteBeneficios, aprovacao(1));
    expect(r.changed.filter((e) => e.status === "available")).toHaveLength(1);
  });
  test("etapa reprovada não libera nada", () => {
    const r = applyStageApprovalRelease(
      seteBeneficios,
      aprovacao(1, { approved: false })
    );
    expect(r.changed).toHaveLength(0);
    expect(r.rejectedReason).toBeTruthy();
  });
  test("aprovação repetida é idempotente e não sobrescreve", () => {
    const primeira = applyStageApprovalRelease(seteBeneficios, aprovacao(1));
    const estado = [...primeira.changed, ...primeira.unchanged];
    const segunda = applyStageApprovalRelease(estado, aprovacao(1));
    expect(segunda.already).toBe(true);
    expect(segunda.changed).toHaveLength(0);
  });
  test("benefício já usado não volta para available", () => {
    const usado = seteBeneficios.map((e) =>
      e.stage === 1 ? { ...e, status: "used" as const } : e
    );
    const r = applyStageApprovalRelease(usado, aprovacao(1));
    expect(r.changed).toHaveLength(0);
    expect(
      [...r.changed, ...r.unchanged].find((e) => e.stage === 1)!.status
    ).toBe("used");
  });
  test("ator e motivo são obrigatórios", () => {
    expect(() =>
      applyStageApprovalRelease(seteBeneficios, aprovacao(1, { actorId: "" }))
    ).toThrow(ManualApprovalError);
    expect(() =>
      applyStageApprovalRelease(seteBeneficios, aprovacao(1, { reason: "  " }))
    ).toThrow(ManualApprovalError);
  });
  test("etapa inexistente para o usuário é rejeitada", () => {
    expect(() =>
      applyStageApprovalRelease(seteBeneficios, aprovacao(9))
    ).toThrow(ManualApprovalError);
  });
  test("não afeta outro usuário nem outro ciclo", () => {
    const outros: Entitlement[] = [
      ...seteBeneficios,
      { ...seteBeneficios[0], entitlementId: "ent-x", userId: "usuario-B" },
      { ...seteBeneficios[0], entitlementId: "ent-y", cycleId: "ciclo-2" },
    ];
    const r = applyStageApprovalRelease(outros, aprovacao(1));
    expect(r.changed).toHaveLength(1);
    expect(r.changed[0].userId).toBe("usuario-A");
    expect(r.changed[0].cycleId).toBe("ciclo-1");
  });
  test("a mesma transição serve à automação futura (só muda a origem)", () => {
    const r = applyStageApprovalRelease(
      seteBeneficios,
      aprovacao(1, { source: "automated_evidence_review" })
    );
    expect(r.changed[0].status).toBe("available");
  });
});

describe("cartão individual, sem saldo agregado", () => {
  test("cada benefício tem valor próprio imutável no snapshot", () => {
    for (const e of seteBeneficios) {
      expect(Number.isInteger(e.assignedAmountCents)).toBe(true);
      expect(e.assignedAmountCents).toBeGreaterThan(0);
    }
  });
  test("não existe saldo total de carteira", () => {
    expect(aggregateWalletBalance()).toBeNull();
  });
});
