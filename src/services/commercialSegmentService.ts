/**
 * Segmentos de Outros — cliente de navegador.
 *
 * O navegador LÊ o catálogo aprovado e ENVIA solicitações; nunca aprova,
 * nunca reserva e nunca decide se um segmento pode ocupar uma posição. Tudo
 * isso é decidido no servidor (RPCs da migration 20261103120000), e a
 * resposta é a única fonte do que a tela exibe.
 *
 * Solicitação de segmento não listado: só o responsável (partner_owner) da
 * empresa pode enviar, e enviar não cria reserva, contrato nem aprovação.
 */
import { supabase } from "../lib/supabase";
import type { CommercialSegment } from "../domain/commercial/types";

type Erro = { tipo: "erro"; codigo: string };

function motivo(o: Record<string, unknown>): string {
  return typeof o.reason === "string" ? o.reason : "unexpected_error";
}

function texto(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v : null;
}

function parseSegmento(raw: unknown): CommercialSegment | null {
  if (!raw || typeof raw !== "object") return null;
  const s = raw as Record<string, unknown>;
  if (typeof s.id !== "string" || typeof s.code !== "string" || typeof s.name !== "string") {
    return null;
  }
  return {
    id: s.id,
    code: s.code,
    name: s.name,
    description: texto(s.description),
    overlapsNicheCode: texto(s.overlaps_niche_code),
  };
}

/** Catálogo público de segmentos aprovados. */
export async function listarSegmentos(): Promise<
  { tipo: "ok"; segmentos: CommercialSegment[] } | Erro
> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data, error } = await supabase.rpc("list_commercial_segments");
  if (error) return { tipo: "erro", codigo: "rpc_error" };
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true || !Array.isArray(o.segments)) return { tipo: "erro", codigo: motivo(o) };
  const segmentos: CommercialSegment[] = [];
  for (const item of o.segments) {
    const s = parseSegmento(item);
    if (!s) return { tipo: "erro", codigo: "unexpected_response" };
    segmentos.push(s);
  }
  return { tipo: "ok", segmentos };
}

export type SolicitacaoSegmento = {
  id: string;
  label: string;
  status: "pending" | "approved" | "rejected" | "cancelled";
  intendedNicheCode: string | null;
  decisionNote: string | null;
  segmentName: string | null;
};

const STATUS_SOLICITACAO = new Set(["pending", "approved", "rejected", "cancelled"]);

/** Solicitação de segmento não listado (owner). */
export async function solicitarSegmento(params: {
  companyId: string;
  label: string;
  justification?: string;
  intendedNicheCode?: string | null;
}): Promise<{ tipo: "ok"; requestId: string; already: boolean } | (Erro & { segmentName?: string })> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data, error } = await supabase.rpc("request_commercial_segment", {
    p_company_id: params.companyId,
    p_label: params.label,
    p_justification: params.justification?.trim() ? params.justification.trim() : null,
    p_intended_niche_code: params.intendedNicheCode ?? null,
  });
  if (error) return { tipo: "erro", codigo: "rpc_error" };
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) {
    return {
      tipo: "erro",
      codigo: motivo(o),
      ...(typeof o.segment_name === "string" ? { segmentName: o.segment_name } : {}),
    };
  }
  if (typeof o.request_id !== "string") return { tipo: "erro", codigo: "unexpected_response" };
  return { tipo: "ok", requestId: o.request_id, already: o.already === true };
}

/** Solicitações da própria empresa (owner). */
export async function minhasSolicitacoes(companyId: string): Promise<
  { tipo: "ok"; solicitacoes: SolicitacaoSegmento[] } | Erro
> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data, error } = await supabase.rpc("get_my_commercial_segment_requests", {
    p_company_id: companyId,
  });
  if (error) return { tipo: "erro", codigo: "rpc_error" };
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true || !Array.isArray(o.requests)) return { tipo: "erro", codigo: motivo(o) };
  const solicitacoes: SolicitacaoSegmento[] = [];
  for (const item of o.requests) {
    const r = (item ?? {}) as Record<string, unknown>;
    if (typeof r.id !== "string" || typeof r.label !== "string" || !STATUS_SOLICITACAO.has(String(r.status))) {
      return { tipo: "erro", codigo: "unexpected_response" };
    }
    solicitacoes.push({
      id: r.id,
      label: r.label,
      status: r.status as SolicitacaoSegmento["status"],
      intendedNicheCode: texto(r.intended_niche_code),
      decisionNote: texto(r.decision_note),
      segmentName: texto(r.segment_name),
    });
  }
  return { tipo: "ok", solicitacoes };
}

// ---------------------------------------------------------------------------
// Administração. O servidor exige site_admin em cada RPC; esconder a tela de
// quem não é admin é só apresentação.
// ---------------------------------------------------------------------------
export type SegmentoAdmin = CommercialSegment & {
  classificationKey: string;
  delimitationPolicy: string | null;
  status: "approved" | "archived";
};
export type SolicitacaoAdmin = SolicitacaoSegmento & {
  companyId: string;
  companyName: string;
  justification: string | null;
};

export async function adminCarregarSegmentos(): Promise<
  { tipo: "ok"; segmentos: SegmentoAdmin[]; solicitacoes: SolicitacaoAdmin[] } | Erro
> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data, error } = await supabase.rpc("admin_list_commercial_segments");
  if (error) return { tipo: "erro", codigo: "not_authorized" };
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true || !Array.isArray(o.segments) || !Array.isArray(o.requests)) {
    return { tipo: "erro", codigo: motivo(o) };
  }
  const segmentos: SegmentoAdmin[] = [];
  for (const item of o.segments) {
    const base = parseSegmento(item);
    const r = (item ?? {}) as Record<string, unknown>;
    if (!base || typeof r.classification_key !== "string" ||
        (r.status !== "approved" && r.status !== "archived")) {
      return { tipo: "erro", codigo: "unexpected_response" };
    }
    segmentos.push({
      ...base,
      classificationKey: r.classification_key,
      delimitationPolicy: texto(r.delimitation_policy),
      status: r.status,
    });
  }
  const solicitacoes: SolicitacaoAdmin[] = [];
  for (const item of o.requests) {
    const r = (item ?? {}) as Record<string, unknown>;
    if (typeof r.id !== "string" || typeof r.label !== "string" ||
        typeof r.company_id !== "string" || !STATUS_SOLICITACAO.has(String(r.status))) {
      return { tipo: "erro", codigo: "unexpected_response" };
    }
    solicitacoes.push({
      id: r.id,
      label: r.label,
      status: r.status as SolicitacaoSegmento["status"],
      intendedNicheCode: texto(r.intended_niche_code),
      decisionNote: texto(r.decision_note),
      segmentName: null,
      companyId: r.company_id,
      companyName: texto(r.company_name) ?? "Empresa",
      justification: texto(r.justification),
    });
  }
  return { tipo: "ok", segmentos, solicitacoes };
}

export type DecisaoSegmento =
  | { decisao: "reject"; nota: string }
  | { decisao: "approve"; segmentoExistenteId: string; nota?: string }
  | {
      decisao: "approve";
      novo: {
        code: string;
        displayName: string;
        classificationKey: string;
        overlapsNicheCode?: string | null;
        delimitationPolicy?: string | null;
      };
      nota?: string;
    };

export async function adminDecidirSolicitacao(
  requestId: string,
  d: DecisaoSegmento
): Promise<{ tipo: "ok"; status: string } | Erro> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const args: Record<string, unknown> = {
    p_request_id: requestId,
    p_decision: d.decisao,
    p_note: d.nota ?? null,
  };
  if (d.decisao === "approve" && "segmentoExistenteId" in d) {
    args.p_existing_segment_id = d.segmentoExistenteId;
  } else if (d.decisao === "approve" && "novo" in d) {
    args.p_new_code = d.novo.code;
    args.p_new_display_name = d.novo.displayName;
    args.p_new_classification_key = d.novo.classificationKey;
    args.p_new_overlaps_niche_code = d.novo.overlapsNicheCode ?? null;
    args.p_new_delimitation_policy = d.novo.delimitationPolicy ?? null;
  }
  const { data, error } = await supabase.rpc("admin_decide_commercial_segment_request", args);
  if (error) return { tipo: "erro", codigo: "not_authorized" };
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) return { tipo: "erro", codigo: motivo(o) };
  return { tipo: "ok", status: String(o.status) };
}

export async function adminArquivarSegmento(
  segmentId: string
): Promise<{ tipo: "ok" } | Erro> {
  if (!supabase) return { tipo: "erro", codigo: "site_backend_unavailable" };
  const { data, error } = await supabase.rpc("admin_archive_commercial_segment", {
    p_segment_id: segmentId,
  });
  if (error) return { tipo: "erro", codigo: "not_authorized" };
  const o = (data ?? {}) as Record<string, unknown>;
  if (o.ok !== true) return { tipo: "erro", codigo: motivo(o) };
  return { tipo: "ok" };
}

/** Mensagens fixas por motivo. Nenhum texto do banco chega à tela. */
const MENSAGENS: Record<string, string> = {
  not_authenticated: "Entre como responsável da empresa para continuar.",
  not_company_owner: "Somente o responsável pela empresa pode fazer isso.",
  company_inactive: "A empresa não está ativa.",
  invalid_label: "Informe o nome do segmento (de 3 a 80 caracteres).",
  invalid_justification: "A descrição pode ter até 1.000 caracteres.",
  segment_already_listed: "Esse segmento já está na lista. Escolha-o acima.",
  too_many_pending_requests:
    "A empresa já tem cinco solicitações em análise. Aguarde a resposta da SmallFlags.",
  segment_required: "Escolha o segmento da sua empresa para a posição Outros.",
  segment_not_approved: "Esse segmento não está disponível para contratação.",
  segment_already_in_exclusivity:
    "Esse segmento já ocupa outra posição desta exclusividade.",
  supermarket_not_substitutable: "A posição Supermercado não pode ser substituída.",
  position_not_substitutable: "Esta posição não aceita segmento de Outros.",
  reservation_segment_mismatch:
    "Sua empresa já tem uma reserva nesta posição com outro segmento.",
  company_already_waitlisted_other_segment:
    "Sua empresa já está na fila desta posição com outro segmento.",
  not_authorized: "Acesso restrito à administração da SmallFlags.",
  request_already_decided: "Esta solicitação já foi decidida.",
  decision_note_required: "Explique o motivo da rejeição (mínimo de 5 caracteres).",
  classification_already_approved:
    "Já existe segmento aprovado com essa classificação. Vincule a solicitação a ele.",
  segment_code_taken: "Já existe segmento com esse código.",
  invalid_segment_definition:
    "Definição inválida. Confira código, classificação e, se houver sobreposição a um nicho, a política de delimitação (mínimo de 20 caracteres).",
};

export function mensagemSegmento(codigo: string): string {
  return MENSAGENS[codigo] ?? "Não foi possível concluir agora. Tente novamente.";
}
