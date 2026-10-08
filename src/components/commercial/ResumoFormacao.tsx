import { useEffect, useState } from "react";
import {
  formatarCentavos,
  type FormationEconomicsServer,
} from "../../domain/pricing/contractPricing";
import { fetchFormationEconomics } from "../../services/commercialService";

/**
 * Resumo agregado da formação completa de referência (seis nichos, condição
 * não fidelizada).
 *
 * OS VALORES VÊM DO SERVIDOR, SEMPRE.
 * Antes desta versão este componente chamava `formationEconomicsV2()` e
 * calculava a economia no próprio navegador. Quando a SF-v1.4 passou a ser a
 * autoridade ativa, a vitrine continuou publicando os números da V2 — pool de
 * R$ 92.316,00 e R$ 1.099,00 por usuário — enquanto o servidor já respondia
 * R$ 83.916,00 e R$ 993,93. Recalcular preço no navegador é exatamente o que o
 * handoff proíbe.
 *
 * A PARCELA QA NÃO É DINHEIRO DO USUÁRIO.
 * Sob a SF-v1.4 o pool contratual é composto de duas parcelas com titulares
 * diferentes: a contraprestação dos MEIs e a parcela de QA, que pertence à
 * SmallFlags. Por isso o pool inteiro NÃO é apresentado como "destinado aos
 * usuários", e o valor por usuário é calculado sobre a contraprestação dos
 * MEIs, não sobre o pool.
 *
 * Falha de consulta NÃO é "não há formação": o componente diz que não
 * conseguiu carregar, em vez de exibir número inventado.
 */

type Estado =
  | { fase: "carregando" }
  | { fase: "indisponivel" }
  | { fase: "ok"; economia: FormationEconomicsServer };

export default function ResumoFormacao() {
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });

  useEffect(() => {
    let vivo = true;
    fetchFormationEconomics()
      .then((economia) => {
        if (vivo) setEstado({ fase: "ok", economia });
      })
      .catch(() => {
        if (vivo) setEstado({ fase: "indisponivel" });
      });
    return () => {
      vivo = false;
    };
  }, []);

  return (
    <section className="card mt-6 p-6" aria-labelledby="resumo-formacao-titulo">
      <h2 id="resumo-formacao-titulo" className="text-lg font-bold">
        A formação completa em números
      </h2>

      {estado.fase === "carregando" && (
        <p role="status" className="mt-3 text-sm text-tinta/70">
          Carregando os valores da formação...
        </p>
      )}

      {estado.fase === "indisponivel" && (
        <div role="alert" className="mt-3 rounded-2xl border border-borda p-4">
          <p className="text-sm font-semibold">
            Não foi possível carregar os valores da formação agora.
          </p>
          <p className="mt-1 text-sm leading-6 text-tinta/70">
            Isto é uma falha de consulta, não a ausência de formação. Os valores
            são calculados no servidor e não são reconstituídos aqui.
          </p>
        </div>
      )}

      {estado.fase === "ok" && <Valores economia={estado.economia} />}
    </section>
  );
}

function Valores({ economia: e }: { economia: FormationEconomicsServer }) {
  const temDecomposicao =
    e.meiConsiderationCents !== null &&
    e.smallflagsQaCents !== null &&
    e.perCompleteMeiBaseCents !== null;

  const linhas: Array<{ rotulo: string; valor: string; destaque?: boolean }> = [
    {
      rotulo: "Valor econômico total da formação",
      valor: formatarCentavos(e.economicValueCents),
    },
  ];

  if (temDecomposicao) {
    linhas.push(
      {
        rotulo: `Contraprestação dos ${e.participantTarget} MEIs participantes`,
        valor: formatarCentavos(e.meiConsiderationCents as number),
      },
      {
        rotulo: "Parcela de QA da SmallFlags (dentro do pool contratual)",
        valor: formatarCentavos(e.smallflagsQaCents as number),
      },
      {
        rotulo: "Pool contratual total (contraprestação + QA)",
        valor: formatarCentavos(e.contractualPoolCents),
      }
    );
  } else {
    // V1/V2: não existia parcela de QA, então não há decomposição a afirmar.
    linhas.push({
      rotulo: "Pool contratual total",
      valor: formatarCentavos(e.contractualPoolCents),
    });
  }

  linhas.push({
    rotulo: "SmallFlags + operação + investimentos",
    valor: formatarCentavos(e.bdflowOpsInvestmentCents),
  });

  if (temDecomposicao) {
    linhas.push({
      rotulo: "Contraprestação potencial por MEI elegível",
      valor: formatarCentavos(e.perCompleteMeiBaseCents as number),
      destaque: true,
    });
  }

  return (
    <>
      <p className="mt-1 text-sm text-tinta/60">
        Referência da primeira formação: seis nichos comerciais e{" "}
        {e.participantTarget} participantes reais, na condição não fidelizada.
      </p>

      <dl className="mt-4 divide-y divide-tinta/10">
        {linhas.map((l) => (
          <div
            key={l.rotulo}
            className="flex items-baseline justify-between gap-4 py-2"
          >
            <dt className="text-sm text-tinta/70">{l.rotulo}</dt>
            <dd
              className={
                l.destaque ? "text-lg font-bold" : "text-sm font-semibold"
              }
            >
              {l.valor}
            </dd>
          </div>
        ))}
      </dl>

      {temDecomposicao && (
        <p className="mt-3 text-xs text-tinta/60">
          A parcela de QA está dentro do pool contratual, mas pertence à
          SmallFlags — não é contraprestação do MEI, não é crédito de usuário e
          não é uma participação adicional. Por isso o valor por MEI acima é
          calculado sobre a contraprestação dos MEIs, e não sobre o pool
          inteiro.
        </p>
      )}

      <p className="mt-2 text-xs text-tinta/60">
        A contraprestação por participante é a alocação total de quem cumpre
        todos os requisitos operacionais aplicáveis na formação de referência
        completa, somando os sete benefícios do App. Não é saldo em dinheiro
        devido pelo simples cadastro, nem carteira de uso livre.
      </p>
    </>
  );
}
