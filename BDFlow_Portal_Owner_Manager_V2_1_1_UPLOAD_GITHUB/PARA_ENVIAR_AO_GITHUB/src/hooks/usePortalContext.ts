/**
 * Contexto autorizado do Portal.
 *
 * Resolve, em um único ponto: sessão → vínculo (RLS) → capacidades (backend).
 * Estado discriminado: loading | error | no_membership | ready.
 *
 * Falha de rede/RLS vira `error`, NUNCA `no_membership`.
 */

import { useCallback, useEffect, useState } from "react";
import { usePortalSiteAuth } from "./usePortalSiteAuth";
import {
  fetchCapabilities,
  fetchCurrentMembership,
} from "../services/portalMembershipService";
import { applyRoleAndStatusFloor, noCapabilities } from "../domain/portal/capabilities";
import type { PortalContextState } from "../domain/portal/types";

export function usePortalContext(): {
  state: PortalContextState;
  email: string | null;
  recarregar: () => void;
} {
  const { session, carregando } = usePortalSiteAuth();
  const [state, setState] = useState<PortalContextState>({ kind: "loading" });
  const [tick, setTick] = useState(0);

  const recarregar = useCallback(() => setTick((t) => t + 1), []);

  useEffect(() => {
    let ativo = true;

    if (carregando) {
      setState({ kind: "loading" });
      return;
    }
    if (!session) {
      // PortalGuard cuida do redirecionamento; aqui não afirmamos nada.
      setState({ kind: "loading" });
      return;
    }

    setState({ kind: "loading" });

    (async () => {
      const vinculo = await fetchCurrentMembership(session.user.id);
      if (!ativo) return;

      if (vinculo.kind === "failed") {
        setState({ kind: "error", code: vinculo.error.code });
        return;
      }
      if (vinculo.kind === "not_found") {
        setState({ kind: "no_membership" });
        return;
      }

      const caps = await fetchCapabilities();
      if (!ativo) return;

      if (caps.kind === "unavailable") {
        // Conservador: nenhuma capacidade concedida por suposição.
        setState({
          kind: "ready",
          membership: vinculo.membership,
          capabilities: noCapabilities(),
          capabilitiesSource: "unavailable",
        });
        return;
      }

      setState({
        kind: "ready",
        membership: vinculo.membership,
        capabilities: applyRoleAndStatusFloor(
          caps.capabilities,
          vinculo.membership.role,
          vinculo.membership.status
        ),
        capabilitiesSource: "backend",
      });
    })();

    return () => {
      ativo = false;
    };
  }, [session, carregando, tick]);

  return { state, email: session?.user.email ?? null, recarregar };
}
