/**
 * Serviço de vínculo do Portal — ÚNICA porta de leitura do vínculo atual.
 *
 * Nenhum componente deve consultar `site_partner_members` diretamente.
 *
 * DISTINÇÃO CRÍTICA: "nenhum vínculo encontrado" (consulta OK, zero linhas)
 * é diferente de "a consulta falhou" (rede/RLS/backend). Uma falha JAMAIS
 * vira `no_membership` — isso produziria estado vazio enganoso e poderia
 * exibir cadastro empresarial indevido.
 */

import { supabase } from "../lib/supabase";
import {
  PortalError,
  isCompanyStatus,
  isMemberStatus,
  isPortalRole,
  type PartnerCompany,
  type PortalCapabilities,
  type PortalMembership,
} from "../domain/portal/types";
import { noCapabilities } from "../domain/portal/capabilities";

export type MembershipLookup =
  | { kind: "found"; membership: PortalMembership }
  | { kind: "not_found" }
  | { kind: "failed"; error: PortalError };

/** Extrai o primeiro objeto de um campo que pode vir objeto ou array. */
function primeiroObjeto(v: unknown): Record<string, unknown> | null {
  if (Array.isArray(v)) {
    const primeiro = v[0];
    return typeof primeiro === "object" && primeiro !== null
      ? (primeiro as Record<string, unknown>)
      : null;
  }
  if (typeof v === "object" && v !== null) return v as Record<string, unknown>;
  return null;
}

function texto(v: unknown, limite: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (!t) return null;
  return t.length > limite ? t.slice(0, limite) : t;
}

/**
 * Monta a empresa a partir do que o backend REALMENTE devolve.
 *
 * `trade_name` é usado apenas como rótulo de exibição provisório, sinalizado
 * pela UI como dado ainda não migrado para `partner_display_name`. Campos
 * públicos ausentes permanecem `null` — não inventamos conteúdo.
 */
function montarEmpresa(raw: Record<string, unknown> | null): PartnerCompany {
  const status = raw?.status;
  return {
    companyId: typeof raw?.id === "string" ? raw.id : null,
    partnerDisplayName:
      texto(raw?.partner_display_name, 160) ?? texto(raw?.trade_name, 160),
    status: isCompanyStatus(status) ? status : null,
    contractStatusLabel: texto(raw?.contract_status_label, 120),
    paymentStatusLabel: texto(raw?.payment_status_label, 120),
    nicheLabel: texto(raw?.niche_label, 120),
    exclusivityStatusLabel: texto(raw?.exclusivity_status_label, 120),
    operationStatusLabel: texto(raw?.operation_status_label, 120),
    notices: [],
  };
}

/**
 * Vínculo atual do usuário autenticado (via RLS).
 *
 * Consulta o mesmo objeto já existente no repositório; não cria RPC nova,
 * não faz INSERT/UPDATE e não contorna RLS.
 */
export async function fetchCurrentMembership(
  userId: string
): Promise<MembershipLookup> {
  if (!supabase) {
    return { kind: "failed", error: new PortalError("NOT_CONFIGURED") };
  }

  const { data, error } = await supabase
    .from("site_partner_members")
    .select("id, role, status, site_monthly_partners(id, trade_name, status)")
    .eq("user_id", userId);

  // Falha real de consulta — NUNCA interpretar como ausência de vínculo.
  if (error) {
    return { kind: "failed", error: new PortalError("QUERY_FAILED") };
  }
  if (!Array.isArray(data)) {
    return { kind: "failed", error: new PortalError("UNEXPECTED_RESPONSE") };
  }
  if (data.length === 0) {
    return { kind: "not_found" };
  }

  // Prioridade determinística de elegibilidade:
  // active > pending_admin_review > suspended > archived.
  // archived NÃO é descartado: se for o único vínculo, o Portal precisa
  // renderizar "Vínculo encerrado" (e não "sem vínculo").
  const linhas = data as Record<string, unknown>[];
  const PRIORIDADE: Record<string, number> = {
    active: 0,
    pending_admin_review: 1,
    suspended: 2,
    archived: 3,
  };
  const ordenadas = [...linhas].sort(
    (a, b) =>
      (PRIORIDADE[String(a.status)] ?? 99) -
      (PRIORIDADE[String(b.status)] ?? 99)
  );
  const escolhida = ordenadas[0];

  const role = escolhida.role;
  const status = escolhida.status;
  const memberId = escolhida.id;

  if (!isPortalRole(role) || !isMemberStatus(status) || typeof memberId !== "string") {
    return { kind: "failed", error: new PortalError("UNEXPECTED_RESPONSE") };
  }

  return {
    kind: "found",
    membership: {
      memberId,
      role,
      status,
      company: montarEmpresa(primeiroObjeto(escolhida.site_monthly_partners)),
    },
  };
}

/**
 * Capacidades do Portal.
 *
 * A API de capacidades AINDA NÃO EXISTE. Enquanto não existir, este serviço
 * devolve `BACKEND_NOT_AVAILABLE` e capacidades todas negadas — nunca
 * derivadas de `role` + `status = active`. Não inventamos nome de RPC.
 */
export async function fetchCapabilities(): Promise<
  | { kind: "granted"; capabilities: PortalCapabilities }
  | { kind: "unavailable"; error: PortalError }
> {
  return {
    kind: "unavailable",
    error: new PortalError("BACKEND_NOT_AVAILABLE"),
  };
}

export function emptyCapabilities(): PortalCapabilities {
  return noCapabilities();
}
