/**
 * POST /api/payments/create — FUNÇÃO SERVERLESS NODE. SERVER-ONLY.
 *
 * Casca fina: traduz HTTP para `criarPagamento` e erro em status. Nenhuma
 * regra vive aqui.
 *
 * DUAS IDENTIDADES DE BANCO
 * A abertura da tentativa roda COMO O USUÁRIO (anon key + Bearer): quem pode
 * pagar é decidido por RLS e pela RPC, não por este endpoint. A gravação dos
 * identificadores do provedor roda com `SUPABASE_SERVICE_ROLE_KEY`, porque a
 * RPC correspondente é `service_role` — ela não tem ator humano.
 *
 * Nenhuma das duas chaves entra no navegador: ambas são lidas do ambiente do
 * processo e nenhuma tem prefixo `VITE_`.
 */

import { createClient } from "@supabase/supabase-js";
import { PaymentError, criarPagamento, type Db } from "../../src/server/payments/paymentCore.js";
import { createPagarmeClient, PagarmeConfigError } from "../../src/server/payments/pagarmeClient.js";

type Req = {
  method?: string;
  body?: unknown;
  headers: Record<string, string | string[] | undefined>;
};
type Res = {
  status: (c: number) => Res;
  json: (b: unknown) => void;
  setHeader: (k: string, v: string) => void;
};

function bearer(h: Req["headers"]): string | null {
  const v = h.authorization ?? h.Authorization;
  const s = Array.isArray(v) ? v[0] : v;
  if (typeof s !== "string") return null;
  const m = /^Bearer\s+(.+)$/i.exec(s.trim());
  return m ? m[1] : null;
}

export default async function handler(req: Req, res: Res): Promise<void> {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, code: "method_not_allowed" });
    return;
  }

  const url = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY ?? process.env.VITE_SUPABASE_ANON_KEY;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anon || !service) {
    res.status(503).json({ ok: false, code: "site_backend_unavailable" });
    return;
  }

  const corpo = (typeof req.body === "string" ? safeParse(req.body) : req.body) as
    | Record<string, unknown>
    | null;
  if (!corpo || typeof corpo !== "object") {
    res.status(400).json({ ok: false, code: "invalid_order" });
    return;
  }

  try {
    // Valida a configuração ANTES de abrir qualquer tentativa local no banco.
    // Assim ausência da chave do provedor não deixa pedido/tentativa pela metade.
    const provedor = createPagarmeClient(process.env);

    const resultado = await criarPagamento(
      { orderId: corpo.order_id, installments: corpo.installments },
      bearer(req.headers),
      {
        criarDbDoUsuario: (token) =>
          createClient(url, anon, {
            auth: { persistSession: false, autoRefreshToken: false },
            global: { headers: { Authorization: `Bearer ${token}` } },
          }) as unknown as Db,
        dbPrivilegiado: () =>
          createClient(url, service, {
            auth: { persistSession: false, autoRefreshToken: false },
          }) as unknown as Db,
        provedor: () => provedor,
      }
    );
    res.status(200).json(resultado);
  } catch (e) {
    // Nada do erro original atravessa: esta pilha tocou credencial.
    if (e instanceof PagarmeConfigError) {
      res.status(503).json({ ok: false, code: e.code });
      return;
    }
    if (e instanceof PaymentError) {
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
