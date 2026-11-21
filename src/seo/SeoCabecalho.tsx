import { useEffect } from "react";
import { matchPath, useLocation } from "react-router-dom";
import fonte from "./rotasSeo.json";

/**
 * SEO P0 — mantém o <head> coerente durante a navegação da SPA.
 *
 * O HTML INICIAL de cada rota já chega do servidor com título, descrição,
 * canonical, robots e Open Graph (gerados no build por
 * scripts/seo/gerar-paginas-seo.mjs a partir de src/seo/rotasSeo.json). Este
 * componente só repete a mesma fonte quando o usuário navega sem recarregar,
 * para que o <head> nunca fique com os dados da página anterior. Não é a
 * fonte do noindex das áreas privadas: isso vem do HTML inicial e do
 * cabeçalho X-Robots-Tag (vercel.json).
 */

export type RotaSeo = {
  caminho: string;
  titulo: string;
  descricao?: string;
  robots: "index, follow" | "noindex, follow" | "noindex, nofollow";
  modelo?: string;
};

const ROTAS = fonte.rotas as RotaSeo[];

/** Rota de SEO do caminho (sem query), ou null para endereço desconhecido. */
export function rotaSeoDe(pathname: string): RotaSeo | null {
  const limpo = pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
  return ROTAS.find((r) => matchPath({ path: r.caminho, end: true }, limpo)) ?? null;
}

function definirMeta(atributo: "name" | "property", chave: string, valor: string | null): void {
  let el = document.head.querySelector<HTMLMetaElement>(`meta[${atributo}="${chave}"]`);
  if (valor === null) {
    el?.remove();
    return;
  }
  if (!el) {
    el = document.createElement("meta");
    el.setAttribute(atributo, chave);
    document.head.appendChild(el);
  }
  el.setAttribute("content", valor);
}

function definirCanonical(url: string | null): void {
  let el = document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]');
  if (url === null) {
    el?.remove();
    return;
  }
  if (!el) {
    el = document.createElement("link");
    el.setAttribute("rel", "canonical");
    document.head.appendChild(el);
  }
  el.setAttribute("href", url);
}

export function aplicarSeo(pathname: string): void {
  const r = rotaSeoDe(pathname);
  const titulo = r?.titulo ?? fonte.naoEncontrada.titulo;
  const robots = r?.robots ?? (fonte.naoEncontrada.robots as RotaSeo["robots"]);
  const descricao = r?.descricao ?? fonte.padrao.descricao;
  const indexavel = robots === "index, follow" && r !== null;
  const url = indexavel ? fonte.origem + (r.caminho === "/" ? "/" : r.caminho) : null;

  document.title = titulo;
  definirMeta("name", "description", descricao);
  definirMeta("name", "robots", robots);
  definirCanonical(url);
  definirMeta("property", "og:type", indexavel ? "website" : null);
  definirMeta("property", "og:site_name", indexavel ? fonte.nomeSite : null);
  definirMeta("property", "og:locale", indexavel ? "pt_BR" : null);
  definirMeta("property", "og:title", indexavel ? titulo : null);
  definirMeta("property", "og:description", indexavel ? descricao : null);
  definirMeta("property", "og:url", url);
  definirMeta("property", "og:image", indexavel ? fonte.origem + fonte.imagemOg : null);
  definirMeta("name", "twitter:card", indexavel ? "summary" : null);
}

export default function SeoCabecalho() {
  const { pathname } = useLocation();
  useEffect(() => {
    aplicarSeo(pathname);
  }, [pathname]);
  return null;
}
