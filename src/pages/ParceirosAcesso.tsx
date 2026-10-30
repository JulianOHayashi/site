import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import Header from "../components/Header";
import { supabase, supabaseConfigurado } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";
import { safeInternalDestination } from "../lib/safeInternalDestination";
import { useCaptchaAuth } from "../components/seguranca/useCaptchaAuth";
import {
  MENSAGEM_CAPTCHA_INDISPONIVEL,
  MENSAGEM_CAPTCHA_PENDENTE,
  mensagemSeguraDeAuth,
  opcoesComCaptcha,
} from "../lib/captcha";

/**
 * /parceiros/acesso — acesso da conta provisória de uma solicitação.
 *
 * Esta rota existe somente para acompanhar a candidatura antes da aprovação.
 * Parceiros já aprovados entram pelo Portal do Parceiro em /portal/login.
 */
export default function ParceirosAcesso() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { session, carregando } = useAuth();

  const destino = safeInternalDestination(
    params.get("next"),
    "/parceiros/solicitacao",
    { requiredPrefix: "/parceiros" }
  );

  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const captcha = useCaptchaAuth("login_provisorio");

  useEffect(() => {
    if (!carregando && session) navigate(destino, { replace: true });
  }, [carregando, session, navigate, destino]);

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || enviando) return;
    // Sem CAPTCHA válido, nada é enviado ao Auth.
    if (!captcha.pronto) {
      setErro(captcha.bloqueado ? MENSAGEM_CAPTCHA_INDISPONIVEL : MENSAGEM_CAPTCHA_PENDENTE);
      return;
    }

    setErro(null);
    setEnviando(true);
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password: senha,
      options: opcoesComCaptcha(captcha.consumir()),
    });
    setEnviando(false);

    if (error) {
      setErro(
        error.code === "invalid_credentials" || error.message.includes("Invalid login")
          ? "E-mail ou senha incorretos."
          : mensagemSeguraDeAuth(error, "Não foi possível entrar. Tente novamente.")
      );
      return;
    }

    navigate(destino, { replace: true });
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        <p className="flex justify-center rotulo-marca">
          Solicitação de parceria
        </p>
        <h1 className="mt-3 text-center text-3xl sm:text-4xl">
          Acompanhar solicitação
          <span className="mx-auto mt-3 traco-marca" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          Use o acesso provisório criado durante sua candidatura para acompanhar
          a análise, responder correções e enviar documentos.
        </p>

        {!supabaseConfigurado && (
          <div className="mt-6 aviso-atencao p-4 text-center">
            Área temporariamente indisponível.
          </div>
        )}

        <form onSubmit={entrar} className="card mt-8 space-y-4 p-6">
          <div>
            <label htmlFor="pa-email" className="mb-1.5 block text-sm font-semibold">
              E-mail
            </label>
            <input
              id="pa-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="username"
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-magenta"
            />
          </div>

          <div>
            <label htmlFor="pa-senha" className="mb-1.5 block text-sm font-semibold">
              Senha
            </label>
            <input
              id="pa-senha"
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              autoComplete="current-password"
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-magenta"
            />
          </div>

          {captcha.widget}

          {erro && (
            <p className="aviso-erro font-medium">
              {erro}
            </p>
          )}

          <button
            type="submit"
            disabled={!supabaseConfigurado || enviando || !captcha.pronto}
            className="btn-primary w-full"
          >
            {enviando ? "Aguarde..." : "Entrar para acompanhar"}
          </button>
        </form>

        <div className="mt-6 space-y-2 text-center text-sm">
          <p>
            <Link to="/parceiros/recuperar" className="font-medium text-ciano hover:underline">
              Reenviar link de acesso
            </Link>
          </p>
          <p>
            <Link to="/parceiros" className="font-medium text-ciano hover:underline">
              ← Voltar para parceiros
            </Link>
          </p>
        </div>
      </main>
    </>
  );
}
