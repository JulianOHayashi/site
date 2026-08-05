import { Link } from "react-router-dom";
import Header from "../components/Header";

/**
 * Área administrativa autenticada.
 *
 * O painel antigo de pedidos e estoque usava dados fictícios do domínio
 * comercial anterior e foi removido. Até os módulos da Fase 2A estarem
 * prontos, esta tela mostra apenas acessos reais e não simula operações.
 */
export default function Admin() {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-12">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
          Administração BDFlow
        </p>
        <h1 className="mt-3 text-3xl sm:text-4xl">Painel administrativo</h1>
        <p className="mt-4 max-w-2xl text-tinta/70">
          O acesso já é protegido pela autorização do backend. Os módulos de
          análise de empresas, owners, managers, unidades e documentos serão
          adicionados conforme a Fase 2A avançar.
        </p>

        <section className="card mt-8 p-6">
          <h2 className="text-xl">Recursos disponíveis</h2>
          <div className="mt-5 flex flex-wrap gap-3">
            <Link to="/oportunidades" className="btn-primary">
              Ver oportunidades
            </Link>
            <Link to="/portal/dashboard" className="btn-secondary">
              Abrir Portal BDFlow
            </Link>
          </div>
        </section>

        <section className="mt-6 rounded-3xl border border-borda bg-papel2 p-6">
          <p className="font-semibold">Operações simuladas foram removidas.</p>
          <p className="mt-2 text-sm text-tinta/70">
            Este painel não exibe pedidos, estoque, pagamentos ou métricas
            fictícias. Cada módulo futuro deverá consumir dados autorizados
            pelo Supabase do Site.
          </p>
        </section>
      </main>
    </>
  );
}
