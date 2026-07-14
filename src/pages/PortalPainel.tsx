import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import Header from "../components/Header";
import { supabaseApp } from "../lib/supabaseApp";
import { useAuthApp } from "../hooks/useAuthApp";

/**
 * PAINEL DO PORTAL (protegido — exige login com a conta do APP).
 *
 * O que já funciona: sessão, dados básicos da conta e saída.
 *
 * ⚠️ ONDE PLUGAR OS DADOS REAIS DO APP:
 * Os três blocos abaixo (QR codes, pagamentos, informações) estão
 * prontos com consultas de EXEMPLO comentadas. Para ativar, basta
 * me informar os nomes reais das tabelas/colunas do projeto do app
 * (ex.: print do Table Editor) que eu ligo cada bloco — as regras
 * RLS do projeto do app continuam mandando no que cada um vê.
 */

export default function PortalPainel() {
  const navigate = useNavigate();
  const { session, carregando } = useAuthApp();
  const [nome, setNome] = useState<string | null>(null);

  // proteção da rota
  useEffect(() => {
    if (!carregando && !session) navigate("/portal");
  }, [carregando, session, navigate]);

  useEffect(() => {
    if (!session) return;
    const meta = session.user.user_metadata as Record<string, string>;
    setNome(meta?.nome ?? meta?.name ?? meta?.full_name ?? null);

    /* REGRA DE ARQUITETURA (spec BDFlow): dados de QR/benefícios do
       app são acessados EXCLUSIVAMENTE pelos RPCs existentes do
       projeto do app — nunca leitura direta de tabela. Quando formos
       ligar os blocos, os exemplos são:

    supabaseApp!.rpc("get_my_partner_context")
      .then(({ data }) => setContexto(data));

    supabaseApp!.rpc("get_partner_cycle_status")
      .then(({ data }) => setCiclo(data));

    supabaseApp!.rpc("get_my_partner_redemption_requests")
      .then(({ data }) => setSolicitacoes(data ?? []));

       Demais RPCs disponíveis: validate_partner_wallet_qr,
       create_partner_redemption_request,
       cancel_partner_redemption_request.
    */
  }, [session]);

  const sair = async () => {
    await supabaseApp?.auth.signOut();
    navigate("/portal");
  };

  if (carregando) {
    return (
      <>
        <Header />
        <div className="mt-24 flex justify-center">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
        </div>
      </>
    );
  }

  if (!session) return null; // redirecionando

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
              Conta do aplicativo
            </p>
            <h1 className="mt-1 text-3xl sm:text-4xl">
              Olá{nome ? `, ${nome}` : ""}!
            </h1>
            <p className="mt-1 text-sm text-tinta/60">{session.user.email}</p>
          </div>
          <button
            onClick={sair}
            className="rounded-xl border-2 border-tinta px-4 py-2 text-sm font-semibold transition hover:bg-tinta hover:text-white"
          >
            Sair
          </button>
        </div>

        {/* BLOCOS DO APP — prontos para receber os dados reais */}
        <div className="mt-10 grid gap-5 md:grid-cols-3">
          {/* ⚠️ QR CODES — plugar tabela real do app */}
          <section className="rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
            <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-papel2 text-xl">
              🔳
            </span>
            <h2 className="mt-4 text-xl">Seus QR codes</h2>
            <p className="mt-2 rounded-xl border border-dashed border-borda p-4 text-xs text-tinta/50">
              Este bloco listará os QR codes gerados no app.
              <span className="mt-1 block">(⚠️ aguardando o nome da tabela no projeto do app)</span>
            </p>
          </section>

          {/* ⚠️ PAGAMENTOS — plugar tabela real do app */}
          <section className="rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
            <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-papel2 text-xl">
              💳
            </span>
            <h2 className="mt-4 text-xl">Pagamentos</h2>
            <p className="mt-2 rounded-xl border border-dashed border-borda p-4 text-xs text-tinta/50">
              Este bloco mostrará o histórico de pagamentos registrado no app.
              <span className="mt-1 block">(⚠️ aguardando o nome da tabela no projeto do app)</span>
            </p>
          </section>

          {/* ⚠️ INFORMAÇÕES DO PARCEIRO — plugar tabela real do app */}
          <section className="rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
            <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-papel2 text-xl">
              🏪
            </span>
            <h2 className="mt-4 text-xl">Suas informações</h2>
            <p className="mt-2 rounded-xl border border-dashed border-borda p-4 text-xs text-tinta/50">
              Dados comerciais do parceiro vindos do app.
              <span className="mt-1 block">(⚠️ aguardando o nome da tabela no projeto do app)</span>
            </p>
          </section>
        </div>

        <p className="mt-8 text-center text-xs text-tinta/40">
          Os dados exibidos aqui vêm do projeto do aplicativo e respeitam as
          regras de acesso (RLS) definidas lá — cada parceiro vê apenas o que
          é seu.
        </p>
      </main>
    </>
  );
}
