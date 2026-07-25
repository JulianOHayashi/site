import type {
  CommercialExclusivityStatus,
  CommercialOpportunityStatus,
} from "./types";

/** Rótulos em PT-BR para status de oportunidade. */
export const OPPORTUNITY_STATUS_LABEL: Record<
  CommercialOpportunityStatus,
  string
> = {
  available: "Disponível",
  reserved: "Reservado",
  payment_pending: "Pagamento pendente",
  contracted: "Contratado",
};

/** Rótulos em PT-BR para status da exclusividade (status resumido). */
export const EXCLUSIVITY_STATUS_LABEL: Record<
  CommercialExclusivityStatus,
  string
> = {
  forming: "Aguardando formação",
  formed: "Formação concluída",
  start_scheduled: "Início previsto",
  operation_authorized: "Operação autorizada",
  operation_started: "Operação iniciada",
  operation_completed: "Operação concluída",
  operation_paused: "Operação pausada",
};

/** Classe visual (não depende só de cor — sempre acompanha rótulo textual). */
export function opportunityStatusTone(
  status: CommercialOpportunityStatus
): string {
  switch (status) {
    case "available":
      return "border-green-300 bg-green-50 text-green-800";
    case "reserved":
      return "border-amarelo bg-amarelo/20 text-tinta";
    case "payment_pending":
      return "border-ciano bg-ciano/10 text-ciano";
    case "contracted":
      return "border-tinta bg-tinta text-white";
  }
}
