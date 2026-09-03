// @vitest-environment node
import { describe, it, expect, vi } from "vitest";
import {
  enviarMensagemSmtp,
  classificarParaRetry,
  codificarAuthPlain,
  anunciaAuthPlain,
  type OpcoesTransporte,
  type ResultadoTransporte,
} from "../server/worker/smtpTransport";
import {
  SmtpSocketError,
  type FabricaSocket,
  type OpcoesConexao,
  type SocketSmtp,
} from "../server/worker/nodeSmtpSocket";
import { criarWorkerLogger } from "../server/worker/workerLogger";
import { montarPayloadData } from "../server/worker/smtpWire";

/**
 * R16 — TRANSPORTE SMTP CONCRETO, PROVA DETERMINÍSTICA.
 *
 * Nenhum servidor SMTP externo. O socket é injetado, o que permite roteirizar
 * respostas, forçar backpressure, cortar a conexão e provar que credencial
 * jamais escapa — coisas que um servidor real não deixaria reproduzir de
 * forma estável.
 */

const SENHA = "senha-smtp-nao-pode-vazar-9876";
const USUARIO = "apikey";
const PAYLOAD = montarPayloadData(
  { from: "nao-responda@bdflow.com.br", to: "socio@empresa.com.br", subject: "Assunto" },
  "corpo de teste"
);

const OPCOES_BASE: OpcoesTransporte = {
  host: "smtp.exemplo.com",
  port: 465,
  mode: "implicit_tls",
  connectTimeoutMs: 1_000,
  readTimeoutMs: 1_000,
  clientName: "bdflow.com.br",
};

const ENVELOPE = { mailFrom: "nao-responda@bdflow.com.br", rcptTo: "socio@empresa.com.br" };

type Ouvinte = (...args: never[]) => void;

/** Socket determinístico: nada de rede, tudo observável. */
class SocketFalso implements SocketSmtp {
  readonly escritas: string[] = [];
  readonly ouvintes: Record<string, Ouvinte[]> = {};
  #seguro: boolean;
  #destruido = false;
  /** Quando >0, as próximas N escritas devolvem false (backpressure). */
  escritasComBackpressure = 0;

  constructor(seguro: boolean) {
    this.#seguro = seguro;
  }
  get seguro(): boolean {
    return this.#seguro;
  }
  get destruido(): boolean {
    return this.#destruido;
  }
  on(evento: string, fn: Ouvinte): void {
    (this.ouvintes[evento] ??= []).push(fn);
  }
  write(dados: string): boolean {
    this.escritas.push(dados);
    if (this.escritasComBackpressure > 0) {
      this.escritasComBackpressure -= 1;
      return false;
    }
    return true;
  }
  end(): void {}
  destroy(): void {
    this.#destruido = true;
  }

  emitir(evento: string, arg?: unknown): void {
    for (const fn of this.ouvintes[evento] ?? []) (fn as (a?: unknown) => void)(arg);
  }
  /** Entrega bytes do servidor no próximo tick, como um socket faria. */
  responder(texto: string): void {
    setImmediate(() => this.emitir("data", texto));
  }
  drenar(): void {
    setImmediate(() => this.emitir("drain"));
  }
}

/**
 * Servidor roteirizado: envia a saudação ao conectar e, a cada escrita do
 * cliente, devolve a próxima resposta do roteiro.
 */
function servidorRoteirizado(
  roteiro: string[],
  opcoes: { seguro?: boolean; comandos?: string[] } = {}
): { fabrica: FabricaSocket; socket: () => SocketFalso; conexoes: OpcoesConexao[] } {
  let criado: SocketFalso | null = null;
  const conexoes: OpcoesConexao[] = [];
  const fila = [...roteiro];

  const fabrica: FabricaSocket = {
    async conectar(o) {
      conexoes.push(o);
      const s = new SocketFalso(opcoes.seguro ?? o.seguro);
      criado = s;
      const original = s.write.bind(s);
      s.write = (dados: string) => {
        opcoes.comandos?.push(dados);
        const coube = original(dados);
        const proxima = fila.shift();
        if (proxima !== undefined) s.responder(proxima);
        if (!coube) s.drenar();
        return coube;
      };
      const saudacao = fila.shift();
      if (saudacao !== undefined) s.responder(saudacao);
      return s;
    },
  };
  return { fabrica, socket: () => criado as SocketFalso, conexoes };
}

const SEQUENCIA_OK = [
  "220 smtp.exemplo.com ESMTP\r\n",
  "250-smtp.exemplo.com\r\n250-PIPELINING\r\n250-AUTH PLAIN LOGIN\r\n250 SIZE 10485760\r\n",
  "235 2.7.0 autenticado\r\n",
  "250 2.1.0 remetente ok\r\n",
  "250 2.1.5 destinatario ok\r\n",
  "354 fim com <CRLF>.<CRLF>\r\n",
  "250 2.0.0 Ok: fila 4F2A\r\n",
  "221 2.0.0 tchau\r\n",
];

const comAuth = (o: Partial<OpcoesTransporte> = {}): OpcoesTransporte => ({
  ...OPCOES_BASE,
  username: USUARIO,
  password: SENHA,
  ...o,
});

describe("R16_SMTP_PROTOCOL_AUDIT — sequência completa", () => {
  it("conexão segura → 220 → EHLO → AUTH → MAIL → RCPT → DATA → 354 → payload → 2xx → QUIT", async () => {
    const comandos: string[] = [];
    const { fabrica, socket } = servidorRoteirizado(SEQUENCIA_OK, { comandos });

    const r = await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);

    expect(r).toEqual({ estado: "enviado", codigo: 250 });
    expect(comandos[0]).toBe("EHLO bdflow.com.br\r\n");
    expect(comandos[1]?.startsWith("AUTH PLAIN ")).toBe(true);
    expect(comandos[2]).toBe("MAIL FROM:<nao-responda@bdflow.com.br>\r\n");
    expect(comandos[3]).toBe("RCPT TO:<socio@empresa.com.br>\r\n");
    expect(comandos[4]).toBe("DATA\r\n");
    expect(comandos[5]).toBe(PAYLOAD);
    expect(comandos[6]).toBe("QUIT\r\n");
    expect(socket().destruido).toBe(true);
  });

  it("sem credencial configurada, AUTH é omitido explicitamente", async () => {
    const comandos: string[] = [];
    const roteiro = SEQUENCIA_OK.filter((l) => !l.startsWith("235"));
    const { fabrica } = servidorRoteirizado(roteiro, { comandos });

    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);

    expect(r.estado).toBe("enviado");
    expect(comandos.some((c) => c.startsWith("AUTH"))).toBe(false);
    expect(comandos[1]).toBe("MAIL FROM:<nao-responda@bdflow.com.br>\r\n");
  });

  it("a resposta multilinha do EHLO é consumida como UMA resposta", async () => {
    const comandos: string[] = [];
    const { fabrica } = servidorRoteirizado(SEQUENCIA_OK, { comandos });
    await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    // Se as linhas 250- tivessem sido tratadas como respostas separadas, o
    // AUTH teria consumido a resposta errada e a sequência quebraria.
    expect(comandos[1]?.startsWith("AUTH PLAIN ")).toBe(true);
  });

  it("saudação diferente de 220 é defeito de protocolo, não recusa", async () => {
    const { fabrica } = servidorRoteirizado(["200 estranho\r\n"]);
    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "unexpected_greeting",
      fase: "greeting",
    });
  });

  it("um 250 no lugar do 354 não é tratado como permissão para enviar o corpo", async () => {
    const comandos: string[] = [];
    const { fabrica } = servidorRoteirizado(
      [
        "220 ok\r\n",
        "250 ehlo\r\n",
        "250 mail\r\n",
        "250 rcpt\r\n",
        "250 nao-e-354\r\n",
      ],
      { comandos }
    );
    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "unexpected_reply_class",
      fase: "data",
    });
    expect(comandos).not.toContain(PAYLOAD);
  });
});

describe("R16_TLS_AUDIT — AUTH nunca antes do estado cifrado", () => {
  it("credencial em socket não seguro é recusada ANTES de qualquer escrita", async () => {
    const comandos: string[] = [];
    const { fabrica, socket } = servidorRoteirizado(SEQUENCIA_OK, {
      seguro: false,
      comandos,
    });

    const r = await enviarMensagemSmtp(
      comAuth({ mode: "plaintext_local_only" }),
      ENVELOPE,
      PAYLOAD,
      fabrica
    );

    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "auth_over_insecure_transport",
      fase: "auth",
    });
    expect(comandos).toHaveLength(0);
    expect(socket().destruido).toBe(true);
  });

  it("modo implicit_tls com socket que voltou inseguro também bloqueia AUTH", async () => {
    // Defesa contra fábrica defeituosa: a autoridade é o socket, não o modo.
    const { fabrica } = servidorRoteirizado(SEQUENCIA_OK, { seguro: false });
    const r = await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    expect((r as { codigo: string }).codigo).toBe("auth_over_insecure_transport");
  });

  it("sem credencial, o modo local em texto claro segue permitido", async () => {
    const roteiro = SEQUENCIA_OK.filter((l) => !l.startsWith("235"));
    const { fabrica } = servidorRoteirizado(roteiro, { seguro: false });
    const r = await enviarMensagemSmtp(
      { ...OPCOES_BASE, mode: "plaintext_local_only" },
      ENVELOPE,
      PAYLOAD,
      fabrica
    );
    expect(r.estado).toBe("enviado");
  });

  it("mecanismo PLAIN não anunciado ⇒ credencial não é enviada", async () => {
    const comandos: string[] = [];
    const { fabrica } = servidorRoteirizado(
      ["220 ok\r\n", "250-servidor\r\n250 AUTH LOGIN CRAM-MD5\r\n"],
      { comandos }
    );
    const r = await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "auth_mechanism_unavailable",
      fase: "auth",
    });
    expect(comandos.join("")).not.toContain(SENHA);
    expect(comandos.some((c) => c.startsWith("AUTH"))).toBe(false);
  });

  it("anunciaAuthPlain distingue anúncio real de anúncio de outro mecanismo", () => {
    expect(anunciaAuthPlain(["AUTH PLAIN LOGIN"])).toBe(true);
    expect(anunciaAuthPlain(["auth login plain"])).toBe(true);
    expect(anunciaAuthPlain(["AUTH LOGIN CRAM-MD5"])).toBe(false);
    expect(anunciaAuthPlain(["PIPELINING", "SIZE 100"])).toBe(false);
    // "AUTHPLAIN" não é anúncio de PLAIN.
    expect(anunciaAuthPlain(["AUTHPLAIN"])).toBe(false);
  });
});

describe("R16_SMTP_PROTOCOL_AUDIT — classificação de desfecho do servidor", () => {
  const casos: Array<[string, string[], "recusa_temporaria" | "recusa_permanente", number, string]> =
    [
      [
        "RCPT 4xx ⇒ temporário",
        ["220 ok\r\n", "250 ehlo\r\n", "250 mail\r\n", "451 tente depois\r\n"],
        "recusa_temporaria",
        451,
        "rcpt_to",
      ],
      [
        "RCPT 5xx ⇒ permanente",
        ["220 ok\r\n", "250 ehlo\r\n", "250 mail\r\n", "550 caixa inexistente\r\n"],
        "recusa_permanente",
        550,
        "rcpt_to",
      ],
      [
        "DATA final 4xx ⇒ temporário",
        [
          "220 ok\r\n",
          "250 ehlo\r\n",
          "250 mail\r\n",
          "250 rcpt\r\n",
          "354 manda\r\n",
          "452 sem espaco\r\n",
        ],
        "recusa_temporaria",
        452,
        "payload",
      ],
      [
        "DATA final 5xx ⇒ permanente",
        [
          "220 ok\r\n",
          "250 ehlo\r\n",
          "250 mail\r\n",
          "250 rcpt\r\n",
          "354 manda\r\n",
          "554 recusada\r\n",
        ],
        "recusa_permanente",
        554,
        "payload",
      ],
      [
        "MAIL FROM 5xx ⇒ permanente",
        ["220 ok\r\n", "250 ehlo\r\n", "553 remetente recusado\r\n"],
        "recusa_permanente",
        553,
        "mail_from",
      ],
      [
        "AUTH 5xx ⇒ permanente",
        ["220 ok\r\n", "250-x\r\n250 AUTH PLAIN\r\n", "535 credencial invalida\r\n"],
        "recusa_permanente",
        535,
        "auth",
      ],
    ];

  for (const [nome, roteiro, estado, codigo, fase] of casos) {
    it(nome, async () => {
      const { fabrica } = servidorRoteirizado(roteiro);
      const opcoes = fase === "auth" ? comAuth() : OPCOES_BASE;
      const r = await enviarMensagemSmtp(opcoes, ENVELOPE, PAYLOAD, fabrica);
      expect(r).toEqual({ estado, codigo, fase });
    });
  }

  it("retentativa segue a classe do servidor", () => {
    expect(classificarParaRetry({ estado: "enviado", codigo: 250 })).toBe("ok");
    expect(
      classificarParaRetry({ estado: "recusa_temporaria", codigo: 451, fase: "rcpt_to" })
    ).toBe("temporario");
    expect(
      classificarParaRetry({ estado: "recusa_permanente", codigo: 550, fase: "rcpt_to" })
    ).toBe("permanente");
  });
});

describe("R16_SMTP_PROTOCOL_AUDIT — falha de transporte não vira 4xx/5xx", () => {
  const naoEhRecusa = (r: ResultadoTransporte) => {
    expect(r.estado).toBe("falha_transporte");
    expect(r).not.toHaveProperty("codigo", expect.any(Number));
    expect(typeof (r as { codigo: unknown }).codigo).toBe("string");
  };

  it("conexão recusada", async () => {
    const fabrica: FabricaSocket = {
      async conectar() {
        throw new SmtpSocketError("connection_refused", "recusada");
      },
    };
    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    naoEhRecusa(r);
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "connection_refused",
      fase: "connect",
    });
  });

  it("erro de certificado", async () => {
    const fabrica: FabricaSocket = {
      async conectar() {
        throw Object.assign(new Error("x"), { code: "DEPTH_ZERO_SELF_SIGNED_CERT" });
      },
    };
    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "tls_certificate_error",
      fase: "connect",
    });
    expect(classificarParaRetry(r)).toBe("temporario");
  });

  it("timeout de leitura no meio da sequência", async () => {
    const { fabrica } = servidorRoteirizado(["220 ok\r\n"]); // nunca responde ao EHLO
    const r = await enviarMensagemSmtp(
      { ...OPCOES_BASE, readTimeoutMs: 40 },
      ENVELOPE,
      PAYLOAD,
      fabrica
    );
    expect(r).toEqual({ estado: "falha_transporte", codigo: "read_timeout", fase: "ehlo" });
  });

  it("fechamento inesperado no meio da sequência", async () => {
    const { fabrica, socket } = servidorRoteirizado(["220 ok\r\n"]);
    const p = enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    await new Promise((r) => setTimeout(r, 10));
    socket().emitir("close");
    const r = await p;
    expect(r).toEqual({ estado: "falha_transporte", codigo: "unexpected_eof", fase: "ehlo" });
  });

  it("resposta truncada no fechamento é erro de protocolo", async () => {
    const { fabrica, socket } = servidorRoteirizado(["220 ok\r\n"]);
    const p = enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    await new Promise((r) => setTimeout(r, 10));
    socket().emitir("data", "250-parcial sem fim"); // sem CRLF final
    socket().emitir("close");
    const r = await p;
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "response_truncated",
      fase: "ehlo",
    });
  });

  it("linha de status malformada é erro de protocolo, não 5xx", async () => {
    const { fabrica } = servidorRoteirizado(["220 ok\r\n", "isto nao e uma resposta\r\n"]);
    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "response_malformed",
      fase: "ehlo",
    });
  });

  it("erro de socket durante a espera", async () => {
    const { fabrica, socket } = servidorRoteirizado(["220 ok\r\n"]);
    const p = enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, PAYLOAD, fabrica);
    await new Promise((r) => setTimeout(r, 10));
    socket().emitir("error", Object.assign(new Error("x"), { code: "ECONNRESET" }));
    const r = await p;
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "connection_reset",
      fase: "ehlo",
    });
  });

  it("endereço de envelope com injeção falha ANTES de abrir socket", async () => {
    const conectar = vi.fn();
    const fabrica: FabricaSocket = { conectar };
    const r = await enviarMensagemSmtp(
      OPCOES_BASE,
      { mailFrom: "a@b.com\r\nRCPT TO:<vitima@x.com>", rcptTo: "socio@empresa.com.br" },
      PAYLOAD,
      fabrica
    );
    expect(r.estado).toBe("falha_transporte");
    expect((r as { codigo: string }).codigo).toBe("serialization_error");
    expect(conectar).not.toHaveBeenCalled();
    expect(classificarParaRetry(r)).toBe("permanente");
  });

  it("clientName com controle é recusado sem abrir socket", async () => {
    const conectar = vi.fn();
    const r = await enviarMensagemSmtp(
      { ...OPCOES_BASE, clientName: "bd\r\nMAIL FROM:<x@y>" },
      ENVELOPE,
      PAYLOAD,
      { conectar }
    );
    expect(r).toEqual({
      estado: "falha_transporte",
      codigo: "invalid_client_name",
      fase: "ehlo",
    });
    expect(conectar).not.toHaveBeenCalled();
    expect(classificarParaRetry(r)).toBe("permanente");
  });

  it("credencial incompleta é erro de configuração permanente", async () => {
    const conectar = vi.fn();
    const r = await enviarMensagemSmtp(
      { ...OPCOES_BASE, username: USUARIO },
      ENVELOPE,
      PAYLOAD,
      { conectar }
    );
    expect((r as { codigo: string }).codigo).toBe("config_error");
    expect(conectar).not.toHaveBeenCalled();
    expect(classificarParaRetry(r)).toBe("permanente");
  });
});

describe("R16_SMTP_DATA_SAFETY — backpressure e limpeza", () => {
  it("write devolvendo false faz a escrita aguardar drain", async () => {
    const comandos: string[] = [];
    const { fabrica, socket } = servidorRoteirizado(SEQUENCIA_OK, { comandos });

    const p = enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    // Backpressure na próxima escrita disponível.
    await new Promise((r) => setTimeout(r, 5));
    socket().escritasComBackpressure = 1;

    const r = await p;
    expect(r.estado).toBe("enviado");
    expect(comandos[5]).toBe(PAYLOAD);
  });

  it("sem drain, a escrita estoura o teto de tempo em vez de travar", async () => {
    // Fábrica que devolve false e nunca drena.
    const fabrica: FabricaSocket = {
      async conectar() {
        const s = new SocketFalso(true);
        s.write = () => false;
        s.responder("220 ok\r\n");
        return s;
      },
    };
    const r = await enviarMensagemSmtp(
      { ...OPCOES_BASE, readTimeoutMs: 40 },
      ENVELOPE,
      PAYLOAD,
      fabrica
    );
    expect(r).toEqual({ estado: "falha_transporte", codigo: "write_timeout", fase: "ehlo" });
  });

  it("o socket é destruído em TODOS os desfechos", async () => {
    const desfechos: Array<[string, string[]]> = [
      ["sucesso", SEQUENCIA_OK],
      ["recusa", ["220 ok\r\n", "250 ehlo\r\n", "550 nao\r\n"]],
      ["protocolo", ["220 ok\r\n", "lixo\r\n"]],
    ];
    for (const [, roteiro] of desfechos) {
      const { fabrica, socket } = servidorRoteirizado(roteiro);
      await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
      expect(socket().destruido).toBe(true);
    }
  });

  it("falha no QUIT não transforma mensagem aceita em erro", async () => {
    // Roteiro sem resposta ao QUIT: o 250 final já confirmou a aceitação.
    const { fabrica } = servidorRoteirizado(SEQUENCIA_OK.slice(0, -1));
    const r = await enviarMensagemSmtp(
      comAuth({ readTimeoutMs: 40 }),
      ENVELOPE,
      PAYLOAD,
      fabrica
    );
    expect(r).toEqual({ estado: "enviado", codigo: 250 });
  });

  it("o payload só é escrito depois do 354", async () => {
    const ordem: string[] = [];
    const { fabrica } = servidorRoteirizado(SEQUENCIA_OK, { comandos: ordem });
    await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    expect(ordem.indexOf("DATA\r\n")).toBeLessThan(ordem.indexOf(PAYLOAD));
  });
});

describe("R16_SECRET_AUDIT — credencial e segredo fora de diagnóstico", () => {
  it("a senha não aparece em nenhum resultado, nem no sucesso nem na falha", async () => {
    const roteiros = [
      SEQUENCIA_OK,
      ["220 ok\r\n", "250-x\r\n250 AUTH PLAIN\r\n", "535 recusado\r\n"],
      ["220 ok\r\n", "lixo\r\n"],
    ];
    for (const roteiro of roteiros) {
      const { fabrica } = servidorRoteirizado(roteiro);
      const r = await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
      const serializado = JSON.stringify(r);
      expect(serializado).not.toContain(SENHA);
      expect(serializado).not.toContain(USUARIO);
      expect(serializado).not.toContain(codificarAuthPlain(USUARIO, SENHA));
    }
  });

  it("a carga AUTH codificada nunca sai no log do worker", async () => {
    const linhas: string[] = [];
    const log = criarWorkerLogger((l) => linhas.push(l), [SENHA]);
    const { fabrica } = servidorRoteirizado([
      "220 ok\r\n",
      "250-x\r\n250 AUTH PLAIN\r\n",
      "535 recusado\r\n",
    ]);
    const r = await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    log.error({ event: "smtp_send", outcome: r.estado, ...log.erroSeguro(r) });

    const tudo = linhas.join("\n");
    expect(tudo).not.toContain(SENHA);
    expect(tudo).not.toContain(codificarAuthPlain(USUARIO, SENHA));
  });

  it("a carga AUTH vai no comando, e SOMENTE nele", async () => {
    const comandos: string[] = [];
    const { fabrica } = servidorRoteirizado(SEQUENCIA_OK, { comandos });
    await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, fabrica);
    const carga = codificarAuthPlain(USUARIO, SENHA);
    expect(comandos.filter((c) => c.includes(carga))).toHaveLength(1);
  });

  it("codificarAuthPlain recusa controle em usuário ou senha", () => {
    expect(() => codificarAuthPlain("a\r\nAUTH", "x")).toThrow();
    expect(() => codificarAuthPlain("a", "x\r\nQUIT")).toThrow();
    // Formato RFC 4616: \0user\0pass
    const b64 = codificarAuthPlain("u", "p");
    expect(Buffer.from(b64, "base64").toString("utf8")).toBe("\0u\0p");
  });

  it("o corpo da mensagem não é ecoado em resultado de falha", async () => {
    const corpoSensivel = montarPayloadData(
      { from: "a@b.com.br", to: "c@d.com.br", subject: "s" },
      "TOKEN-CUNHADO-SECRETO-123456"
    );
    const { fabrica } = servidorRoteirizado([
      "220 ok\r\n",
      "250 ehlo\r\n",
      "250 mail\r\n",
      "250 rcpt\r\n",
      "354 manda\r\n",
      "451 depois\r\n",
    ]);
    const r = await enviarMensagemSmtp(OPCOES_BASE, ENVELOPE, corpoSensivel, fabrica);
    expect(JSON.stringify(r)).not.toContain("TOKEN-CUNHADO-SECRETO-123456");
  });
});

describe("R16_TLS_AUDIT — opções repassadas à fábrica", () => {
  it("modo implicit_tls pede conexão segura; texto claro não", async () => {
    const { fabrica: f1, conexoes: c1 } = servidorRoteirizado(SEQUENCIA_OK);
    await enviarMensagemSmtp(comAuth(), ENVELOPE, PAYLOAD, f1);
    expect(c1[0].seguro).toBe(true);
    expect(c1[0].host).toBe("smtp.exemplo.com");
    expect(c1[0].port).toBe(465);

    const { fabrica: f2, conexoes: c2 } = servidorRoteirizado(SEQUENCIA_OK, { seguro: false });
    await enviarMensagemSmtp(
      { ...OPCOES_BASE, mode: "plaintext_local_only" },
      ENVELOPE,
      PAYLOAD,
      f2
    );
    expect(c2[0].seguro).toBe(false);
  });

  it("o timeout de conexão configurado é repassado", async () => {
    const { fabrica, conexoes } = servidorRoteirizado(SEQUENCIA_OK);
    await enviarMensagemSmtp(comAuth({ connectTimeoutMs: 7_777 }), ENVELOPE, PAYLOAD, fabrica);
    expect(conexoes[0].connectTimeoutMs).toBe(7_777);
  });
});
