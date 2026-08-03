/**
 * /portal/equipe — owner-only.
 *
 * Visão completa de gerentes e convites. Duas ações distintas por manager:
 *  • Suspender acesso  → bloqueio imediato e REVERSÍVEL;
 *  • Revogar acesso    → encerramento DEFINITIVO do vínculo empresarial.
 * Nunca "Excluir cadastro": a conta pessoal e o histórico são preservados.
 */

import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { PortalCabecalho, dataBr } from "./portalUi";
import {
  FuncaoIndisponivel,
  OwnerOnlyGate,
} from "../../components/portal/PortalGuards";
import EquipeConvitesPainel from "../../components/portal/EquipeConvitesPainel";
import ConfirmarRevogacao from "../../components/portal/ConfirmarRevogacao";
import {
  listManagers,
  reactivateManager,
  suspendManager,
} from "../../services/partnerTeamService";
import { portalNavigation } from "../../domain/portal/navigation";
import {
  PORTAL_ERROR_LABEL,
  type PartnerManagerSummary,
  type PortalCapabilities,
  type PortalErrorCode,
  type PortalMembership,
} from "../../domain/portal/types";

const STATUS_MEMBRO: Record<string, { rotulo: string; classes: string }> = {
  active: { rotulo: "Ativo", classes: "bg-[#E8F7EE] text-[#0B7A3E]" },
  pending_admin_review: { rotulo: "Em análise", classes: "bg-amarelo/25 text-tinta" },
  suspended: { rotulo: "Suspenso", classes: "bg-magenta/10 text-magenta" },
  archived: { rotulo: "Encerrado", classes: "bg-papel2 text-tinta/60" },
};

function ListaManagers({ capabilities }: { capabilities: PortalCapabilities }) {
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const [managers, setManagers] = useState<PartnerManagerSummary[]>([]);
  const [aRevogar, setARevogar] = useState<PartnerManagerSummary | null>(null);
  const [mensagem, setMensagem] = useState<PortalErrorCode | null>(null);

  const carregar = useCallback(() => {
    setCarregando(true);
    listManagers().then((r) => {
      if (r.ok) setManagers(r.data);
      else setErro(r.error.code);
      setCarregando(false);
    });
  }, []);

  useEffect(carregar, [carregar]);

  if (carregando) return <p className="mt-6 text-sm text-tinta/60">Carregando equipe...</p>;

  if (erro === "BACKEND_NOT_AVAILABLE") {
    return (
      <FuncaoIndisponivel
        titulo="Gestão de equipe ainda não disponível"
        descricao="A listagem, suspensão e revogação de gerentes dependem de uma camada de servidor que ainda não foi ativada. Nenhuma ação é apresentada como concluída."
      />
    );
  }
  if (erro) {
    return (
      <p className="mt-6 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
        {PORTAL_ERROR_LABEL[erro]}
      </p>
    );
  }
  if (managers.length === 0) {
    return (
      <p className="mt-6 rounded-3xl border border-dashed border-borda p-10 text-center text-sm text-tinta/60">
        Nenhum gerente vinculado até o momento.
      </p>
    );
  }

  return (
    <>
      {mensagem && (
        <p className="mt-4 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[mensagem]} Nenhuma alteração foi aplicada.
        </p>
      )}
      <ul className="mt-6 space-y-3">
        {managers.map((m) => {
          const st = STATUS_MEMBRO[m.status] ?? {
            rotulo: m.status,
            classes: "bg-papel2 text-tinta/60",
          };
          return (
            <li key={m.memberId} className="rounded-2xl border border-borda bg-white/85 p-5">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <Link
                    to={`/portal/equipe/${m.memberId}`}
                    className="font-bold underline decoration-borda underline-offset-4 hover:decoration-tinta"
                  >
                    {m.name ?? "Nome não informado"}
                  </Link>
                  <p className="mt-1 text-sm text-tinta/60">
                    Gerente operacional · desde{" "}
                    {dataBr(m.joinedAt) ?? "data não informada"}
                  </p>
                  <p className="mt-0.5 text-sm text-tinta/60">
                    Última atividade:{" "}
                    {dataBr(m.lastOperationalActivityAt) ?? "não informada"} ·
                    Validações:{" "}
                    {m.validationsCount === null ? "não informado" : m.validationsCount}
                  </p>
                </div>
                <span className={`rounded-full px-3 py-1 text-xs font-semibold ${st.classes}`}>
                  {st.rotulo}
                </span>
              </div>

              {capabilities.canManageManagers &&
                m.status !== "archived" &&
                m.status !== "pending_admin_review" && (
                  <div className="mt-4 flex flex-wrap gap-2">
                    {m.status === "active" && (
                      <button
                        onClick={async () => {
                          const r = await suspendManager(m.memberId);
                          if (!r.ok) setMensagem(r.error.code);
                          else carregar();
                        }}
                        className="rounded-lg border border-borda px-3 py-1.5 text-xs font-semibold transition hover:border-tinta"
                      >
                        Suspender acesso
                      </button>
                    )}
                    {m.status === "suspended" && (
                      <button
                        onClick={async () => {
                          const r = await reactivateManager(m.memberId);
                          if (!r.ok) setMensagem(r.error.code);
                          else carregar();
                        }}
                        className="rounded-lg border border-[#0B7A3E]/40 px-3 py-1.5 text-xs font-semibold text-[#0B7A3E] transition hover:bg-[#E8F7EE]"
                      >
                        Reativar acesso
                      </button>
                    )}
                    <button
                      onClick={() => setARevogar(m)}
                      className="rounded-lg border border-magenta/40 px-3 py-1.5 text-xs font-semibold text-magenta transition hover:bg-magenta/10"
                    >
                      Revogar acesso por desligamento
                    </button>
                  </div>
                )}
              {capabilities.canManageManagers &&
                m.status === "pending_admin_review" && (
                  <p className="mt-4 text-xs text-tinta/50">
                    Em análise administrativa — ações de suspensão e reativação
                    ficam indisponíveis até a definição do vínculo.
                  </p>
                )}
            </li>
          );
        })}
      </ul>

      {aRevogar && (
        <ConfirmarRevogacao
          manager={aRevogar}
          onFechar={() => setARevogar(null)}
          onConcluido={() => {
            setARevogar(null);
            carregar();
          }}
        />
      )}
    </>
  );
}

function Conteudo({
  membership,
  capabilities,
}: {
  membership: PortalMembership;
  capabilities: PortalCapabilities;
}) {
  return (
    <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
      <PortalCabecalho
        titulo="Equipe e convites"
        itens={portalNavigation(membership.role, capabilities)}
      />

      <section className="mt-6">
        <h2 className="text-xl font-bold">Gerentes</h2>
        <ListaManagers capabilities={capabilities} />
      </section>

      <section className="mt-10">
        <h2 className="text-xl font-bold">Convites</h2>
        <EquipeConvitesPainel capabilities={capabilities} mostrarManagers={false} />
      </section>
    </main>
  );
}

export default function PortalEquipe() {
  return (
    <OwnerOnlyGate>
      {({ membership, capabilities }) => (
        <>
          <Header />
          <Conteudo membership={membership} capabilities={capabilities} />
        </>
      )}
    </OwnerOnlyGate>
  );
}
