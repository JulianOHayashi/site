import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Cliente público do Supabase do Site.
 *
 * O navegador usa somente a chave pública. Autorização, integridade comercial
 * e acesso a dados permanecem sob responsabilidade de RLS e RPCs do backend.
 * Nenhuma chave privada ou service_role deve ser exposta aqui.
 */
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const supabase: SupabaseClient | null =
  url && anonKey ? createClient(url, anonKey) : null;

export const supabaseConfigurado = supabase !== null;
