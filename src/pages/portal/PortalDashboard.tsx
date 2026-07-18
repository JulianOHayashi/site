import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../../components/Header";
import { supabase } from "../../lib/supabase";
import { usePortalSiteAuth } from "../../hooks/usePortalSiteAuth";
import { PortalTopo } from "./portalUi";

/**
 * /portal/dashboard — nesta etapa, autenticado no Supabase do SITE.
 *
 * As consultas de contexto/ciclo do parceiro (antes feitas por RPCs
 * do Supabase do APP direto do navegador) foram DESATIVADAS. A
 * integração voltará por uma camada segura de servidor em etapa
 * futura. Sem dados falsos: mostramos o estado real ("em preparação").
 */
type Empresa = { trade_name: string; status: string } | null;

const STATUS_EMPRESA: Record<string, string> = {
  pending: "Aguardando análise da BDFlow",
  active: "Ativa",
  suspended: "Suspensa",
  archived: "Arquivada",
};

export default function PortalDashboard() {
  const navigate = useNavigate();
  const { session } = usePortalSiteAuth(); // sessão garantida pelo PortalGuard
  const [empresa, setEmpresa] = useState<Empresa>(null);
  const [temVinculo, setTemVinculo] = useState<boolean | null>(null);

  // Consulta via RLS: o usuário já é owner de uma empresa?
  useEffect(() => {
    if (!supabase || !session) return;
    let ativo = true;
    supabase
      .from("site_partner_members")
      .select("status, site_monthly_partners(trade_name, status)")
      .eq("user_id", session.user.id)
      .eq("role", "partner_owner")
      .neq("status", "archived")
      .then(({ data }) => {
        if (!ativo) return;
        const v = data?.[0] as
          | { site_monthly_partners: { trade_name: string; status: string } | null }
          | undefined;
        setTemVinculo(Boolean(v));
        setEmpresa(v?.site_monthly_partners ?? null);
      });
    return () => {
      ativo = false;
    };
  }, [session]);

  const sair = async () => {
    await supabase?.auth.signOut();
    navigate("/portal/login", { replace: true });
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Painel do parceiro" onSair={sair} />

        {/* Conta autenticada (Supabase do site) */}
        <section className="mt-8 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
          <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
            Sua conta
          </p>
          <h2 className="mt-1 text-xl font-bold">{session?.user.email}</h2>
        </section>

        {/* Empresa: botão de cadastro (sem vínculo) OU card da empresa */}
        {temVinculo === false && (
          <section className="mt-5 rounded-3xl border-2 border-dashed border-ciano/40 bg-ciano/5 p-8 text-center">
            <p className="text-2xl">🏢</p>
            <h2 className="mt-2 text-2xl font-bold">
              Cadastre sua empresa parceira
            </h2>
            <p className="mx-auto mt-2 max-w-md text-sm text-tinta/70">
              Para começar no Portal BDFlow, cadastre a empresa e torne-se o
              responsável principal. A análise é feita pela BDFlow.
            </p>
            <Link to="/portal/cadastro" className="btn-primary mt-5 inline-block">
              Cadastrar empresa parceira
            </Link>
          </section>
        )}

        {temVinculo === true && empresa && (
          <section className="mt-5 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
            <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
              Empresa parceira
            </p>
            <div className="mt-1 flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-xl font-bold">{empresa.trade_name}</h2>
              <span className="rounded-full bg-amarelo/30 px-3 py-1 text-xs font-semibold">
                {STATUS_EMPRESA[empresa.status] ?? empresa.status}
              </span>
            </div>
          </section>
        )}

        {/* Atalhos (páginas existem, com estado de indisponibilidade) */}
        <section className="mt-8 grid gap-4 sm:grid-cols-2">
          <Link
            to="/portal/validar"
            className="group rounded-3xl bg-magenta p-7 text-white shadow-lg transition hover:-translate-y-1 hover:shadow-[0_20px_60px_rgba(229,0,126,0.35)]"
          >
            <span className="text-3xl">🔳</span>
            <h3 className="mt-3 text-2xl font-bold">Validar benefício</h3>
            <p className="mt-1 text-sm text-white/85">
              Integração em preparação — veja o status na página.
            </p>
            <span className="mt-4 inline-block font-semibold transition group-hover:translate-x-1">
              Abrir →
            </span>
          </Link>
          <Link
            to="/portal/solicitacoes"
            className="group rounded-3xl border-2 border-tinta bg-tinta p-7 text-papel shadow-lg transition hover:-translate-y-1 hover:shadow-[0_20px_60px_rgba(0,168,224,0.3)]"
          >
            <span className="text-3xl">📋</span>
            <h3 className="mt-3 text-2xl font-bold">Solicitações</h3>
            <p className="mt-1 text-sm text-papel/80">
              Histórico de usos de benefício aparecerá aqui.
            </p>
            <span className="mt-4 inline-block font-semibold text-ciano transition group-hover:translate-x-1">
              Abrir →
            </span>
          </Link>
        </section>
      </main>
    </>
  );
}
