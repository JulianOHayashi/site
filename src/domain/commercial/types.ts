/**
 * Domínio comercial do Site SmallFlags — tipos canônicos (Fase 1).
 *
 * Regras:
 * - status e código de nicho usam unions literais (nunca string genérica);
 * - a quantidade contratual EXIBIDA vem sempre da resposta server-side;
 * - o frontend nunca é autoridade sobre quantidade, status ou formação.
 */

/**
 * Posições comerciais ATIVAS (migration 20261103120000): seis posições, 84
 * unidades. "footwear" unifica calçados; "others" é a posição de segmento
 * variável. Supermercado (24) nunca é substituído.
 */
export type CommercialNicheCode =
  | "supermarket"
  | "pharmacy"
  | "womens_clothing"
  | "mens_clothing"
  | "footwear"
  | "others";

/**
 * Códigos HISTÓRICOS de calçados. Continuam existindo no banco para pedidos e
 * registros antigos; não são vendidos de novo. O navegador só os aceita na
 * resposta da formação enquanto o backend ainda não recebeu a migration.
 */
export type LegacyCommercialNicheCode = "womens_footwear" | "mens_footwear";

/** Código de posição que a vitrine pode receber do servidor. */
export type FormationNicheCode = CommercialNicheCode | LegacyCommercialNicheCode;

/** Segmento ocupando uma posição (somente dados públicos). */
export interface OccupyingSegment {
  code: string;
  name: string;
}

/** Segmento aprovado do catálogo público. */
export interface CommercialSegment {
  id: string;
  code: string;
  name: string;
  description: string | null;
  overlapsNicheCode: string | null;
}

export type CommercialExclusivityStatus =
  | "forming"
  | "formed"
  | "start_scheduled"
  | "operation_authorized"
  | "operation_started"
  | "operation_completed"
  | "operation_paused";

export type CommercialOpportunityStatus =
  | "available"
  | "reserved"
  | "payment_pending"
  | "contracted";

export interface CommercialRegion {
  regionId: string;
  regionName: string;
  regionSlug: string;
  uf: string;
  cityName: string;
  isActive: boolean;
}

/** Território persistido no navegador (apenas navegação; backend é autoridade). */
export interface CommercialTerritory {
  uf: string;
  city: string;
  regionId: string | null;
  regionName: string | null;
  regionStatus: "active" | "unavailable";
  resolvedAt: string;
}

/** Metadados de apresentação de um nicho (fonte local, não autoridade). */
export interface CommercialNiche {
  code: FormationNicheCode;
  displayName: string;
  sortOrder: number;
  shortDescription: string;
  icon: string;
}

/** Oportunidade retornada pelo backend (dados públicos). */
export interface CommercialOpportunity {
  id: string;
  exclusivityId: string;
  nicheCode: FormationNicheCode;
  displayName: string;
  contractedQuantity: number;
  status: CommercialOpportunityStatus;
  sortOrder: number;
  /** A posição pode ser ocupada por um segmento de Outros (decisão do servidor). */
  acceptsSegment: boolean;
  /** A posição só existe com segmento (Outros). */
  requiresSegment: boolean;
  /** Segmento que ocupa a posição agora, se houver. */
  segment: OccupyingSegment | null;
}

export interface CommercialExclusivity {
  id: string;
  regionId: string;
  sequenceNumber: number;
  status: CommercialExclusivityStatus;
  isCurrent: boolean;
  plannedStartAt: string | null;
}

export interface CommercialFormationSummary {
  totalOpportunities: number;
  contractedOpportunities: number;
  totalUnits: number;
  contractedUnits: number;
  formationPercent: number;
  isComplete: boolean;
}

/** Resposta consolidada de get_current_commercial_formation. */
export interface CommercialFormationResponse {
  regionAvailable: boolean;
  exclusivityAvailable: boolean;
  region: CommercialRegion | null;
  exclusivity: CommercialExclusivity | null;
  summary: CommercialFormationSummary | null;
  opportunities: CommercialOpportunity[];
}
