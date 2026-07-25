import { supabase } from "../lib/supabase";
import type {
  CommercialFormationResponse,
  CommercialOpportunity,
  CommercialExclusivityStatus,
  CommercialOpportunityStatus,
} from "../domain/commercial/types";

/**
 * Serviço comercial — única porta de entrada para as RPCs de leitura.
 *
 * NÃO acessa as tabelas diretamente, NÃO calcula status como autoridade,
 * NÃO altera dados, NÃO cria oportunidade/reserva. Apenas chama as RPCs,
 * valida minimamente o formato e normaliza erros — nunca expõe mensagem
 * técnica do Supabase ao visitante.
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

const EXCLUSIVITY_STATUSES: CommercialExclusivityStatus[] = [
  "forming",
  "formed",
  "start_scheduled",
  "operation_authorized",
  "operation_started",
  "operation_completed",
  "operation_paused",
];
const OPPORTUNITY_STATUSES: CommercialOpportunityStatus[] = [
  "available",
  "reserved",
  "payment_pending",
  "contracted",
];

function asRecord(v: unknown): Record<string, unknown> {
  if (typeof v !== "object" || v === null) {
    throw new CommercialError("unexpected_response");
  }
  return v as Record<string, unknown>;
}

/**
 * Resolve a formação comercial atual para UF + cidade.
 * Lança CommercialError com kind apropriado.
 */
export async function fetchCurrentFormation(
  uf: string,
  city: string
): Promise<CommercialFormationResponse> {
  if (!supabase) {
    throw new CommercialError("not_configured");
  }

  let data: unknown;
  try {
    const res = await supabase.rpc("get_current_commercial_formation", {
      p_uf: uf,
      p_city: city,
    });
    if (res.error) {
      throw new CommercialError("network_error", res.error.message);
    }
    data = res.data;
  } catch (e) {
    if (e instanceof CommercialError) throw e;
    throw new CommercialError("network_error");
  }

  const root = asRecord(data);
  const regionAvailable = root.region_available === true;

  if (!regionAvailable) {
    return {
      regionAvailable: false,
      exclusivityAvailable: false,
      region: null,
      exclusivity: null,
      summary: null,
      opportunities: [],
    };
  }

  const regionRaw = asRecord(root.region);
  const region = {
    regionId: String(regionRaw.region_id ?? ""),
    regionName: String(regionRaw.region_name ?? ""),
    regionSlug: String(regionRaw.region_slug ?? ""),
    uf: String(regionRaw.uf ?? ""),
    cityName: String(regionRaw.city_name ?? ""),
    isActive: regionRaw.is_active === true,
  };

  const exclusivityAvailable = root.exclusivity_available === true;
  if (!exclusivityAvailable) {
    return {
      regionAvailable: true,
      exclusivityAvailable: false,
      region,
      exclusivity: null,
      summary: null,
      opportunities: [],
    };
  }

  const excRaw = asRecord(root.exclusivity);
  const status = String(excRaw.status ?? "");
  if (!EXCLUSIVITY_STATUSES.includes(status as CommercialExclusivityStatus)) {
    throw new CommercialError("unexpected_response");
  }

  const sumRaw = asRecord(root.summary);
  const summary = {
    totalOpportunities: Number(sumRaw.total_opportunities ?? 0),
    contractedOpportunities: Number(sumRaw.contracted_opportunities ?? 0),
    totalUnits: Number(sumRaw.total_units ?? 0),
    contractedUnits: Number(sumRaw.contracted_units ?? 0),
    formationPercent: Number(sumRaw.formation_percent ?? 0),
    isComplete: sumRaw.is_complete === true,
  };

  const oppsRaw = root.opportunities;
  if (!Array.isArray(oppsRaw)) {
    throw new CommercialError("unexpected_response");
  }

  const opportunities: CommercialOpportunity[] = oppsRaw.map((o) => {
    const r = asRecord(o);
    const oppStatus = String(r.status ?? "");
    if (
      !OPPORTUNITY_STATUSES.includes(oppStatus as CommercialOpportunityStatus)
    ) {
      throw new CommercialError("unexpected_response");
    }
    return {
      nicheCode: String(r.niche_code ?? "") as CommercialOpportunity["nicheCode"],
      displayName: String(r.display_name ?? ""),
      contractedQuantity: Number(r.contracted_quantity ?? 0),
      status: oppStatus as CommercialOpportunityStatus,
      sortOrder: Number(r.sort_order ?? 0),
    };
  });

  return {
    regionAvailable: true,
    exclusivityAvailable: true,
    region,
    exclusivity: {
      sequenceNumber: Number(excRaw.sequence_number ?? 0),
      status: status as CommercialExclusivityStatus,
      isCurrent: excRaw.is_current === true,
      plannedStartAt:
        typeof excRaw.planned_start_at === "string"
          ? excRaw.planned_start_at
          : null,
    },
    summary,
    opportunities,
  };
}
