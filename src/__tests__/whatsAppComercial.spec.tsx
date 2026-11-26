import { afterEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import WhatsAppFlutuante, { cobreControle, intersecta } from "../components/WhatsAppComercial";
import { NICHE_SLUG_BY_CODE } from "../domain/commercial/niches";
import Contato from "../pages/institucional/Contato";
import {
  WHATSAPP_COMERCIAL,
  WHATSAPP_COMERCIAL_URL,
  whatsAppFlutuanteVisivel,
} from "../content/whatsapp";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

const URL_ESPERADA =
  "https://wa.me/5527998803900?text=Ol%C3%A1!%20Gostaria%20de%20conhecer%20as%20oportunidades%20comerciais%20da%20SmallFlags.";
const MENSAGEM = "Olá! Gostaria de conhecer as oportunidades comerciais da SmallFlags.";

const flutuante = (rota: string) =>
  render(
    <MemoryRouter initialEntries={[rota]}>
      <WhatsAppFlutuante />
    </MemoryRouter>,
  );

describe("WhatsApp comercial — número, link e mensagem", () => {
  it("número nacional, internacional e E.164 corretos", () => {
    expect(WHATSAPP_COMERCIAL.numeroNacional).toBe("(27) 99880-3900");
    expect(WHATSAPP_COMERCIAL.numeroInternacional).toBe("+55 27 99880-3900");
    expect(WHATSAPP_COMERCIAL.numeroE164).toBe("5527998803900");
  });

  it("link oficial wa.me com a mensagem inicial codificada", () => {
    expect(WHATSAPP_COMERCIAL_URL).toBe(URL_ESPERADA);
    const u = new URL(WHATSAPP_COMERCIAL_URL);
    expect(u.origin).toBe("https://wa.me");
    expect(u.pathname).toBe("/5527998803900");
    expect(u.searchParams.get("text")).toBe(MENSAGEM);
    expect([...u.searchParams.keys()]).toEqual(["text"]);
  });

  it("sem API do WhatsApp, webhook ou dependência nova", () => {
    const fontes = ["src/content/whatsapp.ts", "src/components/WhatsAppComercial.tsx"]
      .map((f) => readFileSync(resolve(process.cwd(), f), "utf8")).join("\n")
      .replace(/\/\*[\s\S]*?\*\/|^\s*\/\/.*$/gm, ""); // só código, sem comentários
    expect(fontes).not.toMatch(/api\.whatsapp\.com|graph\.facebook\.com|fetch\(|supabase|webhook/i);
    const pkg = JSON.parse(readFileSync(resolve(process.cwd(), "package.json"), "utf8"));
    expect(Object.keys({ ...pkg.dependencies, ...pkg.devDependencies }).filter((d) => /whatsapp|wa-/i.test(d))).toEqual([]);
  });
});

describe("WhatsApp comercial — botão flutuante", () => {
  it.each([
    "/", "/oportunidades", "/oportunidades/pharmacy", "/oportunidades/womens-clothing", "/selecionar-localidade", "/em-breve", "/quem-somos",
    "/como-funciona", "/trabalhe-conosco", "/contato", "/ajuda", "/legal", "/legal/acordo-mestre-parceiros",
    "/parceiros", "/contato/",
  ])("aparece na página pública %s", (rota) => {
    expect(whatsAppFlutuanteVisivel(rota)).toBe(true);
    flutuante(rota);
    const a = screen.getByRole("link", { name: "Fale com a SmallFlags pelo WhatsApp" });
    expect(a.getAttribute("href")).toBe(URL_ESPERADA);
    expect(a.getAttribute("target")).toBe("_blank");
    expect(a.getAttribute("rel")).toBe("noopener noreferrer");
    expect(a.className).toMatch(/\bfixed\b/);
    expect(a.className).toMatch(/\bz-40\b/); // abaixo do cabeçalho fixo (z-50)
    expect(a.querySelector("svg")?.getAttribute("aria-hidden")).not.toBeNull();
  });

  it.each([
    "/admin", "/admin/login", "/admin/solicitacoes", "/admin/segmentos",
    "/portal", "/portal/login", "/portal/dashboard", "/portal/equipe", "/portal/validar", "/portal/pedidos/abc/personalizacao",
    "/beneficios/validar/xyz", "/checkout", "/checkout/revisao",
    "/parceiros/acesso", "/parceiros/cadastro", "/parceiros/confirmar", "/parceiros/recuperar",
    "/parceiros/convite", "/parceiros/solicitacao", "/parceiros/painel",
    "/selecionar-estado", "/previa/precos-bandeiras", "/rota-inexistente", "/oportunidadesx",
    // 404 e slugs não reconhecidos sob prefixos públicos
    "/oportunidades/farmacia", "/oportunidades/inexistente", "/oportunidades/pharmacy/extra",
    "/oportunidades/womens_clothing", "/oportunidades/%E0%A4%A", "/legal/inexistente",
    "/legal/acordo-mestre-parceiros/extra", "/contato/extra",
  ])("não aparece em %s (admin, autenticado, checkout, fluxos ou 404)", (rota) => {
    expect(whatsAppFlutuanteVisivel(rota)).toBe(false);
    const { container } = flutuante(rota);
    expect(container.querySelector('[data-testid="whatsapp-flutuante"]')).toBeNull();
    expect(container.querySelector('a[href*="wa.me"]')).toBeNull();
  });

  it("todos os slugs reconhecidos pelo detalhe mostram o botão; a lista acompanha as rotas do App", () => {
    for (const slug of Object.values(NICHE_SLUG_BY_CODE)) {
      expect(whatsAppFlutuanteVisivel(`/oportunidades/${slug}`)).toBe(true);
    }
    const app = readFileSync(resolve(process.cwd(), "src/App.tsx"), "utf8");
    for (const rota of ["/legal/acordo-mestre-parceiros", "/oportunidades/:nicheSlug", "/contato", "/parceiros"]) {
      expect(app).toContain(`path="${rota}"`);
    }
  });

  it("está montado uma única vez no App, fora das rotas", () => {
    const app = readFileSync(resolve(process.cwd(), "src/App.tsx"), "utf8");
    expect(app.match(/<WhatsAppFlutuante \/>/g)).toHaveLength(1);
    expect(app.indexOf("<WhatsAppFlutuante />")).toBeGreaterThan(app.lastIndexOf("</Routes>"));
  });
});

describe("WhatsApp comercial — página de contato", () => {
  it("apresenta número, texto e o botão com o mesmo link do flutuante; preserva e-mail, telefone e redes", () => {
    render(
      <MemoryRouter initialEntries={["/contato"]}>
        <Contato />
      </MemoryRouter>,
    );
    const bloco = screen.getByTestId("contato-whatsapp");
    expect(within(bloco).getByRole("heading", { name: "WhatsApp" })).toBeDefined();
    expect(within(bloco).getByText("(27) 99880-3900")).toBeDefined();
    expect(bloco.textContent).toContain(
      "Entre em contato com nossa equipe para conhecer as oportunidades comerciais, esclarecer dúvidas e receber informações sobre as contratações.",
    );
    const botao = within(bloco).getByRole("link", { name: "Conversar pelo WhatsApp" });
    expect(botao.getAttribute("href")).toBe(URL_ESPERADA);
    expect(botao.getAttribute("target")).toBe("_blank");
    expect(botao.getAttribute("rel")).toBe("noopener noreferrer");
    expect(document.querySelector('a[href="mailto:grandevitoria@smallflags.com.br"]')).not.toBeNull();
    expect(document.querySelector('a[href="tel:+5527998803900"]')).not.toBeNull();
    const redes = document.querySelector("#redes-sociais") as HTMLElement;
    expect(within(redes).getByRole("heading", { name: "Instagram" })).toBeDefined();
    expect(within(redes).getByRole("heading", { name: "TikTok" })).toBeDefined();
  });
});

describe("WhatsApp comercial — o botão não cobre controles em nenhuma largura", () => {
  const rect = (left: number, top: number, w: number, h: number) =>
    ({ left, top, right: left + w, bottom: top + h, width: w, height: h, x: left, y: top, toJSON: () => ({}) }) as DOMRect;

  it("interseção com folga", () => {
    const b = rect(318, 772, 56, 56);
    expect(intersecta(b, rect(20, 780, 294, 40))).toBe(true); // termina a 4px do botão (folga 6)
    expect(intersecta(b, rect(20, 780, 280, 40))).toBe(false); // a 18px
    expect(intersecta(b, rect(330, 700, 40, 68))).toBe(true); // acima, a 4px
    expect(intersecta(b, rect(330, 600, 40, 60))).toBe(false);
  });

  it("detecta link, botão e campo sob o botão; ignora texto, invisíveis e o próprio botão", () => {
    document.body.innerHTML = `
      <p id="texto">texto</p><a id="link" href="/x">x</a><input id="campo" />
      <button id="oculto" style="visibility:hidden">o</button><a id="wa" href="https://wa.me/x">w</a>`;
    const wa = document.getElementById("wa")!;
    const sob = rect(318, 772, 56, 56), longe = rect(0, 0, 10, 10);
    const posicoes: Record<string, DOMRect> = { wa: sob, texto: sob, link: longe, campo: longe, oculto: sob };
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
      return posicoes[this.id] ?? longe;
    });
    expect(cobreControle(wa)).toBe(false); // só texto e controle invisível
    posicoes.link = rect(300, 790, 80, 30);
    expect(cobreControle(wa)).toBe(true);
    posicoes.link = longe;
    posicoes.campo = rect(250, 760, 100, 40);
    expect(cobreControle(wa)).toBe(true);
  });

  // Recolhimento em qualquer largura (25/11/2026): sem breakpoint e sem matchMedia.
  const montar = (posicoes: Record<string, DOMRect | null>) => {
    // rAF síncrono no jsdom; devolve 0 como "nenhum quadro pendente" (no navegador o id é zerado no callback).
    vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => { cb(0); return 0; });
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
      const chave = this.dataset.testid === "whatsapp-flutuante" ? "botao" : this.id;
      return posicoes[chave] ?? rect(0, 0, 10, 10);
    });
    render(
      <MemoryRouter initialEntries={["/contato"]}>
        <a id="cta" href="/parceiros">Seja parceiro</a>
        <WhatsAppFlutuante />
      </MemoryRouter>,
    );
    return document.querySelector('[data-testid="whatsapp-flutuante"]') as HTMLElement;
  };
  const rolar = () => act(async () => { window.dispatchEvent(new Event("scroll")); });
  const recolhido = (a: HTMLElement) => {
    const r = a.getAttribute("data-recolhido") === "true";
    expect(a.getAttribute("aria-hidden") === "true").toBe(r);
    expect(a.getAttribute("tabindex") === "-1").toBe(r);
    expect(/\binvisible\b/.test(a.className)).toBe(r);
    expect(/\bpointer-events-none\b/.test(a.className)).toBe(r);
    return r;
  };

  it.each([
    ["mobile (390 px) com controle sob o botão", 390, true, true],
    ["mobile (390 px) sem controle sob o botão", 390, false, false],
    ["tablet/notebook (1024 px) com controle sob o botão", 1024, true, true],
    ["desktop (1263 px, barra de rolagem clássica) com controle sob o botão", 1263, true, true],
    ["desktop (1920 px) sem controle sob o botão", 1920, false, false],
  ])("%s", async (_n, largura, temControle, recolhe) => {
    const botao = rect(largura - 76, 772, largura >= 640 ? 60 : 56, largura >= 640 ? 60 : 56);
    const a = montar({ botao, cta: temControle ? rect(largura - 300, 770, 290, 44) : null });
    await rolar();
    expect(a).not.toBeNull(); // nunca desmontado: só recolhido
    expect(recolhido(a)).toBe(recolhe);
    // tamanho, cores e posição não mudam
    expect(a.className).toMatch(/h-14 w-14/);
    expect(a.className).toMatch(/sm:h-\[3\.75rem\] sm:w-\[3\.75rem\]/);
    expect(a.className).toMatch(/bg-\[#25D366\]/);
    expect(a.style.right).toContain("1rem");
  });

  it("funciona sem matchMedia e reaparece quando a área fica livre", async () => {
    vi.stubGlobal("matchMedia", undefined);
    const pos: Record<string, DOMRect | null> = { botao: rect(1187, 768, 60, 60), cta: rect(364, 766, 828, 64) };
    const a = montar(pos);
    await rolar();
    expect(recolhido(a)).toBe(true);
    pos.cta = rect(364, 500, 828, 64); // rolou: a linha saiu de baixo do botão
    await rolar();
    expect(recolhido(a)).toBe(false);
    pos.cta = rect(364, 790, 828, 64); // voltou a ficar sob o botão
    await act(async () => { window.dispatchEvent(new Event("resize")); });
    expect(recolhido(a)).toBe(true);
  });

  it("com foco de teclado no próprio botão, ele não some", async () => {
    const pos: Record<string, DOMRect | null> = { botao: rect(1187, 768, 60, 60), cta: null };
    const a = montar(pos);
    await rolar();
    expect(recolhido(a)).toBe(false);
    a.focus();
    pos.cta = rect(364, 766, 828, 64);
    await rolar();
    expect(recolhido(a)).toBe(false);
  });

  it("o componente não usa mais breakpoint para recolher", () => {
    const fonte = readFileSync(resolve(process.cwd(), "src/components/WhatsAppComercial.tsx"), "utf8");
    expect(fonte).not.toMatch(/matchMedia|MOBILE_MEDIA|max-width/);
  });
});
