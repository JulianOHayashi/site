/**
 * Serviço de equipe (managers e convites) — contratos tipados.
 *
 * NENHUMA operação existe no backend ainda. Todas retornam
 * `BACKEND_NOT_AVAILABLE`. Não geramos token no navegador, não criamos RPC
 * com nome inventado e não fazemos INSERT/UPDATE para contornar RLS.
 */

import {
  PortalError,
  type CreateInvitationBatchInput,
  type ManagerInvitation,
  type ManagerInvitationBatch,
  type PartnerManagerSummary,
  type RevokeManagerMembershipInput,
} from "../domain/portal/types";

export type ServiceResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: PortalError };

const indisponivel = <T,>(): ServiceResult<T> => ({
  ok: false,
  error: new PortalError("BACKEND_NOT_AVAILABLE"),
});

/** Lista os managers da empresa do owner autenticado. */
export async function listManagers(): Promise<
  ServiceResult<PartnerManagerSummary[]>
> {
  return indisponivel();
}

/** Detalhes permitidos de um manager. */
export async function getManager(
  _memberId: string
): Promise<ServiceResult<PartnerManagerSummary>> {
  return indisponivel();
}

/**
 * Cria um lote de convites.
 *
 * Recebe a quantidade e apenas os rótulos preenchidos (esparsos). Cada item
 * do lote vira um convite INDEPENDENTE: token individual e forte, uso único,
 * validade de 48 horas corridas, vinculado à empresa (não a uma filial) e
 * revogável individualmente. O token e o `batchId` são gerados pelo BACKEND.
 * O retorno é o LOTE completo (batchId + convites), não uma lista solta.
 */
export async function createInvitationBatch(
  _input: CreateInvitationBatchInput
): Promise<ServiceResult<ManagerInvitationBatch>> {
  return indisponivel();
}

/** Lista convites recentes (sem segredo recuperável). */
export async function listInvitations(): Promise<
  ServiceResult<ManagerInvitation[]>
> {
  return indisponivel();
}

/** Consulta pública protegida de um convite pelo token. */
export async function getPublicInvitation(
  _token: string
): Promise<ServiceResult<ManagerInvitation>> {
  return indisponivel();
}

/** Aceite do convite (cadastro do manager) — atômico no backend. */
export async function acceptInvitation(
  _token: string,
  _dados: { fullName: string; cpf: string; phone: string }
): Promise<ServiceResult<{ memberId: string }>> {
  return indisponivel();
}

/** Revoga um convite individual ainda não utilizado. */
export async function revokeInvitation(
  _invitationId: string
): Promise<ServiceResult<void>> {
  return indisponivel();
}

/** Revoga os convites AINDA NÃO UTILIZADOS de um lote (nunca os utilizados). */
export async function revokeInvitationBatch(
  _batchId: string
): Promise<ServiceResult<void>> {
  return indisponivel();
}

/**
 * Gera um SUBSTITUTO para um convite expirado ou revogado.
 * Cria (no backend) um novo convite: novo ID, novo token e novas 48 horas.
 * O convite antigo permanece no histórico como expirado/revogado.
 */
export async function replaceInvitation(
  _invitationId: string
): Promise<ServiceResult<ManagerInvitation>> {
  return indisponivel();
}

/** Bloqueio imediato e REVERSÍVEL do acesso do manager. */
export async function suspendManager(
  _memberId: string
): Promise<ServiceResult<void>> {
  return indisponivel();
}

/**
 * REATIVA um manager suspenso. Não cria novo vínculo e nunca é oferecida a
 * vínculo `archived`. Ação reversível — o oposto de suspender.
 */
export async function reactivateManager(
  _memberId: string
): Promise<ServiceResult<void>> {
  return indisponivel();
}

/**
 * Encerramento DEFINITIVO do vínculo empresarial (desligamento).
 *
 * Recebe um objeto tipado com `reason` e `sensitiveActionProof` (prova opaca
 * emitida pelo backend após autenticação adicional — NUNCA senha bruta).
 * Não exclui a conta pessoal nem o histórico — preservados para auditoria.
 */
export async function revokeManagerMembership(
  _input: RevokeManagerMembershipInput
): Promise<ServiceResult<void>> {
  return indisponivel();
}

/** Remoção administrativa agendada ao fim do dia, se mantida pelo backend. */
export async function requestEndOfDayRemoval(
  _memberId: string
): Promise<ServiceResult<void>> {
  return indisponivel();
}
