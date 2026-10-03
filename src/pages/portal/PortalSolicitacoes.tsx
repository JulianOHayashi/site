import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";

/**
 * /portal/solicitacoes — histórico de usos de benefício.
 *
 * POR QUE NÃO HÁ LISTA AQUI.
 *
 * O histórico de uso vive no Supabase do APP, que é a autoridade operacional.
 * O navegador do parceiro não lê tabelas do App, por desenho — e não existe
 * contrato servidor a servidor de leitura desse histórico. O gateway assinado
 * expõe quatro rotas, todas de registro e consulta de UMA solicitação em
 * andamento; nenhuma devolve histórico da empresa.
 *
 * O texto anterior dizia "Nenhuma solicitação encontrada", o que afirma um
 * fato falso: não é que a empresa não tenha solicitações, é que o Portal não
 * tem como lê-las. Um estado vazio inventado é pior que a ausência admitida.
 *
 * Quando o App publicar um contrato de histórico, esta página passa a listar.
 */
export default function PortalSolicitacoes() {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Solicitações" />

        <section
          aria-labelledby="indisponivel-titulo"
          className="mt-10 rounded-3xl border border-borda bg-white p-8 sm:p-12"
        >
          <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
            Histórico indisponível no Portal
          </p>
          <h2 id="indisponivel-titulo" className="mt-3 text-2xl font-bold sm:text-3xl">
            O Portal ainda não consulta o histórico de usos.
          </h2>
          <p className="mt-4 max-w-2xl leading-7 text-tinta/75">
            O registro de cada uso de benefício fica no aplicativo, que é onde o
            participante confirma ou recusa. O Portal registra a solicitação e
            acompanha o resultado dela na hora, mas ainda não lê o histórico da
            empresa. Esta página não mostra uma lista vazia porque isso daria a
            entender que não houve nenhum uso.
          </p>

          <div className="mt-8 border-t border-tinta/15 pt-6">
            <h3 className="text-lg font-bold">Enquanto isso</h3>
            <ul className="mt-3 space-y-2 leading-7 text-tinta/75">
              <li className="flex gap-2.5">
                <span aria-hidden className="text-tinta/35">
                  ·
                </span>
                Para registrar um novo uso, abra a validação de benefício: o
                resultado de cada solicitação aparece na própria tela, em tempo
                real, até a confirmação ou recusa do participante.
              </li>
              <li className="flex gap-2.5">
                <span aria-hidden className="text-tinta/35">
                  ·
                </span>
                Para conferir usos anteriores, fale com a SmallFlags pelos canais
                da sua empresa parceira.
              </li>
            </ul>
          </div>

          <div className="mt-8 flex flex-wrap gap-3">
            <Link to="/portal/validar" className="btn-primary">
              Validar benefício
            </Link>
            <Link to="/portal/dashboard" className="btn-secondary">
              Voltar ao painel
            </Link>
          </div>
        </section>
      </main>
    </>
  );
}
