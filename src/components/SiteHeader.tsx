import { useEffect, useId, useRef, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { obterTerritorio } from "../lib/commercialTerritory";

/**
 * Navegação pública BDFlow.
 *
 * Arquitetura de entrada:
 * - Para empresas (/parceiros): conteúdo público + início da candidatura.
 * - Acompanhar solicitação: acesso provisório, exposto dentro da jornada de parceria.
 * - Entrar: único acesso principal visível para parceiros aprovados -> Portal.
 * - Quero ser parceiro: CTA comercial principal.
 *
 * Páginas institucionais ficam agrupadas no disclosure "Institucional" para
 * não lotar o header no desktop. O disclosure é um botão com aria-expanded
 * controlando uma lista de links (padrão de navegação, não role="menu"):
 * Tab percorre os links, Esc fecha e devolve o foco ao botão, clique fora ou
 * foco saindo do grupo também fecham. Nada depende de hover.
 */
const LINKS_CENTRAIS = [
  { rotulo: "Como funciona", to: "/como-funciona" },
  { rotulo: "Para empresas", to: "/parceiros" },
  { rotulo: "Oportunidades", to: "/oportunidades" },
];

const LINKS_INSTITUCIONAIS = [
  { rotulo: "Quem somos", to: "/quem-somos" },
  { rotulo: "Trabalhe conosco", to: "/trabalhe-conosco" },
  { rotulo: "Ajuda", to: "/ajuda" },
  { rotulo: "Contato", to: "/contato" },
];

function ehAtual(caminho: string, to: string) {
  return caminho === to || caminho.startsWith(`${to}/`);
}

export default function SiteHeader() {
  const location = useLocation();
  const [rolou, setRolou] = useState(false);
  const [menuAberto, setMenuAberto] = useState(false);
  const [institucionalAberto, setInstitucionalAberto] = useState(false);

  const grupoRef = useRef<HTMLDivElement>(null);
  const botaoGrupoRef = useRef<HTMLButtonElement>(null);
  const botaoMenuRef = useRef<HTMLButtonElement>(null);
  const idGrupo = useId();
  const idMenu = useId();

  const caminho = location.pathname;
  const destinoNext = encodeURIComponent(caminho + location.search);
  const ehComercial =
    caminho === "/" ||
    caminho.startsWith("/oportunidades") ||
    caminho.startsWith("/selecionar-localidade");
  const grupoAtivo = LINKS_INSTITUCIONAIS.some((l) => ehAtual(caminho, l.to));

  const territorio = obterTerritorio();
  const temLocalidadeComercial =
    !!territorio &&
    territorio.regionStatus === "active" &&
    !!territorio.regionName;
  const rotuloLocalidade = temLocalidadeComercial
    ? `${territorio!.regionName} · ${territorio!.uf}`
    : "Selecionar localidade";

  useEffect(() => {
    const aoRolar = () => setRolou(window.scrollY > 8);
    aoRolar();
    window.addEventListener("scroll", aoRolar, { passive: true });
    return () => window.removeEventListener("scroll", aoRolar);
  }, []);

  useEffect(() => {
    setMenuAberto(false);
    setInstitucionalAberto(false);
  }, [location.pathname, location.hash]);

  // Clique fora fecha o grupo institucional.
  useEffect(() => {
    if (!institucionalAberto) return;
    const aoPressionar = (e: MouseEvent) => {
      if (grupoRef.current && !grupoRef.current.contains(e.target as Node)) {
        setInstitucionalAberto(false);
      }
    };
    document.addEventListener("mousedown", aoPressionar);
    return () => document.removeEventListener("mousedown", aoPressionar);
  }, [institucionalAberto]);

  // Esc fecha o que estiver aberto e devolve o foco ao controle de origem.
  useEffect(() => {
    if (!institucionalAberto && !menuAberto) return;
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      if (institucionalAberto) {
        setInstitucionalAberto(false);
        botaoGrupoRef.current?.focus();
      } else if (menuAberto) {
        setMenuAberto(false);
        botaoMenuRef.current?.focus();
      }
    };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, [institucionalAberto, menuAberto]);

  const classeLinkDesktop = (ativo: boolean) =>
    `whitespace-nowrap rounded-full px-4 py-2 text-sm font-medium transition hover:bg-papel2 hover:text-tinta ${
      ativo ? "bg-papel2 text-tinta" : "text-tinta/70"
    }`;

  return (
    <header
      className={`sticky top-0 z-50 border-b bg-papel/90 backdrop-blur-md transition-shadow ${
        rolou
          ? "border-borda shadow-[0_4px_24px_rgba(23,18,31,0.08)]"
          : "border-transparent"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3.5">
        <Link to="/" className="display inline-flex min-h-[44px] items-center text-xl" aria-label="BDFlow — início">
          BD<span className="text-magenta">Flow</span>
        </Link>

        <nav className="hidden items-center gap-1 xl:flex" aria-label="Principal">
          {LINKS_CENTRAIS.map((l) => {
            const ativo = ehAtual(caminho, l.to);
            return (
              <Link
                key={l.to}
                to={l.to}
                aria-current={ativo ? "page" : undefined}
                className={classeLinkDesktop(ativo)}
              >
                {l.rotulo}
              </Link>
            );
          })}

          <div
            ref={grupoRef}
            className="relative"
            onBlur={(e) => {
              const proximo = e.relatedTarget as Node | null;
              if (proximo && !e.currentTarget.contains(proximo)) {
                setInstitucionalAberto(false);
              }
            }}
          >
            <button
              ref={botaoGrupoRef}
              type="button"
              aria-expanded={institucionalAberto}
              aria-controls={idGrupo}
              onClick={() => setInstitucionalAberto((v) => !v)}
              className={`flex items-center gap-1.5 ${classeLinkDesktop(grupoAtivo || institucionalAberto)}`}
            >
              Institucional
              <svg
                aria-hidden
                viewBox="0 0 12 12"
                className={`h-3 w-3 transition-transform ${institucionalAberto ? "rotate-180" : ""}`}
              >
                <path d="M2 4.5 6 8.5 10 4.5" fill="none" stroke="currentColor" strokeWidth="1.6" />
              </svg>
            </button>

            {institucionalAberto && (
              <ul
                id={idGrupo}
                className="absolute left-0 top-full mt-2 w-56 rounded-2xl border border-borda bg-white p-2 shadow-[0_12px_32px_rgba(23,18,31,0.12)]"
              >
                {LINKS_INSTITUCIONAIS.map((l) => {
                  const ativo = ehAtual(caminho, l.to);
                  return (
                    <li key={l.to}>
                      <Link
                        to={l.to}
                        aria-current={ativo ? "page" : undefined}
                        className={`block rounded-xl px-4 py-2.5 text-sm font-medium transition hover:bg-papel2 ${
                          ativo ? "bg-papel2 text-tinta" : "text-tinta/75"
                        }`}
                      >
                        {l.rotulo}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </nav>

        <div className="hidden items-center gap-2 xl:flex">
          {ehComercial && (
            <Link
              to={`/selecionar-localidade?next=${destinoNext}`}
              aria-label={
                temLocalidadeComercial
                  ? `Localidade comercial: ${rotuloLocalidade}. Alterar localidade.`
                  : "Selecionar localidade comercial"
              }
              className="flex items-center gap-1.5 whitespace-nowrap rounded-full border border-borda px-3 py-1.5 text-xs font-semibold text-tinta/70 transition hover:border-magenta hover:text-magenta"
            >
              <span aria-hidden>⌖</span>
              {rotuloLocalidade}
              {temLocalidadeComercial && <span className="hidden xl:inline">· Alterar</span>}
            </Link>
          )}

          <Link
            to="/portal/login"
            className="whitespace-nowrap rounded-full px-4 py-2 text-sm font-semibold text-tinta/80 transition hover:bg-papel2 hover:text-tinta"
          >
            Entrar
          </Link>

          <Link
            to="/parceiros/cadastro"
            className="whitespace-nowrap rounded-full bg-tinta px-5 py-2 text-sm font-bold text-white transition hover:bg-magenta"
          >
            Quero ser parceiro
          </Link>
        </div>

        <button
          ref={botaoMenuRef}
          type="button"
          onClick={() => setMenuAberto((v) => !v)}
          aria-expanded={menuAberto}
          aria-controls={idMenu}
          aria-label={menuAberto ? "Fechar menu" : "Abrir menu"}
          className="flex h-11 w-11 items-center justify-center rounded-xl border border-borda xl:hidden"
        >
          <div className="space-y-1.5">
            <span
              className={`block h-0.5 w-5 bg-tinta transition ${
                menuAberto ? "translate-y-2 rotate-45" : ""
              }`}
            />
            <span
              className={`block h-0.5 w-5 bg-tinta transition ${
                menuAberto ? "opacity-0" : ""
              }`}
            />
            <span
              className={`block h-0.5 w-5 bg-tinta transition ${
                menuAberto ? "-translate-y-2 -rotate-45" : ""
              }`}
            />
          </div>
        </button>
      </div>

      {menuAberto && (
        <div
          id={idMenu}
          className="max-h-[calc(100dvh-4.5rem)] overflow-y-auto border-t border-borda bg-papel px-4 pb-6 pt-3 xl:hidden"
        >
          <nav aria-label="Menu">
            <ul className="space-y-1">
              {LINKS_CENTRAIS.map((l) => (
                <li key={l.to}>
                  <Link
                    to={l.to}
                    aria-current={ehAtual(caminho, l.to) ? "page" : undefined}
                    className="block rounded-xl px-4 py-3 font-medium text-tinta/80 transition hover:bg-papel2"
                  >
                    {l.rotulo}
                  </Link>
                </li>
              ))}
            </ul>

            <p className="mt-4 px-4 text-xs font-bold uppercase tracking-[0.2em] text-tinta/60">
              Institucional
            </p>
            <ul className="mt-1 grid grid-cols-2 gap-1">
              {LINKS_INSTITUCIONAIS.map((l) => (
                <li key={l.to}>
                  <Link
                    to={l.to}
                    aria-current={ehAtual(caminho, l.to) ? "page" : undefined}
                    className="block rounded-xl px-4 py-3 text-sm font-medium text-tinta/80 transition hover:bg-papel2"
                  >
                    {l.rotulo}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>

          {ehComercial && (
            <Link
              to={`/selecionar-localidade?next=${destinoNext}`}
              className="mt-4 block rounded-xl border border-borda px-4 py-3 text-center text-sm font-semibold text-tinta/70"
            >
              <span aria-hidden>⌖</span>{" "}
              {temLocalidadeComercial
                ? `${rotuloLocalidade} — alterar localidade`
                : "Selecionar localidade"}
            </Link>
          )}

          <div className="mt-4 grid gap-2">
            <Link
              to="/portal/login"
              className="block rounded-xl border border-borda py-3 text-center font-semibold text-tinta"
            >
              Entrar
            </Link>
            <Link
              to="/parceiros/cadastro"
              className="block rounded-xl bg-tinta py-3 text-center font-bold text-white transition hover:bg-magenta"
            >
              Quero ser parceiro
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}
