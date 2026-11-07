import { useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import { PortalNaoConfigurado } from "./portalUi";
import { useCaptchaAuth } from "../../components/seguranca/useCaptchaAuth";
import {
  ehErroDeCaptcha,
  MENSAGEM_CAPTCHA_FALHOU,
  MENSAGEM_CAPTCHA_INDISPONIVEL,
  MENSAGEM_CAPTCHA_PENDENTE,
  opcoesComCaptcha,
} from "../../lib/captcha";

const RESPOSTA_INVARIANTE =
  "Se houver uma conta para este e-mail, enviaremos as instruções para redefinir a senha.";

export default function PortalForgotPassword() {
  const [email, setEmail] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [concluido, setConcluido] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const captcha = useCaptchaAuth("reset_senha");

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || enviando) return;
    // Sem CAPTCHA válido, nada é enviado ao Auth.
    if (!captcha.pronto) {
      setErro(captcha.bloqueado ? MENSAGEM_CAPTCHA_INDISPONIVEL : MENSAGEM_CAPTCHA_PENDENTE);
      return;
    }

    setErro(null);
    setEnviando(true);
    let recusadoPorCaptcha = false;
    try {
      const redirectTo =
        `${window.location.origin}/portal/redefinir-senha?mode=recovery`;

      const { error } = await supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        opcoesComCaptcha(captcha.consumir(), { redirectTo })
      );
      // CAPTCHA recusado não diz nada sobre a conta, e nenhum e-mail saiu:
      // pede nova tentativa em vez de fingir que enviou.
      recusadoPorCaptcha = ehErroDeCaptcha(error);
    } finally {
      setEnviando(false);
      if (recusadoPorCaptcha) {
        setErro(MENSAGEM_CAPTCHA_FALHOU);
      } else {
        // Resposta visual invariável: não revela se o e-mail existe, se está
        // confirmado nem qualquer detalhe da conta.
        setConcluido(true);
      }
    }
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

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        <p className="flex justify-center rotulo-marca">
          Portal do parceiro SmallFlags
        </p>
        <h1 className="mt-3 text-center text-3xl">
          Recuperar senha
        </h1>

        {concluido ? (
          <section className="card mt-8 p-6 text-center" role="status" aria-live="polite">
            <h2 className="text-lg font-bold">Verifique seu e-mail</h2>
            <p className="mt-3 text-sm text-tinta/70">{RESPOSTA_INVARIANTE}</p>
            <Link
              to="/portal/login"
              className="btn-secondary mt-5 inline-block"
            >
              Voltar ao login
            </Link>
          </section>
        ) : (
          <form onSubmit={enviar} className="card mt-8 space-y-4 p-6">
            <p className="text-sm text-tinta/70">
              Informe o e-mail usado no Portal. Se a conta estiver elegível,
              você receberá um link de uso único para definir uma nova senha.
            </p>

            <div>
              <label htmlFor="pr-email" className="mb-1.5 block text-sm font-semibold">
                E-mail
              </label>
              <input
                id="pr-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                required
                className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
              />
            </div>

            {captcha.widget}

            {erro && <p role="alert" className="aviso-erro font-medium">{erro}</p>}

            <button type="submit" disabled={enviando || !captcha.pronto} className="btn-primary w-full">
              {enviando ? "Enviando..." : "Enviar link de recuperação"}
            </button>

            <p className="text-center text-sm">
              <Link to="/portal/login" className="font-medium text-ciano hover:underline">
                Voltar ao login
              </Link>
            </p>
          </form>
        )}
      </main>
    </>
  );
}
