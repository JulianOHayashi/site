import { supabase } from "../lib/supabase";

export type FutureInterest =
  | { tipo: "none" }
  | {
      tipo: "preorder";
      status: string;
      targetSequenceNumber: number;
      already?: boolean;
    }
  | {
      tipo: "sales_waitlist";
      status: string;
      position: number;
      firstPossibleExclusivitySequence: number;
      already?: boolean;
    }
  | { tipo: "erro"; codigo: string };

export async function joinFutureQueue(params: {
  companyId: string;
  nicheCode: string;
}): Promise<FutureInterest> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };

  const { data, error } = await supabase.rpc("join_my_commercial_future_queue", {
    p_company_id: params.companyId,
    p_niche_code: params.nicheCode,
  });
  if (error) return { tipo: "erro", codigo: "rpc_error" };

  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) {
    return {
      tipo: "erro",
      codigo: typeof o.reason === "string" ? o.reason : "unexpected_error",
    };
  }

  if (o.mode === "preorder") {
    return {
      tipo: "preorder",
      status: String(o.status ?? "waiting"),
      targetSequenceNumber: Number(o.target_sequence_number),
      already: o.already === true,
    };
  }

  if (o.mode === "sales_waitlist") {
    return {
      tipo: "sales_waitlist",
      status: String(o.status ?? "waiting"),
      position: Number(o.position),
      firstPossibleExclusivitySequence: Number(
        o.first_possible_exclusivity_sequence
      ),
      already: o.already === true,
    };
  }

  return { tipo: "erro", codigo: "unexpected_response" };
}

export async function getFutureInterest(params: {
  companyId: string;
  nicheCode: string;
}): Promise<FutureInterest> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };

  const { data, error } = await supabase.rpc("get_my_commercial_future_interest", {
    p_company_id: params.companyId,
    p_niche_code: params.nicheCode,
  });
  if (error) return { tipo: "erro", codigo: "rpc_error" };

  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) {
    return {
      tipo: "erro",
      codigo: typeof o.reason === "string" ? o.reason : "unexpected_error",
    };
  }

  if (o.mode === "none") return { tipo: "none" };

  if (o.mode === "preorder") {
    return {
      tipo: "preorder",
      status: String(o.status ?? "waiting"),
      targetSequenceNumber: Number(o.target_sequence_number),
    };
  }

  if (o.mode === "sales_waitlist") {
    return {
      tipo: "sales_waitlist",
      status: String(o.status ?? "waiting"),
      position: Number(o.position),
      firstPossibleExclusivitySequence: Number(
        o.first_possible_exclusivity_sequence
      ),
    };
  }

  return { tipo: "erro", codigo: "unexpected_response" };
}

export async function registerTerritorialInterest(params: {
  cnpj: string;
  companyName: string;
  responsibleName: string;
  email: string;
  phone: string;
  uf: string;
  city: string;
  nicheCode: string;
}): Promise<{ tipo: "ok"; already: boolean } | { tipo: "erro"; codigo: string }> {
  try {
    const resposta = await fetch("/api/public/commercial/territorial-interest", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        cnpj: params.cnpj,
        company_name: params.companyName,
        responsible_name: params.responsibleName,
        email: params.email,
        phone: params.phone || null,
        uf: params.uf,
        city: params.city,
        niche_code: params.nicheCode,
      }),
    });
    const o = (await resposta.json().catch(() => null)) as Record<string, unknown> | null;
    if (!o || typeof o !== "object") {
      return { tipo: "erro", codigo: "rpc_error" };
    }
    if (!resposta.ok || o.ok !== true) {
      return {
        tipo: "erro",
        codigo: typeof o.reason === "string" ? o.reason : "unexpected_error",
      };
    }

    // O backend não revela se o CNPJ já estava presente.
    return { tipo: "ok", already: false };
  } catch {
    return { tipo: "erro", codigo: "rpc_error" };
  }
}
