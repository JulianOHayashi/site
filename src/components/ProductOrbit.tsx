import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import ShirtPreview from "./ShirtPreview";
import EstoqueBadge from "./EstoqueBadge";
import { formatarPreco } from "../lib/format";
import type { Product } from "../types";

/**
 * Vitrine orbital: as camisas giram continuamente em círculo.
 * - A camisa da frente fica maior, nítida e clicável (vai para o detalhe).
 * - Clicar em uma camisa do fundo a traz suavemente para a frente.
 * - Passa o mouse por cima → a órbita pausa. Setas ‹ › giram manualmente.
 * - Com "reduzir movimento" ativo no sistema, a página usa a grade estática.
 */

const VELOCIDADE = 14; // graus por segundo (volta completa em ~26s)

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

  // Raio responsivo conforme a largura disponível
  useEffect(() => {
    const medir = () => {
      const w = palcoRef.current?.clientWidth ?? 900;
      setRaio(Math.max(120, Math.min(300, w / 2 - 160)));
    };
    medir();
    window.addEventListener("resize", medir);
    return () => window.removeEventListener("resize", medir);
  }, []);

  // Loop de animação
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
          a += diff * Math.min(1, dt * 6); // easing suave até o alvo
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

  /** Traz o item i para a frente com animação. */
  const trazerParaFrente = (i: number) => {
    const atual = anguloRef.current;
    let alvo = -passo * i;
    alvo += Math.round((atual - alvo) / 360) * 360; // caminho mais curto
    alvoRef.current = alvo;
  };

  const girar = (dir: 1 | -1) => {
    const base =
      Math.round((alvoRef.current ?? anguloRef.current) / passo) * passo;
    alvoRef.current = base + dir * passo;
  };

  const angulo = anguloRef.current;

  return (
    <div className="relative">
      {/* PALCO */}
      <div
        ref={palcoRef}
        className="relative mx-auto h-[420px] max-w-4xl sm:h-[460px]"
        onMouseEnter={() => (pausadoRef.current = true)}
        onMouseLeave={() => (pausadoRef.current = false)}
        role="region"
        aria-label="Vitrine giratória de modelos de camisa"
      >
        {products.map((p, i) => {
          const rad = ((angulo + passo * i) * Math.PI) / 180;
          const x = Math.sin(rad) * raio;
          const profundidade = (Math.cos(rad) + 1) / 2; // 0 (fundo) → 1 (frente)
          const escala = 0.68 + 0.32 * profundidade;
          const opacidade = 0.4 + 0.6 * profundidade;
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
              className={`absolute left-1/2 top-1/2 w-[240px] text-left sm:w-[300px] ${
                naFrente && !esgotado ? "cursor-pointer" : "cursor-pointer"
              }`}
              style={{
                transform: `translate(-50%, -50%) translateX(${x}px) scale(${escala})`,
                opacity: esgotado ? opacidade * 0.7 : opacidade,
                zIndex: Math.round(profundidade * 100),
                transition: "box-shadow 200ms",
                willChange: "transform, opacity",
              }}
            >
              <div
                className={`card p-3 sm:p-4 ${
                  naFrente
                    ? "border-2 border-magenta shadow-xl"
                    : "border border-borda"
                }`}
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
      <div className="mt-2 flex items-center justify-center gap-4">
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
