import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import { PortalNaoConfigurado } from "./portalUi";

type Estado = "checando" | "pronto" | "invalido" | "sucesso";

export default function PortalResetPassword() {
  const [estado, setEstado] = useState<Estado>("checando");
  const [senha, setSenha] = useState("");
  const [confirmacao, setConfirmacao] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  useEffect(() => {
    if (!supabase) return;

    let ativo = true;

    const { data: listener } = supabase.auth.onAuthStateChange((evento, sessao) => {
      if (!ativo) return;
      if (evento === "PASSWORD_RECOVERY" && sessao) {
        setEstado("pronto");
      }
    });

    void (async () => {
      const { data, error } = await supabase.auth.getSession();
      if (!ativo) return;

      const modoRecuperacao =
        new URLSearchParams(window.location.search).get("mode") === "recovery";

      if (!error && data.session && modoRecuperacao) {
        setEstado("pronto");
      } else {
        setEstado((atual) => (atual === "pronto" ? atual : "invalido"));
      }
    })();

    return () => {
      ativo = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  const salvar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || salvando || estado !== "pronto") return;

    setErro(null);

    if (senha.length < 8) {
      setErro("Use uma senha com pelo menos 8 caracteres.");
      return;
    }
    if (senha !== confirmacao) {
      setErro("As senhas informadas não coincidem.");
      return;
    }

    setSalvando(true);
    const { error } = await supabase.auth.updateUser({ password: senha });

    if (error) {
      setSalvando(false);
      setErro("Não foi possível alterar a senha. Solicite um novo link e tente novamente.");
      return;
    }

    // Evita deixar uma sessão de recuperação aberta no navegador compartilhado.
    await supabase.auth.signOut();
    setSalvando(false);
    setSenha("");
    setConfirmacao("");
    setEstado("sucesso");
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
          Definir nova senha
        </h1>

        {estado === "checando" && (
          <p className="mt-8 text-center text-sm text-tinta/60" role="status">
            Validando o link de recuperação...
          </p>
        )}

        {estado === "invalido" && (
          <section className="card mt-8 p-6 text-center" role="alert">
            <h2 className="text-lg font-bold">Link inválido ou expirado</h2>
            <p className="mt-3 text-sm text-tinta/70">
              Solicite um novo link de recuperação para continuar.
            </p>
            <Link
              to="/portal/recuperar-senha"
              className="btn-primary mt-5 inline-block"
            >
              Solicitar novo link
            </Link>
          </section>
        )}

        {estado === "sucesso" && (
          <section className="card mt-8 p-6 text-center" role="status" aria-live="polite">
            <h2 className="text-lg font-bold">Senha alterada</h2>
            <p className="mt-3 text-sm text-tinta/70">
              A nova senha foi salva. Entre novamente no Portal.
            </p>
            <Link to="/portal/login" className="btn-primary mt-5 inline-block">
              Ir para o login
            </Link>
          </section>
        )}

        {estado === "pronto" && (
          <form onSubmit={salvar} className="card mt-8 space-y-4 p-6">
            <div>
              <label htmlFor="nova-senha" className="mb-1.5 block text-sm font-semibold">
                Nova senha
              </label>
              <input
                id="nova-senha"
                type="password"
                value={senha}
                onChange={(e) => setSenha(e.target.value)}
                autoComplete="new-password"
                minLength={8}
                required
                className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
              />
            </div>

            <div>
              <label htmlFor="confirmar-senha" className="mb-1.5 block text-sm font-semibold">
                Confirmar nova senha
              </label>
              <input
                id="confirmar-senha"
                type="password"
                value={confirmacao}
                onChange={(e) => setConfirmacao(e.target.value)}
                autoComplete="new-password"
                minLength={8}
                required
                className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
              />
            </div>

            {erro && (
              <p className="rounded-xl bg-magenta/10 px-4 py-2.5 text-sm font-medium text-magenta" role="alert">
                {erro}
              </p>
            )}

            <button type="submit" disabled={salvando} className="btn-primary w-full">
              {salvando ? "Salvando..." : "Salvar nova senha"}
            </button>
          </form>
        )}
      </main>
    </>
  );
}
