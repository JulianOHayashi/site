import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { mockProducts } from "../data/mockProducts";
import type { Product } from "../types";

/**
 * Fonte de produtos + estoque.
 * - Com Supabase configurado: lê do banco e assina Realtime — o estoque
 *   na tela atualiza sozinho quando uma compra acontece.
 * - Sem Supabase: usa dados de demonstração (mock) para o site já rodar.
 */
export function useProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const demo = supabase === null;

  useEffect(() => {
    if (!supabase) {
      setProducts(mockProducts);
      setLoading(false);
      return;
    }

    let ativo = true;

    supabase
      .from("products")
      .select("*")
      .eq("ativo", true)
      .order("preco")
      .then(({ data, error }) => {
        if (!ativo) return;
        if (error || !data) {
          console.error("Erro ao carregar produtos:", error);
          setProducts(mockProducts); // fallback
        } else {
          setProducts(data as Product[]);
        }
        setLoading(false);
      });

    const channel = supabase
      .channel("estoque-produtos")
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "products" },
        (payload) => {
          const atualizado = payload.new as Product;
          setProducts((prev) =>
            prev.map((p) => (p.id === atualizado.id ? atualizado : p))
          );
        }
      )
      .subscribe();

    return () => {
      ativo = false;
      supabase.removeChannel(channel);
    };
  }, []);

  return { products, loading, demo };
}
