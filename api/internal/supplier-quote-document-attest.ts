/**
 * POST /api/internal/supplier-quote-document-attest — R4.2.1 (P1-4).
 *
 * Administrador do Site pede o ATESTADO de um documento de fornecedor já
 * registrado; o servidor baixa os bytes do bucket privado, calcula o SHA-256
 * e grava o atestado com service_role. Lógica em
 * `src/server/artworkChange/supplierDocumentAttestation.ts`.
 * Sem configuração do servidor: 503 (falha fechada).
 */
import {
  atestarDocumentoFornecedor,
  dependenciasSupabase,
} from "../../src/server/artworkChange/supplierDocumentAttestation.js";

type Req = { method?: string; headers: Record<string, string | string[] | undefined>; body?: unknown };
type Res = { status: (c: number) => Res; json: (b: unknown) => void; setHeader: (k: string, v: string) => void };

export default async function handler(req: Req, res: Res): Promise<void> {
  res.setHeader("Cache-Control", "no-store");
  const deps = dependenciasSupabase(process.env);
  if (!deps) {
    res.status(503).json({ ok: false, reason: "not_configured" });
    return;
  }
  const r = await atestarDocumentoFornecedor(req, deps);
  res.status(r.status).json(r.body);
}
