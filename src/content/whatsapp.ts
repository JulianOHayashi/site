import { nicheCodeFromSlug } from "../domain/commercial/niches";

/**
 * WhatsApp comercial da SmallFlags — fonte única do número, da mensagem
 * inicial e do link oficial `wa.me`, usada pelo botão flutuante e pela
 * página de contato. Confirmado pelo operador em 25/11/2026.
 *
 * Só abre a conversa no WhatsApp do visitante: nenhuma API, webhook,
 * chatbot ou armazenamento de conversa.
 */
export const WHATSAPP_COMERCIAL = {
  /** Formato E.164 sem "+", como exige o `wa.me`. */
  numeroE164: "5527998803900",
  numeroNacional: "(27) 99880-3900",
  numeroInternacional: "+55 27 99880-3900",
  mensagemInicial: "Olá! Gostaria de conhecer as oportunidades comerciais da SmallFlags.",
  rotuloAcessivel: "Fale com a SmallFlags pelo WhatsApp",
} as const;

/** Link oficial com a mensagem inicial codificada. */
export const WHATSAPP_COMERCIAL_URL =
  `https://wa.me/${WHATSAPP_COMERCIAL.numeroE164}?text=${encodeURIComponent(WHATSAPP_COMERCIAL.mensagemInicial)}`;

/**
 * Rotas públicas em que o botão flutuante aparece (lista fechada, só rotas
 * que o App reconhece). Fica fora de: admin, portal e demais áreas
 * autenticadas, checkout, validação de benefício, fluxos de cadastro/acesso
 * de parceiros, redirecionamentos antigos e qualquer 404 — inclusive
 * `/oportunidades/<slug desconhecido>` e subcaminhos inexistentes de `/legal`.
 */
const ROTAS_PUBLICAS_EXATAS = new Set([
  "/",
  "/oportunidades",
  "/selecionar-localidade",
  "/em-breve",
  "/quem-somos",
  "/como-funciona",
  "/trabalhe-conosco",
  "/contato",
  "/ajuda",
  "/legal",
  "/legal/acordo-mestre-parceiros",
  "/parceiros",
]);

export function whatsAppFlutuanteVisivel(pathname: string): boolean {
  const p = pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
  if (ROTAS_PUBLICAS_EXATAS.has(p)) return true;
  // /oportunidades/:nicheSlug — só slugs canônicos reconhecidos pelo detalhe.
  const m = /^\/oportunidades\/([^/]+)$/.exec(p);
  if (!m) return false;
  try {
    return nicheCodeFromSlug(decodeURIComponent(m[1])) !== null;
  } catch {
    return false; // URL malformada: trata como 404
  }
}
