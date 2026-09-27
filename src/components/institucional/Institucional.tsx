import { useEffect, type ReactNode } from "react";
import { Link } from "react-router-dom";
import SiteHeader from "../SiteHeader";
import SiteFooter from "../SiteFooter";

/**
 * Primitivas das páginas institucionais públicas (Quem somos, Como funciona,
 * Trabalhe conosco, Contato, Ajuda).
 *
 * Existem só para evitar cinco páginas copiadas. Reutilizam o sistema visual
 * vigente (Space Grotesk/Inter, magenta/ciano/amarelo, tinta, papel/papel2,
 * .btn-primary/.btn-secondary) — não é um segundo design system.
 *
 * Nada aqui coleta dados, autentica ou consulta o Supabase.
 */

const TITULO_BASE = "BDFlow";

/** Casca: header global, <main> com um único h1 vindo da Abertura, footer global. */
export function PaginaInstitucional({
  titulo,
  children,
}: {
  titulo: string;
  children: ReactNode;
}) {
  useEffect(() => {
    const anterior = document.title;
    document.title = `${titulo} | ${TITULO_BASE}`;
    return () => {
      document.title = anterior;
    };
  }, [titulo]);

  return (
    <>
      <SiteHeader />
      <main id="conteudo">{children}</main>
      <SiteFooter />
    </>
  );
}

/**
 * Abertura editorial assimétrica: título largo à esquerda, complemento
 * opcional (aside) à direita. Em telas pequenas empilha.
 */
export function Abertura({
  rotulo,
  titulo,
  texto,
  aside,
  children,
}: {
  rotulo: string;
  titulo: ReactNode;
  texto?: ReactNode;
  aside?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <section className="mx-auto max-w-6xl px-4 pb-14 pt-12 sm:pt-20">
      <div className="grid gap-10 lg:grid-cols-12 lg:gap-12">
        <div className={aside ? "lg:col-span-7" : "lg:col-span-9"}>
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
            {rotulo}
          </p>
          <h1 className="mt-4 text-4xl leading-[1.05] sm:text-5xl lg:text-6xl break-words">
            {titulo}
          </h1>
          {texto && (
            <div className="mt-6 max-w-2xl text-lg leading-8 text-tinta/70">{texto}</div>
          )}
          {children && <div className="mt-8 flex flex-wrap gap-3">{children}</div>}
        </div>
        {aside && <div className="lg:col-span-5 lg:pt-10">{aside}</div>}
      </div>
    </section>
  );
}

/**
 * Seção editorial: título e introdução numa coluna estreita à esquerda,
 * conteúdo na coluna larga. Separada por um fio no topo.
 */
export function Secao({
  id,
  titulo,
  intro,
  children,
  fundo = "papel",
}: {
  id?: string;
  titulo: ReactNode;
  intro?: ReactNode;
  children?: ReactNode;
  fundo?: "papel" | "papel2";
}) {
  const idTitulo = id ? `${id}-titulo` : undefined;
  return (
    <section
      id={id}
      aria-labelledby={idTitulo}
      className={fundo === "papel2" ? "bg-papel2" : undefined}
    >
      <div className="mx-auto max-w-6xl px-4 py-14 sm:py-20">
        <div className="grid gap-8 border-t border-tinta/15 pt-8 lg:grid-cols-12 lg:gap-12">
          <div className="lg:col-span-4">
            <h2 id={idTitulo} className="text-2xl leading-tight sm:text-3xl">
              {titulo}
            </h2>
            {intro && <div className="mt-4 text-tinta/65 leading-7">{intro}</div>}
          </div>
          <div className="lg:col-span-8">{children}</div>
        </div>
      </div>
    </section>
  );
}

type Destino = { rotulo: string; to: string };

/** Faixa final de chamada: fundo tinta, uma ação principal e uma secundária. */
export function Chamada({
  titulo,
  texto,
  principal,
  secundaria,
}: {
  titulo: string;
  texto?: string;
  principal: Destino;
  secundaria?: Destino;
}) {
  return (
    <section className="mx-auto max-w-6xl px-4 pb-20 pt-6">
      <div className="rounded-3xl bg-tinta px-6 py-12 text-white sm:px-12 sm:py-16">
        <div className="grid gap-8 lg:grid-cols-12 lg:items-end">
          <div className="lg:col-span-7">
            <h2 className="text-3xl leading-tight sm:text-4xl">{titulo}</h2>
            {texto && <p className="mt-4 max-w-xl text-white/75 leading-7">{texto}</p>}
          </div>
          <div className="flex flex-wrap gap-3 lg:col-span-5 lg:justify-end">
            <Link
              to={principal.to}
              className="inline-flex min-h-[44px] items-center justify-center rounded-xl bg-magenta px-6 py-3 font-semibold text-white transition hover:brightness-90"
            >
              {principal.rotulo}
            </Link>
            {secundaria && (
              <Link
                to={secundaria.to}
                className="inline-flex min-h-[44px] items-center justify-center rounded-xl border-2 border-white/80 px-6 py-3 font-semibold text-white transition hover:bg-white hover:text-tinta"
              >
                {secundaria.rotulo}
              </Link>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

/** Bloco de texto com título h3 e fio superior colorido opcional. */
export function Bloco({
  titulo,
  children,
  destaque,
}: {
  titulo: ReactNode;
  children: ReactNode;
  destaque?: "magenta" | "ciano" | "amarelo";
}) {
  const fio =
    destaque === "magenta"
      ? "border-magenta"
      : destaque === "ciano"
        ? "border-ciano"
        : destaque === "amarelo"
          ? "border-amarelo"
          : "border-borda";
  return (
    <div className={`border-t-2 ${fio} pt-5`}>
      <h3 className="text-lg leading-snug sm:text-xl">{titulo}</h3>
      <div className="mt-2 text-sm leading-6 text-tinta/70">{children}</div>
    </div>
  );
}
