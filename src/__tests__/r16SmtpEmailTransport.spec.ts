// @vitest-environment node
import { describe, it, expect } from "vitest";
import {
  criarTransporteSmtp,
  derivarClientName,
  identificadorDeEntrega,
  etiquetaDeErro,
  NOME_TRANSPORTE_SMTP,
} from "../server/worker/smtpEmailTransport";
import { carregarWorkerConfig, type WorkerConfig } from "../server/worker/workerConfig";
import type { FabricaSocket, SocketSmtp } from "../server/worker/nodeSmtpSocket";
import { SmtpSocketError } from "../server/worker/nodeSmtpSocket";

/**
 * R16 — CP4: ADAPTADOR ENTRE O DESPACHANTE E O SMTP.
 *
 * Três coisas são provadas aqui e em nenhum outro lugar: a política de
 * destinatário aplicada ANTES do envelope, a renderização restrita ao escopo
 * suportado, e a tradução de desfecho preservando a distinção entre recusa
 * do servidor e falha de transporte.
 */

const SENHA_FIXTURE = "fixture-sem-valor-real";
/**
 * Chave de FIXTURE para service_role. Em constante nomeada, e não como
 * literal adjacente a `SUPABASE_SERVICE_ROLE_KEY:` — esse é exatamente o
 * padrão que a varredura de segredos deve continuar acusando em qualquer
 * arquivo versionado.
 */
const CHAVE_FIXTURE = "chave-de-fixture-inerte-nao-e-credencial";
const TOKEN = "t".repeat(64);

const ENV_BASE: Record<string, string> = {
  ENVIRONMENT: "production",
  SUPABASE_URL: "https://projref.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: CHAVE_FIXTURE,
  SITE_BASE_URL: "https://bdflow.com.br",
  SMTP_MODE: "implicit_tls",
  SMTP_HOST: "smtp.exemplo.com",
  SMTP_PORT: "465",
  SMTP_USERNAME: "apikey",
  SMTP_PASSWORD: SENHA_FIXTURE,
  SMTP_FROM_ADDRESS: "nao-responda@bdflow.com.br",
  SMTP_FROM_NAME: "BDFlow",
  WORKER_BATCH_SIZE: "10",
  WORKER_RECOVERY_RESERVE: "1",
};

const config = (extra: Record<string, string> = {}): WorkerConfig =>
  carregarWorkerConfig({ ...ENV_BASE, ...extra });

type Ouvinte = (...args: never[]) => void;

/** Socket roteirizado, igual ao usado nas provas de protocolo. */
class SocketFalso implements SocketSmtp {
  readonly escritas: string[] = [];
  readonly ouvintes: Record<string, Ouvinte[]> = {};
  constructor(readonly seguro: boolean) {}
  on(evento: string, fn: Ouvinte): void {
    (this.ouvintes[evento] ??= []).push(fn);
  }
  write(dados: string): boolean {
    this.escritas.push(dados);
    return true;
  }
  end(): void {}
  destroy(): void {}
  emitir(evento: string, arg?: unknown): void {
    for (const fn of this.ouvintes[evento] ?? []) (fn as (a?: unknown) => void)(arg);
  }
}

const SEQUENCIA_OK = [
  "220 smtp.exemplo.com ESMTP\r\n",
  "250-smtp.exemplo.com\r\n250 AUTH PLAIN\r\n",
  "235 2.7.0 autenticado\r\n",
  "250 2.1.0 ok\r\n",
  "250 2.1.5 ok\r\n",
  "354 manda\r\n",
  "250 2.0.0 Ok: queued as 4F2AB1\r\n",
  "221 tchau\r\n",
];

function fabricaRoteirizada(roteiro: string[]) {
  const escritas: string[] = [];
  let socket: SocketFalso | null = null;
  const fila = [...roteiro];
  const fabrica: FabricaSocket = {
    async conectar(o) {
      const s = new SocketFalso(o.seguro);
      socket = s;
      const original = s.write.bind(s);
      s.write = (dados: string) => {
        escritas.push(dados);
        const coube = original(dados);
        const proxima = fila.shift();
        if (proxima !== undefined) setImmediate(() => s.emitir("data", proxima));
        return coube;
      };
      const saudacao = fila.shift();
      if (saudacao !== undefined) setImmediate(() => s.emitir("data", saudacao));
      return s;
    },
  };
  return { fabrica, escritas, socket: () => socket };
}

const mensagem = (extra: Partial<{ to: string; templateKey: string }> = {}) => ({
  to: "socio@empresa.com.br",
  templateKey: "manager_invite",
  data: { token: TOKEN, company_name: "Mercado X LTDA" },
  idempotencyKey: "idem-abc-123",
  ...extra,
});

describe("R16 — derivação do EHLO e identificador de entrega", () => {
  it("o nome anunciado vem do domínio do remetente", () => {
    expect(derivarClientName("nao-responda@bdflow.com.br")).toBe("bdflow.com.br");
  });

  it("remetente sem domínio utilizável falha em vez de inventar nome", () => {
    expect(() => derivarClientName("semarroba")).toThrow();
    expect(() => derivarClientName("a@")).toThrow();
    expect(() => derivarClientName("a@dom inio")).toThrow();
  });

  it("o identificador preserva o texto do 250 sanitizado", () => {
    expect(identificadorDeEntrega("2.0.0 Ok: queued as 4F2AB1", "idem-1")).toBe(
      "smtp:2.0.0 Ok: queued as 4F2AB1"
    );
  });

  it("texto ausente cai para a chave de idempotência", () => {
    expect(identificadorDeEntrega(undefined, "idem-1")).toBe("smtp:idem-1");
    expect(identificadorDeEntrega("   ", "idem-1")).toBe("smtp:idem-1");
  });

  it("controle e não-imprimível não chegam ao banco", () => {
    const id = identificadorDeEntrega("Ok\u0000\u0007 queued\u001b[31m", "idem-1");
    expect(id).not.toMatch(/[\x00-\x1F\x7F]/);
  });

  it("o identificador é limitado em tamanho", () => {
    const id = identificadorDeEntrega("x".repeat(5_000), "idem-1");
    expect(id.length).toBeLessThanOrEqual(190);
  });

  it("a etiqueta de erro distingue recusa de falha de transporte", () => {
    expect(etiquetaDeErro({ estado: "enviado", codigo: 250 })).toBe("ok");
    expect(etiquetaDeErro({ estado: "recusa_temporaria", codigo: 451, fase: "rcpt_to" })).toBe(
      "smtp_temporario_451_rcpt_to"
    );
    expect(etiquetaDeErro({ estado: "recusa_permanente", codigo: 550, fase: "rcpt_to" })).toBe(
      "smtp_permanente_550_rcpt_to"
    );
    expect(
      etiquetaDeErro({ estado: "falha_transporte", codigo: "tls_certificate_error", fase: "connect" })
    ).toBe("smtp_transporte_tls_certificate_error_connect");
  });
});

describe("R16 — envio bem-sucedido pelo adaptador", () => {
  it("transmite e devolve identificador rastreável", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    const r = await t.send(mensagem());

    expect(r.ok).toBe(true);
    expect(r).toMatchObject({ provider: NOME_TRANSPORTE_SMTP });
    if (r.ok) expect(r.providerMessageId).toContain("queued as 4F2AB1");

    // Envelope correto e nome do EHLO derivado do remetente.
    expect(escritas[0]).toBe("EHLO bdflow.com.br\r\n");
    expect(escritas).toContain("MAIL FROM:<nao-responda@bdflow.com.br>\r\n");
    expect(escritas).toContain("RCPT TO:<socio@empresa.com.br>\r\n");
  });

  it("o token cunhado entra no CORPO e o From usa o nome amigável", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    await t.send(mensagem());
    const payload = escritas.find((e) => e.includes("\r\n.\r\n")) ?? "";
    expect(payload).toContain(TOKEN);
    expect(payload).toContain("From: BDFlow <nao-responda@bdflow.com.br>");
    expect(payload).toContain("https://bdflow.com.br/parceiros/convite?");
  });

  it("o desfecho é observado com etiqueta e classificação de retentativa", async () => {
    const observados: Array<{ outcome: string; retry: string; error_code: string }> = [];
    const { fabrica } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({
      config: config(),
      fabrica,
      aoDesfecho: (i) => observados.push(i),
    });
    await t.send(mensagem());
    expect(observados).toEqual([{ outcome: "enviado", retry: "ok", error_code: "ok" }]);
  });

  it("serializar o transporte não expõe configuração nem senha", async () => {
    const t = criarTransporteSmtp({ config: config(), fabrica: fabricaRoteirizada([]).fabrica });
    const serializado = JSON.stringify(t);
    expect(serializado).toBe('{"name":"smtp"}');
    expect(serializado).not.toContain(SENHA_FIXTURE);
    expect(serializado).not.toContain("smtp.exemplo.com");
  });
});

describe("R16_STAGING_RECIPIENT_SAFETY — aplicada ANTES do envelope", () => {
  const ENV_STAGING = {
    ENVIRONMENT: "staging",
    STAGING_RECIPIENT_ALLOWLIST: "qa@bdflow.com.br",
  };

  it("destinatário fora da allowlist: ZERO transmissão", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(ENV_STAGING), fabrica });
    const r = await t.send(mensagem({ to: "cliente-real@empresa.com.br" }));

    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errorCode).toBe("recipient_not_in_staging_allowlist");
    // Nenhum byte foi para a rede — nem sequer o EHLO.
    expect(escritas).toEqual([]);
  });

  it("destinatário na allowlist é transmitido normalmente", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(ENV_STAGING), fabrica });
    const r = await t.send(mensagem({ to: "qa@bdflow.com.br" }));
    expect(r.ok).toBe(true);
    expect(escritas).toContain("RCPT TO:<qa@bdflow.com.br>\r\n");
  });

  it("override redireciona: o destinatário original NUNCA vira envelope", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({
      config: config({
        ENVIRONMENT: "staging",
        STAGING_RECIPIENT_OVERRIDE: "caixa-de-staging@bdflow.com.br",
      }),
      fabrica,
    });
    const r = await t.send(mensagem({ to: "cliente-real@empresa.com.br" }));

    expect(r.ok).toBe(true);
    expect(escritas).toContain("RCPT TO:<caixa-de-staging@bdflow.com.br>\r\n");
    expect(escritas.join("")).not.toContain("cliente-real@empresa.com.br");
  });

  it("em produção sem política, o destinatário real é usado", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    await t.send(mensagem({ to: "socio@empresa.com.br" }));
    expect(escritas).toContain("RCPT TO:<socio@empresa.com.br>\r\n");
  });
});

describe("R16 — renderização falha fechada no adaptador", () => {
  it("template fora do escopo não abre conexão", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    const r = await t.send(mensagem({ templateKey: "template_fora_do_escopo" }));

    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errorCode).toBe("render_unsupported_template");
    expect(escritas).toEqual([]);
  });

  it("campo obrigatório ausente não abre conexão", async () => {
    const { fabrica, escritas } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    const r = await t.send({
      to: "socio@empresa.com.br",
      templateKey: "manager_invite",
      data: { token: TOKEN }, // sem company_name
      idempotencyKey: "idem-1",
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errorCode).toBe("render_missing_template_field");
    expect(escritas).toEqual([]);
  });

  it("erro de renderização não devolve mensagem crua nem o token", async () => {
    const { fabrica } = fabricaRoteirizada(SEQUENCIA_OK);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    const r = await t.send(mensagem({ templateKey: "fora" }));
    expect(JSON.stringify(r)).not.toContain(TOKEN);
  });
});

describe("R16 — tradução de desfecho de falha", () => {
  it("recusa 5xx do servidor é etiquetada como permanente", async () => {
    const { fabrica } = fabricaRoteirizada([
      "220 ok\r\n",
      "250-x\r\n250 AUTH PLAIN\r\n",
      "235 ok\r\n",
      "250 ok\r\n",
      "550 caixa inexistente\r\n",
    ]);
    const observados: Array<{ retry: string }> = [];
    const t = criarTransporteSmtp({
      config: config(),
      fabrica,
      aoDesfecho: (i) => observados.push(i),
    });
    const r = await t.send(mensagem());
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.errorCode).toBe("smtp_permanente_550_rcpt_to");
      expect(r.errorMessage).toBe("servidor SMTP recusou a mensagem");
    }
    expect(observados[0].retry).toBe("permanente");
  });

  it("recusa 4xx é etiquetada como temporária", async () => {
    const { fabrica } = fabricaRoteirizada([
      "220 ok\r\n",
      "250-x\r\n250 AUTH PLAIN\r\n",
      "235 ok\r\n",
      "250 ok\r\n",
      "451 tente depois\r\n",
    ]);
    const t = criarTransporteSmtp({ config: config(), fabrica });
    const r = await t.send(mensagem());
    if (!r.ok) expect(r.errorCode).toBe("smtp_temporario_451_rcpt_to");
  });

  it("falha de TLS NÃO é etiquetada como recusa do servidor", async () => {
    const fabrica: FabricaSocket = {
      async conectar() {
        throw new SmtpSocketError("tls_certificate_error", "cert inválido");
      },
    };
    const t = criarTransporteSmtp({ config: config(), fabrica });
    const r = await t.send(mensagem());
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.errorCode).toBe("smtp_transporte_tls_certificate_error_connect");
      expect(r.errorCode).not.toMatch(/permanente|temporario/);
      expect(r.errorMessage).toBe("falha de transporte SMTP");
    }
  });

  it("nenhuma etiqueta de erro carrega senha, destinatário ou token", async () => {
    const roteiros = [
      ["220 ok\r\n", "250-x\r\n250 AUTH PLAIN\r\n", "535 credencial invalida\r\n"],
      ["220 ok\r\n", "lixo\r\n"],
    ];
    for (const roteiro of roteiros) {
      const { fabrica } = fabricaRoteirizada(roteiro);
      const t = criarTransporteSmtp({ config: config(), fabrica });
      const r = await t.send(mensagem());
      const s = JSON.stringify(r);
      expect(s).not.toContain(SENHA_FIXTURE);
      expect(s).not.toContain(TOKEN);
      expect(s).not.toContain("socio@empresa.com.br");
    }
  });
});
