import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import { usePortalSiteAuth } from "../../hooks/usePortalSiteAuth";
import { CarregandoPortal, PortalNaoConfigurado } from "./portalUi";

/**
 * /portal/login — nesta etapa, autentica no Supabase do SITE
 * (mesmo cliente/projeto usado por /parceiros e /admin).
 *
 * Não chama mais nenhuma RPC do Supabase do APP. A verificação de
 * vínculo com um parceiro comercial e as consultas de contexto/uso
 * ficarão em uma camada de serviço separada, a ser conectada em
 * outra etapa.
 */
export default function PortalLogin() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { session, carregando } = usePortalSiteAuth();

  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  const destinoAposLogin = () => {
    const next = params.get("next");
    return next && next.startsWith("/portal") ? next : "/portal/dashboard";
  };

  // Já logado? Segue direto.
  useEffect(() => {
    if (!carregando && session) {
      navigate(destinoAposLogin(), { replace: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [carregando, session]);

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase) return;
    setErro(null);
    setEnviando(true);
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password: senha,
    });
    if (error) {
      setEnviando(false);
      setErro(
        error.message.includes("Invalid login")
          ? "E-mail ou senha incorretos."
          : "Não foi possível entrar. Tente novamente."
      );
      return;
    }
    // sessão do site será detectada pelo hook → redireciona
  };

  if (!supabaseConfigurado) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14">
          <PortalNaoConfigurado />
        </main>
      </>
    );
  }

  if (carregando) {
    return (
      <>
        <Header />
        <CarregandoPortal />
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        <p className="text-center text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
        </p>
        <h1 className="mt-3 text-center text-3xl sm:text-4xl">
          Entrar no portal
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-ciano" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          Acesso para parceiros comerciais BDFlow.
        </p>

        <form onSubmit={entrar} className="card mt-8 space-y-4 p-6">
          <div>
            <label htmlFor="pl-email" className="mb-1.5 block text-sm font-semibold">
              E-mail
            </label>
            <input
              id="pl-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="username"
              required
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
            />
          </div>
          <div>
            <label htmlFor="pl-senha" className="mb-1.5 block text-sm font-semibold">
              Senha
            </label>
            <input
              id="pl-senha"
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              autoComplete="current-password"
              required
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
            />
          </div>

          {erro && (
            <p className="rounded-xl bg-magenta/10 px-4 py-2.5 text-sm font-medium text-magenta">
              {erro}
            </p>
          )}

          <button type="submit" disabled={enviando} className="btn-primary w-full">
            {enviando ? "Aguarde..." : "Entrar"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm">
          <Link to="/" className="font-medium text-ciano hover:underline">
            ← Voltar ao site
          </Link>
        </p>
      </main>
    </>
  );
}
