import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Cliente Supabase OPCIONAL.
 * - Sem as variáveis de ambiente, o site roda em modo demonstração (dados mock).
 * - Com elas preenchidas (.env), produtos/estoque vêm do banco em tempo real.
 * As chaves aqui são públicas (anon) — a segurança fica no RLS do banco.
 */
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const supabase: SupabaseClient | null =
  url && anonKey ? createClient(url, anonKey) : null;

export const supabaseConfigurado = supabase !== null;
