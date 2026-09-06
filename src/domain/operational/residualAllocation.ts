/**
 * COMERCIAL V2 — distribuição exata do pool sobre os 84 participantes.
 *
 * O PROBLEMA
 * Cada pool dividido por 84 deixa resto:
 *
 *   supermercado  2.554.305 / 84 = 30.408, resto 33
 *   cada comum    1.335.459 / 84 = 15.898, resto 27
 *
 * Base por participante: 30.408 + 5 × 15.898 = 109.898 centavos.
 * Resíduos totais: 33 + 5 × 27 = 168 = 84 × 2.
 *
 * Ou seja, cada participante recebe exatamente DOIS centavos de resíduo e o
 * total fecha em 109.900 — o alvo aprovado — sem que nenhum pool seja
 * excedido. A política V1, que deixava o resto sem distribuir, não consegue
 * isso: pararia em 109.898.
 *
 * POR QUE NÃO BASTA ORDENAR OS RESÍDUOS EM FILA
 * Uma primeira ideia foi enfileirar 168 fichas e dar duas a cada
 * participante. As somas fechariam, mas um participante poderia receber os
 * dois centavos do MESMO nicho enquanto outro não recebe nenhum daquele
 * nicho. O contrato exige atribuição de um centavo por nicho: dois centavos
 * do mesmo nicho seriam duas atribuições onde deveria haver uma.
 *
 * A POLÍTICA
 * Matriz binária determinística de 84 × 6:
 *
 *   soma de cada linha (nicho)        = [33, 27, 27, 27, 27, 27]
 *   soma de cada coluna (participante) = 2
 *   cada entrada                       ∈ {0, 1}
 *
 * Algoritmo: para cada participante, na ordem do slot, escolher os DOIS
 * nichos DISTINTOS com maior saldo de resíduo restante, desempatando pela
 * ordem canônica fixa. Determinístico e estável: nada de aleatoriedade,
 * relógio, ordem de linha do banco, ordem lexical de UUID ou entrada do
 * navegador decide alocação.
 *
 * O App continua sendo a autoridade operacional sobre elegibilidade e
 * liberação. Isto aqui é a política contratual de referência do Site.
 */

import {
  PARTICIPANT_TARGET_V2,
  computeCommercialCompositionV2,
  FORMATION_NICHES,
} from "../pricing/commercialV2";
import {
  SUPERMARKET_STAGES,
  type BenefitType,
  type CommercialNiche,
} from "./benefitTypes";

export const DISTRIBUTION_POLICY_VERSION_V2 = 2;

/** Ordem canônica de desempate. Fixa e versionada com a política. */
export const CANONICAL_NICHE_ORDER: readonly CommercialNiche[] = [
  "supermarket",
  "pharmacy",
  "womens_clothing",
  "mens_clothing",
  "womens_footwear",
  "mens_footwear",
] as const;

export type ResidualMatrix = {
  policyVersion: number;
  participantTarget: number;
  /** matrix[slot][niche] ∈ {0,1} */
  matrix: Array<Record<CommercialNiche, 0 | 1>>;
};

/**
 * Constrói a matriz binária de resíduos.
 *
 * Falha fechada: se os saldos não zerarem ao final, ou se algum participante
 * não conseguir dois nichos distintos, lança em vez de devolver uma
 * distribuição silenciosamente errada.
 */
export function buildResidualMatrix(
  remainderByNiche: Record<CommercialNiche, number>,
  participantTarget: number = PARTICIPANT_TARGET_V2
): ResidualMatrix {
  const total = CANONICAL_NICHE_ORDER.reduce((a, n) => a + remainderByNiche[n], 0);
  if (total !== participantTarget * 2) {
    throw new Error(
      `residuos totais (${total}) nao equivalem a 2 por participante (${participantTarget * 2})`
    );
  }
  for (const n of CANONICAL_NICHE_ORDER) {
    const v = remainderByNiche[n];
    if (!Number.isInteger(v) || v < 0 || v > participantTarget) {
      // Mais resíduos que participantes exigiria dar dois do mesmo nicho.
      throw new Error(`resto invalido para ${n}: ${v}`);
    }
  }

  const saldo: Record<CommercialNiche, number> = { ...remainderByNiche };
  const matrix: Array<Record<CommercialNiche, 0 | 1>> = [];

  for (let slot = 0; slot < participantTarget; slot++) {
    // Dois nichos DISTINTOS com maior saldo; empate pela ordem canônica.
    const candidatos = CANONICAL_NICHE_ORDER.filter((n) => saldo[n] > 0).sort((a, b) => {
      if (saldo[b] !== saldo[a]) return saldo[b] - saldo[a];
      return CANONICAL_NICHE_ORDER.indexOf(a) - CANONICAL_NICHE_ORDER.indexOf(b);
    });
    if (candidatos.length < 2) {
      throw new Error(`slot ${slot}: nichos distintos insuficientes com saldo`);
    }
    const escolhidos = candidatos.slice(0, 2);
    const linha = Object.fromEntries(
      CANONICAL_NICHE_ORDER.map((n) => [n, escolhidos.includes(n) ? 1 : 0])
    ) as Record<CommercialNiche, 0 | 1>;
    for (const n of escolhidos) saldo[n] -= 1;
    matrix.push(linha);
  }

  for (const n of CANONICAL_NICHE_ORDER) {
    if (saldo[n] !== 0) throw new Error(`saldo residual nao zerado em ${n}: ${saldo[n]}`);
  }
  return { policyVersion: DISTRIBUTION_POLICY_VERSION_V2, participantTarget, matrix };
}

export type ParticipantAllocation = {
  participantSlot: number;
  /** Alocação por nicho comercial (seis). */
  byNiche: Record<CommercialNiche, number>;
  /** Sete benefícios operacionais do App. */
  benefits: Array<{ benefitType: BenefitType; assignedAmountCents: number }>;
  totalCents: number;
};

export type FormationDistribution = {
  policyVersion: number;
  participantTarget: number;
  poolByNiche: Record<CommercialNiche, number>;
  baseByNiche: Record<CommercialNiche, number>;
  remainderByNiche: Record<CommercialNiche, number>;
  participants: ParticipantAllocation[];
  distributedTotalCents: number;
};

/** Pools da formação completa não fidelizada, pela política V2. */
export function formationPoolsV2(): Record<CommercialNiche, number> {
  const out = {} as Record<CommercialNiche, number>;
  for (const n of FORMATION_NICHES) {
    out[n.code as CommercialNiche] = computeCommercialCompositionV2(
      n.code,
      n.quantity,
      false
    ).userPoolCents;
  }
  return out;
}

/**
 * Distribui a formação completa: base por piso mais o centavo de resíduo
 * definido pela matriz.
 *
 * Supermercado é dividido nas duas etapas operacionais do App; total ímpar
 * usa piso na etapa 1 e o restante na etapa 2. As duas somam exatamente a
 * alocação de supermercado do participante.
 */
export function distributeFormationV2(
  poolByNiche: Record<CommercialNiche, number> = formationPoolsV2(),
  participantTarget: number = PARTICIPANT_TARGET_V2
): FormationDistribution {
  const base = {} as Record<CommercialNiche, number>;
  const resto = {} as Record<CommercialNiche, number>;
  for (const n of CANONICAL_NICHE_ORDER) {
    const pool = poolByNiche[n];
    if (!Number.isInteger(pool) || pool < 0) throw new Error(`pool invalido em ${n}`);
    base[n] = Math.floor(pool / participantTarget);
    resto[n] = pool % participantTarget;
  }

  const { matrix } = buildResidualMatrix(resto, participantTarget);

  const participants: ParticipantAllocation[] = [];
  for (let slot = 0; slot < participantTarget; slot++) {
    const byNiche = {} as Record<CommercialNiche, number>;
    for (const n of CANONICAL_NICHE_ORDER) byNiche[n] = base[n] + matrix[slot][n];

    const sup = byNiche.supermarket;
    const s1 = Math.floor(sup / 2);
    const benefits: ParticipantAllocation["benefits"] = [
      { benefitType: SUPERMARKET_STAGES[0], assignedAmountCents: s1 },
      { benefitType: SUPERMARKET_STAGES[1], assignedAmountCents: sup - s1 },
    ];
    for (const n of CANONICAL_NICHE_ORDER) {
      if (n === "supermarket") continue;
      benefits.push({ benefitType: n as BenefitType, assignedAmountCents: byNiche[n] });
    }

    participants.push({
      participantSlot: slot,
      byNiche,
      benefits,
      totalCents: benefits.reduce((a, b) => a + b.assignedAmountCents, 0),
    });
  }

  return {
    policyVersion: DISTRIBUTION_POLICY_VERSION_V2,
    participantTarget,
    poolByNiche,
    baseByNiche: base,
    remainderByNiche: resto,
    participants,
    distributedTotalCents: participants.reduce((a, p) => a + p.totalCents, 0),
  };
}

/** Conservação: nenhum pool excedido e nada perdido. */
export function poolConservationHolds(d: FormationDistribution): boolean {
  for (const n of CANONICAL_NICHE_ORDER) {
    const soma = d.participants.reduce((a, p) => a + p.byNiche[n], 0);
    if (soma !== d.poolByNiche[n]) return false;
  }
  return true;
}
