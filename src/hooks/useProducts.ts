import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { mockProducts } from "../data/mockProducts";
import type { Product } from "../types";

/**
 * Fonte de produtos — ADAPTADOR para o schema v2 do site
 * (site-schema-v2.sql: products em inglês + campos de customização).
 *
 * O visual do site NÃO muda: este hook mapeia o schema novo para o
 * formato que as páginas já consomem (nome, preco, estoque,
 * frase_fixa, cor_base). Sem Supabase → dados de demonstração.
 */

interface ProdutoV2 {
  id: string;
  slug: string;
  name: string;
  short_description: string | null;
  base_price_cents: number | null;
  stock_quantity: number | null;
  stock_enabled: boolean | null;
  active: boolean;
  product_customization_fields: {
    field_key: string;
    options: { fixed_value?: string } | null;
  }[];
}

function mapear(p: ProdutoV2): Product {
  const campo = (k: string) =>
    p.product_customization_fields?.find((f) => f.field_key === k)?.options
      ?.fixed_value;
  return {
    id: p.id,
    slug: p.slug,
    nome: p.name,
    descricao: p.short_description ?? "",
    preco: (p.base_price_cents ?? 0) / 100,
    frase_fixa: campo("frase_fixa") ?? "",
    cor_base: campo("cor_base") ?? "#FFFFFF",
    estoque: p.stock_enabled === false ? 9999 : (p.stock_quantity ?? 0),
    ativo: p.active,
  };
}

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
      .select(
        "id, slug, name, short_description, base_price_cents, stock_quantity, stock_enabled, active, product_customization_fields(field_key, options)"
      )
      .eq("active", true)
      .order("display_order")
      .then(({ data, error }) => {
        if (!ativo) return;
        if (error || !data) {
          console.error("Erro ao carregar produtos:", error);
          setProducts(mockProducts); // fallback
        } else {
          setProducts((data as unknown as ProdutoV2[]).map(mapear));
        }
        setLoading(false);
      });

    // estoque ao vivo
    const channel = supabase
      .channel("estoque-produtos")
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "products" },
        (payload) => {
          const novo = payload.new as {
            id: string;
            stock_quantity: number | null;
            stock_enabled: boolean | null;
          };
          setProducts((prev) =>
            prev.map((p) =>
              p.id === novo.id
                ? {
                    ...p,
                    estoque:
                      novo.stock_enabled === false
                        ? 9999
                        : (novo.stock_quantity ?? 0),
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
  }, []);

  return { products, loading, demo };
}
