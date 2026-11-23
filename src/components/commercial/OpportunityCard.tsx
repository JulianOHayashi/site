import type { ReactNode } from "react";
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
 * Card resumido de uma oportunidade comercial (uma posição inteira).
 *
 * Vitrine simples, nesta ordem:
 *   1. posição, unidades comerciais, situação real e o selo de exclusividade
 *      (cada posição é vendida a uma única empresa por exclusividade): "de
 *      Nicho" nas cinco posições de nicho; "por Segmento" em Outros, que exige
 *      a definição de um segmento comercial;
 *   2. valor total da primeira contratação — o MAIOR número do card;
 *   3. até quanto desse valor vai aos motoristas participantes, cumprível em
 *      produtos da própria loja (ou financiado em dinheiro, quando o servidor
 *      habilita só o DINHEIRO);
 *   4. produção das bandeiras, com o custo nominal já incluído no total;
 *   5. renovação fidelizada sem novas bandeiras, com a mesma contraprestação
 *      potencial aos motoristas;
 *   6. "Ver oportunidade", que leva ao detalhe — nunca ao checkout.
 *
 * Explicações técnicas (participações, modalidades, critérios de fidelização,
 * QA, condições) ficam no detalhe (`PainelPreco`), que também mantém o aviso
 * de que a prévia SF-v1.5 ainda não é contratável. Aqui, a prévia é marcada
 * de forma compacta.
 *
 * Todos os números vêm de `apresentacaoOportunidade` (servidor validado).
 * Resposta incompleta: o card mostra a oportunidade sem nenhum valor. Nada
 * aqui reserva, contrata ou muda preço.
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
  const disponivel = opportunity.status === "available";
  const ap = apresentacaoOportunidade(precoVigente);
  const somenteDinheiro = ap?.estado === "vigente" && !ap.beneficioDiretoHabilitado && ap.novo.valorDinheiroCentavos !== null;
  const tituloId = `oportunidade-${opportunity.nicheCode}`;
  const seloExclusividade = opportunity.nicheCode === "others"
    ? "Exclusividade por Segmento"
    : "Exclusividade de Nicho";

  const totalCentavos = !ap ? null : somenteDinheiro ? ap.novo.valorDinheiroCentavos : ap.novo.valorTotalCentavos;
  // Renovação fidelizada na modalidade habilitada; sem valor validado, não aparece.
  const renovacaoCentavos = !ap ? null
    : somenteDinheiro ? ap.fidelizado.valorDinheiroCentavos
    : ap.fidelizado.valorTotalCentavos;
  const mostrarRenovacao = !!ap && ap.fidelizado.reutilizaBandeiras && renovacaoCentavos !== null;
  const motoristas = ap ? formatarCentavos(ap.participantes.contraprestacaoPotencialCentavos) : "";
  const modalidade = somenteDinheiro ? " · em dinheiro"
    : ap?.mesmoValorNasDuasFormas ? "" : " · com benefício direto";

  return (
    <article
      aria-labelledby={tituloId}
      className="flex h-full flex-col rounded-2xl border border-borda bg-papel p-4 font-body shadow-painel sm:p-5"
      data-testid={`card-${opportunity.nicheCode}`}
    >
      {/* 1. Posição, unidades, situação e exclusividade */}
      <header>
        <div className="flex items-center gap-3">
          <span
            aria-hidden
            className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl border border-borda bg-superficie2 text-2xl leading-none"
          >
            {meta?.icon ?? "•"}
          </span>
          <div className="min-w-0">
            <h3 id={tituloId} className="font-display text-xl font-bold leading-tight">
              {nome}
            </h3>
            <p className="mt-0.5 text-sm text-suave">
              {opportunity.contractedQuantity} unidades comerciais
            </p>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
          <p
            className="inline-flex items-center gap-1.5 rounded-full border-2 border-transparent py-1 pl-1.5 pr-3 font-display text-sm font-bold text-white"
            style={{
              background:
                "linear-gradient(rgb(var(--sf-noite)), rgb(var(--sf-noite))) padding-box, var(--sf-gradiente) border-box",
            }}
            data-testid="selo-exclusividade"
          >
            <IconeEscudo />
            {seloExclusividade}
          </p>
          <span
            className={`inline-flex shrink-0 items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-semibold ${opportunityStatusTone(
              opportunity.status
            )}`}
            data-testid="status-oportunidade"
          >
            {disponivel && <IconeCheck />}
            {OPPORTUNITY_STATUS_LABEL[opportunity.status]}
          </span>
        </div>
      </header>

      {ap && totalCentavos !== null ? (
        <div className="mt-4 space-y-2">
          {/* 2. Valor total da primeira contratação, em destaque */}
          <div
            className="relative overflow-hidden rounded-2xl bg-superficie2 py-3 pl-5 pr-4"
            data-testid="valor-total"
          >
            <span aria-hidden className="absolute inset-y-0 left-0 w-1.5 bg-marca" />
            <div className="flex flex-wrap items-center justify-between gap-x-2 gap-y-1">
              <p className="text-xs font-semibold uppercase tracking-wide text-tinta/65">
                Valor total da contratação
              </p>
              {ap.estado === "previa" && (
                <span
                  className="rounded-full border border-amarelo/30 bg-amarelo/10 px-2 py-0.5 text-[0.7rem] font-semibold text-amarelo"
                  title="Valor proposto, ainda não contratável"
                  data-testid="indicador-previa"
                >
                  Prévia<span className="sr-only">: valor proposto, ainda não contratável</span>
                </span>
              )}
            </div>
            <p className="mt-1 font-display text-[2.15rem] font-bold leading-none tracking-tight tabular-nums sm:text-4xl">
              {formatarCentavos(totalCentavos)}
            </p>
            <p className="mt-1.5 text-xs text-tinta/60">Primeira contratação{modalidade}</p>
          </div>

          {/* 3. Contraprestação potencial aos motoristas (primeira contratação) */}
          {somenteDinheiro ? (
            <Bloco
              icone={<IconeRepasse />}
              tomIcone="bg-superficie3 text-tinta/70"
              tomBloco="border-borda bg-superficie2"
              testId="motoristas-primeira"
              rotulo={<Rotulo>Contraprestação aos motoristas</Rotulo>}
            >
              <Valor>Até {motoristas}</Valor>
              <Texto>
                Na contratação disponível, é financiada em dinheiro e repassada aos
                motoristas participantes.
              </Texto>
            </Bloco>
          ) : (
            <Bloco
              icone={<IconeCarrinho />}
              tomIcone="bg-verde/10 text-verde"
              tomBloco="border-verde/20 bg-verde/[0.07]"
              testId="motoristas-primeira"
              rotulo={<Rotulo className="text-verde">Em produtos da própria loja</Rotulo>}
            >
              <Valor className="text-verde">Até {motoristas}</Valor>
              <Texto>
                Até este valor pode ser cumprido em produtos da própria loja, como
                contraprestação aos motoristas participantes.
              </Texto>
            </Bloco>
          )}

          {/* 4. Produção das bandeiras (já dentro do total) */}
          {ap.novo.producaoInicial && (
            <Bloco
              icone={<IconeBandeira />}
              tomIcone="bg-azul/10 text-azul"
              tomBloco="border-borda bg-superficie2"
              testId="producao-inicial"
              rotulo={<Rotulo>Produção das bandeiras</Rotulo>}
            >
              <Valor>{formatarCentavos(ap.novo.producaoInicial.custoNominalCentavos)}</Valor>
              <Texto>
                <span className="font-semibold text-tinta">
                  {ap.novo.producaoInicial.bandeirasFisicas} bandeiras físicas.
                </span>{" "}
                Custo já incluído no valor total.
              </Texto>
            </Bloco>
          )}

          {/* 5. Renovação fidelizada sem novas bandeiras */}
          {mostrarRenovacao && (
            <Bloco
              icone={<IconeRenovar />}
              tomIcone="bg-verde/10 text-verde"
              tomBloco="border-amarelo/20 bg-amarelo/[0.06]"
              testId="renovacao-fidelizada"
              rotulo={<Rotulo className="text-verde">Renovação fidelizada</Rotulo>}
            >
              <Valor>{formatarCentavos(renovacaoCentavos!)}</Valor>
              <p
                className={`mt-1.5 rounded-lg px-2 py-1 text-xs font-semibold ${
                  somenteDinheiro ? "bg-superficie3 text-tinta/75" : "bg-verde/10 text-verde"
                }`}
                data-testid="motoristas-renovacao"
              >
                {somenteDinheiro
                  ? `Para os motoristas: até ${motoristas}, financiados em dinheiro.`
                  : `Para os motoristas: até ${motoristas} em produtos da própria loja.`}
              </p>
              <Texto>Sem trocar as bandeiras já produzidas, mediante aprovação.</Texto>
            </Bloco>
          )}
        </div>
      ) : (
        <p className="mt-4 text-sm text-tinta/60" data-testid="valor-indisponivel">
          Valores em atualização. Consulte o detalhe da oportunidade.
        </p>
      )}

      {/* 6. Detalhe — nunca checkout */}
      <div className="mt-auto space-y-2 pt-4">
        {opportunity.segment ? (
          <p className="text-sm text-tinta/70">
            Segmento: <span className="font-semibold">{opportunity.segment.name}</span>
          </p>
        ) : opportunity.requiresSegment ? (
          <p className="text-xs text-tinta/60">Para um segmento comercial autorizado pela SmallFlags.</p>
        ) : null}

        <Link
          to={`/oportunidades/${slugByCode(opportunity.nicheCode)}`}
          className={`${disponivel ? "btn-primary" : "btn-secondary"} w-full text-center font-display text-base`}
          aria-label={`${disponivel ? "Ver oportunidade" : "Ver próxima exclusividade"}: ${nome}`}
        >
          {disponivel ? "Ver oportunidade" : "Ver próxima exclusividade"}
          <IconeSeta />
        </Link>
      </div>
    </article>
  );
}

/* ---------- Blocos ---------- */

function Bloco({
  icone,
  rotulo,
  tomIcone,
  tomBloco,
  testId,
  children,
}: {
  icone: ReactNode;
  rotulo: ReactNode;
  tomIcone: string;
  tomBloco: string;
  testId: string;
  children: ReactNode;
}) {
  return (
    <div className={`rounded-2xl border px-3.5 py-3 ${tomBloco}`} data-testid={testId}>
      <div className="flex items-center gap-2">
        <span aria-hidden className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg ${tomIcone}`}>
          {icone}
        </span>
        {rotulo}
      </div>
      {children}
    </div>
  );
}

function Rotulo({ children, className = "text-tinta/65" }: { children: ReactNode; className?: string }) {
  return <p className={`text-xs font-semibold uppercase tracking-wide ${className}`}>{children}</p>;
}

function Valor({ children, className = "text-tinta" }: { children: ReactNode; className?: string }) {
  return (
    <p className={`mt-0.5 font-display text-xl font-bold leading-tight tabular-nums ${className}`}>
      {children}
    </p>
  );
}

function Texto({ children }: { children: ReactNode }) {
  return <p className="mt-1 text-xs leading-snug text-tinta/70">{children}</p>;
}

/* ---------- Ícones (decorativos; o significado está sempre no texto) ---------- */

const traco = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

function IconeCheck() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-3.5 w-3.5" {...traco} strokeWidth={3}>
      <path d="M5 12.5l4.5 4.5L19 7.5" />
    </svg>
  );
}

function IconeEscudo() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-5 w-5 shrink-0">
      <path
        d="M12 2.5l7.5 3v5.6c0 4.6-3.1 8.6-7.5 10.4-4.4-1.8-7.5-5.8-7.5-10.4V5.5l7.5-3z"
        className="fill-vivo-amarelo"
      />
      <path
        d="M12 7.2l1.35 2.75 3.03.44-2.19 2.14.52 3.02L12 14.13l-2.71 1.42.52-3.02-2.19-2.14 3.03-.44L12 7.2z"
        className="fill-noite"
      />
    </svg>
  );
}

function IconeCarrinho() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-4 w-4" {...traco}>
      <path d="M3 4h2.2l2.3 10.2a1.5 1.5 0 001.5 1.2h8.3a1.5 1.5 0 001.5-1.1L20.5 8H6.3" />
      <circle cx="9.5" cy="19.5" r="1.3" />
      <circle cx="17" cy="19.5" r="1.3" />
    </svg>
  );
}

function IconeRepasse() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-4 w-4" {...traco}>
      <rect x="3" y="6" width="18" height="12" rx="2" />
      <circle cx="12" cy="12" r="2.5" />
      <path d="M6.5 9.5v5M17.5 9.5v5" />
    </svg>
  );
}

function IconeBandeira() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-4 w-4" {...traco}>
      <path d="M6 21V4" />
      <path d="M6 4.5c4-2 6.5 2 11 0v8c-4.5 2-7-2-11 0" className="fill-current" fillOpacity={0.25} />
    </svg>
  );
}

function IconeRenovar() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-4 w-4" {...traco}>
      <path d="M20 11a8 8 0 00-14.3-4.9L4 8" />
      <path d="M4 3.5V8h4.5" />
      <path d="M4 13a8 8 0 0014.3 4.9L20 16" />
      <path d="M20 20.5V16h-4.5" />
    </svg>
  );
}

function IconeSeta() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" className="h-4 w-4" {...traco} strokeWidth={2.5}>
      <path d="M9 5l7 7-7 7" />
    </svg>
  );
}
