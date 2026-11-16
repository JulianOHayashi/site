import { Link } from "react-router-dom";
import { formatarCentavos, type PublicNichePricing } from "../../domain/pricing/contractPricing";
import { apresentacaoOportunidade } from "../../domain/pricing/apresentacaoComercial";
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
 * Card de uma oportunidade comercial (uma posição inteira).
 *
 * Hierarquia comercial, nesta ordem:
 *   1. posição, quantidade contratual e situação;
 *   2. valor total da contratação, em destaque;
 *   3. quanto desse valor são contraprestações potenciais aos motoristas, e
 *      que a empresa pode cumpri-las com benefícios em produtos das suas lojas;
 *   4. a alternativa de contratar tudo em dinheiro (sem QA: o valor pode
 *      diferir do benefício direto; só o servidor diz se é igual);
 *   5. o link para o detalhe.
 *
 * Os números vêm do servidor (via `apresentacaoOportunidade`). Resposta
 * incompleta: o card mostra a oportunidade sem nenhum valor. Nada aqui
 * reserva, contrata ou muda preço.
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
  const ap = apresentacaoOportunidade(precoVigente);
  const somenteDinheiro = ap?.estado === "vigente" && !ap.beneficioDiretoHabilitado && ap.novo.valorDinheiroCentavos !== null;
  const tituloId = `oportunidade-${opportunity.nicheCode}`;

  return (
    <article
      aria-labelledby={tituloId}
      className="card flex h-full flex-col p-5 sm:p-6"
      data-testid={`card-${opportunity.nicheCode}`}
    >
      {/* 1. Posição, quantidade e situação */}
      <header className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <span aria-hidden className="text-2xl leading-none">
            {meta?.icon ?? "•"}
          </span>
          <div className="min-w-0">
            <h3 id={tituloId} className="text-lg font-bold leading-tight">
              {nome}
            </h3>
            <p className="mt-0.5 text-sm text-tinta/60">
              {opportunity.contractedQuantity} unidades comerciais
            </p>
          </div>
        </div>
        <span
          className={`shrink-0 rounded-full border px-2.5 py-1 text-xs font-semibold ${opportunityStatusTone(
            opportunity.status
          )}`}
        >
          {statusLabel}
        </span>
      </header>

      {ap ? (
        <>
          {/* 2. Valor total, em destaque */}
          <div className="mt-5" data-testid="valor-total">
            <p className="text-xs font-semibold uppercase tracking-wide text-tinta/55">
              Valor total da contratação
            </p>
            <p className="mt-1 font-display text-[2rem] font-bold leading-none tabular-nums sm:text-4xl">
              {formatarCentavos(somenteDinheiro ? ap.novo.valorDinheiroCentavos! : ap.novo.valorTotalCentavos)}
            </p>
            <p className="mt-1.5 text-xs text-tinta/60">
              Para novo anunciante{somenteDinheiro ? ", em dinheiro" : ap.mesmoValorNasDuasFormas ? "" : ", com benefício direto"}
            </p>
            {ap.estado === "previa" && (
              <p
                className="mt-2 inline-flex rounded-full border border-amber-300 bg-amber-50 px-2.5 py-0.5 text-xs font-semibold text-amber-900"
                data-testid="selo-previa"
              >
                Novo valor proposto · ainda não contratável
              </p>
            )}
          </div>

          {/* 3. Benefício direto: a vantagem operacional, sem promessa */}
          <div
            className="mt-4 rounded-xl border-l-4 border-vivo-ciano bg-vivo-ciano/10 px-4 py-3"
            data-testid="destaque-beneficio-direto"
          >
            <p className="text-sm text-tinta">
              Até{" "}
              <strong className="tabular-nums">
                {formatarCentavos(ap.participantes.contraprestacaoPotencialCentavos)}
              </strong>{" "}
              deste valor são contraprestações potenciais aos motoristas
              participantes.
            </p>
            <p className="mt-1.5 text-sm text-tinta/75">
              {somenteDinheiro
                ? "Na contratação disponível, essa contraprestação é financiada em dinheiro."
                : "Sua empresa pode cumprir essa parte com benefícios em produtos das suas lojas."}
            </p>
          </div>

          {/* 4. Alternativa em dinheiro */}
          <p className="mt-3 text-sm text-tinta/70" data-testid="alternativa-dinheiro">
            {somenteDinheiro
              ? "Somente DINHEIRO está disponível no momento, sem QA em produtos. A SmallFlags administra os repasses aos participantes elegíveis."
              : ap.mesmoValorNasDuasFormas
              ? "Prefere tudo em dinheiro? Também é possível: a SmallFlags administra os repasses aos participantes."
              : `Prefere tudo em dinheiro? Também é possível, sem os testes com produtos (${
                  ap.novo.valorDinheiroCentavos === null
                    ? "valor confirmado na proposta comercial"
                    : `valor total ${formatarCentavos(ap.novo.valorDinheiroCentavos)}`
                }): a SmallFlags administra os repasses aos participantes.`}
          </p>

          <p className="mt-3 text-xs text-tinta/55">
            {somenteDinheiro
              ? "Benefício direto indisponível no momento."
              : "Benefício direto não reduz o valor total e depende do contrato e da elegibilidade dos participantes."}
          </p>
        </>
      ) : (
        <p className="mt-5 text-sm text-tinta/60" data-testid="valor-indisponivel">
          Valores em atualização. Consulte o detalhe da oportunidade.
        </p>
      )}

      {/* 5. Detalhe (o aviso de segmento fica aqui para alinhar os preços) */}
      <div className="mt-auto space-y-3 pt-5">
        {opportunity.segment ? (
          <p className="text-sm text-tinta/70">
            Segmento: <span className="font-semibold">{opportunity.segment.name}</span>
          </p>
        ) : opportunity.acceptsSegment ? (
          <p className="text-xs text-tinta/60">
            {opportunity.requiresSegment
              ? "Para um segmento comercial autorizado pela SmallFlags."
              : "Também pode ser ocupada por um segmento de Outros."}
          </p>
        ) : null}

        <Link
          to={`/oportunidades/${slugByCode(opportunity.nicheCode)}`}
          className="btn-secondary w-full text-center"
          aria-label={`${
            opportunity.status === "available" ? "Ver oportunidade" : "Ver próxima exclusividade"
          }: ${nome}`}
        >
          {opportunity.status === "available"
            ? "Ver oportunidade"
            : "Ver próxima exclusividade"}
        </Link>
      </div>
    </article>
  );
}
