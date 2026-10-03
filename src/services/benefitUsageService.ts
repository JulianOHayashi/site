/**
 * Cliente de navegador do endpoint síncrono de uso de benefício.
 *
 * O navegador manda o MÍNIMO: o locator, o segredo capturado do fragmento,
 * qual unidade foi escolhida e a confirmação de conferência do documento com
 * foto. Identidades de ponte, papel, nome do parceiro, cidade e UF NÃO são
 * enviados — o servidor os deriva do usuário autenticado, e valor vindo daqui
 * seria valor que o balconista poderia forjar no console.
 */

import { supabase } from "../lib/supabase";

export type BenefitUsageRequestStatus =
  | "awaiting_user_confirmation"
  | "confirmed"
  | "refused"
  | "expired"
  | "cancelled";

const REQUEST_STATUSES = new Set<string>([
  "awaiting_user_confirmation",
  "confirmed",
  "refused",
  "expired",
  "cancelled",
]);

function asRequestStatus(v: unknown): BenefitUsageRequestStatus | null {
  return typeof v === "string" && REQUEST_STATUSES.has(v)
    ? (v as BenefitUsageRequestStatus)
    : null;
}

/**
 * Em que ponto do caminho de execução a falha aconteceu.
 *
 * `pre_despacho` é uma afirmação FORTE: nenhuma requisição saiu do navegador,
 * porque o `return` ocorreu antes do `fetch`. Só este caso autoriza reaproveitar
 * um QR já consumido.
 *
 * `indeterminado` é tudo o mais, inclusive uma resposta de erro do servidor.
 * Um `fetch` rejeitado pode ter entregue o POST e perdido só a resposta; um
 * corpo ilegível pode acompanhar um 200; e um erro devolvido pelo servidor não
 * prova, do lado do cliente, que nada foi criado no App. Na dúvida, fecha.
 */
export type FaseFalhaUsoBeneficio = "pre_despacho" | "indeterminado";

export type ResultadoUsoBeneficio =
  | { tipo: "ok"; correlationId: string; appStatus: string | null }
  | { tipo: "erro"; codigo: string; fase: FaseFalhaUsoBeneficio };

export async function enviarUsoDeBeneficio(params: {
  publicLookupId: string;
  rawSecret: string;
  unitId: string;
  physicalPhotoIdChecked: boolean;
}): Promise<ResultadoUsoBeneficio> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable", fase: "pre_despacho" };
  if (params.physicalPhotoIdChecked !== true) {
    return { tipo: "erro", codigo: "photo_id_check_required", fase: "pre_despacho" };
  }

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { tipo: "erro", codigo: "not_authenticated", fase: "pre_despacho" };

  let resposta: Response;
  try {
    resposta = await fetch("/api/benefit-usage/validate", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        public_lookup_id: params.publicLookupId,
        raw_token_secret: params.rawSecret,
        unit_id: params.unitId,
        physical_photo_id_checked: true,
      }),
    });
  } catch {
    // O POST pode ter chegado ao servidor e só a resposta ter se perdido.
    return { tipo: "erro", codigo: "network_error", fase: "indeterminado" };
  }

  let corpo: Record<string, unknown> | null = null;
  try {
    corpo = (await resposta.json()) as Record<string, unknown>;
  } catch {
    // Corpo ilegível pode vir junto de uma requisição bem-sucedida.
    return { tipo: "erro", codigo: "unexpected_error", fase: "indeterminado" };
  }

  if (!resposta.ok || corpo?.ok !== true) {
    const codigo = typeof corpo?.code === "string" ? corpo.code : "unexpected_error";
    // Erro devolvido PELO servidor: do lado do cliente não há como provar que
    // nada foi criado no App, então não destrava o QR.
    return { tipo: "erro", codigo, fase: "indeterminado" };
  }
  return {
    tipo: "ok",
    correlationId: String(corpo.request_correlation_id ?? ""),
    appStatus:
      typeof corpo.app_status === "string" ? (corpo.app_status as string) : null,
  };
}

/**
 * Código manual do balcão. Caminho SEPARADO do QR, de propósito: os dois
 * provam a mesma autoridade, mas carregam portadores diferentes.
 *
 * O navegador envia três coisas e só três: o código digitado, qual unidade e
 * a confirmação do documento com foto. Pontes, papel, empresa, snapshots e
 * correlação são derivados no servidor — não há por onde enviá-los.
 *
 * O código não é persistido, não entra em URL e não é registrado.
 */
export async function enviarUsoDeBeneficioPorCodigo(params: {
  displayCode: string;
  unitId: string;
  physicalPhotoIdChecked: boolean;
}): Promise<ResultadoUsoBeneficio> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable", fase: "pre_despacho" };
  if (params.physicalPhotoIdChecked !== true) {
    return { tipo: "erro", codigo: "photo_id_check_required", fase: "pre_despacho" };
  }

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { tipo: "erro", codigo: "not_authenticated", fase: "pre_despacho" };

  let resposta: Response;
  try {
    resposta = await fetch("/api/benefit-usage/code/request", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        display_code: params.displayCode,
        unit_id: params.unitId,
        physical_photo_id_checked: true,
      }),
    });
  } catch {
    // O POST pode ter chegado ao servidor e só a resposta ter se perdido.
    return { tipo: "erro", codigo: "network_error", fase: "indeterminado" };
  }

  let corpo: Record<string, unknown> | null = null;
  try {
    corpo = (await resposta.json()) as Record<string, unknown>;
  } catch {
    // Corpo ilegível pode vir junto de uma requisição bem-sucedida.
    return { tipo: "erro", codigo: "unexpected_error", fase: "indeterminado" };
  }

  if (!resposta.ok || corpo?.ok !== true) {
    const codigo =
      typeof corpo?.code === "string" ? corpo.code : "unexpected_error";
    return { tipo: "erro", codigo, fase: "indeterminado" };
  }
  return {
    tipo: "ok",
    correlationId: String(corpo.request_correlation_id ?? ""),
    appStatus:
      typeof corpo.app_status === "string" ? (corpo.app_status as string) : null,
  };
}

export type ResultadoStatusUsoBeneficio =
  | { tipo: "ok"; status: BenefitUsageRequestStatus }
  | { tipo: "erro"; codigo: string };

export async function obterStatusUsoDeBeneficio(params: {
  correlationId: string;
  unitId: string;
}): Promise<ResultadoStatusUsoBeneficio> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { tipo: "erro", codigo: "not_authenticated" };

  let resposta: Response;
  try {
    resposta = await fetch("/api/benefit-usage/status", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        request_correlation_id: params.correlationId,
        unit_id: params.unitId,
      }),
    });
  } catch {
    return { tipo: "erro", codigo: "network_error" };
  }

  let corpo: Record<string, unknown> | null = null;
  try {
    corpo = (await resposta.json()) as Record<string, unknown>;
  } catch {
    return { tipo: "erro", codigo: "unexpected_error" };
  }

  if (!resposta.ok || corpo?.ok !== true) {
    return {
      tipo: "erro",
      codigo: typeof corpo?.code === "string" ? corpo.code : "unexpected_error",
    };
  }

  const status = asRequestStatus(corpo.request_status);
  if (!status) return { tipo: "erro", codigo: "unexpected_status" };
  return { tipo: "ok", status };
}
