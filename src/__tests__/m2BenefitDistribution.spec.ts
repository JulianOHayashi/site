/**
 * BLOCO 8 — Provas da distribuição pool -> benefícios individuais
 * (testes 12-20 da seção 30).
 */
import { describe, test, expect } from "vitest";
import {
  distributePool,
  perUserBenefitSet,
  poolInvariantHolds,
} from "../domain/operational/benefitDistribution";
import { PARTICIPANT_TARGET } from "../domain/operational/schedulePolicy";
import type { CommercialNiche } from "../domain/operational/benefitTypes";

// Pools reais do primeiro lançamento (Bloco 3/4).
const POOL_COMUM = 1_399_930; // R$ 13.999,30
const POOL_SUPER = 2_669_025; // R$ 26.690,25

const POOLS_PRIMEIRO_LANCAMENTO: Record<CommercialNiche, number> = {
  supermarket: POOL_SUPER,
  pharmacy: POOL_COMUM,
  womens_clothing: POOL_COMUM,
  mens_clothing: POOL_COMUM,
  womens_footwear: POOL_COMUM,
  mens_footwear: POOL_COMUM,
};

describe("distribuição sobre os 84 usuários reais", () => {
  const comum = distributePool("pharmacy", POOL_COMUM);
  const superm = distributePool("supermarket", POOL_SUPER);

  test("T12 benefício comum por usuário = R$ 166,65", () => {
    expect(comum.perUserTotalCents).toBe(16_665);
    expect(comum.allocations).toEqual([
      { benefitType: "pharmacy", assignedAmountCents: 16_665 },
    ]);
  });
  test("T13 resto não distribuído do contrato comum = R$ 0,70", () => {
    expect(comum.undistributedRemainderCents).toBe(70);
  });
  test("T14 supermercado por usuário (somado) = R$ 317,74", () => {
    expect(superm.perUserTotalCents).toBe(31_774);
  });
  test("T15/T16 S1 e S2 = R$ 158,87 cada", () => {
    expect(superm.allocations[0]).toEqual({
      benefitType: "supermarket_stage_1",
      assignedAmountCents: 15_887,
    });
    expect(superm.allocations[1]).toEqual({
      benefitType: "supermarket_stage_2",
      assignedAmountCents: 15_887,
    });
  });
  test("T17 resto não distribuído do supermercado = R$ 0,09", () => {
    expect(superm.undistributedRemainderCents).toBe(9);
  });

  const conjunto = perUserBenefitSet(POOLS_PRIMEIRO_LANCAMENTO);

  test("T18 usuário que cumpre tudo recebe R$ 1.150,99 em sete benefícios", () => {
    expect(conjunto.allocations).toHaveLength(7);
    expect(conjunto.totalCents).toBe(115_099);
  });
  test("T19 total não distribuído do primeiro lançamento = R$ 3,59", () => {
    expect(conjunto.undistributedTotalCents).toBe(359);
  });
  test("T20 nenhuma soma de benefícios excede o pool de origem", () => {
    for (const [niche, pool] of Object.entries(POOLS_PRIMEIRO_LANCAMENTO) as Array<
      [CommercialNiche, number]
    >) {
      const d = distributePool(niche, pool);
      expect(poolInvariantHolds(d)).toBe(true);
      const soma = d.perUserTotalCents * PARTICIPANT_TARGET;
      expect(soma).toBeLessThanOrEqual(pool);
    }
  });
  test("o resto NÃO vira entitlement extra (contagem fixa por nicho)", () => {
    expect(distributePool("pharmacy", POOL_COMUM).allocations).toHaveLength(1);
    expect(distributePool("supermarket", POOL_SUPER).allocations).toHaveLength(2);
  });
  test("não existe saldo agregado: cada alocação é individual e nomeada", () => {
    for (const a of conjunto.allocations) {
      expect(Number.isInteger(a.assignedAmountCents)).toBe(true);
      expect(a.benefitType).toBeTruthy();
    }
  });
});

describe("regra geral de divisão do supermercado", () => {
  test("total ímpar: stage_2 recebe o centavo restante e a soma bate", () => {
    // 84 usuários, pool escolhido para gerar total por usuário ímpar.
    const d = distributePool("supermarket", 84 * 101);
    expect(d.perUserTotalCents).toBe(101);
    expect(d.allocations[0].assignedAmountCents).toBe(50);
    expect(d.allocations[1].assignedAmountCents).toBe(51);
    expect(
      d.allocations[0].assignedAmountCents + d.allocations[1].assignedAmountCents
    ).toBe(d.perUserTotalCents);
    expect(poolInvariantHolds(d)).toBe(true);
  });
  test("alvo de participantes maior nunca ultrapassa o pool", () => {
    for (const alvo of [84, 100, 501, 1005]) {
      const d = distributePool("supermarket", POOL_SUPER, alvo);
      expect(d.perUserTotalCents * alvo).toBeLessThanOrEqual(POOL_SUPER);
      expect(poolInvariantHolds(d, alvo)).toBe(true);
    }
  });
  test("entradas inválidas são rejeitadas", () => {
    expect(() => distributePool("pharmacy", -1)).toThrow();
    expect(() => distributePool("pharmacy", 1.5)).toThrow();
    expect(() => distributePool("pharmacy", 100, 0)).toThrow();
  });
});
