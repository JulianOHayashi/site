import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { fetchPublicPricing } from "../../services/commercialService";
import {
  formatarCentavos,
  type PublicNichePricing,
} from "../../domain/pricing/contractPricing";

/**
 * Painel de condições comerciais da vitrine.
 *
 * Apresenta o valor VIGENTE calculado no servidor e a composição contratual:
 *   valor do contrato = compromisso de benefício na rede do parceiro
 *                       + valor devido à BDFlow
 *
 * Não há checkout, reserva, Pix ou cartão: a ação é solicitar contratação.
 * Se o backend não devolver um preço íntegro, nenhum valor é exibido.
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

  const p = estado.preco.founding;
  return (
    <div className="card mt-4 p-6">
      <h2 className="text-lg font-bold">Condições comerciais vigentes</h2>
      <p className="mt-1 text-xs text-tinta/50">
        Nicho contratado integralmente — {estado.preco.nominalQuantity} unidades.
        Tabela versão {p.pricingRuleVersion}.
      </p>

      <div className="mt-4 flex items-baseline justify-between">
        <span className="text-tinta/60">Valor do contrato</span>
        <span className="text-2xl font-bold">
          {formatarCentavos(p.economicValueCents)}
        </span>
      </div>

      <div className="mt-4 space-y-2 rounded-xl bg-papel2 p-4 text-sm">
        <p className="font-semibold">Composição do contrato</p>
        <div className="flex items-center justify-between">
          <span className="text-tinta/70">
            Compromisso de benefício na sua rede ({p.poolBps / 100}%)
          </span>
          <span className="font-semibold">
            {formatarCentavos(p.contractualPoolCents)}
          </span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-tinta/70">Valor devido à BDFlow</span>
          <span className="font-semibold">
            {formatarCentavos(p.bdflowDueCents)}
          </span>
        </div>
        <p className="pt-1 text-xs text-tinta/60">
          O compromisso de benefício não é pago à BDFlow: é o valor que a sua
          empresa honra em compras feitas na própria rede autorizada. A BDFlow
          recebe apenas o valor devido acima.
        </p>
      </div>

      <div className="mt-4 flex items-center justify-between text-sm">
        <span className="text-tinta/60">Renovação fidelizada</span>
        <span className="font-semibold">
          {formatarCentavos(estado.preco.fidelized.economicValueCents)}
        </span>
      </div>
      <p className="mt-1 text-xs text-tinta/50">
        Condição aplicada a contratos seguintes no mesmo CNPJ, cidade e nicho.
      </p>

      <Cta />
    </div>
  );
}

function Cta() {
  return (
    <>
      <Link
        to="/parceiros/cadastro"
        className="btn-primary mt-5 inline-block w-full text-center"
      >
        Solicitar contratação
      </Link>
      <p className="mt-2 text-center text-xs text-tinta/50">
        A contratação é conduzida pela equipe BDFlow. Esta página não realiza
        pagamento, reserva nem gera contrato.
      </p>
    </>
  );
}
