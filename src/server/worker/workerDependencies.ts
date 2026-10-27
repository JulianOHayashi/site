/**
 * R16 — CONSTRUÇÃO DAS DEPENDÊNCIAS DO WORKER. SERVER-ONLY.
 *
 * Extraído de `main.ts` sem alteração de comportamento, para que o
 * entrypoint de CLI e o adaptador one-shot da Vercel
 * (`emailOutboxCronHandler.ts`) montem EXATAMENTE o mesmo gateway canônico e
 * o mesmo transporte SMTP. Duas montagens divergentes seriam duas semânticas
 * de despacho; uma montagem só é uma.
 *
 * NÃO IMPORTAR ISTO DE CÓDIGO DE NAVEGADOR. Cria um cliente com
 * `service_role` e entrega a senha SMTP ao transporte.
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { WorkerConfig } from "./workerConfig.js";
import { createSupabaseOutboxGateway } from "./supabaseOutboxGateway.js";
import { criarTransporteSmtp } from "./smtpEmailTransport.js";
import type { WorkerLogger } from "./workerLogger.js";
import { dormirCancelavel, type DependenciasRuntime } from "./workerRuntime.js";

export type FabricaClienteSupabase = (url: string, serviceKey: string) => SupabaseClient;

const clienteServiceRole: FabricaClienteSupabase = (url, serviceKey) =>
  createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

export function construirDependenciasWorker(
  config: WorkerConfig,
  logger: WorkerLogger,
  criarCliente: FabricaClienteSupabase = clienteServiceRole
): DependenciasRuntime {
  const client = criarCliente(config.supabaseUrl, config.supabaseServiceKey);

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

  return {
    gateway,
    transport,
    logger,
    batchSize: config.batchSize,
    pollIntervalMs: config.pollIntervalMs,
    dormir: dormirCancelavel,
  };
}
