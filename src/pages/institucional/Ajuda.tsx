import { Link } from "react-router-dom";
import type { ReactNode } from "react";
import {
  Abertura,
  PaginaInstitucional,
} from "../../components/institucional/Institucional";
import { REGIAO_ATIVA, TOTAL_UNIDADES_REFERENCIA } from "../../content/institucional";

/**
 * /ajuda — Central de ajuda pública inicial.
 *
 * Sem backend de chamados. Respostas curtas, coerentes com o produto atual,
 * com links para rotas reais. Usa <details>/<summary> nativos: acessíveis por
 * teclado e leitores de tela sem JavaScript próprio.
 */

type Pergunta = { pergunta: string; resposta: ReactNode };
type Categoria = { id: string; titulo: string; perguntas: Pergunta[] };

function L({ to, children }: { to: string; children: ReactNode }) {
  return (
    <Link
      to={to}
      className="font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
    >
      {children}
    </Link>
  );
}

const cidades = `${REGIAO_ATIVA.cidades.slice(0, -1).join(", ")} e ${
  REGIAO_ATIVA.cidades[REGIAO_ATIVA.cidades.length - 1]
}`;

const CATEGORIAS: Categoria[] = [
  {
    id: "empresas",
    titulo: "Empresas interessadas",
    perguntas: [
      {
        pergunta: "Como solicitar parceria?",
        resposta: (
          <>
            Envie a solicitação em <L to="/parceiros/cadastro">Quero ser parceiro</L> com os
            dados da empresa e do responsável, e aceite os documentos exigidos para análise.
          </>
        ),
      },
      {
        pergunta: "O cadastro libera o Portal imediatamente?",
        resposta: (
          <>
            Não. Primeiro a solicitação passa pela análise. O acesso ao Portal do Parceiro
            vem depois da aprovação e da ativação do vínculo comercial.
          </>
        ),
      },
      {
        pergunta: "Como acompanhar uma solicitação?",
        resposta: (
          <>
            Depois de confirmar o e-mail, use{" "}
            <L to="/parceiros/acesso">Acompanhar solicitação</L> para ver o status, responder
            correções e enviar documentos.
          </>
        ),
      },
    ],
  },
  {
    id: "oportunidades",
    titulo: "Oportunidades",
    perguntas: [
      {
        pergunta: "Como escolher minha localidade?",
        resposta: (
          <>
            Informe estado e cidade em <L to="/selecionar-localidade">Selecionar localidade</L>.
            O Site verifica se há uma região comercial ativa. Se não houver, você pode
            registrar interesse territorial, que não representa compra, reserva ou
            exclusividade.
          </>
        ),
      },
      {
        pergunta: "O que é uma oportunidade comercial?",
        resposta: (
          <>
            É a contratação integral de um nicho dentro de uma exclusividade comercial de uma
            região. Veja as disponíveis em <L to="/oportunidades">Oportunidades</L>.
          </>
        ),
      },
      {
        pergunta: "Como os nichos são organizados?",
        resposta: (
          <>
            Cada exclusividade reúne seis nichos, somando {TOTAL_UNIDADES_REFERENCIA} unidades
            na formação de referência: Supermercado (24) e Farmácia, Roupas femininas, Roupas
            masculinas, Calçados femininos e Calçados masculinos (12 cada). Cada nicho é
            contratado por inteiro, e cada CNPJ contrata um único nicho por exclusividade.
          </>
        ),
      },
    ],
  },
  {
    id: "parceiros",
    titulo: "Parceiros",
    perguntas: [
      {
        pergunta: "Onde entrar no Portal?",
        resposta: (
          <>
            Em <L to="/portal/login">Entrar</L>, no topo do site (no menu, em telas menores). O
            Portal é para parceiros aprovados.
          </>
        ),
      },
      {
        pergunta: "Onde acompanhar solicitações?",
        resposta: (
          <>
            A solicitação de parceria, antes da aprovação, é acompanhada em{" "}
            <L to="/parceiros/acesso">Acompanhar solicitação</L>. Depois da aprovação, as
            solicitações de validação de benefícios ficam no Portal do Parceiro.
          </>
        ),
      },
      {
        pergunta: "Onde ocorre a validação de benefícios?",
        resposta: (
          <>
            No estabelecimento da empresa parceira, pelo Portal do Parceiro: o divulgador
            apresenta o QR code do SmallFlags App, a empresa registra a solicitação pelo
            Portal e o divulgador confirma o uso no App. A divulgação em via pública é
            outra atividade e não passa por essa validação.
          </>
        ),
      },
    ],
  },
  {
    id: "smallflags",
    titulo: "SmallFlags",
    perguntas: [
      {
        pergunta: "Qual é a diferença entre Site e App?",
        resposta: (
          <>
            O Site cuida do lado comercial: oportunidades, exclusividade, parceria, contratos,
            pagamentos e o Portal do Parceiro. O SmallFlags App cuida da jornada operacional dos
            divulgadores e do uso dos benefícios. Saiba mais em{" "}
            <L to="/como-funciona">Como funciona</L>.
          </>
        ),
      },
      {
        pergunta: "Onde a operação está disponível?",
        resposta: (
          <>
            A região comercial ativa é a {REGIAO_ATIVA.nome} ({REGIAO_ATIVA.uf}): {cidades}.
            Outras regiões podem ser abertas em etapas futuras.
          </>
        ),
      },
    ],
  },
];

export default function Ajuda() {
  return (
    <PaginaInstitucional titulo="Ajuda">
      <Abertura
        rotulo="Ajuda"
        titulo="Central de ajuda"
        texto={<p>Respostas rápidas sobre parceria, oportunidades e o Portal do Parceiro.</p>}
      />

      <div className="mx-auto max-w-6xl px-4 pb-20">
        <div className="grid gap-10 lg:grid-cols-12 lg:gap-12">
          <nav aria-label="Categorias da ajuda" className="lg:col-span-3">
            <ul className="flex flex-wrap gap-2 lg:sticky lg:top-24 lg:block lg:space-y-1">
              {CATEGORIAS.map((c) => (
                <li key={c.id}>
                  <a
                    href={`#${c.id}`}
                    className="inline-block rounded-full border border-borda px-4 py-2 text-sm font-medium text-tinta/75 transition hover:border-tinta hover:text-tinta lg:rounded-xl lg:border-transparent lg:px-3"
                  >
                    {c.titulo}
                  </a>
                </li>
              ))}
            </ul>
          </nav>

          <div className="space-y-14 lg:col-span-9">
            {CATEGORIAS.map((c) => (
              <section key={c.id} id={c.id} aria-labelledby={`${c.id}-titulo`} className="scroll-mt-24">
                <h2 id={`${c.id}-titulo`} className="text-2xl sm:text-3xl">
                  {c.titulo}
                </h2>
                <div className="mt-5 border-t border-tinta/15">
                  {c.perguntas.map((p) => (
                    <details key={p.pergunta} className="group border-b border-tinta/15">
                      <summary className="flex min-h-[56px] cursor-pointer list-none items-center justify-between gap-4 py-4 text-left font-semibold text-tinta [&::-webkit-details-marker]:hidden">
                        <h3 className="text-base font-semibold sm:text-lg">{p.pergunta}</h3>
                        <span
                          aria-hidden
                          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-borda text-lg leading-none transition group-open:rotate-45 group-open:border-magenta group-open:text-magenta"
                        >
                          +
                        </span>
                      </summary>
                      <div className="max-w-2xl pb-6 text-sm leading-7 text-tinta/75 sm:text-base">
                        {p.resposta}
                      </div>
                    </details>
                  ))}
                </div>
              </section>
            ))}

            <p className="text-sm text-tinta/70">
              Não encontrou o que procurava? Veja a página de{" "}
              <L to="/contato">Contato</L>.
            </p>
          </div>
        </div>
      </div>
    </PaginaInstitucional>
  );
}
