import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

export interface PrecoPedido {
  units_a: number;
  preco_a_cents: number;
  units_b: number;
  preco_b_cents: number;
  total_cents: number;
  preco_unitario_exibido: number;
}

export interface FidelidadeInfo {
  status: "primeira_compra" | "fidelizado";
  units_paid: number;
}

/** Preço exibido ao cliente: preço A se primeira compra, B se fidelizado */
export function usePrecoPorPerfil(
  cnpj: string,
  state: string
): { preco_exibido: "A" | "B"; loading: boolean } {
  const [preco, setPreco] = useState<"A" | "B">("A");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!cnpj || !state || !supabase) return;
    setLoading(true);
    supabase
      .rpc("status_fidelidade", { p_cnpj: cnpj, p_state: state })
      .then(({ data }) => {
        setPreco(data === "fidelizado" ? "B" : "A");
        setLoading(false);
      });
  }, [cnpj, state]);

  return { preco_exibido: preco, loading };
}

/** Cálculo completo A/B para exibir no checkout */
export async function calcularPrecoPedido(
  cnpj: string,
  state: string,
  productId: string,
  quantidade: number
): Promise<PrecoPedido | null> {
  if (!supabase) return null;
  const { data, error } = await supabase.rpc("calcular_preco_pedido", {
    p_cnpj: cnpj,
    p_state: state,
    p_product_id: productId,
    p_quantidade: quantidade,
  });
  if (error) { console.error(error); return null; }
  return data as PrecoPedido;
}

/** Verifica se cancelar um pedido vai causar cascata */
export async function verificarCascata(orderId: string) {
  if (!supabase) return null;
  const { data } = await supabase.rpc("verificar_cascata", {
    p_order_id: orderId,
  });
  return data;
}
