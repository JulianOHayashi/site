import { useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import Header from "../components/Header";
import ShirtPreview from "../components/ShirtPreview";
import { useProducts } from "../hooks/useProducts";

const LIMITE_FRASE = 20; // ⚠️ limite exato A DEFINIR (~20 caracteres)

export default function Personalizar() {
  const { slug } = useParams();
  const navigate = useNavigate();
  const { products, loading } = useProducts();
  const produto = products.find((p) => p.slug === slug);

  const inputRef = useRef<HTMLInputElement>(null);
  const [imagemUrl, setImagemUrl] = useState<string | null>(null);
  const [frase, setFrase] = useState("");
  const [arrastando, setArrastando] = useState(false);

  const receberArquivo = (file: File | undefined) => {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      alert("Envie um arquivo de imagem (PNG, JPG ou SVG).");
      return;
    }
    setImagemUrl(URL.createObjectURL(file));
  };

  if (loading) {
    return (
      <>
        <Header />
        <div className="mt-24 flex justify-center">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
        </div>
      </>
    );
  }

  if (!produto) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-3xl px-4 py-24 text-center">
          <h1 className="text-3xl">Modelo não encontrado</h1>
          <Link to="/produtos" className="btn-secondary mt-6">
            Ver todos os modelos
          </Link>
        </main>
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto grid max-w-6xl gap-10 px-4 pb-20 pt-10 lg:grid-cols-2 lg:items-start">
        {/* PREVIEW AO VIVO */}
        <section>
          <h1 className="mb-4 text-2xl sm:text-3xl">
            Personalize o {produto.nome}
          </h1>
          <ShirtPreview
            corBase={produto.cor_base}
            fraseFixa={produto.frase_fixa}
            fraseCustomizada={frase}
            imagemUrl={imagemUrl}
          />
          <p className="mt-2 text-xs text-tinta/50">
            Preview ilustrativo da área de estampa (49×30cm). A arte final é
            revisada pela nossa equipe antes da produção.
          </p>
        </section>

        {/* CONTROLES */}
        <section className="space-y-6 lg:pt-14">
          {/* 1. Upload */}
          <div>
            <label className="mb-2 block font-semibold">Sua arte</label>
            <div
              role="button"
              tabIndex={0}
              onClick={() => inputRef.current?.click()}
              onKeyDown={(e) =>
                (e.key === "Enter" || e.key === " ") &&
                inputRef.current?.click()
              }
              onDragOver={(e) => {
                e.preventDefault();
                setArrastando(true);
              }}
              onDragLeave={() => setArrastando(false)}
              onDrop={(e) => {
                e.preventDefault();
                setArrastando(false);
                receberArquivo(e.dataTransfer.files?.[0]);
              }}
              className={`flex cursor-pointer flex-col items-center justify-center rounded-2xl border-2 border-dashed p-8 text-center transition ${
                arrastando
                  ? "border-ciano bg-ciano/5"
                  : "border-borda bg-white hover:border-ciano"
              }`}
            >
              <p className="font-semibold">
                {imagemUrl ? "Trocar imagem" : "Arraste sua imagem aqui"}
              </p>
              <p className="mt-1 text-sm text-tinta/60">
                ou clique para escolher · PNG, JPG ou SVG
              </p>
              <input
                ref={inputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => receberArquivo(e.target.files?.[0])}
              />
            </div>
          </div>

          {/* 2. Frase fixa (somente leitura) */}
          <div>
            <label className="mb-2 block font-semibold">
              Frase fixa do modelo{" "}
              <span className="font-normal text-tinta/50">
                — definida pela loja
              </span>
            </label>
            <input
              value={produto.frase_fixa}
              readOnly
              className="w-full cursor-not-allowed rounded-xl border border-borda bg-papel2 px-4 py-3 text-tinta/70"
            />
          </div>

          {/* 3. Frase personalizada */}
          <div>
            <label htmlFor="frase" className="mb-2 block font-semibold">
              Sua frase{" "}
              <span className="font-normal text-tinta/50">
                — até {LIMITE_FRASE} caracteres
              </span>
            </label>
            <div className="relative">
              <input
                id="frase"
                value={frase}
                maxLength={LIMITE_FRASE}
                onChange={(e) => setFrase(e.target.value)}
                placeholder="Ex.: Desde 1998"
                className="w-full rounded-xl border border-borda bg-white px-4 py-3 pr-16 outline-none transition focus:border-ciano"
              />
              <span className="absolute right-4 top-1/2 -translate-y-1/2 text-xs font-semibold text-tinta/50">
                {frase.length}/{LIMITE_FRASE}
              </span>
            </div>
          </div>

          {/* Avançar */}
          <button
            className="btn-primary w-full"
            disabled={!imagemUrl}
            onClick={() =>
              navigate("/checkout", {
                state: {
                  productSlug: produto.slug,
                  imagemUrl,
                  fraseCustomizada: frase,
                },
              })
            }
          >
            Continuar para o pagamento
          </button>
          {!imagemUrl && (
            <p className="text-center text-xs text-tinta/50">
              Envie sua arte para continuar.
            </p>
          )}
        </section>
      </main>
    </>
  );
}
