/**
 * POST /api/payments/webhook — notificação do Pagar.me. SERVER-ONLY.
 *
 * O CORPO NÃO É AUTORIDADE. Dele sai apenas o identificador do pedido no
 * provedor; status, valor e método presentes na notificação são ignorados de
 * propósito. A verdade é lida servidor-a-servidor com a chave secreta, e a
 * RPC canônica confere tudo contra o registro local antes de mudar estado.
 *
 * Um corpo forjado dizendo "paid" não tem, portanto, como produzir pago.
 *
 * Responde 200 mesmo quando não reconcilia: o provedor não deve reenviar
 * indefinidamente por causa de um pagamento que não é nosso. O que importa é
 * que o estado local só muda pelo caminho conciliado.
 */

import { createClient } from "@supabase/supabase-js";
import {
  PaymentError,
  WEBHOOK_MAX_BYTES,
  conciliarWebhook,
  type Db,
} from "../../src/server/payments/paymentCore.js";
import { createPagarmeClient } from "../../src/server/payments/pagarmeClient.js";

type Req = { method?: string; body?: unknown };
type Res = {
  status: (c: number) => Res;
  json: (b: unknown) => void;
  setHeader: (k: string, v: string) => void;
};

export default async function handler(req: Req, res: Res): Promise<void> {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, code: "method_not_allowed" });
    return;
  }

  const url = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !service) {
    res.status(503).json({ ok: false, code: "site_backend_unavailable" });
    return;
  }

  const bruto =
    typeof req.body === "string" ? req.body : JSON.stringify(req.body ?? null);
  if (bruto.length > WEBHOOK_MAX_BYTES) {
    res.status(413).json({ ok: false, code: "payload_too_large" });
    return;
  }

  try {
    const r = await conciliarWebhook(bruto, {
      dbPrivilegiado: () =>
        createClient(url, service, {
          auth: { persistSession: false, autoRefreshToken: false },
        }) as unknown as Db,
      provedor: () => createPagarmeClient(process.env),
    });
    // Só o código curto volta. Nenhum dado do pedido, nenhum valor.
    res.status(200).json({ ok: r.ok, code: r.code });
  } catch (e) {
    if (e instanceof PaymentError) {
      res.status(e.status).json({ ok: false, code: e.code });
      return;
    }
    res.status(500).json({ ok: false, code: "unexpected_error" });
  }
}
