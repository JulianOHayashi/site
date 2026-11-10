import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const read = (p: string) => readFileSync(resolve(__dirname, "..", p), "utf8");

describe("SmallFlags — finalidade da publicidade veicular", () => {
  const paginas = [
    "pages/Home.tsx",
    "pages/institucional/QuemSomos.tsx",
    "pages/institucional/ComoFunciona.tsx",
    "pages/Parceiros.tsx",
    "pages/institucional/Ajuda.tsx",
    "components/institucional/RelacaoSiteApp.tsx",
    "pages/Oportunidades.tsx",
    "pages/OportunidadeDetalhe.tsx",
  ];

  it.each(paginas)("%s explica a bandeira no veículo", (path) => {
    const c = read(path);
    expect(c).toMatch(/bandeiras? publicitárias?|bandeiras? instaladas|bandeira instalada/i);
    expect(c).toMatch(/veículo/i);
  });

  it("não mantém divulgação sonora como objeto da publicidade", () => {
    for (const path of paginas) {
      const c = read(path);
      expect(c).not.toMatch(/divulgação sonora em vias públicas|Divulgação sonora em via pública|para divulgação sonora/i);
    }
  });

  it("usa medidas como referência visual e condiciona a segurança", () => {
    const c = read("pages/institucional/QuemSomos.tsx");
    expect(c).toContain("49 cm de largura por 30,5 cm");
    expect(c).toContain("validação técnica");
  });

  it("minuta legal é rascunho, não contrato publicado", () => {
    const c = readFileSync(resolve(__dirname, "../../docs/legal/MINUTA_PUBLICIDADE_VEICULAR_BANDEIRA_20261110.md"), "utf8");
    expect(c).toContain("NÃO PUBLICADO / NÃO ASSINÁVEL");
    expect(c).toContain("49 cm de largura por 30,5 cm");
    expect(c).toContain("Acordo Mestre");
    expect(c).toContain("Instrumento individual");
  });
});
