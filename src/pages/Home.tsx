import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import SiteHeader from "../components/SiteHeader";
import SiteFooter from "../components/SiteFooter";
import FormacaoReferencia from "../components/institucional/FormacaoReferencia";
import RelacaoSiteApp from "../components/institucional/RelacaoSiteApp";
import { FORMACAO_REFERENCIA, REGIAO_ATIVA } from "../content/institucional";

/**
 * HOME — Site BDFlow (comercial).
 *
 * Primeira dobra responde três perguntas: o que é a BDFlow, qual oportunidade
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

export default function Home() {
  return (
    <>
      <SiteHeader />

      {/* ===================== HERO ===================== */}
      <section className="relative overflow-hidden">
        <div aria-hidden className="malha malha-esmaecida absolute inset-0" />
        <div className="relative mx-auto max-w-6xl px-4 pb-16 pt-12 sm:pb-24 sm:pt-20">
          <div className="grid gap-12 lg:grid-cols-12 lg:gap-10">
            <div className="lg:col-span-7">
              <p className="rotulo text-magenta">Oportunidades comerciais BDFlow</p>
              <h1 className="display t-hero mt-5 max-w-[16ch]">
                Oportunidades comerciais por região e por nicho.
              </h1>
              <p className="mt-7 max-w-xl text-lg leading-8 text-tinta/75">
                Cada oportunidade é a contratação integral de um nicho dentro de uma
                exclusividade comercial da região. A {REGIAO_ATIVA.nome} ({REGIAO_ATIVA.uf})
                é a primeira região ativa.
              </p>
              <div className="mt-9 flex flex-wrap gap-3">
                <Link to="/oportunidades" className="btn-primary">
                  Ver oportunidades
                </Link>
                <Link to="/parceiros" className="btn-secondary">
                  Quero ser parceiro
                </Link>
              </div>
              <p className="mt-5 max-w-md text-sm leading-6 text-tinta/65">
                Estado e cidade são solicitados ao abrir as oportunidades.
              </p>
            </div>

            {/* Painel da região ativa: estado do território, não um card decorativo. */}
            <aside
              aria-label="Região comercial ativa"
              className="lg:col-span-5 lg:pt-16"
            >
              <div className="rounded-3xl border border-tinta/15 bg-white/80 p-7 backdrop-blur-sm sm:p-8">
                <div className="flex items-center gap-2.5">
                  <span aria-hidden className="relative flex h-2.5 w-2.5">
                    <span className="absolute inline-flex h-full w-full rounded-full bg-ciano/60" />
                    <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-ciano" />
                  </span>
                  <p className="rotulo text-tinta/65">Região ativa</p>
                </div>
                <p className="display mt-4 text-3xl leading-tight sm:text-4xl">
                  {REGIAO_ATIVA.nome}
                  <span className="font-normal text-tinta/70"> · {REGIAO_ATIVA.uf}</span>
                </p>
                <ul className="mt-5 flex flex-wrap gap-2">
                  {REGIAO_ATIVA.cidades.map((c) => (
                    <li
                      key={c}
                      className="rounded-full border border-tinta/15 px-3 py-1.5 text-sm text-tinta/75"
                    >
                      {c}
                    </li>
                  ))}
                </ul>
                <p className="mt-6 border-t border-tinta/10 pt-5 text-sm leading-6 text-tinta/70">
                  Novas regiões são abertas por etapas. Fora da região ativa, é possível
                  registrar interesse territorial.
                </p>
                <Link
                  to="/selecionar-localidade"
                  className="mt-4 inline-flex min-h-[44px] items-center font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
                >
                  Selecionar localidade
                </Link>
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
            <p className="mt-4 max-w-sm leading-7 text-tinta/70">
              Cada nicho é contratado integralmente dentro da exclusividade comercial da
              região. Um CNPJ contrata um único nicho.
            </p>
          </div>

          <div className="lg:col-span-8">
            <ol className="border-t border-tinta/15">
              {FORMACAO_REFERENCIA.map((n, i) => (
                <li key={n.nome}>
                  <Revelar atraso={i * 40}>
                    <div className="flex items-baseline gap-4 border-b border-tinta/15 py-5 sm:gap-6">
                      <span
                        aria-hidden
                        className="display w-8 shrink-0 text-sm text-tinta/40 tabular-nums"
                      >
                        {String(i + 1).padStart(2, "0")}
                      </span>
                      <h3 className="flex-1 text-xl leading-snug sm:text-2xl">{n.nome}</h3>
                      <span className="shrink-0 text-sm text-tinta/70">
                        <span className="font-semibold tabular-nums text-tinta">
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
          <div className="rounded-[2rem] bg-tinta px-6 py-12 text-white sm:px-12 sm:py-16">
            <div className="grid gap-10 lg:grid-cols-12 lg:gap-12">
              <div className="lg:col-span-5">
                <p className="rotulo text-amarelo">Formação comercial</p>
                <h2 id="formacao-titulo" className="t-secao mt-4">
                  Seis nichos · 84 unidades
                </h2>
                <p className="mt-5 max-w-sm leading-7 text-white/75">
                  A formação comercial de referência de uma exclusividade. O andamento de
                  cada oportunidade fica na página da sua região.
                </p>
                <Link
                  to="/oportunidades"
                  className="mt-8 inline-flex min-h-[44px] items-center rounded-xl bg-white px-6 py-3 font-semibold text-tinta transition hover:bg-amarelo"
                >
                  Ver oportunidades
                </Link>
              </div>
              <div className="lg:col-span-7">
                <FormacaoReferencia tom="escuro" />
              </div>
            </div>
          </div>
        </Revelar>
      </section>

      {/* ===================== CONHEÇA A BDFLOW: SITE ↔ APP ===================== */}
      <section aria-labelledby="conheca-titulo" className="faixa">
        <div className="fio grid gap-8 lg:grid-cols-12 lg:gap-12">
          <div className="lg:col-span-4">
            <h2 id="conheca-titulo" className="t-secao">
              Conheça a BDFlow
            </h2>
            <p className="mt-4 max-w-sm leading-7 text-tinta/70">
              Dois ambientes com responsabilidades separadas. O Site cuida da relação
              comercial; o App cuida da jornada do participante.
            </p>
            <div className="mt-6 flex flex-wrap gap-3">
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
          <div className="grid gap-px overflow-hidden rounded-3xl border border-borda bg-borda md:grid-cols-2">
            <div className="flex flex-col bg-white p-8 sm:p-10">
              <p className="rotulo text-tinta/60">Ainda não é parceira</p>
              <h3 className="mt-3 text-2xl leading-snug">Conheça a parceria BDFlow</h3>
              <p className="mt-3 flex-1 leading-7 text-tinta/70">
                Entenda o modelo comercial, os requisitos e envie a solicitação da sua
                empresa.
              </p>
              <Link to="/parceiros" className="btn-secondary mt-7 self-start">
                Área de parceiros
              </Link>
            </div>
            <div className="flex flex-col bg-white p-8 sm:p-10">
              <p className="rotulo text-tinta/60">Já é parceira</p>
              <h3 className="mt-3 text-2xl leading-snug">Portal do Parceiro</h3>
              <p className="mt-3 flex-1 leading-7 text-tinta/70">
                Gestão da empresa, equipe e a validação dos benefícios apresentados pelos
                participantes.
              </p>
              <Link to="/portal/login" className="btn-secondary mt-7 self-start">
                Ir para o Portal
              </Link>
            </div>
          </div>
        </Revelar>
      </section>

      {/* ===================== ENTRADA INSTITUCIONAL DISCRETA ===================== */}
      <section className="mx-auto max-w-6xl px-4 pb-6">
        <p className="border-t border-borda pt-8 text-sm leading-6 text-tinta/70">
          Quer construir a BDFlow com a gente?{" "}
          <Link
            to="/trabalhe-conosco"
            className="font-semibold text-tinta underline decoration-ciano decoration-2 underline-offset-4"
          >
            Trabalhe conosco
          </Link>
        </p>
      </section>

      <SiteFooter />
    </>
  );
}
