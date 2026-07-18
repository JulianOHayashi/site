/**
 * FONTE ÚNICA DE VERDADE da UF comercial selecionada.
 *
 * - Persistência: localStorage (sobrevive a recarregamentos e retornos).
 * - Validação: somente siglas oficiais da lista abaixo são aceitas —
 *   texto arbitrário armazenado no navegador é descartado.
 * - Nenhum outro mecanismo concorrente deve guardar a UF.
 */

export const UFS: Record<string, string> = {
  AC: "Acre", AL: "Alagoas", AP: "Amapá", AM: "Amazonas", BA: "Bahia",
  CE: "Ceará", DF: "Distrito Federal", ES: "Espírito Santo", GO: "Goiás",
  MA: "Maranhão", MT: "Mato Grosso", MS: "Mato Grosso do Sul",
  MG: "Minas Gerais", PA: "Pará", PB: "Paraíba", PR: "Paraná",
  PE: "Pernambuco", PI: "Piauí", RJ: "Rio de Janeiro",
  RN: "Rio Grande do Norte", RS: "Rio Grande do Sul", RO: "Rondônia",
  RR: "Roraima", SC: "Santa Catarina", SP: "São Paulo", SE: "Sergipe",
  TO: "Tocantins",
};

const CHAVE = "camisas_uf_selecionada";

function normalizar(t: string): string {
  return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
}

/** Converte o NOME do estado (como o BrazilMap devolve) para a sigla. */
export function nomeParaSigla(nome: string): string | null {
  const alvo = normalizar(nome);
  const s = nome.toUpperCase().trim();
  if (UFS[s]) return s; // já veio como sigla
  for (const [sigla, n] of Object.entries(UFS)) {
    if (normalizar(n) === alvo) return sigla;
  }
  return null;
}

export function ufValida(uf: unknown): uf is string {
  return typeof uf === "string" && Boolean(UFS[uf.toUpperCase().trim()]);
}

/** UF salva e válida, ou null (→ tela de seleção). */
export function obterUF(): string | null {
  try {
    const salvo = window.localStorage.getItem(CHAVE);
    if (salvo && ufValida(salvo)) return salvo.toUpperCase().trim();
    if (salvo) window.localStorage.removeItem(CHAVE); // inválido: descarta
  } catch { /* storage indisponível */ }
  return null;
}

export function salvarUF(uf: string): boolean {
  if (!ufValida(uf)) return false;
  try {
    window.localStorage.setItem(CHAVE, uf.toUpperCase().trim());
    return true;
  } catch {
    return false;
  }
}

export function limparUF(): void {
  try { window.localStorage.removeItem(CHAVE); } catch { /* ok */ }
}
