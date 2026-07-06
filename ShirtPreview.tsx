interface Props {
  corBase: string;
  fraseFixa: string;
  fraseCustomizada?: string;
  imagemUrl?: string | null;
  compacto?: boolean;
}

/**
 * Preview da área de estampa na proporção real 49×30cm (horizontal).
 * Camadas: imagem do cliente → frase customizada → frase fixa.
 */
export default function ShirtPreview({
  corBase,
  fraseFixa,
  fraseCustomizada,
  imagemUrl,
  compacto = false,
}: Props) {
  const escura = corBase.toLowerCase() === "#17121f";
  const corTexto = escura ? "#FBFAF6" : "#17121F";

  return (
    <div
      className="relative w-full overflow-hidden rounded-xl border border-borda shadow-inner"
      style={{ aspectRatio: "49 / 30", backgroundColor: corBase }}
    >
      {/* etiqueta de medida */}
      <span
        className="absolute right-2 top-2 rounded-md px-2 py-0.5 text-[10px] font-semibold"
        style={{
          backgroundColor: escura ? "rgba(251,250,246,.15)" : "rgba(23,18,31,.08)",
          color: corTexto,
        }}
      >
        49 × 30 cm
      </span>

      <div className="absolute inset-0 flex flex-col items-center justify-center gap-1 p-4">
        {imagemUrl ? (
          <img
            src={imagemUrl}
            alt="Arte enviada pelo cliente"
            className="max-h-[55%] max-w-[70%] object-contain"
          />
        ) : (
          !compacto && (
            <div
              className="flex h-[55%] w-[60%] items-center justify-center rounded-lg border-2 border-dashed text-xs"
              style={{ borderColor: corTexto, color: corTexto, opacity: 0.4 }}
            >
              sua arte aqui
            </div>
          )
        )}

        {fraseCustomizada && (
          <p
            className={`display text-center ${compacto ? "text-sm" : "text-lg sm:text-xl"}`}
            style={{ color: corTexto }}
          >
            {fraseCustomizada}
          </p>
        )}

        <p
          className={`text-center font-medium ${compacto ? "text-[10px]" : "text-xs sm:text-sm"}`}
          style={{ color: corTexto, opacity: 0.75 }}
        >
          {fraseFixa}
        </p>
      </div>
    </div>
  );
}
