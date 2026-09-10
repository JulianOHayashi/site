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

export type ResultadoUsoBeneficio =
  | { tipo: "ok"; correlationId: string; appStatus: string | null }
  | { tipo: "erro"; codigo: string };

export async function enviarUsoDeBeneficio(params: {
  publicLookupId: string;
  rawSecret: string;
  unitId: string;
  physicalPhotoIdChecked: boolean;
}): Promise<ResultadoUsoBeneficio> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  if (params.physicalPhotoIdChecked !== true) {
    return { tipo: "erro", codigo: "photo_id_check_required" };
  }

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return { tipo: "erro", codigo: "not_authenticated" };

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
    return { tipo: "erro", codigo: "network_error" };
  }

  let corpo: Record<string, unknown> | null = null;
  try {
    corpo = (await resposta.json()) as Record<string, unknown>;
  } catch {
    return { tipo: "erro", codigo: "unexpected_error" };
  }

  if (!resposta.ok || corpo?.ok !== true) {
    const codigo = typeof corpo?.code === "string" ? corpo.code : "unexpected_error";
    return { tipo: "erro", codigo };
  }
  return {
    tipo: "ok",
    correlationId: String(corpo.request_correlation_id ?? ""),
    appStatus:
      typeof corpo.app_status === "string" ? (corpo.app_status as string) : null,
  };
}
