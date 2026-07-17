import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";

/**
 * /portal/validar?qt=... — nesta etapa a integração de benefícios
 * está DESLIGADA (as RPCs do Supabase do APP não são mais chamadas
 * pelo navegador). A página preserva o parâmetro qt — inclusive
 * através do login, graças ao PortalGuard — e informa o estado real.
 * A futura validação será feita por uma camada segura de servidor.
 */
export default function PortalValidar() {
  const [params] = useSearchParams();
  const qt = (params.get("qt") ?? "").trim();

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Validar benefício" />

        <div className="mt-8 rounded-3xl border-2 border-dashed border-borda bg-papel p-8 text-center">
          <p className="text-2xl">🔒</p>
          <h2 className="mt-2 text-xl font-bold">
            Integração com benefícios ainda não configurada
          </h2>
          <p className="mx-auto mt-2 max-w-md text-sm text-tinta/70">
            A validação de QR codes será ativada por uma integração segura em
            breve. Nenhum benefício pode ser consultado ou utilizado por aqui
            neste momento.
          </p>

          {qt && (
            <div className="mx-auto mt-5 max-w-sm rounded-2xl border border-borda bg-white px-4 py-3 text-sm">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Código recebido
              </p>
              <p className="mt-1 break-all font-mono font-semibold">{qt}</p>
              <p className="mt-1 text-xs text-tinta/50">
                O código foi preservado — quando a integração for ativada,
                este link funcionará normalmente.
              </p>
            </div>
          )}

          <Link to="/portal/dashboard" className="btn-secondary mt-6">
            Voltar ao painel
          </Link>
        </div>
      </main>
    </>
  );
}
