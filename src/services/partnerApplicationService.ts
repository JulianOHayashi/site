import { supabase } from "../lib/supabase";

/**
 * Camada de serviço do onboarding Fase 2A.
 *
 * O frontend NUNCA é autoridade de status, papel ou permissão: ele apenas
 * chama RPCs e reflete o que o backend decidir. Nenhuma validação daqui
 * substitui as constraints e a RLS do banco — a validação local existe só
 * para dar retorno imediato ao usuário.
 */

export type ResultadoRpc<T> = { ok: true; dados: T } | { ok: false; motivo: string };

/** Motivos técnicos do backend traduzidos para texto seguro ao usuário. */
const MENSAGENS: Record<string, string> = {
  invalid_payload: "Não foi possível processar os dados enviados.",
  invalid_data: "Confira os dados informados e tente novamente.",
  invalid_cnpj: "Informe um CNPJ válido com 14 dígitos.",
  application_in_progress:
    "Já existe uma solicitação em andamento para este CNPJ. Se ela é sua, verifique seu e-mail.",
  invalid_token: "Este link não é válido.",
  token_expired: "Este link expirou. Solicite um novo e-mail de confirmação.",
  token_already_used: "Este link já foi utilizado.",
  token_invalidated: "Este link foi substituído por um mais recente.",
  not_authenticated: "Faça login para continuar.",
  not_allowed: "Esta ação não está disponível para a sua solicitação.",
  not_found: "Item não encontrado.",
  invalid_path: "Arquivo inválido.",
  invalid_document: "Documento inválido. Verifique formato e tamanho.",
  duplicate_document: "Este documento já foi enviado.",
  already_linked: "Esta solicitação já está vinculada a outra conta.",
  reviews_incomplete: "As análises de empresa e autoridade precisam estar aprovadas.",
  reason_required: "Informe o motivo da decisão.",
  not_reviewable: "Esta solicitação não está em análise.",
  not_rejected: "Esta solicitação não está rejeitada.",
  already_reconsidered: "Esta solicitação já teve uma reconsideração.",
  cnpj_has_active_application: "Já existe outra solicitação ativa para este CNPJ.",
  deadline_expired: "O prazo de reconsideração terminou.",
  not_authorized: "Você não tem permissão para esta ação.",
};

export function mensagemDeMotivo(motivo: string): string {
  return MENSAGENS[motivo] ?? "Não foi possível concluir. Tente novamente.";
}

async function chamarRpc<T>(nome: string, args: Record<string, unknown>): Promise<ResultadoRpc<T>> {
  if (!supabase) return { ok: false, motivo: "not_configured" };

  const { data, error } = await supabase.rpc(nome, args);
  if (error) {
    // Mensagem do Postgres nunca é repassada crua ao usuário.
    return { ok: false, motivo: error.message.includes("not_authorized") ? "not_authorized" : "rpc_error" };
  }
  const resposta = data as { ok?: boolean; reason?: string } | null;
  if (!resposta || typeof resposta !== "object") return { ok: false, motivo: "rpc_error" };
  if (resposta.ok === false) return { ok: false, motivo: resposta.reason ?? "rpc_error" };
  return { ok: true, dados: resposta as T };
}

// ---------------------------------------------------------------------------
// Solicitação empresarial (pré-Auth)
// ---------------------------------------------------------------------------
export type DadosSolicitacao = {
  cnpj: string;
  legal_name: string;
  trade_name?: string;
  contact_email: string;
  contact_phone?: string;
  postal_code?: string;
  street?: string;
  street_number?: string;
  complement?: string;
  district?: string;
  city: string;
  uf: string;
  representative_full_name: string;
  representative_cpf: string;
  representative_email?: string;
  representative_phone?: string;
  representative_role_title?: string;
};

export function criarSolicitacao(dados: DadosSolicitacao) {
  return chamarRpc<{ application_id: string; status: string }>(
    "create_partner_application",
    { p_payload: dados }
  );
}

export function confirmarEmail(token: string) {
  return chamarRpc<{
    application_id: string;
    status: string;
    already_confirmed: boolean;
    claim_token?: string;
  }>("confirm_partner_application_email", { p_token: token });
}

export function vincularContaProvisoria(claimToken: string) {
  return chamarRpc<{ application_id: string; account_kind: string; already_linked: boolean }>(
    "claim_partner_application_account",
    { p_claim_token: claimToken }
  );
}

export type MinhaSolicitacao = {
  application_id: string | null;
  status?: string;
  company_review_status?: string;
  authority_review_status?: string;
  account_kind?: string;
  cnpj?: string;
  legal_name?: string;
  city?: string;
  uf?: string;
  pending_corrections?: number;
  documents?: number;
};

export async function obterMinhaSolicitacao(): Promise<MinhaSolicitacao | null> {
  if (!supabase) return null;
  const { data, error } = await supabase.rpc("get_my_partner_application", {});
  if (error) return null;
  return (data as MinhaSolicitacao) ?? null;
}

export function responderCorrecao(correctionId: string, mensagem: string) {
  return chamarRpc<{ correction_id: string }>("respond_partner_application_correction", {
    p_correction_id: correctionId,
    p_message: mensagem,
  });
}

// ---------------------------------------------------------------------------
// Administração
// ---------------------------------------------------------------------------
export type SolicitacaoAdmin = {
  application_id: string;
  cnpj: string;
  legal_name: string;
  city: string;
  uf: string;
  status: string;
  company_review_status: string;
  authority_review_status: string;
  created_at: string;
  representative: { id: string; full_name: string; authority_status: string } | null;
};

export function listarSolicitacoesAdmin(status?: string) {
  return chamarRpc<{ items: SolicitacaoAdmin[] }>("admin_list_partner_applications", {
    p_status: status ?? null,
    p_limit: 50,
    p_offset: 0,
  });
}

export function analisarEmpresa(applicationId: string, decisao: string, motivo?: string) {
  return chamarRpc<{ company_review_status: string }>("admin_review_partner_company", {
    p_application_id: applicationId,
    p_decision: decisao,
    p_reason: motivo ?? null,
  });
}

export function analisarAutoridade(applicationId: string, decisao: string, motivo?: string) {
  return chamarRpc<{ authority_review_status: string }>("admin_review_partner_authority", {
    p_application_id: applicationId,
    p_decision: decisao,
    p_reason: motivo ?? null,
  });
}

export function solicitarCorrecao(applicationId: string, escopo: string, mensagem: string) {
  return chamarRpc<{ correction_id: string }>("admin_request_partner_correction", {
    p_application_id: applicationId,
    p_scope: escopo,
    p_message: mensagem,
  });
}

export function decidirSolicitacao(applicationId: string, decisao: string, motivo?: string) {
  return chamarRpc<{ status: string }>("admin_decide_partner_application", {
    p_application_id: applicationId,
    p_decision: decisao,
    p_reason: motivo ?? null,
  });
}
