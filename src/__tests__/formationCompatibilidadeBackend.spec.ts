import { describe, expect, it } from "vitest";
import { parseFormationResponse } from "../services/commercialResponse";
import { positionAcceptsSegment } from "../domain/commercial/niches";
import antigo from "./fixtures/formation-production-backend-antigo-20261104.json";
import novo from "./fixtures/formation-pg17-backend-novo-20261104.json";

/**
 * Compatibilidade do frontend NOVO com respostas REAIS de get_current_commercial_formation:
 *  - backend ANTIGO: capturada de Production em 2026-11-04 (só leitura; função STABLE);
 *  - backend NOVO: capturada do banco PG17.6 descartável com a migration 20261103120000.
 * Nenhuma das duas é montada à mão.
 */
describe("formação pública: frontend novo × backend real", () => {
  it("backend antigo (Production): aceita, sem segmento, sem oferecer Outros", () => {
    const f = parseFormationResponse(antigo);
    expect(f.opportunities.map((o) => o.nicheCode)).toEqual([
      "supermarket", "pharmacy", "womens_clothing", "mens_clothing", "womens_footwear", "mens_footwear",
    ]);
    expect(f.summary?.totalUnits).toBe(84);
    // sem as chaves novas: nada de seletor de segmento, nada de segmento ocupante
    for (const o of f.opportunities) {
      expect(o.acceptsSegment).toBe(false);
      expect(o.requiresSegment).toBe(false);
      expect(o.segment).toBeNull();
    }
  });

  it("backend novo (PG17.6 migrado): seis posições, Calçados e Outros, regras de segmento", () => {
    const f = parseFormationResponse(novo);
    expect(f.opportunities.map((o) => o.nicheCode)).toEqual([
      "supermarket", "pharmacy", "womens_clothing", "mens_clothing", "footwear", "others",
    ]);
    expect(f.opportunities.reduce((s, o) => s + o.contractedQuantity, 0)).toBe(84);
    const porCodigo = Object.fromEntries(f.opportunities.map((o) => [o.nicheCode, o]));
    expect(porCodigo.supermarket.acceptsSegment).toBe(false);
    expect(porCodigo.supermarket.contractedQuantity).toBe(24);
    expect(porCodigo.others.requiresSegment).toBe(true);
    for (const c of ["pharmacy", "womens_clothing", "mens_clothing", "footwear"] as const) {
      expect(porCodigo[c].acceptsSegment).toBe(true);
      expect(positionAcceptsSegment(c)).toBe(true);
    }
    // nada vendido: nenhuma identidade comercial divulgada
    expect(f.opportunities.every((o) => o.segment === null)).toBe(true);
  });

  it("mistura dos dois conjuntos é rejeitada (falha fechada)", () => {
    const misto = structuredClone(antigo) as typeof antigo;
    misto.opportunities[5].niche_code = "others";
    expect(() => parseFormationResponse(misto)).toThrow();
  });
});
