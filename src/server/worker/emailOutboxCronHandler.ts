/**
 * R16 — ADAPTADOR ONE-SHOT DO WORKER DE E-MAIL PARA FUNÇÃO SERVERLESS.
 * SERVER-ONLY.
 *
 * Casca fina sobre o núcleo existente. Não há regra de despacho aqui:
 *
 *   autenticar → carregar config → montar deps (mesma fábrica do CLI)
 *              → executarUmaVez (UM ciclo) → resumo sanitizado
 *
 * O laço de polling NUNCA é iniciado por este módulo. Posse, lease, retry e
 * idempotência continuam sendo das RPCs canônicas, via `dispatchPending`;
 * por isso duas invocações concorrentes (cron entregue duas vezes) são
 * seguras: a segunda recebe `lease_held` e não transmite.
 *
 * RESPOSTA
 * Só contadores operacionais ou um código genérico. Nunca destinatário,
 * template_data, token, URL do banco, credencial, mensagem crua ou stack.
 * O detalhe diagnóstico vai para o log, e o log passa pela allowlist e pela
 * máscara do `workerLogger`.
 *
 * NÃO IMPORTAR ISTO DE CÓDIGO DE NAVEGADOR.
 */

import { autenticarInvocacaoCron } from "./cronAuth.js";
import {
  carregarWorkerConfig,
  WorkerConfigError,
  type FonteEnv,
  type WorkerConfig,
} from "./workerConfig.js";
import { criarWorkerLogger, type Sink, type WorkerLogger } from "./workerLogger.js";
import { construirDependenciasWorker } from "./workerDependencies.js";
import {
  executarUmaVez,
  EXIT_OK,
  type DependenciasRuntime,
  type ResultadoExecucao,
} from "./workerRuntime.js";

export type RespostaCron = {
  status: number;
  headers: Record<string, string>;
  body:
    | {
        ok: true;
        processed: number;
        sent: number;
        failed: number;
        skipped: number;
        unsupported: number;
      }
    | { ok: false; code: string };
};

export type RequisicaoCron = {
  method?: string;
  headers?: Record<string, string | string[] | undefined>;
};

/** Pontos de injeção. Em produção todos têm o valor real por padrão. */
export type FabricasCron = {
  carregarConfig: (env: FonteEnv) => WorkerConfig;
  construirDependencias: (config: WorkerConfig, logger: WorkerLogger) => DependenciasRuntime;
  executar: (deps: DependenciasRuntime) => Promise<ResultadoExecucao>;
  sink?: Sink;
};

const FABRICAS_REAIS: FabricasCron = {
  carregarConfig: carregarWorkerConfig,
  construirDependencias: construirDependenciasWorker,
  executar: executarUmaVez,
};

const SEM_CACHE = { "Cache-Control": "no-store" } as const;

function falha(status: number, code: string, extra: Record<string, string> = {}): RespostaCron {
  return { status, headers: { ...SEM_CACHE, ...extra }, body: { ok: false, code } };
}

export async function executarCicloEmailAgendado(
  req: RequisicaoCron,
  env: FonteEnv,
  fabricas: FabricasCron = FABRICAS_REAIS
): Promise<RespostaCron> {
  // Logger provisório: antes da config, mascara só o segredo do cron.
  let logger = criarWorkerLogger(fabricas.sink, [env.CRON_SECRET]);

  // 1. MÉTODO. O Vercel Cron invoca com GET; nada mais é aceito.
  if (req.method !== "GET") {
    return falha(405, "method_not_allowed", { Allow: "GET" });
  }

  // 2. AUTENTICAÇÃO — antes de ler qualquer outra configuração.
  const auth = autenticarInvocacaoCron(req.headers, env);
  if (!auth.autorizado) {
    // O motivo fica no log; a resposta é a mesma para todo caso.
    logger.warn({ event: "worker_cron_unauthorized", outcome: auth.motivo });
    return falha(401, "unauthorized");
  }

  try {
    // 3. CONFIGURAÇÃO — mesmo carregador fail-closed do CLI.
    let config: WorkerConfig;
    try {
      config = fabricas.carregarConfig(env);
    } catch (e) {
      logger.error({
        event: "worker_config_invalid",
        error_code: e instanceof WorkerConfigError ? e.code : "config_load_failed",
      });
      return falha(503, "worker_unavailable");
    }

    logger = criarWorkerLogger(fabricas.sink, [
      env.CRON_SECRET,
      config.smtp.password,
      config.supabaseServiceKey,
    ]);
    logger.info({
      event: "worker_start",
      outcome: `${config.environment}/${config.smtp.mode}/cron_one_shot`,
      count: config.batchSize,
    });

    // 4. EXATAMENTE UM CICLO.
    const deps = fabricas.construirDependencias(config, logger);
    const r = await fabricas.executar(deps);
    logger.info({ event: "worker_exit", outcome: r.parouPor, count: r.ciclos });

    if (r.exitCode !== EXIT_OK) {
      return falha(502, "worker_cycle_failed");
    }

    const t = r.totais;
    return {
      status: 200,
      headers: { ...SEM_CACHE },
      // Contadores copiados campo a campo: nenhuma propriedade extra que um
      // dia apareça no resumo do runtime vaza para a resposta por espalhamento.
      body: {
        ok: true,
        processed: t.processed,
        sent: t.sent,
        failed: t.failed,
        skipped: t.skipped,
        unsupported: t.unsupported,
      },
    };
  } catch (e) {
    logger.error({ event: "worker_cron_unhandled", ...logger.erroSeguro(e) });
    return falha(500, "unexpected_error");
  }
}
