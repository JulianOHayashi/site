import { useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../components/Header";
import { supabase } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";

/**
 * PAINEL DO PARCEIRO — rota protegida (exige login).
 *
 * ESTADO DE TRANSIÇÃO (pré-migration). O modelo antigo — perfil em `profiles`,
 * histórico de `orders`, percentual de fidelidade via `desconto_para_cnpj`,
 * desconto por volume e "primeira compra libera desconto" — NÃO representa o
 * modelo vigente e foi removido do fluxo ativo. A fidelidade nova
 * (CNPJ + cidade + nicho), oportunidades, contratos e preços serão
 * implementados nas próximas etapas (Fase 2).
 *
 * Nada de preço/fidelidade/pedidos é consultado ou prometido aqui.
 */
export default function ParceirosPainel() {
  const navigate = useNavigate();
  const { session, carregando } = useAuth();

  // Proteção da rota preservada: sem sessão → volta para /parceiros.
  useEffect(() => {
    if (!carregando && !session) navigate("/parceiros");
  }, [carregando, session, navigate]);

  const sair = async () => {
    await supabase?.auth.signOut();
    navigate("/");
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
      <main className="mx-auto max-w-3xl px-4 pb-24 pt-10">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
              Área de parceiros
            </p>
            <h1 className="mt-2 text-3xl sm:text-4xl">
              Painel comercial em atualização
            </h1>
          </div>
          <button
            onClick={sair}
            className="rounded-xl border-2 border-tinta px-4 py-2 text-sm font-semibold transition hover:bg-tinta hover:text-white"
          >
            Sair
          </button>
        </div>

        <div className="card mt-8 p-8">
          <p className="text-tinta/70">
            As oportunidades, contratos, preços e condições de fidelidade serão
            disponibilizados nas próximas etapas do Site BDFlow.
          </p>

          <div className="mt-6 flex flex-wrap gap-3">
            <Link to="/oportunidades" className="btn-primary">
              Ver oportunidades
            </Link>
            <Link to="/portal/login" className="btn-secondary">
              Ir para o Portal BDFlow
            </Link>
          </div>
        </div>
      </main>
    </>
  );
}
