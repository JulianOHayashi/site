import { describe, expect, it } from "vitest";
import { PREVIA_SF15, resumoPrevia } from "../content/previaPrecosBandeiras";

describe("prévia SF-v1.5 (não vigente)", () => {
  it("seis anunciantes novos exigem 504 bandeiras físicas", () => {
    expect(PREVIA_SF15.nichos).toHaveLength(6);
    expect(resumoPrevia.bandeirasNovas).toBe(504);
    expect(resumoPrevia.custoProducaoCentavos).toBe(1_764_000);
  });

  it("valores econômicos propostos fecham em centavos", () => {
    expect(resumoPrevia.novosCentavos).toBe(14_763_400);
    expect(resumoPrevia.fidelizadosCentavos).toBe(10_911_600);
    expect(PREVIA_SF15.nichos[0].novoCentavos).toBe(3_293_900);
    expect(PREVIA_SF15.nichos[0].fidelizadoCentavos).toBe(2_817_600);
    expect(PREVIA_SF15.nichos[1].novoCentavos).toBe(2_293_900);
    expect(PREVIA_SF15.nichos[1].fidelizadoCentavos).toBe(1_618_800);
  });

  it("não confunde 84 unidades comerciais com produção de 84 peças totais", () => {
    const unidadesComerciais = PREVIA_SF15.nichos.reduce((s,n) => s+n.unidadesComerciais,0);
    expect(unidadesComerciais).toBe(84);
    expect(resumoPrevia.bandeirasNovas).toBe(504);
  });
});