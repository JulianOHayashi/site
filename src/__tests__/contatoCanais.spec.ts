import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("canais de contato SmallFlags — Grande Vitória", () => {
  const fonte = readFileSync(resolve(process.cwd(), "src/pages/institucional/Contato.tsx"), "utf8");

  it("publica exatamente o e-mail e telefone fornecidos", () => {
    expect(fonte).toContain('href="mailto:grandevitoria@smallflags.com.br"');
    expect(fonte).toContain('href="tel:+5527998803900"');
    expect(fonte).toContain("(27) 99880-3900");
  });

  it("não presume WhatsApp nem horário de atendimento", () => {
    expect(fonte).not.toContain("wa.me/");
    expect(fonte).not.toContain("api.whatsapp.com");
    expect(fonte).not.toContain("Segunda a sexta");
    expect(fonte).not.toContain("Os canais oficiais de atendimento serão publicados");
  });
});