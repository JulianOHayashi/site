import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { mockProducts } from "../data/mockProducts";
import type { Product } from "../types";

export interface ProductWithState extends Product {
  preco_a: number;
  preco_b: number;
  restock_date: string | null;
  reserved: number;
}

interface ProdutoV3 {
  id: string;
  slug: string;
  name: string;
  short_description: string | null;
  active: boolean;
  display_order: number;
  product_customization_fields: {
    field_key: string;
    options: { fixed_value?: string } | null;
  }[];
  product_state_stock: {
    stock_quantity: number;
    reserved_quantity: number;
    restock_date: string | null;
    preco_a_cents: number;
    preco_b_cents: number;
    active: boolean;
  }[];
}

function mapear(p: ProdutoV3, state: string): ProductWithState {
  const campo = (k: string) =>
    p.product_customization_fields?.find((f) => f.field_key === k)?.options
      ?.fixed_value;

  const stock = p.product_state_stock?.find(() => true);

  return {
    id: p.id,
    slug: p.slug,
    nome: p.name,
    descricao: p.short_description ?? "",
    preco: (stock?.preco_a_cents ?? 0) / 100,
    preco_a: (stock?.preco_a_cents ?? 0) / 100,
    preco_b: (stock?.preco_b_cents ?? 0) / 100,
    frase_fixa: campo("frase_fixa") ?? "",
    cor_base: campo("cor_base") ?? "#FFFFFF",
    estoque: stock?.stock_quantity ?? 0,
    reserved: stock?.reserved_quantity ?? 0,
    restock_date: stock?.restock_date ?? null,
    ativo: p.active,
    state,
  };
}

export function useProductsByState(state: string) {
  const [products, setProducts] = useState<ProductWithState[]>([]);
  const [loading, setLoading] = useState(true);
  const demo = supabase === null;

  useEffect(() => {
    if (!state) return;

    if (!supabase) {
      // modo demonstração: usa mock com estado fictício
      setProducts(
        mockProducts.map((p) => ({
          ...p,
          preco_a: p.preco,
          preco_b: p.preco * 0.85,
          restock_date: null,
          reserved: 0,
          state,
        }))
      );
      setLoading(false);
      return;
    }

    let ativo = true;

    supabase
      .from("products")
      .select(
        `id, slug, name, short_description, active, display_order,
         product_customization_fields(field_key, options),
         product_state_stock!inner(
           stock_quantity, reserved_quantity, restock_date,
           preco_a_cents, preco_b_cents, active
         )`
      )
      .eq("active", true)
      .eq("product_state_stock.state", state)
      .eq("product_state_stock.active", true)
      .order("display_order")
      .then(({ data, error }) => {
        if (!ativo) return;
        if (error || !data) {
          console.error("Erro ao carregar produtos:", error);
          setLoading(false);
          return;
        }
        setProducts((data as unknown as ProdutoV3[]).map((p) => mapear(p, state)));
        setLoading(false);
      });

    // Estoque estadual ao vivo
    const channel = supabase
      .channel(`estoque-${state}`)
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "product_state_stock",
          filter: `state=eq.${state}`,
        },
        (payload) => {
          const novo = payload.new as {
            product_id: string;
            stock_quantity: number;
            reserved_quantity: number;
            restock_date: string | null;
          };
          setProducts((prev) =>
            prev.map((p) =>
              p.id === novo.product_id
                ? {
                    ...p,
                    estoque: novo.stock_quantity,
                    reserved: novo.reserved_quantity,
                    restock_date: novo.restock_date,
                  }
                : p
            )
          );
        }
      )
      .subscribe();

    return () => {
      ativo = false;
      supabase.removeChannel(channel);
    };
  }, [state]);

  return { products, loading, demo };
}
