/**
 * BLOCO 6 — Política DETERMINÍSTICA e VERSIONADA de cronograma operacional
 * (domínio do APP; este módulo é portável e não é executado pelo Site em
 * produção — ver docs/APP_INTEGRATION_SPEC.md).
 *
 * Ciclo inicial: 84 usuários reais = 7 grupos x 12 vagas, sete etapas.
 * Cada usuário recebe exatamente: 2 etapas de supermercado + 1 de cada um
 * dos cinco nichos comuns.
 *
 * A matriz canônica abaixo é DADO VERSIONADO; as invariantes são provadas
 * por código (validateSchedulePolicy), nunca presumidas.
 */
import {
  BENEFIT_TYPES,
  NOMINAL_CAPACITY,
  COMMERCIAL_ORIGIN,
  isSupermarketStage,
  type BenefitType,
} from "./benefitTypes";

export const GROUP_COUNT = 7;
export const SLOTS_PER_GROUP = 12;
export const STAGE_COUNT = 7;
export const PARTICIPANT_TARGET = GROUP_COUNT * SLOTS_PER_GROUP; // 84

export type ScheduleMatrix = BenefitType[][]; // [grupo][etapa]

/**
 * Matriz canônica v1 (legenda do documento de decisão):
 *              ST1 ST2 ST3 ST4 ST5 ST6 ST7
 *   Grupo 1     S1   P  WC  S2  MC  WS  MS
 *   Grupo 2     MS  S1   P  WC  S2  MC  WS
 *   Grupo 3     WS  MS  S1   P  WC  S2  MC
 *   Grupo 4     MC  WS  MS  S1   P  WC  S2
 *   Grupo 5     S1  MC  WS  MS  S2   P  WC
 *   Grupo 6     WC  S1  MC  WS  MS  S2   P
 *   Grupo 7      P  WC  S1  MC  WS  MS  S2
 */
const S1: BenefitType = "supermarket_stage_1";
const S2: BenefitType = "supermarket_stage_2";
const P: BenefitType = "pharmacy";
const WC: BenefitType = "womens_clothing";
const MC: BenefitType = "mens_clothing";
const WS: BenefitType = "womens_footwear";
const MS: BenefitType = "mens_footwear";

export const SCHEDULE_POLICY_VERSION = 1;

export const CANONICAL_SCHEDULE_V1: ScheduleMatrix = [
  [S1, P, WC, S2, MC, WS, MS],
  [MS, S1, P, WC, S2, MC, WS],
  [WS, MS, S1, P, WC, S2, MC],
  [MC, WS, MS, S1, P, WC, S2],
  [S1, MC, WS, MS, S2, P, WC],
  [WC, S1, MC, WS, MS, S2, P],
  [P, WC, S1, MC, WS, MS, S2],
];

export type ScheduleViolation = { code: string; detail: string };

/**
 * Prova matemática das invariantes exigidas. Devolve TODAS as violações
 * encontradas (lista vazia = política válida).
 */
export function validateSchedulePolicy(
  matrix: ScheduleMatrix,
  slotsPerGroup: number = SLOTS_PER_GROUP
): ScheduleViolation[] {
  const v: ScheduleViolation[] = [];
  const push = (code: string, detail: string) => v.push({ code, detail });

  // (21-23) 7 grupos, 12 vagas por grupo, 84 vagas no total.
  if (matrix.length !== GROUP_COUNT) {
    push("group_count", `esperados ${GROUP_COUNT} grupos, obtidos ${matrix.length}`);
  }
  if (slotsPerGroup !== SLOTS_PER_GROUP) {
    push("slots_per_group", `esperadas ${SLOTS_PER_GROUP} vagas por grupo`);
  }
  if (matrix.length * slotsPerGroup !== PARTICIPANT_TARGET) {
    push("total_slots", `esperadas ${PARTICIPANT_TARGET} vagas no total`);
  }

  matrix.forEach((linha, gi) => {
    const grupo = gi + 1;
    // (24) sete etapas por grupo.
    if (linha.length !== STAGE_COUNT) {
      push("stages_per_group", `grupo ${grupo} tem ${linha.length} etapas`);
      return;
    }
    // (25-27) cada benefício exatamente uma vez por grupo.
    for (const tipo of BENEFIT_TYPES) {
      const n = linha.filter((b) => b === tipo).length;
      if (n !== 1) {
        push("benefit_once_per_group", `grupo ${grupo}: ${tipo} aparece ${n}x`);
      }
    }
    const i1 = linha.indexOf(S1);
    const i2 = linha.indexOf(S2);
    if (i1 >= 0 && i2 >= 0) {
      // (28) S1 precede S2.
      if (!(i1 < i2)) {
        push("s1_before_s2", `grupo ${grupo}: S1 na etapa ${i1 + 1}, S2 na ${i2 + 1}`);
      }
      // (29) S1 e S2 nunca consecutivas.
      if (Math.abs(i1 - i2) === 1) {
        push("supermarket_adjacent", `grupo ${grupo}: etapas ${i1 + 1} e ${i2 + 1}`);
      }
    }
  });

  // (30-31) capacidade por etapa de calendário.
  for (let etapa = 0; etapa < STAGE_COUNT; etapa++) {
    const coluna = matrix.map((linha) => linha[etapa]).filter(Boolean);
    const porNicho = new Map<string, number>();
    for (const b of coluna) {
      const nicho = COMMERCIAL_ORIGIN[b];
      porNicho.set(nicho, (porNicho.get(nicho) ?? 0) + slotsPerGroup);
    }
    for (const [nicho, capacidade] of porNicho) {
      const esperado = NOMINAL_CAPACITY[nicho as keyof typeof NOMINAL_CAPACITY];
      if (capacidade !== esperado) {
        push(
          "stage_capacity",
          `etapa ${etapa + 1}: ${nicho} com ${capacidade} vagas (esperado ${esperado})`
        );
      }
    }
    // Toda etapa de calendário aloca as 84 vagas.
    const total = coluna.length * slotsPerGroup;
    if (total !== PARTICIPANT_TARGET) {
      push("stage_total", `etapa ${etapa + 1}: ${total} vagas alocadas`);
    }
  }

  return v;
}

/** Agenda de um grupo (1-indexado), na ordem das etapas de calendário. */
export function scheduleForGroup(
  matrix: ScheduleMatrix,
  group: number
): BenefitType[] {
  if (!Number.isInteger(group) || group < 1 || group > matrix.length) {
    throw new Error("grupo fora da política");
  }
  return [...matrix[group - 1]];
}

/**
 * Benefícios que um usuário ainda pode receber ao entrar/ser substituído a
 * partir de uma etapa: SOMENTE etapas ainda não iniciadas.
 * fromStage é 1-indexado e representa a próxima etapa elegível.
 */
export function futureBenefitsForGroup(
  matrix: ScheduleMatrix,
  group: number,
  fromStage: number
): Array<{ stage: number; benefit: BenefitType }> {
  const agenda = scheduleForGroup(matrix, group);
  const inicio = Math.max(1, fromStage);
  return agenda
    .map((benefit, i) => ({ stage: i + 1, benefit }))
    .filter((x) => x.stage >= inicio);
}

/** Quantidade de etapas de supermercado por usuário de um grupo (deve ser 2). */
export function supermarketStagesPerGroup(
  matrix: ScheduleMatrix,
  group: number
): number {
  return scheduleForGroup(matrix, group).filter(isSupermarketStage).length;
}
