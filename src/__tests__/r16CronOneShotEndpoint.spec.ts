// @vitest-environment node
import { describe, it, expect, vi, afterEach } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, normalize, resolve } from "node:path";
import {
  autenticarInvocacaoCron,
  CRON_SECRET_MIN_LENGTH,
} from "../server/worker/cronAuth";
import {
  executarCicloEmailAgendado,
  type FabricasCron,
  type RequisicaoCron,
} from "../server/worker/emailOutboxCronHandler";
import { executarUmaVez, type DependenciasRuntime } from "../server/worker/workerRuntime";
import {
  rejeitarSegredosPublicos,
  WorkerConfigError,
  type WorkerConfig,
} from "../server/worker/workerConfig";
import { R16_SUPPORTED_TEMPLATE_KEYS } from "../server/notifications/supportedTemplates";
import type {
  CanonicalOutboxGateway,
  MintOutcome,
  PendingNotification,
} from "../server/notifications/dispatchOutbox";
import type { EmailMessage, EmailTransport } from "../server/notifications/emailProvider";
import apiHandler from "../../api/internal/email-outbox-dispatch";

/**
 * R16 — ADAPTADOR ONE-SHOT (Vercel Function) DO WORKER DE E-MAIL.
 *
 * Nenhum teste aqui abre socket, fala com Supabase ou envia e-mail: o
 * gateway e o transporte são falsos, mas o CAMINHO é o canônico real
 * (`executarUmaVez` → `dispatchPending`), para provar que o adaptador não
 * contorna a posse atômica.
 */

const RAIZ = resolve(__dirname, "../..");
const lerFonte = (rel: string) => readFileSync(resolve(RAIZ, rel), "utf8");

const CRON_SECRET = "cron-SEGREDO-de-teste-0123456789abcdef";
const SMTP_PASSWORD = "smtp-SENHA-de-teste-0123456789";
const SERVICE_KEY = "service-ROLE-de-teste-0123456789abcdef";
const TOKEN_CUNHADO = "TOKEN-CUNHADO-".padEnd(64, "x");
const DESTINATARIO = "socio.privado@empresa-exemplo.com.br";
const NOME_PRIVADO = "Maria Pessoa Privada";
const CNPJ_PRIVADO = "12.345.678/0001-95";

const ENV_OK = { CRON_SECRET } as const;
const AUTH_OK = { authorization: `Bearer ${CRON_SECRET}` };

const SEGREDOS = [CRON_SECRET, SMTP_PASSWORD, SERVICE_KEY, TOKEN_CUNHADO];
const PII = [DESTINATARIO, NOME_PRIVADO, CNPJ_PRIVADO];

function configFalsa(): WorkerConfig {
  return {
    environment: "staging",
    supabaseUrl: "https://projeto-falso.supabase.co",
    supabaseServiceKey: SERVICE_KEY,
    siteBaseUrl: "https://site.exemplo",
    smtp: {
      host: "smtp.exemplo",
      port: 465,
      mode: "implicit_tls",
      username: "usuario-smtp",
      password: SMTP_PASSWORD,
      fromAddress: "no-reply@exemplo.com.br",
      connectTimeoutMs: 1000,
      readTimeoutMs: 1000,
    },
    batchSize: 10,
    recoveryReserve: 2,
    pollIntervalMs: 60_000,
    stagingRecipient: { kind: "override", address: "teste@exemplo.com.br" },
  };
}

function evento(id: string, template: string): PendingNotification {
  return {
    id,
    channel: "email",
    template_key: template,
    template_data: { representative_name: NOME_PRIVADO, cnpj: CNPJ_PRIVADO },
    recipient_address: DESTINATARIO,
    idempotency_key: `idem-${id}`,
  };
}

type Registro = {
  chamadas: string[];
  listPending: number;
  enviados: EmailMessage[];
  dormiu: number;
};

function montarDeps(
  reg: Registro,
  fila: PendingNotification[],
  opcoes: {
    mint?: () => MintOutcome;
    erroNaDescoberta?: Error;
  } = {}
) {
  const mint =
    opcoes.mint ??
    ((): MintOutcome => ({
      ok: true,
      token: TOKEN_CUNHADO,
      recipient: DESTINATARIO,
      purpose: "p",
      attempt: 1,
      expires_in_seconds: 900,
    }));

  const gateway: CanonicalOutboxGateway = {
    async listPending() {
      reg.listPending++;
      reg.chamadas.push("listPending");
      if (opcoes.erroNaDescoberta) throw opcoes.erroNaDescoberta;
      return reg.listPending === 1 ? fila : [];
    },
    async mintApplicationToken(id) {
      reg.chamadas.push(`mint:${id}`);
      return mint();
    },
    async mintManagerInviteToken(id) {
      reg.chamadas.push(`mint:${id}`);
      return mint();
    },
    async markSent(id) {
      reg.chamadas.push(`sent:${id}`);
    },
    async markFailed(id) {
      reg.chamadas.push(`failed:${id}`);
    },
    async reschedule(id) {
      reg.chamadas.push(`reschedule:${id}`);
    },
  };

  const transport: EmailTransport = {
    async send(m) {
      reg.chamadas.push(`send:${m.idempotencyKey}`);
      reg.enviados.push(m);
      return { ok: true, provider: "smtp", providerMessageId: `msg-${DESTINATARIO}` };
    },
  } as EmailTransport;

  return (_config: WorkerConfig, logger: DependenciasRuntime["logger"]): DependenciasRuntime => ({
    gateway,
    transport,
    logger,
    batchSize: 10,
    pollIntervalMs: 60_000,
    dormir: async () => {
      reg.dormiu++;
    },
  });
}

function novoRegistro(): Registro {
  return { chamadas: [], listPending: 0, enviados: [], dormiu: 0 };
}

function fabricas(
  reg: Registro,
  fila: PendingNotification[] = [],
  extra: Partial<FabricasCron> & { mint?: () => MintOutcome; erroNaDescoberta?: Error } = {},
  logs: string[] = []
) {
  const carregarConfig = vi.fn(extra.carregarConfig ?? (() => configFalsa()));
  const executar = vi.fn(extra.executar ?? executarUmaVez);
  const construirDependencias = vi.fn(
    extra.construirDependencias ??
      montarDeps(reg, fila, { mint: extra.mint, erroNaDescoberta: extra.erroNaDescoberta })
  );
  const f: FabricasCron = {
    carregarConfig,
    construirDependencias,
    executar,
    sink: (l) => logs.push(l),
  };
  return { f, carregarConfig, construirDependencias, executar, logs };
}

const req = (headers: RequisicaoCron["headers"], method = "GET"): RequisicaoCron => ({
  method,
  headers,
});

function semVazamento(texto: string, termos: readonly string[]) {
  for (const t of termos) expect(texto.includes(t), `vazou: ${t.slice(0, 6)}…`).toBe(false);
}

// ---------------------------------------------------------------------------
describe("autenticação da invocação agendada (CRON_SECRET)", () => {
  it("sem CRON_SECRET no servidor, nunca autoriza — nem com cabeçalho 'certo'", () => {
    expect(autenticarInvocacaoCron(AUTH_OK, {})).toEqual({
      autorizado: false,
      motivo: "secret_not_configured",
    });
    expect(autenticarInvocacaoCron({ authorization: "Bearer " }, { CRON_SECRET: "" }).autorizado).toBe(false);
    expect(autenticarInvocacaoCron({ authorization: "Bearer undefined" }, {}).autorizado).toBe(false);
  });

  it("segredo curto demais ou com espaço é tratado como não configurado", () => {
    const curto = "a".repeat(CRON_SECRET_MIN_LENGTH - 1);
    expect(autenticarInvocacaoCron({ authorization: `Bearer ${curto}` }, { CRON_SECRET: curto }).motivo).toBe(
      "secret_not_configured"
    );
    const comEspaco = `${CRON_SECRET} `;
    expect(
      autenticarInvocacaoCron({ authorization: `Bearer ${CRON_SECRET}` }, { CRON_SECRET: comEspaco }).motivo
    ).toBe("secret_not_configured");
  });

  it("sem cabeçalho Authorization é recusado", () => {
    expect(autenticarInvocacaoCron({}, ENV_OK)).toEqual({ autorizado: false, motivo: "header_missing" });
    expect(autenticarInvocacaoCron(undefined, ENV_OK).autorizado).toBe(false);
  });

  it.each([
    ["sem esquema", CRON_SECRET],
    ["esquema Basic", `Basic ${CRON_SECRET}`],
    ["esquema minúsculo", `bearer ${CRON_SECRET}`],
    ["Bearer vazio", "Bearer "],
    ["Bearer sozinho", "Bearer"],
    ["espaço duplo", `Bearer  ${CRON_SECRET}`],
    ["sufixo extra", `Bearer ${CRON_SECRET} extra`],
    ["espaço final", `Bearer ${CRON_SECRET} `],
  ])("cabeçalho malformado (%s) é recusado", (_n, valor) => {
    const r = autenticarInvocacaoCron({ authorization: valor }, ENV_OK);
    expect(r.autorizado).toBe(false);
  });

  it("cabeçalho repetido é recusado em vez de escolher um", () => {
    const r = autenticarInvocacaoCron(
      { authorization: [`Bearer ${CRON_SECRET}`, `Bearer ${CRON_SECRET}`] },
      ENV_OK
    );
    expect(r).toEqual({ autorizado: false, motivo: "header_malformed" });
  });

  it("segredo Bearer incorreto é recusado (inclusive prefixo do correto)", () => {
    expect(autenticarInvocacaoCron({ authorization: "Bearer outro-segredo-qualquer-123" }, ENV_OK)).toEqual({
      autorizado: false,
      motivo: "secret_mismatch",
    });
    expect(
      autenticarInvocacaoCron({ authorization: `Bearer ${CRON_SECRET.slice(0, -1)}` }, ENV_OK).autorizado
    ).toBe(false);
    expect(
      autenticarInvocacaoCron({ authorization: `Bearer ${CRON_SECRET}x` }, ENV_OK).autorizado
    ).toBe(false);
  });

  it("segredo correto é aceito", () => {
    expect(autenticarInvocacaoCron(AUTH_OK, ENV_OK)).toEqual({ autorizado: true, motivo: "ok" });
    // Node entrega cabeçalho em minúsculas; a forma capitalizada também é lida.
    expect(autenticarInvocacaoCron({ Authorization: `Bearer ${CRON_SECRET}` }, ENV_OK).autorizado).toBe(true);
  });

  it("comparação em tempo constante sobre digest, sem atalho de igualdade de string", () => {
    const fonte = lerFonte("src/server/worker/cronAuth.ts");
    expect(fonte).toContain("timingSafeEqual");
    expect(fonte).not.toMatch(/===\s*segredo|segredo\s*===|!==\s*segredo/);
  });
});

// ---------------------------------------------------------------------------
describe("handler one-shot — portão de autorização", () => {
  it("método diferente de GET é recusado sem tocar em config nem worker", async () => {
    for (const m of ["POST", "PUT", "DELETE", "PATCH", undefined]) {
      const { f, carregarConfig, executar } = fabricas(novoRegistro());
      const r = await executarCicloEmailAgendado({ method: m, headers: AUTH_OK }, ENV_OK, f);
      expect(r.status).toBe(405);
      expect(r.headers.Allow).toBe("GET");
      expect(carregarConfig).not.toHaveBeenCalled();
      expect(executar).not.toHaveBeenCalled();
    }
  });

  it.each([
    ["CRON_SECRET ausente", {}, AUTH_OK],
    ["sem Authorization", ENV_OK, {}],
    ["Authorization malformado", ENV_OK, { authorization: `Token ${CRON_SECRET}` }],
    ["Bearer incorreto", ENV_OK, { authorization: "Bearer segredo-errado-0123456789" }],
  ] as const)("%s → 401 genérico, sem carregar config nem executar ciclo", async (_n, env, headers) => {
    const reg = novoRegistro();
    const { f, carregarConfig, construirDependencias, executar } = fabricas(reg, [
      evento("n1", "manager_invite"),
    ]);
    const r = await executarCicloEmailAgendado(req(headers), env, f);
    expect(r.status).toBe(401);
    // Mesma resposta para todos os motivos: não revela se o segredo existe.
    expect(r.body).toEqual({ ok: false, code: "unauthorized" });
    expect(carregarConfig).not.toHaveBeenCalled();
    expect(construirDependencias).not.toHaveBeenCalled();
    expect(executar).not.toHaveBeenCalled();
    expect(reg.listPending).toBe(0);
    expect(reg.enviados).toHaveLength(0);
  });

  it("o motivo da recusa vai só para o log, sem o segredo", async () => {
    const logs: string[] = [];
    const { f } = fabricas(novoRegistro(), [], {}, logs);
    await executarCicloEmailAgendado(req({ authorization: `Bearer ${CRON_SECRET}-errado` }), ENV_OK, f);
    const tudo = logs.join("\n");
    expect(tudo).toContain("worker_cron_unauthorized");
    expect(tudo).toContain("secret_mismatch");
    semVazamento(tudo, [CRON_SECRET]);
  });
});

// ---------------------------------------------------------------------------
describe("handler one-shot — exatamente um ciclo, pelo caminho canônico", () => {
  it("chamada autorizada executa UM ciclo e nunca entra em polling", async () => {
    const reg = novoRegistro();
    const { f, executar, construirDependencias } = fabricas(reg, [evento("n1", "manager_invite")]);
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);

    expect(r.status).toBe(200);
    expect(executar).toHaveBeenCalledTimes(1);
    expect(construirDependencias).toHaveBeenCalledTimes(1);
    // Uma descoberta só: não houve "segundo ciclo porque sobrou trabalho".
    expect(reg.listPending).toBe(1);
    // A espera do polling nunca é chamada.
    expect(reg.dormiu).toBe(0);
    expect(r.body).toEqual({ ok: true, processed: 1, sent: 1, failed: 0, skipped: 0, unsupported: 0 });
  });

  it("o resultado executado é o do runtime one-shot real (ciclos = 1)", async () => {
    const reg = novoRegistro();
    const resultados: Array<{ ciclos: number; parouPor: string }> = [];
    const { f } = fabricas(reg, [], {
      executar: async (deps) => {
        const r = await executarUmaVez(deps);
        resultados.push({ ciclos: r.ciclos, parouPor: r.parouPor });
        return r;
      },
    });
    await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);
    expect(resultados).toEqual([{ ciclos: 1, parouPor: "one_shot" }]);
  });

  it("posse atômica ANTES de transmitir; template não suportado nunca é tocado", async () => {
    const reg = novoRegistro();
    const { f } = fabricas(reg, [
      evento("sup1", "partner_application_email_verification"),
      evento("nao1", "partner_welcome_generic"),
      evento("sup2", "manager_invite"),
    ]);
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);

    expect(r.body).toEqual({ ok: true, processed: 3, sent: 2, failed: 0, skipped: 0, unsupported: 1 });
    // Ordem canônica: mint → send → markSent, por evento.
    expect(reg.chamadas).toEqual([
      "listPending",
      "mint:sup1",
      "send:idem-sup1",
      "sent:sup1",
      "mint:sup2",
      "send:idem-sup2",
      "sent:sup2",
    ]);
    // Fail-closed: nenhum mint, send, mark ou reschedule para o não suportado.
    expect(reg.chamadas.filter((c) => c.includes("nao1"))).toEqual([]);
  });

  it("invocação duplicada é segura: sem posse (lease_held), nada é transmitido", async () => {
    const reg = novoRegistro();
    const { f } = fabricas(reg, [evento("n1", "manager_invite")], {
      mint: () => ({ ok: false, reason: "lease_held" }),
    });
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);
    expect(r.body).toEqual({ ok: true, processed: 1, sent: 0, failed: 0, skipped: 1, unsupported: 0 });
    expect(reg.enviados).toHaveLength(0);
    expect(reg.chamadas).not.toContain("sent:n1");
  });

  it("o adaptador reutiliza o runtime e a fábrica do worker — sem polling, sem processo filho, sem despacho próprio", () => {
    const fonte = lerFonte("src/server/worker/emailOutboxCronHandler.ts");
    const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    expect(codigo).toContain("executarUmaVez");
    expect(codigo).toContain("construirDependenciasWorker");
    expect(codigo).toContain("carregarWorkerConfig");
    expect(codigo).not.toMatch(/executarPolling|SinalDeParada|dormirCancelavel/);
    expect(codigo).not.toMatch(/child_process|spawn\(|exec\(/);
    expect(codigo).not.toMatch(/dispatchPending|mintApplicationToken|mintManagerInviteToken|markSent/);
    expect(codigo).not.toMatch(/createClient|supabase\.from|\.rpc\(/);

    const api = lerFonte("api/internal/email-outbox-dispatch.ts");
    expect(api).toContain("executarCicloEmailAgendado");
    expect(api).not.toMatch(/executarPolling|createClient|dispatchPending|child_process/);
  });

  it("CLI e adaptador montam as dependências pela MESMA fábrica", () => {
    const main = lerFonte("src/server/worker/main.ts");
    expect(main).toContain("construirDependenciasWorker(config, logger)");
    expect(main).not.toContain("createSupabaseOutboxGateway(");
    expect(main).not.toContain("criarTransporteSmtp(");
  });
});

// ---------------------------------------------------------------------------
describe("handler one-shot — resposta sanitizada", () => {
  it("sucesso devolve só contadores — nada de segredo, PII, token ou URL", async () => {
    const logs: string[] = [];
    const reg = novoRegistro();
    const { f } = fabricas(reg, [evento("n1", "partner_application_account_claim")], {}, logs);
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);

    expect(Object.keys(r.body).sort()).toEqual(
      ["failed", "ok", "processed", "sent", "skipped", "unsupported"].sort()
    );
    const corpo = JSON.stringify(r);
    semVazamento(corpo, [...SEGREDOS, ...PII, "supabase.co", "smtp.exemplo", "msg-"]);
    // O transporte recebeu o token (é o corpo do e-mail) — prova de que o
    // teste exercitou o caminho onde ele existe.
    expect(JSON.stringify(reg.enviados)).toContain(TOKEN_CUNHADO);
    semVazamento(logs.join("\n"), [CRON_SECRET, SMTP_PASSWORD, SERVICE_KEY, TOKEN_CUNHADO, DESTINATARIO]);
  });

  it("falha de infraestrutura no ciclo → 502 genérico, sem mensagem crua nem stack", async () => {
    const logs: string[] = [];
    const erro = new Error(
      `conexão recusada usando ${SERVICE_KEY} para ${DESTINATARIO} senha ${SMTP_PASSWORD} cron ${CRON_SECRET}`
    );
    const { f } = fabricas(novoRegistro(), [], { erroNaDescoberta: erro }, logs);
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);

    expect(r.status).toBe(502);
    expect(r.body).toEqual({ ok: false, code: "worker_cycle_failed" });
    const corpo = JSON.stringify(r);
    semVazamento(corpo, [...SEGREDOS, ...PII, "conexão recusada", "at "]);
    semVazamento(logs.join("\n"), [CRON_SECRET, SMTP_PASSWORD, SERVICE_KEY, DESTINATARIO, "conexão recusada"]);
  });

  it("configuração inválida → 503 genérico, sem nome de variável nem valor", async () => {
    const { f, executar } = fabricas(novoRegistro(), [], {
      carregarConfig: () => {
        throw new WorkerConfigError("missing_required_env", "variável ausente: SMTP_PASSWORD");
      },
    });
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);
    expect(r.status).toBe(503);
    expect(r.body).toEqual({ ok: false, code: "worker_unavailable" });
    expect(JSON.stringify(r)).not.toContain("SMTP_PASSWORD");
    expect(executar).not.toHaveBeenCalled();
  });

  it("exceção inesperada → 500 genérico, sem mensagem nem stack", async () => {
    const logs: string[] = [];
    const { f } = fabricas(
      novoRegistro(),
      [],
      {
        construirDependencias: () => {
          throw new TypeError(`falhou com ${SERVICE_KEY} e ${CRON_SECRET} para ${DESTINATARIO}`);
        },
      },
      logs
    );
    const r = await executarCicloEmailAgendado(req(AUTH_OK), ENV_OK, f);
    expect(r.status).toBe(500);
    expect(r.body).toEqual({ ok: false, code: "unexpected_error" });
    semVazamento(JSON.stringify(r), [...SEGREDOS, ...PII, "TypeError", "falhou com"]);
    semVazamento(logs.join("\n"), [CRON_SECRET, SERVICE_KEY, DESTINATARIO, "falhou com"]);
  });

  it("toda resposta é no-store", async () => {
    const { f } = fabricas(novoRegistro());
    for (const [h, m] of [[AUTH_OK, "GET"], [{}, "GET"], [AUTH_OK, "POST"]] as const) {
      const r = await executarCicloEmailAgendado(req(h, m), ENV_OK, f);
      expect(r.headers["Cache-Control"]).toBe("no-store");
    }
  });
});

// ---------------------------------------------------------------------------
describe("função Vercel api/internal/email-outbox-dispatch (fábricas reais, sem rede)", () => {
  afterEach(() => vi.unstubAllEnvs());

  function resFalsa() {
    const estado: { status?: number; body?: unknown; headers: Record<string, string> } = { headers: {} };
    type ResT = {
      status: (c: number) => ResT;
      json: (b: unknown) => void;
      setHeader: (k: string, v: string) => void;
    };
    const res: ResT = {
      status(c: number) {
        estado.status = c;
        return res;
      },
      json(b: unknown) {
        estado.body = b;
      },
      setHeader(k: string, v: string) {
        estado.headers[k] = v;
      },
    };
    return { res, estado };
  }

  it("sem CRON_SECRET no ambiente do processo → 401", async () => {
    vi.stubEnv("CRON_SECRET", "");
    const { res, estado } = resFalsa();
    await apiHandler({ method: "GET", headers: { authorization: `Bearer ${CRON_SECRET}` } }, res);
    expect(estado.status).toBe(401);
    expect(estado.body).toEqual({ ok: false, code: "unauthorized" });
    expect(estado.headers["Cache-Control"]).toBe("no-store");
  });

  it("autorizado, mas sem config do worker → 503 fail-closed antes de qualquer conexão", async () => {
    vi.stubEnv("CRON_SECRET", CRON_SECRET);
    vi.stubEnv("ENVIRONMENT", "");
    vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "");
    vi.stubEnv("SMTP_PASSWORD", "");
    const { res, estado } = resFalsa();
    await apiHandler({ method: "GET", headers: { authorization: `Bearer ${CRON_SECRET}` } }, res);
    expect(estado.status).toBe(503);
    expect(JSON.stringify(estado.body)).not.toContain(CRON_SECRET);
  });
});

// ---------------------------------------------------------------------------
describe("semântica R16 preservada", () => {
  it("o escopo suportado continua exatamente nos três templates", () => {
    expect([...R16_SUPPORTED_TEMPLATE_KEYS].sort()).toEqual(
      ["manager_invite", "partner_application_account_claim", "partner_application_email_verification"].sort()
    );
  });

  it("VITE_CRON_SECRET é rejeitado pelo carregador do worker", () => {
    expect(() => rejeitarSegredosPublicos({ VITE_CRON_SECRET: "x" })).toThrow(WorkerConfigError);
  });

  it(".env.example declara CRON_SECRET só como nome, sem valor e sem prefixo público", () => {
    const linhas = lerFonte(".env.example").split(/\r?\n/);
    expect(linhas).toContain("CRON_SECRET=");
    expect(linhas.some((l) => /^(VITE_|NEXT_PUBLIC_)\w*CRON/.test(l))).toBe(false);
  });

  it("vercel.json não aponta rewrite de SPA para /api", () => {
    const cfg = JSON.parse(lerFonte("vercel.json")) as { rewrites?: Array<{ source: string }> };
    for (const r of cfg.rewrites ?? []) {
      expect(new RegExp(`^${r.source}$`).test("/api/internal/email-outbox-dispatch")).toBe(false);
    }
  });
});

// ---------------------------------------------------------------------------
describe("fronteira do navegador", () => {
  /**
   * Percorre o grafo REAL do bundle a partir de `src/main.tsx` (imports
   * relativos; o projeto não usa alias) e prova que nenhum módulo de
   * worker/adaptador entra nele, nem os nomes das variáveis server-side.
   */
  const RE_IMPORT = /(?:import|export)\b[^;]*?from\s+["'](\.[^"']+)["']|import\s*\(\s*["'](\.[^"']+)["']\s*\)|^\s*import\s+["'](\.[^"']+)["']/gm;

  function resolver(de: string, spec: string): string | null {
    const base = normalize(join(dirname(de), spec));
    const sem = base.replace(/\.(js|mjs)$/, "");
    const candidatos = [base, `${sem}.ts`, `${sem}.tsx`, `${base}.ts`, `${base}.tsx`, join(base, "index.ts"), join(base, "index.tsx")];
    for (const c of candidatos) {
      const abs = resolve(RAIZ, c);
      if (existsSync(abs) && /\.(tsx?|js|mjs|css|json|svg)$/.test(c)) return c.replace(/\\/g, "/");
    }
    return null;
  }

  function grafoDoNavegador(): string[] {
    const vistos = new Set<string>();
    const fila = ["src/main.tsx"];
    while (fila.length) {
      const atual = fila.shift() as string;
      if (vistos.has(atual)) continue;
      vistos.add(atual);
      if (!/\.tsx?$/.test(atual)) continue;
      const fonte = readFileSync(resolve(RAIZ, atual), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
      RE_IMPORT.lastIndex = 0;
      let m: RegExpExecArray | null;
      while ((m = RE_IMPORT.exec(fonte)) !== null) {
        const spec = m[1] ?? m[2] ?? m[3];
        const alvo = resolver(atual, spec);
        if (alvo) fila.push(alvo);
      }
    }
    return [...vistos];
  }

  const grafo = grafoDoNavegador();

  it("o percurso alcança o app de verdade (não é falso verde)", () => {
    expect(grafo).toContain("src/App.tsx");
    expect(grafo.length).toBeGreaterThan(30);
  });

  it("nenhum módulo do worker, do adaptador ou de api/ entra no bundle", () => {
    const proibidos = grafo.filter(
      (m) => m.startsWith("src/server/worker/") || m.startsWith("api/") || m.includes("emailOutboxCronHandler")
    );
    expect(proibidos).toEqual([]);
  });

  it("nenhum módulo do bundle referencia service_role, credencial SMTP ou CRON_SECRET", () => {
    const termos = ["SUPABASE_SERVICE_ROLE_KEY", "SMTP_PASSWORD", "SMTP_USERNAME", "CRON_SECRET", "service_role"];
    const achados: string[] = [];
    for (const m of grafo.filter((x) => /\.tsx?$/.test(x))) {
      const codigo = readFileSync(resolve(RAIZ, m), "utf8")
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/^\s*\/\/.*$/gm, "");
      for (const t of termos) if (codigo.includes(t)) achados.push(`${m} :: ${t}`);
    }
    expect(achados).toEqual([]);
  });

  it("o Vite mantém o prefixo público padrão (só VITE_ é exposto)", () => {
    expect(lerFonte("vite.config.ts")).not.toMatch(/envPrefix/);
  });
});
