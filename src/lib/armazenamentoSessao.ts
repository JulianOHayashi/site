/**
 * O navegador consegue GUARDAR a sessão de login?
 *
 * A sessão do Supabase vive no localStorage desta origem. Quando o
 * localStorage não existe ou recusa escrita (ex.: Safari com "Bloquear todos
 * os cookies", algumas WebViews de apps), o supabase-js passa em SILÊNCIO para
 * um armazenamento em memória: o login funciona, mas some ao recarregar ou ao
 * abrir outra aba. Este teste repete a verificação de escrita do próprio
 * supabase-js para que a interface possa avisar.
 *
 * Limite honesto: a navegação privada do Safari ACEITA escrita (e apaga ao
 * fechar a aba). Não há detecção confiável desse caso, então ele não é
 * detectado aqui — não inventamos heurística.
 *
 * Nada de token é lido ou gravado: só uma chave de teste, removida em seguida.
 */
const CHAVE_TESTE = "sf-teste-armazenamento";

export function armazenamentoDeSessaoDisponivel(): boolean {
  if (typeof window === "undefined") return false;
  try {
    const ls = window.localStorage;
    if (!ls || typeof ls !== "object") return false;
    const valor = String(Math.random());
    ls.setItem(CHAVE_TESTE, valor);
    const lido = ls.getItem(CHAVE_TESTE);
    ls.removeItem(CHAVE_TESTE);
    return lido === valor;
  } catch {
    return false;
  }
}
