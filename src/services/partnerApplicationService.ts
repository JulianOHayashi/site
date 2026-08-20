import { supabase } from "../lib/supabase";

/**
 * Camada de serviço do onboarding Fase 2A.
 *
 * O frontend NUNCA é autoridade de status, papel ou permissão: ele chama
 * RPCs, lê tabelas sob RLS e reflete o que o backend decidir.
 *
 * Princípio de segurança desta camada: FALHA NUNCA VIRA AUSÊNCIA. Erro de
 * RPC e "não existe" são estados distintos e nunca colapsam no mesmo valor.
 */

export type ResultadoRpc<T> = { ok: true; dados: T } | { ok: false; motivo: string };

const MENSAGENS: Record<string, string> = {
  invalid_payload: "Não foi possível processar os dados enviados.",
  invalid_data: "Confira os dados informados e tente novamente.",
  invalid_cnpj: "Informe um CNPJ válido.",
  invalid_cpf: "Informe um CPF válido.",
  legal_document_unavailable:
    "O cadastro está temporariamente indisponível. Tente novamente mais tarde.",
  acceptance_required: "É necessário aceitar os termos para continuar.",
  acceptance_invalid: "Não foi possível registrar o aceite. Recarregue a página.",
  acceptance_duplicate: "Aceite inválido. Recarregue a página.",
  acceptance_unexpected: "Aceite inválido. Recarregue a página.",
  acceptance_stale:
    "Os termos foram atualizados. Leia a nova versão e aceite novamente para continuar.",
  provisional_terms_required:
    "Você precisa aceitar os termos da conta antes de continuar.",
  storage_object_not_found: "O arquivo não foi encontrado. Envie novamente.",
  storage_object_not_owned: "Este arquivo não pertence à sua solicitação.",
  metadata_mismatch: "O arquivo enviado não confere. Tente novamente.",
  document_superseded: "Este documento foi substituído por uma versão mais recente.",
  already_terminal: "Esta solicitação já está encerrada.",
  application_in_progress:
    "Já existe uma solicitação em andamento para este CNPJ. Se ela é sua, verifique seu e-mail.",
  invalid_token: "Este link não é válido.",
  token_expired: "Este link expirou. Você pode solicitar um novo abaixo.",
  token_already_used: "Este link já foi utilizado.",
  token_invalidated: "Este link foi substituído por um mais recente.",
  not_claimable: "Esta solicitação não está na etapa de criação de acesso.",
  email_mismatch:
    "O e-mail desta conta não é o mesmo que confirmamos na solicitação. Entre com o e-mail informado no cadastro.",
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
  not_configured: "Serviço em configuração.",
  upload_failed: "Não foi possível enviar o arquivo. Tente novamente.",
  rpc_error: "Não foi possível concluir. Tente novamente.",
};

export function mensagemDeMotivo(motivo: string): string {
  return MENSAGENS[motivo] ?? MENSAGENS.rpc_error;
}

/** Nunca repassa mensagem crua do Postgres (SQL, constraint, stack). */
function motivoSeguro(mensagemErro: string): string {
  return mensagemErro.includes("not_authorized") ? "not_authorized" : "rpc_error";
}

async function chamarRpc<T>(nome: string, args: Record<string, unknown>): Promise<ResultadoRpc<T>> {
  if (!supabase) return { ok: false, motivo: "not_configured" };
  const { data, error } = await supabase.rpc(nome, args);
  if (error) return { ok: false, motivo: motivoSeguro(error.message) };
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
  /** IDs exatos dos documentos que o usuário aceitou explicitamente. */
  acceptances: { legal_document_id: string }[];
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
  return chamarRpc<{
    application_id: string;
    account_kind: string;
    status?: string;
    already_linked: boolean;
  }>("claim_partner_application_account", { p_claim_token: claimToken });
}

/**
 * Recuperação pública. A resposta é invariante por desenho: o backend
 * responde igual para dados existentes e inexistentes, e a UI reproduz
 * exatamente a mesma frase nos dois casos.
 */
export async function solicitarRecuperacao(cnpj: string, email: string): Promise<{ ok: boolean }> {
  if (!supabase) return { ok: false };
  const { error } = await supabase.rpc("request_partner_application_recovery", {
    p_cnpj: cnpj,
    p_email: email,
  });
  // Mesmo em erro de transporte não revelamos nada além de "não deu".
  return { ok: !error };
}

// ---------------------------------------------------------------------------
// Documentos jurídicos
// ---------------------------------------------------------------------------
/**
 * O aceite é sempre atado ao ID EXATO do documento vigente. Nunca use um
 * booleano solto: se os termos forem republicados enquanto a tela está
 * aberta, um booleano herdado viraria aceite implícito da versão nova.
 */
export type DocumentoLegal = {
  legal_document_id: string;
  doc_type: string;
  version: string;
  title: string;
  content: string | null;
  content_url: string | null;
  already_accepted?: boolean;
};

export type TermosEstado =
  | { tipo: "carregando" }
  | { tipo: "erro"; motivo: string }
  | { tipo: "carregado"; documentos: DocumentoLegal[] };

async function carregarTermos(rpc: string): Promise<TermosEstado> {
  if (!supabase) return { tipo: "erro", motivo: "not_configured" };
  const { data, error } = await supabase.rpc(rpc, {});
  if (error) return { tipo: "erro", motivo: motivoSeguro(error.message) };
  const r = data as { ok?: boolean; reason?: string; documents?: DocumentoLegal[] } | null;
  if (!r || typeof r !== "object") return { tipo: "erro", motivo: "rpc_error" };
  if (r.ok === false) return { tipo: "erro", motivo: r.reason ?? "rpc_error" };
  return { tipo: "carregado", documentos: r.documents ?? [] };
}

/** Termos exigidos na solicitação empresarial (pré-Auth). */
export function obterTermosSolicitacao() {
  return carregarTermos("get_partner_application_terms");
}

/** Termos exigidos para ativar a conta provisória (já autenticado). */
export function obterTermosContaProvisoria() {
  return carregarTermos("get_provisional_account_terms");
}

/**
 * Registra o aceite ATANDO-O ao documento exato que o usuário viu.
 *
 * Não chamamos `record_legal_acceptance` diretamente: ela resolve o vigente
 * no servidor, e entre o clique do usuário e a chamada os termos podem ter
 * sido republicados — o aceite acabaria recaindo sobre um texto que ninguém
 * leu. O wrapper usa a função protegida como implementação canônica e
 * reverte se o documento persistido não for o esperado.
 */
export function registrarAceiteConta(
  docType: string,
  legalDocumentId: string
): Promise<ResultadoRpc<{ acceptance_id: string; legal_document_id: string }>> {
  return chamarRpc<{ acceptance_id: string; legal_document_id: string }>(
    "record_bound_legal_acceptance",
    {
      p_doc_type: docType,
      p_legal_document_id: legalDocumentId,
      p_client_evidence: { screen: "parceiros/confirmar" },
    }
  );
}

// ---------------------------------------------------------------------------
// Contexto da conta — ESTADO DISCRIMINADO (B3)
// ---------------------------------------------------------------------------
export type Solicitacao = {
  application_id: string;
  status: string;
  company_review_status: string;
  authority_review_status: string;
  account_kind: string;
  cnpj: string;
  legal_name: string;
  city: string;
  uf: string;
  created_at?: string;
  pending_corrections?: number;
  documents?: number;
};

/**
 * Contexto da conta autenticada em relação ao onboarding.
 *
 * Cada estado é distinto por desenho, para que nenhum guard confunda
 * "não sei" com "pode".
 *
 *   carregando            ainda consultando
 *   erro                  falha de RPC, exceção ou resposta malformada
 *   nao_autenticado       sem sessão
 *   sem_contexto_parceiro sessão válida, sem qualquer vínculo de parceria
 *   provisoria            conta provisória de onboarding
 *   parceiro_autorizado   parceiro aprovado e operacional
 *
 * IMPORTANTE — `parceiro_autorizado` NÃO É PRODUZIDO NO M1.
 * A promoção a parceiro aprovado (partner_owner e vínculo operacional)
 * pertence ao M2. O estado existe aqui para que a autorização do Portal
 * seja escrita contra PROVA POSITIVA desde já; enquanto o M2 não existir,
 * simplesmente ninguém o alcança — e o Portal permanece fechado.
 *
 * Ausência de solicitação NÃO é permissão: qualquer conta autenticada sem
 * vínculo cai em `sem_contexto_parceiro`, que os guards devem NEGAR.
 */
export type ContextoConta =
  | { tipo: "carregando" }
  | { tipo: "erro" }
  | { tipo: "nao_autenticado" }
  | { tipo: "sem_contexto_parceiro" }
  | { tipo: "provisoria"; solicitacao: Solicitacao }
  | { tipo: "parceiro_autorizado"; solicitacao?: Solicitacao };

export async function obterContextoConta(): Promise<ContextoConta> {
  if (!supabase) return { tipo: "erro" };

  const { data, error } = await supabase.rpc("get_my_partner_application", {});
  if (error) return { tipo: "erro" };
  if (!data || typeof data !== "object") return { tipo: "erro" };

  const s = data as Partial<Solicitacao>;
  if (!s.application_id) return { tipo: "sem_contexto_parceiro" };
  if (s.account_kind === "provisional") {
    return { tipo: "provisoria", solicitacao: s as Solicitacao };
  }
  // Nenhum outro account_kind confere acesso operacional no M1.
  return { tipo: "sem_contexto_parceiro" };
}

// ---------------------------------------------------------------------------
// Correções
// ---------------------------------------------------------------------------
export type Correcao = {
  id: string;
  application_id: string;
  scope: string;
  message: string;
  requested_at: string;
  response_message: string | null;
  responded_at: string | null;
};

export async function listarCorrecoes(applicationId: string): Promise<ResultadoRpc<Correcao[]>> {
  if (!supabase) return { ok: false, motivo: "not_configured" };
  const { data, error } = await supabase
    .from("partner_application_corrections")
    .select("id, application_id, scope, message, requested_at, response_message, responded_at")
    .eq("application_id", applicationId)
    .order("requested_at", { ascending: false });
  if (error) return { ok: false, motivo: motivoSeguro(error.message) };
  return { ok: true, dados: (data ?? []) as Correcao[] };
}

export function responderCorrecao(correctionId: string, mensagem: string) {
  return chamarRpc<{ correction_id: string }>("respond_partner_application_correction", {
    p_correction_id: correctionId,
    p_message: mensagem,
  });
}

// ---------------------------------------------------------------------------
// Documentos
// ---------------------------------------------------------------------------
export type Documento = {
  id: string;
  application_id: string;
  doc_type: string;
  storage_bucket: string;
  storage_path: string;
  original_filename: string;
  mime_type: string;
  byte_size: number;
  review_status: string;
  review_notes: string | null;
  created_at: string;
  superseded_at: string | null;
  superseded_by_document_id: string | null;
};

export const BUCKET_DOCUMENTOS = "partner-application-docs";

export async function listarDocumentos(applicationId: string): Promise<ResultadoRpc<Documento[]>> {
  if (!supabase) return { ok: false, motivo: "not_configured" };
  const { data, error } = await supabase
    .from("partner_application_documents")
    .select(
      "id, application_id, doc_type, storage_bucket, storage_path, original_filename, mime_type, byte_size, review_status, review_notes, created_at, superseded_at, superseded_by_document_id"
    )
    .eq("application_id", applicationId)
    .order("created_at", { ascending: false });
  if (error) return { ok: false, motivo: motivoSeguro(error.message) };
  return { ok: true, dados: (data ?? []) as Documento[] };
}

/** Caminho novo a cada envio: nunca reaproveita o path de um registrado. */
export function novoCaminhoDocumento(applicationId: string, docType: string, nomeArquivo: string): string {
  const ext = nomeArquivo.includes(".") ? nomeArquivo.split(".").pop()!.toLowerCase() : "bin";
  const carimbo = new Date().toISOString().replace(/[^0-9]/g, "");
  const aleatorio = Math.random().toString(36).slice(2, 10);
  return `${applicationId}/${docType}/${carimbo}-${aleatorio}.${ext}`;
}

/**
 * Upload privado seguido do registro de metadados.
 *
 * NÃO há limpeza pelo cliente (M1-C3). O DELETE direto do solicitante foi
 * removido do bucket porque criava uma corrida contra a própria RPC de
 * registro: entre a validação do objeto e a gravação do metadado, o cliente
 * podia apagar — ou apagar e reenviar outros bytes no mesmo caminho —,
 * deixando metadado sem objeto ou metadado descrevendo conteúdo diferente.
 *
 * Consequência aceita: uma falha de registro pode deixar um objeto órfão. O
 * órfão não tem metadado, não aparece na UI, não é revisável e não é
 * reaproveitável, porque cada tentativa gera caminho novo. A remoção
 * controlada fica para um fluxo server-side posterior.
 */
export async function enviarDocumento(
  applicationId: string,
  docType: string,
  arquivo: File
): Promise<ResultadoRpc<{ document_id: string }>> {
  if (!supabase) return { ok: false, motivo: "not_configured" };

  const caminho = novoCaminhoDocumento(applicationId, docType, arquivo.name);

  const { error: erroUpload } = await supabase.storage
    .from(BUCKET_DOCUMENTOS)
    .upload(caminho, arquivo, { upsert: false, contentType: arquivo.type });
  if (erroUpload) return { ok: false, motivo: "upload_failed" };

  const registro = await chamarRpc<{ document_id: string; supersedes: string | null }>(
    "register_partner_application_document",
    {
      p_doc_type: docType,
      p_storage_path: caminho,
      p_original_filename: arquivo.name,
      p_mime_type: arquivo.type,
      p_byte_size: arquivo.size,
      p_checksum_sha256: null,
    }
  );

  if (!registro.ok) {
    // Sem limpeza pelo cliente: ver a nota acima.
    return { ok: false, motivo: registro.motivo };
  }
  return { ok: true, dados: { document_id: registro.dados.document_id } };
}

/** URL assinada de curta duração. O bucket permanece privado. */
export async function urlAssinadaDocumento(caminho: string): Promise<string | null> {
  if (!supabase) return null;
  const { data, error } = await supabase.storage
    .from(BUCKET_DOCUMENTOS)
    .createSignedUrl(caminho, 60);
  if (error || !data) return null;
  return data.signedUrl;
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

export type DetalheAdmin = {
  aplicacao: Record<string, unknown>;
  representantes: Record<string, unknown>[];
  correcoes: Correcao[];
  documentos: Documento[];
};

export async function obterDetalheAdmin(applicationId: string): Promise<ResultadoRpc<DetalheAdmin>> {
  if (!supabase) return { ok: false, motivo: "not_configured" };

  const [app, reps, corr, docs] = await Promise.all([
    supabase.from("partner_applications").select("*").eq("id", applicationId).maybeSingle(),
    supabase
      .from("partner_application_representatives")
      .select("*")
      .eq("application_id", applicationId)
      .order("created_at", { ascending: false }),
    supabase
      .from("partner_application_corrections")
      .select("*")
      .eq("application_id", applicationId)
      .order("requested_at", { ascending: false }),
    supabase
      .from("partner_application_documents")
      .select("*")
      .eq("application_id", applicationId)
      .order("created_at", { ascending: false }),
  ]);

  if (app.error || reps.error || corr.error || docs.error) {
    return { ok: false, motivo: "rpc_error" };
  }
  if (!app.data) return { ok: false, motivo: "not_found" };

  return {
    ok: true,
    dados: {
      aplicacao: app.data as Record<string, unknown>,
      representantes: (reps.data ?? []) as Record<string, unknown>[],
      correcoes: (corr.data ?? []) as Correcao[],
      documentos: (docs.data ?? []) as Documento[],
    },
  };
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

export function substituirRepresentante(
  applicationId: string,
  payload: { full_name: string; cpf: string; email: string; phone?: string; role_title?: string }
) {
  return chamarRpc<{ representative_id: string }>("admin_replace_partner_representative", {
    p_application_id: applicationId,
    p_payload: payload,
  });
}

export function solicitarCorrecao(applicationId: string, escopo: string, mensagem: string) {
  return chamarRpc<{ correction_id: string }>("admin_request_partner_correction", {
    p_application_id: applicationId,
    p_scope: escopo,
    p_message: mensagem,
  });
}

export function revisarDocumento(documentId: string, decisao: string, notas?: string) {
  return chamarRpc<{ document_id: string }>("admin_review_partner_document", {
    p_document_id: documentId,
    p_decision: decisao,
    p_notes: notas ?? null,
  });
}

export function decidirSolicitacao(applicationId: string, decisao: string, motivo?: string) {
  return chamarRpc<{ status: string }>("admin_decide_partner_application", {
    p_application_id: applicationId,
    p_decision: decisao,
    p_reason: motivo ?? null,
  });
}

/** Encerramento administrativo de solicitação não verificada (B2). */
export function encerrarSolicitacaoAdmin(applicationId: string, motivo: string) {
  return chamarRpc<{ status: string }>("admin_withdraw_partner_application", {
    p_application_id: applicationId,
    p_reason: motivo,
  });
}

export function abrirReconsideracao(applicationId: string) {
  return chamarRpc<{ status: string; mesmo_admin_da_decisao: boolean }>(
    "admin_open_partner_reconsideration",
    { p_application_id: applicationId }
  );
}
