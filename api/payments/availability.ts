/**
 * GET /api/payments/availability — disponibilidade do provedor de pagamento.
 *
 * Endpoint público e sem dados sensíveis. Ele devolve APENAS um booleano:
 * a chave/configuração do provedor está utilizável pelo runtime ou não.
 * Nenhum valor de ambiente, detalhe de credencial ou erro interno é exposto.
 */

import { loadPagarmeConfig } from "../../src/server/payments/pagarmeClient.js";

type Req = { method?: string };
type Res = {
  status: (c: number) => Res;
  json: (b: unknown) => void;
  setHeader: (k: string, v: string) => void;
};

export default function handler(req: Req, res: Res): void {
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "GET") {
    res.status(405).json({ ok: false, code: "method_not_allowed" });
    return;
  }

  try {
    loadPagarmeConfig(process.env);
    res.status(200).json({ ok: true, payment_available: true });
  } catch {
    // Fail-closed e sem ecoar detalhe de configuração.
    res.status(200).json({ ok: true, payment_available: false });
  }
}
