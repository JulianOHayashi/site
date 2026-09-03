// @vitest-environment node
import { describe, it, expect, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  SinalDeParada,
  dormirCancelavel,
  executarUmCiclo,
  executarUmaVez,
  executarPolling,
  CicloFalhouError,
  EXIT_OK,
  EXIT_CONFIG,
  EXIT_RUNTIME,
  type DependenciasRuntime,
} from "../server/worker/workerRuntime";
import { modoUmaVez } from "../server/worker/main";
import { criarWorkerLogger } from "../server/worker/workerLogger";
import type {
  CanonicalOutboxGateway,
  PendingNotification,
} from "../server/notifications/dispatchOutbox";
import type { EmailTransport } from "../server/notifications/emailProvider";

/**
 * R16 — CP4: RUNTIME DO WORKER.
 *
 * O núcleo não toca `process`, então tudo aqui é determinístico: relógio,
 * espera e cancelamento são injetados. Nenhum temporizador real de intervalo
 * de polling é aguardado.
 */

const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");

const TOKEN = "t".repeat(64);

function eventoPendente(id: string, template = "manager_invite"): PendingNotification {
  return {
    id,
    channel: "email",
    template_key: template,
    template_data: { company_name: "X LTDA" },
    recipient_address: "socio@empresa.com.br",
    idempotency_key: `idem-${id}`,
  };
}

type EstadoGateway = {
  filas: PendingNotification[][];
  marcados: string[];
  falhados: string[];
  reagendados: string[];
  erroNaDescoberta?: Error;
};

function gatewayFalso(estado: EstadoGateway): CanonicalOutboxGateway {
  return {
    async listPending() {
      if (estado.erroNaDescoberta) throw estado.erroNaDescoberta;
      return estado.filas.shift() ?? [];
    },
    async mintApplicationToken() {
      return { ok: true, token: TOKEN, recipient: "x@y.com.br", purpose: "p", attempt: 1, expires_in_seconds: 900 };
    },
    async mintManagerInviteToken() {
      return { ok: true, token: TOKEN, recipient: "x@y.com.br", purpose: "p", attempt: 1, expires_in_seconds: 900 };
    },
    async markSent(id) {
      estado.marcados.push(id);
    },
    async markFailed(id) {
      estado.falhados.push(id);
    },
    async reschedule(id) {
      estado.reagendados.push(id);
    },
  };
}

function transporteFalso(
  comportamento: (m: { to: string; idempotencyKey: string }) => boolean = () => true
): EmailTransport & { enviados: string[] } {
  const enviados: string[] = [];
  return {
    name: "falso",
    enviados,
    async send(m) {
      if (comportamento(m)) {
        enviados.push(m.idempotencyKey);
        return { ok: true, provider: "falso", providerMessageId: `id-${m.idempotencyKey}` };
      }
      return { ok: false, provider: "falso", errorCode: "recusado", errorMessage: "recusa" };
    },
  };
}

function deps(
  estado: EstadoGateway,
  extra: Partial<DependenciasRuntime> = {}
): DependenciasRuntime & { linhas: string[] } {
  const linhas: string[] = [];
  const base: DependenciasRuntime = {
    gateway: gatewayFalso(estado),
    transport: transporteFalso(),
    logger: criarWorkerLogger((l) => linhas.push(l)),
    batchSize: 10,
    pollIntervalMs: 30_000,
    // Espera instantânea: nenhum teste paga o intervalo real.
    dormir: async () => {},
    agora: () => 0,
    ...extra,
  };
  return Object.assign(base, { linhas });
}

describe("R16_WORKER_ONE_SHOT — exatamente um ciclo", () => {
  it("executa um ciclo e sai com 0", async () => {
    const estado: EstadoGateway = { filas: [[eventoPendente("a")]], marcados: [], falhados: [], reagendados: [] };
    const d = deps(estado);
    const r = await executarUmaVez(d);
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.ciclos).toBe(1);
    expect(r.parouPor).toBe("one_shot");
    expect(r.totais.sent).toBe(1);
  });

  it("um ciclo é UM ciclo, mesmo com trabalho sobrando", async () => {
    // Duas filas disponíveis; one-shot só consome a primeira.
    const estado: EstadoGateway = {
      filas: [[eventoPendente("a")], [eventoPendente("b")]],
      marcados: [],
      falhados: [],
      reagendados: [],
    };
    const r = await executarUmaVez(deps(estado));
    expect(r.ciclos).toBe(1);
    expect(estado.marcados).toEqual(["a"]);
    expect(estado.filas).toHaveLength(1); // sobra intocada
  });

  it("fila vazia é sucesso, não erro", async () => {
    const estado: EstadoGateway = { filas: [[]], marcados: [], falhados: [], reagendados: [] };
    const r = await executarUmaVez(deps(estado));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.totais.processed).toBe(0);
  });

  it("falha de infraestrutura sai com EXIT_RUNTIME, não com 0", async () => {
    const estado: EstadoGateway = {
      filas: [],
      marcados: [],
      falhados: [],
      reagendados: [],
      erroNaDescoberta: new Error("outbox_discovery_failed:PGRST"),
    };
    const r = await executarUmaVez(deps(estado));
    expect(r.exitCode).toBe(EXIT_RUNTIME);
    expect(r.exitCode).not.toBe(EXIT_OK);
  });

  it("os códigos de saída são distintos e estáveis", () => {
    expect(new Set([EXIT_OK, EXIT_CONFIG, EXIT_RUNTIME]).size).toBe(3);
    expect(EXIT_OK).toBe(0);
    expect(EXIT_CONFIG).toBe(2);
    expect(EXIT_RUNTIME).toBe(3);
    // 1 é reservado para exceção não tratada do Node.
    expect([EXIT_OK, EXIT_CONFIG, EXIT_RUNTIME]).not.toContain(1);
  });
});

describe("R16_WORKER_POLLING — laço e parada cordial", () => {
  it("para entre ciclos quando a parada é pedida", async () => {
    const estado: EstadoGateway = {
      filas: [[eventoPendente("a")], [eventoPendente("b")], [eventoPendente("c")]],
      marcados: [],
      falhados: [],
      reagendados: [],
    };
    const parada = new SinalDeParada();
    const d = deps(estado, {
      // Pede parada durante a espera do primeiro intervalo.
      dormir: async () => parada.pedirParada("SIGTERM"),
    });

    const r = await executarPolling(d, parada);
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.ciclos).toBe(1);
    expect(r.parouPor).toBe("SIGTERM");
    expect(estado.marcados).toEqual(["a"]);
  });

  it("o ciclo em andamento TERMINA antes da saída", async () => {
    // Parada pedida no meio do ciclo: o evento já reivindicado precisa
    // receber desfecho, senão fica órfão em `sending` até o lease expirar.
    const estado: EstadoGateway = { filas: [[eventoPendente("a")]], marcados: [], falhados: [], reagendados: [] };
    const parada = new SinalDeParada();
    const transporte: EmailTransport = {
      name: "falso",
      async send(m) {
        parada.pedirParada("SIGINT"); // parada durante a transmissão
        return { ok: true, provider: "falso", providerMessageId: `id-${m.idempotencyKey}` };
      },
    };
    const r = await executarPolling(deps(estado, { transport: transporte }), parada);
    expect(r.ciclos).toBe(1);
    expect(estado.marcados).toEqual(["a"]); // desfecho registrado
    expect(r.parouPor).toBe("SIGINT");
  });

  it("parada durante o ciclo NÃO paga o intervalo de espera", async () => {
    const estado: EstadoGateway = { filas: [[eventoPendente("a")]], marcados: [], falhados: [], reagendados: [] };
    const parada = new SinalDeParada();
    const dormir = vi.fn(async () => {});
    const transporte: EmailTransport = {
      name: "falso",
      async send(m) {
        parada.pedirParada("SIGTERM");
        return { ok: true, provider: "falso", providerMessageId: `id-${m.idempotencyKey}` };
      },
    };
    await executarPolling(deps(estado, { transport: transporte, dormir }), parada);
    expect(dormir).not.toHaveBeenCalled();
  });

  it("parada pedida ANTES do início executa zero ciclos", async () => {
    const estado: EstadoGateway = { filas: [[eventoPendente("a")]], marcados: [], falhados: [], reagendados: [] };
    const parada = new SinalDeParada();
    parada.pedirParada("SIGTERM");
    const r = await executarPolling(deps(estado), parada);
    expect(r.ciclos).toBe(0);
    expect(estado.marcados).toEqual([]);
  });

  it("vários ciclos acumulam totais", async () => {
    const estado: EstadoGateway = {
      filas: [[eventoPendente("a")], [eventoPendente("b"), eventoPendente("c")]],
      marcados: [],
      falhados: [],
      reagendados: [],
    };
    const parada = new SinalDeParada();
    let n = 0;
    const d = deps(estado, {
      dormir: async () => {
        if (++n >= 2) parada.pedirParada("SIGTERM");
      },
    });
    const r = await executarPolling(d, parada);
    expect(r.ciclos).toBe(2);
    expect(r.totais.sent).toBe(3);
    expect(estado.marcados).toEqual(["a", "b", "c"]);
  });

  it("falha de infraestrutura interrompe o laço em vez de girar em vazio", async () => {
    const estado: EstadoGateway = {
      filas: [],
      marcados: [],
      falhados: [],
      reagendados: [],
      erroNaDescoberta: new Error("outbox_discovery_failed:PGRST"),
    };
    const parada = new SinalDeParada();
    const dormir = vi.fn(async () => {});
    const r = await executarPolling(deps(estado, { dormir }), parada);
    expect(r.exitCode).toBe(EXIT_RUNTIME);
    expect(r.ciclos).toBe(1);
    expect(dormir).not.toHaveBeenCalled();
  });
});

describe("R16_WORKER_SHUTDOWN — sinal de parada", () => {
  it("é monotônico: uma vez pedido, não volta", () => {
    const p = new SinalDeParada();
    expect(p.pedido).toBe(false);
    p.pedirParada("SIGTERM");
    expect(p.pedido).toBe(true);
    expect(p.motivo).toBe("SIGTERM");
  });

  it("é idempotente: o segundo sinal não substitui o motivo do primeiro", () => {
    const p = new SinalDeParada();
    p.pedirParada("SIGTERM");
    p.pedirParada("SIGINT");
    expect(p.motivo).toBe("SIGTERM");
  });

  it("ouvinte registrado depois do pedido dispara imediatamente", () => {
    const p = new SinalDeParada();
    p.pedirParada("SIGTERM");
    const f = vi.fn();
    p.aoPedir(f);
    expect(f).toHaveBeenCalledTimes(1);
  });

  it("a espera real é abortada pelo sinal, sem aguardar o intervalo", async () => {
    const p = new SinalDeParada();
    const t0 = Date.now();
    const espera = dormirCancelavel(30_000, p);
    p.pedirParada("SIGTERM");
    await espera;
    expect(Date.now() - t0).toBeLessThan(1_000);
  });

  it("a espera com parada já pedida resolve de imediato", async () => {
    const p = new SinalDeParada();
    p.pedirParada("SIGTERM");
    const t0 = Date.now();
    await dormirCancelavel(30_000, p);
    expect(Date.now() - t0).toBeLessThan(1_000);
  });

  it("o temporizador do intervalo NÃO é unref", () => {
    // unref esvaziava o laço de eventos e o processo terminava sozinho
    // depois do primeiro ciclo, com código 0 — falha disfarçada de sucesso.
    // Regressão coberta em processo por scripts/audit/worker-smoke.sh.
    const codigo = lerFonte("src/server/worker/workerRuntime.ts")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    expect(codigo).not.toMatch(/unref/);
  });

  it("sem parada, a espera respeita o prazo curto", async () => {
    const p = new SinalDeParada();
    const t0 = Date.now();
    await dormirCancelavel(60, p);
    expect(Date.now() - t0).toBeGreaterThanOrEqual(40);
  });
});

describe("R16_WORKER_MODE_SELECTION", () => {
  it("--once ativa one-shot", () => {
    expect(modoUmaVez(["--once"], {})).toBe(true);
  });
  it("WORKER_ONE_SHOT=1 e =true ativam one-shot", () => {
    expect(modoUmaVez([], { WORKER_ONE_SHOT: "1" })).toBe(true);
    expect(modoUmaVez([], { WORKER_ONE_SHOT: "TRUE" })).toBe(true);
  });
  it("ausente ou desligado mantém polling", () => {
    expect(modoUmaVez([], {})).toBe(false);
    expect(modoUmaVez([], { WORKER_ONE_SHOT: "0" })).toBe(false);
    expect(modoUmaVez([], { WORKER_ONE_SHOT: "" })).toBe(false);
    expect(modoUmaVez(["--polling"], {})).toBe(false);
  });
});

describe("R16_WORKER_LOG_REDACTION — ciclo não vaza segredo", () => {
  it("nenhum log do ciclo carrega o token cunhado", async () => {
    const estado: EstadoGateway = {
      filas: [[eventoPendente("a"), eventoPendente("b", "partner_application_account_claim")]],
      marcados: [],
      falhados: [],
      reagendados: [],
    };
    const d = deps(estado);
    await executarUmCiclo(d);
    const tudo = d.linhas.join("\n");
    expect(tudo).not.toContain(TOKEN);
    expect(tudo).not.toContain("socio@empresa.com.br");
    expect(tudo).not.toContain("X LTDA");
  });

  it("a exceção do ciclo entra como código, sem mensagem crua", async () => {
    const estado: EstadoGateway = {
      filas: [],
      marcados: [],
      falhados: [],
      reagendados: [],
      erroNaDescoberta: new Error(`falha com token=${TOKEN} e senha=abcdefgh12345678`),
    };
    const d = deps(estado);
    await expect(executarUmCiclo(d)).rejects.toBeInstanceOf(CicloFalhouError);
    const tudo = d.linhas.join("\n");
    expect(tudo).not.toContain(TOKEN);
    expect(tudo).not.toContain("abcdefgh12345678");
    expect(tudo).toContain("worker_cycle_failed");
  });

  it("template não suportado é contabilizado sem transmissão", async () => {
    const estado: EstadoGateway = {
      filas: [[eventoPendente("a", "template_fora_do_escopo")]],
      marcados: [],
      falhados: [],
      reagendados: [],
    };
    const transporte = transporteFalso();
    const r = await executarUmCiclo(deps(estado, { transport: transporte }));
    expect(r.unsupported).toBe(1);
    expect(transporte.enviados).toEqual([]);
    expect(estado.marcados).toEqual([]);
    expect(estado.falhados).toEqual([]);
    expect(estado.reagendados).toEqual([]);
  });
});

describe("R16_WORKER_ENTRYPOINT — casca fina e server-only", () => {
  const fonteMain = lerFonte("src/server/worker/main.ts");
  const fonteRuntime = lerFonte("src/server/worker/workerRuntime.ts");

  it("o núcleo não toca process em nenhuma forma", () => {
    const codigo = fonteRuntime
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    expect(codigo).not.toMatch(/process\s*\./);
    expect(codigo).not.toMatch(/process\.env/);
    expect(codigo).not.toMatch(/process\.exit/);
    expect(codigo).not.toMatch(/process\.on/);
  });

  it("o entrypoint registra SIGINT e SIGTERM", () => {
    expect(fonteMain).toContain('registrar("SIGINT")');
    expect(fonteMain).toContain('registrar("SIGTERM")');
    expect(fonteMain).toMatch(/process\.on\(sinal/);
  });

  it("o entrypoint tem guarda para não executar quando importado", () => {
    expect(fonteMain).toMatch(/ehEntrypoint/);
    expect(fonteMain).toMatch(/if \(ehEntrypoint\)/);
  });

  it("configuração inválida sai com EXIT_CONFIG e sem detalhe do valor", () => {
    expect(fonteMain).toContain("return EXIT_CONFIG");
    expect(fonteMain).toContain("worker_config_invalid");
    // Só o código do erro é emitido, nunca a mensagem ou o valor.
    expect(fonteMain).not.toMatch(/error_message:/);
  });

  it("o logger recebe senha e service_role como termos a mascarar", () => {
    expect(fonteMain).toMatch(/criarWorkerLogger\(undefined,\s*\[\s*config\.smtp\.password,\s*config\.supabaseServiceKey,?\s*\]\)/);
  });

  it("o cliente Supabase não persiste sessão no processo do worker", () => {
    expect(fonteMain).toMatch(/persistSession:\s*false/);
    expect(fonteMain).toMatch(/autoRefreshToken:\s*false/);
  });

  it("nenhum arquivo do worker é importado por página ou componente", () => {
    const varrer = (dir: string): string[] => {
      const fs = require("node:fs") as typeof import("node:fs");
      const path = require("node:path") as typeof import("node:path");
      const saida: string[] = [];
      for (const e of fs.readdirSync(dir)) {
        const p = path.join(dir, e);
        if (fs.statSync(p).isDirectory()) saida.push(...varrer(p));
        else if (/\.(ts|tsx)$/.test(e)) saida.push(p);
      }
      return saida;
    };
    const clientes = [
      ...varrer(resolve(process.cwd(), "src/pages")),
      ...varrer(resolve(process.cwd(), "src/components")),
      ...varrer(resolve(process.cwd(), "src/hooks")),
    ];
    expect(clientes.length).toBeGreaterThan(5);
    for (const arquivo of clientes) {
      const conteudo = readFileSync(arquivo, "utf8");
      expect(conteudo, arquivo).not.toMatch(/from\s+["'][^"']*server\/worker/);
      expect(conteudo, arquivo).not.toMatch(/from\s+["']node:(net|tls)["']/);
    }
  });
});
