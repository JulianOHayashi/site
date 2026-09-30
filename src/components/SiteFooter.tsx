import { Link } from "react-router-dom";
import { REGIAO_ATIVA } from "../content/institucional";

/**
 * Rodapé público global do Site SmallFlags.
 *
 * Só aponta para rotas que existem. A coluna Legal fica reservada: enquanto
 * não houver páginas públicas de Privacidade/Termos, ela diz isso em texto em
 * vez de exibir links falsos.
 */
const COLUNAS: { titulo: string; links: { rotulo: string; to: string }[] }[] = [
  {
    titulo: "SmallFlags",
    links: [
      { rotulo: "Quem somos", to: "/quem-somos" },
      { rotulo: "Como funciona", to: "/como-funciona" },
      { rotulo: "Trabalhe conosco", to: "/trabalhe-conosco" },
    ],
  },
  {
    titulo: "Empresas",
    links: [
      { rotulo: "Seja parceiro", to: "/parceiros" },
      { rotulo: "Oportunidades", to: "/oportunidades" },
      { rotulo: "Acompanhar solicitação", to: "/parceiros/acesso" },
      { rotulo: "Portal do Parceiro", to: "/portal/login" },
    ],
  },
  {
    titulo: "Suporte",
    links: [
      { rotulo: "Ajuda", to: "/ajuda" },
      { rotulo: "Contato", to: "/contato" },
    ],
  },
];

export default function SiteFooter() {
  return (
    <footer className="mt-12 border-t border-borda bg-papel2/70">
      <div className="mx-auto max-w-6xl px-4 py-16">
        <div className="grid gap-12 lg:grid-cols-12">
          <div className="lg:col-span-4">
            <Link to="/" className="display inline-block text-2xl" aria-label="SmallFlags — início">
              Small<span className="text-magenta">Flags</span>
            </Link>
            <p className="mt-3 max-w-xs text-sm leading-6 text-tinta/65">
              Oportunidades comerciais por região e por nicho. Região comercial
              ativa: {REGIAO_ATIVA.nome} ({REGIAO_ATIVA.uf}).
            </p>
          </div>

          <nav
            aria-label="Rodapé"
            className="grid grid-cols-2 gap-8 sm:grid-cols-4 lg:col-span-8"
          >
            {COLUNAS.map((c) => (
              <div key={c.titulo}>
                <h2 className="rotulo text-tinta/60">{c.titulo}</h2>
                <ul className="mt-3 space-y-1">
                  {c.links.map((l) => (
                    <li key={l.to}>
                      <Link
                        to={l.to}
                        className="inline-block py-1.5 text-sm text-tinta/70 transition hover:text-magenta"
                      >
                        {l.rotulo}
                      </Link>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
            <div>
              <h2 className="rotulo text-tinta/60">Legal</h2>
              <p className="mt-3 py-1.5 text-sm leading-6 text-tinta/65">
                Os documentos legais públicos serão disponibilizados aqui.
              </p>
            </div>
          </nav>
        </div>

        <p className="mt-14 border-t border-borda pt-6 text-xs text-tinta/65">
          © 2026 SmallFlags
        </p>
      </div>
    </footer>
  );
}
