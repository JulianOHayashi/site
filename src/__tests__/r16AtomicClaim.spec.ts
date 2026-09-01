import { describe, it, expect } from "vitest";
import {
  dispatchPending,
  type CanonicalOutboxGateway,
  type PendingNotification,
  type MintOutcome,
} from "../server/notifications/dispatchOutbox";
import { FakeLocalTransport } from "../server/notifications/emailProvider";
import {
  R16_SUPPORTED_TEMPLATE_KEYS,
  R16_SUPPORTED_TEMPLATES,
  isSupportedTemplate,
  mintCategoryFor,
} from "../server/notifications/supportedTemplates";

/**
 * R16 — POSSE ATÔMICA E PROTEÇÃO CONTRA ENVIO DUPLICADO.
 *
 * O gateway abaixo NÃO é um mock de contagem de chamadas: ele reproduz a
 * semântica das RPCs canônicas do M1 sobre estado compartilhado —
 * `SELECT ... FOR UPDATE` seguido de transição para `sending`. Sem isso o
 * teste de concorrência não provaria nada.
 *
 *   pending  + cunhagem      → posse, vira 'sending', attempt+1
 *   sending  (lease vivo)    → 'lease_held', SEM posse
 *   sent                     → 'not_dispatchable'
 *
 * FRONTEIRAS DE PROVA — não fundir:
 *   R15_DB_ATOMIC_CLAIM_PROOF        semântica real de lock no PostgreSQL
 *                                    (evidência prévia do M1-C). NÃO provada aqui.
 *   R16_DISPATCHER_DUPLICATE_PROTECTION  o worker respeita o resultado do
 *                                    claim e envia exatamente uma vez.
 *   STAGING_SMOKE                    integração remota, depois.
 */

type LinhaOutbox = {
  id: string;
  template_key: string;
  status: "pending" | "sending" | "sent" | "failed" | "scheduled";
  attempt_count: number;
  recipient_address: string;
  idempotency_key: string;
  template_data: Record<string, unknown>;
};

class OutboxFalso {
  readonly linhas = new Map<string, LinhaOutbox>();
  readonly mintsBemSucedidos: string[] = [];

  constructor(linhas: LinhaOutbox[]) {
    for (const l of linhas) this.linhas.set(l.id, { ...l });
  }

  /** Reproduz a decisão de posse das RPCs svc_mint_*. */
  cunhar(id: string, categoria: "application" | "manager_invite"): MintOutcome {
    const linha = this.linhas.get(id);
    if (!linha) return { ok: false, reason: "not_dispatchable" };
    if (linha.status === "sending") return { ok: false, reason: "lease_held" };
    if (linha.status !== "pending" && linha.status !== "scheduled") {
      return { ok: false, reason: "not_dispatchable" };
    }

    linha.status = "sending";
    linha.attempt_count += 1;
    this.mintsBemSucedidos.push(id);

    return {
      ok: true,
      token: `segredo-${categoria}-${id}-${linha.attempt_count}`,
      recipient: linha.recipient_address,
      purpose: categoria,
      attempt: linha.attempt_count,
      expires_in_seconds: 1800,
    };
  }

  marcarEnviado(id: string) {
    const l = this.linhas.get(id);
    if (l && l.status === "sending") l.status = "sent";
  }
  marcarFalha(id: string) {
    const l = this.linhas.get(id);
    if (l && l.status === "sending") l.status = "failed";
  }
}

function criarGateway(db: OutboxFalso): CanonicalOutboxGateway {
  return {
    async listPending(_channel: string, limit: number): Promise<PendingNotification[]> {
      return [...db.linhas.values()]
        .filter(
          (l) =>
            (l.status === "pending" || l.status === "scheduled") &&
            R16_SUPPORTED_TEMPLATE_KEYS.includes(l.template_key)
        )
        .slice(0, limit)
        .map((l) => ({
          id: l.id,
          channel: "email",
          template_key: l.template_key,
          template_data: l.template_data,
          recipient_address: l.recipient_address,
          idempotency_key: l.idempotency_key,
        }));
    },
    async mintApplicationToken(id) {
      return db.cunhar(id, "application");
    },
    async mintManagerInviteToken(id) {
      return db.cunhar(id, "manager_invite");
    },
    async markSent(id) {
      db.marcarEnviado(id);
    },
    async markFailed(id) {
      db.marcarFalha(id);
    },
    async reschedule() {
      /* sem efeito neste teste */
    },
  };
}

function linha(over: Partial<LinhaOutbox> = {}): LinhaOutbox {
  return {
    id: over.id ?? "evt-1",
    template_key: over.template_key ?? "partner_application_email_verification",
    status: over.status ?? "pending",
    attempt_count: over.attempt_count ?? 0,
    recipient_address: over.recipient_address ?? "destino@teste.com.br",
    idempotency_key: over.idempotency_key ?? "idem-1",
    template_data: over.template_data ?? { application_id: "app-1" },
  };
}

describe("R16 — allowlist canônica", () => {
  it("expõe exatamente os três templates com posse atômica", () => {
    expect([...R16_SUPPORTED_TEMPLATE_KEYS].sort()).toEqual([
      "manager_invite",
      "partner_application_account_claim",
      "partner_application_email_verification",
    ]);
  });

  it("cada template suportado tem categoria de cunhagem", () => {
    for (const k of R16_SUPPORTED_TEMPLATE_KEYS) {
      expect(mintCategoryFor(k)).not.toBeNull();
      expect(["application", "manager_invite"]).toContain(R16_SUPPORTED_TEMPLATES[k]);
    }
  });

  it("template fora do conjunto não tem caminho de posse", () => {
    expect(isSupportedTemplate("partner_application_decided")).toBe(false);
    expect(mintCategoryFor("partner_application_decided")).toBeNull();
  });

  it("a allowlist é imutável", () => {
    expect(() => {
      (R16_SUPPORTED_TEMPLATES as Record<string, string>).qualquer = "application";
    }).toThrow();
  });
});

describe("R16_OUTBOX_TWO_WORKER_DUPLICATE_PROTECTION", () => {
  for (const template of R16_SUPPORTED_TEMPLATE_KEYS) {
    it(`somente um worker envia: ${template}`, async () => {
      const db = new OutboxFalso([linha({ id: "evt-x", template_key: template })]);
      const gateway = criarGateway(db);
      const a = new FakeLocalTransport();
      const b = new FakeLocalTransport();

      const [ra, rb] = await Promise.all([
        dispatchPending(gateway, a),
        dispatchPending(gateway, b),
      ]);

      expect(a.sent.length + b.sent.length).toBe(1);
      expect(db.mintsBemSucedidos).toEqual(["evt-x"]);
      expect(ra.sent + rb.sent).toBe(1);
      expect(ra.skipped + rb.skipped).toBe(1);
      expect(db.linhas.get("evt-x")!.status).toBe("sent");
      expect(db.linhas.get("evt-x")!.attempt_count).toBe(1);
    });
  }

  it("dez workers concorrentes produzem exatamente um envio", async () => {
    const db = new OutboxFalso([linha({ id: "evt-w" })]);
    const gateway = criarGateway(db);
    const ts = Array.from({ length: 10 }, () => new FakeLocalTransport());
    await Promise.all(ts.map((t) => dispatchPending(gateway, t)));
    expect(ts.reduce((n, t) => n + t.sent.length, 0)).toBe(1);
    expect(db.mintsBemSucedidos).toHaveLength(1);
  });

  it("evento já enviado não é retransmitido", async () => {
    const db = new OutboxFalso([linha({ id: "evt-z", status: "sent" })]);
    const t = new FakeLocalTransport();
    const r = await dispatchPending(criarGateway(db), t);
    expect(r.processed).toBe(0);
    expect(t.sent).toHaveLength(0);
  });
});

describe("R16_UNSUPPORTED_TEMPLATE_POLICY — fail closed", () => {
  it("template não suportado não é descoberto pela consulta", async () => {
    const db = new OutboxFalso([
      linha({ id: "evt-nao", template_key: "partner_application_decided" }),
    ]);
    const t = new FakeLocalTransport();
    const r = await dispatchPending(criarGateway(db), t);
    expect(r.processed).toBe(0);
    expect(t.sent).toHaveLength(0);
    expect(db.linhas.get("evt-nao")!.status).toBe("pending");
  });

  it("se escapar da consulta, o despacho recusa sem enviar nem mutar", async () => {
    const db = new OutboxFalso([
      linha({ id: "evt-fuga", template_key: "partner_application_decided" }),
    ]);
    // Consulta DEFEITUOSA de propósito, para exercitar a segunda barreira.
    const furado: CanonicalOutboxGateway = {
      ...criarGateway(db),
      async listPending() {
        const l = db.linhas.get("evt-fuga")!;
        return [
          {
            id: l.id,
            channel: "email",
            template_key: l.template_key,
            template_data: l.template_data,
            recipient_address: l.recipient_address,
            idempotency_key: l.idempotency_key,
          },
        ];
      },
    };
    const t = new FakeLocalTransport();
    const motivos: string[] = [];
    const r = await dispatchPending(furado, t, {
      onDiagnostic: (e) => motivos.push(e.reason),
    });

    expect(r).toEqual({ processed: 1, sent: 0, failed: 0, skipped: 0, unsupported: 1 });
    expect(t.sent).toHaveLength(0);
    expect(db.mintsBemSucedidos).toEqual([]);
    expect(db.linhas.get("evt-fuga")!.status).toBe("pending");
    expect(db.linhas.get("evt-fuga")!.attempt_count).toBe(0);
    expect(motivos).toEqual(["unsupported_template_no_atomic_claim"]);
  });

  it("o diagnóstico não carrega dados do template nem endereço", async () => {
    const db = new OutboxFalso([
      linha({
        id: "evt-diag",
        template_key: "partner_application_decided",
        template_data: { segredo_falso: "NAO-DEVE-APARECER" },
        recipient_address: "vitima@exemplo.com",
      }),
    ]);
    const furado: CanonicalOutboxGateway = {
      ...criarGateway(db),
      async listPending() {
        const l = db.linhas.get("evt-diag")!;
        return [
          {
            id: l.id,
            channel: "email",
            template_key: l.template_key,
            template_data: l.template_data,
            recipient_address: l.recipient_address,
            idempotency_key: l.idempotency_key,
          },
        ];
      },
    };
    const capturado: unknown[] = [];
    await dispatchPending(furado, new FakeLocalTransport(), {
      onDiagnostic: (e) => capturado.push(e),
    });
    const texto = JSON.stringify(capturado);
    expect(texto).not.toContain("NAO-DEVE-APARECER");
    expect(texto).not.toContain("vitima@exemplo.com");
    expect(texto).toContain("evt-diag");
  });
});

describe("R16 — posse é pré-condição do envio", () => {
  it("recusa de posse impede a transmissão", async () => {
    const db = new OutboxFalso([linha({ id: "evt-lh", status: "sending" })]);
    const furado: CanonicalOutboxGateway = {
      ...criarGateway(db),
      async listPending() {
        const l = db.linhas.get("evt-lh")!;
        return [
          {
            id: l.id,
            channel: "email",
            template_key: l.template_key,
            template_data: l.template_data,
            recipient_address: l.recipient_address,
            idempotency_key: l.idempotency_key,
          },
        ];
      },
    };
    const t = new FakeLocalTransport();
    const motivos: string[] = [];
    const r = await dispatchPending(furado, t, {
      onDiagnostic: (e) => motivos.push(e.reason),
    });
    expect(r.skipped).toBe(1);
    expect(t.sent).toHaveLength(0);
    expect(motivos).toContain("lease_held");
    expect(db.mintsBemSucedidos).toEqual([]);
  });

  it("o segredo cunhado entra na mensagem e não na fila", async () => {
    const db = new OutboxFalso([linha({ id: "evt-seg" })]);
    const t = new FakeLocalTransport();
    await dispatchPending(criarGateway(db), t);
    expect(t.sent[0].data.token).toBe("segredo-application-evt-seg-1");
    expect(JSON.stringify(db.linhas.get("evt-seg"))).not.toContain("segredo-application");
  });
});
