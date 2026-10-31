import { Link } from "react-router-dom";
import Header from "../../components/Header";
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
  const { session } = usePortalSiteAuth(); // sessão garantida pelo PortalGuard
  const ctx = useEmpresaSelecionada();

  const empresa = ctx.fase === "pronta" ? ctx.atual : null;

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Painel do parceiro" />

        {/* Conta autenticada (Supabase do site) */}
        <section className="card mt-8 p-6">
          <p className="rotulo text-tinta/60">
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
          <section className="mt-5 rounded-2xl border border-dashed border-ciano/40 bg-ciano/5 p-8 text-center">
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

            <section className="card mt-5 p-6">
              <p className="rotulo text-tinta/60">
                Empresa parceira
              </p>
              <div className="mt-1 flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-xl font-bold">{empresa.trade_name}</h2>
                <span
                  className={
                    empresa.company_status === "active"
                      ? "status-ok"
                      : empresa.company_status === "pending"
                        ? "status-aviso"
                        : "status-neutro"
                  }
                >
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
                className="group painel-marca rounded-2xl p-7 transition hover:shadow-brilho"
              >
                <h3 className="text-2xl font-bold">Validar benefício</h3>
                <p className="mt-2 text-sm leading-6 text-tinta/70">
                  Leia o QR code do divulgador e registre a solicitação. A
                  confirmação é feita pelo próprio divulgador no aplicativo.
                </p>
                <span className="mt-4 inline-block font-semibold text-tinta transition group-hover:translate-x-1">
                  Abrir →
                </span>
              </Link>

              <Link
                to="/portal/solicitacoes"
                className="group card-interativo p-7"
              >
                <h3 className="text-2xl font-bold">Solicitações</h3>
                <p className="mt-2 text-sm leading-6 text-tinta/70">
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
                  className="group card-interativo p-7"
                >
                  <h3 className="text-2xl font-bold">Equipe e unidades</h3>
                  <p className="mt-2 text-sm leading-6 text-tinta/70">
                    Cadastre filiais e convide managers para validar benefícios.
                  </p>
                  <span className="mt-4 inline-block font-semibold text-ciano transition group-hover:translate-x-1">
                    Gerenciar →
                  </span>
                </Link>
              )}

              {empresa.role === "partner_owner" && empresa.member_status === "active" && (
                <Link
                  to="/portal/pedidos"
                  className="group card-interativo p-7"
                >
                  <h3 className="text-2xl font-bold">Pedidos</h3>
                  <p className="mt-2 text-sm leading-6 text-tinta/70">
                    Envie ou substitua a imagem para personalização de cada
                    pedido de exclusividade.
                  </p>
                  <span className="mt-4 inline-block font-semibold text-ciano transition group-hover:translate-x-1">
                    Abrir →
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
