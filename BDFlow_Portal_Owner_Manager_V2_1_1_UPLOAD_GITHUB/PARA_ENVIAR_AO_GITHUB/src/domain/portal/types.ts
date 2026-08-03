/**
 * Domínio do Portal BDFlow — tipos canônicos.
 *
 * REGRA CENTRAL: nada aqui deriva autorização de `role` + `status = active`.
 * Capacidades são concedidas EXCLUSIVAMENTE pelo backend (RPC/gateway/RLS).
 * Guards e telas do frontend melhoram a experiência; a autoridade real
 * continua sendo RLS, RPCs, validação server-side e auditoria.
 */

// ---------------------------------------------------------------------------
// Papéis e estados que o backend já possui
// ---------------------------------------------------------------------------

export type PortalRole = "partner_owner" | "partner_manager";

export type CompanyStatus =
  | "lead"
  | "pending"
  | "active"
  | "suspended"
  | "archived";

export type MemberStatus =
  | "active"
  | "pending_admin_review"
  | "suspended"
  | "archived";

export const PORTAL_ROLES: readonly PortalRole[] = [
  "partner_owner",
  "partner_manager",
];
export const COMPANY_STATUSES: readonly CompanyStatus[] = [
  "lead",
  "pending",
  "active",
  "suspended",
  "archived",
];
export const MEMBER_STATUSES: readonly MemberStatus[] = [
  "active",
  "pending_admin_review",
  "suspended",
  "archived",
];

export function isPortalRole(v: unknown): v is PortalRole {
  return typeof v === "string" && (PORTAL_ROLES as readonly string[]).includes(v);
}
export function isCompanyStatus(v: unknown): v is CompanyStatus {
  return (
    typeof v === "string" && (COMPANY_STATUSES as readonly string[]).includes(v)
  );
}
export function isMemberStatus(v: unknown): v is MemberStatus {
  return (
    typeof v === "string" && (MEMBER_STATUSES as readonly string[]).includes(v)
  );
}

// ---------------------------------------------------------------------------
// Erros de domínio padronizados
// ---------------------------------------------------------------------------

export type PortalErrorCode =
  | "BACKEND_NOT_AVAILABLE"
  | "FORBIDDEN"
  | "MEMBERSHIP_NOT_FOUND"
  | "MEMBERSHIP_SUSPENDED"
  | "CAPABILITY_NOT_GRANTED"
  | "INVITATION_EXPIRED"
  | "INVITATION_USED"
  | "INVITATION_REVOKED"
  | "INVITATION_EMAIL_MISMATCH"
  | "OPERATION_NOT_ACTIVE"
  | "NOT_CONFIGURED"
  | "QUERY_FAILED"
  | "UNEXPECTED_RESPONSE";

export class PortalError extends Error {
  code: PortalErrorCode;
  constructor(code: PortalErrorCode, message?: string) {
    super(message ?? code);
    this.code = code;
    this.name = "PortalError";
  }
}

/** Mensagens PT-BR seguras (nunca expõem detalhe técnico do backend). */
export const PORTAL_ERROR_LABEL: Record<PortalErrorCode, string> = {
  BACKEND_NOT_AVAILABLE:
    "Esta função ainda não está disponível: a integração de servidor não foi ativada.",
  FORBIDDEN: "Acesso não autorizado.",
  MEMBERSHIP_NOT_FOUND: "Nenhum vínculo elegível para o Portal foi encontrado.",
  MEMBERSHIP_SUSPENDED: "Seu acesso está suspenso no momento.",
  CAPABILITY_NOT_GRANTED: "Sua conta não possui permissão para esta ação.",
  INVITATION_EXPIRED: "Este convite expirou.",
  INVITATION_USED: "Este convite já foi utilizado.",
  INVITATION_REVOKED: "Este convite não está mais disponível.",
  INVITATION_EMAIL_MISMATCH:
    "Este convite foi protegido por e-mail e não corresponde à conta autenticada. Entre com a conta correta para continuar.",
  NOT_CONFIGURED: "Portal em configuração.",
  OPERATION_NOT_ACTIVE: "A operação ainda não está ativa para esta empresa.",
  QUERY_FAILED: "Não foi possível consultar seus dados agora.",
  UNEXPECTED_RESPONSE: "A resposta recebida não pôde ser interpretada.",
};

// ---------------------------------------------------------------------------
// Capacidades
// ---------------------------------------------------------------------------

export type PortalCapabilities = {
  canAccessPortal: boolean;
  canPrepareOperation: boolean;
  canManageUnits: boolean;
  canInviteManagers: boolean;
  canManageManagers: boolean;
  canValidateBenefits: boolean;
  canViewCompanyTransactions: boolean;
  canAccessFinancial: boolean;
};

export type PortalCapabilityKey = keyof PortalCapabilities;

export const CAPABILITY_KEYS: readonly PortalCapabilityKey[] = [
  "canAccessPortal",
  "canPrepareOperation",
  "canManageUnits",
  "canInviteManagers",
  "canManageManagers",
  "canValidateBenefits",
  "canViewCompanyTransactions",
  "canAccessFinancial",
];

// ---------------------------------------------------------------------------
// Empresa, vínculo e unidades
// ---------------------------------------------------------------------------

/**
 * Campos públicos de apresentação (limites definidos na Fase 2A).
 * `trade_name`, `city` e `state` NÃO são substitutos definitivos:
 * quando o campo público não vier do backend, exibimos ausência.
 */
export type PartnerCompany = {
  companyId: string | null;
  partnerDisplayName: string | null;
  status: CompanyStatus | null;
  /** Situação contratual/pagamento, quando o backend fornecer. */
  contractStatusLabel: string | null;
  paymentStatusLabel: string | null;
  nicheLabel: string | null;
  exclusivityStatusLabel: string | null;
  operationStatusLabel: string | null;
  /** Avisos (suspensão, análise, antifraude, chargeback). */
  notices: readonly string[];
};

export type PartnerUnit = {
  unitId: string;
  isHeadquarters: boolean;
  branchDisplayName: string | null;
  branchLocationLabel: string | null;
  branchCityName: string | null;
  branchStateCode: string | null;
  status: "active" | "suspended" | "archived" | null;
  /** Autorizada pelo backend a liberar benefícios. */
  benefitsAuthorized: boolean | null;
  activeManagersCount: number | null;
};

export type PortalMembership = {
  memberId: string;
  role: PortalRole;
  status: MemberStatus;
  company: PartnerCompany;
};

// ---------------------------------------------------------------------------
// Contexto do Portal (estado discriminado — falha ≠ ausência)
// ---------------------------------------------------------------------------

export type PortalContextState =
  | { kind: "loading" }
  /** A consulta FALHOU. Nunca tratar como "sem vínculo". */
  | { kind: "error"; code: PortalErrorCode }
  /** Consulta bem-sucedida e sem vínculo elegível. */
  | { kind: "no_membership" }
  | {
      kind: "ready";
      membership: PortalMembership;
      capabilities: PortalCapabilities;
      /** Origem das capacidades: backend real ou indisponível. */
      capabilitiesSource: "backend" | "unavailable";
    };

// ---------------------------------------------------------------------------
// Convites de manager
// ---------------------------------------------------------------------------

/** Validade fixa: 48 horas corridas desde a criação. */
export const INVITATION_TTL_HOURS = 48;

export type InvitationBackendStatus =
  | "not_used"
  | "used"
  | "expired"
  | "revoked";

export type ManagerInvitation = {
  invitationId: string;
  /** Lote ao qual o convite pertence (mesmo lote = mesma geração). */
  batchId: string | null;
  /** Rótulo organizacional opcional (nome esperado, turno...). */
  label: string | null;
  /** Só existe no resultado IMEDIATO da geração. Nunca re-exibido depois. */
  url: string | null;
  createdAt: string | null;
  expiresAt: string | null;
  status: InvitationBackendStatus;
  usedAt: string | null;
  /** Manager criado a partir deste convite, quando o backend revelar. */
  usedByMemberId: string | null;
  usedByName: string | null;
};

/** Estado visual derivado (puro) — inclui expiração por tempo. */
export type InvitationVisualState =
  | "not_used"
  | "used"
  | "expired"
  | "revoked";

export type ManagerInvitationDraft = {
  /** Rótulo organizacional opcional por vaga. */
  label: string;
};

/**
 * Lote de convites devolvido pela criação. O contrato de criação retorna
 * explicitamente o lote e seus convites — não apenas uma lista solta.
 */
export type ManagerInvitationBatch = {
  batchId: string;
  createdAt: string | null;
  invitations: ManagerInvitation[];
};

/**
 * Entrada de criação em lote — PROTEGE contra quantidades enormes:
 * envia a quantidade e apenas os rótulos PREENCHIDOS (esparsos por posição),
 * nunca um array do tamanho total.
 */
export type CreateInvitationBatchInput = {
  quantity: number;
  labels: Array<{ position: number; label: string }>;
};

/**
 * Entrada tipada para a ação sensível de revogação de vínculo.
 * `sensitiveActionProof` representa uma prova OPACA, curta, emitida pelo
 * backend após autenticação adicional — NUNCA uma senha bruta.
 */
export type RevokeManagerMembershipInput = {
  memberId: string;
  reason: string;
  sensitiveActionProof: string;
};

// ---------------------------------------------------------------------------
// Managers
// ---------------------------------------------------------------------------

export type PartnerManagerSummary = {
  memberId: string;
  name: string | null;
  role: PortalRole;
  status: MemberStatus;
  joinedAt: string | null;
  lastOperationalActivityAt: string | null;
  validationsCount: number | null;
};

// ---------------------------------------------------------------------------
// Transações / validações
// ---------------------------------------------------------------------------

/**
 * Recorte permitido ao Site. NUNCA inclui jornada, horas, sessões,
 * documentos, faltas, grupo, sequência operacional, localização ou
 * histórico geral do usuário do App.
 */
export type PartnerTransaction = {
  transactionId: string;
  unitLabel: string | null;
  operatorName: string | null;
  operatorRole: PortalRole | null;
  benefitTypeLabel: string | null;
  tokenState: "open" | "expired" | "revoked" | "used" | null;
  result: "confirmed" | "refused" | "expired" | "completed" | null;
  occurredAt: string | null;
};

// ---------------------------------------------------------------------------
// Validação de benefício
// ---------------------------------------------------------------------------

export type ValidationRequest = {
  unitId: string;
  code: string;
};

export type ValidationOutcome = {
  state: "confirmed" | "refused" | "expired" | "completed";
  benefitTypeLabel: string | null;
  unitLabel: string | null;
  deadlineAt: string | null;
  message: string | null;
};

// ---------------------------------------------------------------------------
// Limites de campos públicos (Fase 2A §14.1)
// ---------------------------------------------------------------------------

export const PUBLIC_FIELD_LIMITS = {
  partner_display_name: 160,
  branch_display_name: 120,
  branch_location_label: 160,
  branch_city_name: 100,
} as const;

/** UF válida: exatamente duas letras maiúsculas dentro das 27 oficiais. */
export const UFS_27: readonly string[] = [
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS",
  "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC",
  "SP", "SE", "TO",
];

export function isValidStateCode(v: unknown): v is string {
  return typeof v === "string" && /^[A-Z]{2}$/.test(v) && UFS_27.includes(v);
}
