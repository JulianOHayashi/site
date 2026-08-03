/**
 * Funções PURAS de resumo de lotes de convite (sem React/JSX), para permitir
 * teste isolado via esbuild + node.
 */

import { invitationVisualState } from "./invitations";
import type { ManagerInvitation } from "./types";

export type ResumoLote = {
  batchId: string;
  createdAt: string | null;
  total: number;
  disponiveis: number;
  utilizados: number;
  expirados: number;
  revogados: number;
};

/** Identificador curto e legível do lote. */
export function loteCurto(batchId: string | null): string {
  if (!batchId) return "—";
  return batchId.length <= 8 ? batchId : batchId.slice(0, 8);
}

/** Agrega convites por lote (disponíveis/utilizados/expirados/revogados). */
export function resumirLotes(
  convites: readonly ManagerInvitation[],
  agora: Date = new Date()
): ResumoLote[] {
  const mapa = new Map<string, ResumoLote>();
  for (const c of convites) {
    if (!c.batchId) continue;
    const r =
      mapa.get(c.batchId) ??
      ({
        batchId: c.batchId,
        createdAt: c.createdAt,
        total: 0,
        disponiveis: 0,
        utilizados: 0,
        expirados: 0,
        revogados: 0,
      } as ResumoLote);
    r.total += 1;
    const estado = invitationVisualState(c, agora);
    if (estado === "not_used") r.disponiveis += 1;
    else if (estado === "used") r.utilizados += 1;
    else if (estado === "expired") r.expirados += 1;
    else if (estado === "revoked") r.revogados += 1;
    mapa.set(c.batchId, r);
  }
  return [...mapa.values()];
}
