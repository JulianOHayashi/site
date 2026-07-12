import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../components/Header";
import { supabase } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";
import { formatarPreco } from "../lib/format";

/**
 * PAINEL DO PARCEIRO (rota protegida — exige login).
 *
 * - No primeiro acesso, cria o registro em `profiles` a partir dos
 *   dados do cadastro (nome da empresa + CNPJ do user_metadata) —
 *   isso liga o parceiro ao desconto fidelidade automaticamente.
 * - Mostra: dados da empresa, status de fidelidade, histórico de
 *   pedidos (RLS garante que cada um vê só os seus) e espaços de
 *   conteúdo do parceiro (⚠️ A DEFINIR: mídia kit, materiais...).
 */

interface Perfil {
  cnpj: string;
  nome_empresa: string | null;
}

interface PedidoResumo {
  id: string;
  quantidade: number;
  status: string;
  preco_final: number | null;
  criado_em: string;
  products: { nome: string } | null;
}

const STATUS_LABEL: Record<string, string> = {
  recebido: "Recebido",
  em_producao: "Em produção",
  enviado: "Enviado",
};

export default function ParceirosPainel() {
  const navigate = useNavigate();
  const { session, carregando } = useAuth();
  const [perfil, setPerfil] = useState<Perfil | null>(null);
  const [pedidos, setPedidos] = useState<PedidoResumo[]>([]);
  const [fidelidade, setFidelidade] = useState<number>(0);
  const [carregandoDados, setCarregandoDados] = useState(true);

  // proteção da rota
  useEffect(() => {
    if (!carregando && !session) navigate("/parceiros");
  }, [carregando, session, navigate]);

  // carrega (ou cria) o perfil + pedidos + fidelidade
  useEffect(() => {
    if (!supabase || !session) return;
    let ativo = true;

    (async () => {
      const uid = session.user.id;

      // 1. perfil — cria no primeiro acesso a partir do cadastro
      let { data: p } = await supabase
        .from("profiles")
        .select("cnpj, nome_empresa")
        .eq("id", uid)
        .maybeSingle();

      if (!p) {
        const meta = session.user.user_metadata as {
          cnpj?: string;
          nome_empresa?: string;
        };
        if (meta?.cnpj) {
          const { data: novo } = await supabase
            .from("profiles")
            .insert({
              id: uid,
              cnpj: meta.cnpj,
              nome_empresa: meta.nome_empresa ?? null,
              email: session.user.email,
            })
            .select("cnpj, nome_empresa")
            .single();
          p = novo;
        }
      }
      if (ativo && p) setPerfil(p as Perfil);

      // 2. fidelidade
      if (p?.cnpj) {
        const { data: pct } = await supabase.rpc("desconto_para_cnpj", {
          p_cnpj: p.cnpj,
        });
        if (ativo && typeof pct === "number") setFidelidade(pct);
      }

      // 3. pedidos (RLS: só os do próprio usuário)
      const { data: peds } = await supabase
        .from("orders")
        .select("id, quantidade, status, preco_final, criado_em, products(nome)")
        .order("criado_em", { ascending: false });
      if (ativo && peds) setPedidos(peds as unknown as PedidoResumo[]);

      if (ativo) setCarregandoDados(false);
    })();

    return () => {
      ativo = false;
    };
  }, [session]);

  const sair = async () => {
    await supabase?.auth.signOut();
    navigate("/");
  };

  if (carregando || (session && carregandoDados)) {
    return (
      <>
        <Header />
        <div className="mt-24 flex justify-center">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
        </div>
      </>
    );
  }

  if (!session) return null; // redirecionando

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 className="text-3xl sm:text-4xl">
              Olá, {perfil?.nome_empresa ?? "parceiro"}!
            </h1>
            <p className="mt-1 text-sm text-tinta/60">
              {perfil?.cnpj ? `CNPJ ${perfil.cnpj}` : session.user.email}
            </p>
          </div>
          <button
            onClick={sair}
            className="rounded-xl border-2 border-tinta px-4 py-2 text-sm font-semibold transition hover:bg-tinta hover:text-white"
          >
            Sair
          </button>
        </div>

        {/* FIDELIDADE */}
        <section className="mt-8">
          {fidelidade > 0 ? (
            <div className="rounded-3xl border-2 border-green-200 bg-green-50 p-6">
              <p className="font-display text-xl font-bold text-green-800">
                💚 Parceiro fidelidade: {fidelidade}% de desconto ativo
              </p>
              <p className="mt-1 text-sm text-green-800/80">
                Aplicado automaticamente em todos os novos pedidos, por cima do
                desconto de volume.
              </p>
            </div>
          ) : (
            <div className="rounded-3xl bg-papel2 p-6">
              <p className="font-display text-xl font-bold">
                💛 Sua primeira compra libera a fidelidade
              </p>
              <p className="mt-1 text-sm text-tinta/70">
                A partir do segundo pedido, seu CNPJ ganha desconto automático —
                por cima do desconto de volume, que já vale desde já.
              </p>
            </div>
          )}
        </section>

        {/* PEDIDOS */}
        <section className="mt-8">
          <h2 className="text-2xl">Seus pedidos</h2>
          {pedidos.length === 0 ? (
            <div className="card mt-4 p-8 text-center text-sm text-tinta/60">
              Nenhum pedido ainda.{" "}
              <Link to="/produtos" className="font-semibold text-ciano hover:underline">
                Conheça os modelos →
              </Link>
            </div>
          ) : (
            <div className="card mt-4 overflow-x-auto">
              <table className="w-full min-w-[560px] text-left text-sm">
                <thead>
                  <tr className="border-b border-borda text-xs uppercase tracking-wider text-tinta/50">
                    <th className="px-4 py-3">Data</th>
                    <th className="px-4 py-3">Produto</th>
                    <th className="px-4 py-3">Qtd.</th>
                    <th className="px-4 py-3">Total</th>
                    <th className="px-4 py-3">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {pedidos.map((p) => (
                    <tr key={p.id} className="border-b border-borda/60">
                      <td className="px-4 py-3">
                        {new Date(p.criado_em).toLocaleDateString("pt-BR")}
                      </td>
                      <td className="px-4 py-3">{p.products?.nome ?? "—"}</td>
                      <td className="px-4 py-3">{p.quantidade} un.</td>
                      <td className="px-4 py-3 font-semibold">
                        {p.preco_final != null ? formatarPreco(p.preco_final) : "—"}
                      </td>
                      <td className="px-4 py-3">
                        <span className="rounded-full bg-papel2 px-2.5 py-1 text-xs font-semibold">
                          {STATUS_LABEL[p.status] ?? p.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        {/* ÁREA DO PARCEIRO — conteúdo a definir */}
        <section className="mt-8">
          <h2 className="text-2xl">Materiais do parceiro</h2>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            {/* ⚠️ CONTEÚDO A DEFINIR — mídia kit, tabelas, materiais de anúncio */}
            <div className="rounded-3xl border border-dashed border-borda bg-white/70 p-6 text-sm text-tinta/50">
              📄 Mídia kit e formatos de anúncio
              <span className="mt-1 block text-xs">(⚠️ conteúdo a definir)</span>
            </div>
            <div className="rounded-3xl border border-dashed border-borda bg-white/70 p-6 text-sm text-tinta/50">
              🎨 Materiais e guias de arte para estampa
              <span className="mt-1 block text-xs">(⚠️ conteúdo a definir)</span>
            </div>
          </div>
        </section>
      </main>
    </>
  );
}
