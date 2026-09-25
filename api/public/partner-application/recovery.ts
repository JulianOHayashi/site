import {
  enforceTwoLimits,
  isJsonRequest,
  loadPublicWriteBackend,
  parseBody,
  type HttpHeaders,
} from "../../../src/server/publicWrites/publicWriteSecurity.js";

type Req = { method?: string; body?: unknown; headers: HttpHeaders };
type Res = {
  status: (code: number) => Res;
  json: (body: unknown) => void;
  setHeader: (key: string, value: string) => void;
};

export default async function handler(req: Req, res: Res): Promise<void> {
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "POST") {
    res.status(405).json({ ok: false, reason: "method_not_allowed" });
    return;
  }
  if (!isJsonRequest(req.headers)) {
    res.status(415).json({ ok: false, reason: "unsupported_media_type" });
    return;
  }

  const backend = loadPublicWriteBackend();
  if (!backend) {
    res.status(503).json({ ok: false, reason: "site_backend_unavailable" });
    return;
  }

  const body = parseBody(req.body);
  if (!body) {
    res.status(400).json({ ok: false, reason: "invalid_payload" });
    return;
  }

  const cnpj = String(body.cnpj ?? "").replace(/\D/g, "");
  const email = String(body.email ?? "").trim().toLowerCase();
  const gate = await enforceTwoLimits({
    backend,
    headers: req.headers,
    action: "partner_application_recovery",
    subject: `${cnpj}:${email}`,
    ipWindowSeconds: 15 * 60,
    ipLimit: 10,
    subjectWindowSeconds: 10 * 60,
    subjectLimit: 3,
  });

  if (gate === "blocked") {
    res.status(429).json({ ok: false, reason: "rate_limited" });
    return;
  }
  if (gate === "error") {
    res.status(503).json({ ok: false, reason: "site_backend_unavailable" });
    return;
  }

  const { error } = await backend.db.rpc("request_partner_application_recovery", {
    p_cnpj: cnpj,
    p_email: email,
  });
  if (error) {
    res.status(500).json({ ok: false, reason: "rpc_error" });
    return;
  }

  // Response intentionally invariant: never reveal whether the application exists.
  res.status(200).json({ ok: true });
}
