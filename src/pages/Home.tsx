import { useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import BrazilMap from "../components/BrazilMap";
import DemoBanner from "../components/DemoBanner";
import ProductOrbit from "../components/ProductOrbit";
import ShirtPreview from "../components/ShirtPreview";
import EstoqueBadge from "../components/EstoqueBadge";
import { useProducts } from "../hooks/useProducts";
import { formatarPreco } from "../lib/format";

/**
 * Página única em panorama vertical:
 *  ── CÉU     → título + mapa do Brasil flutuando entre nuvens
 *  ── ESTRADA → horizonte com estrada em perspectiva; a vitrine de
 *               camisas "pousa" sobre a estrada. Clicar num estado
 *               NÃO troca de página: a tela rola até aqui.
 *               Estado ≠ ES → mostra "Em breve" nesta mesma seção.
 *  ── ASFALTO → base escura com os dois caminhos e o rodapé.
 */

function Nuvem({
  top,
  largura,
  duracao,
  atraso,
  opacidade = 0.9,
}: {
  top: string;
  largura: number;
  duracao: string;
  atraso: string;
  opacidade?: number;
}) {
  return (
    <div
      className="nuvem"
      style={{
        top,
        width: largura,
        height: largura * 0.32,
        animationDuration: duracao,
        animationDelay: atraso,
        opacity: opacidade,
      }}
      aria-hidden
    />
  );
}

export default function Home() {
  const navigate = useNavigate();
  const { products, loading } = useProducts();
  const vitrineRef = useRef<HTMLElement>(null);
  const topoRef = useRef<HTMLElement>(null);
  const [selecao, setSelecao] = useState<{ nome: string; es: boolean } | null>(
    null
  );

  const reduzMovimento =
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const aoEscolherEstado = (nome: string, es: boolean) => {
    setSelecao({ nome, es });
    vitrineRef.current?.scrollIntoView({
      behavior: reduzMovimento ? "auto" : "smooth",
    });
  };

  const mostrarProdutos = !selecao || selecao.es;

  return (
    <main className="overflow-x-clip">
      <DemoBanner />

      {/* ============ SEÇÃO 1 · CÉU ============ */}
      <section
        ref={topoRef}
        className="relative min-h-screen"
        style={{
          background: "linear-gradient(180deg, #7FC4E8 0%, #C7E5F4 100%)",
        }}
      >
        {/* nuvens à deriva */}
        <div className="pointer-events-none absolute inset-0 overflow-hidden">
          <Nuvem top="8%" largura={180} duracao="70s" atraso="-10s" />
          <Nuvem top="18%" largura={120} duracao="55s" atraso="-30s" opacidade={0.75} />
          <Nuvem top="30%" largura={220} duracao="90s" atraso="-50s" />
          <Nuvem top="55%" largura={140} duracao="65s" atraso="-20s" opacidade={0.7} />
          <Nuvem top="70%" largura={190} duracao="80s" atraso="-60s" opacidade={0.8} />
        </div>

        <div className="relative mx-auto max-w-5xl px-4 pb-10 pt-14 text-center sm:pt-20">
          <h1 className="text-4xl leading-[1.05] text-tinta sm:text-6xl md:text-7xl">
            CAMISAS QUE <span className="text-magenta">CONTAM</span>
            <br />A SUA <span className="text-white drop-shadow-[0_2px_6px_rgba(0,90,140,0.45)]">
              MARCA
            </span>
            <span className="text-amarelo">.</span>
          </h1>
          <p className="mx-auto mt-5 max-w-md text-tinta/80">
            Estamos começando pelo Espírito Santo.{" "}
            <span className="font-semibold text-tinta">
              Clique no seu estado para descer até os modelos.
            </span>
          </p>

          {/* mapa flutuando entre as nuvens */}
          <div className="mt-8 rounded-3xl bg-white/60 p-3 shadow-xl backdrop-blur-sm sm:p-5">
            <BrazilMap onSelectState={aoEscolherEstado} />
          </div>

          <p className="mt-6 animate-bounce text-2xl text-tinta/50" aria-hidden>
            ↓
          </p>
        </div>
      </section>

      {/* ============ SEÇÃO 2 · ESTRADA (vitrine) ============ */}
      <section ref={vitrineRef} className="relative min-h-screen scroll-mt-4">
        {/* paisagem: céu → horizonte → estrada em perspectiva */}
        <svg
          className="absolute inset-0 h-full w-full"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden
        >
          <defs>
            <linearGradient id="ceu2" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#C7E5F4" />
              <stop offset="100%" stopColor="#EAF6FC" />
            </linearGradient>
            <linearGradient id="campo" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#A8D48F" />
              <stop offset="100%" stopColor="#7FB86B" />
            </linearGradient>
            <linearGradient id="pista" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#4A4756" />
              <stop offset="100%" stopColor="#2E2B38" />
            </linearGradient>
          </defs>

          {/* céu até o horizonte */}
          <rect x="0" y="0" width="100" height="38" fill="url(#ceu2)" />
          {/* brilho do horizonte */}
          <rect x="0" y="37.2" width="100" height="1.6" fill="#FFFFFF" opacity="0.55" />
          {/* campo */}
          <rect x="0" y="38" width="100" height="62" fill="url(#campo)" />
          {/* estrada em perspectiva */}
          <polygon points="47.5,38 52.5,38 88,100 12,100" fill="url(#pista)" />
          {/* acostamento (linhas brancas das bordas) */}
          <polygon points="47.5,38 48.1,38 14.5,100 12,100" fill="#FBFAF6" opacity="0.8" />
          <polygon points="51.9,38 52.5,38 88,100 85.5,100" fill="#FBFAF6" opacity="0.8" />
          {/* faixa central tracejada (amarela, afinando no horizonte) */}
          <polygon points="49.8,42 50.2,42 50.25,49 49.75,49" fill="#FFC400" />
          <polygon points="49.6,55 50.4,55 50.5,64 49.5,64" fill="#FFC400" />
          <polygon points="49.3,70 50.7,70 50.9,81 49.1,81" fill="#FFC400" />
          <polygon points="48.9,87 51.1,87 51.4,100 48.6,100" fill="#FFC400" />
        </svg>

        <div className="relative mx-auto max-w-5xl px-4 pb-24 pt-16">
          {mostrarProdutos ? (
            <>
              <h2 className="text-center text-3xl text-tinta sm:text-5xl">
                {selecao?.es ? (
                  <>
                    Bem-vindo, <span className="text-magenta">Espírito Santo</span>!
                  </>
                ) : (
                  "Escolha o modelo"
                )}
              </h2>
              <p className="mt-2 text-center text-tinta/70">
                Tamanho único · Área de estampa horizontal de 49×30cm
              </p>

              <div className="mt-10">
                {loading ? (
                  <div className="flex justify-center">
                    <div className="h-10 w-10 animate-spin rounded-full border-4 border-white border-t-magenta" />
                  </div>
                ) : reduzMovimento ? (
                  /* grade estática para quem reduz movimento */
                  <div className="grid gap-6 md:grid-cols-3">
                    {products.map((p) => {
                      const esgotado = p.estoque === 0;
                      return (
                        <Link
                          key={p.id}
                          to={esgotado ? "#" : `/produto/${p.slug}`}
                          onClick={(e) => esgotado && e.preventDefault()}
                          className={`card block p-4 ${esgotado ? "cursor-not-allowed opacity-60" : "hover:-translate-y-1 hover:shadow-lg"}`}
                        >
                          <ShirtPreview corBase={p.cor_base} fraseFixa={p.frase_fixa} compacto />
                          <div className="mt-3 flex items-center justify-between gap-2">
                            <div>
                              <p className="font-display font-bold">{p.nome}</p>
                              <p className="font-bold">{formatarPreco(p.preco)}</p>
                            </div>
                            <EstoqueBadge estoque={p.estoque} />
                          </div>
                        </Link>
                      );
                    })}
                  </div>
                ) : (
                  /* vitrine orbital pousada sobre a estrada */
                  <ProductOrbit products={products} />
                )}
              </div>
            </>
          ) : (
            /* estado ≠ ES: "Em breve" na própria página */
            <div className="mx-auto max-w-lg rounded-3xl bg-white/90 p-10 text-center shadow-xl backdrop-blur">
              <h2 className="text-3xl sm:text-4xl">
                Em breve em {selecao?.nome}!
                <span className="mx-auto mt-3 block h-2 w-36 rounded-full bg-amarelo" />
              </h2>
              <p className="mt-5 text-tinta/70">
                Estamos começando pelo Espírito Santo, mas a estrada já está
                sendo asfaltada até aí.
              </p>
              <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
                <button
                  onClick={() =>
                    topoRef.current?.scrollIntoView({
                      behavior: reduzMovimento ? "auto" : "smooth",
                    })
                  }
                  className="btn-secondary"
                >
                  Escolher outro estado
                </button>
                <button
                  onClick={() => setSelecao(null)}
                  className="btn-primary"
                >
                  Ver os modelos mesmo assim
                </button>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* ============ SEÇÃO 3 · ASFALTO (base) ============ */}
      <section
        className="relative"
        style={{
          backgroundColor: "#2B2933",
          backgroundImage:
            "radial-gradient(rgba(255,255,255,0.07) 1px, transparent 1px), radial-gradient(rgba(255,255,255,0.04) 1px, transparent 1px)",
          backgroundSize: "18px 18px, 31px 31px",
          backgroundPosition: "0 0, 9px 12px",
        }}
      >
        {/* faixa dupla amarela — divisa da pista */}
        <div className="h-1.5 w-full bg-amarelo" />
        <div className="mt-1 h-1.5 w-full bg-amarelo/70" />

        <div className="mx-auto grid max-w-5xl gap-5 px-4 pb-10 pt-12 md:grid-cols-2">
          <button
            onClick={() =>
              vitrineRef.current?.scrollIntoView({
                behavior: reduzMovimento ? "auto" : "smooth",
              })
            }
            className="group rounded-2xl bg-magenta p-7 text-left text-white shadow-md transition hover:-translate-y-0.5 hover:shadow-xl"
          >
            <p className="text-xs font-bold uppercase tracking-widest opacity-80">
              Caminho 1
            </p>
            <h2 className="mt-1 text-3xl">Empresarial</h2>
            <p className="mt-2 text-sm opacity-90">
              Camisas para sua empresa. Você está aqui — suba até a vitrine e
              escolha um modelo.
            </p>
            <span className="mt-4 inline-block text-sm font-semibold underline-offset-4 group-hover:underline">
              Ver modelos ↑
            </span>
          </button>

          <button
            onClick={() => navigate("/em-breve", { state: { origem: "individual" } })}
            className="group relative rounded-2xl border-2 border-ciano bg-white p-7 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg"
          >
            <span className="absolute right-5 top-5 rounded-full bg-amarelo px-3 py-1 text-[10px] font-bold uppercase tracking-wider text-tinta">
              Em breve
            </span>
            <p className="text-xs font-bold uppercase tracking-widest text-ciano">
              Caminho 2
            </p>
            <h2 className="mt-1 text-3xl text-tinta">Individual</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Compre uma camisa avulsa para você. Em construção.
            </p>
          </button>
        </div>

        <div className="mx-auto flex max-w-5xl items-center justify-between px-4 pb-8 text-xs text-white/40">
          <span>camisas.es — feito no Espírito Santo</span>
          <Link to="/admin" className="hover:text-white/80">
            Admin
          </Link>
        </div>
      </section>
    </main>
  );
}
