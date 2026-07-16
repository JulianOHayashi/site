import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { appSupabase } from "../lib/appSupabaseClient";

/** Sessão do PORTAL (APP Supabase — parceiro comercial BDFlow). */
export function usePortalAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    if (!appSupabase) {
      setCarregando(false);
      return;
    }
    appSupabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setCarregando(false);
    });
    const { data: sub } = appSupabase.auth.onAuthStateChange(
      (_e, nova) => setSession(nova)
    );
    return () => sub.subscription.unsubscribe();
  }, []);

  return { session, carregando };
}
