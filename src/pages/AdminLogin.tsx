import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import Header from "../components/Header";
import { supabase, supabaseConfigurado } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";

/**
 * /admin/login — autenticação administrativa.
 *
 * Esta página APENAS autentica (e-mail + senha via Supabase do site).
 * A autorização administrativa pertence ao AdminGuard, que consulta a
 * RPC is_site_admin. Aqui não há allowlist, e-mail fixo, senha
 * hardcoded, leitura de site_admins nem concessão de papel.
 */
export default function AdminLogin() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { session, carregando } = useAuth();

  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  // next seguro: apenas caminhos internos iniciados por /admin
  const destino = (() => {
    const next = params.get("next");
    if (next && next.startsWith("/admin") && !next.startsWith("//")) return next;
    return "/admin";
  })();

  // já autenticado → segue ao destino (autorização é do AdminGuard).
  // Navegação em efeito, nunca durante a renderização.
  useEffect(() => {
    if (!carregando && session) {
      navigate(destino, { replace: true });
    }
  }, [carregando, session, destino, navigate]);

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase) return;
    setErro(null);
    setEnviando(true);
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password: senha,
    });
    setEnviando(false);
    if (error) {
      setErro(
        error.message.includes("Invalid login")
          ? "E-mail ou senha incorretos."
          : "Não foi possível entrar. Tente novamente."
      );
      return;
    }
    // sessão detectada → AdminGuard decide o acesso ao painel
    navigate(destino, { replace: true });
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        <p className="text-center text-xs font-bold uppercase tracking-[0.3em] text-magenta">
          Acesso restrito
        </p>
        <h1 className="mt-3 text-center text-3xl sm:text-4xl">
          Painel administrativo
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-magenta" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          Área de gestão do site. Apenas administradores autorizados.
        </p>

        {!supabaseConfigurado && (
          <div className="mt-6 rounded-2xl bg-amarelo/25 p-4 text-center text-sm">
            Supabase do site não configurado. Defina VITE_SUPABASE_URL e
            VITE_SUPABASE_ANON_KEY e recarregue.
          </div>
        )}

        <form onSubmit={entrar} className="card mt-6 space-y-4 p-6">
          <div>
            <label htmlFor="ad-email" className="mb-1.5 block text-sm font-semibold">
              E-mail
            </label>
            <input
              id="ad-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="username"
              required
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-magenta"
            />
          </div>
          <div>
            <label htmlFor="ad-senha" className="mb-1.5 block text-sm font-semibold">
              Senha
            </label>
            <input
              id="ad-senha"
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              autoComplete="current-password"
              required
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-magenta"
            />
          </div>

          {erro && (
            <p className="rounded-xl bg-magenta/10 px-4 py-2.5 text-sm font-medium text-magenta">
              {erro}
            </p>
          )}

          <button
            type="submit"
            disabled={!supabaseConfigurado || enviando}
            className="btn-primary w-full"
          >
            {enviando ? "Entrando..." : "Entrar"}
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
