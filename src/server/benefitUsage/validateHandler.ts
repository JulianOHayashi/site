/**
 * NÚCLEO DO ENDPOINT SÍNCRONO DE USO DE BENEFÍCIO. SERVER-ONLY.
 *
 * Separado do adaptador da Vercel de propósito: aqui não há `process`, `req`
 * nem `res`, então a sequência inteira — autoridade, auditoria, abertura de
 * token, criação da solicitação — pode ser provada sem servidor de pé.
 *
 * ORDEM DAS PORTAS, E POR QUÊ ELA É ESTA
 *   1. formato do locator e do segredo   entrada malformada não gasta rede
 *   2. sessão do Site                    sem usuário não há autoridade
 *   3. autoridade no banco               deriva pontes e apresentação
 *   4. auditoria da tentativa            grava ANTES de falar com o App
 *   5. token/open assinado
 *   6. create_request assinado           só se 5 permitir explicitamente
 *
 * O SEGREDO CRU
 * Entra pelo corpo do POST, vive em variável local durante a transação, é
 * usado nas duas chamadas ao gateway e some com o escopo. Não é gravado, não
 * entra em query string, não vai para log, não volta na resposta e não é
 * interpolado em mensagem de erro nenhuma. O que persiste é o hash
 * unidirecional que `prepare_benefit_validation` já calculava antes disto
 * existir.
 */

import { randomUUID } from "node:crypto";
import {
  BenefitUsageError,
  ehSegredoCru,
  ehUuid,
  interpretarAutoridade,
  montarCreateRequestBody,
  montarOpenTokenBody,
  type BenefitUsageAuthority,
} from "./benefitUsageContract";
import type { BenefitUsageGatewayClient } from "./benefitUsageGatewayClient";

/** Cliente de banco atuando COMO O USUÁRIO logado, nunca como service_role. */
export type UserScopedDb = {
  rpc: (
    fn: string,
    args: Record<string, unknown>
  ) => Promise<{ data: unknown; error: { message: string } | null }>;
};

export type BenefitUsageInput = {
  /** Do caminho da URL. */
  publicLookupId: unknown;
  /** Do fragmento, capturado pelo navegador. Nunca da query string. */
  rawTokenSecret: unknown;
  /** Única identidade que o navegador escolhe: QUAL unidade. */
  unitId: unknown;
  physicalPhotoIdChecked: unknown;
};

export type BenefitUsageDeps = {
  /** Constrói o cliente de banco a partir do token de sessão do usuário. */
  criarDbDoUsuario: (accessToken: string) => UserScopedDb;
  gateway: BenefitUsageGatewayClient;
  novoCorrelationId?: () => string;
};

/** Resposta devolvida ao navegador. Deliberadamente pobre. */
export type BenefitUsageResult = {
  ok: true;
  status: "request_created";
  request_correlation_id: string;
  partner_display_name: string;
  branch_display_name: string;
  branch_location_label: string;
  /** Estado devolvido pelo App, se ele mandar um rótulo seguro. */
  app_status: string | null;
};

function exigirEntrada(input: BenefitUsageInput): {
  publicLookupId: string;
  rawSecret: string;
  unitId: string;
} {
  if (!ehUuid(input.publicLookupId)) {
    throw new BenefitUsageError("invalid_locator", 400);
  }
  if (!ehSegredoCru(input.rawTokenSecret)) {
    // A mensagem não diz o que veio. Um "esperado 64 hex, recebido X" seria
    // eco do segredo.
    throw new BenefitUsageError("invalid_locator", 400);
  }
  if (!ehUuid(input.unitId)) {
    throw new BenefitUsageError("invalid_unit", 400);
  }
  if (input.physicalPhotoIdChecked !== true) {
    throw new BenefitUsageError("photo_id_check_required", 400);
  }
  return {
    publicLookupId: input.publicLookupId,
    rawSecret: input.rawTokenSecret,
    unitId: input.unitId,
  };
}

async function obterAutoridade(
  db: UserScopedDb,
  unitId: string
): Promise<BenefitUsageAuthority> {
  const { data, error } = await db.rpc("get_my_benefit_usage_authority", {
    p_unit_id: unitId,
  });
  if (error) throw new BenefitUsageError("authority_unavailable", 502);
  return interpretarAutoridade(data);
}

/**
 * Auditoria: reusa a RPC existente, que grava a tentativa com hash
 * unidirecional do token. Falha aqui INTERROMPE o fluxo — chamar o App sem
 * deixar rastro no Site trocaria evidência por conveniência.
 */
async function auditarTentativa(
  db: UserScopedDb,
  autoridade: BenefitUsageAuthority,
  rawSecret: string
): Promise<void> {
  const { data, error } = await db.rpc("prepare_benefit_validation", {
    p_company_id: autoridade.company_id,
    p_unit_id: autoridade.unit_id,
    p_token: rawSecret,
  });
  if (error) throw new BenefitUsageError("audit_failed", 502);
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) throw new BenefitUsageError("audit_failed", 502);
  if (o.allowed !== true) throw new BenefitUsageError("not_authorized", 403);
}

export async function executarUsoDeBeneficio(
  input: BenefitUsageInput,
  accessToken: string | null,
  deps: BenefitUsageDeps
): Promise<BenefitUsageResult> {
  const { publicLookupId, rawSecret, unitId } = exigirEntrada(input);

  if (!accessToken || accessToken.trim() === "") {
    throw new BenefitUsageError("not_authenticated", 401);
  }

  const db = deps.criarDbDoUsuario(accessToken);
  const autoridade = await obterAutoridade(db, unitId);
  await auditarTentativa(db, autoridade, rawSecret);

  // UM correlation id para a submissão inteira. Repetir a operação com um id
  // novo seria uma segunda solicitação, não uma retentativa — por isso não há
  // retentativa automática em lugar nenhum deste arquivo.
  const requestCorrelationId = (deps.novoCorrelationId ?? randomUUID)();

  const abertura = await deps.gateway.openToken(
    montarOpenTokenBody(publicLookupId, rawSecret, autoridade),
    requestCorrelationId
  );
  if (!abertura.ok || abertura.body?.usage_request_may_follow !== true) {
    // Recusa do App JAMAIS vira sucesso, e a create_request não acontece.
    throw new BenefitUsageError("token_open_denied", 409);
  }

  const criacao = await deps.gateway.createRequest(
    montarCreateRequestBody(
      publicLookupId,
      rawSecret,
      requestCorrelationId,
      autoridade
    ),
    requestCorrelationId
  );
  if (!criacao.ok) {
    throw new BenefitUsageError("request_denied", 409);
  }

  const appStatus = criacao.body?.status;
  return {
    ok: true,
    status: "request_created",
    request_correlation_id: requestCorrelationId,
    // Devolve só o que a tela precisa mostrar de volta ao balconista.
    partner_display_name: autoridade.snapshot_partner_display_name,
    branch_display_name: autoridade.snapshot_branch_display_name,
    branch_location_label: autoridade.snapshot_branch_location_label,
    app_status: typeof appStatus === "string" ? appStatus : null,
  };
}
