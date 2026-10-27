/**
 * R16 — AUTENTICAÇÃO DA INVOCAÇÃO AGENDADA DO WORKER. SERVER-ONLY.
 *
 * Contrato: `Authorization: Bearer <CRON_SECRET>`. É o cabeçalho que o Vercel
 * Cron envia quando `CRON_SECRET` está definido no projeto.
 *
 * FAIL-CLOSED
 *   - `CRON_SECRET` ausente, vazio ou curto demais  → nunca autoriza;
 *   - cabeçalho ausente, repetido ou fora do formato → nunca autoriza;
 *   - segredo divergente                             → nunca autoriza.
 *
 * Quem chama recebe só "autorizado ou não". O MOTIVO (`motivo`) existe para
 * log server-side e não deve ir para a resposta HTTP: dizer "o servidor não
 * tem segredo configurado" a um chamador anônimo é informação gratuita.
 *
 * Comparação em tempo constante sobre os digests SHA-256 dos dois valores:
 * igualar comprimentos antes do `timingSafeEqual` evita vazar o tamanho do
 * segredo pelo atalho de comprimento diferente.
 *
 * O valor do segredo nunca é logado, retornado ou concatenado em mensagem.
 */

import { createHash, timingSafeEqual } from "node:crypto";

/** Abaixo disso o segredo é tratado como não configurado. */
export const CRON_SECRET_MIN_LENGTH = 16;

export type MotivoAuthCron =
  | "ok"
  | "secret_not_configured"
  | "header_missing"
  | "header_malformed"
  | "secret_mismatch";

export type ResultadoAuthCron = { autorizado: boolean; motivo: MotivoAuthCron };

type Cabecalhos = Record<string, string | string[] | undefined>;

function digest(v: string): Buffer {
  return createHash("sha256").update(v, "utf8").digest();
}

export function autenticarInvocacaoCron(
  headers: Cabecalhos | undefined,
  env: Record<string, string | undefined>
): ResultadoAuthCron {
  const segredo = env.CRON_SECRET;
  // Segredo com espaço em branco não é aparado: o Vercel envia o valor cru, e
  // aparar aqui faria um segredo "válido" nunca bater. Recusa de saída.
  if (
    typeof segredo !== "string" ||
    segredo.length < CRON_SECRET_MIN_LENGTH ||
    /\s/.test(segredo)
  ) {
    return { autorizado: false, motivo: "secret_not_configured" };
  }

  const bruto = headers?.authorization ?? headers?.Authorization;
  if (bruto === undefined) return { autorizado: false, motivo: "header_missing" };
  // Cabeçalho repetido é ambíguo: recusa em vez de escolher um.
  if (Array.isArray(bruto)) {
    if (bruto.length !== 1) return { autorizado: false, motivo: "header_malformed" };
  }
  const valor = Array.isArray(bruto) ? bruto[0] : bruto;
  if (typeof valor !== "string") return { autorizado: false, motivo: "header_malformed" };

  const m = /^Bearer ([^\s]+)$/.exec(valor);
  if (!m) return { autorizado: false, motivo: "header_malformed" };

  const iguais = timingSafeEqual(digest(m[1]), digest(segredo));
  return iguais
    ? { autorizado: true, motivo: "ok" }
    : { autorizado: false, motivo: "secret_mismatch" };
}
