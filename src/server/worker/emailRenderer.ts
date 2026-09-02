/**
 * R16 — RENDERIZAÇÃO DE MENSAGEM.
 *
 * Exatamente os três templates suportados. Nada de serializar `template_data`
 * inteiro: só os campos explicitamente exigidos entram na mensagem, porque
 * um despejo de objeto levaria segredo e PII para dentro do e-mail.
 *
 * ORIGEM DE URL
 * Todo link acionável nasce de `siteBaseUrl` (configurada e validada) mais
 * uma rota interna de um conjunto FECHADO. `template_data` não escolhe
 * esquema, host, porta nem origem. Uma URL absoluta hostil vinda dos dados
 * não pode substituir o destino: ela é tratada como texto, nunca como base.
 */

import { mintCategoryFor } from "../notifications/supportedTemplates";
import { montarPayloadData, type CabecalhosEmail } from "./smtpWire";

export class RenderError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "RenderError";
    this.code = code;
  }
}

/** Rotas internas permitidas. Conjunto fechado, não parametrizável. */
const ROTAS = {
  confirmarEmail: "/parceiros/confirmar",
  recuperarAcesso: "/parceiros/recuperar",
  aceitarConvite: "/parceiros/convite",
} as const;

/** Escapa texto para inserção segura em HTML. */
export function escaparHtml(texto: string): string {
  return texto
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Monta um link acionável. A base vem SEMPRE da configuração; o segredo entra
 * como parâmetro de consulta devidamente codificado.
 */
export function montarLink(
  siteBaseUrl: string,
  rota: keyof typeof ROTAS,
  parametros: Record<string, string>
): string {
  const url = new URL(siteBaseUrl + ROTAS[rota]);
  for (const [k, v] of Object.entries(parametros)) {
    if (typeof v !== "string") {
      throw new RenderError("invalid_link_param", `parâmetro ${k} inválido`);
    }
    url.searchParams.set(k, v);
  }
  const final = url.toString();
  // Barreira final: o link tem de permanecer na origem configurada.
  if (!final.startsWith(new URL(siteBaseUrl).origin)) {
    throw new RenderError("url_origin_escaped", "link saiu da origem configurada");
  }
  return final;
}

function exigirTexto(dados: Record<string, unknown>, campo: string, max = 200): string {
  const v = dados[campo];
  if (typeof v !== "string" || v.trim().length === 0 || v.length > max) {
    throw new RenderError("missing_template_field", `campo obrigatório ausente: ${campo}`);
  }
  if (/[\r\n\0]/.test(v)) {
    throw new RenderError("template_field_control_char", `campo ${campo} com controle`);
  }
  return v;
}

export type MensagemRenderizada = {
  subject: string;
  texto: string;
  html: string;
};

/**
 * Renderiza pelo template. Falha fechada em template não suportado e em campo
 * obrigatório ausente ou malformado.
 */
export function renderizar(
  templateKey: string,
  dados: Record<string, unknown>,
  siteBaseUrl: string
): MensagemRenderizada {
  if (mintCategoryFor(templateKey) === null) {
    throw new RenderError("unsupported_template", "template fora do escopo do R16");
  }

  const token = exigirTexto(dados, "token", 256);

  switch (templateKey) {
    case "partner_application_email_verification": {
      const link = montarLink(siteBaseUrl, "confirmarEmail", { token });
      const linkHtml = escaparHtml(link);
      return {
        subject: "Confirme seu e-mail — BDFlow",
        texto: [
          "Recebemos sua solicitação de parceria.",
          "",
          "Para continuar, confirme seu e-mail acessando o link abaixo:",
          link,
          "",
          "Se você não solicitou, ignore esta mensagem.",
        ].join("\n"),
        html: [
          "<p>Recebemos sua solicitação de parceria.</p>",
          "<p>Para continuar, confirme seu e-mail:</p>",
          `<p><a href="${linkHtml}">Confirmar e-mail</a></p>`,
          "<p>Se você não solicitou, ignore esta mensagem.</p>",
        ].join(""),
      };
    }

    case "partner_application_account_claim": {
      const link = montarLink(siteBaseUrl, "confirmarEmail", { claim: token });
      const linkHtml = escaparHtml(link);
      return {
        subject: "Crie seu acesso — BDFlow",
        texto: [
          "Seu e-mail foi confirmado.",
          "",
          "Crie seu acesso provisório para acompanhar a análise:",
          link,
          "",
          "Se você não solicitou, ignore esta mensagem.",
        ].join("\n"),
        html: [
          "<p>Seu e-mail foi confirmado.</p>",
          "<p>Crie seu acesso provisório para acompanhar a análise:</p>",
          `<p><a href="${linkHtml}">Criar acesso</a></p>`,
          "<p>Se você não solicitou, ignore esta mensagem.</p>",
        ].join(""),
      };
    }

    case "manager_invite": {
      const link = montarLink(siteBaseUrl, "aceitarConvite", { token });
      const linkHtml = escaparHtml(link);
      // Nome da empresa é dinâmico e vai para HTML: precisa de escape.
      const empresa = exigirTexto(dados, "company_name", 300);
      return {
        subject: "Convite para gerenciar — BDFlow",
        texto: [
          `Você foi convidado para gerenciar uma unidade de ${empresa}.`,
          "",
          "Para aceitar o convite, acesse:",
          link,
          "",
          "Se você não esperava este convite, ignore esta mensagem.",
        ].join("\n"),
        html: [
          `<p>Você foi convidado para gerenciar uma unidade de ${escaparHtml(empresa)}.</p>`,
          "<p>Para aceitar o convite:</p>",
          `<p><a href="${linkHtml}">Aceitar convite</a></p>`,
          "<p>Se você não esperava este convite, ignore esta mensagem.</p>",
        ].join(""),
      };
    }

    default:
      // Inalcançável pela checagem acima; fail-closed por segurança.
      throw new RenderError("unsupported_template", "template fora do escopo do R16");
  }
}

/** Monta o payload SMTP completo a partir da mensagem renderizada. */
export function montarMensagemSmtp(
  destino: string,
  fromAddress: string,
  fromName: string | undefined,
  m: MensagemRenderizada
): string {
  const from = fromName ? `${fromName} <${fromAddress}>` : fromAddress;
  const cabecalhos: CabecalhosEmail = {
    from,
    to: destino,
    subject: m.subject,
    date: new Date().toUTCString(),
  };
  return montarPayloadData(cabecalhos, m.texto, m.html);
}
