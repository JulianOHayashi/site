import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";

/**
 * Sessão do usuário (Supabase Auth).
 * Em modo demonstração (sem Supabase), session é sempre null.
 */
export function useAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    if (!supabase) {
      setCarregando(false);
      return;
    }

    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setCarregando(false);
    });

    const { data: sub } = supabase.auth.onAuthStateChange(
      (_evento, novaSessao) => {
        setSession(novaSessao);
      }
    );

    return () => sub.subscription.unsubscribe();
  }, []);

  return { session, carregando };
}
