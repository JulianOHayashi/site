import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { geoMercator, geoPath, type GeoPermissibleObjects } from "d3-geo";

const GEO_URL =
  "https://raw.githubusercontent.com/codeforamerica/click_that_hood/main/public/data/brazil-states.geojson";

const TINTAS = ["#E5007E", "#00A8E0", "#FFC400"];
const LARGURA = 800;
const ALTURA = 780;

interface Feature {
  type: string;
  properties: Record<string, string>;
  geometry: GeoPermissibleObjects;
}

/** Remove acentos e baixa a caixa para comparar nomes com segurança. */
function normalizar(s: string): string {
  return s
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .trim();
}

function nomeDoEstado(f: Feature): string {
  const p = f.properties ?? {};
  return p.name ?? p.NAME ?? p.nome ?? p.NOME_UF ?? "";
}

const ES = normalizar("Espírito Santo");

// Lista de fallback caso o GeoJSON não carregue (sem internet, URL fora do ar…)
const UFS = [
  "AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG",
  "PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO",
];

export default function BrazilMap() {
  const navigate = useNavigate();
  const containerRef = useRef<HTMLDivElement>(null);
  const [features, setFeatures] = useState<Feature[] | null>(null);
  const [erro, setErro] = useState(false);
  const [hovered, setHovered] = useState<string | null>(null);
  const [zooming, setZooming] = useState(false);
  const [origin, setOrigin] = useState("50% 50%");

  useEffect(() => {
    fetch(GEO_URL)
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      })
      .then((geo) => setFeatures(geo.features as Feature[]))
      .catch(() => setErro(true));
  }, []);

  const irPara = (nome: string) => {
    const destino = normalizar(nome) === ES ? "/produtos" : "/em-breve";
    navigate(destino, { state: { estado: nome } });
  };

  const handleClick = (nome: string, e: React.MouseEvent) => {
    if (zooming) return;
    const reduzMovimento = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;
    if (reduzMovimento || !containerRef.current) {
      irPara(nome);
      return;
    }
    const rect = containerRef.current.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * 100;
    const y = ((e.clientY - rect.top) / rect.height) * 100;
    setOrigin(`${x}% ${y}%`);
    setZooming(true);
    window.setTimeout(() => irPara(nome), 700);
  };

  // ---------- Fallback: grade de UFs clicáveis ----------
  if (erro) {
    return (
      <div className="mx-auto max-w-xl">
        <p className="mb-4 text-center text-sm text-tinta/70">
          Não foi possível carregar o mapa. Escolha seu estado:
        </p>
        <div className="grid grid-cols-5 gap-2 sm:grid-cols-7">
          {UFS.map((uf, i) => (
            <button
              key={uf}
              onClick={() =>
                navigate(uf === "ES" ? "/produtos" : "/em-breve", {
                  state: { estado: uf },
                })
              }
              className="card px-2 py-3 font-display font-bold transition hover:text-white"
              onMouseEnter={(e) =>
                (e.currentTarget.style.backgroundColor = TINTAS[i % 3])
              }
              onMouseLeave={(e) =>
                (e.currentTarget.style.backgroundColor = "")
              }
            >
              {uf}
            </button>
          ))}
        </div>
      </div>
    );
  }

  // ---------- Carregando ----------
  if (!features) {
    return (
      <div className="flex h-72 items-center justify-center">
        <div
          className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta"
          aria-label="Carregando mapa"
        />
      </div>
    );
  }

  // ---------- Mapa ----------
  const projection = geoMercator().fitSize([LARGURA, ALTURA], {
    type: "FeatureCollection",
    features,
  } as GeoPermissibleObjects);
  const path = geoPath(projection);

  return (
    <div className="relative mx-auto max-w-3xl overflow-hidden" aria-label="Mapa do Brasil — clique no seu estado">
      <div
        ref={containerRef}
        style={{
          transformOrigin: origin,
          transform: zooming ? "scale(6)" : "scale(1)",
          opacity: zooming ? 0 : 1,
          transition: "transform 700ms ease-in, opacity 650ms ease-in",
        }}
      >
        <svg
          viewBox={`0 0 ${LARGURA} ${ALTURA}`}
          className="h-auto w-full"
          role="group"
        >
          {features.map((f, i) => {
            const nome = nomeDoEstado(f);
            const ativo = hovered === nome;
            return (
              <path
                key={nome || i}
                d={path(f.geometry) ?? undefined}
                fill={ativo ? TINTAS[i % 3] : "#FFFFFF"}
                stroke="#17121F"
                strokeWidth={ativo ? 1.4 : 0.8}
                style={{ cursor: "pointer", transition: "fill 150ms" }}
                tabIndex={0}
                role="button"
                aria-label={`${nome}${normalizar(nome) === ES ? "" : " — em breve"}`}
                onMouseEnter={() => setHovered(nome)}
                onMouseLeave={() => setHovered(null)}
                onFocus={() => setHovered(nome)}
                onBlur={() => setHovered(null)}
                onClick={(e) => handleClick(nome, e)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    irPara(nome);
                  }
                }}
              />
            );
          })}
        </svg>
      </div>

      {hovered && !zooming && (
        <div className="pointer-events-none absolute left-1/2 top-2 -translate-x-1/2 rounded-full bg-tinta px-4 py-1.5 text-sm font-semibold text-white shadow-lg">
          {hovered}
          {normalizar(hovered) !== ES && (
            <span className="ml-1.5 font-normal opacity-70">· em breve</span>
          )}
        </div>
      )}
    </div>
  );
}
