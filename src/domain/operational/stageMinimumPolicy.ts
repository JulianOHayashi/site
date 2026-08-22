/**
 * BLOCO 7 (parte 2) — Mínimo contratual medido POR ETAPA CORRESPONDENTE.
 *
 * Alvo nominal:        nicho comum 12 | supermercado 24
 * Mínimo contratual:   nicho comum 10 | supermercado 20   (contrato v1)
 *
 * A medição é SEMPRE por etapa correspondente. Uma etapa boa NUNCA compensa
 * outra abaixo do mínimo — não existe média entre etapas.
 *
 * "Entregue" = participações efetivamente concluídas/aprovadas pelo App, não
 * "havia uma vaga".
 *
 * A tolerância futura (~5% em populações muito maiores) NÃO está ativa: a
 * política é versionada para que um contrato futuro mude os números sem
 * reescrever ciclos históricos.
 */
import { COMMERCIAL_ORIGIN, type BenefitType } from "./benefitTypes";

export const STAGE_MINIMUM_POLICY_VERSION = 1;

export type StageMinimumPolicy = {
  version: number;
  nominalCommon: number;
  minimumCommon: number;
  nominalSupermarket: number;
  minimumSupermarket: number;
};

export const STAGE_MINIMUM_POLICY_V1: StageMinimumPolicy = {
  version: 1,
  nominalCommon: 12,
  minimumCommon: 10,
  nominalSupermarket: 24,
  minimumSupermarket: 20,
};

export type StageMeasurement = {
  /** Etapa de calendário (1-indexada). */
  stage: number;
  benefitType: BenefitType;
  /** Participações concluídas E aprovadas nesta etapa correspondente. */
  approvedCount: number;
};

export type StageMeasurementResult = {
  policyVersion: number;
  stage: number;
  benefitType: BenefitType;
  nominalTarget: number;
  contractualMinimum: number;
  approvedCount: number;
  result: "pass" | "below_minimum";
  measuredAt: string;
};

export function evaluateStage(
  m: StageMeasurement,
  policy: StageMinimumPolicy = STAGE_MINIMUM_POLICY_V1,
  measuredAt: Date = new Date()
): StageMeasurementResult {
  const supermercado = COMMERCIAL_ORIGIN[m.benefitType] === "supermarket";
  const nominal = supermercado ? policy.nominalSupermarket : policy.nominalCommon;
  const minimo = supermercado ? policy.minimumSupermarket : policy.minimumCommon;
  return {
    policyVersion: policy.version,
    stage: m.stage,
    benefitType: m.benefitType,
    nominalTarget: nominal,
    contractualMinimum: minimo,
    approvedCount: m.approvedCount,
    result: m.approvedCount >= minimo ? "pass" : "below_minimum",
    measuredAt: measuredAt.toISOString(),
  };
}

/**
 * Avalia TODAS as etapas separadamente. Não existe agregação por média: o
 * resultado do contrato é "alguma etapa abaixo do mínimo" ou "nenhuma".
 */
export function evaluateAllStages(
  medicoes: StageMeasurement[],
  policy: StageMinimumPolicy = STAGE_MINIMUM_POLICY_V1
): {
  perStage: StageMeasurementResult[];
  breaches: StageMeasurementResult[];
  anyBreach: boolean;
} {
  const perStage = medicoes.map((m) => evaluateStage(m, policy));
  const breaches = perStage.filter((r) => r.result === "below_minimum");
  return { perStage, breaches, anyBreach: breaches.length > 0 };
}

/**
 * A punição do parceiro por etapa abaixo do mínimo NÃO recai sobre usuários
 * individuais: esta função existe para deixar a regra explícita e testável.
 */
export function userPenaltyFromStageBreach(): null {
  return null;
}
