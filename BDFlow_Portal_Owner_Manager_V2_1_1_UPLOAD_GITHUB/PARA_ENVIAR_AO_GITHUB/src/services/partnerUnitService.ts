/**
 * Serviço de unidades (matriz e filiais) — contratos tipados.
 * Backend ainda inexistente: tudo retorna BACKEND_NOT_AVAILABLE.
 */

import { PortalError, type PartnerUnit } from "../domain/portal/types";
import type { ServiceResult } from "./partnerTeamService";

const indisponivel = <T,>(): ServiceResult<T> => ({
  ok: false,
  error: new PortalError("BACKEND_NOT_AVAILABLE"),
});

/** Todas as unidades da empresa (matriz + filiais). */
export async function listUnits(): Promise<ServiceResult<PartnerUnit[]>> {
  return indisponivel();
}

/**
 * Unidades elegíveis para uma validação AGORA: cadastradas, ativas e
 * autorizadas a liberar benefícios. A elegibilidade é decidida pelo
 * backend; o filtro abaixo é apenas defesa adicional da interface.
 */
export async function listValidatableUnits(): Promise<
  ServiceResult<PartnerUnit[]>
> {
  return indisponivel();
}

/** Filtro puro de elegibilidade (testável). */
export function filterValidatableUnits(
  unidades: readonly PartnerUnit[]
): PartnerUnit[] {
  return unidades.filter(
    (u) => u.status === "active" && u.benefitsAuthorized === true
  );
}

/** Cadastro de filial — somente com canManageUnits concedida pelo backend. */
export async function createUnit(
  _dados: Record<string, unknown>
): Promise<ServiceResult<PartnerUnit>> {
  return indisponivel();
}
