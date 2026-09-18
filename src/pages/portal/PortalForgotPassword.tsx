import { useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import { PortalNaoConfigurado } from "./portalUi";

const RESPOSTA_INVARIANTE =
  "Se houver uma conta para este e-mail, enviaremos as instruções para redefinir a senha.";

export default function PortalForgotPassword() {
  const [email, setEmail] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [concluido, setConcluido] = useState(false);

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || enviando) return;

    setEnviando(true);
    try {
      const redirectTo =
        `${window.location.origin}/portal/redefinir-senha?mode=recovery`;

      await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
        redirectTo,
      });
    } finally {
      // Resposta visual invariável: não revela se o e-mail existe, se está
      // confirmado nem qualquer detalhe da conta.
      setEnviando(false);
      setConcluido(true);
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
        <p className="text-center text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
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

            <button type="submit" disabled={enviando} className="btn-primary w-full">
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
