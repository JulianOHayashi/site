import { Link } from "react-router-dom";
import type { CommercialOpportunity } from "../../domain/commercial/types";
import {
  nicheByCode,
  isNicheCode,
  slugByCode,
} from "../../domain/commercial/niches";
import {
  OPPORTUNITY_STATUS_LABEL,
  opportunityStatusTone,
} from "../../domain/commercial/status";

/**
 * Card de uma oportunidade comercial (um nicho completo).
 *
 * Mostra nome, quantidade completa (server-side), status, descrição curta
 * e a indicação de contratação integral. "Ver oportunidade" só aparece
 * para status available — e ainda assim NÃO permite reservar nem pagar
 * (contratação será liberada em fase posterior).
 */
export default function OpportunityCard({
  opportunity,
}: {
  opportunity: CommercialOpportunity;
}) {
  const meta = isNicheCode(opportunity.nicheCode)
    ? nicheByCode(opportunity.nicheCode)
    : null;
  const nome = meta?.displayName ?? opportunity.displayName;
  const statusLabel = OPPORTUNITY_STATUS_LABEL[opportunity.status];

  return (
    <div className="card flex h-full flex-col p-6">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2">
          <span aria-hidden className="text-2xl">
            {meta?.icon ?? "•"}
          </span>
          <h3 className="text-lg font-bold">{nome}</h3>
        </div>
        <span
          className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${opportunityStatusTone(
            opportunity.status
          )}`}
        >
          {statusLabel}
        </span>
      </div>

      <p className="mt-3 text-sm text-tinta/60">
        {meta?.shortDescription ?? "Oportunidade comercial da região."}
      </p>

      <dl className="mt-4 space-y-1 text-sm">
        <div className="flex justify-between">
          <dt className="text-tinta/60">Quantidade</dt>
          <dd className="font-bold">{opportunity.contractedQuantity} unidades</dd>
        </div>
      </dl>

      <p className="mt-3 rounded-xl bg-papel2 px-3 py-2 text-xs text-tinta/70">
        Nicho contratado integralmente — não há venda de unidades avulsas.
      </p>

      <div className="mt-auto pt-4">
        {opportunity.status === "available" ? (
          <Link
            to={`/oportunidades/${slugByCode(opportunity.nicheCode)}`}
            className="btn-secondary w-full text-center"
          >
            Ver oportunidade
          </Link>
        ) : (
          <span className="block w-full rounded-xl bg-papel2 py-2.5 text-center text-sm font-semibold text-tinta/50">
            {statusLabel}
          </span>
        )}
      </div>
    </div>
  );
}
