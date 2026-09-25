import { createHmac } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export type HttpHeaders = Record<string, string | string[] | undefined>;

export type PublicWriteBackend = {
  db: SupabaseClient;
  fingerprintSecret: string;
};

function header(headers: HttpHeaders, name: string): string | null {
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() !== wanted) continue;
    const first = Array.isArray(value) ? value[0] : value;
    return typeof first === "string" && first.trim() ? first.trim() : null;
  }
  return null;
}

export function loadPublicWriteBackend(): PublicWriteBackend | null {
  const url = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !service) return null;

  return {
    db: createClient(url, service, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
    // HMAC only. The secret itself is never persisted, returned or logged.
    fingerprintSecret: service,
  };
}

export function clientAddress(headers: HttpHeaders): string {
  const forwarded =
    header(headers, "x-vercel-forwarded-for") ??
    header(headers, "x-forwarded-for") ??
    header(headers, "x-real-ip") ??
    "unknown";

  const first = forwarded.split(",")[0]?.trim() || "unknown";
  return first.slice(0, 128);
}

export function isJsonRequest(headers: HttpHeaders): boolean {
  const contentType = header(headers, "content-type");
  return contentType?.toLowerCase().startsWith("application/json") === true;
}

export function parseBody(body: unknown): Record<string, unknown> | null {
  if (typeof body === "string") {
    try {
      const parsed = JSON.parse(body);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? (parsed as Record<string, unknown>)
        : null;
    } catch {
      return null;
    }
  }

  return body && typeof body === "object" && !Array.isArray(body)
    ? (body as Record<string, unknown>)
    : null;
}

function fingerprint(secret: string, scope: string, raw: string): string {
  return createHmac("sha256", secret)
    .update(scope)
    .update("\0")
    .update(raw)
    .digest("hex");
}

export async function consumeRateLimit(
  backend: PublicWriteBackend,
  scope: string,
  rawIdentity: string,
  windowSeconds: number,
  limit: number
): Promise<"allowed" | "blocked" | "error"> {
  const { data, error } = await backend.db.rpc("consume_public_write_rate_limit", {
    p_action: scope,
    p_fingerprint: fingerprint(
      backend.fingerprintSecret,
      scope,
      rawIdentity.slice(0, 512)
    ),
    p_window_seconds: windowSeconds,
    p_limit: limit,
  });

  if (error || !data || typeof data !== "object") return "error";
  const result = data as Record<string, unknown>;
  if (result.ok !== true || typeof result.allowed !== "boolean") return "error";
  return result.allowed ? "allowed" : "blocked";
}

export async function enforceTwoLimits(params: {
  backend: PublicWriteBackend;
  headers: HttpHeaders;
  action: string;
  subject: string;
  ipWindowSeconds: number;
  ipLimit: number;
  subjectWindowSeconds: number;
  subjectLimit: number;
}): Promise<"allowed" | "blocked" | "error"> {
  const ip = await consumeRateLimit(
    params.backend,
    `${params.action}:ip`,
    clientAddress(params.headers),
    params.ipWindowSeconds,
    params.ipLimit
  );
  if (ip !== "allowed") return ip;

  return consumeRateLimit(
    params.backend,
    `${params.action}:subject`,
    params.subject || "missing",
    params.subjectWindowSeconds,
    params.subjectLimit
  );
}
