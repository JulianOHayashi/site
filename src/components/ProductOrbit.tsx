import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import ShirtPreview from "./ShirtPreview";
import EstoqueBadge from "./EstoqueBadge";
import { formatarPreco } from "../lib/format";
import type { Product } from "../types";

/**
 * Vitrine orbital — inspirada no efeito "World Orbit":
 * palco escuro estrelado, planeta com brilho no horizonte e os cards
 * das camisas orbitando em arco por cima dele.
 *
 * - Giro contínuo e suave; o card da frente fica maior e clicável.
 * - Cards laterais recuam, descem pelo arco e inclinam levemente.
 * - Mouse sobre o palco pausa a órbita. Setas ‹ › giram manualmente.
 * - Clicar num card lateral o traz para a frente.
 */

const VELOCIDADE = 12; // graus/segundo (volta completa em 30s)
const ARCO_Y = 34; // quanto os cards descem nas laterais (px por unidade)
const INCLINACAO = 13; // inclinação máxima dos cards laterais (graus)

/** Estrelas com posições determinísticas (sem aleatório a cada render). */
const ESTRELAS = Array.from({ length: 42 }, (_, i) => ({
  left: `${(i * 37) % 100}%`,
  top: `${(i * 53) % 62}%`,
  size: 1 + ((i * 7) % 3),
  cor:
    i % 9 === 0
      ? "#E5007E"
      : i % 7 === 0
        ? "#00A8E0"
        : i % 5 === 0
          ? "#FFC400"
          : "#FBFAF6",
  pisca: i % 4 === 0,
}));

interface Props {
  products: Product[];
}

export default function ProductOrbit({ products }: Props) {
  const navigate = useNavigate();
  const n = products.length;
  const passo = 360 / n;

  const palcoRef = useRef<HTMLDivElement>(null);
  const anguloRef = useRef(0);
  const alvoRef = useRef<number | null>(null);
  const pausadoRef = useRef(false);
  const [, forceRender] = useState(0);
  const [raio, setRaio] = useState(260);

  // Raio responsivo conforme a largura do palco
  useEffect(() => {
    const medir = () => {
      const w = palcoRef.current?.clientWidth ?? 900;
      setRaio(Math.max(120, Math.min(300, w / 2 - 150)));
    };
    medir();
    window.addEventListener("resize", medir);
    return () => window.removeEventListener("resize", medir);
  }, []);

  // Loop da órbita
  useEffect(() => {
    let raf = 0;
    let ultimo = performance.now();

    const tick = (agora: number) => {
      const dt = Math.min(0.05, (agora - ultimo) / 1000);
      ultimo = agora;

      let a = anguloRef.current;
      const alvo = alvoRef.current;

      if (alvo !== null) {
        const diff = alvo - a;
        if (Math.abs(diff) < 0.15) {
          a = alvo;
          alvoRef.current = null;
        } else {
          a += diff * Math.min(1, dt * 6); // easing até o alvo
        }
      } else if (!pausadoRef.current) {
        a += dt * VELOCIDADE; // órbita contínua
      }

      anguloRef.current = a;
      forceRender((v) => v + 1);
      raf = requestAnimationFrame(tick);
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  /** Traz o item i para a frente pelo caminho mais curto. */
  const trazerParaFrente = (i: number) => {
    const atual = anguloRef.current;
    let alvo = -passo * i;
    alvo += Math.round((atual - alvo) / 360) * 360;
    alvoRef.current = alvo;
  };

  const girar = (dir: 1 | -1) => {
    const base =
      Math.round((alvoRef.current ?? anguloRef.current) / passo) * passo;
    alvoRef.current = base + dir * passo;
  };

  const angulo = anguloRef.current;

  return (
    <div>
      {/* PALCO ESPACIAL */}
      <div
        ref={palcoRef}
        className="relative mx-auto h-[440px] max-w-4xl overflow-hidden rounded-3xl bg-tinta sm:h-[480px]"
        onMouseEnter={() => (pausadoRef.current = true)}
        onMouseLeave={() => (pausadoRef.current = false)}
        role="region"
        aria-label="Vitrine giratória de modelos de camisa"
      >
        {/* céu com leve gradiente */}
        <div
          className="pointer-events-none absolute inset-0"
          style={{
            background:
              "radial-gradient(120% 90% at 50% 0%, rgba(0,168,224,0.10) 0%, rgba(229,0,126,0.06) 45%, transparent 70%)",
          }}
        />

        {/* estrelas */}
        {ESTRELAS.map((e, i) => (
          <span
            key={i}
            className={`pointer-events-none absolute rounded-full ${e.pisca ? "animate-pulse" : ""}`}
            style={{
              left: e.left,
              top: e.top,
              width: e.size,
              height: e.size,
              backgroundColor: e.cor,
              opacity: 0.8,
            }}
          />
        ))}

        {/* planeta no horizonte, com brilho magenta/ciano */}
        <div
          className="pointer-events-none absolute left-1/2 top-[76%] aspect-square w-[170%] -translate-x-1/2 rounded-full"
          style={{
            background:
              "radial-gradient(closest-side, #241C33 0%, #1D1628 55%, #17121F 100%)",
            boxShadow:
              "0 -18px 70px rgba(229,0,126,0.35), 0 -6px 28px rgba(0,168,224,0.35), inset 0 24px 60px rgba(251,250,246,0.05)",
          }}
        />

        {/* CARDS EM ÓRBITA */}
        {products.map((p, i) => {
          const rad = ((angulo + passo * i) * Math.PI) / 180;
          const seno = Math.sin(rad);
          const profundidade = (Math.cos(rad) + 1) / 2; // 0 fundo → 1 frente
          const x = seno * raio;
          const y = (1 - Math.cos(rad)) * ARCO_Y; // desce pelo arco nas laterais
          const inclinacao = seno * INCLINACAO; // inclina acompanhando a curva
          const escala = 0.64 + 0.36 * profundidade;
          const opacidade = 0.38 + 0.62 * profundidade;
          const naFrente = profundidade > 0.88;
          const esgotado = p.estoque === 0;

          return (
            <button
              key={p.id}
              onClick={() => {
                if (!naFrente) return trazerParaFrente(i);
                if (!esgotado) navigate(`/produto/${p.slug}`);
              }}
              aria-label={
                naFrente
                  ? esgotado
                    ? `${p.nome} — esgotado`
                    : `Ver detalhes de ${p.nome}`
                  : `Trazer ${p.nome} para a frente`
              }
              className="absolute left-1/2 top-[42%] w-[230px] cursor-pointer text-left sm:w-[290px]"
              style={{
                transform: `translate(-50%, -50%) translate(${x}px, ${y}px) rotate(${inclinacao}deg) scale(${escala})`,
                opacity: esgotado ? opacidade * 0.7 : opacidade,
                zIndex: Math.round(profundidade * 100),
                willChange: "transform, opacity",
              }}
            >
              <div
                className={`rounded-2xl bg-white p-3 sm:p-4 ${
                  naFrente ? "ring-2 ring-magenta" : ""
                }`}
                style={{
                  boxShadow: naFrente
                    ? "0 10px 50px rgba(229,0,126,0.45)"
                    : "0 8px 30px rgba(0,0,0,0.45)",
                }}
              >
                <ShirtPreview
                  corBase={p.cor_base}
                  fraseFixa={p.frase_fixa}
                  compacto
                />
                <div className="mt-3 flex items-center justify-between gap-2">
                  <div>
                    <p className="font-display text-base font-bold sm:text-lg">
                      {p.nome}
                    </p>
                    <p className="text-sm font-bold sm:text-base">
                      {formatarPreco(p.preco)}
                    </p>
                  </div>
                  <EstoqueBadge estoque={p.estoque} />
                </div>
                {naFrente && (
                  <p className="mt-2 text-center text-xs font-semibold text-magenta">
                    {esgotado ? "Esgotado" : "Clique para personalizar →"}
                  </p>
                )}
              </div>
            </button>
          );
        })}
      </div>

      {/* CONTROLES */}
      <div className="mt-4 flex items-center justify-center gap-4">
        <button
          onClick={() => girar(-1)}
          aria-label="Girar para o modelo anterior"
          className="flex h-11 w-11 items-center justify-center rounded-full border-2 border-tinta text-xl font-bold transition hover:bg-tinta hover:text-white"
        >
          ‹
        </button>
        <p className="text-xs text-tinta/50">
          gira sozinho · passe o mouse para pausar
        </p>
        <button
          onClick={() => girar(1)}
          aria-label="Girar para o próximo modelo"
          className="flex h-11 w-11 items-center justify-center rounded-full border-2 border-tinta text-xl font-bold transition hover:bg-tinta hover:text-white"
        >
          ›
        </button>
      </div>
    </div>
  );
}
