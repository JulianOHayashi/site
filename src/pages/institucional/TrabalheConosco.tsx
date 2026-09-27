import { Link } from "react-router-dom";
import {
  Abertura,
  PaginaInstitucional,
  Secao,
} from "../../components/institucional/Institucional";

/**
 * /trabalhe-conosco — página institucional de recrutamento.
 *
 * NÃO coleta dados: sem formulário, upload de currículo, tabela ou e-mail.
 * As áreas são áreas de interesse, não vagas abertas.
 *
 * Para publicar vagas no futuro, preencha VAGAS_ABERTAS: a seção passa a
 * listar os cartões sem reconstruir o layout.
 */

type Vaga = {
  titulo: string;
  area: string;
  local: string;
  modalidade: string;
  resumo: string;
  /** Rota interna ou URL externa do processo seletivo. */
  destino: string;
};

const VAGAS_ABERTAS: Vaga[] = [];

const AREAS = [
  {
    nome: "Tecnologia",
    texto: "Site, Portal do Parceiro, aplicativo e as integrações que conectam os dois ambientes.",
  },
  {
    nome: "Operações",
    texto: "Organização do dia a dia que faz a BDFlow funcionar nas regiões ativas.",
  },
  {
    nome: "Comercial",
    texto: "Relacionamento com empresas e formação das exclusividades comerciais.",
  },
  {
    nome: "Atendimento",
    texto: "Suporte a empresas parceiras e participantes ao longo da jornada.",
  },
  {
    nome: "Administrativo",
    texto: "Processos, documentação e rotinas que sustentam a operação.",
  },
];

function CartaoVaga({ vaga }: { vaga: Vaga }) {
  const externo = /^https?:\/\//.test(vaga.destino);
  return (
    <li className="rounded-3xl border border-borda bg-white p-6">
      <p className="text-sm font-bold text-tinta/70">{vaga.area}</p>
      <h3 className="mt-1 text-xl">{vaga.titulo}</h3>
      <p className="mt-1 text-sm text-tinta/65">
        {vaga.local}, {vaga.modalidade}
      </p>
      <p className="mt-3 text-sm leading-6 text-tinta/75">{vaga.resumo}</p>
      {externo ? (
        <a href={vaga.destino} className="btn-secondary mt-5" rel="noopener noreferrer" target="_blank">
          Ver processo seletivo
        </a>
      ) : (
        <Link to={vaga.destino} className="btn-secondary mt-5">
          Ver processo seletivo
        </Link>
      )}
    </li>
  );
}

export default function TrabalheConosco() {
  return (
    <PaginaInstitucional titulo="Trabalhe conosco">
      <Abertura
        rotulo="Trabalhe conosco"
        titulo="Construa a BDFlow com a gente."
        texto={
          <p>
            A BDFlow reúne tecnologia, operação comercial e relacionamento com
            empresas parceiras. Quando houver processos seletivos abertos, eles
            serão publicados nesta página.
          </p>
        }
      />

      <Secao
        id="areas"
        titulo="Áreas de atuação"
        intro={
          <p>
            As frentes em que a BDFlow trabalha. Não indicam vagas abertas.
          </p>
        }
      >
        <ul className="divide-y divide-tinta/10 border-y border-tinta/10">
          {AREAS.map((a) => (
            <li key={a.nome} className="grid gap-1 py-5 sm:grid-cols-3 sm:gap-6">
              <h3 className="text-xl">{a.nome}</h3>
              <p className="text-sm leading-6 text-tinta/70 sm:col-span-2">{a.texto}</p>
            </li>
          ))}
        </ul>
      </Secao>

      <Secao id="processos" fundo="papel2" titulo="Processos seletivos">
        {VAGAS_ABERTAS.length > 0 ? (
          <ul className="grid gap-4 md:grid-cols-2">
            {VAGAS_ABERTAS.map((v) => (
              <CartaoVaga key={`${v.area}-${v.titulo}`} vaga={v} />
            ))}
          </ul>
        ) : (
          <div className="rounded-3xl border border-dashed border-tinta/25 p-8">
            <p className="text-xl font-semibold text-tinta">
              Não há processos seletivos abertos no momento.
            </p>
            <p className="mt-3 max-w-xl text-sm leading-6 text-tinta/70">
              As oportunidades serão publicadas aqui quando houver processos
              seletivos abertos, com a descrição da função e a forma de
              participação. Esta página não recebe currículos.
            </p>
          </div>
        )}
        <p className="mt-8 text-sm text-tinta/70">
          Quer entender melhor o que fazemos?{" "}
          <Link
            to="/quem-somos"
            className="font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
          >
            Conheça a BDFlow
          </Link>
        </p>
      </Secao>
    </PaginaInstitucional>
  );
}
