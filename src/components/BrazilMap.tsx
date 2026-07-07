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

/**
 * Bandeiras OFICIAIS via Wikimedia Commons (Special:FilePath rasteriza
 * o SVG oficial em PNG na largura pedida). Chave: nome normalizado.
 * Se alguma imagem não carregar, as faixas de cores abaixo aparecem
 * automaticamente como reserva.
 */
const ARQUIVO_BANDEIRA: Record<string, string> = {
  acre: "Bandeira do Acre.svg",
  alagoas: "Bandeira de Alagoas.svg",
  amapa: "Bandeira do Amapá.svg",
  amazonas: "Bandeira do Amazonas.svg",
  bahia: "Bandeira da Bahia.svg",
  ceara: "Bandeira do Ceará.svg",
  "distrito federal": "Bandeira do Distrito Federal (Brasil).svg",
  "espirito santo": "Bandeira do Espírito Santo.svg",
  goias: "Bandeira de Goiás.svg",
  maranhao: "Bandeira do Maranhão.svg",
  "mato grosso": "Bandeira de Mato Grosso.svg",
  "mato grosso do sul": "Bandeira de Mato Grosso do Sul.svg",
  "minas gerais": "Bandeira de Minas Gerais.svg",
  para: "Bandeira do Pará.svg",
  paraiba: "Bandeira da Paraíba.svg",
  parana: "Bandeira do Paraná.svg",
  pernambuco: "Bandeira de Pernambuco.svg",
  piaui: "Bandeira do Piauí.svg",
  "rio de janeiro": "Bandeira do estado do Rio de Janeiro.svg",
  "rio grande do norte": "Bandeira do Rio Grande do Norte.svg",
  "rio grande do sul": "Bandeira do Rio Grande do Sul.svg",
  rondonia: "Bandeira de Rondônia.svg",
  roraima: "Bandeira de Roraima.svg",
  "santa catarina": "Bandeira de Santa Catarina.svg",
  "sao paulo": "Bandeira do estado de São Paulo.svg",
  sergipe: "Bandeira de Sergipe.svg",
  tocantins: "Bandeira do Tocantins.svg",
};

function urlBandeira(nomeNormalizado: string, largura = 400): string | null {
  const arquivo = ARQUIVO_BANDEIRA[nomeNormalizado];
  if (!arquivo) return null;
  return `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(
    arquivo.replace(/ /g, "_")
  )}?width=${largura}`;
}

/** Cores predominantes (RESERVA caso a imagem da bandeira falhe). */
const CORES_BANDEIRA: Record<string, string[]> = {
  acre: ["#FEDD00", "#009739", "#CE1126"],
  alagoas: ["#CE1126", "#FFFFFF", "#0B5BA5"],
  amapa: ["#009739", "#FEDD00", "#FFFFFF", "#0033A0"],
  amazonas: ["#FFFFFF", "#CE1126", "#00205B"],
  bahia: ["#FFFFFF", "#CE1126", "#003DA5"],
  ceara: ["#009739", "#FEDD00", "#FFFFFF"],
  "distrito federal": ["#FFFFFF", "#FEDD00", "#009739"],
  "espirito santo": ["#E75CA8", "#FFFFFF", "#0072CE"],
  goias: ["#009739", "#FEDD00", "#0033A0"],
  maranhao: ["#CE1126", "#FFFFFF", "#000000", "#0033A0"],
  "mato grosso": ["#0033A0", "#FEDD00", "#FFFFFF"],
  "mato grosso do sul": ["#FFFFFF", "#009739", "#0072CE", "#FEDD00"],
  "minas gerais": ["#FFFFFF", "#CE1126"],
  para: ["#CE1126", "#FFFFFF", "#0033A0"],
  paraiba: ["#000000", "#CE1126", "#FFFFFF"],
  parana: ["#009739", "#FFFFFF", "#0033A0"],
  pernambuco: ["#0033A0", "#FFFFFF", "#FEDD00"],
  piaui: ["#009739", "#FEDD00", "#0033A0"],
  "rio de janeiro": ["#FFFFFF", "#0033A0"],
  "rio grande do norte": ["#009739", "#FFFFFF", "#FEDD00"],
  "rio grande do sul": ["#009739", "#CE1126", "#FEDD00"],
  rondonia: ["#0033A0", "#009739", "#FEDD00", "#FFFFFF"],
  roraima: ["#0072CE", "#FFFFFF", "#009739", "#CE1126"],
  "santa catarina": ["#CE1126", "#FFFFFF", "#009739"],
  "sao paulo": ["#000000", "#FFFFFF", "#CE1126"],
  sergipe: ["#009739", "#FEDD00", "#0033A0"],
  tocantins: ["#FFFFFF", "#0033A0", "#FEDD00"],
};

function paradasDeFaixas(cores: string[]) {
  const n = cores.length;
  const paradas: { offset: string; cor: string }[] = [];
  cores.forEach((cor, i) => {
    paradas.push({ offset: `${(i / n) * 100}%`, cor });
    paradas.push({ offset: `${((i + 1) / n) * 100}%`, cor });
  });
  return paradas;
}

const UFS = [
  "AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG",
  "PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO",
];

export default function BrazilMap({
  onSelectState,
}: {
  /** Se fornecido, o mapa NÃO navega: avisa a página, que rola até a vitrine. */
  onSelectState?: (nome: string, isES: boolean) => void;
}) {
  const navigate = useNavigate();
  const containerRef = useRef<HTMLDivElement>(null);
  const [features, setFeatures] = useState<Feature[] | null>(null);
  const [erro, setErro] = useState(false);
  const [hovered, setHovered] = useState<string | null>(null);
  const [selecionado, setSelecionado] = useState<string | null>(null);
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
    const isES = normalizar(nome) === ES;
    if (onSelectState) {
      onSelectState(nome, isES);
      window.setTimeout(() => {
        setZooming(false);
        setSelecionado(null);
      }, 450);
      return;
    }
    navigate(isES ? "/produtos" : "/em-breve", { state: { estado: nome } });
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
    setSelecionado(nome);
    setZooming(true);
    window.setTimeout(() => irPara(nome), 700);
  };

  // ---------- Fallback: grade de UFs clicáveis ----------
  if (erro) {
    return (
      <div className="mx-auto max-w-xl">
        <p className="mb-4 text-center text-sm font-medium text-white drop-shadow">
          Não foi possível carregar o mapa. Escolha seu estado:
        </p>
        <div className="grid grid-cols-5 gap-2 sm:grid-cols-7">
          {UFS.map((uf, i) => (
            <button
              key={uf}
              onClick={() => irPara(uf === "ES" ? "Espírito Santo" : uf)}
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
          className="h-10 w-10 animate-spin rounded-full border-4 border-white/30 border-t-magenta"
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
    <div
      className="relative mx-auto max-w-3xl overflow-hidden"
      aria-label="Mapa do Brasil — clique no seu estado"
    >
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
          className="h-auto w-full drop-shadow-[0_4px_16px_rgba(23,18,31,0.5)]"
          role="group"
        >
          <defs>
            {features.map((f, i) => {
              const nomeN = normalizar(nomeDoEstado(f));
              const cores = CORES_BANDEIRA[nomeN] ?? [TINTAS[i % 3]];
              const url = urlBandeira(nomeN);
              return (
                <g key={`defs-${i}`}>
                  {/* reserva: faixas de cor */}
                  <linearGradient
                    id={`faixas-${i}`}
                    x1="0"
                    y1="0"
                    x2="0"
                    y2="1"
                  >
                    {paradasDeFaixas(cores).map((p, j) => (
                      <stop key={j} offset={p.offset} stopColor={p.cor} />
                    ))}
                  </linearGradient>
                  {/* bandeira oficial preenchendo o estado */}
                  {url && (
                    <pattern
                      id={`bandeira-${i}`}
                      patternUnits="objectBoundingBox"
                      patternContentUnits="objectBoundingBox"
                      width="1"
                      height="1"
                    >
                      <image
                        href={url}
                        width="1"
                        height="1"
                        preserveAspectRatio="xMidYMid slice"
                      />
                    </pattern>
                  )}
                </g>
              );
            })}
          </defs>

          {features.map((f, i) => {
            const nome = nomeDoEstado(f);
            const nomeN = normalizar(nome);
            const ativo = hovered === nome || selecionado === nome;
            const temBandeira = !!urlBandeira(nomeN);
            const d = path(f.geometry) ?? undefined;

            return (
              <g key={nome || i}>
                {/* camada base: translúcida mostrando o terreno; no hover,
                    vira as faixas de cor (reserva por baixo da bandeira) */}
                <path
                  d={d}
                  fill={
                    ativo ? `url(#faixas-${i})` : "rgba(251,250,246,0.22)"
                  }
                  stroke="#FBFAF6"
                  strokeWidth={ativo ? 1.6 : 0.9}
                  style={{ cursor: "pointer", transition: "fill 150ms" }}
                  tabIndex={0}
                  role="button"
                  aria-label={`${nome}${nomeN === ES ? "" : " — em breve"}`}
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
                {/* camada da bandeira oficial (por cima da reserva) */}
                {ativo && temBandeira && (
                  <path
                    d={d}
                    fill={`url(#bandeira-${i})`}
                    stroke="#FBFAF6"
                    strokeWidth={1.6}
                    pointerEvents="none"
                  />
                )}
              </g>
            );
          })}
        </svg>
      </div>

      {hovered && !zooming && (
        <div className="pointer-events-none absolute left-1/2 top-2 flex -translate-x-1/2 items-center gap-2 rounded-full bg-tinta/85 px-4 py-1.5 text-sm font-semibold text-white shadow-lg backdrop-blur">
          {/* mini-bandeira oficial no tooltip (faixas como reserva) */}
          <span className="relative h-3.5 w-5 overflow-hidden rounded-[2px]">
            <span className="absolute inset-0 flex flex-col">
              {(CORES_BANDEIRA[normalizar(hovered)] ?? ["#FFFFFF"]).map(
                (cor, j) => (
                  <span
                    key={j}
                    className="w-full flex-1"
                    style={{ backgroundColor: cor }}
                  />
                )
              )}
            </span>
            {urlBandeira(normalizar(hovered), 80) && (
              <img
                src={urlBandeira(normalizar(hovered), 80)!}
                alt=""
                className="absolute inset-0 h-full w-full object-cover"
              />
            )}
          </span>
          {hovered}
          {normalizar(hovered) !== ES && (
            <span className="font-normal opacity-70">· em breve</span>
          )}
        </div>
      )}
    </div>
  );
}
