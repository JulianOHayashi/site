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
  const niche = String(body.niche_code ?? "").trim().toLowerCase();
  const uf = String(body.uf ?? "").trim().toUpperCase();
  const city = String(body.city ?? "").trim().toLowerCase();

  const gate = await enforceTwoLimits({
    backend,
    headers: req.headers,
    action: "territorial_waitlist_register",
    subject: cnpj + ":" + uf + ":" + city + ":" + niche,
    ipWindowSeconds: 15 * 60,
    ipLimit: 10,
    subjectWindowSeconds: 24 * 60 * 60,
    subjectLimit: 5,
  });

  if (gate === "blocked") {
    res.status(429).json({ ok: false, reason: "rate_limited" });
    return;
  }

  if (gate === "error") {
    res.status(503).json({ ok: false, reason: "site_backend_unavailable" });
    return;
  }

  const { data, error } = await backend.db.rpc(
    "register_territorial_waitlist_interest",
    {
      p_cnpj: cnpj,
      p_company_name: String(body.company_name ?? ""),
      p_responsible_name: String(body.responsible_name ?? ""),
      p_email: String(body.email ?? ""),
      p_phone:
        typeof body.phone === "string" && body.phone.trim() ? body.phone : null,
      p_uf: uf,
      p_city: String(body.city ?? ""),
      p_niche_code: String(body.niche_code ?? ""),
    }
  );

  if (error || !data || typeof data !== "object") {
    res.status(500).json({ ok: false, reason: "rpc_error" });
    return;
  }

  const result = data as Record<string, unknown>;
  if (result.ok !== true) {
    res.status(200).json({
      ok: false,
      reason: typeof result.reason === "string" ? result.reason : "unexpected_error",
    });
    return;
  }

  res.status(200).json({ ok: true, already: false });
}
