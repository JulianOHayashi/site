import { Link, useParams } from "react-router-dom";
import Header from "../components/Header";
import ShirtPreview from "../components/ShirtPreview";
import EstoqueBadge from "../components/EstoqueBadge";
import { useProductsByState } from "../hooks/useProductsByState";
import { obterUF } from "../lib/estado";
import { formatarPreco } from "../lib/format";

export default function ProdutoDetalhe() {
  const { slug } = useParams();
  const { products, loading } = useProductsByState(obterUF() ?? "");
  const produto = products.find((p) => p.slug === slug);

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

  const esgotado = produto.estoque === 0;

  return (
    <>
      <Header />
      <main className="mx-auto grid max-w-6xl gap-10 px-4 pb-20 pt-10 md:grid-cols-2 md:items-start">
        <ShirtPreview
          corBase={produto.cor_base}
          fraseFixa={produto.frase_fixa}
        />

        <div>
          <h1 className="text-3xl sm:text-5xl">{produto.nome}</h1>
          <div className="mt-3 flex items-center gap-3">
            <p className="text-2xl font-bold">{formatarPreco(produto.preco)}</p>
            <EstoqueBadge estoque={produto.estoque} />
          </div>

          <p className="mt-5 text-tinta/80">{produto.descricao}</p>

          <div className="card mt-6 space-y-2 p-5 text-sm">
            <p>
              <span className="font-semibold">Tamanho:</span> único
            </p>
            <p>
              <span className="font-semibold">Frase fixa incluída:</span>{" "}
              <em>“{produto.frase_fixa}”</em>
            </p>
            <p>
              <span className="font-semibold">Área de estampa:</span> 49 × 30
              cm (horizontal)
            </p>
          </div>

          <Link
            to={esgotado ? "#" : `/personalizar/${produto.slug}`}
            aria-disabled={esgotado}
            onClick={(e) => esgotado && e.preventDefault()}
            className={`btn-primary mt-7 w-full sm:w-auto ${
              esgotado ? "pointer-events-none bg-gray-300 text-gray-500" : ""
            }`}
          >
            {esgotado ? "Esgotado" : "Personalizar esta camisa"}
          </Link>

          {/* TODO: regras de parcelamento — A DEFINIR */}
          <p className="mt-3 text-xs text-tinta/50">
            Parcelamento: condições a definir.
          </p>
        </div>
      </main>
    </>
  );
}
