import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * APP SUPABASE CLIENT — projeto principal do BDFlow (QR/benefícios).
 *
 * Usado EXCLUSIVAMENTE pelas páginas /portal (parceiro comercial:
 * supermercado, farmácia, loja que valida QR codes).
 *
 * Regras (spec BDFlow):
 * - Somente VITE_APP_SUPABASE_URL e VITE_APP_SUPABASE_ANON_KEY
 * - storage key próprio (sessão separada da loja do site)
 * - Acesso a dados APENAS via RPC — nunca consulta direta a tabelas
 * - Nenhuma chave privada de servidor no navegador
 */
const url = import.meta.env.VITE_APP_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_APP_SUPABASE_ANON_KEY as string | undefined;

export const appSupabase: SupabaseClient | null =
  url && anonKey
    ? createClient(url, anonKey, {
        auth: { storageKey: "bdflow_partner_portal_auth" },
      })
    : null;

export const portalConfigurado = appSupabase !== null;
