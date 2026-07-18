import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import Header from "../components/Header";
import ShirtPreview from "../components/ShirtPreview";
import { useProductsByState } from "../hooks/useProductsByState";
import { obterUF } from "../lib/estado";
import { formatarPreco } from "../lib/format";
import {
  QUANTIDADE_MINIMA,
  FAIXAS_PADRAO,
  carregarFaixas,
  descontoPorQuantidade,
  proximaFaixa,
  type Faixa,
} from "../lib/precificacao";

const LIMITE_FRASE = 20; // ⚠️ limite exato A DEFINIR (~20 caracteres)

export default function Personalizar() {
  const { slug } = useParams();
  const navigate = useNavigate();
  const { products, loading } = useProductsByState(obterUF() ?? "");
  const produto = products.find((p) => p.slug === slug);

  const inputRef = useRef<HTMLInputElement>(null);
  const [imagemUrl, setImagemUrl] = useState<string | null>(null);
  const [frase, setFrase] = useState("");
  const [arrastando, setArrastando] = useState(false);
  const [quantidade, setQuantidade] = useState(QUANTIDADE_MINIMA);
  const [faixas, setFaixas] = useState<Faixa[]>(FAIXAS_PADRAO);

  useEffect(() => {
    carregarFaixas().then(setFaixas);
  }, []);

  const receberArquivo = (file: File | undefined) => {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      alert("Envie um arquivo de imagem (PNG, JPG ou SVG).");
      return;
    }
    setImagemUrl(URL.createObjectURL(file));
  };

  const mudarQuantidade = (delta: number) =>
    setQuantidade((q) => Math.max(QUANTIDADE_MINIMA, q + delta));

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

  const descVolume = descontoPorQuantidade(quantidade, faixas);
  const proxima = proximaFaixa(quantidade, faixas);
  const precoUnitario = produto.preco * (1 - descVolume / 100);
  const totalEstimado = precoUnitario * quantidade;

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

          {/* 4. Quantidade — mínimo 10, preço cai por volume */}
          <div>
            <label className="mb-2 block font-semibold">
              Quantidade{" "}
              <span className="font-normal text-tinta/50">
                — mínimo {QUANTIDADE_MINIMA} unidades
              </span>
            </label>
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={() => mudarQuantidade(-5)}
                disabled={quantidade <= QUANTIDADE_MINIMA}
                aria-label="Diminuir 5 unidades"
                className="flex h-12 w-12 items-center justify-center rounded-xl border-2 border-tinta text-xl font-bold transition hover:bg-tinta hover:text-white disabled:cursor-not-allowed disabled:border-borda disabled:text-tinta/30 disabled:hover:bg-transparent"
              >
                −
              </button>
              <input
                type="number"
                min={QUANTIDADE_MINIMA}
                value={quantidade}
                onChange={(e) =>
                  setQuantidade(
                    Math.max(
                      QUANTIDADE_MINIMA,
                      parseInt(e.target.value || "0", 10) || QUANTIDADE_MINIMA
                    )
                  )
                }
                className="h-12 w-24 rounded-xl border border-borda bg-white text-center font-display text-lg font-bold outline-none focus:border-ciano"
              />
              <button
                type="button"
                onClick={() => mudarQuantidade(5)}
                aria-label="Aumentar 5 unidades"
                className="flex h-12 w-12 items-center justify-center rounded-xl border-2 border-tinta text-xl font-bold transition hover:bg-tinta hover:text-white"
              >
                +
              </button>

              {descVolume > 0 && (
                <span className="rounded-full bg-[#E8F7EE] px-3 py-1.5 text-xs font-bold text-[#0B7A3E]">
                  −{descVolume}% por volume
                </span>
              )}
            </div>

            {/* dica da próxima faixa */}
            {proxima && (
              <p className="mt-2 text-xs text-tinta/50">
                💡 Faltam{" "}
                <span className="font-bold text-tinta">
                  {proxima.min - quantidade} unidades
                </span>{" "}
                para {proxima.pct}% de desconto por volume.
              </p>
            )}

            {/* preço estimado ao vivo */}
            <div className="mt-3 flex items-baseline justify-between rounded-2xl bg-papel2 px-4 py-3">
              <span className="text-sm text-tinta/60">
                {formatarPreco(precoUnitario)} / un. × {quantidade}
                <span className="ml-1 text-tinta/40">(valores provisórios)</span>
              </span>
              <span className="font-display text-xl font-bold">
                {formatarPreco(totalEstimado)}
              </span>
            </div>
            <p className="mt-1 text-xs text-tinta/40">
              Cliente que já comprou ganha desconto fidelidade adicional no
              checkout, identificado pelo CNPJ.
            </p>
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
                  quantidade,
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
