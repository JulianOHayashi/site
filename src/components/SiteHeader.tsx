import { useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { obterTerritorio } from "../lib/commercialTerritory";

/**
 * Navegação pública BDFlow.
 *
 * Arquitetura de entrada:
 * - Parceiros: conteúdo público + início da candidatura.
 * - Acompanhar solicitação: acesso provisório, exposto dentro da jornada de parceria.
 * - Entrar: único acesso principal visível para parceiros aprovados -> Portal.
 */
const LINKS_CENTRAIS = [
  { rotulo: "Oportunidades", to: "/oportunidades" },
  { rotulo: "Parceiros", to: "/parceiros" },
];

export default function SiteHeader() {
  const location = useLocation();
  const [rolou, setRolou] = useState(false);
  const [menuAberto, setMenuAberto] = useState(false);

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

  useEffect(() => {
    const aoRolar = () => setRolou(window.scrollY > 8);
    aoRolar();
    window.addEventListener("scroll", aoRolar, { passive: true });
    return () => window.removeEventListener("scroll", aoRolar);
  }, []);

  useEffect(() => {
    setMenuAberto(false);
  }, [location.pathname, location.hash]);

  return (
    <header
      className={`sticky top-0 z-50 border-b bg-papel/90 backdrop-blur-md transition-shadow ${
        rolou
          ? "border-borda shadow-[0_4px_24px_rgba(23,18,31,0.08)]"
          : "border-transparent"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3.5">
        <Link to="/" className="display text-xl" aria-label="BDFlow — início">
          BD<span className="text-magenta">Flow</span>
        </Link>

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

        <div className="hidden items-center gap-2 lg:flex">
          {ehComercial && (
            <Link
              to={`/selecionar-localidade?next=${destinoNext}`}
              aria-label={
                temLocalidadeComercial
                  ? `Localidade comercial: ${rotuloLocalidade}. Alterar localidade.`
                  : "Selecionar localidade comercial"
              }
              className="flex items-center gap-1.5 rounded-full border border-borda px-3 py-1.5 text-xs font-semibold text-tinta/70 transition hover:border-magenta hover:text-magenta"
            >
              <span aria-hidden>⌖</span>
              {rotuloLocalidade}
              {temLocalidadeComercial && <span className="hidden xl:inline">· Alterar</span>}
            </Link>
          )}

          <Link
            to="/portal/login"
            className="rounded-full px-4 py-2 text-sm font-semibold text-tinta/80 transition hover:bg-papel2 hover:text-tinta"
          >
            Entrar
          </Link>

          <Link
            to="/parceiros/cadastro"
            className="rounded-full bg-tinta px-5 py-2 text-sm font-bold text-white transition hover:bg-magenta"
          >
            Quero ser parceiro
          </Link>
        </div>

        <button
          onClick={() => setMenuAberto((v) => !v)}
          aria-expanded={menuAberto}
          aria-label={menuAberto ? "Fechar menu" : "Abrir menu"}
          className="flex h-10 w-10 items-center justify-center rounded-xl border border-borda lg:hidden"
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
        <div className="border-t border-borda bg-papel px-4 pb-6 pt-3 lg:hidden">
          <nav className="space-y-1" aria-label="Menu">
            {LINKS_CENTRAIS.map((l) => (
              <Link
                key={l.to}
                to={l.to}
                className="block rounded-xl px-4 py-3 font-medium text-tinta/80 transition hover:bg-papel2"
              >
                {l.rotulo}
              </Link>
            ))}
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
