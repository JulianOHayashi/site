import { useEffect, useRef, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { obterTerritorio } from "../lib/commercialTerritory";

/**
 * SiteHeader — navegação moderna compartilhada por todo o site.
 *
 * Padrão: logo à esquerda · links centrais enxutos · à direita o
 * dropdown "Entrar" (separando as duas áreas de acesso) + CTA de
 * oportunidades. No mobile, menu hambúrguer com painel completo.
 *
 * Áreas de acesso no dropdown:
 *  - Área de pedidos (/parceiros)  → empresas que compram no site
 *  - Portal BDFlow (/portal/login) → parceiros comerciais que
 *    validam QR codes (liga o site ao APP)
 */

const LINKS_CENTRAIS = [
  { rotulo: "Oportunidades", to: "/oportunidades" },
  { rotulo: "Parceiros", to: "/parceiros" },
  { rotulo: "Portal", to: "/portal/login" },
];

const AREAS_ENTRAR = [
  {
    rotulo: "Área de parceiros",
    descricao: "Empresas acompanham oportunidades por região",
    to: "/parceiros",
    icone: "🧾",
  },
  {
    rotulo: "Portal BDFlow",
    descricao: "Parceiros comerciais: validação de QR codes",
    to: "/portal/login",
    icone: "🔳",
  },
];

export default function SiteHeader() {
  const location = useLocation();
  const [rolou, setRolou] = useState(false);
  const [entrarAberto, setEntrarAberto] = useState(false);
  const [menuAberto, setMenuAberto] = useState(false);
  const entrarRef = useRef<HTMLDivElement>(null);

  // ---------------------------------------------------------------------------
  // Contexto territorial do domínio comercial BDFlow.
  // Rotas públicas/comerciais exibem a região resolvida e permitem alterá-la.
  // Portal, administração e área autenticada não exibem esse controle.
  //
  // O território comercial vem do localStorage APENAS para rótulo de navegação;
  // NÃO é autoridade — /oportunidades re-resolve a região pelo backend.
  const caminho = location.pathname;
  const destinoNext = encodeURIComponent(caminho + location.search);
  const ehComercial =
    caminho === "/" ||
    caminho.startsWith("/oportunidades") ||
    caminho.startsWith("/selecionar-localidade");

  const territorio = obterTerritorio();
  const temLocalidadeComercial =
    !!territorio &&
    territorio.regionStatus === "active" &&
    !!territorio.regionName;
  const rotuloLocalidade = temLocalidadeComercial
    ? `${territorio!.regionName} · ${territorio!.uf}`
    : "Selecionar localidade";

  // sombra ao rolar
  useEffect(() => {
    const aoRolar = () => setRolou(window.scrollY > 8);
    aoRolar();
    window.addEventListener("scroll", aoRolar, { passive: true });
    return () => window.removeEventListener("scroll", aoRolar);
  }, []);

  // fecha dropdown ao clicar fora / mudar de rota
  useEffect(() => {
    const fora = (e: MouseEvent) => {
      if (entrarRef.current && !entrarRef.current.contains(e.target as Node)) {
        setEntrarAberto(false);
      }
    };
    document.addEventListener("mousedown", fora);
    return () => document.removeEventListener("mousedown", fora);
  }, []);

  useEffect(() => {
    setEntrarAberto(false);
    setMenuAberto(false);
  }, [location.pathname, location.hash]);

  return (
    <header
      className={`sticky top-0 z-50 border-b bg-papel/85 backdrop-blur-md transition-shadow ${
        rolou ? "border-borda shadow-[0_4px_24px_rgba(23,18,31,0.08)]" : "border-transparent"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3.5">
        {/* Logo — identidade principal BDFlow */}
        <Link to="/" className="display text-xl" aria-label="BDFlow — início">
          BD<span className="text-magenta">Flow</span>
        </Link>

        {/* Links centrais (desktop) */}
        <nav className="hidden items-center gap-1 lg:flex" aria-label="Principal">
          {LINKS_CENTRAIS.map((l) => (
            <Link
              key={l.to}
              to={l.to}
              className="rounded-full px-4 py-2 text-sm font-medium text-tinta/70 transition hover:bg-papel2 hover:text-tinta"
            >
              {l.rotulo}
            </Link>
          ))}
        </nav>

        {/* Ações (desktop) */}
        <div className="hidden items-center gap-2 lg:flex">
          {/* Localidade COMERCIAL (rotas BDFlow) → /selecionar-localidade */}
          {ehComercial && (
            <Link
              to={`/selecionar-localidade?next=${destinoNext}`}
              aria-label={
                temLocalidadeComercial
                  ? `Localidade comercial: ${rotuloLocalidade}. Alterar localidade.`
                  : "Selecionar localidade comercial"
              }
              title={
                temLocalidadeComercial
                  ? `${rotuloLocalidade} — alterar localidade`
                  : "Selecionar localidade"
              }
              className="flex items-center gap-1.5 rounded-full border border-borda px-3 py-1.5 text-xs font-semibold text-tinta/70 transition hover:border-magenta hover:text-magenta"
            >
              📍 {rotuloLocalidade}
              {temLocalidadeComercial && (
                <span className="hidden xl:inline">· Alterar</span>
              )}
            </Link>
          )}
          {/* Dropdown Entrar */}
          <div ref={entrarRef} className="relative">
            <button
              onClick={() => setEntrarAberto((v) => !v)}
              aria-expanded={entrarAberto}
              aria-haspopup="menu"
              className="flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold text-tinta/80 transition hover:bg-papel2 hover:text-tinta"
            >
              Entrar
              <svg
                width="12" height="12" viewBox="0 0 12 12" aria-hidden
                className={`transition-transform ${entrarAberto ? "rotate-180" : ""}`}
              >
                <path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
              </svg>
            </button>

            {entrarAberto && (
              <div
                role="menu"
                className="absolute right-0 top-full mt-2 w-80 overflow-hidden rounded-2xl border border-borda bg-white shadow-[0_16px_48px_rgba(23,18,31,0.14)]"
              >
                {AREAS_ENTRAR.map((a, i) => (
                  <Link
                    key={a.to}
                    to={a.to}
                    role="menuitem"
                    className={`flex items-start gap-3 px-5 py-4 transition hover:bg-papel ${
                      i > 0 ? "border-t border-borda/60" : ""
                    }`}
                  >
                    <span className="mt-0.5 text-xl">{a.icone}</span>
                    <span>
                      <span className="block text-sm font-bold">{a.rotulo}</span>
                      <span className="block text-xs text-tinta/55">{a.descricao}</span>
                    </span>
                    <span className="ml-auto mt-1 text-tinta/30">→</span>
                  </Link>
                ))}
              </div>
            )}
          </div>

          {/* CTA Oportunidades comerciais (novo fluxo BDFlow) */}
          <Link
            to="/oportunidades"
            className="rounded-full bg-tinta px-5 py-2 text-sm font-bold text-white transition hover:bg-magenta"
          >
            Oportunidades
          </Link>
        </div>

        {/* Hambúrguer (mobile) */}
        <button
          onClick={() => setMenuAberto((v) => !v)}
          aria-expanded={menuAberto}
          aria-label={menuAberto ? "Fechar menu" : "Abrir menu"}
          className="flex h-10 w-10 items-center justify-center rounded-xl border border-borda lg:hidden"
        >
          <div className="space-y-1.5">
            <span className={`block h-0.5 w-5 bg-tinta transition ${menuAberto ? "translate-y-2 rotate-45" : ""}`} />
            <span className={`block h-0.5 w-5 bg-tinta transition ${menuAberto ? "opacity-0" : ""}`} />
            <span className={`block h-0.5 w-5 bg-tinta transition ${menuAberto ? "-translate-y-2 -rotate-45" : ""}`} />
          </div>
        </button>
      </div>

      {/* Painel mobile */}
      {menuAberto && (
        <div className="border-t border-borda bg-papel px-4 pb-6 pt-3 lg:hidden">
          <nav className="space-y-1" aria-label="Menu">
            {LINKS_CENTRAIS.map((l) => (
              <Link
                key={l.to}
                to={l.to}
                onClick={() => setMenuAberto(false)}
                className="block rounded-xl px-4 py-3 font-medium text-tinta/80 transition hover:bg-papel2"
              >
                {l.rotulo}
              </Link>
            ))}
          </nav>

          <p className="mt-4 px-4 text-xs font-bold uppercase tracking-widest text-tinta/40">
            Entrar
          </p>
          <div className="mt-1 space-y-1">
            {AREAS_ENTRAR.map((a) => (
              <Link
                key={a.to}
                to={a.to}
                className="flex items-start gap-3 rounded-xl px-4 py-3 transition hover:bg-papel2"
              >
                <span className="text-lg">{a.icone}</span>
                <span>
                  <span className="block text-sm font-bold">{a.rotulo}</span>
                  <span className="block text-xs text-tinta/55">{a.descricao}</span>
                </span>
              </Link>
            ))}
          </div>

          {ehComercial && (
            <Link
              to={`/selecionar-localidade?next=${destinoNext}`}
              className="mt-4 block rounded-xl border border-borda px-4 py-3 text-center text-sm font-semibold text-tinta/70"
            >
              📍 {temLocalidadeComercial
                ? `${rotuloLocalidade} — alterar localidade`
                : "Selecionar localidade"}
            </Link>
          )}
          <Link
            to="/oportunidades"
            className="mt-3 block rounded-xl bg-tinta py-3 text-center font-bold text-white transition hover:bg-magenta"
          >
            Ver oportunidades
          </Link>
        </div>
      )}
    </header>
  );
}
