import { supabaseConfigurado } from "../lib/supabase";

/** Aviso discreto quando o site está rodando sem Supabase (dados de demonstração). */
export default function DemoBanner() {
  if (supabaseConfigurado) return null;
  return (
    <div className="bg-amarelo/30 px-4 py-1.5 text-center text-xs font-medium text-tinta">
      Modo demonstração — conecte o Supabase (.env) para estoque e pedidos reais.
    </div>
  );
}
