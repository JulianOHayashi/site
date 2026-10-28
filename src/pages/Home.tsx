import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import SiteHeader from "../components/SiteHeader";
import SiteFooter from "../components/SiteFooter";
import FormacaoReferencia from "../components/institucional/FormacaoReferencia";
import RelacaoSiteApp from "../components/institucional/RelacaoSiteApp";
import { FORMACAO_REFERENCIA, REGIAO_ATIVA } from "../content/institucional";

/**
 * HOME — Site SmallFlags (comercial).
 *
 * Primeira dobra responde três perguntas: o que é a SmallFlags, qual oportunidade
 * existe aqui e o que a empresa faz em seguida. Depois: região ativa, os seis
 * nichos, a formação de referência, a relação Site ↔ App e as entradas de
 * parceiro.
 *
 * Pública: não exige território selecionado. O território (UF + cidade) é
 * pedido pelo CommercialTerritoryGuard ao abrir /oportunidades.
 *
 * Nenhum dado inventado: sem métricas, clientes, depoimentos, logos ou
 * cobertura nacional.
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
      threshold: 0.12,
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

/** Seta decorativa dos CTAs. */
function Seta() {
  return (
    <svg aria-hidden viewBox="0 0 16 16" className="h-4 w-4">
      <path d="M3 8h9M8.5 4 12.5 8l-4 4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export default function Home() {
  return (
    <>
      <SiteHeader />

      {/* ===================== HERO ===================== */}
      <section className="relative overflow-hidden">
        <div aria-hidden className="malha malha-esmaecida absolute inset-0" />
        <div aria-hidden className="halo-marca -right-48 -top-56 h-[34rem] w-[34rem] opacity-[0.09] sm:opacity-[0.16]" />
        <div className="relative mx-auto max-w-6xl px-4 pb-16 pt-14 sm:px-6 sm:pb-24 sm:pt-24">
          <div className="grid gap-12 lg:grid-cols-12 lg:gap-10">
            <div className="lg:col-span-7">
              <p className="rotulo-marca entrar">Oportunidades comerciais SmallFlags</p>
              <h1 className="display t-hero entrar entrar-2 mt-6 max-w-[16ch]">
                Oportunidades comerciais por região e{" "}
                <span className="texto-marca">por nicho.</span>
              </h1>
              <p className="entrar entrar-3 mt-7 max-w-xl text-lg leading-8 text-tinta/70">
                Cada oportunidade é a contratação integral de um nicho dentro de uma
                exclusividade comercial da região. A {REGIAO_ATIVA.nome} ({REGIAO_ATIVA.uf})
                é a primeira região ativa.
              </p>
              <div className="entrar entrar-4 mt-10 flex flex-wrap gap-3">
                <Link to="/oportunidades" className="btn-primary px-6">
                  Ver oportunidades
                  <Seta />
                </Link>
                <Link to="/parceiros" className="btn-secondary px-6">
                  Quero ser parceiro
                </Link>
              </div>
              <p className="mt-5 max-w-md text-sm leading-6 text-tinta/60">
                Estado e cidade são solicitados ao abrir as oportunidades.
              </p>
            </div>

            {/* Painel da região ativa: estado do território, não um card decorativo. */}
            <aside
              aria-label="Região comercial ativa"
              className="entrar entrar-3 lg:col-span-5 lg:pt-6"
            >
              <div className="painel-marca relative overflow-hidden p-7 sm:p-8">
                <div aria-hidden className="absolute inset-x-0 top-0 h-40 bg-marca-suave opacity-80 [mask-image:linear-gradient(to_bottom,black,transparent)]" />
                <div className="relative">
                  <div className="flex items-center gap-3">
                    <span aria-hidden className="ponto-vivo" />
                    <p className="rotulo text-tinta/65">Região ativa</p>
                  </div>
                  <p className="display mt-5 text-3xl leading-tight sm:text-4xl">
                    {REGIAO_ATIVA.nome}
                    <span className="font-normal text-tinta/60"> · {REGIAO_ATIVA.uf}</span>
                  </p>
                  <ul className="mt-5 flex flex-wrap gap-2">
                    {REGIAO_ATIVA.cidades.map((c) => (
                      <li key={c} className="chip">
                        {c}
                      </li>
                    ))}
                  </ul>
                  <p className="mt-6 border-t border-borda pt-5 text-sm leading-6 text-tinta/65">
                    Novas regiões são abertas por etapas. Fora da região ativa, é possível
                    registrar interesse territorial.
                  </p>
                  <Link to="/selecionar-localidade" className="btn-tertiary mt-3">
                    Selecionar localidade
                  </Link>
                </div>
              </div>
            </aside>
          </div>
        </div>
      </section>

      {/* ===================== SEIS NICHOS ===================== */}
      <section aria-labelledby="nichos-titulo" className="faixa">
        <div className="fio grid gap-8 lg:grid-cols-12 lg:gap-12">
          <div className="lg:col-span-4">
            <h2 id="nichos-titulo" className="t-secao">
              Seis nichos por exclusividade
            </h2>
            <p className="mt-4 max-w-sm leading-7 text-tinta/65">
              Cada nicho é contratado integralmente dentro da exclusividade comercial da
              região. Um CNPJ contrata um único nicho.
            </p>
          </div>

          <div className="lg:col-span-8">
            <ol className="border-t border-borda">
              {FORMACAO_REFERENCIA.map((n, i) => (
                <li key={n.nome}>
                  <Revelar atraso={i * 40}>
                    <div className="group flex items-baseline gap-4 border-b border-borda py-5 sm:gap-6">
                      <span
                        aria-hidden
                        className="display w-8 shrink-0 text-sm text-tinta/35 tabular-nums"
                      >
                        {String(i + 1).padStart(2, "0")}
                      </span>
                      <h3 className="flex-1 text-xl leading-snug sm:text-2xl">{n.nome}</h3>
                      <span className="shrink-0 text-sm text-tinta/60">
                        <span className="display text-lg tabular-nums text-tinta">
                          {n.unidades}
                        </span>{" "}
                        unidades
                      </span>
                    </div>
                  </Revelar>
                </li>
              ))}
            </ol>
          </div>
        </div>
      </section>

      {/* ===================== FORMAÇÃO DE REFERÊNCIA ===================== */}
      <section aria-labelledby="formacao-titulo" className="faixa-densa">
        <Revelar>
          <div className="relative overflow-hidden rounded-[2rem] border border-borda bg-superficie px-6 py-12 shadow-painel sm:px-12 sm:py-16">
            <div aria-hidden className="halo-marca -bottom-40 -left-24 h-80 w-80 opacity-[0.12]" />
            <hr aria-hidden className="divisor-marca absolute inset-x-0 top-0 opacity-70" />
            <div className="relative grid gap-10 lg:grid-cols-12 lg:gap-12">
              <div className="lg:col-span-5">
                <p className="rotulo-marca">Formação comercial</p>
                <h2 id="formacao-titulo" className="t-secao mt-5">
                  Seis nichos · 84 unidades
                </h2>
                <p className="mt-5 max-w-sm leading-7 text-tinta/65">
                  A formação comercial de referência de uma exclusividade. O andamento de
                  cada oportunidade fica na página da sua região.
                </p>
                <Link to="/oportunidades" className="btn-primary mt-8 px-6">
                  Ver oportunidades
                  <Seta />
                </Link>
              </div>
              <div className="lg:col-span-7">
                <FormacaoReferencia />
              </div>
            </div>
          </div>
        </Revelar>
      </section>

      {/* ===================== CONHEÇA A SMALLFLAGS: SITE ↔ APP ===================== */}
      <section aria-labelledby="conheca-titulo" className="faixa">
        <div className="fio grid gap-8 lg:grid-cols-12 lg:gap-12">
          <div className="lg:col-span-4">
            <h2 id="conheca-titulo" className="t-secao">
              Conheça a SmallFlags
            </h2>
            <p className="mt-4 max-w-sm leading-7 text-tinta/65">
              Dois ambientes com responsabilidades separadas. O Site cuida da relação
              comercial; o App cuida da jornada do divulgador — o microempreendedor
              individual que faz divulgação sonora em vias públicas com o próprio
              veículo.
            </p>
            <div className="mt-7 flex flex-wrap gap-3">
              <Link to="/quem-somos" className="btn-secondary">
                Quem somos
              </Link>
              <Link to="/como-funciona" className="btn-secondary">
                Como funciona
              </Link>
            </div>
          </div>
          <div className="lg:col-span-8">
            <RelacaoSiteApp />
          </div>
        </div>
      </section>

      {/* ===================== ENTRADAS DE PARCEIRO ===================== */}
      <section aria-labelledby="parceiros-titulo" className="faixa-densa">
        <h2 id="parceiros-titulo" className="sr-only">
          Entradas para empresas parceiras
        </h2>
        <Revelar>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="card-interativo flex flex-col p-8 sm:p-10">
              <p className="rotulo text-tinta/60">Ainda não é parceira</p>
              <h3 className="mt-3 text-2xl leading-snug">Conheça a parceria SmallFlags</h3>
              <p className="mt-3 flex-1 leading-7 text-tinta/65">
                Entenda o modelo comercial, os requisitos e envie a solicitação da sua
                empresa.
              </p>
              <Link to="/parceiros" className="btn-primary mt-8 self-start">
                Área de parceiros
                <Seta />
              </Link>
            </div>
            <div className="card-interativo flex flex-col p-8 sm:p-10">
              <p className="rotulo text-tinta/60">Já é parceira</p>
              <h3 className="mt-3 text-2xl leading-snug">Portal do Parceiro</h3>
              <p className="mt-3 flex-1 leading-7 text-tinta/65">
                Gestão da empresa, equipe e a validação dos benefícios apresentados pelos
                divulgadores.
              </p>
              <Link to="/portal/login" className="btn-secondary mt-8 self-start">
                Ir para o Portal
              </Link>
            </div>
          </div>
        </Revelar>
      </section>

      {/* ===================== ENTRADA INSTITUCIONAL DISCRETA ===================== */}
      <section className="mx-auto max-w-6xl px-4 pb-6 sm:px-6">
        <p className="border-t border-borda pt-8 text-sm leading-6 text-tinta/65">
          Quer construir a SmallFlags com a gente?{" "}
          <Link to="/trabalhe-conosco" className="link">
            Trabalhe conosco
          </Link>
        </p>
      </section>

      <SiteFooter />
    </>
  );
}
