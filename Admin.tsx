import { useMemo, useState } from "react";
import Header from "../components/Header";
import EstoqueBadge from "../components/EstoqueBadge";
import { useProducts } from "../hooks/useProducts";
import { mockOrders } from "../data/mockOrders";
import type { Order, OrderStatus } from "../types";

/*
 * ⚠️ Painel em modo demonstração (dados mock, sem login).
 * TODOs futuros:
 * - Proteger com Supabase Auth (role admin)
 * - Ler/atualizar pedidos reais na tabela orders
 * - Envio automático de email ao cliente a cada mudança de status
 * - Reposição de estoque via RPC protegida
 */

const STATUS_LABEL: Record<OrderStatus, string> = {
  recebido: "Recebido",
  em_producao: "Em produção",
  enviado: "Enviado",
};

const STATUS_COR: Record<OrderStatus, string> = {
  recebido: "bg-amarelo text-tinta",
  em_producao: "bg-ciano text-white",
  enviado: "bg-magenta text-white",
};

const PROXIMO: Record<OrderStatus, OrderStatus | null> = {
  recebido: "em_producao",
  em_producao: "enviado",
  enviado: null,
};

export default function Admin() {
  const { products } = useProducts();
  const [orders, setOrders] = useState<Order[]>(mockOrders);
  const [filtroStatus, setFiltroStatus] = useState<"todos" | OrderStatus>(
    "todos"
  );
  const [filtroEstado, setFiltroEstado] = useState("todos");
  const [aviso, setAviso] = useState<string | null>(null);

  const estados = useMemo(
    () => Array.from(new Set(orders.map((o) => o.estado))),
    [orders]
  );

  const visiveis = orders.filter(
    (o) =>
      (filtroStatus === "todos" || o.status === filtroStatus) &&
      (filtroEstado === "todos" || o.estado === filtroEstado)
  );

  const contar = (s: OrderStatus) =>
    orders.filter((o) => o.status === s).length;

  const notificar = (msg: string) => {
    setAviso(msg);
    window.setTimeout(() => setAviso(null), 4000);
  };

  const aprovarImagem = (id: string) => {
    setOrders((prev) =>
      prev.map((o) => (o.id === id ? { ...o, imagemAprovada: true } : o))
    );
    notificar(`Imagem do pedido ${id} aprovada para produção.`);
  };

  const avancarStatus = (id: string) => {
    setOrders((prev) =>
      prev.map((o) => {
        if (o.id !== id) return o;
        const prox = PROXIMO[o.status];
        if (!prox) return o;
        if (prox === "em_producao" && !o.imagemAprovada) {
          notificar("Aprove a imagem antes de enviar para produção.");
          return o;
        }
        notificar(
          `Pedido ${id} → ${STATUS_LABEL[prox]}. Email automático ao cliente será enviado (integração a configurar).`
        );
        return { ...o, status: prox };
      })
    );
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-6xl px-4 pb-20 pt-10">
        <h1 className="text-3xl sm:text-4xl">Painel de pedidos</h1>

        {/* CONTADORES */}
        <div className="mt-6 flex flex-wrap gap-3">
          {(Object.keys(STATUS_LABEL) as OrderStatus[]).map((s) => (
            <div
              key={s}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold ${STATUS_COR[s]}`}
            >
              {STATUS_LABEL[s]}: {contar(s)}
            </div>
          ))}
        </div>

        {/* ESTOQUE */}
        <section className="card mt-8 p-5">
          <h2 className="text-xl">Estoque</h2>
          <div className="mt-3 grid gap-3 sm:grid-cols-3">
            {products.map((p) => (
              <div
                key={p.id}
                className="flex items-center justify-between rounded-xl bg-papel2 px-4 py-3"
              >
                <span className="font-medium">{p.nome}</span>
                <EstoqueBadge estoque={p.estoque} />
              </div>
            ))}
          </div>
          <p className="mt-3 text-xs text-tinta/50">
            Reposição de estoque: pelo painel do Supabase por enquanto (RPC
            protegida virá com o login de admin).
          </p>
        </section>

        {/* FILTROS */}
        <div className="mt-8 flex flex-wrap gap-3">
          <select
            value={filtroStatus}
            onChange={(e) =>
              setFiltroStatus(e.target.value as "todos" | OrderStatus)
            }
            className="rounded-xl border border-borda bg-white px-4 py-2.5 text-sm font-medium outline-none focus:border-ciano"
            aria-label="Filtrar por status"
          >
            <option value="todos">Todos os status</option>
            <option value="recebido">Recebido</option>
            <option value="em_producao">Em produção</option>
            <option value="enviado">Enviado</option>
          </select>
          <select
            value={filtroEstado}
            onChange={(e) => setFiltroEstado(e.target.value)}
            className="rounded-xl border border-borda bg-white px-4 py-2.5 text-sm font-medium outline-none focus:border-ciano"
            aria-label="Filtrar por estado"
          >
            <option value="todos">Todos os estados</option>
            {estados.map((uf) => (
              <option key={uf} value={uf}>
                {uf}
              </option>
            ))}
          </select>
        </div>

        {/* TABELA (vira cards no mobile via overflow) */}
        <div className="card mt-4 overflow-x-auto">
          <table className="w-full min-w-[820px] text-left text-sm">
            <thead>
              <tr className="border-b border-borda text-xs uppercase tracking-wider text-tinta/50">
                <th className="px-4 py-3">Pedido</th>
                <th className="px-4 py-3">Empresa</th>
                <th className="px-4 py-3">UF</th>
                <th className="px-4 py-3">Produto</th>
                <th className="px-4 py-3">Frase</th>
                <th className="px-4 py-3">Imagem</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Ações</th>
              </tr>
            </thead>
            <tbody>
              {visiveis.map((o) => (
                <tr key={o.id} className="border-b border-borda/60">
                  <td className="px-4 py-3 font-semibold">{o.id}</td>
                  <td className="px-4 py-3">
                    {o.empresa}
                    <span className="block text-xs text-tinta/50">
                      {o.cnpj}
                    </span>
                  </td>
                  <td className="px-4 py-3">{o.estado}</td>
                  <td className="px-4 py-3">{o.produto}</td>
                  <td className="px-4 py-3">“{o.fraseCustomizada}”</td>
                  <td className="px-4 py-3">
                    {o.imagemAprovada ? (
                      <span className="rounded-full bg-[#E8F7EE] px-2.5 py-1 text-xs font-semibold text-[#0B7A3E]">
                        Aprovada
                      </span>
                    ) : (
                      <button
                        onClick={() => aprovarImagem(o.id)}
                        className="rounded-full bg-amarelo px-2.5 py-1 text-xs font-semibold text-tinta hover:brightness-95"
                      >
                        Aprovar imagem
                      </button>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_COR[o.status]}`}
                    >
                      {STATUS_LABEL[o.status]}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => avancarStatus(o.id)}
                      disabled={o.status === "enviado"}
                      className="rounded-xl border-2 border-tinta px-3 py-1.5 text-xs font-semibold transition hover:bg-tinta hover:text-white disabled:cursor-not-allowed disabled:border-borda disabled:text-tinta/30 disabled:hover:bg-transparent"
                    >
                      Avançar status
                    </button>
                  </td>
                </tr>
              ))}
              {visiveis.length === 0 && (
                <tr>
                  <td
                    colSpan={8}
                    className="px-4 py-10 text-center text-tinta/50"
                  >
                    Nenhum pedido com esses filtros.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </main>

      {/* TOAST */}
      {aviso && (
        <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-full bg-tinta px-5 py-2.5 text-sm font-medium text-white shadow-xl">
          {aviso}
        </div>
      )}
    </>
  );
}
