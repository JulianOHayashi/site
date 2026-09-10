/**
 * CAPTURA DO SEGREDO DO TOKEN DE BENEFÍCIO A PARTIR DO FRAGMENTO.
 *
 * O App gera a URL como:
 *   {SITE_ORIGIN}/beneficios/validar/{public_lookup_id}#{raw_secret}
 *
 * O fragmento é escolha deliberada do contrato: o navegador o entrega ao
 * JavaScript, mas NÃO o envia no GET. Assim o segredo nunca aparece em log de
 * servidor, em Referer nem em histórico de proxy.
 *
 * REGRAS QUE ESTE MÓDULO EXISTE PARA CUMPRIR
 *   - o segredo vive só em memória do módulo;
 *   - some da URL visível assim que é lido, para não sobreviver em
 *     screenshot, barra de endereço ou botão "voltar";
 *   - nunca vira query string nem armazenamento persistente do
 *     navegador. A asserção que cobre isto varre o PRÓPRIO texto destes
 *     arquivos, então nem em comentário os nomes dessas APIs aparecem.
 *
 * A captura roda no import, antes do React montar, porque o guard de
 * autenticação pode redirecionar para o login — e o fragmento não sobrevive a
 * uma navegação. A memória do módulo sobrevive, já que o Portal navega por
 * SPA sem recarregar a página.
 */

import { RAW_SECRET_RE } from "../server/benefitUsage/benefitUsageContract";

/** Só o caminho de validação de benefício ativa a captura. */
const CAMINHO_RE = /^\/beneficios\/validar\/([^/?#]+)\/?$/;

let segredoEmMemoria: string | null = null;
let locatorEmMemoria: string | null = null;

export type CapturaFragmento =
  | { tipo: "ignorado" }
  | { tipo: "invalido" }
  | { tipo: "capturado"; publicLookupId: string; rawSecret: string };

/**
 * Unidade pura, para teste: decide a partir de caminho e fragmento, sem tocar
 * em `window`.
 */
export function interpretarLocalizacao(
  pathname: string,
  hash: string
): CapturaFragmento {
  const m = CAMINHO_RE.exec(pathname);
  if (!m) return { tipo: "ignorado" };

  const publicLookupId = decodeURIComponent(m[1]);
  const bruto = hash.startsWith("#") ? hash.slice(1) : hash;
  if (bruto === "") return { tipo: "invalido" };
  if (!RAW_SECRET_RE.test(bruto)) return { tipo: "invalido" };
  return { tipo: "capturado", publicLookupId, rawSecret: bruto };
}

/**
 * Captura de verdade: lê `window.location`, guarda em memória e APAGA o
 * fragmento da URL visível no mesmo passo.
 */
export function capturarFragmento(
  win: Pick<Window, "location" | "history"> | undefined = typeof window !==
  "undefined"
    ? window
    : undefined
): CapturaFragmento {
  if (!win) return { tipo: "ignorado" };
  const r = interpretarLocalizacao(win.location.pathname, win.location.hash);

  if (r.tipo === "capturado") {
    segredoEmMemoria = r.rawSecret;
    locatorEmMemoria = r.publicLookupId;
  }
  // Fragmento inválido também é apagado: lixo na barra de endereço parece
  // segredo para quem estiver olhando por cima do ombro.
  if (r.tipo !== "ignorado" && win.location.hash !== "") {
    win.history.replaceState(
      null,
      "",
      `${win.location.pathname}${win.location.search}`
    );
  }
  return r;
}

/** Lê o que foi capturado. Não consome: a tela pode remontar. */
export function lerSegredoCapturado(): string | null {
  return segredoEmMemoria;
}

export function lerLocatorCapturado(): string | null {
  return locatorEmMemoria;
}

/** Descarta após a transação — ou ao sair da tela. */
export function descartarSegredoCapturado(): void {
  segredoEmMemoria = null;
  locatorEmMemoria = null;
}
