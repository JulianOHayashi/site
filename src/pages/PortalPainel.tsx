/**
 * PortalPainel — página legada.
 *
 * Fase 0: os imports quebrados do fluxo antigo do aplicativo foram
 * removidos. Esta página passa a ser apenas uma camada de
 * compatibilidade que reaproveita o painel atual do Portal
 * (autenticação do Site).
 *
 * Não recria login separado do app, não consulta o banco do app,
 * não cria RPCs e não altera o PortalDashboard.
 */
export { default } from "./portal/PortalDashboard";
