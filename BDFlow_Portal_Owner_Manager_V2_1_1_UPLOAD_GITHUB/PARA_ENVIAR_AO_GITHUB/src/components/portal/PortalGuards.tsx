/**
 * Guards do Portal por papel e capacidade.
 *
 * IMPORTANTE: guards de frontend melhoram a experiência (não mostram e não
 * "piscam" o que o usuário não pode usar), mas NÃO substituem RLS, RPCs,
 * validação server-side nem auditoria. A autoridade é sempre o backend.
 */

import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import Header from "../Header";
import { usePortalContext } from "../../hooks/usePortalContext";
import { CarregandoPortal } from "../../pages/portal/portalUi";
import {
  PORTAL_ERROR_LABEL,
  type PortalCapabilities,
  type PortalCapabilityKey,
  type PortalContextState,
  type PortalMembership,
  type PortalRole,
} from "../../domain/portal/types";

// ---------------------------------------------------------------------------
// Telas de estado (reutilizadas por todas as páginas)
// ---------------------------------------------------------------------------

export function PortalAviso({
  titulo,
  descricao,
  tom = "neutro",
  acao,
}: {
  titulo: string;
  descricao: string;
  tom?: "neutro" | "alerta" | "erro";
  acao?: ReactNode;
}) {
  const cores =
    tom === "erro"
      ? "border-magenta/30 bg-magenta/10"
      : tom === "alerta"
        ? "border-amarelo bg-amarelo/15"
        : "border-borda bg-papel2/60";
  return (
    <div className={`mt-6 rounded-3xl border-2 ${cores} p-6 text-center`}>
      <p className="font-semibold">{titulo}</p>
      <p className="mx-auto mt-2 max-w-md text-sm text-tinta/70">{descricao}</p>
      {acao && <div className="mt-5">{acao}</div>}
    </div>
  );
}

/** Função indisponível por ausência de backend — estado honesto. */
export function FuncaoIndisponivel({
  titulo = "Função ainda não disponível",
  descricao = PORTAL_ERROR_LABEL.BACKEND_NOT_AVAILABLE,
}: {
  titulo?: string;
  descricao?: string;
}) {
  return (
    <div className="mt-6 rounded-3xl border-2 border-dashed border-borda bg-papel p-8 text-center">
      <p className="text-2xl">🔒</p>
      <h2 className="mt-2 text-xl font-bold">{titulo}</h2>
      <p className="mx-auto mt-2 max-w-md text-sm text-tinta/70">{descricao}</p>
    </div>
  );
}

function PaginaEstado({
  titulo,
  children,
}: {
  titulo: string;
  children: ReactNode;
}) {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-3xl px-4 pb-24 pt-12 text-center">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
        </p>
        <h1 className="mt-3 text-3xl">{titulo}</h1>
        {children}
      </main>
    </>
  );
}

export function AcessoNaoAutorizado() {
  return (
    <PaginaEstado titulo="Acesso não autorizado">
      <PortalAviso
        titulo="Você não tem permissão para abrir esta área."
        descricao="Se acredita que isto é um engano, fale com o responsável principal da sua empresa."
        tom="erro"
        acao={
          <Link to="/portal/dashboard" className="btn-secondary">
            Voltar ao início
          </Link>
        }
      />
    </PaginaEstado>
  );
}

// ---------------------------------------------------------------------------
// Guard base: exige vínculo elegível do Portal
// ---------------------------------------------------------------------------

export type PortalReady = Extract<PortalContextState, { kind: "ready" }>;

/**
 * Renderiza `children` apenas quando há vínculo resolvido.
 * Trata: carregando · falha de consulta · sem vínculo · suspenso/arquivado.
 */
export function PortalMemberGate({
  children,
  exigirAtivo = false,
}: {
  children: (ctx: {
    membership: PortalMembership;
    capabilities: PortalCapabilities;
    capabilitiesSource: "backend" | "unavailable";
    email: string | null;
  }) => ReactNode;
  exigirAtivo?: boolean;
}) {
  const { state, email } = usePortalContext();

  if (state.kind === "loading") {
    return (
      <>
        <Header />
        <CarregandoPortal />
      </>
    );
  }

  // Falha de consulta — jamais confundir com ausência de vínculo.
  if (state.kind === "error") {
    return (
      <PaginaEstado titulo="Não foi possível carregar seu acesso">
        <PortalAviso
          titulo={PORTAL_ERROR_LABEL[state.code]}
          descricao="Nenhuma informação foi assumida. Recarregue a página em instantes ou tente novamente mais tarde."
          tom="erro"
        />
      </PaginaEstado>
    );
  }

  if (state.kind === "no_membership") {
    return (
      <PaginaEstado titulo="Acesso ao Portal indisponível">
        <PortalAviso
          titulo="Esta conta não possui vínculo elegível para o Portal."
          descricao="O Portal é destinado a responsáveis e gerentes de empresas parceiras. Para conhecer as oportunidades comerciais, use a área de parceiros."
          acao={
            <Link to="/parceiros" className="btn-primary">
              Ir para a área de parceiros
            </Link>
          }
        />
      </PaginaEstado>
    );
  }

  const { membership, capabilities, capabilitiesSource } = state;

  if (membership.status === "archived") {
    return (
      <PaginaEstado titulo="Vínculo encerrado">
        <PortalAviso
          titulo="Seu vínculo com esta empresa foi encerrado."
          descricao="O histórico é preservado para auditoria. Uma nova participação exige novo convite do responsável principal."
          tom="alerta"
        />
      </PaginaEstado>
    );
  }

  if (exigirAtivo && membership.status !== "active") {
    const titulo =
      membership.status === "suspended"
        ? "Acesso suspenso"
        : "Acesso em análise";
    const descricao =
      membership.status === "suspended"
        ? PORTAL_ERROR_LABEL.MEMBERSHIP_SUSPENDED
        : "Seu acesso está em análise administrativa. Nenhuma ação operacional está liberada por enquanto.";
    return (
      <PaginaEstado titulo={titulo}>
        <PortalAviso titulo={descricao} descricao="" tom="alerta" />
      </PaginaEstado>
    );
  }

  return <>{children({ membership, capabilities, capabilitiesSource, email })}</>;
}

// ---------------------------------------------------------------------------
// Guards por papel
// ---------------------------------------------------------------------------

function GateDePapel({
  papel,
  children,
}: {
  papel: PortalRole;
  children: (ctx: {
    membership: PortalMembership;
    capabilities: PortalCapabilities;
    capabilitiesSource: "backend" | "unavailable";
    email: string | null;
  }) => ReactNode;
}) {
  return (
    <PortalMemberGate>
      {(ctx) =>
        ctx.membership.role === papel ? (
          children(ctx)
        ) : (
          <AcessoNaoAutorizado />
        )
      }
    </PortalMemberGate>
  );
}

/** Somente `partner_owner`. Manager recebe "Acesso não autorizado". */
export function OwnerOnlyGate({
  children,
}: {
  children: (ctx: {
    membership: PortalMembership;
    capabilities: PortalCapabilities;
    capabilitiesSource: "backend" | "unavailable";
    email: string | null;
  }) => ReactNode;
}) {
  return <GateDePapel papel="partner_owner">{children}</GateDePapel>;
}

/** Somente `partner_manager`. Owner não recebe página manager-only. */
export function ManagerOnlyGate({
  children,
}: {
  children: (ctx: {
    membership: PortalMembership;
    capabilities: PortalCapabilities;
    capabilitiesSource: "backend" | "unavailable";
    email: string | null;
  }) => ReactNode;
}) {
  return <GateDePapel papel="partner_manager">{children}</GateDePapel>;
}

/** Renderiza somente com a capacidade concedida pelo backend. */
export function CapabilityGate({
  capabilities,
  requer,
  children,
  fallback,
}: {
  capabilities: PortalCapabilities;
  requer: PortalCapabilityKey;
  children: ReactNode;
  fallback?: ReactNode;
}) {
  if (capabilities[requer] === true) return <>{children}</>;
  return <>{fallback ?? null}</>;
}
