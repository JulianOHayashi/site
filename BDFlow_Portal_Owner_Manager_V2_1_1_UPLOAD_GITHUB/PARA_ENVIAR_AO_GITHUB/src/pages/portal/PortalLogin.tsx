import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import { usePortalSiteAuth } from "../../hooks/usePortalSiteAuth";
import { CarregandoPortal, PortalNaoConfigurado } from "./portalUi";
import { safePortalNext } from "../../domain/portal/nextTarget";

/**
 * /portal/login — autentica no Supabase do SITE (mesmo cliente usado por
 * /parceiros e /admin). Não chama RPC do Supabase do APP.
 *
 * V2.1 — Troca segura de conta:
 * Com `switch_account=1`, NÃO reutilizamos a sessão existente nem redirecionamos
 * automaticamente. Encerramos a sessão local (`signOut({ scope: "local" })`),
 * bloqueando o formulário até o encerramento concluir. Se o encerramento
 * falhar, o formulário permanece bloqueado, sem navegar ao convite e sem
 * declarar sucesso. Só voltamos ao `next` após NOVA autenticação bem-sucedida.
 */
export default function PortalLogin() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { session, carregando } = usePortalSiteAuth();

  const switchAccount = params.get("switch_account") === "1";
  // Destino validado com allowlist do Portal (5.3). Inválido → /portal/dashboard.
  const destinoAposLogin = () => safePortalNext(params.get("next"));

  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  // Estados da troca de conta.
  const [encerrandoSessao, setEncerrandoSessao] = useState(switchAccount);
  const [falhaEncerrar, setFalhaEncerrar] = useState(false);
  const [sessaoAnteriorEncerrada, setSessaoAnteriorEncerrada] = useState(false);

  // Guard de idempotência: impede que o disparo automático execute o
  // encerramento mais de uma vez. Necessário porque, sob React.StrictMode
  // (dev), o efeito monta → desmonta → remonta, o que dispararia signOut
  // duas vezes para uma única troca de conta. A retentativa manual reseta
  // este guard explicitamente, então continua funcionando.
  const encerramentoIniciado = useRef(false);

  // --- Fluxo normal: já logado e SEM switch_account → segue direto. ---
  useEffect(() => {
    if (switchAccount) return; // troca de conta desativa o redirecionamento automático
    if (!carregando && session) {
      navigate(destinoAposLogin(), { replace: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [carregando, session, switchAccount]);

  // --- Troca de conta: encerra a sessão local antes de liberar o formulário. ---
  // `manual = true` na retentativa do usuário, que libera o guard de reentrada.
  const encerrarSessaoLocal = async (manual = false) => {
    if (manual) encerramentoIniciado.current = false;
    // Já em andamento/concluído por este ciclo → não repete (protege StrictMode).
    if (encerramentoIniciado.current) return;
    encerramentoIniciado.current = true;

    setFalhaEncerrar(false);
    setEncerrandoSessao(true);
    if (!supabase) {
      // Sem cliente configurado, não há sessão a encerrar com segurança.
      encerramentoIniciado.current = false; // permite nova tentativa
      setFalhaEncerrar(true);
      setEncerrandoSessao(false);
      return;
    }
    const { error } = await supabase.auth.signOut({ scope: "local" });
    if (error) {
      // Não liberar o formulário, não navegar, não declarar sucesso.
      encerramentoIniciado.current = false; // permite nova tentativa
      setFalhaEncerrar(true);
      setEncerrandoSessao(false);
      return;
    }
    setSessaoAnteriorEncerrada(true);
    setEncerrandoSessao(false);
  };

  useEffect(() => {
    if (!switchAccount) return;
    if (carregando) return;
    // Executa o encerramento uma única vez ao entrar em modo troca de conta.
    void encerrarSessaoLocal();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [switchAccount, carregando]);

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
    // Após NOVA autenticação bem-sucedida, navega ao destino seguro.
    // (No fluxo de troca de conta, este é o único caminho de volta ao convite.)
    navigate(destinoAposLogin(), { replace: true });
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

  // Carregamento do hook de sessão (fluxo normal).
  if (carregando && !switchAccount) {
    return (
      <>
        <Header />
        <CarregandoPortal />
      </>
    );
  }

  // Troca de conta: encerrando a sessão anterior.
  if (switchAccount && encerrandoSessao) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14 text-center">
          <div className="mt-16 flex flex-col items-center gap-3">
            <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
            <p className="text-sm text-tinta/60">Encerrando a sessão anterior...</p>
          </div>
        </main>
      </>
    );
  }

  // Troca de conta: falha ao encerrar → não libera o formulário.
  if (switchAccount && falhaEncerrar) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14 text-center">
          <div className="mt-10 rounded-3xl border-2 border-magenta/30 bg-magenta/10 p-6">
            <p className="font-semibold">Não foi possível encerrar a sessão anterior.</p>
            <p className="mx-auto mt-2 max-w-sm text-sm text-tinta/70">
              Por segurança, o acesso não foi liberado e você não foi
              redirecionado. Tente encerrar a sessão novamente.
            </p>
            <button
              onClick={() => encerrarSessaoLocal(true)}
              className="btn-primary mt-5"
            >
              Tentar encerrar sessão novamente
            </button>
          </div>
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
        <h1 className="mt-3 text-center text-3xl sm:text-4xl">
          Entrar no portal
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-ciano" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          Acesso para parceiros comerciais BDFlow.
        </p>

        {switchAccount && sessaoAnteriorEncerrada && (
          <p className="mt-5 rounded-xl bg-amarelo/20 px-4 py-3 text-center text-sm">
            A sessão anterior foi encerrada. Entre com a conta correta para
            continuar.
          </p>
        )}

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
