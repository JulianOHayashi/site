import { formatarCentavos } from "../../domain/pricing/contractPricing";
import {
  formationEconomicsV2,
  PARTICIPANT_TARGET_V2,
} from "../../domain/pricing/commercialV2";

/**
 * Resumo agregado da formação completa de referência (seis nichos, condição
 * não fidelizada).
 *
 * Os valores vêm da política canônica do domínio, não de aritmética avulsa
 * escrita na tela. Duplicar as contas aqui deixaria a vitrine capaz de
 * divergir do servidor sem ninguém perceber.
 *
 * SOBRE O R$ 1.099,00
 * É a alocação monetária total de um participante que cumpre TODOS os
 * requisitos operacionais correspondentes na formação de referência
 * completa. Não é saldo automático de cadastro e não é carteira. A
 * qualificação está no texto, não em nota de rodapé escondida.
 */
export default function ResumoFormacao() {
  const f = formationEconomicsV2();

  const linhas: Array<{ rotulo: string; valor: string; destaque?: boolean }> = [
    {
      rotulo: "Valor econômico total da formação",
      valor: formatarCentavos(f.economicValueCents),
    },
    {
      rotulo: `Pool destinado aos ${f.participantTarget} usuários BDFlow`,
      valor: formatarCentavos(f.userPoolCents),
    },
    {
      rotulo: "BDFlow + operação + investimentos",
      valor: formatarCentavos(f.bdflowOpsInvestmentCents),
    },
    {
      rotulo: "Valor total potencial por usuário elegível",
      valor: formatarCentavos(f.perCompleteUserCents),
      destaque: true,
    },
  ];

  return (
    <section
      className="card mt-6 p-6"
      aria-labelledby="resumo-formacao-titulo"
    >
      <h2 id="resumo-formacao-titulo" className="text-lg font-bold">
        A formação completa em números
      </h2>
      <p className="mt-1 text-sm text-tinta/60">
        Referência da primeira formação: seis nichos comerciais e{" "}
        {PARTICIPANT_TARGET_V2} usuários reais, na condição não fidelizada.
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

      <p className="mt-3 text-xs text-tinta/60">
        O valor por usuário é a alocação total de quem cumpre todos os
        requisitos operacionais aplicáveis na formação de referência completa,
        somando os sete benefícios do App. Não é saldo em dinheiro devido pelo
        simples cadastro, nem carteira de uso livre.
      </p>
    </section>
  );
}
