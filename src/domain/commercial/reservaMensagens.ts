/**
 * Mensagens fixas para os motivos de recusa da reserva comercial.
 *
 * Nenhum texto do banco chega à tela. Para a produção de bandeiras (SF-v1.5),
 * a recusa nunca traz preço: a mensagem explica o que falta, sem prometer
 * reposição gratuita nem anunciar cobrança que não foi aprovada.
 */
const MENSAGENS: Record<string, string> = {
  opportunity_reserved: "Esta oportunidade está reservada por outra empresa no momento.",
  not_company_owner: "Apenas o responsável da empresa pode reservar.",
  company_already_contracted_in_exclusivity:
    "Esta empresa já possui um nicho contratado nesta exclusividade. Cada CNPJ pode contratar apenas um nicho por exclusividade.",
  region_not_operating: "Ainda não operamos na cidade cadastrada para a sua empresa.",
  flag_reuse_not_verified:
    "A renovação fidelizada reutiliza as bandeiras já fabricadas para a sua marca, e essas peças ainda não têm inspeção de conservação aprovada para esta contratação. A SmallFlags precisa verificar o conjunto antes de liberar a reserva. Nada foi reservado nem cobrado.",
  flag_replacement_policy_pending:
    "A inspeção encontrou bandeiras do seu conjunto que precisam de substituição. A política de reposição ainda está em definição, então a SmallFlags vai entrar em contato antes de liberar esta contratação. Nada foi reservado nem cobrado.",
  settlement_mode_not_enabled:
    "No momento, a contratação está disponível somente na forma em dinheiro. Nada foi reservado nem cobrado.",
  artwork_change_not_ready:
    "A renovação com a nova arte ainda depende do registro da cobrança e da fabricação das bandeiras. Nada foi reservado nem cobrado.",
  artwork_change_pending_for_campaign:
    "Há uma solicitação de alteração de arte em andamento para esta campanha. Conclua ou cancele a solicitação antes de renovar. Nada foi reservado nem cobrado.",
  pricing_rule_not_published:
    "As condições comerciais estão sendo atualizadas. Tente novamente mais tarde. Nada foi cobrado.",
};

export function mensagemFalhaReserva(codigo: string): string | null {
  return MENSAGENS[codigo] ?? null;
}
