import {
  BenefitUsageError,
  ehUuid,
  interpretarAutoridade,
  montarGetRequestStatusBody,
  type BenefitUsageAuthority,
} from "./benefitUsageContract.js";
import type { BenefitUsageGatewayClient } from "./benefitUsageGatewayClient.js";
import type { UserScopedDb } from "./validateHandler.js";

export type BenefitUsageRequestStatus =
  | "awaiting_user_confirmation"
  | "confirmed"
  | "refused"
  | "expired"
  | "cancelled";

export type BenefitUsageStatusInput = {
  requestCorrelationId: unknown;
  unitId: unknown;
};

export type BenefitUsageStatusDeps = {
  criarDbDoUsuario: (accessToken: string) => UserScopedDb;
  gateway: BenefitUsageGatewayClient;
};

export type BenefitUsageStatusResult = {
  ok: true;
  request_correlation_id: string;
  request_status: BenefitUsageRequestStatus;
  confirmed_at: string | null;
  refused_at: string | null;
  expired_at: string | null;
  cancelled_at: string | null;
};

const STATUS = new Set<string>([
  "awaiting_user_confirmation",
  "confirmed",
  "refused",
  "expired",
  "cancelled",
]);

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

function textoOuNull(v: unknown): string | null {
  return typeof v === "string" ? v : null;
}

export async function obterStatusDeUsoDeBeneficio(
  input: BenefitUsageStatusInput,
  accessToken: string | null,
  deps: BenefitUsageStatusDeps
): Promise<BenefitUsageStatusResult> {
  if (!ehUuid(input.requestCorrelationId)) {
    throw new BenefitUsageError("invalid_correlation_id", 400);
  }
  if (!ehUuid(input.unitId)) {
    throw new BenefitUsageError("invalid_unit", 400);
  }
  if (!accessToken || accessToken.trim() === "") {
    throw new BenefitUsageError("not_authenticated", 401);
  }

  const db = deps.criarDbDoUsuario(accessToken);
  const autoridade = await obterAutoridade(db, input.unitId);

  const consulta = await deps.gateway.getRequestStatus(
    montarGetRequestStatusBody(input.requestCorrelationId, autoridade),
    input.requestCorrelationId
  );

  if (!consulta.ok || consulta.body?.success !== true) {
    throw new BenefitUsageError(
      consulta.status === 422 ? "request_status_denied" : "request_status_unavailable",
      consulta.status === 422 ? 409 : 502
    );
  }

  const correlation = consulta.body.request_correlation_id;
  const status = consulta.body.request_status;
  if (
    correlation !== input.requestCorrelationId ||
    typeof status !== "string" ||
    !STATUS.has(status)
  ) {
    throw new BenefitUsageError("request_status_malformed", 502);
  }

  return {
    ok: true,
    request_correlation_id: input.requestCorrelationId,
    request_status: status as BenefitUsageRequestStatus,
    confirmed_at: textoOuNull(consulta.body.confirmed_at),
    refused_at: textoOuNull(consulta.body.refused_at),
    expired_at: textoOuNull(consulta.body.expired_at),
    cancelled_at: textoOuNull(consulta.body.cancelled_at),
  };
}
