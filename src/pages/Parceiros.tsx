import { Link, Navigate, useSearchParams } from "react-router-dom";
import Header from "../components/Header";

/**
 * /parceiros — página pública para empresas interessadas em se tornar parceiras.
 *
 * Não autentica ninguém. A candidatura vive em /parceiros/cadastro.
 * O acompanhamento provisório vive em /parceiros/acesso.
 * Parceiros aprovados entram pelo Portal do Parceiro em /portal/login.
 */
export default function Parceiros() {
  const [params] = useSearchParams();
  const legadoNext = params.get("next");

  // Compatibilidade com links antigos do acesso provisório.
  if (legadoNext) {
    return (
      <Navigate
        to={`/parceiros/acesso?next=${encodeURIComponent(legadoNext)}`}
        replace
      />
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-6xl px-4 pb-24 pt-12">
        <section className="max-w-3xl">
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
            Para empresas
          </p>
          <h1 className="mt-4 text-4xl leading-[1.05] sm:text-6xl">
            Torne sua empresa parceira BDFlow.
          </h1>
          <p className="mt-5 max-w-2xl text-lg text-tinta/70">
            Solicite a análise da sua empresa para participar das oportunidades
            comerciais BDFlow. O cadastro não cria acesso ao Portal do Parceiro
            imediatamente: primeiro a solicitação passa pela análise prevista.
          </p>

          <div className="mt-8 flex flex-wrap gap-3">
            <Link to="/parceiros/cadastro" className="btn-primary">
              Solicitar parceria
            </Link>
            <Link to="/parceiros/acesso" className="btn-secondary">
              Acompanhar solicitação
            </Link>
          </div>
        </section>

        <section className="mt-14 grid gap-4 lg:grid-cols-3">
          <div className="border-t border-borda pt-5">
            <p className="text-sm font-bold text-magenta">01</p>
            <h2 className="mt-2 text-xl">Envie a solicitação</h2>
            <p className="mt-2 text-sm leading-6 text-tinta/65">
              Informe os dados da empresa, do responsável e aceite os documentos
              vigentes exigidos para análise.
            </p>
          </div>

          <div className="border-t border-borda pt-5">
            <p className="text-sm font-bold text-magenta">02</p>
            <h2 className="mt-2 text-xl">Acompanhe a análise</h2>
            <p className="mt-2 text-sm leading-6 text-tinta/65">
              Após confirmar o e-mail, o acesso provisório permite acompanhar o
              status, responder correções e enviar documentos.
            </p>
          </div>

          <div className="border-t border-borda pt-5">
            <p className="text-sm font-bold text-magenta">03</p>
            <h2 className="mt-2 text-xl">Entre no Portal do Parceiro</h2>
            <p className="mt-2 text-sm leading-6 text-tinta/65">
              Depois da aprovação e ativação do vínculo comercial, a operação
              cotidiana acontece no Portal do Parceiro.
            </p>
          </div>
        </section>

        <section className="mt-14 rounded-3xl bg-tinta p-8 text-white sm:p-10">
          <div className="grid gap-8 md:grid-cols-[1fr_auto] md:items-center">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.3em] text-amarelo">
                Já é parceiro aprovado?
              </p>
              <h2 className="mt-3 text-2xl sm:text-3xl">Acesse o Portal do Parceiro.</h2>
              <p className="mt-3 max-w-2xl text-sm leading-6 text-white/70">
                O Portal reúne as funções operacionais da parceria, incluindo
                equipe, solicitações e validação de benefícios.
              </p>
            </div>
            <Link
              to="/portal/login"
              className="inline-flex items-center justify-center rounded-xl bg-white px-6 py-3 font-semibold text-tinta transition hover:bg-amarelo"
            >
              Entrar no portal
            </Link>
          </div>
        </section>
      </main>
    </>
  );
}
