import { useCallback, useEffect, useState } from "react";
import {
  obterTerritorio,
  salvarTerritorio,
  limparTerritorio,
} from "../lib/commercialTerritory";
import {
  fetchCurrentFormation,
  CommercialError,
} from "../services/commercialService";
import type { CommercialTerritory } from "../domain/commercial/types";

/**
 * Hook territorial do domínio comercial.
 *
 * Lê a persistência (apenas navegação), resolve a região pelo backend
 * (autoridade), e expõe ações. Não trata localStorage como autoridade e
 * não consulta tabelas diretamente. Estado local — sem Context global.
 */
export function useCommercialTerritory() {
  const [territory, setTerritory] = useState<CommercialTerritory | null>(() =>
    obterTerritorio()
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const resolver = useCallback(async (uf: string, city: string) => {
    setLoading(true);
    setError(null);
    try {
      const resp = await fetchCurrentFormation(uf, city);
      const t: CommercialTerritory = {
        uf: uf.toUpperCase().trim(),
        city: city.trim(),
        regionId: resp.region?.regionId ?? null,
        regionName: resp.region?.regionName ?? null,
        regionStatus: resp.regionAvailable ? "active" : "unavailable",
        resolvedAt: new Date().toISOString(),
      };
      salvarTerritorio(t);
      setTerritory(t);
      return t;
    } catch (e) {
      const msg =
        e instanceof CommercialError && e.kind === "not_configured"
          ? "Serviço comercial não configurado."
          : "Não foi possível verificar a disponibilidade nesta localidade.";
      setError(msg);
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  const selectLocation = useCallback(
    (uf: string, city: string) => resolver(uf, city),
    [resolver]
  );

  const refreshRegion = useCallback(() => {
    if (territory) return resolver(territory.uf, territory.city);
    return Promise.resolve(null);
  }, [territory, resolver]);

  const clearLocation = useCallback(() => {
    limparTerritorio();
    setTerritory(null);
    setError(null);
  }, []);

  // Re-hidrata se outra aba alterar a persistência.
  useEffect(() => {
    const onStorage = () => setTerritory(obterTerritorio());
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  return {
    territory,
    loading,
    error,
    selectLocation,
    clearLocation,
    refreshRegion,
  };
}
