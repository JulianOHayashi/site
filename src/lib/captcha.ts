/**
 * CAPTCHA (Cloudflare Turnstile) das operações do Supabase Auth.
 *
 * A proteção REAL é do servidor: com CAPTCHA ligado no Supabase Auth
 * (Authentication → Bot and Abuse Protection → CAPTCHA), login, cadastro e
 * reset de senha sem um token válido são recusados pelo próprio Auth, mesmo
 * que alguém ignore esta interface e chame a API diretamente. O frontend só
 * obtém o token do Turnstile e o envia em `options.captchaToken`.
 *
 * O SECRET do Turnstile fica SOMENTE no Supabase Dashboard. Aqui existe
 * apenas a site key PÚBLICA (`VITE_TURNSTILE_SITE_KEY`).
 *
 * Política de configuração:
 *   site key presente            → Turnstile obrigatório
 *   sem site key em PRODUCTION   → FAIL-CLOSED: nenhuma operação de Auth
 *                                   protegida é enviada (erro explícito)
 *   sem site key fora de PROD    → desligado (dev/teste local), sem token
 */

export type ConfigCaptcha =
  | { modo: "turnstile"; siteKey: string }
  | { modo: "erro_config" }
  | { modo: "desligado" };

type EnvCaptcha = { VITE_TURNSTILE_SITE_KEY?: string; PROD?: boolean };

/** Lida a cada chamada (não no import), para refletir o ambiente real. */
export function lerConfigCaptcha(env: EnvCaptcha = import.meta.env): ConfigCaptcha {
  const siteKey = (env.VITE_TURNSTILE_SITE_KEY ?? "").trim();
  if (siteKey) return { modo: "turnstile", siteKey };
  if (env.PROD) return { modo: "erro_config" };
  return { modo: "desligado" };
}

export const MENSAGEM_CAPTCHA_PENDENTE =
  "Conclua a verificação de segurança para continuar.";
export const MENSAGEM_CAPTCHA_FALHOU =
  "Não foi possível confirmar a verificação de segurança. Tente novamente.";
export const MENSAGEM_CAPTCHA_INDISPONIVEL =
  "Acesso temporariamente indisponível: a verificação de segurança não está configurada.";
export const MENSAGEM_LIMITE =
  "Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.";

type ErroAuth = { code?: string; message?: string; status?: number } | null | undefined;

/** O Supabase recusou por CAPTCHA ausente/inválido? */
export function ehErroDeCaptcha(erro: ErroAuth): boolean {
  if (!erro) return false;
  return erro.code === "captcha_failed" || /captcha/i.test(erro.message ?? "");
}

/**
 * Mensagem segura para o usuário. Nunca repassa `error.message` do servidor
 * (que pode trazer detalhe interno) e nunca diferencia "conta existe" de
 * "senha errada": credencial inválida e qualquer erro desconhecido caem na
 * mensagem genérica que cada tela já usava.
 */
export function mensagemSeguraDeAuth(erro: ErroAuth, generica: string): string {
  if (ehErroDeCaptcha(erro)) return MENSAGEM_CAPTCHA_FALHOU;
  if (erro?.code === "over_request_rate_limit" || erro?.status === 429) return MENSAGEM_LIMITE;
  return generica;
}

/** Opções de Auth com o token, só quando há token (modo desligado: nada). */
export function opcoesComCaptcha<T extends object>(
  token: string | undefined,
  extras?: T
): (T & { captchaToken?: string }) | undefined {
  if (!token && !extras) return undefined;
  return { ...(extras ?? ({} as T)), ...(token ? { captchaToken: token } : {}) };
}
