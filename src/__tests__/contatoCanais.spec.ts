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

  it("publica o Instagram confirmado e mantém TikTok sem link", () => {
    expect(fonte).toContain('id="redes-sociais"');
    expect(fonte).toContain("@smallflagsBR");
    expect(fonte).toContain('href="https://www.instagram.com/smallflagsBR/"');
    expect(fonte).toContain("Acessar Instagram");
    expect(fonte).toContain("TikTok");
    expect(fonte).toContain("Em breve");
    expect(fonte).not.toContain("Número de atendimento a confirmar.");
    expect(fonte).not.toMatch(/https?:\/\/(?:www\.)?tiktok\.com\//i);
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