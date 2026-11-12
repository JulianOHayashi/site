import { Link } from "react-router-dom";
import { formatarCentavos, type PublicNichePricing } from "../../domain/pricing/contractPricing";
import { previaIndividualSF15 } from "../../domain/pricing/previewSF15";
import type { CommercialOpportunity } from "../../domain/commercial/types";
import {
  nicheByCode,
  isFormationNicheCode,
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
  precoVigente = null,
}: {
  opportunity: CommercialOpportunity;
  precoVigente?: PublicNichePricing | null;
}) {
  const meta = isFormationNicheCode(opportunity.nicheCode)
    ? nicheByCode(opportunity.nicheCode)
    : null;
  const nome = meta?.displayName ?? opportunity.displayName;
  const statusLabel = OPPORTUNITY_STATUS_LABEL[opportunity.status];
  const previa = precoVigente ? previaIndividualSF15(precoVigente) : null;

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
        {opportunity.segment && (
          <div className="flex justify-between">
            <dt className="text-tinta/60">Segmento</dt>
            <dd className="font-semibold">{opportunity.segment.name}</dd>
          </div>
        )}
      </dl>

      {opportunity.acceptsSegment && !opportunity.segment && (
        <p className="mt-3 text-xs text-tinta/60">
          {opportunity.requiresSegment
            ? "Posição para um segmento comercial autorizado pela SmallFlags."
            : "Também pode ser ocupada por um segmento de Outros."}
        </p>
      )}

      {precoVigente && (
        <div className="mt-4 rounded-xl border border-tinta/15 p-3 text-sm">
          <p className="font-semibold">Preços vigentes · servidor</p>
          <div className="mt-2 flex justify-between gap-2">
            <span className="text-tinta/70">Não fidelizado</span>
            <strong className="tabular-nums">{formatarCentavos(precoVigente.founding.economicValueCents)}</strong>
          </div>
          <div className="mt-1 flex justify-between gap-2">
            <span className="text-tinta/70">Fidelizado</span>
            <strong className="tabular-nums">{formatarCentavos(precoVigente.fidelized.economicValueCents)}</strong>
          </div>
        </div>
      )}

      {previa && (
        <div className="mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">
          <p className="font-bold">Proposta SF-v1.5 · NÃO VIGENTE</p>
          <div className="mt-2 flex justify-between gap-2">
            <span>Novo anunciante</span>
            <strong className="tabular-nums">{formatarCentavos(previa.novoCentavos)}</strong>
          </div>
          <div className="mt-1 flex justify-between gap-2">
            <span>Fidelizado com reutilização</span>
            <strong className="tabular-nums">{formatarCentavos(previa.fidelizadoReutilizacaoCentavos)}</strong>
          </div>
          <p className="mt-2 text-xs">A proposta inclui 84 bandeiras novas por anunciante não fidelizado. Reutilização condicionada à inspeção. O checkout mantém os preços vigentes.</p>
        </div>
      )}

      <p className="mt-3 rounded-xl bg-papel2 px-3 py-2 text-xs text-tinta/70">
        Nicho contratado integralmente — não há venda de unidades avulsas.
      </p>

      <div className="mt-auto pt-4">
        <Link
          to={`/oportunidades/${slugByCode(opportunity.nicheCode)}`}
          className="btn-secondary w-full text-center"
        >
          {opportunity.status === "available"
            ? "Ver oportunidade"
            : "Ver próxima exclusividade"}
        </Link>
      </div>
    </div>
  );
}
