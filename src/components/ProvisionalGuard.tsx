import { Navigate, useLocation } from "react-router-dom";
import SiteHeader from "./SiteHeader";
import { useAuth } from "../hooks/useAuth";
import { supabaseConfigurado } from "../lib/supabase";
import { safeInternalDestination } from "../lib/safeInternalDestination";

/**
 * ProvisionalGuard — protege a área da conta provisória.
 *
 * Exige apenas sessão: a autoridade sobre QUAIS dados aparecem é da RLS e
 * das RPCs. Este guard não concede nada; ele só evita renderizar a área
 * para quem não está autenticado.
 */
export default function ProvisionalGuard({ children }: { children: React.ReactNode }) {
  const { session, carregando } = useAuth();
  const location = useLocation();

  if (!supabaseConfigurado) {
    return (
      <>
        <SiteHeader />
        <main className="mx-auto mt-16 max-w-md px-4">
          <div className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
            Área em configuração.
          </div>
        </main>
      </>
    );
  }

  if (carregando) {
    return (
      <>
        <SiteHeader />
        <main className="mx-auto mt-24 flex max-w-md flex-col items-center gap-3 px-4">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
          <p className="text-sm text-tinta/60">Carregando...</p>
        </main>
      </>
    );
  }

  if (!session) {
    const destino = safeInternalDestination(
      location.pathname + location.search,
      "/parceiros/solicitacao",
      { requiredPrefix: "/parceiros" }
    );
    return <Navigate to={`/parceiros?next=${encodeURIComponent(destino)}`} replace />;
  }

  return <>{children}</>;
}
