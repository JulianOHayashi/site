import { Link, useNavigate } from "react-router-dom";
import Header from "../../components/Header";
import { supabase } from "../../lib/supabase";
import { usePortalSiteAuth } from "../../hooks/usePortalSiteAuth";
import { PortalTopo } from "./portalUi";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import {
  EmpresaAtualBarra,
  EscolhaEmpresa,
  ErroContexto,
} from "../../portal/EmpresaSeletor";

/**
 * /portal/dashboard — autenticado no Supabase do SITE.
 *
 * DUAS COISAS DIFERENTES, QUE O TEXTO ANTIGO MISTURAVA:
 *
 * 1. VALIDAR BENEFÍCIO já funciona. O fluxo QR → solicitação → confirmação do
 *    participante no App foi testado ponta a ponta pelo gateway assinado. O
 *    card não pode mais dizer "integração em preparação".
 *
 * 2. HISTÓRICO de usos continua indisponível. As RPCs do Supabase do APP não
 *    são chamadas pelo navegador e não existe contrato de leitura servidor a
 *    servidor para esse histórico. O estado tem de dizer isso, sem inventar
 *    lista vazia.
 *
 * SELEÇÃO DE EMPRESA: quem tem mais de um vínculo escolhe. Antes o primeiro
 * item era adotado em silêncio, o que mostrava a empresa errada sem aviso.
 */
const STATUS_EMPRESA: Record<string, string> = {
  pending: "Aguardando análise da SmallFlags",
  active: "Ativa",
  suspended: "Suspensa",
  archived: "Arquivada",
};

export default function PortalDashboard() {
  const navigate = useNavigate();
  const { session } = usePortalSiteAuth(); // sessão garantida pelo PortalGuard
  const ctx = useEmpresaSelecionada();

  const empresa = ctx.fase === "pronta" ? ctx.atual : null;

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
          <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
            Sua conta
          </p>
          <h2 className="mt-1 text-xl font-bold">{session?.user.email}</h2>
        </section>

        {ctx.fase === "carregando" && (
          <p role="status" className="mt-8 text-center text-sm text-tinta/60">
            Carregando suas empresas...
          </p>
        )}

        {/* Erro de consulta NUNCA vira convite para cadastrar empresa. */}
        <ErroContexto />
        <EscolhaEmpresa />

        {ctx.fase === "sem_vinculo" && (
          <section className="mt-5 rounded-3xl border-2 border-dashed border-ciano/40 bg-ciano/5 p-8 text-center">
            <h2 className="text-2xl font-bold">Cadastre sua empresa parceira</h2>
            <p className="mx-auto mt-2 max-w-md text-sm text-tinta/70">
              Para começar no Portal SmallFlags, cadastre a empresa e torne-se o
              responsável principal. A análise é feita pela SmallFlags.
            </p>
            <Link to="/portal/cadastro" className="btn-primary mt-5 inline-block">
              Cadastrar empresa parceira
            </Link>
          </section>
        )}

        {empresa && (
          <>
            <EmpresaAtualBarra />

            <section className="mt-5 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                Empresa parceira
              </p>
              <div className="mt-1 flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-xl font-bold">{empresa.trade_name}</h2>
                <span className="rounded-full bg-amarelo/30 px-3 py-1 text-xs font-semibold">
                  {STATUS_EMPRESA[empresa.company_status] ?? empresa.company_status}
                </span>
              </div>
            </section>

            {/* Atalhos. Cada card descreve o estado REAL da sua função, e o
                card de equipe só existe para quem é responsável NESTA empresa:
                ser owner em outra não abre a equipe daqui. */}
            <section className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Link
                to="/portal/validar"
                className="group rounded-3xl bg-magenta p-7 text-white shadow-lg transition hover:-translate-y-1 hover:shadow-[0_20px_60px_rgba(229,0,126,0.35)]"
              >
                <h3 className="text-2xl font-bold">Validar benefício</h3>
                <p className="mt-2 text-sm text-white/85">
                  Leia o QR code do divulgador e registre a solicitação. A
                  confirmação é feita pelo próprio divulgador no aplicativo.
                </p>
                <span className="mt-4 inline-block font-semibold transition group-hover:translate-x-1">
                  Abrir →
                </span>
              </Link>

              <Link
                to="/portal/solicitacoes"
                className="group rounded-3xl border-2 border-tinta bg-tinta p-7 text-papel shadow-lg transition hover:-translate-y-1"
              >
                <h3 className="text-2xl font-bold">Solicitações</h3>
                <p className="mt-2 text-sm text-papel/80">
                  O histórico de usos ainda não está disponível no Portal. A
                  página explica onde consultar enquanto isso.
                </p>
                <span className="mt-4 inline-block font-semibold text-ciano transition group-hover:translate-x-1">
                  Abrir →
                </span>
              </Link>

              {empresa.role === "partner_owner" && (
                <Link
                  to="/portal/equipe"
                  className="group rounded-3xl border-2 border-borda bg-white p-7 text-tinta shadow-lg transition hover:-translate-y-1"
                >
                  <h3 className="text-2xl font-bold">Equipe e unidades</h3>
                  <p className="mt-2 text-sm text-tinta/70">
                    Cadastre filiais e convide managers para validar benefícios.
                  </p>
                  <span className="mt-4 inline-block font-semibold text-ciano transition group-hover:translate-x-1">
                    Gerenciar →
                  </span>
                </Link>
              )}
            </section>
          </>
        )}
      </main>
    </>
  );
}
