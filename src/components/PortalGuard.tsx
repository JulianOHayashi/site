import { useEffect, useState } from "react";
import { Navigate, useLocation } from "react-router-dom";
import SiteHeader from "./SiteHeader";
import { usePortalSiteAuth } from "../hooks/usePortalSiteAuth";
import { supabaseConfigurado } from "../lib/supabase";
import { obterContextoConta, type ContextoConta } from "../services/partnerApplicationService";

/**
 * PortalGuard — acesso ao Portal do parceiro APROVADO.
 *
 * Regra absoluta: sem PROVA POSITIVA de que a conta pode entrar, não
 * renderiza os filhos. Falha de consulta nunca é tratada como "não tem
 * solicitação"; erro é estado próprio e DENY.
 *
 * Estados:
 *   carregando        -> nada renderiza
 *   sem sessão        -> login, preservando o destino
 *   erro              -> DENY explícito (fail-closed)
 *   provisória        -> redireciona à área de acompanhamento
 *   sem_solicitacao   -> conta comum do portal: libera
 */
type Decisao = "carregando" | "erro" | "provisoria" | "liberado";

function decidir(ctx: ContextoConta | null): Decisao {
  if (ctx === null) return "carregando";
  switch (ctx.tipo) {
    case "provisoria":
      return "provisoria";
    case "sem_solicitacao":
      return "liberado";
    // "erro", "carregando" e "nao_autenticado" nunca liberam.
    default:
      return "erro";
  }
}

export default function PortalGuard({ children }: { children: React.ReactNode }) {
  const { session, carregando } = usePortalSiteAuth();
  const location = useLocation();
  const [contexto, setContexto] = useState<ContextoConta | null>(null);

  useEffect(() => {
    let ativo = true;
    if (carregando || !session) {
      setContexto(null);
      return;
    }
    (async () => {
      try {
        const ctx = await obterContextoConta();
        if (ativo) setContexto(ctx);
      } catch {
        // Exceção inesperada também é erro, e erro nega.
        if (ativo) setContexto({ tipo: "erro" });
      }
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
            Portal em configuração.
          </div>
        </main>
      </>
    );
  }

  if (carregando) return <Carregando texto="Carregando..." />;

  if (!session) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/portal/login?next=${next}`} replace />;
  }

  const decisao = decidir(contexto);

  if (decisao === "carregando") return <Carregando texto="Verificando acesso..." />;

  if (decisao === "provisoria") return <Navigate to="/parceiros/solicitacao" replace />;

  if (decisao === "erro") {
    return (
      <>
        <SiteHeader />
        <main className="mx-auto mt-16 max-w-md px-4">
          <div role="alert" className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
            <p className="font-semibold">Não foi possível verificar seu acesso.</p>
            <p className="mt-2 text-tinta/70">
              Por segurança, o portal não foi aberto. Tente novamente em instantes.
            </p>
          </div>
        </main>
      </>
    );
  }

  return <>{children}</>;
}

function Carregando({ texto }: { texto: string }) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto mt-24 flex max-w-md flex-col items-center gap-3 px-4">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
        <p className="text-sm text-tinta/60" role="status">
          {texto}
        </p>
      </main>
    </>
  );
}
