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

  it("reserva Instagram e TikTok sem inventar links", () => {
    for (const rede of ["Instagram", "TikTok"]) {
      expect(fonte).toContain(`nome: "${rede}"`);
    }
    expect(fonte).toContain('id="redes-sociais"');
    expect(fonte).not.toContain("Número de atendimento a confirmar.");
    expect(fonte).not.toContain("https://www.instagram.com/");
    expect(fonte).not.toContain("https://www.tiktok.com/");
  });

  it("WhatsApp comercial confirmado em 25/11/2026: só pela fonte única, sem API nem horário", () => {
    expect(fonte).toContain("WHATSAPP_COMERCIAL_URL");
    expect(fonte).not.toContain("wa.me/"); // o link vem de content/whatsapp, não fixo na página
    expect(fonte).not.toContain("api.whatsapp.com");
    expect(fonte).not.toContain("não está identificado como canal de WhatsApp");
    expect(fonte).not.toContain("Segunda a sexta");
    expect(fonte).not.toContain("Os canais oficiais de atendimento serão publicados");
  });
});