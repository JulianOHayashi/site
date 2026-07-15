import { Link, useLocation, useNavigate } from "react-router-dom";
import Header from "../components/Header";
import DemoBanner from "../components/DemoBanner";
import { useProductsByState } from "../hooks/useProductsByState";
import { formatarPreco } from "../lib/format";

/** Badge de estoque estadual — compacta, dentro do card */
function EstoqueBadge({
  state,
  estoque,
  reserved,
  restockDate,
}: {
  state: string;
  estoque: number;
  reserved: number;
  restockDate: string | null;
}) {
  const disponiveis = estoque - reserved;

  if (disponiveis <= 0) {
    return (
      <span className="inline-flex items-center gap-1.5 rounded-full bg-tinta px-3 py-1 text-xs font-semibold text-white">
        Esgotado · {state}
        {restockDate && (
          <span className="opacity-70">
            · reposição{" "}
            {new Date(restockDate).toLocaleDateString("pt-BR", {
              day: "2-digit",
              month: "2-digit",
            })}
          </span>
        )}
      </span>
    );
  }
  if (disponiveis <= 20) {
    return (
      <span className="inline-flex items-center gap-1.5 rounded-full bg-amarelo px-3 py-1 text-xs font-semibold text-tinta">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-tinta" />
        {state} · últimas {disponiveis} un.
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-[#E8F7EE] px-3 py-1 text-xs font-semibold text-[#0B7A3E]">
      <span className="h-1.5 w-1.5 rounded-full bg-[#0B7A3E]" />
      {state} · {disponiveis} disponíveis
    </span>
  );
}

/** Preview da área de estampa (proporção 49:30) */
function ShirtCard({ corBase, nome }: { corBase: string; nome: string }) {
  const escura = corBase.toLowerCase() === "#17121f";
  return (
    <div
      className="relative w-full overflow-hidden rounded-2xl"
      style={{ aspectRatio: "49/30", backgroundColor: corBase }}
    >
      <span
        className="absolute right-3 top-3 rounded-md px-2 py-0.5 text-[10px] font-semibold"
        style={{
          backgroundColor: escura
            ? "rgba(251,250,246,0.12)"
            : "rgba(23,18,31,0.07)",
          color: escura ? "#FBFAF6" : "#17121F",
        }}
      >
        49 × 30 cm
      </span>
      <div className="absolute bottom-4 left-0 right-0 text-center">
        <span
          className="font-display text-sm font-bold tracking-wide opacity-30"
          style={{ color: escura ? "#FBFAF6" : "#17121F" }}
        >
          {nome}
        </span>
      </div>
    </div>
  );
}

const BORDAS_HOVER = [
  "hover:border-magenta hover:shadow-[0_8px_40px_rgba(229,0,126,0.18)]",
  "hover:border-ciano hover:shadow-[0_8px_40px_rgba(0,168,224,0.18)]",
  "hover:border-amarelo hover:shadow-[0_8px_40px_rgba(255,196,0,0.18)]",
];

export default function Produtos() {
  const location = useLocation();
  const navigate = useNavigate();
  const state = (location.state as { estado?: string })?.estado ?? "ES";
  const { products, loading, demo } = useProductsByState(state);

  return (
    <>
      <Header />
      <DemoBanner />
      <main className="mx-auto max-w-6xl px-4 pb-24 pt-12">
        {/* Cabeçalho da vitrine */}
        <div className="mb-10 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
              {state} — Vitrine de modelos
            </p>
            <h1 className="mt-2 text-3xl sm:text-5xl">Escolha o modelo</h1>
            <p className="mt-2 text-tinta/60">
              Tamanho único · Área de estampa horizontal 49×30cm · Mínimo 10 unidades
            </p>
          </div>
          <button
            onClick={() => navigate(-1)}
            className="rounded-xl border-2 border-borda px-4 py-2 text-sm font-semibold transition hover:border-tinta"
          >
            ← Trocar estado
          </button>
        </div>

        {loading ? (
          <div className="flex h-64 items-center justify-center">
            <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
          </div>
        ) : products.length === 0 ? (
          <div className="rounded-3xl border border-dashed border-borda p-16 text-center">
            <p className="text-lg font-semibold">
              Nenhum produto disponível em {state} no momento.
            </p>
            <p className="mt-2 text-sm text-tinta/60">
              Verifique outros estados ou entre em contato.
            </p>
          </div>
        ) : (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {products.map((p, i) => {
              const disponiveis = p.estoque - p.reserved;
              const esgotado = disponiveis <= 0;

              return (
                <article key={p.id} className="group flex flex-col">
                  <Link
                    to={`/produto/${p.slug}`}
                    state={{ estado: state }}
                    aria-disabled={false}
                    className={`flex flex-col rounded-3xl border-2 border-borda bg-white p-5 shadow-sm transition duration-300 ${
                      BORDAS_HOVER[i % 3]
                    } ${esgotado ? "opacity-75" : ""}`}
                  >
                    {/* Preview da camisa */}
                    <ShirtCard corBase={p.cor_base} nome={p.nome} />

                    {/* Informações */}
                    <div className="mt-5 flex flex-1 flex-col gap-3">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <h2 className="text-xl font-bold">{p.nome}</h2>
                          <p className="mt-0.5 text-sm text-tinta/60 line-clamp-2">
                            {p.descricao}
                          </p>
                        </div>
                      </div>

                      {/* Preço — mostra só o do perfil do cliente */}
                      <div>
                        <p className="text-2xl font-bold">
                          {formatarPreco(p.preco_a)}
                          <span className="ml-1.5 text-sm font-normal text-tinta/40">
                            / un.
                          </span>
                        </p>
                        <p className="text-xs text-tinta/50">
                          A partir de {formatarPreco(p.preco_b)}/un. com fidelidade
                        </p>
                      </div>

                      {/* Badge de estoque por estado */}
                      <div className="mt-auto pt-1">
                        <EstoqueBadge
                          state={state}
                          estoque={p.estoque}
                          reserved={p.reserved}
                          restockDate={p.restock_date}
                        />
                      </div>

                      {/* CTA esgotado */}
                      {esgotado && (
                        <Link
                          to={`/produto/${p.slug}`}
                          state={{ estado: state, preOrder: true }}
                          className="mt-2 w-full rounded-xl border-2 border-tinta bg-transparent py-2.5 text-center text-sm font-semibold transition hover:bg-tinta hover:text-white"
                          onClick={(e) => e.stopPropagation()}
                        >
                          Pré-pedido para {p.restock_date
                            ? new Date(p.restock_date).toLocaleDateString("pt-BR", {
                                month: "long",
                              })
                            : "próxima reposição"}
                        </Link>
                      )}
                    </div>
                  </Link>
                </article>
              );
            })}
          </div>
        )}

        {demo && (
          <p className="mt-8 text-center text-xs text-tinta/40">
            Modo demonstração — conecte o Supabase para ver o estoque real por estado.
          </p>
        )}
      </main>
    </>
  );
}
