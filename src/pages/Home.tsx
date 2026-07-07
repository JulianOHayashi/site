import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import BrazilMap from "../components/BrazilMap";
import DemoBanner from "../components/DemoBanner";
import ProductOrbit from "../components/ProductOrbit";
import ShirtPreview from "../components/ShirtPreview";
import EstoqueBadge from "../components/EstoqueBadge";
import { useProducts } from "../hooks/useProducts";
import { formatarPreco } from "../lib/format";

/**
 * HOME "DECOLAGEM" v2 — página sobre a foto panorâmica (/panorama.jpg),
 * percorrida DE BAIXO PARA CIMA, agora com ~2,5 telas de altura:
 *
 *   CÉU/MONTANHA · "Quem somos"
 *   CARRO        · vitrine orbital SEM palco (cards direto na foto)
 *   BASE (capim) · título + mapa DIRETO sobre o terreno
 *                  (estados translúcidos; bandeiras oficiais no hover)
 *
 * A foto é ancorada pela BASE (object-bottom): em telas maiores o corte
 * acontece só no céu, mantendo mapa/carro/montanha alinhados.
 * A versão anterior continua em /classica.
 */

export default function Home() {
  const { products, loading } = useProducts();
  const mapaRef = useRef<HTMLDivElement>(null);
  const vitrineRef = useRef<HTMLDivElement>(null);
  const sobreRef = useRef<HTMLDivElement>(null);
  const [selecao, setSelecao] = useState<{ nome: string; es: boolean } | null>(
    null
  );
  const [imgCarregada, setImgCarregada] = useState(false);

  const reduzMovimento =
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const irAte = (ref: React.RefObject<HTMLDivElement>) => {
    ref.current?.scrollIntoView({
      behavior: reduzMovimento ? "auto" : "smooth",
      block: "center",
    });
  };

  // O site ABRE na base (mapa)
  useEffect(() => {
    if (!imgCarregada) return;
    mapaRef.current?.scrollIntoView({ behavior: "auto", block: "end" });
  }, [imgCarregada]);

  const aoEscolherEstado = (nome: string, es: boolean) => {
    setSelecao({ nome, es });
    irAte(vitrineRef);
  };

  const mostrarProdutos = !selecao || selecao.es;

  return (
    <main>
      <DemoBanner />

      {/* PALCO: foto panorâmica, ~2,5 telas, ancorada pela base */}
      <div className="relative" style={{ height: "max(250vh, 140vw)" }}>
        <img
          src="/panorama.jpg"
          alt=""
          aria-hidden
          onLoad={() => setImgCarregada(true)}
          className="absolute inset-0 h-full w-full object-cover object-bottom"
        />

        {/* ============ TOPO · QUEM SOMOS (montanha/céu) ============ */}
        <div
          ref={sobreRef}
          className="absolute bottom-[63%] left-1/2 w-full max-w-2xl -translate-x-1/2 px-4"
        >
          <div className="rounded-3xl bg-white/85 p-8 shadow-xl backdrop-blur-md sm:p-10">
            <h2 className="text-3xl sm:text-4xl">
              Quem somos
              <span className="mt-3 block h-2 w-28 rounded-full bg-ciano" />
            </h2>
            {/* ⚠️ TEXTO PROVISÓRIO — A DEFINIR pelo dono do site */}
            <p className="mt-5 text-tinta/80">
              Somos uma estamparia capixaba que transforma a identidade da sua
              empresa em camisas de qualidade. Cada peça é produzida no
              Espírito Santo, com arte revisada uma a uma pela nossa equipe
              antes de ir para a máquina.
            </p>
            <p className="mt-3 text-tinta/80">
              Começamos pelo ES — e, como a estrada aí embaixo sugere, estamos
              a caminho de todo o Brasil.
            </p>

            <div className="mt-7 grid gap-3 text-sm sm:grid-cols-2">
              {/* ⚠️ CONTATOS PROVISÓRIOS — A DEFINIR */}
              <div className="rounded-xl bg-papel2 p-4">
                <p className="font-semibold">Contato</p>
                <p className="mt-1 text-tinta/70">contato@exemplo.com.br</p>
              </div>
              <div className="rounded-xl bg-papel2 p-4">
                <p className="font-semibold">Onde estamos</p>
                <p className="mt-1 text-tinta/70">Espírito Santo, Brasil</p>
              </div>
            </div>

            <div className="mt-6 flex flex-wrap items-center justify-between gap-3 text-xs text-tinta/50">
              <span>
                Política de trocas (em breve) · Termos (em breve) · Privacidade
                (em breve)
              </span>
              <Link to="/admin" className="hover:text-tinta">
                Admin
              </Link>
            </div>
          </div>

          <div className="mt-4 flex justify-center">
            <button
              onClick={() => irAte(vitrineRef)}
              className="rounded-full bg-tinta/70 px-5 py-2 text-sm font-semibold text-white backdrop-blur transition hover:bg-tinta"
            >
              ↓ Descer até os modelos
            </button>
          </div>
        </div>

        {/* ============ MEIO · VITRINE (sobre o carro) ============ */}
        <div
          ref={vitrineRef}
          className="absolute bottom-[30%] left-1/2 w-full max-w-5xl -translate-x-1/2 px-4"
        >
          {mostrarProdutos ? (
            <>
              <h2 className="text-center text-3xl text-white drop-shadow-[0_2px_10px_rgba(23,18,31,0.8)] sm:text-5xl">
                {selecao?.es ? (
                  <>
                    Bem-vindo,{" "}
                    <span className="text-amarelo">Espírito Santo</span>!
                  </>
                ) : (
                  "Escolha o modelo"
                )}
              </h2>
              <p className="mt-2 text-center font-medium text-white/90 drop-shadow">
                Tamanho único · Área de estampa horizontal de 49×30cm
              </p>

              <div className="mt-6">
                {loading ? (
                  <div className="flex justify-center">
                    <div className="h-10 w-10 animate-spin rounded-full border-4 border-white/40 border-t-magenta" />
                  </div>
                ) : reduzMovimento ? (
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
                          <ShirtPreview
                            corBase={p.cor_base}
                            fraseFixa={p.frase_fixa}
                            compacto
                          />
                          <div className="mt-3 flex items-center justify-between gap-2">
                            <div>
                              <p className="font-display font-bold">{p.nome}</p>
                              <p className="font-bold">
                                {formatarPreco(p.preco)}
                              </p>
                            </div>
                            <EstoqueBadge estoque={p.estoque} />
                          </div>
                        </Link>
                      );
                    })}
                  </div>
                ) : (
                  /* vitrine SEM palco: cards orbitam direto sobre a foto */
                  <ProductOrbit products={products} fundoTransparente />
                )}
              </div>
            </>
          ) : (
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
                <button onClick={() => irAte(mapaRef)} className="btn-secondary">
                  Escolher outro estado
                </button>
                <button onClick={() => setSelecao(null)} className="btn-primary">
                  Ver os modelos mesmo assim
                </button>
              </div>
            </div>
          )}
        </div>

        {/* ============ BASE · MAPA direto sobre o terreno ============ */}
        <div
          ref={mapaRef}
          className="absolute bottom-[1.5%] left-1/2 w-full max-w-xl -translate-x-1/2 px-4"
        >
          <h1 className="text-center text-3xl leading-[1.05] text-white drop-shadow-[0_3px_12px_rgba(23,18,31,0.85)] sm:text-4xl">
            CAMISAS QUE <span className="text-magenta">CONTAM</span> A SUA{" "}
            <span className="text-amarelo">MARCA.</span>
          </h1>
          <p className="mt-2 text-center font-medium text-white/90 drop-shadow">
            Clique no seu estado — e decole até os modelos. 🛫
          </p>

          {/* mapa SEM cartão: estados translúcidos revelando o terreno */}
          <div className="mt-4">
            <BrazilMap onSelectState={aoEscolherEstado} />
          </div>
        </div>
      </div>

      {/* NAVEGAÇÃO FIXA (as 3 alturas) */}
      <nav
        className="fixed right-3 top-1/2 z-40 flex -translate-y-1/2 flex-col gap-2"
        aria-label="Navegar entre as seções"
      >
        {[
          { rotulo: "Quem somos", ref: sobreRef, icone: "☁️" },
          { rotulo: "Modelos", ref: vitrineRef, icone: "👕" },
          { rotulo: "Mapa", ref: mapaRef, icone: "🗺️" },
        ].map((s) => (
          <button
            key={s.rotulo}
            onClick={() => irAte(s.ref)}
            title={s.rotulo}
            aria-label={`Ir para ${s.rotulo}`}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-tinta/60 text-base backdrop-blur transition hover:scale-110 hover:bg-tinta"
          >
            {s.icone}
          </button>
        ))}
      </nav>
    </main>
  );
}
