import { describe, it, expect, vi } from "vitest";
import {
  inspectEmailConfig,
  createEmailTransport,
  FakeLocalTransport,
  HttpApiTransport,
  sanitizeForLog,
  EMAIL_ENV_VARS,
} from "../server/notifications/emailProvider";
import {
  dispatchPending,
  retryDelayMinutes,
  type CanonicalOutboxGateway,
  type PendingNotification,
  type MintOutcome,
} from "../server/notifications/dispatchOutbox";

/**
 * R13 — adaptador de provedor e worker sobre a semântica canônica do M1.
 * Nenhum segredo pode escapar; o worker não redesenha a máquina de estados.
 */
const SEGREDO = "a".repeat(64);
const CHAVE = "chave-secreta-do-provedor-123456";
const envCompleto = {
  BDFLOW_EMAIL_PROVIDER: "provedor-x",
  BDFLOW_EMAIL_API_KEY: CHAVE,
  BDFLOW_EMAIL_FROM: "nao-responda@bdflow.exemplo",
  BDFLOW_EMAIL_API_BASE_URL: "https://api.exemplo/v1",
};

describe("R13 — configuração em tempo de execução", () => {
  it("ambiente vazio usa transporte fake rotulado", () => {
    const s = inspectEmailConfig({});
    expect(s.configured).toBe(false);
    expect(s.transportName).toBe("fake-local");
    expect(createEmailTransport({})).toBeInstanceOf(FakeLocalTransport);
  });
  it("relata apenas NOMES de variáveis ausentes", () => {
    const s = inspectEmailConfig({ BDFLOW_EMAIL_API_KEY: CHAVE });
    expect(s.missing).toEqual(EMAIL_ENV_VARS.filter((k) => k !== "BDFLOW_EMAIL_API_KEY"));
    expect(JSON.stringify(s)).not.toContain(CHAVE);
  });
  it("ambiente completo cria transporte HTTP", () => {
    expect(createEmailTransport(envCompleto)).toBeInstanceOf(HttpApiTransport);
  });
  it("a chave NAO aparece em JSON.stringify do transporte", () => {
    // Campos privados reais de JS (#) — 'private' do TypeScript some na
    // compilação e deixaria a chave visível aqui.
    expect(JSON.stringify(createEmailTransport(envCompleto))).not.toContain(CHAVE);
  });
  it("erro HTTP nao ecoa corpo da resposta", async () => {
    const fakeFetch = (async () =>
      ({
        ok: false,
        status: 500,
        json: async () => ({ detail: `vazou ${CHAVE}` }),
      }) as unknown as Response) as unknown as typeof fetch;
    const r = await createEmailTransport(envCompleto, fakeFetch).send({
      to: "x@y.z",
      templateKey: "t",
      data: {},
      idempotencyKey: "i1",
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errorMessage).not.toContain(CHAVE);
  });
});

function criarGateway(
  pendentes: PendingNotification[],
  mint: MintOutcome = {
    ok: true,
    token: SEGREDO,
    recipient: "x@y.z",
    purpose: "email_verification",
    attempt: 1,
    expires_in_seconds: 86400,
  }
) {
  const chamadas: Array<Record<string, unknown>> = [];
  const gateway: CanonicalOutboxGateway = {
    listPending: async () => pendentes,
    mintApplicationToken: async (id) => {
      chamadas.push({ op: "mintApplication", id });
      return mint;
    },
    mintManagerInviteToken: async (id) => {
      chamadas.push({ op: "mintManagerInvite", id });
      return mint;
    },
    markSent: async (id, provider, msg) =>
      void chamadas.push({ op: "sent", id, provider, msg }),
    markFailed: async (id, code, message) =>
      void chamadas.push({ op: "failed", id, code, message }),
    reschedule: async (id, delay) =>
      void chamadas.push({ op: "reschedule", id, delay }),
  };
  return { gateway, chamadas };
}

const evento = (over?: Partial<PendingNotification>): PendingNotification => ({
  id: "ev-1",
  channel: "email",
  template_key: "partner_application_email_verification",
  template_data: { application_id: "a1" },
  recipient_address: "titular@teste.local",
  idempotency_key: "pav:a1",
  ...over,
});

describe("R13 — worker usa as operações canônicas do M1", () => {
  it("onboarding cunha pela svc de candidatura", async () => {
    const { gateway, chamadas } = criarGateway([evento()]);
    const t = new FakeLocalTransport();
    const r = await dispatchPending(gateway, t);
    expect(r).toEqual({ processed: 1, sent: 1, failed: 0, skipped: 0 });
    expect(chamadas[0]).toMatchObject({ op: "mintApplication" });
    expect(t.sent[0].data.token).toBe(SEGREDO);
  });

  it("convite de manager cunha pela svc PRÓPRIA do convite", async () => {
    const { gateway, chamadas } = criarGateway([
      evento({ template_key: "manager_invite", template_data: { invite_id: "i1" } }),
    ]);
    await dispatchPending(gateway, new FakeLocalTransport());
    expect(chamadas[0]).toMatchObject({ op: "mintManagerInvite" });
  });

  it("template sem segredo NAO cunha nem injeta token", async () => {
    const { gateway, chamadas } = criarGateway([
      evento({ template_key: "partner_application_decided" }),
    ]);
    const t = new FakeLocalTransport();
    await dispatchPending(gateway, t);
    expect(chamadas.some((c) => String(c.op).startsWith("mint"))).toBe(false);
    expect(t.sent[0].data).not.toHaveProperty("token");
  });

  it("recusa canônica da cunhagem é respeitada, sem insistir", async () => {
    for (const motivo of [
      "lease_held",
      "not_due_yet",
      "stale_for_state",
      "max_attempts",
      "not_dispatchable",
    ]) {
      const { gateway, chamadas } = criarGateway([evento()], {
        ok: false,
        reason: motivo,
      });
      const r = await dispatchPending(gateway, new FakeLocalTransport());
      expect(r.skipped).toBe(1);
      expect(r.sent).toBe(0);
      // O worker não marca nada: quem decide o estado é o M1.
      expect(chamadas.filter((c) => c.op !== "mintApplication")).toHaveLength(0);
    }
  });
});

describe("R13 — segredo nunca escapa", () => {
  it("o segredo NAO vai para a coluna de erro", async () => {
    const { gateway, chamadas } = criarGateway([evento()]);
    const t = new FakeLocalTransport();
    t.failOnce("smtp_error", `falha ao enviar com token ${SEGREDO}`);
    await dispatchPending(gateway, t);
    const falha = chamadas.find((c) => c.op === "failed")!;
    expect(String(falha.message)).not.toContain(SEGREDO);
    expect(String(falha.message)).toContain("[REDIGIDO]");
  });

  it("falha reagenda pela transição canônica, com espera exponencial", async () => {
    const { gateway, chamadas } = criarGateway([evento()], {
      ok: true,
      token: SEGREDO,
      recipient: "x@y.z",
      purpose: "email_verification",
      attempt: 3,
      expires_in_seconds: 86400,
    });
    const t = new FakeLocalTransport();
    t.failOnce("timeout", "tempo esgotado");
    await dispatchPending(gateway, t);
    expect(chamadas.find((c) => c.op === "reschedule")).toMatchObject({ delay: 4 });
  });

  it("espera exponencial limitada a 60 minutos", () => {
    expect(retryDelayMinutes(1)).toBe(1);
    expect(retryDelayMinutes(3)).toBe(4);
    expect(retryDelayMinutes(10)).toBe(60);
  });

  it("sanitização ignora valores curtos e limita tamanho", () => {
    expect(sanitizeForLog("erro abc", ["abc"])).toBe("erro abc");
    expect(sanitizeForLog("x".repeat(5000), []).length).toBe(2000);
  });
});
