import { describe, it, expect } from "vitest";
import {
  createSupabaseOutboxGateway,
  dividirCapacidade,
  validarLinha,
  WorkerConfigError,
  BATCH_SIZE_MINIMO,
} from "../server/worker/supabaseOutboxGateway";
import { dispatchPending } from "../server/notifications/dispatchOutbox";
import { FakeLocalTransport } from "../server/notifications/emailProvider";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * R16 — CHECKPOINT 2: DESCOBERTA EM DUAS FASES E RECUPERAÇÃO APÓS CRASH.
 *
 * INVARIANTE CENTRAL
 *   Um worker que morre depois de tomar posse NÃO pode deixar o evento órfão
 *   para sempre.
 *
 * FRONTEIRAS DE PROVA — deliberadamente não fundidas:
 *   R15_DB_ATOMIC_CLAIM_PROOF   semântica real de lock/lease no PostgreSQL,
 *                               provada no M1-C com duas sessões. NÃO aqui.
 *   R16_DISPATCHER_DUPLICATE_PROTECTION  o worker respeita o resultado do
 *                               claim e envia uma única vez.
 *   R16_CRASH_RECOVERY_CONTRACT a redescoberta devolve a linha `sending`
 *                               abandonada à RPC canônica.
 *   STAGING_SMOKE               integração remota, depois.
 *
 * O cliente falso reproduz os filtros que o gateway emite (eq/in/or/order/
 * limit) sobre um conjunto de linhas, para que a consulta seja realmente
 * exercitada — e não apenas registrada.
 */

type Linha = {
  id: string;
  channel: string;
  template_key: string;
  template_data: Record<string, unknown> | null;
  recipient_address: string | null;
  idempotency_key: string;
  status: string;
  attempt_count: number;
  scheduled_for: string | null;
  created_at: string;
  updated_at: string;
};

// HARNESS_FIXTURE_BUG corrigido: uma versão anterior fixava AGORA numa data
// literal, mas o gateway usa `new Date()` real. Se o relógio do ambiente
// passasse dessa data, um `scheduled_for` "futuro" do teste já seria passado
// para o gateway, e o caso de exclusão passaria a validar o oposto do que
// afirma. Ancorar no relógio real elimina a dependência de calendário.
const AGORA = Date.now();
const iso = (offset: number) => new Date(AGORA + offset).toISOString();
const uuid = (n: number) => `11111111-1111-1111-1111-${String(n).padStart(12, "0")}`;

function linha(over: Partial<Linha> = {}): Linha {
  const id = over.id ?? uuid(1);
  return {
    id,
    channel: "email",
    template_key: "partner_application_email_verification",
    template_data: { application_id: "app-1" },
    recipient_address: "destino@teste.com.br",
    idempotency_key: `idem-${id}`,
    status: "pending",
    attempt_count: 0,
    scheduled_for: null,
    created_at: iso(-60_000),
    updated_at: iso(-60_000),
    ...over,
  };
}

/** Cliente Supabase falso que aplica os filtros realmente emitidos. */
function clienteFalso(
  linhas: Linha[],
  rpcImpl: Record<string, (a: Record<string, unknown>) => unknown>
) {
  const consultas: { filtros: Record<string, unknown>; ordem: string[]; limite: number }[] = [];

  function builder() {
    const filtros: Record<string, unknown> = {};
    const ordem: string[] = [];
    const api = {
      select: () => api,
      eq(c: string, v: unknown) { filtros[`eq:${c}`] = v; return api; },
      in(c: string, v: unknown[]) { filtros[`in:${c}`] = v; return api; },
      or(e: string) { filtros["or"] = e; return api; },
      order(c: string) { ordem.push(c); return api; },
      async limit(n: number) {
        consultas.push({ filtros, ordem, limite: n });
        let out = linhas.filter((l) => {
          if (filtros["eq:channel"] && l.channel !== filtros["eq:channel"]) return false;
          const tpl = filtros["in:template_key"] as string[] | undefined;
          if (tpl && !tpl.includes(l.template_key)) return false;
          if (filtros["eq:status"] && l.status !== filtros["eq:status"]) return false;
          if (typeof filtros["or"] === "string") {
            const m = /scheduled_for\.lte\.([^)]+)\)/.exec(filtros["or"] as string);
            const corte = m ? Date.parse(m[1]) : AGORA;
            const pend = l.status === "pending";
            const vencido =
              l.status === "scheduled" &&
              l.scheduled_for !== null &&
              Date.parse(l.scheduled_for) <= corte;
            if (!pend && !vencido) return false;
          }
          return true;
        });
        const chave = ordem[0] === "updated_at" ? "updated_at" : "created_at";
        out = [...out].sort((a, b) => {
          const d = Date.parse(a[chave as "updated_at"]) - Date.parse(b[chave as "updated_at"]);
          return d !== 0 ? d : a.id.localeCompare(b.id);
        });
        return { data: out.slice(0, n), error: null };
      },
    };
    return api;
  }

  const client = {
    from: () => builder(),
    async rpc(nome: string, args: Record<string, unknown>) {
      const fn = rpcImpl[nome];
      if (!fn) return { data: null, error: { code: "42883" } };
      return { data: fn(args), error: null };
    },
  } as unknown as SupabaseClient;

  return { client, consultas };
}

/** RPC de cunhagem reproduzindo a decisão canônica sobre posse e lease. */
function rpcs(linhas: Linha[], leaseVivo: (l: Linha) => boolean, chamadas: string[]) {
  const mint = (a: Record<string, unknown>) => {
    const id = String(a.p_notification_id);
    chamadas.push(id);
    const l = linhas.find((x) => x.id === id);
    if (!l) return { ok: false, reason: "not_dispatchable" };
    if (l.status === "sending" && leaseVivo(l)) return { ok: false, reason: "lease_held" };
    if (l.status === "scheduled" && l.scheduled_for && Date.parse(l.scheduled_for) > AGORA) {
      return { ok: false, reason: "not_due_yet" };
    }
    if (!["pending", "scheduled", "sending"].includes(l.status)) {
      return { ok: false, reason: "not_dispatchable" };
    }
    // Teto de tentativas: decisão do BANCO, não do TypeScript.
    if (l.attempt_count >= 5) {
      l.status = "failed";
      return { ok: false, reason: "max_attempts" };
    }
    l.status = "sending";
    l.attempt_count += 1;
    l.updated_at = new Date(AGORA).toISOString();
    return {
      ok: true,
      token: `segredo-${id}`,
      recipient: l.recipient_address,
      purpose: "email_verification",
      attempt: l.attempt_count,
      expires_in_seconds: 1800,
    };
  };
  return {
    svc_mint_partner_application_token: mint,
    svc_mint_manager_invite_token: mint,
    svc_mark_notification_sent: (a: Record<string, unknown>) => {
      const l = linhas.find((x) => x.id === String(a.p_notification_id));
      if (l && l.status === "sending") l.status = "sent";
      return { ok: true };
    },
    svc_mark_notification_failed: (a: Record<string, unknown>) => {
      const l = linhas.find((x) => x.id === String(a.p_notification_id));
      if (l && l.status === "sending") l.status = "failed";
      return { ok: true };
    },
    svc_reschedule_notification: () => ({ ok: true }),
  };
}

const LEASE_VIVO = () => true;
const LEASE_VENCIDO = () => false;

// ===========================================================================

describe("R16_NORMAL_DISCOVERY", () => {
  it("evento pending é descoberto e processado", async () => {
    const ls = [linha({ id: uuid(1) })];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const t = new FakeLocalTransport();
    const r = await dispatchPending(createSupabaseOutboxGateway(client), t, { max: 10 });
    expect(r.sent).toBe(1);
    expect(t.sent).toHaveLength(1);
    expect(ls[0].status).toBe("sent");
  });

  it("apenas as colunas necessárias são mapeadas", async () => {
    const ls = [linha({ id: uuid(1) })];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const [p] = await createSupabaseOutboxGateway(client).listPending("email", 10);
    expect(Object.keys(p).sort()).toEqual(
      ["channel", "id", "idempotency_key", "recipient_address", "template_data", "template_key"].sort()
    );
  });

  it("ordem da fase normal é created_at ASC, id ASC", async () => {
    const ls = [
      linha({ id: uuid(3), created_at: iso(-1000) }),
      linha({ id: uuid(1), created_at: iso(-9000) }),
      linha({ id: uuid(2), created_at: iso(-5000) }),
    ];
    const { client, consultas } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const out = await createSupabaseOutboxGateway(client).listPending("email", 10);
    expect(out.map((o) => o.id)).toEqual([uuid(1), uuid(2), uuid(3)]);
    expect(consultas[0].ordem).toEqual(["created_at", "id"]);
  });
});

describe("R16_SCHEDULED_DUE_DISCOVERY", () => {
  it("scheduled já vencido é descoberto", async () => {
    const ls = [linha({ id: uuid(2), status: "scheduled", scheduled_for: iso(-1000) })];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    expect(await createSupabaseOutboxGateway(client).listPending("email", 10)).toHaveLength(1);
  });

  it("scheduled exatamente vencido (=agora) é elegível", async () => {
    const ls = [linha({ id: uuid(2), status: "scheduled", scheduled_for: iso(0) })];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    expect(await createSupabaseOutboxGateway(client).listPending("email", 10)).toHaveLength(1);
  });
});

describe("R16_FUTURE_SCHEDULED_EXCLUDED", () => {
  it("scheduled futuro NÃO é devolvido como trabalho normal", async () => {
    const ls = [linha({ id: uuid(3), status: "scheduled", scheduled_for: iso(3_600_000) })];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    expect(await createSupabaseOutboxGateway(client).listPending("email", 10)).toHaveLength(0);
  });

  it("estados terminais são excluídos", async () => {
    for (const status of ["sent", "delivered", "read", "failed", "cancelled"]) {
      const ls = [linha({ id: uuid(4), status })];
      const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
      expect(await createSupabaseOutboxGateway(client).listPending("email", 10)).toHaveLength(0);
    }
  });
});

describe("R16_RECOVERY_ORDERING", () => {
  it("sondagem usa updated_at ASC, id ASC", async () => {
    const ls = [
      linha({ id: uuid(30), status: "sending", updated_at: iso(-1000) }),
      linha({ id: uuid(10), status: "sending", updated_at: iso(-9000) }),
      linha({ id: uuid(20), status: "sending", updated_at: iso(-5000) }),
    ];
    const { client, consultas } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const gw = createSupabaseOutboxGateway(client, {}, { recoveryReserve: 3 });
    const out = await gw.listPending("email", 4);
    expect(out.map((o) => o.id)).toEqual([uuid(10), uuid(20), uuid(30)]);
    const faseB = consultas.find((c) => c.filtros["eq:status"] === "sending");
    expect(faseB?.ordem).toEqual(["updated_at", "id"]);
  });

  it("updated_at NÃO é interpretado como expirado/não expirado pelo TypeScript", async () => {
    // Duas linhas idênticas exceto por updated_at; ambas são SONDADAS.
    // Quem decide o desfecho é a RPC, não a idade da coluna.
    const ls = [
      linha({ id: uuid(40), status: "sending", updated_at: iso(-1) }),
      linha({ id: uuid(41), status: "sending", updated_at: iso(-99_999_999) }),
    ];
    const chamadas: string[] = [];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, chamadas));
    const gw = createSupabaseOutboxGateway(client, {}, { recoveryReserve: 2 });
    await dispatchPending(gw, new FakeLocalTransport(), { max: 3 });
    // Ambas foram apresentadas à RPC; nenhuma foi pré-filtrada por idade.
    expect(chamadas.sort()).toEqual([uuid(40), uuid(41)]);
  });
});

describe("R16_ACTIVE_LEASE_NO_SEND", () => {
  it("sending com lease VIVO é sondado, recebe lease_held e não envia", async () => {
    const ls = [linha({ id: uuid(6), status: "sending", attempt_count: 1 })];
    const chamadas: string[] = [];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, chamadas));
    const t = new FakeLocalTransport();
    const motivos: string[] = [];
    const r = await dispatchPending(createSupabaseOutboxGateway(client), t, {
      max: 10,
      onDiagnostic: (e) => motivos.push(e.reason),
    });

    expect(chamadas).toEqual([uuid(6)]);       // a RPC FOI consultada
    expect(t.sent).toHaveLength(0);            // e negou o envio
    expect(r.sent).toBe(0);
    expect(motivos).toContain("lease_held");
    expect(ls[0].status).toBe("sending");      // posse alheia intacta
    expect(ls[0].attempt_count).toBe(1);
  });
});

describe("R16_EXPIRED_LEASE_RECOVERY_PATH", () => {
  it("sending com lease VENCIDO produz exatamente um envio", async () => {
    const ls = [
      linha({ id: uuid(7), status: "sending", attempt_count: 1, updated_at: iso(-3_600_000) }),
    ];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VENCIDO, []));
    const t = new FakeLocalTransport();
    const r = await dispatchPending(createSupabaseOutboxGateway(client), t, { max: 10 });
    expect(r.sent).toBe(1);
    expect(t.sent).toHaveLength(1);
    expect(ls[0].status).toBe("sent");
    expect(ls[0].attempt_count).toBe(2);
  });
});

describe("R16_CRASH_RECOVERY_CONTRACT", () => {
  it("worker morto: o evento não fica órfão para sempre", async () => {
    const ls = [linha({ id: uuid(8) })];
    const chamadas: string[] = [];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, chamadas));
    const gw = createSupabaseOutboxGateway(client);

    // Worker 1 toma posse e MORRE antes de marcar enviado.
    const posse = await gw.mintApplicationToken(uuid(8));
    expect(posse.ok).toBe(true);
    expect(ls[0].status).toBe("sending");

    // Com o lease vivo, nenhum reenvio.
    const t1 = new FakeLocalTransport();
    await dispatchPending(gw, t1, { max: 10 });
    expect(t1.sent).toHaveLength(0);

    // Passado o lease, a MESMA sondagem reapresenta a linha à RPC, que a
    // recupera. O worker não decidiu isso — a RPC decidiu.
    const chamadas2: string[] = [];
    const { client: c2 } = clienteFalso(ls, rpcs(ls, LEASE_VENCIDO, chamadas2));
    const t2 = new FakeLocalTransport();
    const r2 = await dispatchPending(createSupabaseOutboxGateway(c2), t2, { max: 10 });

    expect(chamadas2).toContain(uuid(8));
    expect(r2.sent).toBe(1);
    expect(ls[0].status).toBe("sent");
  });

  it("a sondagem é read-only: nenhuma mutação direta", async () => {
    const ls = [linha({ id: uuid(9), status: "sending", attempt_count: 2 })];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const antes = JSON.stringify(ls[0]);
    await createSupabaseOutboxGateway(client).listPending("email", 10);
    expect(JSON.stringify(ls[0])).toBe(antes);
  });
});

describe("R16_NORMAL_WORK_NO_STARVATION", () => {
  it("muitos sending não consomem a capacidade normal", async () => {
    const ls: Linha[] = [];
    for (let i = 0; i < 30; i++) {
      ls.push(linha({ id: uuid(100 + i), status: "sending", updated_at: iso(-9_000_000 + i) }));
    }
    ls.push(linha({ id: uuid(200), status: "pending", created_at: iso(-10) }));

    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const out = await createSupabaseOutboxGateway(client).listPending("email", 5);

    expect(out.some((e) => e.id === uuid(200))).toBe(true);
    const sondagens = out.filter((e) => e.id !== uuid(200));
    expect(sondagens).toHaveLength(1); // recoveryReserve=1
  });
});

describe("R16_RECOVERY_NO_STARVATION", () => {
  it("tráfego normal contínuo não elimina a vaga de recuperação", async () => {
    const ls: Linha[] = [];
    for (let i = 0; i < 50; i++) {
      ls.push(linha({ id: uuid(300 + i), status: "pending", created_at: iso(-5000 + i) }));
    }
    ls.push(linha({ id: uuid(999), status: "sending", updated_at: iso(-7_200_000) }));

    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const out = await createSupabaseOutboxGateway(client).listPending("email", 5);
    expect(out.some((e) => e.id === uuid(999))).toBe(true);
  });
});

describe("R16_BATCH_MINIMUM_VALIDATION", () => {
  it("batchSize=2 dá exatamente uma vaga a cada classe", () => {
    expect(dividirCapacidade(2, 1)).toEqual({ normal: 1, recovery: 1 });
  });

  it("toda divisão válida garante normal>=1 e recovery>=1", () => {
    for (let b = BATCH_SIZE_MINIMO; b <= 30; b++) {
      for (let r = 1; r < b; r++) {
        const c = dividirCapacidade(b, r);
        expect(c.normal).toBeGreaterThanOrEqual(1);
        expect(c.recovery).toBeGreaterThanOrEqual(1);
        expect(c.normal + c.recovery).toBe(b);
      }
    }
  });

  it("batchSize=1 é REJEITADO, não coagido para 2", () => {
    expect(() => dividirCapacidade(1, 1)).toThrow(WorkerConfigError);
    try {
      dividirCapacidade(1, 1);
    } catch (e) {
      expect((e as WorkerConfigError).code).toBe("batch_size_below_minimum");
      expect((e as WorkerConfigError).message).not.toMatch(/key|senha|token|password/i);
    }
  });

  it("recoveryReserve inválido é rejeitado, nunca normalizado", () => {
    expect(() => dividirCapacidade(10, 0)).toThrow(WorkerConfigError);
    expect(() => dividirCapacidade(10, -1)).toThrow(WorkerConfigError);
    expect(() => dividirCapacidade(5, 5)).toThrow(WorkerConfigError);
    expect(() => dividirCapacidade(5, 99)).toThrow(WorkerConfigError);
    expect(() => dividirCapacidade(10, 1.5)).toThrow(WorkerConfigError);
    expect(() => dividirCapacidade(2.5, 1)).toThrow(WorkerConfigError);
  });

  it("os códigos de erro são distintos e estáveis", () => {
    const cod = (fn: () => unknown) => {
      try { fn(); return "sem_erro"; } catch (e) { return (e as WorkerConfigError).code; }
    };
    expect(cod(() => dividirCapacidade(1, 1))).toBe("batch_size_below_minimum");
    expect(cod(() => dividirCapacidade(10, 0))).toBe("recovery_reserve_below_minimum");
    expect(cod(() => dividirCapacidade(5, 5))).toBe("recovery_reserve_exceeds_batch");
    expect(cod(() => dividirCapacidade(2.5, 1))).toBe("invalid_batch_size");
    expect(cod(() => dividirCapacidade(10, 1.5))).toBe("invalid_recovery_reserve");
  });

  it("listPending propaga a rejeição de lote inválido", async () => {
    const ls = [linha()];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    await expect(createSupabaseOutboxGateway(client).listPending("email", 1)).rejects.toThrow(
      WorkerConfigError
    );
  });
});

describe("R16_INVALID_RECIPIENT_FAIL_CLOSED", () => {
  it("linha sem endereço não vira e-mail", () => {
    expect(validarLinha({ id: uuid(1), channel: "email", template_key: "partner_application_email_verification", template_data: {}, recipient_address: null, idempotency_key: "k" })).toBeNull();
    expect(validarLinha({ id: uuid(1), channel: "email", template_key: "partner_application_email_verification", template_data: {}, recipient_address: "", idempotency_key: "k" })).toBeNull();
    expect(validarLinha({ id: uuid(1), channel: "email", template_key: "partner_application_email_verification", template_data: {}, recipient_address: "   ", idempotency_key: "k" })).toBeNull();
    expect(validarLinha({ id: uuid(1), channel: "email", template_key: "partner_application_email_verification", template_data: {}, recipient_address: "sem-arroba", idempotency_key: "k" })).toBeNull();
  });

  it("CR/LF/NUL no endereço é rejeitado (injeção de cabeçalho)", () => {
    for (const mau of ["a@b.com\r\nBcc: x@y.com", "a@b.com\nX: 1", "a@b.com\0"]) {
      expect(validarLinha({ id: uuid(1), channel: "email", template_key: "partner_application_email_verification", template_data: {}, recipient_address: mau, idempotency_key: "k" })).toBeNull();
    }
  });

  it("id que não é uuid é rejeitado", () => {
    expect(validarLinha({ id: "nao-e-uuid", channel: "email", template_key: "partner_application_email_verification", template_data: {}, recipient_address: "a@b.com", idempotency_key: "k" })).toBeNull();
  });

  it("template_data inválido é rejeitado", () => {
    for (const mau of [null, "texto", [1, 2]]) {
      expect(validarLinha({ id: uuid(1), channel: "email", template_key: "partner_application_email_verification", template_data: mau, recipient_address: "a@b.com", idempotency_key: "k" })).toBeNull();
    }
  });

  it("linha malformada não chega ao transporte", async () => {
    const ls = [linha({ id: uuid(50), recipient_address: null })];
    const chamadas: string[] = [];
    const invalidas: string[] = [];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, chamadas));
    const gw = createSupabaseOutboxGateway(client, {
      onLinhaInvalida: (i) => invalidas.push(i.motivo),
    });
    const t = new FakeLocalTransport();
    const r = await dispatchPending(gw, t, { max: 10 });

    expect(t.sent).toHaveLength(0);
    expect(chamadas).toEqual([]);            // nem sequer reivindicada
    expect(r.processed).toBe(0);
    expect(invalidas).toEqual(["malformed_row_rejected"]);
    expect(ls[0].status).toBe("pending");    // intocada
  });
});

describe("R16_MAX_ATTEMPTS_AUTHORITY", () => {
  it("a consulta NÃO filtra por attempt_count — o banco decide", async () => {
    const ls = [linha({ id: uuid(60), attempt_count: 99 })];
    const { client, consultas } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, []));
    const out = await createSupabaseOutboxGateway(client).listPending("email", 10);

    // Descoberto apesar do attempt_count alto: nenhuma autoridade local.
    expect(out).toHaveLength(1);
    for (const c of consultas) {
      expect(Object.keys(c.filtros).some((k) => k.includes("attempt_count"))).toBe(false);
    }
  });

  it("candidato no teto é descoberto, a RPC recusa e nada é enviado", async () => {
    const ls = [linha({ id: uuid(61), attempt_count: 5 })];
    const chamadas: string[] = [];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VIVO, chamadas));
    const t = new FakeLocalTransport();
    const motivos: string[] = [];
    const r = await dispatchPending(createSupabaseOutboxGateway(client), t, {
      max: 10,
      onDiagnostic: (e) => motivos.push(e.reason),
    });

    expect(chamadas).toEqual([uuid(61)]);   // apresentado à autoridade
    expect(motivos).toContain("max_attempts");
    expect(t.sent).toHaveLength(0);
    expect(ls[0].status).toBe("failed");    // transição canônica do banco
    expect(r.sent).toBe(0);
  });
});

describe("R16_UNSUPPORTED_TEMPLATE_EXCLUSION", () => {
  it("template não suportado fica fora das DUAS fases", async () => {
    const ls = [
      linha({ id: uuid(70), status: "pending", template_key: "partner_application_decided" }),
      linha({ id: uuid(71), status: "sending", template_key: "partner_application_decided" }),
    ];
    const chamadas: string[] = [];
    const { client } = clienteFalso(ls, rpcs(ls, LEASE_VENCIDO, chamadas));
    const t = new FakeLocalTransport();
    const r = await dispatchPending(createSupabaseOutboxGateway(client), t, { max: 10 });

    expect(r.processed).toBe(0);
    expect(chamadas).toEqual([]);
    expect(t.sent).toHaveLength(0);
    expect(ls[0].status).toBe("pending");
    expect(ls[1].status).toBe("sending");
  });
});

describe("R16_OUTBOX_TWO_WORKER_DUPLICATE_PROTECTION", () => {
  it("dois workers sondando o mesmo sending: um único remetente", async () => {
    const ls = [
      linha({ id: uuid(80), status: "sending", attempt_count: 1, updated_at: iso(-7_200_000) }),
    ];
    let recuperado = false;
    const leaseVivo = () => {
      if (!recuperado) { recuperado = true; return false; }
      return true;
    };
    const { client } = clienteFalso(ls, rpcs(ls, leaseVivo, []));
    const gw = createSupabaseOutboxGateway(client);
    const a = new FakeLocalTransport();
    const b = new FakeLocalTransport();

    await Promise.all([
      dispatchPending(gw, a, { max: 10 }),
      dispatchPending(gw, b, { max: 10 }),
    ]);

    expect(a.sent.length + b.sent.length).toBe(1);
  });
});
