/**
 * POST /api/gate-d-probe — DIAGNÓSTICO TEMPORÁRIO, SÓ PREVIEW.
 *
 * O arquivo mora DIRETO em `api/`, sem subpasta e sem prefixo de sublinhado.
 * A primeira tentativa viveu em `api/_internal/`, e a Vercel devolveu o 404
 * de plataforma: arquivos com sublinhado na frente são tratados como auxiliar
 * e não viram função. O handler nunca chegou a rodar — o 404 dele seria JSON
 * com `Cache-Control: no-store`, e o observado era texto puro com
 * `X-Vercel-Error: NOT_FOUND`. Caminho raso elimina a ambiguidade.
 *
 * Assina UMA requisição `benefit_usage.open_token` com a chave que a Vercel
 * guarda e envia exatamente os mesmos bytes duas vezes, para o gateway do App
 * provar detecção de replay. Devolve apenas status e um rótulo curto.
 *
 * ESTE ARQUIVO É DESCARTÁVEL. Não pode ser fundido em `main`: é um
 * instrumento de medição, e instrumento de medição em produção vira
 * superfície de ataque. A remoção acontece depois que a evidência ao vivo for
 * colhida, para que o commit exatamente testado permaneça auditável.
 *
 * O endpoint de validação do parceiro não é tocado por nada aqui.
 */

import {
  SondaConfigError,
  SondaIndisponivelError,
  executarSondaGateD,
} from "../src/server/gateD/gateDProbe.js";

type Req = {
  method?: string;
  headers: Record<string, string | string[] | undefined>;
};

type Res = {
  status: (code: number) => Res;
  json: (body: unknown) => void;
  setHeader: (k: string, v: string) => void;
};

export default async function handler(req: Req, res: Res): Promise<void> {
  res.setHeader("Cache-Control", "no-store");

  // Fora do Preview o endpoint não existe. 404, e não 403: dizer "proibido"
  // confirmaria que a rota está lá.
  if (process.env.VERCEL_ENV !== "preview") {
    res.status(404).json({ ok: false, code: "not_found" });
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, code: "method_not_allowed" });
    return;
  }

  try {
    const resultado = await executarSondaGateD(process.env, {
      fetchImpl: globalThis.fetch as never,
    });
    res.status(200).json(resultado);
  } catch (e) {
    // Nenhum detalhe atravessa: esta pilha tocou a configuração de assinatura.
    if (e instanceof SondaIndisponivelError) {
      res.status(404).json({ ok: false, code: "not_found" });
      return;
    }
    if (e instanceof SondaConfigError) {
      res.status(503).json({ ok: false, code: "gateway_not_configured" });
      return;
    }
    res.status(502).json({ ok: false, code: "probe_failed" });
  }
}
