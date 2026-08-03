/**
 * /portal/equipe/:memberId — owner-only.
 * Detalhes permitidos do gerente. Sem dados pessoais do usuário do App.
 */

import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Header from "../../components/Header";
import { CampoInfo, PortalCabecalho, dataBr } from "./portalUi";
import {
  FuncaoIndisponivel,
  OwnerOnlyGate,
} from "../../components/portal/PortalGuards";
import { getManager } from "../../services/partnerTeamService";
import { portalNavigation } from "../../domain/portal/navigation";
import {
  PORTAL_ERROR_LABEL,
  type PartnerManagerSummary,
  type PortalCapabilities,
  type PortalErrorCode,
  type PortalMembership,
} from "../../domain/portal/types";

function Conteudo({
  membership,
  capabilities,
  memberId,
}: {
  membership: PortalMembership;
  capabilities: PortalCapabilities;
  memberId: string;
}) {
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const [manager, setManager] = useState<PartnerManagerSummary | null>(null);

  useEffect(() => {
    let ativo = true;
    getManager(memberId).then((r) => {
      if (!ativo) return;
      if (r.ok) setManager(r.data);
      else setErro(r.error.code);
      setCarregando(false);
    });
    return () => {
      ativo = false;
    };
  }, [memberId]);

  return (
    <main className="mx-auto max-w-3xl px-4 pb-24 pt-10">
      <PortalCabecalho
        titulo="Gerente"
        itens={portalNavigation(membership.role, capabilities)}
      />

      {carregando ? (
        <p className="mt-6 text-sm text-tinta/60">Carregando...</p>
      ) : erro === "BACKEND_NOT_AVAILABLE" ? (
        <FuncaoIndisponivel titulo="Detalhes ainda não disponíveis" />
      ) : erro ? (
        <p className="mt-6 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[erro]}
        </p>
      ) : manager ? (
        <section className="mt-6 grid gap-5 rounded-3xl border border-borda bg-white/85 p-6 sm:grid-cols-2">
          <CampoInfo rotulo="Nome" valor={manager.name} />
          <CampoInfo rotulo="Papel" valor="Gerente operacional" />
          <CampoInfo rotulo="Situação" valor={manager.status} />
          <CampoInfo rotulo="Entrada" valor={dataBr(manager.joinedAt)} />
          <CampoInfo
            rotulo="Última atividade"
            valor={dataBr(manager.lastOperationalActivityAt)}
          />
          <CampoInfo rotulo="Validações" valor={manager.validationsCount} />
        </section>
      ) : (
        <p className="mt-6 text-sm text-tinta/60">Gerente não encontrado.</p>
      )}

      {manager && manager.status !== "archived" && (
        <p className="mt-6 rounded-2xl border border-borda bg-papel2/60 p-4 text-sm text-tinta/70">
          {manager.status === "active" &&
            "Este gerente está ativo. As ações de suspender e revogar estão disponíveis na lista de equipe."}
          {manager.status === "suspended" &&
            "Este gerente está suspenso. Reativar acesso e revogar por desligamento estão disponíveis na lista de equipe."}
          {manager.status === "pending_admin_review" &&
            "Este gerente está em análise administrativa. Ações de suspensão e reativação ficam indisponíveis até a definição do vínculo."}
        </p>
      )}
      {manager && manager.status === "archived" && (
        <p className="mt-6 rounded-2xl border border-borda bg-papel2/60 p-4 text-sm text-tinta/60">
          Vínculo encerrado. O histórico é preservado para auditoria; nenhuma
          ação de suspensão, reativação ou nova revogação se aplica. Uma futura
          recontratação exige novo convite.
        </p>
      )}

      <Link to="/portal/equipe" className="btn-secondary mt-6 inline-block">
        Voltar à equipe
      </Link>
    </main>
  );
}

export default function PortalEquipeDetalhe() {
  const { memberId } = useParams();
  return (
    <OwnerOnlyGate>
      {({ membership, capabilities }) => (
        <>
          <Header />
          <Conteudo
            membership={membership}
            capabilities={capabilities}
            memberId={memberId ?? ""}
          />
        </>
      )}
    </OwnerOnlyGate>
  );
}
