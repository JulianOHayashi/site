/**
 * Painel administrativo do `partner_owner`.
 *
 * Mostra SOMENTE dados reais devolvidos pelo backend. Campos ausentes
 * aparecem como ausência explícita — nunca preenchidos com invenção.
 * Nenhum CTA de cadastro empresarial é exibido a quem já tem vínculo.
 */

import { Link } from "react-router-dom";
import { CampoInfo, PortalCabecalho } from "../../pages/portal/portalUi";
import { CapabilityGate, FuncaoIndisponivel, PortalAviso } from "./PortalGuards";
import UnidadesResumo from "./UnidadesResumo";
import EquipeConvitesPainel from "./EquipeConvitesPainel";
import { portalNavigation } from "../../domain/portal/navigation";
import { roleLabel } from "../../domain/portal/capabilities";
import {
  type PortalCapabilities,
  type PortalMembership,
} from "../../domain/portal/types";

const STATUS_EMPRESA: Record<string, string> = {
  lead: "Interesse registrado",
  pending: "Aguardando análise da BDFlow",
  active: "Ativa",
  suspended: "Suspensa",
  archived: "Arquivada",
};

export default function OwnerDashboard({
  membership,
  capabilities,
  capabilitiesSource,
  email,
  onSair,
}: {
  membership: PortalMembership;
  capabilities: PortalCapabilities;
  capabilitiesSource: "backend" | "unavailable";
  email: string | null;
  onSair: () => void;
}) {
  const nav = portalNavigation("partner_owner", capabilities);
  const empresa = membership.company;
  const backendIndisponivel = capabilitiesSource === "unavailable";

  return (
    <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
      <PortalCabecalho titulo="Painel do parceiro" itens={nav} onSair={onSair} />

      {backendIndisponivel && (
        <div className="mt-6 rounded-2xl border border-borda bg-papel2/70 px-5 py-4 text-sm text-tinta/70">
          As permissões operacionais e administrativas ainda são concedidas por
          uma camada de servidor que não foi ativada. Por isso, as ações abaixo
          aparecem como indisponíveis em vez de habilitadas por suposição.
        </div>
      )}

      {/* ================= 4.1 Empresa e operação ================= */}
      <section className="mt-6 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
              Empresa parceira
            </p>
            <h2 className="mt-1 text-2xl font-bold">
              {empresa.partnerDisplayName ?? "Nome público não informado"}
            </h2>
            <p className="mt-1 text-sm text-tinta/60">
              {roleLabel(membership.role)} · {email}
            </p>
          </div>
          {empresa.status && (
            <span className="rounded-full bg-amarelo/30 px-3 py-1 text-xs font-semibold">
              {STATUS_EMPRESA[empresa.status] ?? empresa.status}
            </span>
          )}
        </div>

        <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <CampoInfo rotulo="Situação do contrato" valor={empresa.contractStatusLabel} />
          <CampoInfo rotulo="Situação do pagamento" valor={empresa.paymentStatusLabel} />
          <CampoInfo rotulo="Nicho contratado" valor={empresa.nicheLabel} />
          <CampoInfo rotulo="Exclusividade" valor={empresa.exclusivityStatusLabel} />
          <CampoInfo rotulo="Operação" valor={empresa.operationStatusLabel} />
          <CampoInfo rotulo="Seu vínculo" valor={membership.status === "active" ? "Ativo" : membership.status} />
        </div>

        {empresa.notices.length > 0 && (
          <ul className="mt-5 space-y-2">
            {empresa.notices.map((n, i) => (
              <li
                key={i}
                className="rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta"
              >
                {n}
              </li>
            ))}
          </ul>
        )}

        {empresa.status === "suspended" && (
          <PortalAviso
            tom="erro"
            titulo="Empresa suspensa"
            descricao="Novas ações operacionais estão bloqueadas até a regularização pela BDFlow."
          />
        )}
      </section>

      {/* ================= 4.2 Filiais ================= */}
      <section className="mt-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-xl font-bold">Matriz e filiais</h2>
          <div className="flex gap-2">
            <Link to="/portal/unidades" className="btn-secondary text-sm">
              Gerenciar filiais
            </Link>
            <CapabilityGate
              capabilities={capabilities}
              requer="canManageUnits"
              fallback={
                <button
                  disabled
                  title="Permissão concedida pelo servidor ainda indisponível"
                  className="cursor-not-allowed rounded-xl border-2 border-borda px-3 py-2 text-sm font-semibold text-tinta/40"
                >
                  Cadastrar filial
                </button>
              }
            >
              <Link to="/portal/unidades" className="btn-primary text-sm">
                Cadastrar filial
              </Link>
            </CapabilityGate>
          </div>
        </div>
        <UnidadesResumo />
      </section>

      {/* ================= 4.3 Equipe e convites ================= */}
      <section className="mt-8">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-xl font-bold">Equipe e convites</h2>
          <Link to="/portal/equipe" className="btn-secondary text-sm">
            Ver equipe completa
          </Link>
        </div>
        <EquipeConvitesPainel capabilities={capabilities} />
      </section>

      {/* ================= 4.5 Transações ================= */}
      <section className="mt-8">
        <h2 className="text-xl font-bold">Transações e validações da empresa</h2>
        <p className="mt-1 text-sm text-tinta/60">
          Histórico das validações realizadas pela sua empresa, por filial e
          operador. Dados pessoais e a jornada do usuário do aplicativo não são
          exibidos aqui.
        </p>
        <CapabilityGate
          capabilities={capabilities}
          requer="canViewCompanyTransactions"
          fallback={<FuncaoIndisponivel titulo="Transações ainda não disponíveis" />}
        >
          <Link to="/portal/solicitacoes" className="btn-primary mt-4 inline-block">
            Abrir transações
          </Link>
        </CapabilityGate>
      </section>
    </main>
  );
}
