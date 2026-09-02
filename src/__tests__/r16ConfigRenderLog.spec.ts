import { describe, it, expect, vi } from "vitest";
import {
  carregarWorkerConfig,
  validarSiteBaseUrl,
  resolverPoliticaDestinatario,
  aplicarPoliticaDestinatario,
  rejeitarSegredosPublicos,
  WorkerConfigError,
} from "../server/worker/workerConfig";
import {
  renderizar,
  montarLink,
  escaparHtml,
  montarMensagemSmtp,
  RenderError,
} from "../server/worker/emailRenderer";
import { criarWorkerLogger } from "../server/worker/workerLogger";

const SENHA = "senha-smtp-super-secreta";
const SERVICE_KEY = "serviceroleabcdefghijklmnopqrstuvwxyz0123456789";
const TOKEN = "a".repeat(64);

const ENV_BASE: Record<string, string> = {
  ENVIRONMENT: "production",
  SUPABASE_URL: "https://projref.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY,
  SITE_BASE_URL: "https://bdflow.com.br",
  SMTP_MODE: "implicit_tls",
  SMTP_HOST: "smtp.exemplo.com",
  SMTP_PORT: "465",
  SMTP_USERNAME: "apikey",
  SMTP_PASSWORD: SENHA,
  SMTP_FROM_ADDRESS: "nao-responda@bdflow.com.br",
  WORKER_BATCH_SIZE: "10",
  WORKER_RECOVERY_RESERVE: "1",
};

describe("R16 — configuração: segredo sob prefixo público", () => {
  it("VITE_ com segredo é rejeitado", () => {
    expect(() => rejeitarSegredosPublicos({ VITE_SMTP_PASSWORD: SENHA })).toThrow(
      WorkerConfigError
    );
  });

  it("NEXT_PUBLIC_ com service role é rejeitado", () => {
    expect(() =>
      rejeitarSegredosPublicos({ NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY })
    ).toThrow(WorkerConfigError);
  });

  it("VITE_ sem segredo é aceito", () => {
    expect(() => rejeitarSegredosPublicos({ VITE_SUPABASE_ANON_KEY: "anon" })).not.toThrow();
  });

  it("o erro não contém o valor do segredo", () => {
    try {
      rejeitarSegredosPublicos({ VITE_SMTP_PASSWORD: SENHA });
    } catch (e) {
      expect((e as Error).message).not.toContain(SENHA);
      expect((e as WorkerConfigError).code).toBe("secret_under_public_prefix");
    }
  });
});

describe("R16 — configuração: base do Site", () => {
  it("https é aceito e normalizado sem barra final", () => {
    expect(validarSiteBaseUrl("https://bdflow.com.br/", "production")).toBe(
      "https://bdflow.com.br"
    );
  });

  it("http é rejeitado fora de desenvolvimento", () => {
    expect(() => validarSiteBaseUrl("http://bdflow.com.br", "production")).toThrow(
      WorkerConfigError
    );
    expect(() => validarSiteBaseUrl("http://bdflow.com.br", "staging")).toThrow(
      WorkerConfigError
    );
  });

  it("localhost é aceito apenas em desenvolvimento", () => {
    expect(validarSiteBaseUrl("http://localhost:5173", "development")).toContain("localhost");
    expect(() => validarSiteBaseUrl("http://localhost:5173", "staging")).toThrow(
      WorkerConfigError
    );
  });

  it("URL com credenciais embutidas é rejeitada", () => {
    expect(() => validarSiteBaseUrl("https://u:p@bdflow.com.br", "production")).toThrow(
      WorkerConfigError
    );
  });

  it("URL malformada é rejeitada", () => {
    expect(() => validarSiteBaseUrl("nao-e-url", "production")).toThrow(WorkerConfigError);
  });
});

describe("R16_STAGING_RECIPIENT_SAFETY", () => {
  it("staging SEM override e SEM allowlist FALHA na inicialização", () => {
    try {
      resolverPoliticaDestinatario({}, "staging");
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as WorkerConfigError).code).toBe("staging_recipient_safety_missing");
    }
  });

  it("staging com override redireciona TODO destinatário", () => {
    const p = resolverPoliticaDestinatario(
      { STAGING_RECIPIENT_OVERRIDE: "captura@sandbox.test" },
      "staging"
    );
    const r = aplicarPoliticaDestinatario("cliente.real@empresa.com.br", p);
    expect(r).toEqual({ enviar: true, destino: "captura@sandbox.test" });
  });

  it("o destinatário original NUNCA vira destino SMTP sob override", () => {
    const p = resolverPoliticaDestinatario(
      { STAGING_RECIPIENT_OVERRIDE: "captura@sandbox.test" },
      "staging"
    );
    for (const real of ["a@x.com", "b@y.com.br", "c@z.org"]) {
      const r = aplicarPoliticaDestinatario(real, p);
      expect(r.enviar && r.destino).toBe("captura@sandbox.test");
      expect(r.enviar && r.destino).not.toBe(real);
    }
  });

  it("allowlist permite o que está na lista", () => {
    const p = resolverPoliticaDestinatario(
      { STAGING_RECIPIENT_ALLOWLIST: "qa1@teste.com, qa2@teste.com" },
      "staging"
    );
    expect(aplicarPoliticaDestinatario("qa2@teste.com", p)).toEqual({
      enviar: true,
      destino: "qa2@teste.com",
    });
  });

  it("allowlist BLOQUEIA quem está fora — zero envio", () => {
    const p = resolverPoliticaDestinatario(
      { STAGING_RECIPIENT_ALLOWLIST: "qa1@teste.com" },
      "staging"
    );
    const r = aplicarPoliticaDestinatario("cliente.real@empresa.com.br", p);
    expect(r.enviar).toBe(false);
    expect(r.enviar === false && r.motivo).toBe("recipient_not_in_staging_allowlist");
  });

  it("override E allowlist juntos é ambiguidade rejeitada", () => {
    expect(() =>
      resolverPoliticaDestinatario(
        {
          STAGING_RECIPIENT_OVERRIDE: "a@b.com",
          STAGING_RECIPIENT_ALLOWLIST: "c@d.com",
        },
        "staging"
      )
    ).toThrow(WorkerConfigError);
  });

  it("produção NÃO herda override de staging — é erro de configuração", () => {
    try {
      resolverPoliticaDestinatario(
        { STAGING_RECIPIENT_OVERRIDE: "captura@sandbox.test" },
        "production"
      );
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as WorkerConfigError).code).toBe("staging_policy_in_production");
    }
  });

  it("produção sem política envia ao destinatário real", () => {
    const p = resolverPoliticaDestinatario({}, "production");
    expect(p).toBeUndefined();
    expect(aplicarPoliticaDestinatario("cliente@empresa.com", p)).toEqual({
      enviar: true,
      destino: "cliente@empresa.com",
    });
  });
});

describe("R16 — configuração: SMTP e lote", () => {
  it("configuração válida carrega", () => {
    const c = carregarWorkerConfig(ENV_BASE);
    expect(c.smtp.mode).toBe("implicit_tls");
    expect(c.batchSize).toBe(10);
    expect(c.recoveryReserve).toBe(1);
  });

  it("modo SMTP desconhecido é rejeitado, não convertido", () => {
    expect(() => carregarWorkerConfig({ ...ENV_BASE, SMTP_MODE: "tls_qualquer" })).toThrow(
      WorkerConfigError
    );
  });

  it("texto claro é proibido fora de desenvolvimento", () => {
    try {
      carregarWorkerConfig({ ...ENV_BASE, SMTP_MODE: "plaintext_local_only" });
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as WorkerConfigError).code).toBe("plaintext_smtp_forbidden");
    }
  });

  it("AUTH sobre texto claro é proibido", () => {
    try {
      carregarWorkerConfig({
        ...ENV_BASE,
        ENVIRONMENT: "development",
        SITE_BASE_URL: "http://localhost:5173",
        SUPABASE_URL: "http://localhost:54321",
        SMTP_MODE: "plaintext_local_only",
      });
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as WorkerConfigError).code).toBe("auth_over_plaintext_forbidden");
    }
  });

  it("credencial incompleta é rejeitada", () => {
    expect(() =>
      carregarWorkerConfig({ ...ENV_BASE, SMTP_PASSWORD: "" })
    ).toThrow(WorkerConfigError);
  });

  it("batchSize=1 é rejeitado", () => {
    try {
      carregarWorkerConfig({ ...ENV_BASE, WORKER_BATCH_SIZE: "1" });
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as WorkerConfigError).code).toBe("batch_size_below_minimum");
    }
  });

  it("recoveryReserve >= batchSize é rejeitado", () => {
    expect(() =>
      carregarWorkerConfig({ ...ENV_BASE, WORKER_RECOVERY_RESERVE: "10" })
    ).toThrow(WorkerConfigError);
  });

  it("nenhum erro de configuração vaza valor de segredo", () => {
    const casos = [
      { ...ENV_BASE, SMTP_MODE: "invalido" },
      { ...ENV_BASE, WORKER_BATCH_SIZE: "1" },
      { ...ENV_BASE, SITE_BASE_URL: "http://x.com" },
    ];
    for (const env of casos) {
      try {
        carregarWorkerConfig(env);
      } catch (e) {
        const m = (e as Error).message;
        expect(m).not.toContain(SENHA);
        expect(m).not.toContain(SERVICE_KEY);
      }
    }
  });
});

describe("R16_URL_ORIGIN_AUDIT", () => {
  const BASE = "https://bdflow.com.br";

  it("link usa a base configurada", () => {
    const l = montarLink(BASE, "confirmarEmail", { token: TOKEN });
    expect(l.startsWith("https://bdflow.com.br/parceiros/confirmar?")).toBe(true);
    expect(l).toContain(`token=${TOKEN}`);
  });

  it("URL absoluta hostil em template_data NÃO substitui a origem", () => {
    const m = renderizar(
      "partner_application_email_verification",
      {
        token: TOKEN,
        // Campos hostis que a renderização simplesmente não consome.
        site_base_url: "https://evil.example",
        link: "https://evil.example/roubar",
        origin: "https://evil.example",
      },
      BASE
    );
    expect(m.texto).toContain("https://bdflow.com.br/parceiros/confirmar");
    expect(m.texto).not.toContain("evil.example");
    expect(m.html).not.toContain("evil.example");
  });

  it("javascript: não pode virar link de ação", () => {
    const m = renderizar(
      "partner_application_email_verification",
      { token: TOKEN, link: "javascript:alert(1)" },
      BASE
    );
    expect(m.html).not.toContain("javascript:");
  });

  it("parâmetro é codificado corretamente", () => {
    const l = montarLink(BASE, "confirmarEmail", { token: "a b&c=d" });
    expect(l).toContain("token=a+b%26c%3Dd");
    expect(l.startsWith(BASE)).toBe(true);
  });
});

describe("R16 — renderização dos três templates", () => {
  const BASE = "https://bdflow.com.br";

  it("partner_application_email_verification renderiza", () => {
    const m = renderizar("partner_application_email_verification", { token: TOKEN }, BASE);
    expect(m.subject).toContain("Confirme");
    expect(m.texto).toContain("/parceiros/confirmar");
    expect(m.html).toContain("<a href=");
  });

  it("partner_application_account_claim renderiza com parâmetro claim", () => {
    const m = renderizar("partner_application_account_claim", { token: TOKEN }, BASE);
    expect(m.texto).toContain(`claim=${TOKEN}`);
  });

  it("manager_invite renderiza com nome da empresa", () => {
    const m = renderizar(
      "manager_invite",
      { token: TOKEN, company_name: "Super Teste LTDA" },
      BASE
    );
    expect(m.texto).toContain("Super Teste LTDA");
    expect(m.texto).toContain("/parceiros/convite");
  });

  it("template não suportado falha fechado", () => {
    expect(() =>
      renderizar("partner_application_decided", { token: TOKEN }, BASE)
    ).toThrow(RenderError);
  });

  it("campo obrigatório ausente falha fechado", () => {
    expect(() => renderizar("partner_application_email_verification", {}, BASE)).toThrow(
      RenderError
    );
  });

  it("template_data NÃO é serializado inteiro na mensagem", () => {
    const m = renderizar(
      "partner_application_email_verification",
      { token: TOKEN, cnpj: "12345678000195", interno_id: "segredo-interno" },
      BASE
    );
    expect(m.texto).not.toContain("12345678000195");
    expect(m.texto).not.toContain("segredo-interno");
    expect(m.html).not.toContain("segredo-interno");
  });

  it("HTML dinâmico é escapado", () => {
    expect(escaparHtml('<script>alert("x")</script>')).toBe(
      "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"
    );
    const m = renderizar(
      "manager_invite",
      { token: TOKEN, company_name: '<script>alert(1)</script>' },
      BASE
    );
    expect(m.html).not.toContain("<script>");
    expect(m.html).toContain("&lt;script&gt;");
  });

  it("campo com CR/LF é rejeitado antes de virar cabeçalho", () => {
    expect(() =>
      renderizar("manager_invite", { token: TOKEN, company_name: "X\r\nBcc: v@x.com" }, BASE)
    ).toThrow(RenderError);
  });

  it("mensagem SMTP completa é montada com terminador único", () => {
    const m = renderizar("partner_application_email_verification", { token: TOKEN }, BASE);
    const payload = montarMensagemSmtp(
      "destino@teste.com.br",
      "nao-responda@bdflow.com.br",
      "BDFlow",
      m
    );
    expect(payload.endsWith("\r\n.\r\n")).toBe(true);
    expect(payload).toContain("From: BDFlow <nao-responda@bdflow.com.br>");
  });
});

describe("R16_LOG_REDACTION_AUDIT", () => {
  it("apenas campos da allowlist são emitidos", () => {
    const linhas: string[] = [];
    const log = criarWorkerLogger((l) => linhas.push(l));
    log.info({
      event: "dispatch",
      notification_id: "evt-1",
      // Campos fora da allowlist devem ser DESCARTADOS.
      ...({ token: TOKEN, template_data: { a: 1 }, password: SENHA } as object),
    });
    const saida = linhas.join("");
    expect(saida).toContain("evt-1");
    expect(saida).not.toContain(TOKEN);
    expect(saida).not.toContain(SENHA);
    expect(saida).not.toContain("template_data");
  });

  it("segredo conhecido que escape para string é mascarado", () => {
    const linhas: string[] = [];
    const log = criarWorkerLogger((l) => linhas.push(l), [SENHA, SERVICE_KEY]);
    log.error({ event: "falha", error_code: `erro com ${SENHA} embutida` });
    const saida = linhas.join("");
    expect(saida).not.toContain(SENHA);
    expect(saida).toContain("[REDIGIDO]");
  });

  it("exceção não vira mensagem crua nem stack no log", () => {
    const log = criarWorkerLogger(() => {}, [SENHA]);
    const e = new Error(`falhou usando ${SENHA} no host interno`);
    const campos = log.erroSeguro(e);
    expect(JSON.stringify(campos)).not.toContain(SENHA);
    expect(JSON.stringify(campos)).not.toContain("host interno");
    expect(campos.error_code).toBe("Error");
  });

  it("erro com code usa o código, não a mensagem", () => {
    const log = criarWorkerLogger(() => {});
    expect(log.erroSeguro({ code: "smtp_timeout", message: SENHA })).toEqual({
      error_code: "smtp_timeout",
    });
  });

  it("destinatário NÃO é emitido em log, nem como impressão digital", () => {
    // A versão anterior emitia um hash de 32 bits com domínio em texto claro
    // e o chamava de "não reversível". Era falso. O campo foi removido.
    const linhas: string[] = [];
    const log = criarWorkerLogger((l) => linhas.push(l));
    log.info({
      event: "sent",
      notification_id: "evt-3",
      ...({ recipient_fingerprint: "abc@empresa.com.br",
            recipient_address: "cliente.real@empresa.com.br" } as object),
    });
    const saida = linhas.join("");
    expect(saida).not.toContain("empresa.com.br");
    expect(saida).not.toContain("cliente.real");
    expect(saida).not.toContain("recipient");
    expect(saida).toContain("evt-3");
  });

  it("nenhum log carrega corpo de e-mail", () => {
    const linhas: string[] = [];
    const log = criarWorkerLogger((l) => linhas.push(l));
    log.info({
      event: "sent",
      notification_id: "evt-2",
      ...({ body: "corpo completo do email", html: "<p>x</p>" } as object),
    });
    expect(linhas.join("")).not.toContain("corpo completo");
  });
});
