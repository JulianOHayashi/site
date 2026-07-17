import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";

/**
 * Sessão do PORTAL — agora no Supabase do SITE
 * (mesmo projeto/cliente já usado por /parceiros e /admin).
 *
 * Nesta migração:
 * - O portal NÃO usa mais o Supabase do APP.
 * - Ao carregar, removemos silenciosamente a sessão antiga
 *   guardada com a chave `bdflow_partner_portal_auth`, para que
 *   ninguém fique "logado" residualmente no cliente antigo.
 * - A sessão principal do site (usada por /parceiros) NÃO é tocada.
 */

const CHAVE_ANTIGA = "bdflow_partner_portal_auth";

function limparSessaoAntigaDoApp() {
  if (typeof window === "undefined") return;
  try {
    // supabase-js guarda a sessão nessa mesma chave em ambos storages
    window.localStorage.removeItem(CHAVE_ANTIGA);
    window.sessionStorage.removeItem(CHAVE_ANTIGA);
  } catch {
    /* ambientes sem storage — ignorar em silêncio */
  }
}

export function usePortalSiteAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    limparSessaoAntigaDoApp();

    if (!supabase) {
      setCarregando(false);
      return;
    }

    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setCarregando(false);
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_e, nova) => {
      setSession(nova);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  return { session, carregando };
}
