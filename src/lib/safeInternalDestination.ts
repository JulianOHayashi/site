/**
 * safeInternalDestination — validação de destino de navegação interno.
 *
 * Motivação (M0.5): o parâmetro `?next=` é controlado pelo usuário e é
 * consumido por páginas que chamam `navigate(destino)`. Validação por
 * prefixo (`startsWith("/")` + `!startsWith("//")`) NÃO é suficiente:
 * o parser de URL do navegador trata `\` como `/` em esquemas especiais,
 * então `/\evil.com` escapa da checagem e resolve para outra origem.
 *
 * Estratégia: em vez de tentar enumerar padrões perigosos, resolvemos o
 * candidato com o parser WHATWG contra uma origem fixa e fictícia e
 * exigimos que a origem resultante seja exatamente essa. Qualquer coisa
 * que mude a origem — `//host`, `/\host`, `\\host`, `https://host`,
 * `javascript:`, `data:`, `mailto:` — é rejeitada pelo mesmo teste, sem
 * depender de `window` (funciona em teste, SSR e navegador).
 *
 * O destino devolvido é SEMPRE reconstruído a partir do resultado do
 * parser (pathname + search + hash), nunca a string crua, de modo que
 * nenhuma forma não normalizada chegue ao roteador.
 */

/** Origem fictícia: `.invalid` é reservado por RFC 2606 e nunca resolve. */
const DUMMY_ORIGIN = "https://internal.invalid";

export type SafeInternalDestinationOptions = {
  /**
   * Restringe o destino a uma subárvore (ex.: "/admin", "/portal").
   * A comparação respeita fronteira de segmento: "/admin" e "/admin/x"
   * são aceitos, "/administrador" não.
   */
  requiredPrefix?: string;
};

/**
 * Resolve um destino interno confiável.
 *
 * @param raw       valor cru vindo do usuário (querystring, estado, etc.)
 * @param fallback  destino interno usado quando `raw` é inválido
 * @returns caminho interno normalizado, ou `fallback`
 */
export function safeInternalDestination(
  raw: string | null | undefined,
  fallback: string,
  options: SafeInternalDestinationOptions = {}
): string {
  const candidato = resolverInterno(raw, options.requiredPrefix);
  if (candidato !== null) return candidato;

  // O fallback é literal do código, mas passa pela mesma validação:
  // nenhum caminho de retorno escapa da checagem de origem.
  const seguro = resolverInterno(fallback, options.requiredPrefix);
  return seguro !== null ? seguro : "/";
}

function resolverInterno(
  raw: string | null | undefined,
  requiredPrefix?: string
): string | null {
  if (typeof raw !== "string" || raw.length === 0) return null;

  // Exigimos caminho absoluto interno. Destinos relativos ("x", "../y")
  // dependeriam da rota atual e não são aceitos aqui.
  if (raw[0] !== "/") return null;

  // Rejeição antecipada de protocolo-relativo em ambas as grafias.
  // A checagem de origem abaixo já cobriria, mas manter isso explícito
  // torna a intenção auditável.
  if (raw[1] === "/" || raw[1] === "\\") return null;

  let url: URL;
  try {
    url = new URL(raw, DUMMY_ORIGIN);
  } catch {
    return null;
  }

  // Checagem decisiva: qualquer fuga de origem reprova aqui.
  if (url.origin !== DUMMY_ORIGIN) return null;

  // Reconstrução a partir do parser — nunca a string crua.
  const destino = `${url.pathname}${url.search}${url.hash}`;
  if (!destino.startsWith("/") || destino.startsWith("//")) return null;

  if (requiredPrefix !== undefined && !dentroDoPrefixo(url.pathname, requiredPrefix)) {
    return null;
  }

  return destino;
}

function dentroDoPrefixo(pathname: string, prefixo: string): boolean {
  if (pathname === prefixo) return true;
  const base = prefixo.endsWith("/") ? prefixo : `${prefixo}/`;
  return pathname.startsWith(base);
}
