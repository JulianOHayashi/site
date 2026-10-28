import { useEffect, useId, useRef, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { obterTerritorio } from "../lib/commercialTerritory";
import { supabase } from "../lib/supabase";
import Marca from "./marca/Marca";

/**
 * Navegação pública SmallFlags.
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
  const navigate = useNavigate();
  const [rolou, setRolou] = useState(false);
  const [menuAberto, setMenuAberto] = useState(false);
  const [institucionalAberto, setInstitucionalAberto] = useState(false);
  const [autenticado, setAutenticado] = useState(false);
  const [saindo, setSaindo] = useState(false);

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
    if (!supabase?.auth) {
      setAutenticado(false);
      return;
    }

    let ativo = true;

    void supabase.auth.getSession().then(({ data }) => {
      if (ativo) setAutenticado(Boolean(data.session));
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_evento, sessao) => {
      if (ativo) setAutenticado(Boolean(sessao));
    });

    return () => {
      ativo = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  const sair = async () => {
    if (!supabase?.auth || saindo) return;
    setSaindo(true);
    const { error } = await supabase.auth.signOut({ scope: "local" });
    setSaindo(false);
    if (error) return;
    setAutenticado(false);
    navigate("/portal/login", { replace: true });
  };

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
    `relative whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-medium transition hover:bg-superficie2 hover:text-tinta ${
      ativo ? "bg-superficie2 text-tinta" : "text-tinta/70"
    }`;

  return (
    <header
      className={`sticky top-0 z-50 border-b backdrop-blur-xl transition-colors duration-300 ${
        rolou ? "border-borda bg-papel/85" : "border-transparent bg-papel/60"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6">
        <Link
          to="/"
          className="inline-flex min-h-[44px] items-center rounded-lg"
          aria-label="SmallFlags — início"
        >
          <Marca tamanho="md" />
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
                className="absolute left-0 top-full mt-2 w-56 rounded-2xl border border-borda bg-superficie p-1.5 shadow-painel"
              >
                {LINKS_INSTITUCIONAIS.map((l) => {
                  const ativo = ehAtual(caminho, l.to);
                  return (
                    <li key={l.to}>
                      <Link
                        to={l.to}
                        aria-current={ativo ? "page" : undefined}
                        className={`block rounded-xl px-4 py-2.5 text-sm font-medium transition hover:bg-superficie2 hover:text-tinta ${
                          ativo ? "bg-superficie2 text-tinta" : "text-tinta/75"
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
              className="flex min-h-[36px] items-center gap-2 whitespace-nowrap rounded-full border border-borda bg-superficie/60 px-3 py-1.5 text-xs font-semibold text-tinta/75 transition hover:border-borda-forte hover:text-tinta"
            >
              {temLocalidadeComercial ? (
                <span aria-hidden className="ponto-vivo h-1.5 w-1.5" />
              ) : (
                <span aria-hidden>⌖</span>
              )}
              {rotuloLocalidade}
              {temLocalidadeComercial && <span className="hidden xl:inline">· Alterar</span>}
            </Link>
          )}

          {autenticado ? (
            <>
              <Link
                to="/portal/dashboard"
                className="whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-semibold text-tinta/80 transition hover:bg-superficie2 hover:text-tinta"
              >
                Portal
              </Link>
              <button
                type="button"
                onClick={() => void sair()}
                disabled={saindo}
                className="whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-semibold text-tinta/80 transition hover:bg-superficie2 hover:text-tinta disabled:opacity-60"
              >
                {saindo ? "Saindo..." : "Sair"}
              </button>
            </>
          ) : (
            <Link
              to="/portal/login"
              className="whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-semibold text-tinta/80 transition hover:bg-superficie2 hover:text-tinta"
            >
              Entrar
            </Link>
          )}

          <Link
            to="/parceiros/cadastro"
            className="btn-primary btn-sm rounded-full px-4"
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
          className="flex h-11 w-11 items-center justify-center rounded-xl border border-borda bg-superficie/60 transition hover:border-borda-forte xl:hidden"
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
          className="max-h-[calc(100dvh-4.5rem)] overflow-y-auto border-t border-borda bg-papel px-4 pb-6 pt-3 sm:px-6 xl:hidden"
        >
          <nav aria-label="Menu">
            <ul className="space-y-1">
              {LINKS_CENTRAIS.map((l) => (
                <li key={l.to}>
                  <Link
                    to={l.to}
                    aria-current={ehAtual(caminho, l.to) ? "page" : undefined}
                    className="block rounded-xl px-4 py-3 font-medium text-tinta/80 transition hover:bg-superficie2 hover:text-tinta aria-[current=page]:bg-superficie2 aria-[current=page]:text-tinta"
                  >
                    {l.rotulo}
                  </Link>
                </li>
              ))}
            </ul>

            <p className="rotulo mt-5 px-4 text-tinta/60">
              Institucional
            </p>
            <ul className="mt-1 grid grid-cols-2 gap-1">
              {LINKS_INSTITUCIONAIS.map((l) => (
                <li key={l.to}>
                  <Link
                    to={l.to}
                    aria-current={ehAtual(caminho, l.to) ? "page" : undefined}
                    className="block rounded-xl px-4 py-3 text-sm font-medium text-tinta/80 transition hover:bg-superficie2 hover:text-tinta aria-[current=page]:bg-superficie2 aria-[current=page]:text-tinta"
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
              className="mt-4 block rounded-xl border border-borda bg-superficie px-4 py-3 text-center text-sm font-semibold text-tinta/75"
            >
              <span aria-hidden>⌖</span>{" "}
              {temLocalidadeComercial
                ? `${rotuloLocalidade} — alterar localidade`
                : "Selecionar localidade"}
            </Link>
          )}

          <div className="mt-4 grid gap-2">
            {autenticado ? (
              <>
                <Link
                  to="/portal/dashboard"
                  className="btn-secondary w-full"
                >
                  Portal
                </Link>
                <button
                  type="button"
                  onClick={() => void sair()}
                  disabled={saindo}
                  className="btn-secondary w-full disabled:opacity-60"
                >
                  {saindo ? "Saindo..." : "Sair"}
                </button>
              </>
            ) : (
              <Link
                to="/portal/login"
                className="btn-secondary w-full"
              >
                Entrar
              </Link>
            )}
            <Link
              to="/parceiros/cadastro"
              className="btn-primary w-full"
            >
              Quero ser parceiro
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}
