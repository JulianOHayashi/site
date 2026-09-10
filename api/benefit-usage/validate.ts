/**
 * POST /api/benefit-usage/validate — FUNÇÃO SERVERLESS NODE DA VERCEL.
 *
 * Casca fina de propósito: traduz HTTP para o núcleo em
 * `src/server/benefitUsage/validateHandler.ts` e traduz erro de volta em
 * status. Nenhuma regra vive aqui.
 *
 * ESTE ARQUIVO NUNCA VAI PARA O NAVEGADOR. Ele lê
 * `BDFLOW_APP_BRIDGE_SIGNING_KEY` do ambiente do processo — variável sem
 * prefixo `VITE_`, portanto invisível ao build do cliente por construção, não
 * por disciplina.
 *
 * O banco é acessado COMO O USUÁRIO logado: a função monta um cliente com a
 * chave pública anônima mais o Bearer da sessão do parceiro. Não há
 * service_role aqui — dar autoridade ampla de banco a um endpoint público
 * seria trocar RLS por confiança.
 */

import { createClient } from "@supabase/supabase-js";
import { BenefitUsageError } from "../../src/server/benefitUsage/benefitUsageContract";
import { createBenefitUsageGatewayClient } from "../../src/server/benefitUsage/benefitUsageGatewayClient";
import {
  executarUsoDeBeneficio,
  type UserScopedDb,
} from "../../src/server/benefitUsage/validateHandler";

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
    res.status(400).json({ ok: false, code: "invalid_locator" });
    return;
  }

  try {
    // Falha fechada de configuração: sem as cinco variáveis do gateway, nada
    // é enviado e a chamada NÃO degrada para requisição sem assinatura.
    const gateway = createBenefitUsageGatewayClient(process.env);

    const resultado = await executarUsoDeBeneficio(
      {
        publicLookupId: corpo.public_lookup_id,
        rawTokenSecret: corpo.raw_token_secret,
        unitId: corpo.unit_id,
        physicalPhotoIdChecked: corpo.physical_photo_id_checked,
      },
      bearer(req.headers),
      { criarDbDoUsuario: criarDbDoUsuario(url, anonKey), gateway }
    );
    res.status(200).json(resultado);
  } catch (e) {
    // NADA do erro original atravessa. A pilha desta função tocou o segredo
    // cru; devolver `e.message` ao navegador ou ao log seria o caminho mais
    // curto para vazá-lo.
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
