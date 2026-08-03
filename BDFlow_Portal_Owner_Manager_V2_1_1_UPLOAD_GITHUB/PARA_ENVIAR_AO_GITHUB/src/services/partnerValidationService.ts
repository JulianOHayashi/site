/**
 * Serviço de validação de benefício — contratos tipados.
 *
 * O navegador NUNCA valida token, NUNCA consulta o banco privado do App e
 * NUNCA decide liberação. A validação ocorrerá por camada server-side
 * Site→App (gateway). Enquanto o gateway não existir, retorna
 * BACKEND_NOT_AVAILABLE — sem simular consulta, aprovação ou uso.
 */

import {
  PortalError,
  type PartnerTransaction,
  type ValidationOutcome,
  type ValidationRequest,
} from "../domain/portal/types";
import type { ServiceResult } from "./partnerTeamService";

const indisponivel = <T,>(): ServiceResult<T> => ({
  ok: false,
  error: new PortalError("BACKEND_NOT_AVAILABLE"),
});

/** Inicia a validação (filial + código) pela camada server-side. */
export async function startValidation(
  _req: ValidationRequest
): Promise<ServiceResult<ValidationOutcome>> {
  return indisponivel();
}

/** Transações/validações da empresa (owner). */
export async function listCompanyTransactions(): Promise<
  ServiceResult<PartnerTransaction[]>
> {
  return indisponivel();
}

/** Somente as próprias validações (manager). */
export async function listOwnValidations(): Promise<
  ServiceResult<PartnerTransaction[]>
> {
  return indisponivel();
}
