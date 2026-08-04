import { Link } from "react-router-dom";
import Header from "../components/Header";

/**
 * /parceiros/cadastro — página PROVISÓRIA (Pacote P0).
 *
 * O cadastro definitivo da Fase 2A (solicitação pública, conta provisória,
 * análise administrativa, validação de autoridade do owner) ainda não foi
 * implementado — depende do próximo pacote.
 *
 * Esta página é apenas informativa:
 * - NÃO renderiza formulário funcional;
 * - NÃO coleta nem envia nenhum dado;
 * - NÃO chama nenhuma RPC (nem a antiga, nem uma nova inventada);
 * - NÃO afirma que uma solicitação foi enviada ou está em análise;
 * - NÃO cria conta, empresa ou owner de forma alguma.
 *
 * A antiga rota /portal/cadastro redireciona para cá (ver src/App.tsx).
 */
export default function ParceirosCadastro() {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-lg px-4 pb-24 pt-14 text-center">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
        </p>
        <h1 className="mt-3 text-3xl sm:text-4xl">
          Cadastro de empresas em preparação
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-amarelo" />
        </h1>

        <div className="mt-8 rounded-3xl border-2 border-borda bg-white p-7">
          <p className="text-tinta/80">
            O novo cadastro de empresas parceiras está sendo preparado e
            ainda não está disponível nesta página.
          </p>
          <p className="mt-4 text-sm text-tinta/60">
            Quando estiver pronto, o cadastro vai pedir os dados da empresa e
            do responsável, incluir a análise administrativa da BDFlow e
            validar a autoridade de quem assina pela empresa antes de liberar
            o acesso ao Portal.
          </p>
        </div>

        <p className="mt-6 text-xs text-tinta/40">
          Nenhuma informação é coletada nesta página. Nenhuma solicitação foi
          enviada.
        </p>

        <div className="mt-8 flex flex-col items-center gap-3">
          <Link to="/oportunidades" className="btn-primary">
            Ver oportunidades comerciais
          </Link>
          <Link to="/" className="text-sm font-medium text-ciano hover:underline">
            ← Voltar ao início
          </Link>
        </div>
      </main>
    </>
  );
}
