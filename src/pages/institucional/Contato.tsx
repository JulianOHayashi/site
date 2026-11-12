import { Link } from "react-router-dom";
import {
  Abertura,
  PaginaInstitucional,
  Secao,
} from "../../components/institucional/Institucional";

/** /contato — canais informados pelo operador em 12/11/2026.
 * Telefone não é presumido como WhatsApp, sem horário/endereço inventados.
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
        titulo="Entre em contato com a SmallFlags."
        texto={
          <p>
            Para atendimento na Grande Vitória, utilize os canais abaixo.
            Para cadastro e acompanhamento de parceria, use também os acessos disponíveis nesta página.
          </p>
        }
      />

      <section aria-labelledby="caminhos-titulo" className="mx-auto max-w-6xl px-4 pb-6">
        <h2 id="caminhos-titulo" className="sr-only">
          Escolha o seu caminho
        </h2>
        <ul className="grid gap-px overflow-hidden rounded-3xl border border-borda bg-borda md:grid-cols-2">
          {CAMINHOS.map((c) => (
            <li key={c.to} className="flex flex-col bg-superficie p-7 sm:p-8">
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
        titulo="Canais de atendimento — Grande Vitória"
        intro={<p>Entre em contato por e-mail ou telefone.</p>}
      >
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
            <h3 className="text-lg font-bold">E-mail</h3>
            <a
              href="mailto:grandevitoria@smallflags.com.br"
              className="mt-3 inline-block break-all text-base font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
            >
              grandevitoria@smallflags.com.br
            </a>
            <p className="mt-2 text-sm text-tinta/65">
              Canal de contato da SmallFlags na Grande Vitória.
            </p>
          </div>
          <div className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
            <h3 className="text-lg font-bold">Telefone</h3>
            <a
              href="tel:+5527998803900"
              className="mt-3 inline-block text-base font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
            >
              (27) 99880-3900
            </a>
            <p className="mt-2 text-sm text-tinta/65">
              Toque no número para iniciar uma chamada telefônica.
            </p>
          </div>
        </div>
        <p className="mt-5 text-sm leading-6 text-tinta/70">
          Para dúvidas frequentes, consulte a{" "}
          <Link
            to="/ajuda"
            className="font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
          >
            Central de ajuda
          </Link>.
        </p>
      </Secao>

      <Secao
        id="redes-sociais"
        titulo="Redes sociais"
        intro={
          <p>
            Reservamos este espaço para nossos canais oficiais. Os links serão
            disponibilizados quando forem confirmados pela SmallFlags.
          </p>
        }
      >
        <ul className="grid gap-4 sm:grid-cols-3">
          {[
            { nome: "Instagram", descricao: "Perfil oficial a confirmar." },
            { nome: "TikTok", descricao: "Perfil oficial a confirmar." },
            { nome: "WhatsApp", descricao: "Número de atendimento a confirmar." },
          ].map((rede) => (
            <li
              key={rede.nome}
              className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8"
            >
              <div className="flex items-start justify-between gap-3">
                <h3 className="text-xl font-bold">{rede.nome}</h3>
                <span className="rounded-full bg-papel2 px-3 py-1 text-xs font-semibold text-tinta/60">
                  Em breve
                </span>
              </div>
              <p className="mt-4 text-sm leading-6 text-tinta/65">
                {rede.descricao}
              </p>
            </li>
          ))}
        </ul>
        <p className="mt-5 text-sm leading-6 text-tinta/65">
          Enquanto isso, utilize o e-mail e o telefone publicados nesta página.
          O telefone de contato não está identificado como canal de WhatsApp.
        </p>
      </Secao>
    </PaginaInstitucional>
  );
}
