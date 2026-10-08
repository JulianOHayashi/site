import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { fetchPublicPricing } from "../../services/commercialService";
import {
  formatarCentavos,
  type NichePricing,
  type PublicNichePricing,
} from "../../domain/pricing/contractPricing";
import {
  FOUNDING_BLOCK_UNITS,
  FOUNDING_BLOCK_PRICE_CENTS,
  EXTRA_UNIT_PRICE_CENTS,
} from "../../domain/pricing/commercialV2";

/**
 * Painel de condições comerciais da vitrine.
 *
 * A autoridade material é sempre a RPC. A fórmula bloco + excedentes só é
 * exibida para versões históricas <= 2, nas quais ela faz parte do próprio
 * contrato de preço. A SF-v1.4 (versão 3) é uma agenda explícita: nenhum total
 * vigente é reconstruído no navegador.
 *
 * Se o retorno não for íntegro, nada é exibido — nenhum número é inventado para
 * preencher a tela.
 */
export default function PainelPreco({ nicheCode }: { nicheCode: string }) {
  const [estado, setEstado] = useState<
    | { fase: "carregando" }
    | { fase: "indisponivel" }
    | { fase: "ok"; preco: PublicNichePricing }
  >({ fase: "carregando" });

  useEffect(() => {
    let ativo = true;
    fetchPublicPricing()
      .then((lista) => {
        if (!ativo) return;
        const preco = lista.find((p) => p.nicheCode === nicheCode);
        setEstado(preco ? { fase: "ok", preco } : { fase: "indisponivel" });
      })
      .catch(() => {
        if (ativo) setEstado({ fase: "indisponivel" });
      });
    return () => {
      ativo = false;
    };
  }, [nicheCode]);

  if (estado.fase === "carregando") {
    return (
      <div className="card mt-4 p-6 text-sm text-tinta/60" aria-live="polite">
        Carregando condições comerciais...
      </div>
    );
  }

  if (estado.fase === "indisponivel") {
    return (
      <div className="card mt-4 p-6">
        <h2 className="text-lg font-bold">Condições comerciais</h2>
        <p className="mt-2 text-sm text-tinta/70">
          As condições vigentes não estão disponíveis no momento. Fale com a
          SmallFlags para receber a proposta atualizada.
        </p>
        <Cta />
      </div>
    );
  }

  const { founding, fidelized, nominalQuantity } = estado.preco;
  const usaFormulaHistorica = founding.pricingRuleVersion <= 2;
  const extras = usaFormulaHistorica
    ? Math.max(0, nominalQuantity - FOUNDING_BLOCK_UNITS)
    : 0;

  return (
    <div className="card mt-4 p-6">
      <h2 className="text-lg font-bold">Condições comerciais vigentes</h2>
      <p className="mt-1 text-xs text-tinta/50">
        Nicho contratado integralmente — {nominalQuantity} unidades. Tabela
        versão {founding.pricingRuleVersion}.
      </p>

      {usaFormulaHistorica && extras > 0 && (
        <div className="mt-4 space-y-1 rounded-xl bg-papel2 p-4 text-sm">
          <p className="font-semibold">Formação do valor</p>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">
              {FOUNDING_BLOCK_UNITS} primeiras unidades
            </span>
            <span>{formatarCentavos(FOUNDING_BLOCK_PRICE_CENTS)}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">{extras} unidades adicionais</span>
            <span>{formatarCentavos(extras * EXTRA_UNIT_PRICE_CENTS)}</span>
          </div>
          <div className="flex items-center justify-between border-t border-tinta/10 pt-1 font-semibold">
            <span>Total</span>
            <span>{formatarCentavos(founding.economicValueCents)}</span>
          </div>
        </div>
      )}

      <Composicao titulo="Condição fundadora (não fidelizada)" p={founding} />
      <Composicao titulo="Renovação fidelizada" p={fidelized} />

      <div className="mt-4 space-y-2 rounded-xl bg-papel2 p-4 text-sm">
        <p className="font-semibold">
          Como a parcela dos usuários pode ser cumprida
        </p>
        <p className="text-tinta/70">
          <span className="font-semibold">Benefícios diretos</span> — {founding.pricingRuleVersion >= 3
            ? "a empresa cumpre diretamente perante os MEIs elegíveis a contraprestação ordinária. A remuneração da SmallFlags, incluída a parcela de QA, continua devida em dinheiro."
            : "a empresa disponibiliza o pool histórico diretamente aos usuários elegíveis; a parcela operacional permanece devida à SmallFlags."}
        </p>
        <p className="text-tinta/70">
          <span className="font-semibold">Dinheiro real</span> — {founding.pricingRuleVersion >= 3
            ? "a empresa aporta em dinheiro a contraprestação dos participantes elegíveis, além da remuneração contratual da SmallFlags. A cobrança financeira corresponde ao valor econômico completo."
            : "a empresa aporta em dinheiro o pool histórico dos usuários elegíveis. A cobrança financeira corresponde ao valor econômico completo."}
        </p>
        <p className="text-xs text-tinta/50">
          A escolha é feita pela empresa na etapa de contratação.
        </p>
      </div>

      <p className="mt-3 text-xs text-tinta/50">
        Condição fidelizada aplicada a contratos seguintes no mesmo CNPJ,
        cidade e nicho. A condição é determinada pela SmallFlags a partir do
        histórico da empresa, não escolhida na contratação.
      </p>

      <Cta nicheCode={nicheCode} />
    </div>
  );
}

/** Composição econômica em reais, com o percentual apenas como aproximação. */
function Composicao({ titulo, p }: { titulo: string; p: NichePricing }) {
  return (
    <div className="mt-4 space-y-2 rounded-xl border border-tinta/10 p-4 text-sm">
      <p className="font-semibold">{titulo}</p>
      <div className="flex items-baseline justify-between">
        <span className="text-tinta/70">Valor econômico da contratação</span>
        <span className="text-lg font-bold">
          {formatarCentavos(p.economicValueCents)}
        </span>
      </div>
      {/*
        Sob a SF-v1.4 o pool contratual tem DOIS titulares: a contraprestação
        dos MEIs e a parcela de QA, que é da SmallFlags. Apresentar o pool
        inteiro como "destinado aos usuários" seria afirmar que a parcela de QA
        é dinheiro deles. Quando o servidor manda a decomposição, ela é exibida;
        sob V1/V2, que não tinham parcela de QA, o pool aparece sem decomposição.
      */}
      {p.meiConsiderationCents !== null && p.smallflagsQaCents !== null ? (
        <>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">Contraprestação dos MEIs</span>
            <span className="font-semibold">
              {formatarCentavos(p.meiConsiderationCents)}
            </span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">
              Parcela de QA da SmallFlags (dentro do pool)
            </span>
            <span className="font-semibold">
              {formatarCentavos(p.smallflagsQaCents)}
            </span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">
              Pool contratual total
              {p.displayPoolPercent ? ` (${p.displayPoolPercent})` : ""}
            </span>
            <span className="font-semibold">
              {formatarCentavos(p.contractualPoolCents)}
            </span>
          </div>
        </>
      ) : (
        <div className="flex items-center justify-between">
          <span className="text-tinta/70">
            Pool contratual total
            {p.displayPoolPercent ? ` (${p.displayPoolPercent})` : ""}
          </span>
          <span className="font-semibold">
            {formatarCentavos(p.contractualPoolCents)}
          </span>
        </div>
      )}
      {p.smallflagsMainFeeCents !== null && p.smallflagsTotalRemunerationCents !== null ? (
        <>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">Parcela operacional principal da SmallFlags</span>
            <span className="font-semibold">
              {formatarCentavos(p.smallflagsMainFeeCents)}
            </span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-tinta/70">Remuneração contratual total da SmallFlags</span>
            <span className="font-semibold">
              {formatarCentavos(p.smallflagsTotalRemunerationCents)}
            </span>
          </div>
        </>
      ) : (
        <div className="flex items-center justify-between">
          <span className="text-tinta/70">SmallFlags + operação + investimentos</span>
          <span className="font-semibold">
            {formatarCentavos(p.bdflowDueCents)}
          </span>
        </div>
      )}
      {p.paymentMethod && (
        <div className="flex items-center justify-between border-t border-tinta/10 pt-2">
          <span className="text-tinta/60">Forma de pagamento</span>
          <span className="font-semibold">
            {p.paymentMethod === "pix" ? "Pix" : "Cartão de crédito"}
          </span>
        </div>
      )}
    </div>
  );
}

function Cta({ nicheCode }: { nicheCode?: string }) {
  const destino = nicheCode
    ? `/checkout?nicho=${encodeURIComponent(nicheCode)}`
    : "/parceiros/cadastro";

  return (
    <>
      <Link
        to={destino}
        className="btn-primary mt-5 inline-block w-full text-center"
      >
        Solicitar contratação
      </Link>
      <p className="mt-2 text-center text-xs text-tinta/50">
        {nicheCode
          ? "No checkout, o titular autenticado pode reservar a oportunidade por 30 minutos e avançar após o aceite dos termos."
          : "As condições vigentes não estão disponíveis. Solicite o contato da SmallFlags para receber a proposta atualizada."}
      </p>
    </>
  );
}
