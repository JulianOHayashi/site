/**
 * BLOCO 6 — Provas matemáticas da política de cronograma (testes 21-31 da
 * seção 30). As invariantes são verificadas por código, não presumidas do
 * dado estático; mutantes deliberados devem ser detectados.
 */
import { describe, test, expect } from "vitest";
import {
  CANONICAL_SCHEDULE_V1,
  validateSchedulePolicy,
  scheduleForGroup,
  futureBenefitsForGroup,
  supermarketStagesPerGroup,
  GROUP_COUNT,
  SLOTS_PER_GROUP,
  STAGE_COUNT,
  PARTICIPANT_TARGET,
  type ScheduleMatrix,
} from "../domain/operational/schedulePolicy";
import {
  BENEFIT_TYPES,
  COMMERCIAL_ORIGIN,
  isSupermarketStage,
} from "../domain/operational/benefitTypes";

const M = CANONICAL_SCHEDULE_V1;

describe("política canônica v1 — invariantes obrigatórias", () => {
  test("a política canônica não tem NENHUMA violação", () => {
    expect(validateSchedulePolicy(M)).toEqual([]);
  });
  test("T21 84 vagas no total", () => {
    expect(GROUP_COUNT * SLOTS_PER_GROUP).toBe(84);
    expect(PARTICIPANT_TARGET).toBe(84);
  });
  test("T22 exatamente 7 grupos", () => {
    expect(M.length).toBe(7);
  });
  test("T23 12 vagas por grupo", () => {
    expect(SLOTS_PER_GROUP).toBe(12);
  });
  test("T24 sete etapas por grupo", () => {
    for (const linha of M) expect(linha.length).toBe(STAGE_COUNT);
  });
  test("T25 cada nicho comum aparece uma vez por grupo", () => {
    const comuns = BENEFIT_TYPES.filter((b) => !isSupermarketStage(b));
    for (let g = 1; g <= GROUP_COUNT; g++) {
      const agenda = scheduleForGroup(M, g);
      for (const c of comuns) {
        expect(agenda.filter((b) => b === c)).toHaveLength(1);
      }
    }
  });
  test("T26/T27 S1 e S2 uma vez cada por grupo", () => {
    for (let g = 1; g <= GROUP_COUNT; g++) {
      const agenda = scheduleForGroup(M, g);
      expect(agenda.filter((b) => b === "supermarket_stage_1")).toHaveLength(1);
      expect(agenda.filter((b) => b === "supermarket_stage_2")).toHaveLength(1);
      expect(supermarketStagesPerGroup(M, g)).toBe(2);
    }
  });
  test("T28 S1 precede S2 em todos os grupos", () => {
    for (const linha of M) {
      expect(linha.indexOf("supermarket_stage_1")).toBeLessThan(
        linha.indexOf("supermarket_stage_2")
      );
    }
  });
  test("T29 S1 e S2 nunca são consecutivas", () => {
    for (const linha of M) {
      const d = Math.abs(
        linha.indexOf("supermarket_stage_1") - linha.indexOf("supermarket_stage_2")
      );
      expect(d).toBeGreaterThan(1);
    }
  });
  test("T30 supermercado = 24 vagas em cada etapa de calendário", () => {
    for (let e = 0; e < STAGE_COUNT; e++) {
      const coluna = M.map((l) => l[e]);
      const superm = coluna.filter(isSupermarketStage).length * SLOTS_PER_GROUP;
      expect(superm).toBe(24);
    }
  });
  test("T31 cada nicho comum = 12 vagas em cada etapa de calendário", () => {
    const comuns = ["pharmacy", "womens_clothing", "mens_clothing",
                    "womens_footwear", "mens_footwear"];
    for (let e = 0; e < STAGE_COUNT; e++) {
      const coluna = M.map((l) => l[e]);
      for (const c of comuns) {
        const n = coluna.filter((b) => COMMERCIAL_ORIGIN[b] === c).length;
        expect(n * SLOTS_PER_GROUP).toBe(12);
      }
    }
  });
  test("cada etapa de calendário aloca as 84 vagas", () => {
    for (let e = 0; e < STAGE_COUNT; e++) {
      expect(M.map((l) => l[e]).length * SLOTS_PER_GROUP).toBe(84);
    }
  });
  test("cada usuário recebe 2 supermercado + 5 comuns = 7 benefícios", () => {
    for (let g = 1; g <= GROUP_COUNT; g++) {
      const agenda = scheduleForGroup(M, g);
      expect(agenda.filter(isSupermarketStage)).toHaveLength(2);
      expect(agenda.filter((b) => !isSupermarketStage(b))).toHaveLength(5);
      expect(new Set(agenda).size).toBe(7);
    }
  });
});

describe("o validador realmente detecta violações (mutação)", () => {
  const clonar = (): ScheduleMatrix => M.map((l) => [...l]);
  const temCodigo = (m: ScheduleMatrix, code: string) =>
    validateSchedulePolicy(m).some((v) => v.code === code);

  test("S1/S2 consecutivas são detectadas", () => {
    const mut = clonar();
    // Grupo 1: S1 na etapa 1, S2 na 4 -> move S2 para a etapa 2.
    mut[0] = ["supermarket_stage_1", "supermarket_stage_2", "womens_clothing",
              "pharmacy", "mens_clothing", "womens_footwear", "mens_footwear"];
    expect(temCodigo(mut, "supermarket_adjacent")).toBe(true);
  });
  test("S2 antes de S1 é detectado", () => {
    const mut = clonar();
    mut[0] = ["supermarket_stage_2", "pharmacy", "womens_clothing",
              "supermarket_stage_1", "mens_clothing", "womens_footwear",
              "mens_footwear"];
    expect(temCodigo(mut, "s1_before_s2")).toBe(true);
  });
  test("benefício repetido no grupo é detectado", () => {
    const mut = clonar();
    mut[0][1] = "womens_clothing"; // duplica WC, some P
    expect(temCodigo(mut, "benefit_once_per_group")).toBe(true);
  });
  test("capacidade errada por etapa é detectada", () => {
    const mut = clonar();
    // Duas farmácias na etapa 1 -> 24 vagas de farmácia (esperado 12).
    mut[1][0] = "pharmacy";
    expect(temCodigo(mut, "stage_capacity")).toBe(true);
  });
  test("número de grupos errado é detectado", () => {
    expect(temCodigo(clonar().slice(0, 6), "group_count")).toBe(true);
  });
  test("grupo com menos etapas é detectado", () => {
    const mut = clonar();
    mut[3] = mut[3].slice(0, 6);
    expect(temCodigo(mut, "stages_per_group")).toBe(true);
  });
});

describe("etapas futuras (base da substituição)", () => {
  test("a partir da etapa 1 devolve as sete etapas", () => {
    expect(futureBenefitsForGroup(M, 1, 1)).toHaveLength(7);
  });
  test("a partir da etapa 5 devolve apenas as etapas 5,6,7", () => {
    const f = futureBenefitsForGroup(M, 3, 5);
    expect(f.map((x) => x.stage)).toEqual([5, 6, 7]);
  });
  test("depois da última etapa não há nada a conceder", () => {
    expect(futureBenefitsForGroup(M, 2, 8)).toHaveLength(0);
  });
  test("grupo fora da política é rejeitado", () => {
    expect(() => scheduleForGroup(M, 8)).toThrow();
    expect(() => scheduleForGroup(M, 0)).toThrow();
  });
});
