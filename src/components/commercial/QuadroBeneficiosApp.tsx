import { formatarCentavos } from "../../domain/pricing/contractPricing";
import type { BeneficiosPorOportunidade, ParcelaPorContratacao } from "../../domain/pricing/beneficiosAppPorOportunidade";

function Rubricas({titulo,parcela}:{titulo:string;parcela:ParcelaPorContratacao}) {
  return (
    <div className="rounded-xl border border-tinta/15 bg-white p-3 text-tinta">
      <p className="font-bold">{titulo}</p>
      <dl className="mt-2 space-y-1 text-sm">
        <div className="flex justify-between gap-2">
          <dt>Valor econômico</dt><dd className="font-semibold tabular-nums">{formatarCentavos(parcela.valorEconomicoCentavos)}</dd>
        </div>
        <div className="flex justify-between gap-2">
          <dt>Contraprestações potenciais dos MEIs (App)</dt>
          <dd className="font-semibold tabular-nums">{formatarCentavos(parcela.contraprestacaoMEIsCentavos)}</dd>
        </div>
        <div className="flex justify-between gap-2">
          <dt>Remuneração SmallFlags (QA inclusa)</dt>
          <dd className="font-semibold tabular-nums">{formatarCentavos(parcela.remuneracaoSmallFlagsCentavos)}</dd>
        </div>
        {parcela.fabricacaoIncluidaCentavos !== null && parcela.fabricacaoIncluidaCentavos > 0 && (
          <div className="flex justify-between gap-2 text-xs">
            <dt>Dos quais: fabricação das bandeiras, já incluída na parcela SmallFlags</dt>
            <dd className="tabular-nums">{formatarCentavos(parcela.fabricacaoIncluidaCentavos)}</dd>
          </div>
        )}
        <div className="flex justify-between gap-2 text-xs">
          <dt>QA da SmallFlags (não é contraprestação do MEI)</dt>
          <dd className="tabular-nums">{formatarCentavos(parcela.qaSmallFlagsCentavos)}</dd>
        </div>
      </dl>
    </div>
  );
}

/** Detalhamento por oportunidade; jamais soma contratos de anunciantes distintos. */
export default function QuadroBeneficiosApp({dados,compacto=false}:{
  dados:BeneficiosPorOportunidade;
  compacto?:boolean;
}) {
  if(compacto) return (
    <div className="mt-3 rounded-xl border border-tinta/15 bg-white p-3 text-sm text-tinta">
      <p className="font-bold">Incluído nos dois preços: usuários do App</p>
      <p className="mt-1">
        <strong>{formatarCentavos(dados.novo.contraprestacaoMEIsCentavos)}</strong>
        {" "}em contraprestações potenciais aos MEIs elegíveis
        {" "}({dados.participacoesPotenciais} participações × {formatarCentavos(dados.valorPorParticipacaoCentavos)}).
      </p>
      <p className="mt-1 text-xs text-tinta/70">
        O restante compõe a remuneração contratual da SmallFlags:{" "}
        {formatarCentavos(dados.novo.remuneracaoSmallFlagsCentavos)} para novo anunciante
        {" "}ou {formatarCentavos(dados.fidelizado.remuneracaoSmallFlagsCentavos)} para fidelizado,
        incluindo QA. Não são valores adicionais ao preço mostrado.
      </p>
      <p className="mt-1 text-xs text-tinta/60">Projeção sujeita aos requisitos do App; não é saldo ou benefício liberado automaticamente.</p>
    </div>
  );
  return (
    <section className="mt-4 space-y-3" aria-label="Composição econômica individual e benefícios dos usuários do App">
      <h3 className="text-lg font-bold">Como cada preço considera os usuários do App</h3>
      <p className="text-sm text-tinta/70">
        Referência de {dados.participacoesPotenciais} participações potenciais nesta posição,
        a {formatarCentavos(dados.valorPorParticipacaoCentavos)} por participação elegível.
        O valor destinado aos MEIs já está incluído no preço econômico — não é cobrança extra.
        Não é saldo garantido; a liberação depende das regras e comprovações do App.
      </p>
      <div className="grid gap-3 md:grid-cols-2">
        <Rubricas titulo="Novo anunciante" parcela={dados.novo} />
        <Rubricas titulo="Fidelizado com reutilização" parcela={dados.fidelizado} />
      </div>
      <div className="rounded-xl bg-papel2 p-4 text-sm text-tinta/80">
        <p><strong>Benefício direto:</strong> o anunciante cumpre diretamente a contraprestação
          dos MEIs elegíveis, e a remuneração da SmallFlags é devida em dinheiro:
          {formatarCentavos(dados.novo.remuneracaoSmallFlagsCentavos)} (novo)
          {" "}ou {formatarCentavos(dados.fidelizado.remuneracaoSmallFlagsCentavos)} (fidelizado).
        </p>
        <p className="mt-2"><strong>Modalidade em dinheiro:</strong> o aporte corresponde ao valor
          econômico integral da condição contratada. A parcela destinada aos MEIs é
          contabilmente separada da remuneração da SmallFlags; não é receita própria.
        </p>
        <p className="mt-2 text-xs">A parcela QA pertence à SmallFlags, não aos MEIs. A inspeção das peças condiciona a reutilização fidelizada; a política de reposição permanece pendente.</p>
      </div>
    </section>
  );
}
