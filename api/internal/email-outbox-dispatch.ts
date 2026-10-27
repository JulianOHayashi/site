/**
 * GET /api/internal/email-outbox-dispatch — UM ciclo do worker de e-mail (R16).
 *
 * Endpoint interno para agendador (Vercel Cron). Exige
 * `Authorization: Bearer <CRON_SECRET>` e falha fechado sem ele. Toda a
 * lógica vive em `src/server/worker/emailOutboxCronHandler.ts`; aqui só se
 * liga a requisição da plataforma ao núcleo.
 *
 * Nada de valor de ambiente, destinatário, payload ou erro cru na resposta.
 */

import { executarCicloEmailAgendado } from "../../src/server/worker/emailOutboxCronHandler.js";

type Req = {
  method?: string;
  headers: Record<string, string | string[] | undefined>;
};

type Res = {
  status: (c: number) => Res;
  json: (b: unknown) => void;
  setHeader: (k: string, v: string) => void;
};

export default async function handler(req: Req, res: Res): Promise<void> {
  const r = await executarCicloEmailAgendado(req, process.env);
  for (const [k, v] of Object.entries(r.headers)) res.setHeader(k, v);
  res.status(r.status).json(r.body);
}
