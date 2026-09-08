/**
 * BLOCO 8 — Distribuição do POOL CONTRATUAL em benefícios individuais.
 *
 * ┌──────────────────────────────────────────────────────────────────────┐
 * │ POLÍTICA DE DISTRIBUIÇÃO **VERSÃO 1 — HISTÓRICA, NÃO É A ATIVA**.    │
 * │                                                                      │
 * │ A política ATIVA da Comercial V2 é a versão 2, implementada em       │
 * │ `residualAllocation.ts`: ela distribui o resíduo de forma            │
 * │ determinística e fecha em 109.900 centavos por participante          │
 * │ completo. Esta V1 para em 109.898 porque deixa o resto sem           │
 * │ distribuir — era correta quando foi escrita e continua sendo a       │
 * │ referência de como o sistema se comportava.                         │
 * │                                                                      │
 * │ Mantida para regressão histórica. Não importar em caminho novo:      │
 * │ hoje nenhum código de produto a importa, apenas testes. Ao ler o     │
 * │ campo `benefit_distribution_policy_version` de um pedido, 1 aponta   │
 * │ para este arquivo e 2 para `residualAllocation.ts`.                  │
 * └──────────────────────────────────────────────────────────────────────┘
 *
 * O pool de cada contrato é distribuído sobre os MESMOS 84 usuários reais do
 * ciclo (não 84 produtos avulsos).
 *
 *   benefício por usuário = floor(pool_cents / participant_target)
 *
 * O resto NÃO é distribuído e NÃO gera entitlement extra nem razão especial
 * de centavos: o contrato guarda o pool total, então a diferença permanece
 * matematicamente derivável.
 *
 * Supermercado: o total por usuário é dividido em duas etapas operacionais
 *   stage_1 = floor(total / 2)
 *   stage_2 = total - stage_1
 * (Com 84 usuários o total é par e as duas etapas ficam iguais.)
 *
 * INVARIANTE OBRIGATÓRIA: a soma de todos os benefícios normais derivados de
 * um contrato NUNCA excede o pool contratual de origem.
 *
 * Tudo em CENTAVOS INTEIROS.
 */
import {
  SUPERMARKET_STAGES,
  type BenefitType,
  type CommercialNiche,
} from "./benefitTypes";
import { PARTICIPANT_TARGET } from "./schedulePolicy";

export const DISTRIBUTION_POLICY_VERSION = 1;

export type BenefitAllocation = {
  benefitType: BenefitType;
  assignedAmountCents: number;
};

export type PoolDistribution = {
  distributionPolicyVersion: number;
  niche: CommercialNiche;
  poolCents: number;
  participantTarget: number;
  perUserTotalCents: number;
  allocations: BenefitAllocation[];
  /** Resto do pool que permanece NÃO distribuído (não é saldo de usuário). */
  undistributedRemainderCents: number;
};

export function distributePool(
  niche: CommercialNiche,
  poolCents: number,
  participantTarget: number = PARTICIPANT_TARGET
): PoolDistribution {
  if (!Number.isInteger(poolCents) || poolCents < 0) {
    throw new Error("pool deve ser inteiro em centavos");
  }
  if (!Number.isInteger(participantTarget) || participantTarget <= 0) {
    throw new Error("alvo de participantes inválido");
  }
  const perUserTotal = Math.floor(poolCents / participantTarget);

  let allocations: BenefitAllocation[];
  if (niche === "supermarket") {
    const s1 = Math.floor(perUserTotal / 2);
    const s2 = perUserTotal - s1;
    allocations = [
      { benefitType: SUPERMARKET_STAGES[0], assignedAmountCents: s1 },
      { benefitType: SUPERMARKET_STAGES[1], assignedAmountCents: s2 },
    ];
  } else {
    allocations = [
      { benefitType: niche as BenefitType, assignedAmountCents: perUserTotal },
    ];
  }

  const distribuido = perUserTotal * participantTarget;
  return {
    distributionPolicyVersion: DISTRIBUTION_POLICY_VERSION,
    niche,
    poolCents,
    participantTarget,
    perUserTotalCents: perUserTotal,
    allocations,
    undistributedRemainderCents: poolCents - distribuido,
  };
}

/**
 * Verificação da invariante do teste 20: a soma de todos os benefícios
 * normais atribuídos a partir de um contrato não pode exceder o pool.
 */
export function poolInvariantHolds(
  distribution: PoolDistribution,
  assignedUsers: number = distribution.participantTarget
): boolean {
  const somaPorUsuario = distribution.allocations.reduce(
    (acc, a) => acc + a.assignedAmountCents,
    0
  );
  if (somaPorUsuario !== distribution.perUserTotalCents) return false;
  return somaPorUsuario * assignedUsers <= distribution.poolCents;
}

/**
 * Conjunto completo dos sete benefícios de um usuário que cumpre todas as
 * etapas, a partir dos pools dos seis contratos da formação.
 */
export function perUserBenefitSet(
  poolsByNiche: Record<CommercialNiche, number>,
  participantTarget: number = PARTICIPANT_TARGET
): { allocations: BenefitAllocation[]; totalCents: number; undistributedTotalCents: number } {
  const allocations: BenefitAllocation[] = [];
  let undistributed = 0;
  for (const [niche, pool] of Object.entries(poolsByNiche) as Array<
    [CommercialNiche, number]
  >) {
    const d = distributePool(niche, pool, participantTarget);
    allocations.push(...d.allocations);
    undistributed += d.undistributedRemainderCents;
  }
  return {
    allocations,
    totalCents: allocations.reduce((a, x) => a + x.assignedAmountCents, 0),
    undistributedTotalCents: undistributed,
  };
}
