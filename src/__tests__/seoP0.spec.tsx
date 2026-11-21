import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, cleanup, act } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useNavigate } from "react-router-dom";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { matchPath } from "react-router-dom";

import fonte from "../seo/rotasSeo.json";
import SeoCabecalho, { rotaSeoDe } from "../seo/SeoCabecalho";
import NaoEncontrada from "../pages/NaoEncontrada";
// @ts-expect-error módulo .mjs do script de build, sem tipos
import * as gerador from "../../scripts/seo/gerar-paginas-seo.mjs";

/**
 * SEO P0 — identidade pública e limpeza da indexação. Evidência LOCAL: o
 * comportamento real da Vercel (cleanUrls, 404.html, cabeçalhos) fica
 * PENDENTE_DE_TESTE_EM_STAGING.
 */
const RAIZ = resolve(__dirname, "../..");
const ler = (p: string) => readFileSync(join(RAIZ, p), "utf8");
const ORIGEM = "https://www.smallflags.com.br";
type Rota = { caminho: string; titulo: string; descricao?: string; robots: string; modelo?: string };
const ROTAS = fonte.rotas as Rota[];
const INDEXAVEIS = ROTAS.filter((r) => r.robots === "index, follow");
const vercel = JSON.parse(ler("vercel.json")) as {
  cleanUrls: boolean;
  trailingSlash: boolean;
  redirects: Array<{ source: string; destination: string; permanent: boolean }>;
  rewrites: Array<{ source: string; destination: string }>;
  headers: Array<{ source: string; headers: Array<{ key: string; value: string }> }>;
};
const casa = (padrao: string, caminho: string) => matchPath({ path: padrao, end: true }, caminho) !== null;
/** Caminhos declarados no React Router (App.tsx), sem o fallback "*". */
const rotasDoApp = () => [...ler("src/App.tsx").matchAll(/path="([^"]+)"/g)].map((m) => m[1]).filter((p) => p !== "*");

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("fonte única de SEO", () => {
  it("React Router × catálogo: toda rota do App.tsx classificada e nenhuma entrada do catálogo sem rota", () => {
    const caminhos = rotasDoApp();
    const conhecidos = new Set([...ROTAS.map((r) => r.caminho), ...fonte.redirecionamentos.map((r) => r.de)]);
    expect(caminhos.filter((c) => !conhecidos.has(c))).toEqual([]);
    // Entrada sem rota publicaria HTML 200 para um endereço que não existe.
    expect(ROTAS.map((r) => r.caminho).filter((c) => !caminhos.includes(c))).toEqual([]);
    for (const r of fonte.removidas) expect(caminhos).not.toContain(r.caminho);
  });

  it("indexáveis: exatamente as páginas institucionais e legais públicas previstas", () => {
    expect(INDEXAVEIS.map((r) => r.caminho)).toEqual([
      "/", "/quem-somos", "/como-funciona", "/parceiros", "/contato", "/ajuda", "/trabalhe-conosco", "/legal",
    ]);
    expect(gerador.carregarFonte()).toBeTruthy();
  });

  it("Home: título e descrição propostos, coerentes com o H1 visível", () => {
    const home = ROTAS[0];
    expect(home.titulo).toBe("SmallFlags | Publicidade em Veículos com Bandeiras");
    expect(home.descricao).toBe(
      "A SmallFlags conecta empresas anunciantes à publicidade visual por meio de bandeiras instaladas em veículos. Conheça oportunidades comerciais por nicho e região.");
    expect(ler("src/pages/Home.tsx")).toMatch(/Publicidade em veículos com\{" "\}\s*<span[^>]*>bandeiras\.<\/span>/);
  });

  it("títulos e descrições únicos, de tamanho adequado, sem resíduo da loja nem alegação não comprovada", () => {
    const titulos = INDEXAVEIS.map((r) => r.titulo);
    const descricoes = INDEXAVEIS.map((r) => r.descricao ?? "");
    expect(new Set(titulos).size).toBe(titulos.length);
    expect(new Set(descricoes).size).toBe(descricoes.length);
    for (const r of INDEXAVEIS) {
      expect(r.titulo.length).toBeLessThanOrEqual(60);
      expect(r.titulo).toMatch(/SmallFlags/);
      expect((r.descricao ?? "").length).toBeGreaterThanOrEqual(70);
      expect((r.descricao ?? "").length).toBeLessThanOrEqual(165);
    }
    const tudo = JSON.stringify(fonte.rotas) + ler("index.html");
    expect(tudo).not.toMatch(/camis|t-?shirt|estampa|loja|produtos? (?:da|de) |nacional|todo o brasil|milhares|audi[eê]ncia|\d+\s*ve[ií]culos/i);
  });
});

describe("vercel.json: rotas, URLs antigas e diretivas", () => {
  it("sem rewrite geral: endereço desconhecido cai no 404 real; /api nunca é reescrita", () => {
    expect(vercel.cleanUrls).toBe(true);
    expect(vercel.trailingSlash).toBe(false);
    for (const r of vercel.rewrites) {
      expect(r.source).not.toMatch(/\(\.\*\)|\(\?!|^\/:path\*|^\/\*/);
      for (const p of ["/qualquer-coisa", "/api/internal/email-outbox-dispatch", "/produtos", "/produto/camisa-azul", "/classica", "/personalizar/x"]) {
        expect(casa(r.source, p)).toBe(false);
      }
    }
  });

  it("rotas dinâmicas reescritas para o modelo SEM extensão (regra da Vercel com cleanUrls)", () => {
    const dinamicas = ROTAS.filter((r) => r.caminho.includes(":"));
    expect(vercel.rewrites).toEqual(dinamicas.map((r) => ({ source: r.caminho, destination: `/_seo/${r.modelo}` })));
    expect(vercel.rewrites.filter((r) => /\.html$/.test(r.destination))).toEqual([]);
  });

  it("cleanUrls + destino terminado em .html é recusado (falha o build)", () => {
    const ruim = { ...vercel, rewrites: vercel.rewrites.map((r) => ({ ...r, destination: `${r.destination}.html` })) };
    const dir = mkdtempSync(join(tmpdir(), "seo-dist-"));
    try {
      writeFileSync(join(dir, "index.html"), ler("index.html"));
      expect(() => gerador.gerar(dir, gerador.carregarFonte(), ruim)).toThrow(/cleanUrls com destino \.html/);
      const geral = { ...vercel, rewrites: [...vercel.rewrites, { source: "/((?!api/).*)", destination: "/" }] };
      expect(() => gerador.gerar(dir, gerador.carregarFonte(), geral)).toThrow(/rewrite não previsto no catálogo/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("redirecionamento permanente (308) só com destino equivalente; URLs da loja sem destino => 404", () => {
    expect(vercel.redirects).toEqual([
      { source: "/selecionar-estado", destination: "/selecionar-localidade", permanent: true },
      { source: "/previa/precos-bandeiras", destination: "/oportunidades", permanent: true },
    ]);
    for (const { caminho } of fonte.removidas) {
      expect(vercel.redirects.some((r) => casa(r.source, caminho.replace(":slug", "x")))).toBe(false);
      expect(ROTAS.some((r) => casa(r.caminho, caminho.replace(":slug", "x")))).toBe(false);
    }
  });

  it("toda rota fora do índice tem X-Robots-Tag igual ao meta; indexáveis não têm; /api e /_seo com noindex", () => {
    const valor = (src: string) => vercel.headers.find((h) => h.source === src)?.headers.find((x) => x.key === "X-Robots-Tag")?.value;
    for (const r of ROTAS) expect(valor(r.caminho)).toBe(r.robots === "index, follow" ? undefined : r.robots);
    expect(valor("/api/(.*)")).toBe("noindex, nofollow");
    expect(valor("/_seo/(.*)")).toBe("noindex, nofollow");
    for (const r of INDEXAVEIS) {
      expect(vercel.headers.filter((h) => h.source !== "/api/(.*)" && h.source !== "/_seo/(.*)" && casa(h.source, r.caminho))).toEqual([]);
    }
  });

  it("áreas privadas e formulários sensíveis: noindex, nofollow", () => {
    for (const p of ["/admin", "/admin/login", "/portal/login", "/portal/dashboard", "/parceiros/cadastro", "/parceiros/convite",
      "/checkout", "/beneficios/validar/abc", "/portal/pedidos/1/personalizacao"]) {
      expect(rotaSeoDe(p)?.robots).toBe("noindex, nofollow");
    }
    for (const p of ["/oportunidades", "/oportunidades/farmacia", "/selecionar-localidade", "/em-breve", "/legal/acordo-mestre-parceiros"]) {
      expect(rotaSeoDe(p)?.robots).toBe("noindex, follow");
    }
  });
});

describe("gerador do HTML inicial, 404, robots.txt e sitemap.xml", () => {
  function distFalso() {
    const dir = mkdtempSync(join(tmpdir(), "seo-dist-"));
    const html = ler("index.html").replace('<script type="module" src="/src/main.tsx"></script>',
      '<script type="module" crossorigin src="/assets/index-abc.js"></script>');
    writeFileSync(join(dir, "index.html"), html);
    return dir;
  }

  it("cada rota estática recebe o próprio <head>; indexáveis com canonical www e Open Graph; corpo da SPA intacto", () => {
    const dir = distFalso();
    try {
      gerador.gerar(dir);
      for (const r of ROTAS) {
        const arq = join(dir, gerador.arquivoDaRota(r));
        expect(existsSync(arq)).toBe(true);
        const h = readFileSync(arq, "utf8");
        expect(h.match(/<title>/g)).toHaveLength(1);
        expect(h).toContain(`<title>${r.titulo.replace(/&/g, "&amp;")}</title>`);
        expect(h).toContain(`<meta name="robots" content="${r.robots}" />`);
        expect(h).toContain('<div id="root"></div>');
        expect(h).toContain('src="/assets/index-abc.js"');
        if (r.robots === "index, follow") {
          const url = ORIGEM + (r.caminho === "/" ? "/" : r.caminho);
          expect(h).toContain(`<link rel="canonical" href="${url}" />`);
          expect(h).toContain(`<meta property="og:url" content="${url}" />`);
          expect(h).toContain(`<meta property="og:image" content="${ORIGEM}/brand/smallflags-icon.png" />`);
          expect(h).toContain(`<meta name="description" content="${r.descricao}" />`);
        } else {
          expect(h).not.toMatch(/rel="canonical"|og:/);
        }
      }
      expect(existsSync(join(RAIZ, "public/brand/smallflags-icon.png"))).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("404.html com noindex; robots.txt sem bloquear as áreas privadas (o noindex precisa ser lido); sitemap só com canônicas indexáveis", () => {
    const dir = distFalso();
    try {
      gerador.gerar(dir);
      const nf = readFileSync(join(dir, "404.html"), "utf8");
      expect(nf).toContain("<title>Página não encontrada | SmallFlags</title>");
      expect(nf).toContain('<meta name="robots" content="noindex, nofollow" />');
      const robots = readFileSync(join(dir, "robots.txt"), "utf8");
      expect(robots).toBe(`User-agent: *\nAllow: /\nDisallow: /api/\n\nSitemap: ${ORIGEM}/sitemap.xml\n`);
      expect(robots).not.toMatch(/Disallow: \/(admin|portal|parceiros|checkout)/);
      const sm = readFileSync(join(dir, "sitemap.xml"), "utf8");
      const locs = [...sm.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
      expect(locs).toEqual(INDEXAVEIS.map((r) => ORIGEM + (r.caminho === "/" ? "/" : r.caminho)));
      expect(sm).toMatch(/^<\?xml version="1.0" encoding="UTF-8"\?>\n<urlset xmlns="http:\/\/www.sitemaps.org\/schemas\/sitemap\/0.9">/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("React Router × catálogo × vercel.json × dist: toda rota tem entrega HTTP; destinos dos rewrites são arquivos gerados", () => {
    const dir = distFalso();
    try {
      gerador.gerar(dir);
      expect(gerador.verificarEntregaHttp(dir, gerador.carregarFonte(), vercel)).toEqual([]);
      for (const r of vercel.rewrites) expect(existsSync(join(dir, `${r.destination.slice(1)}.html`))).toBe(true);
      for (const c of rotasDoApp()) {
        const red = fonte.redirecionamentos.find((x) => x.de === c);
        if (red) {
          expect(vercel.redirects.find((x) => x.source === c)).toMatchObject({ destination: red.para, permanent: true });
          continue;
        }
        const entrega = c.includes(":")
          ? vercel.rewrites.find((r) => r.source === c)?.destination
          : `/${gerador.arquivoDaRota({ caminho: c }).replace(/\.html$/, "")}`;
        expect(entrega, c).toBeTruthy();
        expect(existsSync(join(dir, `${(entrega as string).slice(1) || "index"}.html`)), c).toBe(true);
      }
      // Rota sem estratégia de entrega => falha.
      const semEntrega = { ...vercel, rewrites: vercel.rewrites.slice(1) };
      expect(gerador.verificarEntregaHttp(dir, gerador.carregarFonte(), semEntrega).join()).toMatch(/rota dinâmica sem rewrite/);
      const semCabecalho = { ...vercel, headers: vercel.headers.filter((h) => h.source !== "/portal/login") };
      expect(gerador.verificarEntregaHttp(dir, gerador.carregarFonte(), semCabecalho).join()).toMatch(/X-Robots-Tag divergente em \/portal\/login/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("verificação do build (exata): rota React nova sem classificação, rewrite geral adicional e redirect removido falham", () => {
    const dir = distFalso();
    try {
      gerador.gerar(dir); // estado atual: coerente
      const f = () => gerador.carregarFonte();
      const app = ler("src/App.tsx");
      // 1. Nova rota React sem classificação SEO.
      const appNovo = app.replace('<Route path="/ajuda"', '<Route path="/nova-pagina" element={<Ajuda />} />\n        <Route path="/ajuda"');
      expect(() => gerador.gerar(dir, f(), vercel, appNovo)).toThrow(/rota React sem classificação SEO: \/nova-pagina/);
      // Entrada do catálogo sem rota React (HTML 200 para endereço inexistente).
      const fonteMorta = { ...f(), rotas: [...f().rotas, { caminho: "/fantasma", titulo: "X | SmallFlags", robots: "noindex, nofollow" }] };
      const vercelMorta = { ...vercel, headers: [...vercel.headers, { source: "/fantasma", headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow" }] }] };
      expect(() => gerador.gerar(dir, fonteMorta, vercelMorta, app)).toThrow(/entrada do catálogo sem rota React.*\/fantasma/);
      // 2. Rewrite geral adicional — rejeitado mesmo com destino existente.
      for (const source of ["/(.+)", "/:caminho*", "/((?!api/).*)", "/:a/:b"]) {
        const geral = { ...vercel, rewrites: [...vercel.rewrites, { source, destination: "/_seo/oportunidade-nicho" }] };
        expect(existsSync(join(dir, "_seo/oportunidade-nicho.html"))).toBe(true);
        expect(() => gerador.gerar(dir, f(), geral, app)).toThrow(/rewrite não previsto no catálogo/);
      }
      // 3. Redirecionamento obrigatório removido (ou alterado / extra).
      const semRedirect = { ...vercel, redirects: vercel.redirects.filter((r) => r.source !== "/selecionar-estado") };
      expect(() => gerador.gerar(dir, f(), semRedirect, app)).toThrow(/redirecionamento obrigatório ausente ou divergente: \/selecionar-estado/);
      const temporario = { ...vercel, redirects: vercel.redirects.map((r) => ({ ...r, permanent: false })) };
      expect(() => gerador.gerar(dir, f(), temporario, app)).toThrow(/redirecionamento obrigatório ausente ou divergente/);
      const extra = { ...vercel, redirects: [...vercel.redirects, { source: "/produtos", destination: "/", permanent: true }] };
      expect(() => gerador.gerar(dir, f(), extra, app)).toThrow(/redirecionamento não previsto no catálogo: \/produtos/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("o próprio comando do build (node scripts/seo/gerar-paginas-seo.mjs) sai com código 1 nesses casos", () => {
    const casos: Array<[string, (v: typeof vercel, app: string) => [typeof vercel, string]]> = [
      ["rota React sem classificação", (v, app) => [v, app.replace('<Route path="/ajuda"', '<Route path="/nova-pagina" element={<Ajuda />} />\n        <Route path="/ajuda"')]],
      ["rewrite não previsto", (v, app) => [{ ...v, rewrites: [...v.rewrites, { source: "/(.+)", destination: "/_seo/portal-pedido" }] }, app]],
      ["redirecionamento obrigatório ausente", (v, app) => [{ ...v, redirects: v.redirects.slice(1) }, app]],
    ];
    for (const [esperado, mutar] of casos) {
      const raiz = mkdtempSync(join(tmpdir(), "seo-raiz-"));
      try {
        for (const rel of ["scripts/seo/gerar-paginas-seo.mjs", "src/seo/rotasSeo.json", "index.html"]) {
          mkdirSync(dirname(join(raiz, rel)), { recursive: true });
          writeFileSync(join(raiz, rel), ler(rel));
        }
        const [v, app] = mutar(vercel, ler("src/App.tsx"));
        mkdirSync(join(raiz, "dist"), { recursive: true });
        writeFileSync(join(raiz, "vercel.json"), JSON.stringify(v));
        writeFileSync(join(raiz, "src/App.tsx"), app);
        writeFileSync(join(raiz, "dist/index.html"), ler("index.html"));
        const r = spawnSync(process.execPath, [join(raiz, "scripts/seo/gerar-paginas-seo.mjs")], { encoding: "utf8" });
        expect(r.status, esperado).toBe(1);
        expect(r.stderr).toContain(esperado);
      } finally {
        rmSync(raiz, { recursive: true, force: true });
      }
    }
  });

  it("idempotente; falha fechada sem os marcadores no index.html", () => {
    const dir = distFalso();
    try {
      gerador.gerar(dir);
      const a = readFileSync(join(dir, "quem-somos.html"), "utf8");
      gerador.gerar(dir);
      expect(readFileSync(join(dir, "quem-somos.html"), "utf8")).toBe(a);
      writeFileSync(join(dir, "index.html"), "<html><head><title>x</title></head></html>");
      expect(() => gerador.gerar(dir)).toThrow(/marcadores/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("o build roda o gerador depois do vite build", () => {
    expect(JSON.parse(ler("package.json")).scripts.build).toBe("vite build && node scripts/seo/gerar-paginas-seo.mjs");
  });
});

describe("navegação da SPA: <head> coerente e página não encontrada", () => {
  function Navegador({ para }: { para: { atual: (p: string) => void } }) {
    const nav = useNavigate();
    para.atual = nav;
    return null;
  }

  it("troca título, canonical, robots e Open Graph ao navegar; remove canonical/OG em rota privada e desconhecida", () => {
    const ref = { atual: (_p: string) => {} };
    render(
      <MemoryRouter initialEntries={["/quem-somos"]}>
        <SeoCabecalho />
        <Navegador para={ref} />
        <Routes><Route path="*" element={<NaoEncontrada />} /></Routes>
      </MemoryRouter>
    );
    expect(document.title).toBe("Quem somos | SmallFlags");
    expect(document.head.querySelector('link[rel="canonical"]')?.getAttribute("href")).toBe(`${ORIGEM}/quem-somos`);
    expect(document.head.querySelector('meta[name="robots"]')?.getAttribute("content")).toBe("index, follow");
    act(() => ref.atual("/portal/login"));
    expect(document.head.querySelector('meta[name="robots"]')?.getAttribute("content")).toBe("noindex, nofollow");
    expect(document.head.querySelector('link[rel="canonical"]')).toBeNull();
    expect(document.head.querySelector('meta[property="og:title"]')).toBeNull();
    act(() => ref.atual("/produto/camisa-azul"));
    expect(document.title).toBe("Página não encontrada | SmallFlags");
    expect(document.head.querySelector('meta[name="robots"]')?.getAttribute("content")).toBe("noindex, nofollow");
    expect(screen.getByRole("heading", { level: 1 }).textContent).toMatch(/Página não encontrada/);
    act(() => ref.atual("/"));
    expect(document.title).toBe("SmallFlags | Publicidade em Veículos com Bandeiras");
    expect(document.head.querySelector('link[rel="canonical"]')?.getAttribute("href")).toBe(`${ORIGEM}/`);
  });

  it("App: URLs da antiga loja e endereço inexistente mostram 'Página não encontrada' (sem redirecionar à Home)", async () => {
    vi.stubGlobal("matchMedia", (q: string) => ({ matches: true, media: q, addEventListener() {}, removeEventListener() {} }));
    const { default: App } = await import("../App");
    for (const p of ["/produtos", "/produto/camisa-azul", "/personalizar/x", "/classica", "/nao-existe"]) {
      window.history.pushState({}, "", p);
      render(<App />);
      expect(window.location.pathname).toBe(p);
      expect(screen.getByRole("heading", { level: 1 }).textContent).toMatch(/Página não encontrada/);
      cleanup();
    }
  });
});
