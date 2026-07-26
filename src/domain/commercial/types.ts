/**
 * Domínio comercial do Site BDFlow — tipos canônicos (Fase 1).
 *
 * Regras:
 * - status e código de nicho usam unions literais (nunca string genérica);
 * - a quantidade contratual EXIBIDA vem sempre da resposta server-side;
 * - o frontend nunca é autoridade sobre quantidade, status ou formação.
 */

export type CommercialNicheCode =
  | "supermarket"
  | "pharmacy"
  | "womens_clothing"
  | "mens_clothing"
  | "womens_footwear"
  | "mens_footwear";

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
  code: CommercialNicheCode;
  displayName: string;
  sortOrder: number;
  shortDescription: string;
  icon: string;
}

/** Oportunidade retornada pelo backend (dados públicos). */
export interface CommercialOpportunity {
  id: string;
  exclusivityId: string;
  nicheCode: CommercialNicheCode;
  displayName: string;
  contractedQuantity: number;
  status: CommercialOpportunityStatus;
  sortOrder: number;
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
