/**
 * Resolução de capacidades — PURA e conservadora.
 *
 * INVARIANTE: `role` e `status = active` NÃO concedem capacidade alguma.
 * Uma capacidade só é verdadeira quando o backend a devolve explicitamente
 * como booleano `true`. Qualquer ausência, tipo errado, string "true",
 * número 1 ou payload malformado resulta em `false` (fail-closed).
 */

import {
  CAPABILITY_KEYS,
  isMemberStatus,
  isPortalRole,
  type MemberStatus,
  type PortalCapabilities,
  type PortalCapabilityKey,
  type PortalRole,
} from "./types";

/** Todas as capacidades negadas — estado inicial e de fallback. */
export function noCapabilities(): PortalCapabilities {
  return {
    canAccessPortal: false,
    canPrepareOperation: false,
    canManageUnits: false,
    canInviteManagers: false,
    canManageManagers: false,
    canValidateBenefits: false,
    canViewCompanyTransactions: false,
    canAccessFinancial: false,
  };
}

/**
 * Converte a resposta do backend em capacidades tipadas.
 * Só aceita `true` booleano literal. Não infere nada de papel/status.
 */
export function parseCapabilities(raw: unknown): PortalCapabilities {
  const caps = noCapabilities();
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return caps;
  }
  const obj = raw as Record<string, unknown>;
  for (const key of CAPABILITY_KEYS) {
    if (obj[key] === true) caps[key] = true;
  }
  return caps;
}

/**
 * Trava de segurança adicional aplicada DEPOIS do backend.
 *
 * Mesmo que o backend devolva `true` por engano, o frontend não exibe
 * capacidades administrativas para `partner_manager`, e nenhum membro
 * suspenso/arquivado/em análise recebe ação operacional.
 *
 * Isto NÃO substitui RLS: é defesa em profundidade da interface.
 */
export function applyRoleAndStatusFloor(
  caps: PortalCapabilities,
  role: PortalRole,
  status: MemberStatus
): PortalCapabilities {
  const out: PortalCapabilities = { ...caps };

  // Membro não ativo: nenhuma ação operacional ou administrativa.
  if (status !== "active") {
    for (const key of CAPABILITY_KEYS) {
      if (key === "canAccessPortal") continue; // pode entrar e ver o próprio estado
      out[key] = false;
    }
    return out;
  }

  // Manager nunca recebe poderes administrativos nem financeiro.
  if (role === "partner_manager") {
    out.canManageUnits = false;
    out.canInviteManagers = false;
    out.canManageManagers = false;
    out.canViewCompanyTransactions = false;
    out.canAccessFinancial = false;
    out.canPrepareOperation = false;
  }

  return out;
}

/**
 * Pipeline completo: backend → parse → trava de papel/status.
 * `rawCapabilities === undefined` significa backend indisponível.
 */
export function resolveCapabilities(
  rawCapabilities: unknown,
  role: unknown,
  status: unknown
): PortalCapabilities {
  if (!isPortalRole(role) || !isMemberStatus(status)) return noCapabilities();
  if (rawCapabilities === undefined || rawCapabilities === null) {
    return noCapabilities();
  }
  return applyRoleAndStatusFloor(parseCapabilities(rawCapabilities), role, status);
}

/** Verificação pontual de capacidade. */
export function hasCapability(
  caps: PortalCapabilities,
  key: PortalCapabilityKey
): boolean {
  return caps[key] === true;
}

/** O membro está apto a operar (ativo)? Não concede capacidade por si só. */
export function isOperationalMember(status: MemberStatus): boolean {
  return status === "active";
}

/** Rótulo PT-BR do papel. */
export function roleLabel(role: PortalRole): string {
  return role === "partner_owner" ? "Responsável principal" : "Gerente operacional";
}
