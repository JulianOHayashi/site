import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import SiteHeader from "../components/SiteHeader";

/**
 * HOME — Site BDFlow (comercial).
 *
 * Apresenta o negócio comercial: oportunidades por região e nicho,
 * exclusividade, os seis nichos e a formação de referência (84 unidades),
 * a área de parceiros e uma referência resumida à operação administrada
 * pelo aplicativo BDFlow.
 *
 * Pública: não exige território previamente selecionado. O território
 * (UF + cidade) é solicitado pelo CommercialTerritoryGuard ao acessar
 * /oportunidades.
 *
 * Textos neutros e provisórios — sem conteúdo jurídico/comercial definitivo.
 */

/* ---------- Revelar ao rolar (fade + sobe; respeita reduced-motion) ---------- */
function Revelar({
  children,
  atraso = 0,
  className = "",
}: {
  children: React.ReactNode;
  atraso?: number;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visivel, setVisivel] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setVisivel(true);
      return;
    }
    const obs = new IntersectionObserver(([e]) => setVisivel(e.isIntersecting), {
      threshold: 0.15,
    });
    obs.observe(el);
    return () => obs.disconnect();
  }, []);
  return (
    <div
      ref={ref}
      style={{ transitionDelay: `${atraso}ms` }}
      className={`transition-all duration-700 ${
        visivel ? "translate-y-0 opacity-100" : "translate-y-6 opacity-0"
      } ${className}`}
    >
      {children}
    </div>
  );
}

const NICHOS = [
  { icone: "🛒", nome: "Supermercado", qtd: 24 },
  { icone: "💊", nome: "Farmácia", qtd: 12 },
  { icone: "👗", nome: "Roupas femininas", qtd: 12 },
  { icone: "👔", nome: "Roupas masculinas", qtd: 12 },
  { icone: "👠", nome: "Calçados femininos", qtd: 12 },
  { icone: "👞", nome: "Calçados masculinos", qtd: 12 },
];

export default function Home() {
  return (
    <>
      <SiteHeader />

      {/* HERO */}
      <section className="mx-auto max-w-6xl px-4 pt-14 pb-10 sm:pt-20">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
          Oportunidades comerciais BDFlow
        </p>
        <h1 className="mt-4 max-w-3xl text-4xl leading-[1.05] sm:text-6xl">
          Oportunidades comerciais por região e por nicho.
        </h1>
        <p className="mt-5 max-w-2xl text-lg text-tinta/70">
          Empresas podem acompanhar oportunidades por região e nicho. Cada
          oportunidade representa a contratação integral de um nicho dentro de
          uma exclusividade comercial.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link to="/oportunidades" className="btn-primary">
            Ver oportunidades
          </Link>
          <Link to="/parceiros" className="btn-secondary">
            Área de parceiros
          </Link>
        </div>
        <p className="mt-4 text-sm text-tinta/50">
          O território (estado e cidade) é solicitado ao abrir as oportunidades.
        </p>
      </section>

      {/* REGIÕES ATENDIDAS */}
      <section className="mx-auto max-w-6xl px-4 py-10">
        <Revelar className="card p-8">
          <h2 className="text-2xl sm:text-3xl">Regiões atendidas</h2>
          <p className="mt-3 max-w-2xl text-tinta/70">
            A primeira região comercial ativa é a{" "}
            <span className="font-semibold">Grande Vitória (ES)</span>, reunindo
            Vitória, Vila Velha, Serra, Cariacica e Viana. Novas regiões serão
            abertas nas próximas etapas.
          </p>
          <div className="mt-5">
            <Link to="/selecionar-localidade" className="btn-secondary">
              Selecionar localidade
            </Link>
          </div>
        </Revelar>
      </section>

      {/* SEIS NICHOS */}
      <section className="mx-auto max-w-6xl px-4 py-10">
        <h2 className="text-2xl sm:text-3xl">Seis nichos por exclusividade</h2>
        <p className="mt-3 max-w-2xl text-tinta/70">
          Cada nicho é contratado integralmente dentro de uma exclusividade
          comercial da região.
        </p>
        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {NICHOS.map((n, i) => (
            <Revelar key={n.nome} atraso={i * 60}>
              <div className="card flex items-center gap-3 p-5">
                <span aria-hidden className="text-2xl">
                  {n.icone}
                </span>
                <div>
                  <p className="font-bold">{n.nome}</p>
                  <p className="text-sm text-tinta/60">
                    {n.qtd} unidades contratadas
                  </p>
                </div>
              </div>
            </Revelar>
          ))}
        </div>
      </section>

      {/* FORMAÇÃO DE REFERÊNCIA */}
      <section className="mx-auto max-w-6xl px-4 py-10">
        <Revelar className="card bg-tinta p-8 text-white">
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-amarelo">
            Formação comercial
          </p>
          <h2 className="mt-3 text-2xl sm:text-3xl">
            Seis nichos · 84 unidades
          </h2>
          <p className="mt-3 max-w-2xl text-white/80">
            A formação comercial de referência reúne seis nichos e 84 unidades
            contratadas. O acompanhamento de cada oportunidade fica na página de
            oportunidades da sua região.
          </p>
          <div className="mt-6">
            <Link
              to="/oportunidades"
              className="rounded-full bg-white px-5 py-2.5 text-sm font-bold text-tinta transition hover:bg-amarelo"
            >
              Ver oportunidades
            </Link>
          </div>
        </Revelar>
      </section>

      {/* REFERÊNCIA OPERACIONAL */}
      <section className="mx-auto max-w-6xl px-4 py-10">
        <Revelar className="rounded-3xl border border-borda bg-papel2 p-8">
          <h2 className="text-2xl sm:text-3xl">Site e aplicativo</h2>
          <p className="mt-3 max-w-2xl text-tinta/70">
            O Site administra a exclusividade comercial. A jornada dos usuários
            e o ciclo operacional são administrados pelo aplicativo BDFlow.
          </p>
        </Revelar>
      </section>

      {/* ÁREA DE PARCEIROS */}
      <section className="mx-auto max-w-6xl px-4 py-10">
        <Revelar className="grid gap-4 sm:grid-cols-2">
          <div className="card p-8">
            <h3 className="text-xl font-bold">Área de parceiros</h3>
            <p className="mt-2 text-sm text-tinta/70">
              Empresas acompanham suas oportunidades e informações comerciais.
            </p>
            <Link to="/parceiros" className="btn-secondary mt-4 inline-block">
              Área de parceiros
            </Link>
          </div>
          <div className="card p-8">
            <h3 className="text-xl font-bold">Portal BDFlow</h3>
            <p className="mt-2 text-sm text-tinta/70">
              Parceiros comerciais validam QR codes — a ponte entre o site e o
              aplicativo.
            </p>
            <Link to="/portal/login" className="btn-secondary mt-4 inline-block">
              Ir para o Portal
            </Link>
          </div>
        </Revelar>
      </section>

      {/* RODAPÉ */}
      <footer className="mt-10 border-t border-borda">
        <div className="mx-auto max-w-6xl px-4 py-10">
          <p className="display text-lg">
            BD<span className="text-magenta">Flow</span>
          </p>
          <p className="mt-2 max-w-md text-sm text-tinta/60">
            Oportunidades comerciais por região e por nicho. Conteúdo provisório
            — informações comerciais definitivas serão publicadas nas próximas
            etapas.
          </p>
          <div className="mt-5 flex flex-wrap gap-4 text-sm font-medium">
            <Link to="/oportunidades" className="text-ciano hover:underline">
              Oportunidades
            </Link>
            <Link to="/parceiros" className="text-ciano hover:underline">
              Parceiros
            </Link>
            <Link to="/portal/login" className="text-ciano hover:underline">
              Portal
            </Link>
          </div>
          <p className="mt-6 text-xs text-tinta/40">© 2026 BDFlow</p>
        </div>
      </footer>
    </>
  );
}
