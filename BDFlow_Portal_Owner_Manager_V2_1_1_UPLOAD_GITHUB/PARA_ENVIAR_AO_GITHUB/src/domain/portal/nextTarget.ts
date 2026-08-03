/**
 * Validação segura do parâmetro `next` do Portal.
 *
 * Aceita SOMENTE destinos internos do Portal: exatamente "/portal" ou algo
 * que comece com "/portal/". Rejeita URLs externas, esquemas, barras
 * invertidas, caracteres de controle e valores que apenas COMECEM
 * lexicalmente por "/portal" (ex.: "/portal-malicioso", "/portal.example").
 *
 * Em qualquer valor inválido, retorna o destino seguro "/portal/dashboard".
 */

export const DEFAULT_PORTAL_TARGET = "/portal/dashboard";

export function isSafePortalNext(value: string | null | undefined): value is string {
  if (typeof value !== "string" || value.length === 0) return false;

  // Precisa ser um caminho absoluto interno.
  if (!value.startsWith("/")) return false;
  // Barra dupla no início = URL protocol-relative (//host) — rejeitar.
  if (value.startsWith("//")) return false;
  // Barra invertida em qualquer posição — rejeitar.
  if (value.includes("\\")) return false;
  // Caracteres de controle (inclui \n, \r, \t, \0) — rejeitar.
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(value)) return false;
  // Esquema (http:, javascript:, data:...) antes de qualquer "/" — rejeitar.
  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return false;

  // Somente "/portal" exato ou prefixo "/portal/". O caractere seguinte a
  // "/portal" precisa ser "/" ou "?" ou "#" — nunca "-", "." ou letra.
  if (value === "/portal") return true;
  if (value.startsWith("/portal/")) return true;
  if (value.startsWith("/portal?")) return true;
  if (value.startsWith("/portal#")) return true;
  return false;
}

/** Retorna `next` se for seguro; caso contrário, o destino padrão. */
export function safePortalNext(value: string | null | undefined): string {
  return isSafePortalNext(value) ? value : DEFAULT_PORTAL_TARGET;
}
