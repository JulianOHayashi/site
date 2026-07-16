import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { appSupabase, portalConfigurado } from "../../lib/appSupabaseClient";
import { usePortalAuth } from "../../hooks/usePortalAuth";
import { CarregandoPortal, PortalNaoConfigurado } from "./portalUi";

/**
 * /portal/login — entrada do PARCEIRO COMERCIAL BDFlow
 * (supermercado, farmácia, loja que valida QR codes).
 * Não é o usuário do app móvel.
 *
 * Fluxo (spec):
 * 1. Auth no APP Supabase (e-mail + senha)
 * 2. Chama get_my_partner_context()
 * 3. Com vínculo → /portal/dashboard (ou ?next= preservado, ex.: validação com ?qt=)
 * 4. Sem vínculo → mensagem exata de não-vinculado
 */

export default function PortalLogin() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { session, carregando } = usePortalAuth();

  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [semVinculo, setSemVinculo] = useState(false);
  const [enviando, setEnviando] = useState(false);

  const destinoAposLogin = () => {
    const next = params.get("next");
    return next && next.startsWith("/portal") ? next : "/portal/dashboard";
  };

  const verificarVinculo = async (): Promise<boolean> => {
    const { data, error } = await appSupabase!.rpc("get_my_partner_context");
    if (error || data == null) return false;
    // contexto pode vir como objeto ou array — qualquer conteúdo = vinculado
    if (Array.isArray(data) && data.length === 0) return false;
    return true;
  };

  // Já logado? Verifica vínculo e segue.
  useEffect(() => {
    if (carregando || !session || !appSupabase) return;
    verificarVinculo().then((ok) => {
      if (ok) navigate(destinoAposLogin(), { replace: true });
      else setSemVinculo(true);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [carregando, session]);

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!appSupabase) return;
    setErro(null);
    setSemVinculo(false);
    setEnviando(true);

    const { error } = await appSupabase.auth.signInWithPassword({
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

    const ok = await verificarVinculo();
    setEnviando(false);

    if (ok) {
      navigate(destinoAposLogin(), { replace: true });
    } else {
      setSemVinculo(true);
    }
  };

  const sair = async () => {
    await appSupabase?.auth.signOut();
    setSemVinculo(false);
  };

  if (!portalConfigurado) {
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
          Acesso para parceiros comerciais que validam QR codes — mercados,
          farmácias e lojas.
        </p>

        {semVinculo ? (
          <div className="mt-8 rounded-2xl border-2 border-amarelo bg-amarelo/15 p-6 text-center">
            <p className="font-semibold">
              Seu usuário ainda não está vinculado a um parceiro comercial
              BDFlow.
            </p>
            <p className="mt-2 text-sm text-tinta/70">
              Fale com o administrador do seu estabelecimento ou com o suporte
              BDFlow para ativar o vínculo.
            </p>
            <button
              onClick={sair}
              className="btn-secondary mt-4"
            >
              Entrar com outra conta
            </button>
          </div>
        ) : (
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
        )}

        <p className="mt-6 text-center text-sm">
          <Link to="/" className="font-medium text-ciano hover:underline">
            ← Voltar ao site
          </Link>
        </p>
      </main>
    </>
  );
}
