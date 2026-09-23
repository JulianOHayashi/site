/**
 * CÓDIGO MANUAL DO BALCÃO — núcleo de servidor.
 *
 * Irmão do fluxo de QR, não uma extensão dele. As duas superfícies provam a
 * mesma coisa — quem está validando e em qual filial — mas carregam
 * portadores diferentes: o QR leva `public_lookup_id` + `raw_token_secret`, o
 * balcão leva um `display_code` digitado. Sobrepor os dois significaria
 * converter um código de balcão em portador de token.
 *
 * O QUE O SITE DELIBERADAMENTE NÃO FAZ
 * Não faz hash nem HMAC do código, não consulta tabela do App, não resolve
 * expiração e não implementa uso único. O App é a autoridade sobre o código;
 * o Site prova a autoridade do VALIDADOR e transporta o resto.
 *
 * Por isso este caminho NÃO chama `prepare_benefit_validation`: aquela RPC
 * pertence ao desenho antigo, que interpretava e hasheava o token no Site.
 */

import { randomUUID } from "node:crypto";
import {
  BenefitUsageError,
  ehUuid,
  interpretarAutoridade,
  montarCreateRequestByCodeBody,
  normalizarDisplayCode,
} from "./benefitUsageContract.js";
import type { BenefitUsageGatewayClient } from "./benefitUsageGatewayClient.js";
import type { UserScopedDb } from "./validateHandler.js";

export type ManualCodeInput = {
  /** Como o balconista digitou. Normalizado aqui, nunca adivinhado. */
  displayCode: unknown;
  /** Única identidade que o navegador escolhe: QUAL unidade. */
  unitId: unknown;
  physicalPhotoIdChecked: unknown;
};

export type ManualCodeDeps = {
  criarDbDoUsuario: (accessToken: string) => UserScopedDb;
  gateway: BenefitUsageGatewayClient;
  novoCorrelationId?: () => string;
};

/** Resposta ao navegador: deliberadamente pobre, como no fluxo de QR. */
export type ManualCodeResult = {
  ok: true;
  status: "request_created";
  request_correlation_id: string;
  partner_display_name: string;
  branch_display_name: string;
  branch_location_label: string;
  app_status: string | null;
};

export async function executarCodigoManual(
  input: ManualCodeInput,
  accessToken: string | null,
  deps: ManualCodeDeps
): Promise<ManualCodeResult> {
  // ---- forma, antes de qualquer rede
  const codigo = normalizarDisplayCode(input.displayCode);
  if (!codigo) {
    // A mensagem não ecoa o que foi digitado: o código circula nesta pilha.
    throw new BenefitUsageError("invalid_display_code", 400);
  }
  if (!ehUuid(input.unitId)) {
    throw new BenefitUsageError("invalid_unit", 400);
  }
  if (input.physicalPhotoIdChecked !== true) {
    throw new BenefitUsageError("photo_id_check_required", 400);
  }
  if (!accessToken || accessToken.trim() === "") {
    throw new BenefitUsageError("not_authenticated", 401);
  }

  // ---- autoridade do Site, como o usuário. A empresa é derivada da unidade.
  const db = deps.criarDbDoUsuario(accessToken);
  const { data, error } = await db.rpc("get_my_benefit_usage_authority", {
    p_unit_id: input.unitId,
  });
  if (error) throw new BenefitUsageError("authority_unavailable", 502);
  const autoridade = interpretarAutoridade(data);

  // UM correlation id por submissão, gerado no servidor. Repetir com um id
  // novo seria uma segunda solicitação, não uma retentativa — por isso não há
  // retentativa automática em lugar nenhum deste arquivo.
  const requestCorrelationId = (deps.novoCorrelationId ?? randomUUID)();

  const r = await deps.gateway.createRequestByCode(
    montarCreateRequestByCodeBody(codigo, requestCorrelationId, autoridade),
    requestCorrelationId
  );
  if (!r.ok) {
    // Recusa do App JAMAIS vira sucesso.
    throw new BenefitUsageError("request_denied", 409);
  }

  const appStatus = r.body?.request_status;
  return {
    ok: true,
    status: "request_created",
    request_correlation_id: requestCorrelationId,
    partner_display_name: autoridade.snapshot_partner_display_name,
    branch_display_name: autoridade.snapshot_branch_display_name,
    branch_location_label: autoridade.snapshot_branch_location_label,
    app_status: typeof appStatus === "string" ? appStatus : null,
  };
}