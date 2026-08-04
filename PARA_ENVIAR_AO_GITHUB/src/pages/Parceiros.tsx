import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../components/Header";
import { supabase, supabaseConfigurado } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";

/**
 * ÁREA DE PARCEIROS — somente LOGIN (homologação Fase 1).
 *
 * O cadastro público de empresas está TEMPORARIAMENTE indisponível: não há
 * aba "Cadastrar", campos de empresa/CNPJ, chamada a signUp nem criação de
 * registro no Supabase por esta página. Apenas o login de parceiros
 * existentes (e-mail + senha) permanece ativo, levando a /parceiros/painel.
 *
 * Pacote P0: adicionado um link claramente provisório para
 * /parceiros/cadastro (página informativa, sem formulário, sem RPC, sem
 * signUp/insert). Esta página em si continua sendo só login.
 */
export default function Parceiros() {
  const navigate = useNavigate();
  const { session, carregando } = useAuth();

  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  // Já logado? Vai direto ao painel.
  useEffect(() => {
    if (!carregando && session) navigate("/parceiros/painel");
  }, [carregando, session, navigate]);

  const entrar = async () => {
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
    navigate("/parceiros/painel");
  };

  const enviar = (e: React.FormEvent) => {
    e.preventDefault();
    entrar();
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        <h1 className="text-center text-3xl sm:text-4xl">
          Área de parceiros
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-ciano" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          Empresas parceiras: entre para acompanhar oportunidades e informações
          comerciais.
        </p>

        {!supabaseConfigurado && (
          <div className="mt-6 rounded-2xl bg-amarelo/25 p-4 text-center text-sm">
            Modo demonstração — o login real será ativado quando o Supabase
            estiver conectado (Auth por e-mail).
          </div>
        )}

        {/* Cadastro público desativado temporariamente. */}
        <div className="mt-8 rounded-2xl border border-borda bg-white px-4 py-3 text-center text-sm font-semibold text-tinta/60">
          Entrar
          <span className="ml-2 rounded-full bg-papel2 px-2 py-0.5 text-xs font-medium text-tinta/50">
            Cadastro em breve
          </span>
        </div>
        <p className="mt-3 text-center text-sm">
          <Link
            to="/parceiros/cadastro"
            className="font-medium text-ciano hover:underline"
          >
            Ver como está a preparação do novo cadastro →
          </Link>
        </p>

        {/* formulário — somente login */}
        <form onSubmit={enviar} className="card mt-4 space-y-4 p-6">
          <div>
            <label htmlFor="p-email" className="mb-1.5 block text-sm font-semibold">
              E-mail
            </label>
            <input
              id="p-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
            />
          </div>

          <div>
            <label htmlFor="p-senha" className="mb-1.5 block text-sm font-semibold">
              Senha
            </label>
            <input
              id="p-senha"
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
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
            {enviando ? "Aguarde..." : "Entrar"}
          </button>
        </form>

        <p className="mt-6 text-center text-xs text-tinta/40">
          O cadastro de novas empresas parceiras será disponibilizado em uma
          próxima etapa.
        </p>
        <p className="mt-2 text-center text-sm">
          <Link to="/" className="font-medium text-ciano hover:underline">
            ← Voltar ao início
          </Link>
        </p>
      </main>
    </>
  );
}
