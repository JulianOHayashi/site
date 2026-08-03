/**
 * Painel operacional reduzido do `partner_manager`.
 *
 * O manager NUNCA vê: cadastro de empresa, contratos, pagamentos, valores
 * financeiros, gestão/cadastro de filiais, equipe, convites, suspensão ou
 * revogação de membros, histórico geral da empresa ou transações de outros
 * operadores. Nada disso é renderizado — nem desabilitado "só visualmente".
 */

import { Link } from "react-router-dom";
import { PortalCabecalho } from "../../pages/portal/portalUi";
import { PortalAviso } from "./PortalGuards";
import { portalNavigation } from "../../domain/portal/navigation";
import { roleLabel } from "../../domain/portal/capabilities";
import type {
  PortalCapabilities,
  PortalMembership,
} from "../../domain/portal/types";

const STATUS_MEMBRO: Record<string, { rotulo: string; tom: "neutro" | "alerta" | "erro" }> = {
  active: { rotulo: "Ativo", tom: "neutro" },
  pending_admin_review: { rotulo: "Em análise administrativa", tom: "alerta" },
  suspended: { rotulo: "Suspenso", tom: "erro" },
  archived: { rotulo: "Encerrado", tom: "erro" },
};

export default function ManagerDashboard({
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
  const nav = portalNavigation("partner_manager", capabilities);
  const st = STATUS_MEMBRO[membership.status] ?? {
    rotulo: membership.status,
    tom: "alerta" as const,
  };

  return (
    <main className="mx-auto max-w-3xl px-4 pb-24 pt-10">
      <PortalCabecalho titulo="Painel operacional" itens={nav} onSair={onSair} />

      <section className="mt-6 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
        <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
          Empresa vinculada
        </p>
        <h2 className="mt-1 text-2xl font-bold">
          {membership.company.partnerDisplayName ?? "Empresa não informada"}
        </h2>
        <p className="mt-2 text-sm text-tinta/70">
          {roleLabel(membership.role)} · {email}
        </p>
        <span className="mt-3 inline-block rounded-full bg-papel2 px-3 py-1 text-xs font-semibold">
          Seu acesso: {st.rotulo}
        </span>
      </section>

      {membership.status !== "active" && (
        <PortalAviso
          tom={st.tom}
          titulo={
            membership.status === "suspended"
              ? "Seu acesso está suspenso."
              : "Seu acesso está em análise."
          }
          descricao="Enquanto isso, nenhuma validação de benefício pode ser realizada."
        />
      )}

      {membership.status === "active" && !capabilities.canValidateBenefits && (
        <PortalAviso
          tom="alerta"
          titulo="Operação ainda não ativa"
          descricao={
            capabilitiesSource === "unavailable"
              ? "A permissão para validar benefícios é concedida por uma camada de servidor que ainda não foi ativada. Por isso a validação aparece indisponível."
              : "Sua empresa ainda não está autorizada a liberar benefícios."
          }
        />
      )}

      {capabilities.canValidateBenefits && (
        <section className="mt-6">
          <Link
            to="/portal/validar"
            className="group block rounded-3xl bg-magenta p-7 text-white shadow-lg transition hover:-translate-y-1"
          >
            <span className="text-3xl">🔳</span>
            <h3 className="mt-3 text-2xl font-bold">Validar benefício</h3>
            <p className="mt-1 text-sm text-white/85">
              Selecione a filial em que você está trabalhando e informe o código.
            </p>
          </Link>
        </section>
      )}

      <section className="mt-6 grid gap-4 sm:grid-cols-2">
        <Link
          to="/portal/solicitacoes"
          className="rounded-3xl border-2 border-borda bg-white/85 p-6 transition hover:border-tinta"
        >
          <h3 className="font-bold">Minhas validações</h3>
          <p className="mt-1 text-sm text-tinta/60">
            Apenas as validações realizadas por você.
          </p>
        </Link>
        <Link
          to="/portal/meu-acesso"
          className="rounded-3xl border-2 border-borda bg-white/85 p-6 transition hover:border-tinta"
        >
          <h3 className="font-bold">Meu acesso</h3>
          <p className="mt-1 text-sm text-tinta/60">
            Papel, situação e empresa vinculada.
          </p>
        </Link>
      </section>
    </main>
  );
}
