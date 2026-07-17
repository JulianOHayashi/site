import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";

/**
 * /portal/solicitacoes — nesta etapa a listagem está indisponível:
 * as RPCs do Supabase do APP não são mais chamadas pelo navegador.
 * Estado vazio real (sem dados falsos) até a integração segura.
 */
export default function PortalSolicitacoes() {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Solicitações" />

        <div className="mt-10 rounded-3xl border border-dashed border-borda p-14 text-center">
          <p className="text-lg font-semibold">Nenhuma solicitação encontrada.</p>
          <p className="mt-1 text-sm text-tinta/60">
            O histórico de usos de benefício ficará disponível quando a
            integração segura for ativada.
          </p>
          <Link to="/portal/dashboard" className="btn-secondary mt-6">
            Voltar ao painel
          </Link>
        </div>
      </main>
    </>
  );
}
