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

/**
 * Sessão do navegador: persistida e renovada automaticamente.
 *
 * Estes são os defaults do supabase-js; ficam explícitos para que ninguém
 * os desligue por engano. A sessão vive no localStorage da ORIGEM atual
 * (chave `sb-<ref>-auth-token`): cada URL de deployment da Vercel é uma
 * origem diferente e não enxerga a sessão das outras — o login só persiste
 * entre visitas quando o Site é aberto sempre pelo mesmo domínio.
 *
 * Não definir `storageKey` customizado: mudar a chave descartaria a sessão
 * de todos os usuários já logados.
 */
export const supabase: SupabaseClient | null =
  url && anonKey
    ? createClient(url, anonKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
        },
      })
    : null;

export const supabaseConfigurado = supabase !== null;
