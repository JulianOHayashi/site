import { Link } from "react-router-dom";
import Header from "../components/Header";
import DemoBanner from "../components/DemoBanner";
import ShirtPreview from "../components/ShirtPreview";
import EstoqueBadge from "../components/EstoqueBadge";
import { useProducts } from "../hooks/useProducts";
import { formatarPreco } from "../lib/format";

const TINTAS = [
  "hover:border-magenta",
  "hover:border-ciano",
  "hover:border-amarelo",
];

export default function Produtos() {
  const { products, loading } = useProducts();

  return (
    <>
      <Header />
      <DemoBanner />
      <main className="mx-auto max-w-6xl px-4 pb-20 pt-10">
        <h1 className="text-3xl sm:text-5xl">Escolha o modelo</h1>
        <p className="mt-2 text-tinta/70">
          Tamanho único · Área de estampa horizontal de 49×30cm
        </p>

        {loading ? (
          <div className="mt-16 flex justify-center">
            <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
          </div>
        ) : (
          <div className="mt-10 grid gap-6 md:grid-cols-3">
            {products.map((p, i) => {
              const esgotado = p.estoque === 0;
              return (
                <Link
                  key={p.id}
                  to={esgotado ? "#" : `/produto/${p.slug}`}
                  aria-disabled={esgotado}
                  onClick={(e) => esgotado && e.preventDefault()}
                  className={`card group block border-2 border-transparent p-4 transition ${
                    esgotado
                      ? "cursor-not-allowed opacity-60"
                      : `hover:-translate-y-1 hover:shadow-lg ${TINTAS[i % 3]}`
                  }`}
                >
                  <ShirtPreview
                    corBase={p.cor_base}
                    fraseFixa={p.frase_fixa}
                    compacto
                  />
                  <div className="mt-4 flex items-start justify-between gap-2">
                    <div>
                      <h2 className="text-xl">{p.nome}</h2>
                      <p className="mt-1 text-lg font-bold">
                        {formatarPreco(p.preco)}
                        <span className="ml-2 align-middle rounded bg-papel2 px-1.5 py-0.5 text-[10px] font-medium text-tinta/60">
                          preço provisório
                        </span>
                      </p>
                    </div>
                  </div>
                  <div className="mt-3">
                    <EstoqueBadge estoque={p.estoque} />
                  </div>
                </Link>
              );
            })}
          </div>
        )}
      </main>
    </>
  );
}
