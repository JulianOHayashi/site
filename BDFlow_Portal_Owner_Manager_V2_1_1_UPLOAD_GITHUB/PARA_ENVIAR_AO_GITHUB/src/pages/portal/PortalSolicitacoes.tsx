/**
 * /portal/solicitacoes
 *  • owner   → transações/validações da EMPRESA (todas as filiais);
 *  • manager → SOMENTE as próprias validações.
 *
 * Nenhum papel vê jornada, horas, sessões, documentos, faltas, grupo,
 * sequência operacional, localização ou histórico geral do usuário do App.
 */

import { useEffect, useState } from "react";
import Header from "../../components/Header";
import { PortalCabecalho, dataBr } from "./portalUi";
import {
  FuncaoIndisponivel,
  PortalMemberGate,
} from "../../components/portal/PortalGuards";
import {
  listCompanyTransactions,
  listOwnValidations,
} from "../../services/partnerValidationService";
import { portalNavigation } from "../../domain/portal/navigation";
import {
  PORTAL_ERROR_LABEL,
  type PartnerTransaction,
  type PortalCapabilities,
  type PortalErrorCode,
  type PortalMembership,
} from "../../domain/portal/types";

function Conteudo({
  membership,
  capabilities,
}: {
  membership: PortalMembership;
  capabilities: PortalCapabilities;
}) {
  const ehOwner = membership.role === "partner_owner";
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const [itens, setItens] = useState<PartnerTransaction[]>([]);

  useEffect(() => {
    let ativo = true;
    const consulta = ehOwner ? listCompanyTransactions() : listOwnValidations();
    consulta.then((r) => {
      if (!ativo) return;
      if (r.ok) setItens(r.data);
      else setErro(r.error.code);
      setCarregando(false);
    });
    return () => {
      ativo = false;
    };
  }, [ehOwner]);

  const nav = portalNavigation(membership.role, capabilities);
  const titulo = ehOwner ? "Transações da empresa" : "Minhas validações";

  return (
    <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
      <PortalCabecalho titulo={titulo} itens={nav} />

      <p className="mt-3 text-sm text-tinta/60">
        {ehOwner
          ? "Validações realizadas pela sua empresa, por filial e operador."
          : "Somente as validações realizadas por você."}
      </p>

      {carregando ? (
        <p className="mt-8 text-sm text-tinta/60">Carregando...</p>
      ) : erro === "BACKEND_NOT_AVAILABLE" ? (
        <FuncaoIndisponivel
          titulo="Histórico ainda não disponível"
          descricao="O histórico depende da camada segura de servidor entre o Site e o aplicativo, que ainda não foi ativada. Nenhum dado é exibido por suposição."
        />
      ) : erro ? (
        <div className="mt-6 rounded-2xl border-2 border-magenta/30 bg-magenta/10 p-5 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[erro]}
        </div>
      ) : itens.length === 0 ? (
        <div className="mt-8 rounded-3xl border border-dashed border-borda p-14 text-center">
          <p className="text-lg font-semibold">Nenhum registro encontrado.</p>
        </div>
      ) : (
        <div className="mt-6 overflow-x-auto">
          <table className="w-full min-w-[720px] border-collapse text-sm">
            <thead>
              <tr className="border-b-2 border-borda text-left text-xs uppercase tracking-widest text-tinta/50">
                <th className="py-3 pr-4">Data</th>
                <th className="py-3 pr-4">Filial</th>
                {ehOwner && <th className="py-3 pr-4">Operador</th>}
                {ehOwner && <th className="py-3 pr-4">Papel</th>}
                <th className="py-3 pr-4">Benefício</th>
                <th className="py-3 pr-4">Token</th>
                <th className="py-3">Resultado</th>
              </tr>
            </thead>
            <tbody>
              {itens.map((t) => (
                <tr key={t.transactionId} className="border-b border-borda">
                  <td className="py-3 pr-4">{dataBr(t.occurredAt) ?? "—"}</td>
                  <td className="py-3 pr-4">{t.unitLabel ?? "—"}</td>
                  {ehOwner && <td className="py-3 pr-4">{t.operatorName ?? "—"}</td>}
                  {ehOwner && <td className="py-3 pr-4">{t.operatorRole ?? "—"}</td>}
                  <td className="py-3 pr-4">{t.benefitTypeLabel ?? "—"}</td>
                  <td className="py-3 pr-4">{t.tokenState ?? "—"}</td>
                  <td className="py-3">{t.result ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  );
}

export default function PortalSolicitacoes() {
  return (
    <PortalMemberGate>
      {({ membership, capabilities }) => (
        <>
          <Header />
          <Conteudo membership={membership} capabilities={capabilities} />
        </>
      )}
    </PortalMemberGate>
  );
}
