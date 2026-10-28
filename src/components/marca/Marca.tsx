/**
 * Marca SmallFlags — símbolo + nome.
 *
 * Componente único de marca para header, footer, login, Portal e telas
 * institucionais. O símbolo é o ícone oficial fornecido (não redesenhar,
 * não recolorir, não reinterpretar); fica em `public/brand/`.
 *
 * ASSET: `public/brand/smallflags-icon.png` (quadrado, fundo preto).
 * Para trocar pela arte final em alta resolução, substitua o arquivo no
 * MESMO caminho — nenhum componente precisa mudar.
 *
 * Acessibilidade: o símbolo é decorativo (alt=""). Quem envolve a marca em
 * um link dá o nome acessível ao link (ex.: aria-label="SmallFlags — início").
 */
export const ICONE_MARCA_SRC = "/brand/smallflags-icon.png";

const TAMANHOS = {
  sm: { icone: "h-7 w-7", nome: "text-base", gap: "gap-2" },
  md: { icone: "h-9 w-9", nome: "text-xl", gap: "gap-2.5" },
  lg: { icone: "h-12 w-12", nome: "text-2xl", gap: "gap-3" },
} as const;

export function IconeMarca({
  tamanho = "md",
  className = "",
}: {
  tamanho?: keyof typeof TAMANHOS;
  className?: string;
}) {
  return (
    <img
      src={ICONE_MARCA_SRC}
      alt=""
      aria-hidden
      width={96}
      height={96}
      decoding="async"
      draggable={false}
      // Se o arquivo faltar, some sem deixar ícone quebrado: o nome continua.
      onError={(e) => {
        e.currentTarget.style.display = "none";
      }}
      className={`${TAMANHOS[tamanho].icone} shrink-0 rounded-[24%] object-cover ring-1 ring-black/5 shadow-sm ${className}`}
    />
  );
}

export default function Marca({
  tamanho = "md",
  comNome = true,
  sufixo,
  className = "",
}: {
  tamanho?: keyof typeof TAMANHOS;
  /** Exibe "SmallFlags" ao lado do símbolo. */
  comNome?: boolean;
  /** Complemento discreto após o nome (ex.: "Portal"). */
  sufixo?: string;
  className?: string;
}) {
  const t = TAMANHOS[tamanho];
  return (
    <span className={`inline-flex items-center ${t.gap} ${className}`}>
      <IconeMarca tamanho={tamanho} />
      {comNome && (
        <span className={`display ${t.nome} leading-none tracking-[-0.02em]`}>
          SmallFlags
          {sufixo && (
            <span className="ml-2 align-middle font-body text-[0.6em] font-semibold uppercase tracking-[0.2em] text-tinta/60">
              {sufixo}
            </span>
          )}
        </span>
      )}
    </span>
  );
}
