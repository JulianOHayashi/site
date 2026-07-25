import { UFS } from "./estado";
import type { CommercialTerritory } from "../domain/commercial/types";

/**
 * Persistência territorial do domínio comercial BDFlow.
 *
 * Chave NOVA (não reutiliza o nome antigo de camisas). Serve apenas para
 * experiência de navegação — o backend continua sendo a autoridade:
 * - regionId armazenado NÃO é confiável; sempre permitimos nova resolução;
 * - trata JSON inválido, valor incompleto ou expirado;
 * - nunca armazena endereço completo, CNPJ ou dados sensíveis.
 */
const CHAVE = "bdflow_commercial_territory_v1";

// Validade da resolução em cache (para navegação). Após isso, re-resolver.
const VALIDADE_MS = 1000 * 60 * 60 * 24; // 24h

export function ufValida(uf: unknown): uf is string {
  return typeof uf === "string" && Boolean(UFS[uf.toUpperCase().trim()]);
}

function cidadeValida(city: unknown): city is string {
  return typeof city === "string" && city.trim().length > 0;
}

/** Lê o território salvo, se válido e não expirado. Senão, null. */
export function obterTerritorio(): CommercialTerritory | null {
  try {
    const bruto = window.localStorage.getItem(CHAVE);
    if (!bruto) return null;

    const dado = JSON.parse(bruto) as Partial<CommercialTerritory>;

    // validação de forma mínima
    if (!ufValida(dado.uf) || !cidadeValida(dado.city)) {
      window.localStorage.removeItem(CHAVE);
      return null;
    }
    if (
      dado.regionStatus !== "active" &&
      dado.regionStatus !== "unavailable"
    ) {
      window.localStorage.removeItem(CHAVE);
      return null;
    }
    if (typeof dado.resolvedAt !== "string") {
      window.localStorage.removeItem(CHAVE);
      return null;
    }

    // expiração
    const quando = Date.parse(dado.resolvedAt);
    if (Number.isNaN(quando) || Date.now() - quando > VALIDADE_MS) {
      window.localStorage.removeItem(CHAVE);
      return null;
    }

    return {
      uf: dado.uf.toUpperCase().trim(),
      city: dado.city.trim(),
      regionId: typeof dado.regionId === "string" ? dado.regionId : null,
      regionName: typeof dado.regionName === "string" ? dado.regionName : null,
      regionStatus: dado.regionStatus,
      resolvedAt: dado.resolvedAt,
    };
  } catch {
    // JSON inválido ou storage indisponível
    try {
      window.localStorage.removeItem(CHAVE);
    } catch {
      /* ignore */
    }
    return null;
  }
}

export function salvarTerritorio(t: CommercialTerritory): boolean {
  if (!ufValida(t.uf) || !cidadeValida(t.city)) return false;
  try {
    window.localStorage.setItem(CHAVE, JSON.stringify(t));
    return true;
  } catch {
    return false;
  }
}

export function limparTerritorio(): void {
  try {
    window.localStorage.removeItem(CHAVE);
  } catch {
    /* ignore */
  }
}
