#!/usr/bin/env node
/**
 * SEO P0 — gera, DEPOIS do `vite build`, o HTML inicial de cada rota com os
 * metadados próprios (título, descrição, canonical, robots, Open Graph), a
 * página 404, o robots.txt e o sitemap.xml. Fonte única: src/seo/rotasSeo.json.
 *
 * ESCOPO (SEO P0/P0.1): este gerador NÃO pré-renderiza o conteúdo textual do
 * React. Só o <head> de cada rota é escrito no HTML inicial; o corpo continua
 * sendo o mesmo #root vazio da SPA, renderizado no navegador (o Google indexa
 * o texto depois de executar o JavaScript). Navegação, estilos e
 * comportamento não mudam. O pré-render completo das páginas institucionais
 * é melhoria posterior, fora deste patch.
 *
 * Entrega HTTP (vercel.json, `cleanUrls: true`): rota estática = arquivo
 * `<rota>.html`; rota dinâmica = rewrite para `/_seo/<modelo>` (SEM `.html`,
 * regra da Vercel com cleanUrls), servido pelo arquivo `_seo/<modelo>.html`.
 * Ao final, `verificarEntregaHttp` confere React Router (src/App.tsx) ×
 * catálogo × vercel.json × arquivos gerados e FALHA o build se: uma rota React
 * não tiver classificação SEO; uma entrada do catálogo não tiver rota React;
 * existir rewrite ou redirecionamento diferente dos previstos no catálogo
 * (inclusive qualquer rewrite geral); um destino não tiver arquivo; ou o
 * X-Robots-Tag divergir da classificação.
 *
 *   uso: node scripts/seo/gerar-paginas-seo.mjs [diretorio-dist]   (padrão: dist)
 *
 * Falha (código 1) se o index.html não tiver os marcadores de SEO ou se a
 * fonte de rotas for incoerente: build com metadado errado não publica.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const INICIO = "<!-- seo:inicio -->";
const FIM = "<!-- seo:fim -->";

const esc = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function carregarFonte(caminho = join(RAIZ, "src/seo/rotasSeo.json")) {
  const f = JSON.parse(readFileSync(caminho, "utf8"));
  const vistos = new Set();
  for (const r of f.rotas) {
    if (vistos.has(r.caminho)) throw new Error(`rota duplicada: ${r.caminho}`);
    vistos.add(r.caminho);
    if (!["index, follow", "noindex, follow", "noindex, nofollow"].includes(r.robots)) {
      throw new Error(`robots inválido em ${r.caminho}`);
    }
    if (r.robots === "index, follow" && (!r.descricao || r.caminho.includes(":"))) {
      throw new Error(`rota indexável sem descrição ou dinâmica: ${r.caminho}`);
    }
    if (r.caminho.includes(":") && !/^[a-z0-9-]+$/.test(r.modelo ?? "")) {
      throw new Error(`rota dinâmica sem modelo: ${r.caminho}`);
    }
  }
  if (!/^https:\/\/[a-z0-9.-]+$/.test(f.origem)) throw new Error("origem inválida");
  return f;
}

/** Bloco <head> de SEO de uma rota (ou da página 404). */
export function cabecalhoSeo(fonte, r) {
  const indexavel = r.robots === "index, follow";
  const descricao = r.descricao ?? fonte.padrao.descricao;
  const linhas = [
    `<title>${esc(r.titulo)}</title>`,
    `<meta name="description" content="${esc(descricao)}" />`,
    `<meta name="robots" content="${esc(r.robots)}" />`,
  ];
  if (indexavel) {
    const url = fonte.origem + (r.caminho === "/" ? "/" : r.caminho);
    linhas.push(
      `<link rel="canonical" href="${esc(url)}" />`,
      `<meta property="og:type" content="website" />`,
      `<meta property="og:site_name" content="${esc(fonte.nomeSite)}" />`,
      `<meta property="og:locale" content="pt_BR" />`,
      `<meta property="og:title" content="${esc(r.titulo)}" />`,
      `<meta property="og:description" content="${esc(descricao)}" />`,
      `<meta property="og:url" content="${esc(url)}" />`,
      `<meta property="og:image" content="${esc(fonte.origem + fonte.imagemOg)}" />`,
      `<meta name="twitter:card" content="summary" />`,
    );
  }
  return linhas.map((l) => `    ${l}`).join("\n");
}

export function aplicarCabecalho(html, bloco) {
  const i = html.indexOf(INICIO);
  const j = html.indexOf(FIM);
  if (i < 0 || j < i || html.indexOf(INICIO, i + 1) >= 0) throw new Error("marcadores de SEO ausentes ou repetidos no index.html");
  return `${html.slice(0, i + INICIO.length)}\n${bloco}\n    ${html.slice(j)}`;
}

/** Arquivo de saída de uma rota estática: "/" -> index.html, "/a/b" -> a/b.html (cleanUrls). */
export function arquivoDaRota(r) {
  if (r.caminho.includes(":")) return `_seo/${r.modelo}.html`;
  return r.caminho === "/" ? "index.html" : `${r.caminho.slice(1)}.html`;
}

export function robotsTxt(fonte) {
  return ["User-agent: *", "Allow: /", "Disallow: /api/", "", `Sitemap: ${fonte.origem}/sitemap.xml`, ""].join("\n");
}

export function sitemapXml(fonte) {
  const urls = fonte.rotas
    .filter((r) => r.robots === "index, follow")
    .map((r) => `  <url><loc>${esc(fonte.origem + (r.caminho === "/" ? "/" : r.caminho))}</loc></url>`);
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join("\n")}\n</urlset>\n`;
}

/** Caminhos declarados no React Router (`path="..."` em src/App.tsx), sem o fallback "*". */
export function rotasDoReact(appTsx) {
  return [...appTsx.matchAll(/\bpath="([^"]+)"/g)].map((m) => m[1]).filter((p) => p !== "*");
}

const chave = (o) => JSON.stringify(o);

/**
 * Coerência entre React Router, a fonte de SEO, o vercel.json e os arquivos
 * gerados em `dist`. Devolve a lista de problemas (vazia = coerente).
 *
 * Exceções documentadas: o fallback "*" (página não encontrada, servida pelo
 * 404.html) e as rotas React que só cobrem localmente um redirecionamento já
 * feito pelo servidor (`redirecionamentos` do catálogo).
 */
export function verificarEntregaHttp(dist, fonte, vercel, appTsx = readFileSync(join(RAIZ, "src/App.tsx"), "utf8")) {
  const problemas = [];
  const existe = (rel) => existsSync(join(dist, rel));
  const rewrites = vercel.rewrites ?? [];
  const redirects = vercel.redirects ?? [];
  const headers = vercel.headers ?? [];

  // 1) React Router x catálogo (nos dois sentidos).
  const react = rotasDoReact(appTsx);
  const catalogadas = new Set(fonte.rotas.map((r) => r.caminho));
  const redirecionadas = new Set(fonte.redirecionamentos.map((r) => r.de));
  for (const c of react) {
    if (!catalogadas.has(c) && !redirecionadas.has(c)) problemas.push(`rota React sem classificação SEO: ${c}`);
  }
  for (const c of catalogadas) {
    if (!react.includes(c)) problemas.push(`entrada do catálogo sem rota React (geraria HTML 200 para endereço inexistente): ${c}`);
  }
  for (const r of fonte.removidas) {
    if (react.includes(r.caminho)) problemas.push(`URL removida ainda declarada no React: ${r.caminho}`);
  }

  // 2) Rewrites: EXATAMENTE os das rotas dinâmicas do catálogo (sem nenhum adicional).
  const rwEsperados = fonte.rotas.filter((r) => r.caminho.includes(":")).map((r) => ({ source: r.caminho, destination: `/_seo/${r.modelo}` }));
  const rwEsp = new Set(rwEsperados.map(chave));
  const rwAtu = rewrites.map((r) => chave({ source: r.source, destination: r.destination }));
  for (const [i, k] of rwAtu.entries()) {
    if (!rwEsp.has(k)) problemas.push(`rewrite não previsto no catálogo: ${rewrites[i].source} -> ${rewrites[i].destination}`);
    if (rwAtu.indexOf(k) !== i) problemas.push(`rewrite repetido: ${rewrites[i].source}`);
    if (Object.keys(rewrites[i]).some((x) => !["source", "destination"].includes(x))) problemas.push(`rewrite com campos extras: ${rewrites[i].source}`);
  }
  for (const r of rwEsperados) if (!rwAtu.includes(chave(r))) problemas.push(`rota dinâmica sem rewrite para ${r.destination}: ${r.source}`);
  for (const r of rewrites) {
    if (vercel.cleanUrls === true && /\.html$/.test(r.destination)) {
      problemas.push(`cleanUrls com destino .html (a Vercel exige o destino sem extensão): ${r.destination}`);
      continue;
    }
    const arquivo = vercel.cleanUrls === true ? `${r.destination.slice(1)}.html` : r.destination.slice(1);
    if (!existe(arquivo)) problemas.push(`destino do rewrite sem arquivo gerado: ${r.destination} -> ${arquivo}`);
  }

  // 3) Redirecionamentos: EXATAMENTE os do catálogo, permanentes (308).
  const rdEsperados = fonte.redirecionamentos.map((r) => chave({ source: r.de, destination: r.para, permanent: true }));
  const rdAtu = redirects.map((r) => chave({ source: r.source, destination: r.destination, permanent: r.permanent }));
  for (const [i, k] of rdAtu.entries()) {
    if (!rdEsperados.includes(k)) problemas.push(`redirecionamento não previsto no catálogo: ${redirects[i].source} -> ${redirects[i].destination}`);
    if (rdAtu.indexOf(k) !== i) problemas.push(`redirecionamento repetido: ${redirects[i].source}`);
    if (Object.keys(redirects[i]).some((x) => !["source", "destination", "permanent"].includes(x))) {
      problemas.push(`redirecionamento com campos extras: ${redirects[i].source}`);
    }
  }
  for (const [i, k] of rdEsperados.entries()) {
    if (!rdAtu.includes(k)) problemas.push(`redirecionamento obrigatório ausente ou divergente: ${fonte.redirecionamentos[i].de} -> ${fonte.redirecionamentos[i].para}`);
  }

  // 4) Arquivos e cabeçalhos por rota.
  for (const r of fonte.rotas) {
    if (r.caminho.includes(":")) {
      // coberta pelos rewrites acima
    } else if (!existe(arquivoDaRota(r))) {
      problemas.push(`rota estática sem arquivo gerado: ${r.caminho}`);
    }
    const xrt = headers.find((h) => h.source === r.caminho)?.headers?.find((h) => h.key === "X-Robots-Tag")?.value;
    const esperado = r.robots === "index, follow" ? undefined : r.robots;
    if (xrt !== esperado) problemas.push(`X-Robots-Tag divergente em ${r.caminho}: ${xrt ?? "ausente"} (esperado ${esperado ?? "ausente"})`);
  }
  if (!existe("404.html")) problemas.push("404.html ausente");
  return problemas;
}

export function gerar(
  dist,
  fonte = carregarFonte(),
  vercel = JSON.parse(readFileSync(join(RAIZ, "vercel.json"), "utf8")),
  appTsx = readFileSync(join(RAIZ, "src/App.tsx"), "utf8"),
) {
  const base = readFileSync(join(dist, "index.html"), "utf8");
  aplicarCabecalho(base, ""); // valida marcadores antes de escrever qualquer coisa
  const escritos = [];
  const escrever = (rel, conteudo) => {
    const alvo = join(dist, rel);
    mkdirSync(dirname(alvo), { recursive: true });
    writeFileSync(alvo, conteudo);
    escritos.push(rel);
  };
  const modelos = new Set();
  for (const r of fonte.rotas) {
    const rel = arquivoDaRota(r);
    if (r.modelo) {
      if (modelos.has(r.modelo)) continue; // um modelo serve várias rotas dinâmicas iguais
      modelos.add(r.modelo);
    }
    escrever(rel, aplicarCabecalho(base, cabecalhoSeo(fonte, r)));
  }
  escrever("404.html", aplicarCabecalho(base, cabecalhoSeo(fonte, { ...fonte.naoEncontrada, caminho: "/404" })));
  escrever("robots.txt", robotsTxt(fonte));
  escrever("sitemap.xml", sitemapXml(fonte));
  const problemas = verificarEntregaHttp(dist, fonte, vercel, appTsx);
  if (problemas.length) throw new Error(`entrega HTTP incoerente:\n  - ${problemas.join("\n  - ")}`);
  return escritos;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const dist = resolve(process.argv[2] ?? join(RAIZ, "dist"));
    const escritos = gerar(dist);
    console.log(`seo: ${escritos.length} arquivos gerados em ${dist}`);
  } catch (e) {
    console.error(`seo: falhou — ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
  }
}
