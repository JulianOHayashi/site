import { isCommercialNicheCode } from "../domain/commercial/niches";
import type {
  CommercialFormationResponse,
  CommercialOpportunity,
  CommercialExclusivityStatus,
  CommercialOpportunityStatus,
  CommercialNicheCode,
  CommercialRegion,
  CommercialExclusivity,
} from "../domain/commercial/types";

/**
 * Validação e parsing PUROS da resposta de get_current_commercial_formation.
 *
 * Sem cliente Supabase — determinístico e testável isoladamente. Toda a
 * política do contrato da Fase 1 vive aqui. Qualquer violação vira
 * CommercialError("unexpected_response"). Nunca completa dados ausentes com
 * mock nem ajusta silenciosamente valores. Nada de casting como validação.
 */

export type CommercialErrorKind =
  | "not_configured"
  | "region_unavailable"
  | "formation_unavailable"
  | "network_error"
  | "unexpected_response";

export class CommercialError extends Error {
  kind: CommercialErrorKind;
  constructor(kind: CommercialErrorKind, message?: string) {
    super(message ?? kind);
    this.kind = kind;
    this.name = "CommercialError";
  }
}

// ---------------------------------------------------------------------------
// Contrato canônico da Fase 1 (usado só para VALIDAR — o backend é a autoridade)
// ---------------------------------------------------------------------------
export const EXPECTED_QUANTITY_BY_CODE: Record<CommercialNicheCode, number> = {
  supermarket: 24,
  pharmacy: 12,
  womens_clothing: 12,
  mens_clothing: 12,
  womens_footwear: 12,
  mens_footwear: 12,
};
export const EXPECTED_SORT_ORDER_BY_CODE: Record<CommercialNicheCode, number> = {
  supermarket: 1,
  pharmacy: 2,
  womens_clothing: 3,
  mens_clothing: 4,
  womens_footwear: 5,
  mens_footwear: 6,
};
export const EXPECTED_OPPORTUNITY_COUNT = 6;
export const EXPECTED_TOTAL_UNITS = 84;

const UFS_27 = new Set([
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS",
  "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC",
  "SP", "SE", "TO",
]);

const EXCLUSIVITY_STATUSES: readonly CommercialExclusivityStatus[] = [
  "forming",
  "formed",
  "start_scheduled",
  "operation_authorized",
  "operation_started",
  "operation_completed",
  "operation_paused",
];
const OPPORTUNITY_STATUSES: readonly CommercialOpportunityStatus[] = [
  "available",
  "reserved",
  "payment_pending",
  "contracted",
];

function isExclusivityStatus(v: unknown): v is CommercialExclusivityStatus {
  return (
    typeof v === "string" &&
    EXCLUSIVITY_STATUSES.includes(v as CommercialExclusivityStatus)
  );
}
function isOpportunityStatus(v: unknown): v is CommercialOpportunityStatus {
  return (
    typeof v === "string" &&
    OPPORTUNITY_STATUSES.includes(v as CommercialOpportunityStatus)
  );
}
function isValidUf27(v: unknown): v is string {
  return typeof v === "string" && UFS_27.has(v.trim().toUpperCase());
}

function asRecord(v: unknown): Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) {
    throw new CommercialError("unexpected_response");
  }
  return v as Record<string, unknown>;
}
function isStrictInteger(v: unknown): v is number {
  return typeof v === "number" && Number.isInteger(v);
}
function isPositiveInteger(v: unknown): v is number {
  return isStrictInteger(v) && v > 0;
}
function nonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim().length > 0;
}
function isNullOrValidDate(v: unknown): boolean {
  if (v === null || v === undefined) return true;
  if (typeof v !== "string") return false;
  return !Number.isNaN(Date.parse(v));
}
function fail(): never {
  throw new CommercialError("unexpected_response");
}

// ---------------------------------------------------------------------------
// Região (seção 8)
// ---------------------------------------------------------------------------
function parseRegion(raw: unknown): CommercialRegion {
  const r = asRecord(raw);
  if (!nonEmptyString(r.region_id)) fail();
  if (!nonEmptyString(r.region_name)) fail();
  if (!nonEmptyString(r.region_slug)) fail();
  if (!isValidUf27(r.uf)) fail();
  if (r.is_active !== true) fail(); // ativa exige exatamente true
  if (!nonEmptyString(r.city_name)) fail();
  return {
    regionId: r.region_id,
    regionName: r.region_name,
    regionSlug: r.region_slug,
    uf: r.uf.trim().toUpperCase(),
    cityName: r.city_name,
    isActive: true,
  };
}

// ---------------------------------------------------------------------------
// Exclusividade (seção 9)
// ---------------------------------------------------------------------------
function parseExclusivity(
  raw: unknown,
  region: CommercialRegion
): CommercialExclusivity {
  const e = asRecord(raw);
  if (!nonEmptyString(e.id)) fail(); // identificador não vazio
  if (!nonEmptyString(e.region_id) || e.region_id !== region.regionId) fail();
  if (!isPositiveInteger(e.sequence_number)) fail();
  if (!isExclusivityStatus(e.status)) fail();
  if (e.is_current !== true) fail(); // exclusividade ATUAL exige true
  if (!isNullOrValidDate(e.planned_start_at)) fail();
  return {
    id: e.id,
    regionId: e.region_id,
    sequenceNumber: e.sequence_number,
    status: e.status,
    isCurrent: true,
    plannedStartAt:
      typeof e.planned_start_at === "string" ? e.planned_start_at : null,
  };
}

// ---------------------------------------------------------------------------
// Oportunidades (seção 10)
// ---------------------------------------------------------------------------
function parseOpportunities(
  raw: unknown,
  exclusivity: CommercialExclusivity
): CommercialOpportunity[] {
  if (!Array.isArray(raw)) fail();
  if (raw.length !== EXPECTED_OPPORTUNITY_COUNT) fail();

  const codigosVistos = new Set<CommercialNicheCode>();
  const ordensVistas = new Set<number>();
  let soma = 0;

  const opportunities = raw.map((item): CommercialOpportunity => {
    const o = asRecord(item);

    if (!nonEmptyString(o.id)) fail(); // identificador não vazio
    if (
      !nonEmptyString(o.exclusivity_id) ||
      o.exclusivity_id !== exclusivity.id
    ) {
      fail();
    }

    const nicheCode = o.niche_code;
    if (!isCommercialNicheCode(nicheCode)) fail();
    if (codigosVistos.has(nicheCode)) fail(); // duplicidade de código
    codigosVistos.add(nicheCode);

    if (!nonEmptyString(o.display_name)) fail(); // nome exibido não vazio

    const qty = o.contracted_quantity;
    if (!isPositiveInteger(qty)) fail();
    if (qty !== EXPECTED_QUANTITY_BY_CODE[nicheCode]) fail();
    soma += qty;

    if (!isOpportunityStatus(o.status)) fail();

    const sortOrder = o.sort_order;
    if (!isPositiveInteger(sortOrder)) fail();
    if (sortOrder !== EXPECTED_SORT_ORDER_BY_CODE[nicheCode]) fail(); // ordem canônica
    if (ordensVistas.has(sortOrder)) fail(); // duplicidade de ordem
    ordensVistas.add(sortOrder);

    return {
      id: o.id,
      exclusivityId: o.exclusivity_id,
      nicheCode,
      displayName: o.display_name,
      contractedQuantity: qty,
      status: o.status,
      sortOrder,
    };
  });

  if (codigosVistos.size !== EXPECTED_OPPORTUNITY_COUNT) fail();
  if (ordensVistas.size !== EXPECTED_OPPORTUNITY_COUNT) fail();
  if (soma !== EXPECTED_TOTAL_UNITS) fail();

  return opportunities;
}

// ---------------------------------------------------------------------------
// Resumo (seção 11)
// ---------------------------------------------------------------------------
function parseSummary(
  raw: unknown,
  opportunities: CommercialOpportunity[]
): CommercialFormationResponse["summary"] {
  const s = asRecord(raw);

  const totalOpportunities = s.total_opportunities;
  const contractedOpportunities = s.contracted_opportunities;
  const totalUnits = s.total_units;
  const contractedUnits = s.contracted_units;
  const formationPercent = s.formation_percent;
  const isComplete = s.is_complete;

  if (totalOpportunities !== EXPECTED_OPPORTUNITY_COUNT) fail();
  if (totalUnits !== EXPECTED_TOTAL_UNITS) fail();
  if (
    !isStrictInteger(contractedOpportunities) ||
    contractedOpportunities < 0 ||
    contractedOpportunities > EXPECTED_OPPORTUNITY_COUNT
  ) {
    fail();
  }
  if (
    !isStrictInteger(contractedUnits) ||
    contractedUnits < 0 ||
    contractedUnits > EXPECTED_TOTAL_UNITS
  ) {
    fail();
  }
  if (
    typeof formationPercent !== "number" ||
    Number.isNaN(formationPercent) ||
    formationPercent < 0 ||
    formationPercent > 100
  ) {
    fail();
  }
  if (typeof isComplete !== "boolean") fail();

  // Coerência com os cards.
  const contratados = opportunities.filter((o) => o.status === "contracted");
  const somaContratada = contratados.reduce(
    (acc, o) => acc + o.contractedQuantity,
    0
  );
  if (contractedOpportunities !== contratados.length) fail();
  if (contractedUnits !== somaContratada) fail();

  // Percentual coerente com a MESMA fórmula do SQL: round(100 * contratados / 6).
  // Tolerância máxima de 0,01 (normaliza divergência decimal).
  const percentEsperado = Math.round(
    (100 * contratados.length) / EXPECTED_OPPORTUNITY_COUNT
  );
  if (Math.abs(formationPercent - percentEsperado) > 0.01) fail();

  // Completo SOMENTE com os seis nichos contratados E 84 unidades contratadas.
  const completo =
    contratados.length === EXPECTED_OPPORTUNITY_COUNT &&
    somaContratada === EXPECTED_TOTAL_UNITS;
  if (isComplete !== completo) fail();

  return {
    totalOpportunities,
    contractedOpportunities,
    totalUnits,
    contractedUnits,
    formationPercent,
    isComplete,
  };
}

// ---------------------------------------------------------------------------
// Parser completo (estados de ausência de região/exclusividade são VÁLIDOS)
// ---------------------------------------------------------------------------
export function parseFormationResponse(
  data: unknown
): CommercialFormationResponse {
  const root = asRecord(data);

  // region_available deve ser um booleano REAL (ausente/string/número → rejeita).
  if (typeof root.region_available !== "boolean") fail();
  if (root.region_available === false) {
    return {
      regionAvailable: false,
      exclusivityAvailable: false,
      region: null,
      exclusivity: null,
      summary: null,
      opportunities: [],
    };
  }

  const region = parseRegion(root.region);

  // exclusivity_available deve ser um booleano REAL (só é avaliado quando
  // region_available = true; ausente/string/número aqui → rejeita).
  if (typeof root.exclusivity_available !== "boolean") fail();
  if (root.exclusivity_available === false) {
    return {
      regionAvailable: true,
      exclusivityAvailable: false,
      region,
      exclusivity: null,
      summary: null,
      opportunities: [],
    };
  }

  const exclusivity = parseExclusivity(root.exclusivity, region);
  const opportunities = parseOpportunities(root.opportunities, exclusivity);
  const summary = parseSummary(root.summary, opportunities);

  return {
    regionAvailable: true,
    exclusivityAvailable: true,
    region,
    exclusivity,
    summary,
    opportunities,
  };
}
