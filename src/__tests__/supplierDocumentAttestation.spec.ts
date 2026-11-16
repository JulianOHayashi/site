import { describe, expect, it, vi } from "vitest";
import { createHash } from "node:crypto";
import {
  atestarDocumentoFornecedor,
  type DependenciasAtestado,
} from "../server/artworkChange/supplierDocumentAttestation";

// R4.2.1 (P1-4): o SHA-256 do documento do fornecedor é calculado pelo
// servidor sobre os BYTES do objeto, nunca aceito do administrador.
const DOC = "77777777-7777-4777-8777-777777777777";
const OBJ = "88888888-8888-4888-8888-888888888888";
const BYTES = new TextEncoder().encode("%PDF-1.7 orcamento do fornecedor 84 bandeiras");
const SHA = createHash("sha256").update(BYTES).digest("hex");

function deps(over: Partial<DependenciasAtestado> = {}): DependenciasAtestado {
  return {
    ehAdministrador: vi.fn(async () => true),
    lerDocumento: vi.fn(async () => ({ storageBucket: "supplier-quote-documents", storagePath: `req/${DOC}`,
                                      storageObjectId: OBJ, byteSize: BYTES.byteLength })),
    baixarObjeto: vi.fn(async () => BYTES),
    atestar: vi.fn(async () => ({ ok: true })),
    ...over,
  };
}
const req = (body: unknown = { document_id: DOC }, auth = "Bearer token-admin") =>
  ({ method: "POST", headers: { authorization: auth }, body });

describe("R4.2.1 — atestado do documento do fornecedor pelo servidor", () => {
  it("calcula o SHA-256 dos bytes baixados e grava o atestado com o objeto e o tamanho registrados", async () => {
    const d = deps();
    const r = await atestarDocumentoFornecedor(req(), d);
    expect(r).toEqual({ status: 200, body: { ok: true, document_id: DOC, attested_sha256: SHA } });
    expect(d.atestar).toHaveBeenCalledWith({ documentId: DOC, storageObjectId: OBJ, sha256: SHA, byteSize: BYTES.byteLength });
  });

  it("ignora qualquer hash enviado pelo cliente: o atestado usa só os bytes", async () => {
    const d = deps();
    await atestarDocumentoFornecedor(req({ document_id: DOC, sha256: "f".repeat(64) }), d);
    expect(d.atestar).toHaveBeenCalledWith(expect.objectContaining({ sha256: SHA }));
  });

  it("divergência com o declarado: informa 409 (o banco já registrou a divergência)", async () => {
    const d = deps({ atestar: vi.fn(async () => ({ ok: false, reason: "supplier_document_sha256_mismatch" })) });
    const r = await atestarDocumentoFornecedor(req(), d);
    expect(r.status).toBe(409);
    expect(r.body).toMatchObject({ ok: false, reason: "supplier_document_sha256_mismatch", attested_sha256: SHA });
  });

  it("objeto com tamanho diferente do registrado não é atestado", async () => {
    const d = deps({ baixarObjeto: vi.fn(async () => new Uint8Array([1, 2, 3])) });
    const r = await atestarDocumentoFornecedor(req(), d);
    expect(r).toEqual({ status: 409, body: { ok: false, reason: "storage_object_changed" } });
    expect(d.atestar).not.toHaveBeenCalled();
  });

  it.each([
    ["sem token", req(undefined, ""), 401, "not_authenticated"],
    ["método GET", { method: "GET", headers: { authorization: "Bearer t" } }, 405, "method_not_allowed"],
    ["id inválido", req({ document_id: "x" }), 400, "invalid_document_id"],
  ])("recusa %s", async (_n, r0, status, reason) => {
    const d = deps();
    const r = await atestarDocumentoFornecedor(r0 as never, d);
    expect(r).toEqual({ status, body: { ok: false, reason } });
    expect(d.atestar).not.toHaveBeenCalled();
  });

  it("não administrador não aciona download nem atestado", async () => {
    const d = deps({ ehAdministrador: vi.fn(async () => false) });
    const r = await atestarDocumentoFornecedor(req(), d);
    expect(r).toEqual({ status: 403, body: { ok: false, reason: "not_authorized" } });
    expect(d.baixarObjeto).not.toHaveBeenCalled();
  });

  it("falha de download ou de gravação: falha fechada, sem atestado", async () => {
    expect((await atestarDocumentoFornecedor(req(), deps({ baixarObjeto: vi.fn(async () => null) }))).status).toBe(502);
    expect((await atestarDocumentoFornecedor(req(), deps({ atestar: vi.fn(async () => null) }))).status).toBe(502);
    expect((await atestarDocumentoFornecedor(req(), deps({ lerDocumento: vi.fn(async () => null) }))).status).toBe(404);
  });
});
