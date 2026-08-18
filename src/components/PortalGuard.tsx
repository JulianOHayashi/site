import { useEffect, useState } from "react";
import { Navigate, useLocation } from "react-router-dom";
import SiteHeader from "./SiteHeader";
import { usePortalSiteAuth } from "../hooks/usePortalSiteAuth";
import { supabaseConfigurado } from "../lib/supabase";
import { obterMinhaSolicitacao } from "../services/partnerApplicationService";

/**
 * PortalGuard — proteção das rotas internas do /portal
 * (/portal/dashboard, /portal/validar, /portal/solicitacoes).
 *
 * Enquanto verifica: estado de carregamento (nada renderiza).
 * Sem sessão: redireciona a /portal/login preservando pathname + search
 *   — assim /portal/validar?qt=XYZ volta com o mesmo qt após o login.
 *
 * Conta PROVISÓRIA (onboarding Fase 2A) não acessa o portal do parceiro
 * aprovado: ela é redirecionada à própria área de acompanhamento. Ter
 * sessão não é o mesmo que ser parceiro. A verificação consulta o backend
 * — o navegador não decide isso.
 */
export default function PortalGuard({ children }: { children: React.ReactNode }) {
  const { session, carregando } = usePortalSiteAuth();
  const location = useLocation();
  const [provisorio, setProvisorio] = useState<boolean | null>(null);

  useEffect(() => {
    let ativo = true;
    if (carregando || !session) {
      setProvisorio(null);
      return;
    }
    (async () => {
      const solicitacao = await obterMinhaSolicitacao();
      if (!ativo) return;
      setProvisorio(solicitacao?.account_kind === "provisional");
    })();
    return () => {
      ativo = false;
    };
  }, [carregando, session]);

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

  // Sessão presente, mas ainda não sabemos o tipo de conta: não renderiza.
  if (provisorio === null) {
    return (
      <>
        <SiteHeader />
        <main className="mx-auto mt-24 flex max-w-md flex-col items-center gap-3 px-4">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
          <p className="text-sm text-tinta/60">Verificando acesso...</p>
        </main>
      </>
    );
  }

  if (provisorio) {
    return <Navigate to="/parceiros/solicitacao" replace />;
  }

  return <>{children}</>;
}
