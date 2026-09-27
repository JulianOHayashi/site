import { Link } from "react-router-dom";
import {
  Abertura,
  Chamada,
  PaginaInstitucional,
} from "../../components/institucional/Institucional";
import FormacaoReferencia from "../../components/institucional/FormacaoReferencia";
import { REGIAO_ATIVA } from "../../content/institucional";
import type { ReactNode } from "react";

/**
 * /como-funciona — o modelo BDFlow em cinco etapas.
 *
 * A numeração é legítima: é uma sequência real (localidade → oportunidade →
 * parceria → exclusividade → Site e App). Não descreve mecânicas operacionais
 * do App nem promete aprovação imediata.
 */

type Etapa = { titulo: string; conteudo: ReactNode; extra?: ReactNode };

/** Link autônomo (fora de frase): precisa de alvo de toque de 44px. */
const linkTexto =
  "inline-flex min-h-[44px] items-center font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4";

const ETAPAS: Etapa[] = [
  {
    titulo: "Localidade",
    conteudo: (
      <>
        <p>
          A empresa informa estado e cidade. O Site verifica se existe uma
          região comercial ativa para essa localidade.
        </p>
        <p className="mt-3">
          Hoje a região ativa é a {REGIAO_ATIVA.nome} ({REGIAO_ATIVA.uf}):{" "}
          {REGIAO_ATIVA.cidades.slice(0, -1).join(", ")} e{" "}
          {REGIAO_ATIVA.cidades[REGIAO_ATIVA.cidades.length - 1]}. Fora dela, é
          possível registrar interesse territorial, sem compra, reserva ou
          exclusividade.
        </p>
      </>
    ),
    extra: (
      <Link to="/selecionar-localidade" className={linkTexto}>
        Selecionar localidade
      </Link>
    ),
  },
  {
    titulo: "Oportunidade comercial",
    conteudo: (
      <p>
        As oportunidades comerciais são organizadas por região e por nicho.
        A página de oportunidades mostra o status da exclusividade, o progresso
        da formação comercial e, quando definido, o início previsto da operação.
      </p>
    ),
    extra: (
      <Link to="/oportunidades" className={linkTexto}>
        Ver oportunidades
      </Link>
    ),
  },
  {
    titulo: "Parceria",
    conteudo: (
      <p>
        A empresa interessada envia a solicitação de parceria e acompanha a
        análise. O cadastro não libera o Portal do Parceiro imediatamente: o
        acesso vem depois da aprovação e da ativação do vínculo comercial.
      </p>
    ),
    extra: (
      <Link to="/parceiros" className={linkTexto}>
        Como funciona a parceria
      </Link>
    ),
  },
  {
    titulo: "Exclusividade comercial",
    conteudo: (
      <p>
        Uma exclusividade comercial reúne seis nichos. Cada nicho é contratado
        integralmente por uma empresa — as unidades de um nicho não são
        vendidas separadamente, e cada CNPJ contrata um único nicho por
        exclusividade.
      </p>
    ),
    extra: (
      <div className="mt-2 rounded-3xl bg-tinta p-6 sm:p-8">
        <p className="mb-4 text-sm font-bold text-amarelo">Formação comercial de referência</p>
        <FormacaoReferencia tom="escuro" />
      </div>
    ),
  },
  {
    titulo: "Site e App",
    conteudo: (
      <p>
        A gestão comercial continua no Site e no Portal do Parceiro. A jornada
        operacional dos participantes é administrada pelo BDFlow App, onde eles
        também acessam os benefícios oferecidos pelas empresas parceiras.
      </p>
    ),
  },
];

export default function ComoFunciona() {
  return (
    <PaginaInstitucional titulo="Como funciona">
      <Abertura
        rotulo="Como funciona"
        titulo="Entenda como a BDFlow funciona."
        texto={
          <p>
            Da localidade da sua empresa até a exclusividade comercial, em cinco
            etapas.
          </p>
        }
      />

      <section aria-labelledby="etapas-titulo" className="mx-auto max-w-6xl px-4 pb-10">
        <h2 id="etapas-titulo" className="sr-only">
          Etapas
        </h2>
        <ol className="border-t border-tinta/15">
          {ETAPAS.map((e, i) => (
            <li
              key={e.titulo}
              className="grid gap-4 border-b border-tinta/15 py-10 sm:py-14 lg:grid-cols-12 lg:gap-12"
            >
              <div className="flex items-baseline gap-4 lg:col-span-4 lg:block">
                <span
                  aria-hidden
                  className="display text-5xl leading-none text-magenta sm:text-7xl"
                >
                  {i + 1}
                </span>
                <h3 className="text-2xl leading-tight sm:text-3xl lg:mt-4">
                  <span className="sr-only">Etapa {i + 1}: </span>
                  {e.titulo}
                </h3>
              </div>
              <div className="max-w-2xl text-base leading-7 text-tinta/75 lg:col-span-8">
                {e.conteudo}
                {e.extra && <div className="mt-5">{e.extra}</div>}
              </div>
            </li>
          ))}
        </ol>
      </section>

      <Chamada
        titulo="Pronto para ver as oportunidades?"
        texto="Selecione sua localidade e veja a exclusividade comercial da sua região."
        principal={{ rotulo: "Ver oportunidades", to: "/oportunidades" }}
        secundaria={{ rotulo: "Quero ser parceiro", to: "/parceiros/cadastro" }}
      />
    </PaginaInstitucional>
  );
}
