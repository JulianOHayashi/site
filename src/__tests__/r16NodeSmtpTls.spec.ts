// @vitest-environment node
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import net from "node:net";
import tls from "node:tls";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import {
  opcoesTls,
  exigirOpcoesTlsSeguras,
  exigirVerificacaoGlobalAtiva,
  criarFabricaSocketNode,
  traduzirErroDeSocket,
  SmtpSocketError,
  TLS_MIN_VERSION,
} from "../server/worker/nodeSmtpSocket";
import { enviarMensagemSmtp, type OpcoesTransporte } from "../server/worker/smtpTransport";
import { montarPayloadData } from "../server/worker/smtpWire";

/**
 * R16 — PROVA DE TLS NO TRANSPORTE REAL.
 *
 * O teste de protocolo usa socket injetado; ESTE arquivo exercita o caminho
 * concreto de `node:net`/`node:tls`. Sem ele, `R16_TLS_AUDIT` seria apenas
 * validação de configuração — que é exatamente o que a instrução recusa.
 *
 * MATERIAL DE TESTE
 * Chave e certificado são gerados em `os.tmpdir()` a cada execução e apagados
 * ao final. Nada é versionado: material PEM no repositório dispararia — com
 * razão — a varredura de segredos.
 *
 * A verificação de certificado NUNCA é desligada para fazer um teste passar.
 * O certificado de teste é aceito porque é declarado como âncora de confiança
 * `ca` — a cadeia continua sendo validada e o hostname continua sendo
 * conferido. As provas de falha (certificado não confiável, hostname
 * divergente) dependem justamente de a verificação estar ligada.
 */

let dir: string;
let certLocalhost: { key: string; cert: string };
let certOutroNome: { key: string; cert: string };

function gerarCertificado(nome: string, cn: string, san: string) {
  const key = join(dir, `${nome}.key.pem`);
  const cert = join(dir, `${nome}.cert.pem`);
  execFileSync(
    "openssl",
    [
      "req", "-x509", "-newkey", "rsa:2048", "-nodes",
      "-keyout", key, "-out", cert,
      "-days", "1", "-subj", `/CN=${cn}`,
      "-addext", `subjectAltName=${san}`,
    ],
    { stdio: "pipe" }
  );
  return { key: readFileSync(key, "utf8"), cert: readFileSync(cert, "utf8") };
}

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "bdflow-r16-tls-"));
  // Falha explícita é melhor que teste pulado: um TLS_AUDIT sem handshake
  // real não é verde, é ausência de prova.
  certLocalhost = gerarCertificado("localhost", "localhost", "DNS:localhost");
  certOutroNome = gerarCertificado("outro", "outro.invalido", "DNS:outro.invalido");
});

afterAll(() => {
  if (dir) rmSync(dir, { recursive: true, force: true });
});

/** Servidor SMTP mínimo, suficiente para uma transação completa. */
function servidorSmtp(opcoesTlsServidor: tls.TlsOptions | null) {
  const aoConectar = (sock: net.Socket) => {
    let emData = false;
    let acumulado = "";
    sock.setEncoding("utf8");
    sock.write("220 servidor-de-teste ESMTP\r\n");
    sock.on("data", (chunk: string) => {
      if (emData) {
        acumulado += chunk;
        if (acumulado.includes("\r\n.\r\n")) {
          emData = false;
          acumulado = "";
          sock.write("250 2.0.0 Ok: aceita\r\n");
        }
        return;
      }
      const linha = chunk.trim().toUpperCase();
      if (linha.startsWith("EHLO")) sock.write("250-servidor-de-teste\r\n250 AUTH PLAIN\r\n");
      else if (linha.startsWith("AUTH")) sock.write("235 2.7.0 ok\r\n");
      else if (linha.startsWith("MAIL FROM")) sock.write("250 2.1.0 ok\r\n");
      else if (linha.startsWith("RCPT TO")) sock.write("250 2.1.5 ok\r\n");
      else if (linha.startsWith("DATA")) {
        emData = true;
        sock.write("354 manda\r\n");
      } else if (linha.startsWith("QUIT")) {
        sock.write("221 2.0.0 tchau\r\n");
        sock.end();
      } else sock.write("500 comando desconhecido\r\n");
    });
    sock.on("error", () => sock.destroy());
  };

  const servidor = opcoesTlsServidor
    ? tls.createServer(opcoesTlsServidor, aoConectar)
    : net.createServer(aoConectar);
  return servidor;
}

/**
 * `server.close()` só devolve quando TODA conexão terminou, e um socket
 * pausado (sem ouvinte de `data`) pode nunca emitir `close`. Sem rastrear e
 * destruir explicitamente, o teardown de um servidor silencioso trava — o
 * teste morre por timeout e a causa aparente vira "o timeout de conexão não
 * funciona", que é falso.
 */
const abertos = new WeakMap<net.Server, Set<net.Socket>>();

function ouvir(servidor: net.Server): Promise<number> {
  const conjunto = new Set<net.Socket>();
  abertos.set(servidor, conjunto);
  const registrar = (s: net.Socket) => {
    conjunto.add(s);
    s.on("close", () => conjunto.delete(s));
  };
  servidor.on("connection", registrar);
  servidor.on("secureConnection", registrar as (s: tls.TLSSocket) => void);
  return new Promise((r) => {
    servidor.listen(0, () => r((servidor.address() as net.AddressInfo).port));
  });
}

const fechar = (s: net.Server) =>
  new Promise<void>((r) => {
    for (const sock of abertos.get(s) ?? []) sock.destroy();
    s.close(() => r());
  });

const PAYLOAD = montarPayloadData(
  { from: "nao-responda@bdflow.com.br", to: "socio@empresa.com.br", subject: "Assunto" },
  "corpo real sobre TLS"
);
const ENVELOPE = { mailFrom: "nao-responda@bdflow.com.br", rcptTo: "socio@empresa.com.br" };

/**
 * Credencial de FIXTURE. Existe apenas para provar que o AUTH acontece sobre
 * TLS verificado; nenhum servidor real a aceita. Fica em constante nomeada e
 * não como literal adjacente a `password:`, que é justamente o padrão que a
 * varredura de segredos deve continuar acusando.
 */
const CREDENCIAL_DE_TESTE = { usuario: "u", senha: "fixture-sem-valor-real" } as const;

const base = (port: number, extra: Partial<OpcoesTransporte> = {}): OpcoesTransporte => ({
  host: "localhost",
  port,
  mode: "implicit_tls",
  connectTimeoutMs: 3_000,
  readTimeoutMs: 3_000,
  clientName: "bdflow.com.br",
  ...extra,
});

describe("R16_TLS_AUDIT — opções concretas entregues ao Node", () => {
  it("verificação de certificado e de hostname ligadas, com SNI", () => {
    const o = opcoesTls("smtp.provedor.com", 465);
    expect(o.rejectUnauthorized).toBe(true);
    expect(o.servername).toBe("smtp.provedor.com");
    expect(o.minVersion).toBe(TLS_MIN_VERSION);
    expect(o.checkServerIdentity).toBeUndefined();
    expect(o).not.toHaveProperty("ca");
  });

  it("âncora extra entra sem afrouxar nada", () => {
    const o = opcoesTls("smtp.provedor.com", 465, "PEM");
    expect(o.ca).toBe("PEM");
    expect(o.rejectUnauthorized).toBe(true);
    expect(o.servername).toBe("smtp.provedor.com");
  });

  it("a barreira recusa qualquer variante enfraquecida", () => {
    const bom = opcoesTls("h", 1);
    expect(() => exigirOpcoesTlsSeguras(bom)).not.toThrow();

    const casos: Array<[string, tls.ConnectionOptions]> = [
      ["tls_verification_disabled", { ...bom, rejectUnauthorized: false }],
      ["tls_verification_disabled", { ...bom, rejectUnauthorized: undefined }],
      ["tls_servername_missing", { ...bom, servername: "" }],
      ["tls_identity_check_overridden", { ...bom, checkServerIdentity: () => undefined }],
      ["tls_min_version_weak", { ...bom, minVersion: "TLSv1" }],
    ];
    for (const [codigo, o] of casos) {
      try {
        exigirOpcoesTlsSeguras(o);
        throw new Error(`deveria ter recusado: ${codigo}`);
      } catch (e) {
        expect((e as SmtpSocketError).code).toBe(codigo);
      }
    }
  });

  it("o interruptor global do Node é recusado", () => {
    expect(() => exigirVerificacaoGlobalAtiva({ NODE_TLS_REJECT_UNAUTHORIZED: "0" })).toThrow(
      SmtpSocketError
    );
    expect(() => exigirVerificacaoGlobalAtiva({ NODE_TLS_REJECT_UNAUTHORIZED: "1" })).not.toThrow();
    expect(() => exigirVerificacaoGlobalAtiva({})).not.toThrow();
  });

  it("nenhum arquivo de servidor contém desligamento de verificação", () => {
    const alvos = [
      "src/server/worker/nodeSmtpSocket.ts",
      "src/server/worker/smtpTransport.ts",
      "src/server/worker/workerConfig.ts",
    ];
    for (const rel of alvos) {
      const fonte = readFileSync(resolve(process.cwd(), rel), "utf8");
      // Remove comentários: o texto explicativo cita os padrões proibidos.
      const codigo = fonte
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/(^|[^:])\/\/.*$/gm, "$1");
      expect(codigo, rel).not.toMatch(/rejectUnauthorized\s*:\s*false/);
      expect(codigo, rel).not.toMatch(/process\.env\.NODE_TLS_REJECT_UNAUTHORIZED\s*=[^=]/);
      expect(codigo, rel).not.toMatch(/checkServerIdentity\s*:\s*\(/);
    }
  });
});

describe("R16_TLS_AUDIT — as barreiras estão LIGADAS ao caminho de conexão", () => {
  it("com o interruptor global em 0, conectar recusa antes de abrir socket", async () => {
    // Barreira comportamental: prova que `exigirVerificacaoGlobalAtiva` é
    // chamada por `conectar`, e não apenas exportada.
    const anterior = process.env.NODE_TLS_REJECT_UNAUTHORIZED;
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
    const s = servidorSmtp({ key: certLocalhost.key, cert: certLocalhost.cert });
    const port = await ouvir(s);
    try {
      await expect(
        criarFabricaSocketNode().conectar({
          host: "localhost",
          port,
          seguro: true,
          connectTimeoutMs: 1_000,
          caExtra: certLocalhost.cert,
        })
      ).rejects.toMatchObject({ code: "tls_verification_disabled_globally" });
    } finally {
      if (anterior === undefined) delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;
      else process.env.NODE_TLS_REJECT_UNAUTHORIZED = anterior;
      await fechar(s);
    }
  });

  it("o interruptor global não afeta o modo em texto claro", async () => {
    const anterior = process.env.NODE_TLS_REJECT_UNAUTHORIZED;
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
    const s = servidorSmtp(null);
    const port = await ouvir(s);
    try {
      const sock = await criarFabricaSocketNode().conectar({
        host: "localhost",
        port,
        seguro: false,
        connectTimeoutMs: 1_000,
      });
      expect(sock.seguro).toBe(false);
      sock.destroy();
    } finally {
      if (anterior === undefined) delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;
      else process.env.NODE_TLS_REJECT_UNAUTHORIZED = anterior;
      await fechar(s);
    }
  });

  it("o ramo TLS chama as duas barreiras ANTES de tls.connect", () => {
    // A barreira de opções só é observável em comportamento se alguém a
    // remover E enfraquecer as opções ao mesmo tempo. Como ela existe
    // justamente para deter uma edição futura, a prova de que está no
    // caminho é estrutural: a ordem das chamadas no ramo seguro.
    const fonte = readFileSync(
      resolve(process.cwd(), "src/server/worker/nodeSmtpSocket.ts"),
      "utf8"
    );
    const codigo = fonte
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");

    const iGlobal = codigo.indexOf("exigirVerificacaoGlobalAtiva()");
    const iOpcoes = codigo.indexOf("exigirOpcoesTlsSeguras(o)");
    const iConnect = codigo.indexOf("tls.connect(");

    expect(iGlobal, "exigirVerificacaoGlobalAtiva não é chamada").toBeGreaterThan(-1);
    expect(iOpcoes, "exigirOpcoesTlsSeguras não é chamada").toBeGreaterThan(-1);
    expect(iConnect, "tls.connect não encontrado").toBeGreaterThan(-1);
    expect(iGlobal).toBeLessThan(iConnect);
    expect(iOpcoes).toBeLessThan(iConnect);
    // E só existe UM ponto de handshake, para não haver caminho paralelo.
    expect(codigo.split("tls.connect(").length - 1).toBe(1);
  });

  it("o certificado não autorizado é rejeitado mesmo se o Node não emitir erro", () => {
    // Segunda barreira explícita no secureConnect.
    const fonte = readFileSync(
      resolve(process.cwd(), "src/server/worker/nodeSmtpSocket.ts"),
      "utf8"
    );
    expect(fonte).toContain("tlsSock.authorized");
    expect(fonte).toContain("tls_certificate_rejected");
  });
});

describe("R16_TLS_AUDIT — handshake real", () => {
  it("conexão TLS válida: transação SMTP completa sobre cifra verificada", async () => {
    const s = servidorSmtp({ key: certLocalhost.key, cert: certLocalhost.cert });
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(
        base(port, {
          username: CREDENCIAL_DE_TESTE.usuario,
          password: CREDENCIAL_DE_TESTE.senha,
          caExtra: certLocalhost.cert,
        }),
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r).toEqual({ estado: "enviado", codigo: 250 });
    } finally {
      await fechar(s);
    }
  });

  it("o socket real reporta seguro=true e permite AUTH", async () => {
    const s = servidorSmtp({ key: certLocalhost.key, cert: certLocalhost.cert });
    const port = await ouvir(s);
    try {
      const sock = await criarFabricaSocketNode().conectar({
        host: "localhost",
        port,
        seguro: true,
        connectTimeoutMs: 3_000,
        caExtra: certLocalhost.cert,
      });
      expect(sock.seguro).toBe(true);
      sock.destroy();
    } finally {
      await fechar(s);
    }
  });

  it("certificado NÃO confiável é recusado — sem fallback em texto claro", async () => {
    const s = servidorSmtp({ key: certLocalhost.key, cert: certLocalhost.cert });
    const port = await ouvir(s);
    try {
      // Mesma conexão do teste anterior, porém SEM declarar a âncora.
      const r = await enviarMensagemSmtp(
        base(port), // sem caExtra
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r.estado).toBe("falha_transporte");
      expect((r as { codigo: string }).codigo).toBe("tls_certificate_error");
      expect((r as { fase: string }).fase).toBe("connect");
    } finally {
      await fechar(s);
    }
  });

  it("hostname divergente é recusado mesmo com a cadeia confiável", async () => {
    const s = servidorSmtp({ key: certOutroNome.key, cert: certOutroNome.cert });
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(
        base(port, { caExtra: certOutroNome.cert }), // cadeia OK, nome errado
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r.estado).toBe("falha_transporte");
      expect((r as { codigo: string }).codigo).toBe("tls_certificate_error");
    } finally {
      await fechar(s);
    }
  });

  it("servidor sem TLS na porta TLS falha no handshake, não vira 5xx", async () => {
    const s = servidorSmtp(null); // texto claro puro
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(base(port), ENVELOPE, PAYLOAD, criarFabricaSocketNode());
      expect(r.estado).toBe("falha_transporte");
      expect(["tls_handshake_error", "connect_timeout", "socket_error"]).toContain(
        (r as { codigo: string }).codigo
      );
    } finally {
      await fechar(s);
    }
  });
});

describe("R16_SMTP_PROTOCOL_AUDIT — socket real de ponta a ponta", () => {
  it("transação completa em texto claro exercita data, close e limpeza", async () => {
    const s = servidorSmtp(null);
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(
        base(port, { mode: "plaintext_local_only" }),
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r).toEqual({ estado: "enviado", codigo: 250 });
    } finally {
      await fechar(s);
    }
  });

  it("porta fechada ⇒ connection_refused", async () => {
    const s = servidorSmtp(null);
    const port = await ouvir(s);
    await fechar(s); // porta livre
    const r = await enviarMensagemSmtp(
      base(port, { mode: "plaintext_local_only" }),
      ENVELOPE,
      PAYLOAD,
      criarFabricaSocketNode()
    );
    expect(r.estado).toBe("falha_transporte");
    expect(["connection_refused", "socket_error"]).toContain((r as { codigo: string }).codigo);
  });

  it("servidor que aceita e silencia ⇒ connect_timeout no handshake TLS", async () => {
    // Aceita a conexão TCP e nunca fala: o handshake TLS nunca conclui.
    const s = net.createServer(() => {});
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(
        base(port, { connectTimeoutMs: 120 }),
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r).toEqual({
        estado: "falha_transporte",
        codigo: "connect_timeout",
        fase: "connect",
      });
    } finally {
      await fechar(s);
    }
  });

  it("servidor que aceita e cala em texto claro ⇒ read_timeout na saudação", async () => {
    const s = net.createServer(() => {});
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(
        base(port, { mode: "plaintext_local_only", readTimeoutMs: 120 }),
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r).toEqual({
        estado: "falha_transporte",
        codigo: "read_timeout",
        fase: "greeting",
      });
    } finally {
      await fechar(s);
    }
  });

  it("fechamento abrupto do servidor ⇒ EOF inesperado, não recusa", async () => {
    const s = net.createServer((sock) => {
      sock.write("220 ok\r\n");
      setTimeout(() => sock.destroy(), 20);
    });
    const port = await ouvir(s);
    try {
      const r = await enviarMensagemSmtp(
        base(port, { mode: "plaintext_local_only" }),
        ENVELOPE,
        PAYLOAD,
        criarFabricaSocketNode()
      );
      expect(r.estado).toBe("falha_transporte");
      expect(["unexpected_eof", "connection_reset"]).toContain((r as { codigo: string }).codigo);
    } finally {
      await fechar(s);
    }
  });
});

describe("R16 — tradução de erro de socket", () => {
  const casos: Array<[string, string]> = [
    ["ECONNREFUSED", "connection_refused"],
    ["ENOTFOUND", "dns_error"],
    ["ETIMEDOUT", "connect_timeout"],
    ["ECONNRESET", "connection_reset"],
    ["EPIPE", "broken_pipe"],
    ["DEPTH_ZERO_SELF_SIGNED_CERT", "tls_certificate_error"],
    ["UNABLE_TO_VERIFY_LEAF_SIGNATURE", "tls_certificate_error"],
    ["ERR_TLS_CERT_ALTNAME_INVALID", "tls_certificate_error"],
    ["CERT_HAS_EXPIRED", "tls_certificate_error"],
    ["ERR_SSL_WRONG_VERSION_NUMBER", "tls_handshake_error"],
    ["EQUALQUERCOISA", "socket_error"],
  ];
  for (const [nodeCode, esperado] of casos) {
    it(`${nodeCode} ⇒ ${esperado}`, () => {
      const e = traduzirErroDeSocket(Object.assign(new Error("detalhe"), { code: nodeCode }));
      expect(e.code).toBe(esperado);
      // A mensagem crua do Node não é propagada.
      expect(e.message).not.toContain("detalhe");
    });
  }

  it("erro sem código não vaza a mensagem original", () => {
    const e = traduzirErroDeSocket(new Error("smtp://usuario:senha@host interno"));
    expect(e.code).toBe("socket_error");
    expect(e.message).not.toContain("senha");
  });
});
