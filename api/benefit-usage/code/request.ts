/**
 * POST /api/benefit-usage/code/request — CÓDIGO MANUAL DO BALCÃO.
 * FUNÇÃO SERVERLESS NODE. EXCLUSIVAMENTE DE SERVIDOR.
 *
 * Mesma forma de segurança do endpoint de QR: POST apenas, Bearer da sessão
 * obrigatório, banco acessado COMO O USUÁRIO (anon key + Bearer), sem
 * service_role, configuração de gateway falhando fechada, e nenhum erro
 * original atravessando.
 *
 * O CÓDIGO DIGITADO NÃO É REGISTRADO. Ele circula nesta pilha, e devolver
 * `e.message` ou logar qualquer coisa aqui seria o caminho mais curto para
 * ele acabar num arquivo de log.
 *
 * Caminho raso em `api/`, sem sublinhado em nenhum segmento: a Vercel não
 * transforma caminho com sublinhado em função.
 */

import { createClient } from "@supabase/supabase-js";
import { BenefitUsageError } from "../../../src/server/benefitUsage/benefitUsageContract.js";
import { createBenefitUsageGatewayClient } from "../../../src/server/benefitUsage/benefitUsageGatewayClient.js";
import { executarCodigoManual } from "../../../src/server/benefitUsage/manualCodeHandler.js";
import type { UserScopedDb } from "../../../src/server/benefitUsage/validateHandler.js";

type Req = {
  method?: string;
  body?: unknown;
  headers: Record<string, string | string[] | undefined>;
};

type Res = {
  status: (code: number) => Res;
  json: (body: unknown) => void;
  setHeader: (k: string, v: string) => void;
};

function bearer(headers: Req["headers"]): string | null {
  const h = headers.authorization ?? headers.Authorization;
  const v = Array.isArray(h) ? h[0] : h;
  if (typeof v !== "string") return null;
  const m = /^Bearer\s+(.+)$/i.exec(v.trim());
  return m ? m[1] : null;
}

function criarDbDoUsuario(url: string, anonKey: string) {
  return (accessToken: string): UserScopedDb =>
    createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    }) as unknown as UserScopedDb;
}

export default async function handler(req: Req, res: Res): Promise<void> {
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "POST") {
    res.status(405).json({ ok: false, code: "method_not_allowed" });
    return;
  }

  const url = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL;
  const anonKey =
    process.env.SUPABASE_ANON_KEY ?? process.env.VITE_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    res.status(503).json({ ok: false, code: "site_backend_unavailable" });
    return;
  }

  const corpo = (typeof req.body === "string"
    ? safeParse(req.body)
    : req.body) as Record<string, unknown> | null;
  if (!corpo || typeof corpo !== "object") {
    res.status(400).json({ ok: false, code: "invalid_display_code" });
    return;
  }

  try {
    // Falha fechada de configuração: sem as cinco variáveis do gateway nada é
    // enviado, e nunca se degrada para requisição sem assinatura.
    const gateway = createBenefitUsageGatewayClient(process.env);

    const resultado = await executarCodigoManual(
      {
        displayCode: corpo.display_code,
        unitId: corpo.unit_id,
        physicalPhotoIdChecked: corpo.physical_photo_id_checked,
      },
      bearer(req.headers),
      { criarDbDoUsuario: criarDbDoUsuario(url, anonKey), gateway }
    );
    res.status(200).json(resultado);
  } catch (e) {
    if (e instanceof BenefitUsageError) {
      res.status(e.status).json({ ok: false, code: e.code });
      return;
    }
    res.status(500).json({ ok: false, code: "unexpected_error" });
  }
}

function safeParse(s: string): Record<string, unknown> | null {
  try {
    const v = JSON.parse(s);
    return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}