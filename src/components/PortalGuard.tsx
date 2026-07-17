import { Navigate, useLocation } from "react-router-dom";
import SiteHeader from "./SiteHeader";
import { usePortalSiteAuth } from "../hooks/usePortalSiteAuth";
import { supabaseConfigurado } from "../lib/supabase";

/**
 * PortalGuard — proteção das rotas internas do /portal
 * (/portal/dashboard, /portal/validar, /portal/solicitacoes).
 *
 * Enquanto verifica: estado de carregamento (nada renderiza).
 * Sem sessão: redireciona a /portal/login preservando pathname + search
 *   — assim /portal/validar?qt=XYZ volta com o mesmo qt após o login.
 */
export default function PortalGuard({ children }: { children: React.ReactNode }) {
  const { session, carregando } = usePortalSiteAuth();
  const location = useLocation();

  if (!supabaseConfigurado) {
    return (
      <>
        <SiteHeader />
        <main className="mx-auto mt-16 max-w-md px-4">
          <div className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
            Portal em configuração — defina VITE_SUPABASE_URL e
            VITE_SUPABASE_ANON_KEY na Vercel e faça Redeploy.
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
          <p className="text-sm text-tinta/60">Carregando portal...</p>
        </main>
      </>
    );
  }

  if (!session) {
    const destino = location.pathname + location.search;
    return (
      <Navigate
        to={`/portal/login?next=${encodeURIComponent(destino)}`}
        replace
      />
    );
  }

  return <>{children}</>;
}
