import {
  Abertura,
  Bloco,
  Chamada,
  PaginaInstitucional,
  Secao,
} from "../../components/institucional/Institucional";
import RelacaoSiteApp from "../../components/institucional/RelacaoSiteApp";
import { REGIAO_ATIVA } from "../../content/institucional";
import { Link } from "react-router-dom";

/**
 * /quem-somos — página institucional.
 *
 * Explica a SmallFlags sem afirmações corporativas não sustentadas: nada de
 * números de clientes, prêmios, funcionários ou "valores oficiais".
 * Distingue o Site (domínio comercial) do App SmallFlags (jornada operacional
 * do participante) sem expor detalhes internos de integração.
 */
export default function QuemSomos() {
  return (
    <PaginaInstitucional titulo="Quem somos">
      <Abertura
        rotulo="Quem somos"
        titulo="Empresas, tecnologia e operação conectadas em um único ecossistema."
        texto={
          <p>
            A SmallFlags organiza uma estrutura comercial para empresas parceiras e
            a conecta a um aplicativo dedicado à experiência dos participantes.
            Cada parte tem sua responsabilidade — e as duas trabalham juntas.
          </p>
        }
      />

      <Secao
        id="o-que-fazemos"
        titulo="O que a SmallFlags faz"
        intro={
          <p>
            Um modelo em que a relação comercial com as empresas e a jornada dos
            participantes são tratadas por ambientes próprios.
          </p>
        }
      >
        <p className="max-w-2xl text-lg leading-8 text-tinta/80">
          Empresas parceiras participam de oportunidades comerciais organizadas
          por região e por nicho, dentro de uma exclusividade comercial. Os
          participantes vivem a experiência SmallFlags pelo aplicativo, onde também
          acessam os benefícios oferecidos pelas empresas parceiras.
        </p>
      </Secao>

      <Secao
        id="dois-ambientes"
        fundo="papel2"
        titulo="Dois ambientes conectados"
        intro={
          <p>
            O Site não administra a jornada dos participantes, e o App não
            administra contratos com empresas.
          </p>
        }
      >
        <RelacaoSiteApp />
      </Secao>

      <Secao
        id="inicio-comercial"
        titulo="Onde começamos"
        intro={
          <p>
            A primeira região comercial ativa é a {REGIAO_ATIVA.nome} (
            {REGIAO_ATIVA.uf}).
          </p>
        }
      >
        <ul className="flex flex-wrap gap-x-6 gap-y-3" aria-label={`Cidades da região ${REGIAO_ATIVA.nome}`}>
          {REGIAO_ATIVA.cidades.map((c) => (
            <li key={c} className="display text-3xl text-tinta sm:text-4xl">
              {c}
            </li>
          ))}
        </ul>
        <p className="mt-8 max-w-2xl text-sm leading-6 text-tinta/70">
          A expansão para outras regiões pode acontecer em etapas futuras. Se a
          sua cidade ainda não tem uma região ativa, é possível{" "}
          <Link to="/selecionar-localidade" className="font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4">
            registrar interesse territorial
          </Link>{" "}
          — sem compra, reserva ou exclusividade.
        </p>
      </Secao>

      <Secao
        id="principios"
        fundo="papel2"
        titulo="Como trabalhamos"
        intro={<p>Princípios que orientam o produto.</p>}
      >
        <div className="grid gap-8 sm:grid-cols-2">
          <Bloco titulo="Responsabilidades claras" destaque="magenta">
            O que é comercial fica no Site; o que é operacional fica no App.
            Cada parte sabe o que decide.
          </Bloco>
          <Bloco titulo="Processos rastreáveis" destaque="ciano">
            Solicitações de parceria, contratações e validações seguem etapas
            registradas, com status que a empresa pode acompanhar.
          </Bloco>
          <Bloco titulo="Expansão controlada" destaque="amarelo">
            Novas regiões são abertas por etapas, sem prometer cobertura antes
            de a operação estar pronta.
          </Bloco>
          <Bloco titulo="Tecnologia a serviço da relação">
            A tecnologia existe para aproximar participantes e empresas
            parceiras, com regras claras para os dois lados.
          </Bloco>
        </div>
      </Secao>

      <Chamada
        titulo="Conheça as oportunidades da sua região."
        texto="Veja as oportunidades comerciais disponíveis ou solicite a parceria da sua empresa."
        principal={{ rotulo: "Ver oportunidades", to: "/oportunidades" }}
        secundaria={{ rotulo: "Quero ser parceiro", to: "/parceiros/cadastro" }}
      />
    </PaginaInstitucional>
  );
}
