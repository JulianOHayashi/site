import type {
  CommercialFormationSummary,
  CommercialExclusivityStatus,
} from "../../domain/commercial/types";
import { EXCLUSIVITY_STATUS_LABEL } from "../../domain/commercial/status";

/**
 * Progresso da formação comercial.
 *
 * Exibe nichos contratados de 6, unidades correspondentes de 84, percentual
 * e status da exclusividade. O percentual vem do resumo do backend (ou é
 * apenas apresentado a partir dele) — NUNCA usado para alterar estado. A
 * formação só está completa quando o backend indicar (summary.isComplete).
 */
export default function FormationProgress({
  summary,
  status,
}: {
  summary: CommercialFormationSummary;
  status: CommercialExclusivityStatus;
}) {
  const pct = Math.max(0, Math.min(100, summary.formationPercent));

  return (
    <div className="card p-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-xl">Formação comercial</h2>
        <span className="rounded-full bg-papel2 px-3 py-1 text-xs font-semibold">
          {EXCLUSIVITY_STATUS_LABEL[status]}
        </span>
      </div>

      <div className="mt-4">
        <div
          className="h-3 w-full overflow-hidden rounded-full bg-papel2"
          role="progressbar"
          aria-valuenow={pct}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label="Percentual de formação comercial"
        >
          <div
            className="h-full rounded-full bg-magenta transition-all"
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      <dl className="mt-4 grid grid-cols-2 gap-4 text-sm">
        <div>
          <dt className="text-tinta/60">Nichos contratados</dt>
          <dd className="font-display text-2xl font-bold">
            {summary.contractedOpportunities}
            <span className="text-base text-tinta/40"> de 6</span>
          </dd>
        </div>
        <div>
          <dt className="text-tinta/60">Unidades correspondentes</dt>
          <dd className="font-display text-2xl font-bold">
            {summary.contractedUnits}
            <span className="text-base text-tinta/40"> de 84</span>
          </dd>
        </div>
      </dl>

      {summary.isComplete ? (
        <p className="mt-4 rounded-xl border border-green-300 bg-green-50 px-3 py-2 text-sm font-semibold text-green-800">
          Formação concluída — os seis nichos foram contratados.
        </p>
      ) : (
        <p className="mt-4 text-xs text-tinta/50">
          A formação comercial se completa quando os seis nichos estiverem
          contratados (84 unidades correspondentes).
        </p>
      )}
    </div>
  );
}
