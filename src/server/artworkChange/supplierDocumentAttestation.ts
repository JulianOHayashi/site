/**
 * R4.2.1 (P1-4) — ATESTADO do documento do fornecedor pelo servidor.
 *
 * O administrador envia o orçamento original do fornecedor ao bucket privado
 * `supplier-quote-documents` e o registra (com o SHA-256 que ele declara).
 * Este núcleo, com service_role, BAIXA OS BYTES do objeto, calcula o SHA-256
 * e grava o atestado (`service_artwork_change_attest_supplier_document`). O
 * banco só aceita orçamento com documento atestado IGUAL ao declarado.
 *
 * Quem chama: administrador do Site autenticado (Bearer do usuário). O
 * resultado não depende de quem chama: o hash vem dos bytes, não do pedido.
 * Nada de chave, conteúdo do documento ou erro cru na resposta.
 */
import { createHash } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

export type DocumentoRegistrado = {
  storageBucket: string;
  storagePath: string;
  storageObjectId: string;
  byteSize: number;
};

export type DependenciasAtestado = {
  /** true se o portador do token for administrador do Site. */
  ehAdministrador(token: string): Promise<boolean>;
  lerDocumento(documentId: string): Promise<DocumentoRegistrado | null>;
  baixarObjeto(bucket: string, caminho: string): Promise<Uint8Array | null>;
  atestar(args: { documentId: string; storageObjectId: string; sha256: string; byteSize: number }):
    Promise<Record<string, unknown> | null>;
};

export type RequisicaoAtestado = {
  method?: string;
  headers: Record<string, string | string[] | undefined>;
  body?: unknown;
};

export type RespostaAtestado = { status: number; body: Record<string, unknown> };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LIMITE_BYTES = 20 * 1024 * 1024;

function bearer(headers: RequisicaoAtestado["headers"]): string | null {
  for (const [k, v] of Object.entries(headers)) {
    if (k.toLowerCase() !== "authorization") continue;
    const s = Array.isArray(v) ? v[0] : v;
    const m = typeof s === "string" ? /^Bearer\s+(\S+)$/i.exec(s.trim()) : null;
    return m ? m[1] : null;
  }
  return null;
}

function corpo(body: unknown): Record<string, unknown> | null {
  if (typeof body === "string") {
    try { const j = JSON.parse(body); return j && typeof j === "object" && !Array.isArray(j) ? j : null; } catch { return null; }
  }
  return body && typeof body === "object" && !Array.isArray(body) ? (body as Record<string, unknown>) : null;
}

export function sha256Hex(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export async function atestarDocumentoFornecedor(
  req: RequisicaoAtestado, deps: DependenciasAtestado,
): Promise<RespostaAtestado> {
  if ((req.method ?? "").toUpperCase() !== "POST") return { status: 405, body: { ok: false, reason: "method_not_allowed" } };
  const token = bearer(req.headers);
  if (!token) return { status: 401, body: { ok: false, reason: "not_authenticated" } };
  if (!(await deps.ehAdministrador(token))) return { status: 403, body: { ok: false, reason: "not_authorized" } };
  const b = corpo(req.body);
  const id = typeof b?.document_id === "string" ? b.document_id : "";
  if (!UUID.test(id)) return { status: 400, body: { ok: false, reason: "invalid_document_id" } };

  const doc = await deps.lerDocumento(id);
  if (!doc) return { status: 404, body: { ok: false, reason: "not_found" } };
  if (doc.byteSize <= 0 || doc.byteSize > LIMITE_BYTES) return { status: 422, body: { ok: false, reason: "invalid_size" } };
  const bytes = await deps.baixarObjeto(doc.storageBucket, doc.storagePath);
  if (!bytes) return { status: 502, body: { ok: false, reason: "storage_download_failed" } };
  // O tamanho baixado precisa ser o registrado; senão o objeto mudou.
  if (bytes.byteLength !== doc.byteSize) return { status: 409, body: { ok: false, reason: "storage_object_changed" } };

  const sha = sha256Hex(bytes);
  const r = await deps.atestar({ documentId: id, storageObjectId: doc.storageObjectId, sha256: sha, byteSize: bytes.byteLength });
  if (!r) return { status: 502, body: { ok: false, reason: "attestation_failed" } };
  if (r.ok === true) return { status: 200, body: { ok: true, document_id: id, attested_sha256: sha } };
  const reason = typeof r.reason === "string" ? r.reason : "attestation_failed";
  // Divergência com o declarado fica registrada no banco; aqui só informa.
  return { status: reason === "supplier_document_sha256_mismatch" ? 409 : 422,
           body: { ok: false, reason, attested_sha256: sha } };
}

/** Dependências reais (Supabase). Retorna null sem configuração. */
export function dependenciasSupabase(env: Record<string, string | undefined>): DependenciasAtestado | null {
  const url = env.SUPABASE_URL ?? env.VITE_SUPABASE_URL;
  const service = env.SUPABASE_SERVICE_ROLE_KEY;
  const anon = env.SUPABASE_ANON_KEY ?? env.VITE_SUPABASE_ANON_KEY;
  if (!url || !service || !anon) return null;
  const opcoes = { auth: { persistSession: false, autoRefreshToken: false } };
  const db = createClient(url, service, opcoes);
  return {
    async ehAdministrador(token) {
      const u = createClient(url, anon, { ...opcoes, global: { headers: { Authorization: `Bearer ${token}` } } });
      const r = await u.rpc("is_site_admin");
      return !r.error && r.data === true;
    },
    async lerDocumento(documentId) {
      const r = await db.from("commercial_artwork_change_supplier_documents")
        .select("storage_bucket, storage_path, storage_object_id, byte_size").eq("id", documentId).maybeSingle();
      if (r.error || !r.data) return null;
      return { storageBucket: r.data.storage_bucket, storagePath: r.data.storage_path,
               storageObjectId: r.data.storage_object_id, byteSize: Number(r.data.byte_size) };
    },
    async baixarObjeto(bucket, caminho) {
      const r = await db.storage.from(bucket).download(caminho);
      if (r.error || !r.data) return null;
      return new Uint8Array(await r.data.arrayBuffer());
    },
    async atestar(a) {
      const r = await db.rpc("service_artwork_change_attest_supplier_document", {
        p_document_id: a.documentId, p_storage_object_id: a.storageObjectId,
        p_computed_sha256: a.sha256, p_byte_size: a.byteSize,
      });
      return r.error || !r.data || typeof r.data !== "object" ? null : (r.data as Record<string, unknown>);
    },
  };
}
