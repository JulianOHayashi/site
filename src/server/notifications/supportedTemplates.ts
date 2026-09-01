/**
 * R16 — ESCOPO DE TEMPLATES SUPORTADOS PELO WORKER DE E-MAIL
 *
 * Fonte ÚNICA de verdade. As três chaves não são repetidas soltas em nenhum
 * outro arquivo: consulta de descoberta, decisão fail-closed do despachante e
 * testes importam daqui.
 *
 * POR QUE EXATAMENTE ESTES TRÊS
 * O worker só transmite depois de obter POSSE EXCLUSIVA do evento. No
 * contrato canônico do M1, a posse é estabelecida pelas RPCs de cunhagem, que
 * fazem `SELECT ... FOR UPDATE`, transicionam para `sending` e incrementam
 * `attempt_count`:
 *
 *   svc_mint_partner_application_token → partner_application_email_verification
 *                                        partner_application_account_claim
 *   svc_mint_manager_invite_token      → manager_invite
 *
 * Para qualquer outro template não existe operação equivalente: a cunhagem
 * responderia `no_token_needed` sem tomar posse. Transmitir nesse caso seria
 *
 *     descobrir → enviar → marcar enviado
 *
 * que não é claim durável e permite que dois workers enviem o mesmo e-mail.
 *
 * DECISÃO DE RELEASE, NÃO CONTORNO
 * O R16 é deliberadamente restrito a este conjunto. Um claim genérico
 * (`svc_claim_notification`) exigiria mudança de schema e é trabalho
 * separado, declarado e adiado.
 *
 *   R16_SUPPORTED_TEMPLATE_KEYS=3
 *   R16_UNSUPPORTED_TEMPLATE_POLICY=FAIL_CLOSED_NOT_PROCESSED
 *   R16_GENERIC_NOTIFICATION_CLAIM=DEFERRED
 */

/** Categoria de cunhagem canônica que estabelece a posse do evento. */
export type MintCategory = "application" | "manager_invite";

/**
 * Templates suportados e a operação canônica que dá posse a cada um.
 * Acrescentar uma chave aqui SEM operação de posse correspondente
 * reintroduziria o envio sem claim.
 */
export const R16_SUPPORTED_TEMPLATES: Readonly<Record<string, MintCategory>> =
  Object.freeze({
    partner_application_email_verification: "application",
    partner_application_account_claim: "application",
    manager_invite: "manager_invite",
  });

/** Lista imutável, para uso como filtro `in` na consulta de descoberta. */
export const R16_SUPPORTED_TEMPLATE_KEYS: readonly string[] = Object.freeze(
  Object.keys(R16_SUPPORTED_TEMPLATES)
);

/** Verdadeiro apenas para template com posse atômica comprovada. */
export function isSupportedTemplate(templateKey: string): boolean {
  return Object.prototype.hasOwnProperty.call(R16_SUPPORTED_TEMPLATES, templateKey);
}

/**
 * Categoria de cunhagem do template, ou `null` quando não suportado.
 * `null` significa "sem caminho de posse" e, portanto, "não transmitir".
 */
export function mintCategoryFor(templateKey: string): MintCategory | null {
  return isSupportedTemplate(templateKey)
    ? R16_SUPPORTED_TEMPLATES[templateKey]
    : null;
}
