import { Link } from "react-router-dom";
import { IconeWhatsApp } from "../../components/WhatsAppComercial";
import { WHATSAPP_COMERCIAL, WHATSAPP_COMERCIAL_URL } from "../../content/whatsapp";
import {
  Abertura,
  PaginaInstitucional,
  Secao,
} from "../../components/institucional/Institucional";

/** /contato — canais informados pelo operador em 12/11/2026; WhatsApp
 * comercial confirmado em 25/11/2026 (mesmo número e link do botão
 * flutuante). Instagram confirmado em 26/11/2026.
 * Sem horário/endereço inventados.
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
        intro={<p>Entre em contato por e-mail, telefone ou WhatsApp.</p>}
      >
        <div
          className="mb-4 flex flex-col gap-5 rounded-3xl border border-[#128C7E]/40 bg-[#25D366]/[0.08] p-6 sm:p-8 md:flex-row md:items-center md:justify-between"
          data-testid="contato-whatsapp"
        >
          <div>
            <h3 className="flex items-center gap-2 text-lg font-bold">
              <IconeWhatsApp className="h-6 w-6 text-[#128C7E]" />
              WhatsApp
            </h3>
            <p className="mt-3 text-base font-semibold text-tinta">
              {WHATSAPP_COMERCIAL.numeroNacional}
            </p>
            <p className="mt-2 max-w-xl text-sm leading-6 text-tinta/70">
              Entre em contato com nossa equipe para conhecer as oportunidades comerciais,
              esclarecer dúvidas e receber informações sobre as contratações.
            </p>
          </div>
          <a
            href={WHATSAPP_COMERCIAL_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="btn shrink-0 self-start border-2 border-[#128C7E] bg-[#25D366] text-noite hover:brightness-95 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-[#128C7E]/40 md:self-center"
          >
            <IconeWhatsApp className="h-5 w-5" />
            Conversar pelo WhatsApp
          </a>
        </div>
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
        intro={<p>Acompanhe a SmallFlags em nossos canais oficiais.</p>}
      >
        <ul className="grid gap-4 sm:grid-cols-2">
          <li className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
            <h3 className="flex items-center gap-2 text-xl font-bold">
              <svg aria-hidden="true" focusable="false" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-6 w-6 text-[#E1306C]">
                <rect x="3" y="3" width="18" height="18" rx="5" />
                <circle cx="12" cy="12" r="4" />
                <circle cx="17.5" cy="6.5" r="1" fill="currentColor" stroke="none" />
              </svg>
              Instagram
            </h3>
            <p className="mt-3 text-base font-semibold text-tinta">@smallflagsBR</p>
            <p className="mt-2 text-sm leading-6 text-tinta/65">
              Acompanhe nossas campanhas publicitárias, novidades e oportunidades comerciais.
            </p>
            <a
              href="https://www.instagram.com/smallflagsBR/"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-secondary mt-6"
            >
              Acessar Instagram
            </a>
          </li>
          <li className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8">
            <div className="flex items-start justify-between gap-3">
              <h3 className="text-xl font-bold">TikTok</h3>
              <span className="rounded-full bg-papel2 px-3 py-1 text-xs font-semibold text-tinta/60">
                Em breve
              </span>
            </div>
            <p className="mt-4 text-sm leading-6 text-tinta/65">
              Perfil oficial a confirmar.
            </p>
          </li>
        </ul>
        <p className="mt-5 text-sm leading-6 text-tinta/65">
          Para atendimento, utilize o WhatsApp, o e-mail e o telefone publicados nesta página.
        </p>
      </Secao>
    </PaginaInstitucional>
  );
}
