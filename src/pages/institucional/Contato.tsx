import { Link } from "react-router-dom";
import {
  Abertura,
  PaginaInstitucional,
  Secao,
} from "../../components/institucional/Institucional";

/**
 * /contato — página institucional de contato.
 *
 * Não existem canais de contato verificados no repositório; por isso esta
 * página NÃO publica telefone, WhatsApp, e-mail, endereço, horário ou redes
 * sociais. Ela direciona cada perfil para a jornada que já existe e não
 * coleta dados.
 */

const CAMINHOS = [
  {
    perfil: "Empresa interessada em ser parceira",
    texto: "Conheça a parceria e envie a solicitação da sua empresa.",
    rotulo: "Seja parceiro",
    to: "/parceiros",
  },
  {
    perfil: "Já enviei uma solicitação",
    texto: "Acompanhe a análise, responda correções e envie documentos.",
    rotulo: "Acompanhar solicitação",
    to: "/parceiros/acesso",
  },
  {
    perfil: "Sou parceiro aprovado",
    texto: "Entre no Portal do Parceiro para a operação do dia a dia.",
    rotulo: "Entrar no Portal",
    to: "/portal/login",
  },
  {
    perfil: "Quero conhecer as oportunidades",
    texto: "Veja as oportunidades comerciais da sua região.",
    rotulo: "Ver oportunidades",
    to: "/oportunidades",
  },
];

export default function Contato() {
  return (
    <PaginaInstitucional titulo="Contato">
      <Abertura
        rotulo="Contato"
        titulo="Fale com a SmallFlags pelo caminho certo."
        texto={
          <p>
            Para a maioria dos assuntos, o jeito mais rápido é seguir a jornada
            correspondente abaixo.
          </p>
        }
      />

      <section aria-labelledby="caminhos-titulo" className="mx-auto max-w-6xl px-4 pb-6">
        <h2 id="caminhos-titulo" className="sr-only">
          Escolha o seu caminho
        </h2>
        <ul className="grid gap-px overflow-hidden rounded-3xl border border-borda bg-borda md:grid-cols-2">
          {CAMINHOS.map((c) => (
            <li key={c.to} className="flex flex-col bg-white p-7 sm:p-8">
              <h3 className="text-xl leading-snug">{c.perfil}</h3>
              <p className="mt-2 flex-1 text-sm leading-6 text-tinta/70">{c.texto}</p>
              <Link to={c.to} className="btn-secondary mt-6 self-start">
                {c.rotulo}
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <Secao
        id="canais"
        titulo="Canais de atendimento"
        intro={<p>Telefone, e-mail e outros canais oficiais.</p>}
      >
        <div className="rounded-3xl border border-dashed border-tinta/25 p-8">
          <p className="text-lg font-semibold text-tinta">
            Os canais oficiais de atendimento serão publicados nesta página.
          </p>
          <p className="mt-3 max-w-xl text-sm leading-6 text-tinta/70">
            Enquanto isso, as dúvidas mais comuns sobre parceria, oportunidades e
            o Portal do Parceiro estão respondidas na{" "}
            <Link
              to="/ajuda"
              className="font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
            >
              Central de ajuda
            </Link>
            .
          </p>
        </div>
      </Secao>
    </PaginaInstitucional>
  );
}
