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
 * Painel de condições comerciais da vitrine — Comercial V2.
 *
 * O QUE MUDOU EM RELAÇÃO À V1
 * A versão anterior afirmava, sem condição, que o pool "não é pago à BDFlow"
 * e é sempre honrado na rede do parceiro. Sob a V2 isso deixou de ser
 * universalmente verdadeiro: a empresa escolhe entre cumprir em benefícios
 * diretos ou aportar o pool em dinheiro. O texto passa a ser condicional.
 *
 * A composição é exibida em REAIS, não escondida atrás de um total único nem
 * atrás de um percentual. Os percentuais aparecem como aproximação declarada
 * porque os centavos é que são a autoridade.
 *
 * Nenhum valor é calculado aqui: tudo vem da RPC. Se o retorno não for
 * íntegro, nada é exibido — nenhum número é inventado para preencher a tela.
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
          BDFlow para receber a proposta atualizada.
        </p>
        <Cta />
      </div>
    );
  }

  const { founding, fidelized, nominalQuantity } = estado.preco;
  const extras = Math.max(0, nominalQuantity - FOUNDING_BLOCK_UNITS);

  return (
    <div className="card mt-4 p-6">
      <h2 className="text-lg font-bold">Condições comerciais vigentes</h2>
      <p className="mt-1 text-xs text-tinta/50">
        Nicho contratado integralmente — {nominalQuantity} unidades. Tabela
        versão {founding.pricingRuleVersion}.
      </p>

      {extras > 0 && (
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
          <span className="font-semibold">Benefícios diretos</span> — a empresa
          disponibiliza os benefícios diretamente aos usuários elegíveis,
          conforme as regras operacionais. Nesse caso, o valor pago à BDFlow é
          apenas a parcela de BDFlow, operação e investimentos.
        </p>
        <p className="text-tinta/70">
          <span className="font-semibold">Dinheiro real</span> — a empresa
          aporta em dinheiro o valor do pool destinado aos usuários elegíveis
          que cumprirem as tarefas e requisitos aplicáveis. Nesse caso, a
          cobrança financeira corresponde ao valor econômico completo.
        </p>
        <p className="text-xs text-tinta/50">
          A escolha é feita pela empresa na etapa de contratação.
        </p>
      </div>

      <p className="mt-3 text-xs text-tinta/50">
        Condição fidelizada aplicada a contratos seguintes no mesmo CNPJ,
        cidade e nicho. A condição é determinada pela BDFlow a partir do
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
      <div className="flex items-center justify-between">
        <span className="text-tinta/70">
          Pool destinado aos usuários BDFlow
          {p.displayPoolPercent ? ` (${p.displayPoolPercent})` : ""}
        </span>
        <span className="font-semibold">
          {formatarCentavos(p.contractualPoolCents)}
        </span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-tinta/70">BDFlow + operação + investimentos</span>
        <span className="font-semibold">
          {formatarCentavos(p.bdflowDueCents)}
        </span>
      </div>
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
          : "As condições vigentes não estão disponíveis. Solicite o contato da BDFlow para receber a proposta atualizada."}
      </p>
    </>
  );
}
