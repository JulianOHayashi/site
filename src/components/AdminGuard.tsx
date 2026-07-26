import { useEffect, useState } from "react";
import { Navigate, useLocation } from "react-router-dom";
import Header from "./Header";
import { supabase, supabaseConfigurado } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";

/**
 * AdminGuard — proteção real das rotas administrativas.
 *
 * Fluxo: verificar configuração → verificar sessão → consultar a RPC
 * is_site_admin → permitir ou bloquear.
 *
 * Segurança:
 * - autorização vem EXCLUSIVAMENTE de supabase.rpc("is_site_admin");
 * - nunca confia em e-mail, metadados ou allowlist do frontend;
 * - nunca lê a tabela site_admins diretamente;
 * - enquanto carrega (sessão ou RPC), NÃO libera o conteúdo;
 * - erro da RPC ou retorno false → acesso negado;
 * - a proteção visual não substitui RLS (o banco não é alterado aqui).
 */
export default function AdminGuard({ children }: { children: React.ReactNode }) {
  const { session, carregando } = useAuth();
  const location = useLocation();

  const [verificando, setVerificando] = useState(true);
  const [autorizado, setAutorizado] = useState(false);

  useEffect(() => {
    let ativo = true;

    if (carregando) return;
    if (!session || !supabase) {
      // sem sessão: nada a consultar; o render trata o redirecionamento
      setVerificando(false);
      setAutorizado(false);
      return;
    }

    setVerificando(true);
    supabase
      .rpc("is_site_admin")
      .then(({ data, error }) => {
        if (!ativo) return;
        if (error) {
          // erro técnico apenas no console, sem segredos
          console.error("Falha ao verificar permissão administrativa.");
          setAutorizado(false);
        } else {
          setAutorizado(data === true);
        }
        setVerificando(false);
      });

    return () => {
      ativo = false;
    };
  }, [carregando, session]);

  // Supabase não configurado → estado de configuração
  if (!supabaseConfigurado) {
    return (
      <>
        <Header />
        <main className="mx-auto mt-16 max-w-md px-4">
          <div className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
            Supabase do site não configurado. Defina VITE_SUPABASE_URL e
            VITE_SUPABASE_ANON_KEY e recarregue.
          </div>
        </main>
      </>
    );
  }

  // Carregando sessão ou consultando a RPC → loading (não libera nada)
  if (carregando || (session && verificando)) {
    return (
      <>
        <Header />
        <main className="mx-auto mt-24 flex max-w-md flex-col items-center gap-3 px-4">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
          <p className="text-sm text-tinta/60">Verificando permissões...</p>
        </main>
      </>
    );
  }

  // Sem sessão → login preservando o caminho solicitado em next
  if (!session) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/admin/login?next=${next}`} replace />;
  }

  // Sessão presente, mas RPC negou (false ou erro) → acesso negado + sair
  if (!autorizado) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14 text-center">
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
            Acesso restrito
          </p>
          <h1 className="mt-3 text-3xl">Painel administrativo</h1>
          <div className="mt-6 rounded-2xl border-2 border-magenta/30 bg-magenta/10 p-6">
            <p className="font-semibold text-magenta">
              Você não possui permissão para acessar esta área.
            </p>
            <p className="mt-2 text-sm text-tinta/70">
              Sua conta está autenticada, mas não está autorizada como
              administradora.
            </p>
          </div>
          <button
            onClick={async () => {
              await supabase?.auth.signOut();
            }}
            className="btn-secondary mt-6"
          >
            Sair da conta
          </button>
        </main>
      </>
    );
  }

  // Autorizado pela RPC → libera o conteúdo
  return <>{children}</>;
}
