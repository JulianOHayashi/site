/**
 * R16 — ENTRYPOINT DO WORKER DE E-MAIL. SERVER-ONLY.
 *
 * Casca fina de propósito: liga ambiente, sinais e código de saída ao núcleo
 * em `workerRuntime.ts`. Nenhuma regra de despacho vive aqui, para que o
 * núcleo possa ser provado sem `process`.
 *
 * NÃO IMPORTAR ISTO DE CÓDIGO DE NAVEGADOR. O módulo cria um cliente com
 * `service_role` e lê senha SMTP do ambiente do processo.
 *
 * MODOS
 *   --once   (ou WORKER_ONE_SHOT=1)  um ciclo e sai. Uso previsto: cron.
 *   padrão                            polling até SIGINT/SIGTERM.
 *
 * SAÍDA
 *   0 concluído, ou parada cordial atendida
 *   2 configuração inválida (reiniciar não resolve)
 *   3 falha de infraestrutura durante a execução
 *
 * SEGREDO
 * Nada de valor de configuração em log. O logger recebe a senha SMTP e a
 * chave de service_role como termos a mascarar — segunda barreira, depois da
 * allowlist de campos.
 */

import { createClient } from "@supabase/supabase-js";
import { carregarWorkerConfig, WorkerConfigError } from "./workerConfig";
import { createSupabaseOutboxGateway } from "./supabaseOutboxGateway";
import { criarTransporteSmtp } from "./smtpEmailTransport";
import { criarWorkerLogger } from "./workerLogger";
import {
  SinalDeParada,
  dormirCancelavel,
  executarPolling,
  executarUmaVez,
  EXIT_CONFIG,
  type DependenciasRuntime,
} from "./workerRuntime";

/** `--once` na linha de comando ou `WORKER_ONE_SHOT` no ambiente. */
export function modoUmaVez(
  argv: readonly string[],
  env: Record<string, string | undefined>
): boolean {
  if (argv.includes("--once")) return true;
  const v = env.WORKER_ONE_SHOT?.trim().toLowerCase();
  return v === "1" || v === "true";
}

export async function main(
  argv: readonly string[] = process.argv.slice(2),
  env: Record<string, string | undefined> = process.env
): Promise<number> {
  // 1. CONFIGURAÇÃO — fail-closed antes de abrir qualquer conexão.
  let config;
  try {
    config = carregarWorkerConfig(env);
  } catch (e) {
    // Sem logger ainda: emite apenas o CÓDIGO, nunca o valor ofensor.
    const codigo = e instanceof WorkerConfigError ? e.code : "config_load_failed";
    console.error(JSON.stringify({ level: "error", event: "worker_config_invalid", error_code: codigo }));
    return EXIT_CONFIG;
  }

  const logger = criarWorkerLogger(undefined, [
    config.smtp.password,
    config.supabaseServiceKey,
  ]);

  logger.info({
    event: "worker_start",
    // Ambiente e modo são operacionais; host, porta e credencial não entram.
    outcome: `${config.environment}/${config.smtp.mode}`,
    count: config.batchSize,
  });

  // 2. DEPENDÊNCIAS.
  const client = createClient(config.supabaseUrl, config.supabaseServiceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const gateway = createSupabaseOutboxGateway(
    client,
    {
      onLinhaInvalida: (info) =>
        logger.warn({
          event: "worker_row_rejected",
          notification_id: info.id ?? undefined,
          outcome: info.motivo,
        }),
    },
    { recoveryReserve: config.recoveryReserve }
  );

  const transport = criarTransporteSmtp({
    config,
    aoDesfecho: (info) =>
      logger.info({
        event: "worker_smtp_outcome",
        provider: "smtp",
        outcome: `${info.outcome}/${info.retry}`,
        error_code: info.error_code,
      }),
  });

  const deps: DependenciasRuntime = {
    gateway,
    transport,
    logger,
    batchSize: config.batchSize,
    pollIntervalMs: config.pollIntervalMs,
    dormir: dormirCancelavel,
  };

  // 3. EXECUÇÃO.
  if (modoUmaVez(argv, env)) {
    const r = await executarUmaVez(deps);
    logger.info({ event: "worker_exit", outcome: r.parouPor, count: r.ciclos });
    return r.exitCode;
  }

  const parada = new SinalDeParada();
  // Parada cordial: o ciclo em andamento TERMINA. Abortar no meio deixaria
  // eventos com posse concedida e sem desfecho, órfãos até o lease expirar.
  const registrar = (sinal: NodeJS.Signals) => {
    process.on(sinal, () => parada.pedirParada(sinal));
  };
  registrar("SIGINT");
  registrar("SIGTERM");

  const r = await executarPolling(deps, parada);
  logger.info({ event: "worker_exit", outcome: r.parouPor, count: r.ciclos });
  return r.exitCode;
}

/**
 * Só executa quando este arquivo É o entrypoint. Sem a guarda, importar o
 * módulo em teste dispararia o worker de verdade.
 */
const ehEntrypoint = (() => {
  const alvo = process.argv[1] ?? "";
  return /(^|[\\/])main\.(ts|js|mjs)$/.test(alvo);
})();

if (ehEntrypoint) {
  main().then(
    (codigo) => process.exit(codigo),
    (e) => {
      // Exceção não prevista: código distinto de 2 e 3, sem detalhe cru.
      console.error(
        JSON.stringify({
          level: "error",
          event: "worker_unhandled",
          error_code: e instanceof Error ? e.name : "unknown",
        })
      );
      process.exit(1);
    }
  );
}
