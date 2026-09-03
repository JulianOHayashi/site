/**
 * R16 — NÚCLEO DO RUNTIME DO WORKER.
 *
 * Deliberadamente SEM acesso a `process`: nem env, nem sinais, nem
 * `process.exit`. Tudo que o processo real fornece — relógio, espera,
 * cancelamento — entra por injeção. Isso é o que permite provar parada
 * cordial, comportamento de saída e ausência de laço infinito em teste
 * determinístico, sem depender de temporizador de verdade.
 *
 * O entrypoint (`main.ts`) é a casca fina que liga sinais e ambiente a este
 * núcleo. A regra é: toda decisão fica aqui, todo efeito de processo fica lá.
 */

import { dispatchPending, type CanonicalOutboxGateway } from "../notifications/dispatchOutbox";
import type { EmailTransport } from "../notifications/emailProvider";
import type { WorkerLogger } from "./workerLogger";

/**
 * Códigos de saída. Estáveis e documentados: um orquestrador decide reinício
 * a partir deles, então mudá-los é mudança de contrato operacional.
 *
 *   0  ciclo(s) concluído(s), ou parada cordial atendida
 *   2  configuração inválida — reiniciar NÃO resolve, exige intervenção
 *   3  falha de infraestrutura durante a execução (descoberta, RPC) —
 *      reiniciar pode resolver
 *
 * 1 é evitado de propósito: é o código que o Node usa para exceção não
 * tratada, e distingui-lo de falha declarada nossa tem valor operacional.
 */
export const EXIT_OK = 0;
export const EXIT_CONFIG = 2;
export const EXIT_RUNTIME = 3;

export type ResumoCiclo = {
  processed: number;
  sent: number;
  failed: number;
  skipped: number;
  unsupported: number;
};

export type DependenciasRuntime = {
  gateway: CanonicalOutboxGateway;
  transport: EmailTransport;
  logger: WorkerLogger;
  batchSize: number;
  pollIntervalMs: number;
  /** Espera cancelável. Recebe o sinal para abortar a espera na parada. */
  dormir: (ms: number, parada: SinalDeParada) => Promise<void>;
  /** Relógio injetável, para medir duração sem depender de Date.now real. */
  agora?: () => number;
};

/**
 * Sinal de parada de leitura única e monotônico: uma vez pedido, nunca
 * volta. Um booleano solto poderia ser reabilitado por engano; isto não.
 */
export class SinalDeParada {
  #pedido = false;
  #motivo: string | null = null;
  readonly #ouvintes: Array<() => void> = [];

  get pedido(): boolean {
    return this.#pedido;
  }
  get motivo(): string | null {
    return this.#motivo;
  }

  /** Idempotente: o segundo sinal não substitui o motivo do primeiro. */
  pedirParada(motivo: string): void {
    if (this.#pedido) return;
    this.#pedido = true;
    this.#motivo = motivo;
    for (const f of this.#ouvintes) f();
  }

  aoPedir(f: () => void): void {
    if (this.#pedido) {
      f();
      return;
    }
    this.#ouvintes.push(f);
  }
}

/**
 * Espera real, abortada de imediato quando a parada é pedida.
 *
 * O TEMPORIZADOR NÃO É `unref`.
 *
 * Uma versão anterior chamava `unref()` na intenção de não segurar o processo
 * vivo. O efeito real foi outro: sem nenhum handle ativo, o laço de eventos
 * do Node esvaziava durante a espera e o processo TERMINAVA sozinho depois do
 * primeiro ciclo — com código 0, o que fazia a falha parecer sucesso. O
 * polling nunca chegava ao segundo ciclo.
 *
 * Em polling, segurar o processo vivo durante o intervalo é o comportamento
 * correto, não um efeito colateral. O modo one-shot não chama esta função, e
 * a parada cordial já limpa o temporizador — não há nada a proteger com
 * `unref`.
 *
 * Este defeito não é detectável por teste unitário: sob Vitest o processo
 * segue vivo por outros motivos. Ele é coberto por
 * `scripts/audit/worker-smoke.sh`, que exige o evento de shutdown no
 * artefato real.
 */
export function dormirCancelavel(ms: number, parada: SinalDeParada): Promise<void> {
  if (parada.pedido) return Promise.resolve();
  return new Promise<void>((resolver) => {
    const t = setTimeout(() => resolver(), ms);
    parada.aoPedir(() => {
      clearTimeout(t);
      resolver();
    });
  });
}

/**
 * Erro de infraestrutura do ciclo. Distinto de recusa do provedor: recusa é
 * desfecho normal e o despachante já a contabiliza; isto é falha ao falar com
 * o banco, e não pode ser confundida com "nada a fazer".
 */
export class CicloFalhouError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.name = "CicloFalhouError";
    this.code = code;
  }
}

/**
 * Executa UM ciclo de despacho.
 *
 * Não engole exceção: a decisão sobre reiniciar ou abortar pertence a quem
 * chama. O resumo é emitido em log com campos da allowlist.
 */
export async function executarUmCiclo(deps: DependenciasRuntime): Promise<ResumoCiclo> {
  const relogio = deps.agora ?? (() => Date.now());
  const t0 = relogio();
  deps.logger.info({ event: "worker_cycle_start", count: deps.batchSize });

  try {
    const resumo = await dispatchPending(deps.gateway, deps.transport, {
      channel: "email",
      max: deps.batchSize,
      onDiagnostic: (d) => {
        // `reason` é código canônico da RPC ou do escopo; nunca dado do
        // template e nunca o segredo cunhado.
        deps.logger.info({
          event: "worker_event_skipped",
          notification_id: d.notificationId,
          template_key: d.templateKey,
          outcome: d.reason,
        });
      },
    });

    deps.logger.info({
      event: "worker_cycle_end",
      count: resumo.processed,
      outcome: `sent=${resumo.sent} failed=${resumo.failed} skipped=${resumo.skipped} unsupported=${resumo.unsupported}`,
      duration_ms: relogio() - t0,
    });
    return resumo;
  } catch (e) {
    deps.logger.error({
      event: "worker_cycle_failed",
      duration_ms: relogio() - t0,
      ...deps.logger.erroSeguro(e),
    });
    throw new CicloFalhouError(
      e instanceof Error && "code" in e && typeof e.code === "string"
        ? e.code
        : "cycle_failed"
    );
  }
}

export type ResultadoExecucao = {
  exitCode: number;
  ciclos: number;
  totais: ResumoCiclo;
  /** Motivo da parada: "one_shot", o sinal recebido, ou o código da falha. */
  parouPor: string;
};

const zerado = (): ResumoCiclo => ({
  processed: 0,
  sent: 0,
  failed: 0,
  skipped: 0,
  unsupported: 0,
});

const somar = (a: ResumoCiclo, b: ResumoCiclo): ResumoCiclo => ({
  processed: a.processed + b.processed,
  sent: a.sent + b.sent,
  failed: a.failed + b.failed,
  skipped: a.skipped + b.skipped,
  unsupported: a.unsupported + b.unsupported,
});

/**
 * MODO ONE-SHOT: exatamente um ciclo, sempre.
 *
 * Um ciclo, não "um ciclo e mais um se sobrou trabalho": é isso que torna a
 * execução por cron previsível e o teste determinístico. Falha de
 * infraestrutura sai com EXIT_RUNTIME.
 */
export async function executarUmaVez(deps: DependenciasRuntime): Promise<ResultadoExecucao> {
  try {
    const resumo = await executarUmCiclo(deps);
    return { exitCode: EXIT_OK, ciclos: 1, totais: resumo, parouPor: "one_shot" };
  } catch (e) {
    return {
      exitCode: EXIT_RUNTIME,
      ciclos: 1,
      totais: zerado(),
      parouPor: e instanceof CicloFalhouError ? e.code : "cycle_failed",
    };
  }
}

/**
 * MODO POLLING: ciclos até a parada ser pedida.
 *
 * PARADA CORDIAL, NÃO ABORTO
 * O sinal é conferido entre ciclos e a espera é cancelável, mas um ciclo já
 * iniciado TERMINA. Abortar no meio deixaria eventos em `sending` com posse
 * concedida e sem desfecho registrado — órfãos até o lease expirar. Esperar
 * o ciclo é mais lento e mais correto.
 *
 * FALHA NÃO É MOTIVO PARA GIRAR EM VAZIO
 * Um ciclo que falha por infraestrutura interrompe o laço com EXIT_RUNTIME em
 * vez de repetir a cada intervalo. Insistir esconderia a falha em log
 * repetido, e o orquestrador é quem deve decidir reinício com backoff.
 */
export async function executarPolling(
  deps: DependenciasRuntime,
  parada: SinalDeParada
): Promise<ResultadoExecucao> {
  let ciclos = 0;
  let totais = zerado();

  while (!parada.pedido) {
    ciclos++;
    try {
      totais = somar(totais, await executarUmCiclo(deps));
    } catch (e) {
      return {
        exitCode: EXIT_RUNTIME,
        ciclos,
        totais,
        parouPor: e instanceof CicloFalhouError ? e.code : "cycle_failed",
      };
    }

    // Confere ANTES de esperar: parada durante o ciclo não paga o intervalo.
    if (parada.pedido) break;
    await deps.dormir(deps.pollIntervalMs, parada);
  }

  const parouPor = parada.pedido ? (parada.motivo ?? "stop_requested") : "loop_ended";
  deps.logger.info({ event: "worker_shutdown", outcome: parouPor, count: ciclos });
  return { exitCode: EXIT_OK, ciclos, totais, parouPor };
}
