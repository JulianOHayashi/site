import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, cleanup, fireEvent, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import QuemSomos from "../pages/institucional/QuemSomos";
import ComoFunciona from "../pages/institucional/ComoFunciona";
import TrabalheConosco from "../pages/institucional/TrabalheConosco";
import Contato from "../pages/institucional/Contato";
import Ajuda from "../pages/institucional/Ajuda";
import Home from "../pages/Home";
import SiteHeader from "../components/SiteHeader";
import SiteFooter from "../components/SiteFooter";
import {
  FORMACAO_REFERENCIA,
  TOTAL_UNIDADES_REFERENCIA,
} from "../content/institucional";


/**
 * Incremento institucional público: rotas novas, header, footer e Home.
 * Só frontend — nenhuma destas páginas coleta dados.
 */

afterEach(() => cleanup());

const PAGINAS = [
  ["/quem-somos", QuemSomos, /ecossistema/i],
  ["/como-funciona", ComoFunciona, /como a smallflags funciona/i],
  ["/trabalhe-conosco", TrabalheConosco, /construa a smallflags/i],
  ["/contato", Contato, /caminho certo/i],
  ["/ajuda", Ajuda, /central de ajuda/i],
] as const;

/** jsdom não implementa matchMedia; com reduced-motion o Revelar exibe tudo. */
function stubReducedMotion() {
  vi.stubGlobal("matchMedia", (q: string) => ({
    matches: true,
    media: q,
    addEventListener() {},
    removeEventListener() {},
  }));
}

afterEach(() => vi.unstubAllGlobals());

function montar(caminho: string, Pagina: () => JSX.Element) {
  return render(
    <MemoryRouter initialEntries={[caminho]}>
      <Pagina />
    </MemoryRouter>
  );
}

const APP_SRC = readFileSync(resolve(__dirname, "../App.tsx"), "utf8");
const ROTAS = new Set(
  [...APP_SRC.matchAll(/<Route\s+path="([^"]+)"/g)].map((m) => m[1])
);

describe("rotas institucionais", () => {
  it("as cinco rotas estão registradas explicitamente no App", () => {
    for (const [caminho] of PAGINAS) expect(ROTAS.has(caminho)).toBe(true);
  });

  for (const [caminho, Pagina, titulo] of PAGINAS) {
    it(`${caminho}: um único h1, header e footer globais, nenhum formulário`, () => {
      const { container } = montar(caminho, Pagina);
      const h1s = screen.getAllByRole("heading", { level: 1 });
      expect(h1s).toHaveLength(1);
      expect(h1s[0].textContent).toMatch(titulo);
      expect(container.querySelector("header")).not.toBeNull();
      expect(screen.getByRole("contentinfo")).toBeDefined();
      expect(container.querySelector("form, input, textarea, select")).toBeNull();
    });
  }
});

describe("sem dados inventados", () => {
  it("contato e trabalhe conosco não publicam telefone, e-mail ou endereço", () => {
    for (const Pagina of [Contato, TrabalheConosco]) {
      const { container } = montar("/", Pagina);
      const texto = container.querySelector("main")!.textContent ?? "";
      expect(texto).not.toMatch(/@|\(\d{2}\)|\d{4,5}-\d{4}|whatsapp|instagram|linkedin/i);
      expect(container.querySelector('a[href^="mailto:"], a[href^="tel:"]')).toBeNull();
      cleanup();
    }
  });

  it("trabalhe conosco não afirma vagas abertas", () => {
    montar("/trabalhe-conosco", TrabalheConosco);
    expect(screen.getByText(/não há processos seletivos abertos/i)).toBeDefined();
    expect(screen.getByText(/serão publicadas aqui/i)).toBeDefined();
  });

  it("a formação de referência soma 84 em seis nichos inteiros", () => {
    expect(FORMACAO_REFERENCIA).toHaveLength(6);
    expect(TOTAL_UNIDADES_REFERENCIA).toBe(84);
    montar("/como-funciona", ComoFunciona);
    expect(screen.getAllByText(/contratado\s+integralmente/i).length).toBeGreaterThan(0);
  });
});

describe("SiteHeader", () => {
  it("expõe os destinos principais e mantém Entrar e o CTA", () => {
    montar("/", SiteHeader);
    const nav = screen.getByRole("navigation", { name: "Principal" });
    for (const nome of [/como funciona/i, /para empresas/i, /oportunidades/i]) {
      expect(within(nav).getByRole("link", { name: nome })).toBeDefined();
    }
    expect(screen.getByRole("link", { name: /^entrar$/i }).getAttribute("href")).toBe(
      "/portal/login"
    );
    expect(
      screen.getByRole("link", { name: /quero ser parceiro/i }).getAttribute("href")
    ).toBe("/parceiros/cadastro");
  });

  it("grupo Institucional abre por clique, fecha com Esc e devolve o foco", () => {
    montar("/", SiteHeader);
    const botao = screen.getByRole("button", { name: /institucional/i });
    expect(botao.getAttribute("aria-expanded")).toBe("false");
    expect(screen.queryByRole("link", { name: /quem somos/i })).toBeNull();

    fireEvent.click(botao);
    expect(botao.getAttribute("aria-expanded")).toBe("true");
    const lista = document.getElementById(botao.getAttribute("aria-controls")!);
    expect(lista).not.toBeNull();
    for (const nome of [/quem somos/i, /trabalhe conosco/i, /ajuda/i, /contato/i]) {
      expect(within(lista!).getByRole("link", { name: nome })).toBeDefined();
    }

    fireEvent.keyDown(document, { key: "Escape" });
    expect(botao.getAttribute("aria-expanded")).toBe("false");
    expect(document.activeElement).toBe(botao);
  });

  it("grupo fecha com clique fora", () => {
    montar("/", SiteHeader);
    const botao = screen.getByRole("button", { name: /institucional/i });
    fireEvent.click(botao);
    fireEvent.mouseDown(document.body);
    expect(botao.getAttribute("aria-expanded")).toBe("false");
  });

  it("menu móvel lista todos os destinos e fecha com Esc", () => {
    montar("/", SiteHeader);
    const botao = screen.getByRole("button", { name: /abrir menu/i });
    fireEvent.click(botao);
    const menu = screen.getByRole("navigation", { name: "Menu" });
    for (const nome of [
      /como funciona/i,
      /para empresas/i,
      /oportunidades/i,
      /quem somos/i,
      /trabalhe conosco/i,
      /ajuda/i,
      /contato/i,
    ]) {
      expect(within(menu).getByRole("link", { name: nome })).toBeDefined();
    }
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("navigation", { name: "Menu" })).toBeNull();
    expect(document.activeElement).toBe(screen.getByRole("button", { name: /abrir menu/i }));
  });
});

describe("SiteFooter", () => {
  it("todos os links apontam para rotas existentes e não há link legal falso", () => {
    const { container } = montar("/", SiteFooter);
    const hrefs = [...container.querySelectorAll("a")].map((a) => a.getAttribute("href")!);
    expect(hrefs.length).toBeGreaterThan(0);
    for (const href of hrefs) expect(ROTAS.has(href)).toBe(true);
    expect(screen.queryByRole("link", { name: /privacidade|termos/i })).toBeNull();
    expect(container.textContent).toContain("© 2026 SmallFlags");
    expect(container.textContent).not.toMatch(/conteúdo provisório/i);
  });

  it("links do header também apontam para rotas existentes", () => {
    const { container } = montar("/", SiteHeader);
    fireEvent.click(screen.getByRole("button", { name: /institucional/i }));
    const hrefs = [...container.querySelectorAll("a")]
      .map((a) => a.getAttribute("href")!.split("?")[0]);
    for (const href of hrefs) expect(ROTAS.has(href)).toBe(true);
  });
});

describe("Home", () => {
  it("usa o footer global, liga ao institucional e preserva as 84 unidades", () => {
    stubReducedMotion();
    const { container } = montar("/", Home);
    expect(container.querySelectorAll("footer")).toHaveLength(1);
    expect(container.textContent).not.toMatch(/conteúdo provisório/i);
    expect(screen.getByRole("heading", { name: /conheça a smallflags/i })).toBeDefined();
    const main = container.querySelector("footer")!.parentElement!;
    const hrefs = [...main.querySelectorAll("a")].map((a) => a.getAttribute("href"));
    for (const destino of ["/quem-somos", "/como-funciona", "/trabalhe-conosco"]) {
      expect(hrefs).toContain(destino);
    }
    expect(screen.getByText(/seis nichos · 84 unidades/i)).toBeDefined();
  });
});

describe("fase visual 1", () => {
  it("a Home apresenta a região ativa e os cinco municípios no hero", () => {
    stubReducedMotion();
    montar("/", Home);
    const hero = screen.getByRole("complementary", { name: /região comercial ativa/i });
    for (const c of ["Vitória", "Vila Velha", "Serra", "Cariacica", "Viana"]) {
      expect(within(hero).getByText(c)).toBeDefined();
    }
  });

  it("a Home lista os seis nichos com as unidades da formação de referência", () => {
    stubReducedMotion();
    const { container } = montar("/", Home);
    const secao = container.querySelector("#nichos-titulo")!.closest("section")!;
    for (const n of FORMACAO_REFERENCIA) {
      expect(within(secao).getByRole("heading", { name: n.nome })).toBeDefined();
    }
    // Supermercado é o único com 24; os demais com 12.
    expect(within(secao).getAllByText("24")).toHaveLength(1);
    expect(within(secao).getAllByText("12")).toHaveLength(5);
  });

  it("a relação Site↔App separa os domínios e nomeia o ponto de encontro", () => {
    montar("/quem-somos", QuemSomos);
    const comercial = screen.getByRole("region", { name: /trilha comercial/i });
    const operacional = screen.getByRole("region", { name: /trilha operacional/i });
    expect(within(comercial).getByText("SmallFlags Site")).toBeDefined();
    expect(within(operacional).getByText("SmallFlags App")).toBeDefined();
    // O Site não pode aparecer na trilha operacional, nem o App na comercial.
    expect(within(comercial).queryByText("SmallFlags App")).toBeNull();
    expect(within(operacional).queryByText("SmallFlags Site")).toBeNull();
    expect(screen.getByText(/onde as duas se encontram/i)).toBeDefined();
  });

  it("as etapas de Como funciona ficam numa lista ordenada e anunciam o número", () => {
    const { container } = montar("/como-funciona", ComoFunciona);
    const passos = container.querySelectorAll("ol > li");
    expect(passos).toHaveLength(5);
    expect(screen.getByRole("heading", { name: /etapa 1: localidade/i })).toBeDefined();
    expect(screen.getByRole("heading", { name: /etapa 5: site e app/i })).toBeDefined();
  });
});

describe("marca pública SmallFlags", () => {
  /**
   * A marca pública é SmallFlags. Identificadores técnicos internos (env vars
   * BDFLOW_*, chaves de storage bdflow_*, campos bdflow*Cents, protocolo do
   * gateway) continuam com o codinome interno de propósito, e este teste não
   * os cobre — ele vigia só o que o usuário lê.
   */
  const PAGINAS_PUBLICAS = [
    ["/", Home],
    ["/quem-somos", QuemSomos],
    ["/como-funciona", ComoFunciona],
    ["/trabalhe-conosco", TrabalheConosco],
    ["/contato", Contato],
    ["/ajuda", Ajuda],
  ] as const;

  for (const [caminho, Pagina] of PAGINAS_PUBLICAS) {
    it(`${caminho} não exibe a marca antiga em texto nem em rótulo acessível`, () => {
      stubReducedMotion();
      const { container } = montar(caminho, Pagina);
      expect(container.textContent).not.toMatch(/bd\s*flow/i);
      const rotulos = [...container.querySelectorAll("[aria-label]")].map((e) =>
        e.getAttribute("aria-label")
      );
      for (const r of rotulos) expect(r).not.toMatch(/bd\s*flow/i);
    });
  }

  it("o wordmark do header e do rodapé diz SmallFlags", () => {
    const { container } = montar("/", SiteHeader);
    expect(
      within(container).getByRole("link", { name: /smallflags — início/i }).textContent
    ).toBe("SmallFlags");
    cleanup();
    const rodape = montar("/", SiteFooter);
    expect(
      within(rodape.container).getByRole("link", { name: /smallflags — início/i })
        .textContent
    ).toBe("SmallFlags");
  });
});
