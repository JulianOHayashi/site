/**
 * Navegação do Portal — derivada PURAMENTE de papel + capacidades.
 *
 * O menu nunca "pisca" itens proibidos: enquanto o contexto carrega,
 * `portalNavigation` não é chamado (a UI mostra o esqueleto de carregamento).
 */

import type { PortalCapabilities, PortalRole } from "./types";

export type PortalNavItem = {
  rotulo: string;
  to: string;
  /** Item de destino owner-only/manager-only, para asserção em testes. */
  ownerOnly?: boolean;
  managerOnly?: boolean;
};

/**
 * Owner: Início · Empresa e filiais · Equipe e convites · Validar · Transações
 * Manager: Início · Meu acesso · Validar · Minhas validações
 *
 * Itens que dependem de capacidade só aparecem quando ela foi concedida
 * pelo backend — exceto os de leitura do próprio estado.
 */
export function portalNavigation(
  role: PortalRole,
  caps: PortalCapabilities
): PortalNavItem[] {
  const itens: PortalNavItem[] = [{ rotulo: "Início", to: "/portal/dashboard" }];

  if (role === "partner_owner") {
    itens.push({ rotulo: "Empresa e filiais", to: "/portal/unidades", ownerOnly: true });
    itens.push({ rotulo: "Equipe e convites", to: "/portal/equipe", ownerOnly: true });
    if (caps.canValidateBenefits) {
      itens.push({ rotulo: "Validar", to: "/portal/validar" });
    }
    itens.push({ rotulo: "Transações", to: "/portal/solicitacoes", ownerOnly: true });
    return itens;
  }

  // partner_manager
  itens.push({ rotulo: "Meu acesso", to: "/portal/meu-acesso", managerOnly: true });
  if (caps.canValidateBenefits) {
    itens.push({ rotulo: "Validar", to: "/portal/validar" });
  }
  itens.push({ rotulo: "Minhas validações", to: "/portal/solicitacoes" });
  return itens;
}

/** Rotas exclusivas de owner (guard + teste). */
export const OWNER_ONLY_ROUTES: readonly string[] = [
  "/portal/equipe",
  "/portal/unidades",
];

/** Rotas exclusivas de manager (guard + teste). */
export const MANAGER_ONLY_ROUTES: readonly string[] = ["/portal/meu-acesso"];

/** O papel pode abrir a rota? (apenas UX — RLS é a autoridade real.) */
export function canRoleOpenRoute(role: PortalRole, path: string): boolean {
  const base = path.split("?")[0];
  if (OWNER_ONLY_ROUTES.some((r) => base === r || base.startsWith(r + "/"))) {
    return role === "partner_owner";
  }
  if (MANAGER_ONLY_ROUTES.some((r) => base === r || base.startsWith(r + "/"))) {
    return role === "partner_manager";
  }
  return true;
}
