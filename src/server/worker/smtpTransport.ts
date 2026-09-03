/**
 * R16 — MOTOR DE PROTOCOLO SMTP.
 *
 * Conversa apenas com a interface `SocketSmtp`. Isso permite provar sequência
 * de comandos, backpressure, timeouts e classificação de falha com um socket
 * determinístico, sem servidor SMTP externo e sem rede.
 *
 * MODOS SUPORTADOS
 *   implicit_tls          — TLS desde o primeiro byte. Caminho de produção.
 *   plaintext_local_only  — sem cifra, restrito a desenvolvimento pela
 *                           configuração, e AUTH é recusado pelo motor.
 *
 * STARTTLS NÃO É SUPORTADO NESTA JANELA. Não há upgrade de socket, não há
 * re-EHLO e não há detecção de capacidade STARTTLS. Anunciar suporte
 * incompleto seria pior do que não anunciar: um operador configuraria a porta
 * 587 esperando cifra e receberia um caminho não exercitado. A configuração
 * recusa o modo explicitamente (`unsupported_smtp_mode`).
 *
 * FALHA DE TRANSPORTE ≠ RECUSA DO SERVIDOR
 * Erro de certificado, socket, timeout, EOF inesperado, resposta malformada e
 * erro de configuração produzem `falha_transporte` com código interno
 * sanitizado — jamais um 4xx/5xx sintético. Fabricar um código de servidor
 * corromperia a decisão de retentativa e o diagnóstico.
 */

import {
  LeitorRespostaSmtp,
  SmtpProtocolError,
  type RespostaSmtp,
} from "./smtpReplyParser";
import { SmtpSerializationError, validarEnderecoDeEnvelope } from "./smtpWire";
import {
  SmtpSocketError,
  traduzirErroDeSocket,
  type FabricaSocket,
  type SocketSmtp,
} from "./nodeSmtpSocket";

export type FaseSmtp =
  | "connect"
  | "greeting"
  | "ehlo"
  | "auth"
  | "mail_from"
  | "rcpt_to"
  | "data"
  | "payload"
  | "quit";

export type ResultadoTransporte =
  | {
      estado: "enviado";
      codigo: number;
      /**
       * Texto da linha final do servidor. SMTP não define id de mensagem
       * canônico; provedores costumam embutir a chave da fila aqui. É texto
       * arbitrário de terceiro — quem o persistir precisa sanitizá-lo.
       */
      linhaFinal?: string;
    }
  | { estado: "recusa_temporaria"; codigo: number; fase: FaseSmtp }
  | { estado: "recusa_permanente"; codigo: number; fase: FaseSmtp }
  | { estado: "falha_transporte"; codigo: string; fase: FaseSmtp };

export type OpcoesTransporte = {
  host: string;
  port: number;
  mode: "implicit_tls" | "plaintext_local_only";
  username?: string;
  password?: string;
  connectTimeoutMs: number;
  readTimeoutMs: number;
  /** Nome anunciado no EHLO. Sem CR/LF/espaço. */
  clientName: string;
  /** Âncora de confiança extra; nunca desliga verificação. */
  caExtra?: string | string[];
};

export type EnvelopeSmtp = {
  mailFrom: string;
  rcptTo: string;
};

/**
 * Códigos internos que NÃO melhoram com retentativa: a mensagem, do jeito que
 * está, nunca será aceita. Todo o resto (rede, TLS, timeout) é temporário.
 */
const FALHAS_PERMANENTES: ReadonlySet<string> = new Set([
  "config_error",
  "auth_over_insecure_transport",
  "auth_mechanism_unavailable",
  "invalid_client_name",
  "serialization_error",
]);

/** Traduz o resultado para a decisão de retentativa do despachante. */
export function classificarParaRetry(
  r: ResultadoTransporte
): "ok" | "temporario" | "permanente" {
  switch (r.estado) {
    case "enviado":
      return "ok";
    case "recusa_temporaria":
      return "temporario";
    case "recusa_permanente":
      return "permanente";
    case "falha_transporte":
      return FALHAS_PERMANENTES.has(r.codigo) ? "permanente" : "temporario";
  }
}

/** Codifica AUTH PLAIN (RFC 4616). O retorno NUNCA pode ir para log. */
export function codificarAuthPlain(usuario: string, senha: string): string {
  if (/[\r\n\0]/.test(usuario) || /[\r\n\0]/.test(senha)) {
    throw new SmtpSerializationError(
      "auth_control_char",
      "credencial contém caractere de controle"
    );
  }
  return Buffer.from(`\0${usuario}\0${senha}`, "utf8").toString("base64");
}

/** Verdadeiro se as linhas do EHLO anunciam AUTH com o mecanismo PLAIN. */
export function anunciaAuthPlain(linhas: readonly string[]): boolean {
  return linhas.some((l) => {
    const t = l.trim().toUpperCase();
    return t === "AUTH PLAIN" || t.startsWith("AUTH ")
      ? t.split(/\s+/).slice(1).includes("PLAIN")
      : false;
  });
}

class FalhaDeTransporte extends Error {
  readonly codigo: string;
  readonly fase: FaseSmtp;
  constructor(codigo: string, fase: FaseSmtp) {
    super(codigo);
    this.name = "FalhaDeTransporte";
    this.codigo = codigo;
    this.fase = fase;
  }
}

class RecusaDoServidor extends Error {
  readonly resposta: RespostaSmtp;
  readonly fase: FaseSmtp;
  constructor(resposta: RespostaSmtp, fase: FaseSmtp) {
    super(`smtp_${resposta.code}`);
    this.name = "RecusaDoServidor";
    this.resposta = resposta;
    this.fase = fase;
  }
}

/**
 * Conversa com um socket: acumula bytes, entrega respostas completas e
 * resolve backpressure. Todo desfecho anormal vira `FalhaDeTransporte`.
 */
class Conversa {
  readonly #socket: SocketSmtp;
  readonly #leitor = new LeitorRespostaSmtp();
  readonly #prontas: RespostaSmtp[] = [];
  #esperando: ((r: RespostaSmtp) => void) | null = null;
  #falhando: ((e: unknown) => void) | null = null;
  #erro: unknown = null;
  #fechado = false;
  #aguardandoDrain: Array<() => void> = [];

  constructor(socket: SocketSmtp) {
    this.#socket = socket;

    socket.on("data", (chunk: string) => {
      try {
        this.#leitor.push(chunk);
        for (;;) {
          const r = this.#leitor.proxima();
          if (r === null) break;
          if (this.#esperando) {
            const resolver = this.#esperando;
            this.#esperando = null;
            this.#falhando = null;
            resolver(r);
          } else {
            this.#prontas.push(r);
          }
        }
      } catch (e) {
        this.#registrarErro(e);
      }
    });

    socket.on("error", (e: Error) => this.#registrarErro(traduzirErroDeSocket(e)));

    socket.on("close", () => {
      this.#fechado = true;
      try {
        this.#leitor.fimDeFluxo();
      } catch (e) {
        this.#registrarErro(e);
        return;
      }
      // Fechou sem resposta pendente incompleta, mas alguém esperava: EOF.
      if (this.#esperando) {
        this.#registrarErro(new SmtpSocketError("unexpected_eof", "conexão encerrada"));
      }
    });

    socket.on("drain", () => {
      const fila = this.#aguardandoDrain;
      this.#aguardandoDrain = [];
      for (const f of fila) f();
    });
  }

  #registrarErro(e: unknown): void {
    if (this.#erro === null) this.#erro = e;
    const rejeitar = this.#falhando;
    this.#esperando = null;
    this.#falhando = null;
    if (rejeitar) rejeitar(e);
    // Destrava escritas presas em backpressure de um socket já morto.
    const fila = this.#aguardandoDrain;
    this.#aguardandoDrain = [];
    for (const f of fila) f();
  }

  /** Espera uma resposta completa, com teto de tempo. */
  esperar(fase: FaseSmtp, readTimeoutMs: number): Promise<RespostaSmtp> {
    if (this.#prontas.length > 0) return Promise.resolve(this.#prontas.shift() as RespostaSmtp);
    if (this.#erro !== null) return Promise.reject(this.#converter(this.#erro, fase));
    if (this.#fechado) {
      return Promise.reject(new FalhaDeTransporte("unexpected_eof", fase));
    }

    return new Promise<RespostaSmtp>((resolver, rejeitar) => {
      const temporizador = setTimeout(() => {
        this.#esperando = null;
        this.#falhando = null;
        rejeitar(new FalhaDeTransporte("read_timeout", fase));
      }, readTimeoutMs);

      this.#esperando = (r) => {
        clearTimeout(temporizador);
        resolver(r);
      };
      this.#falhando = (e) => {
        clearTimeout(temporizador);
        rejeitar(this.#converter(e, fase));
      };
    });
  }

  #converter(e: unknown, fase: FaseSmtp): FalhaDeTransporte {
    if (e instanceof FalhaDeTransporte) return e;
    if (e instanceof SmtpProtocolError) return new FalhaDeTransporte(e.code, fase);
    if (e instanceof SmtpSocketError) return new FalhaDeTransporte(e.code, fase);
    return new FalhaDeTransporte("socket_error", fase);
  }

  /**
   * Escreve respeitando backpressure.
   *
   * `write` devolvendo `false` significa que o buffer do kernel encheu; seguir
   * escrevendo cresceria memória sem limite. E o retorno de `write` NÃO é
   * prova de aceitação pelo servidor SMTP — só a resposta é.
   */
  async escrever(dados: string, fase: FaseSmtp, readTimeoutMs: number): Promise<void> {
    if (this.#erro !== null) throw this.#converter(this.#erro, fase);
    if (this.#fechado) throw new FalhaDeTransporte("unexpected_eof", fase);

    const coube = this.#socket.write(dados);
    if (coube) return;

    await new Promise<void>((resolver, rejeitar) => {
      const temporizador = setTimeout(() => {
        this.#aguardandoDrain = this.#aguardandoDrain.filter((f) => f !== aoDrenar);
        rejeitar(new FalhaDeTransporte("write_timeout", fase));
      }, readTimeoutMs);
      const aoDrenar = () => {
        clearTimeout(temporizador);
        resolver();
      };
      this.#aguardandoDrain.push(aoDrenar);
    });

    if (this.#erro !== null) throw this.#converter(this.#erro, fase);
  }
}

/** Exige 2xx/3xx; qualquer outra classe vira recusa do SERVIDOR, não do transporte. */
function exigirClasse(
  r: RespostaSmtp,
  fase: FaseSmtp,
  esperada: 2 | 3
): void {
  if (r.classe === esperada) return;
  if (r.classe === 4 || r.classe === 5) throw new RecusaDoServidor(r, fase);
  // 2xx onde se esperava 3xx (ou vice-versa): o servidor não está seguindo o
  // protocolo. Não é recusa — é defeito de protocolo.
  throw new FalhaDeTransporte("unexpected_reply_class", fase);
}

function validarClientName(nome: string): string {
  if (typeof nome !== "string" || nome.length === 0 || /[\r\n\0\s]/.test(nome)) {
    throw new FalhaDeTransporte("invalid_client_name", "ehlo");
  }
  return nome;
}

/**
 * Executa uma transação SMTP completa e devolve o desfecho.
 *
 * O socket é destruído em qualquer saída — sucesso, recusa ou exceção.
 */
export async function enviarMensagemSmtp(
  opcoes: OpcoesTransporte,
  envelope: EnvelopeSmtp,
  payloadData: string,
  fabrica: FabricaSocket
): Promise<ResultadoTransporte> {
  let socket: SocketSmtp | null = null;
  const { readTimeoutMs } = opcoes;

  try {
    // Validações que não dependem de rede acontecem ANTES de abrir socket.
    const clientName = validarClientName(opcoes.clientName);
    const mailFrom = validarEnderecoDeEnvelope("MAIL FROM", envelope.mailFrom);
    const rcptTo = validarEnderecoDeEnvelope("RCPT TO", envelope.rcptTo);
    if ((opcoes.username && !opcoes.password) || (!opcoes.username && opcoes.password)) {
      throw new FalhaDeTransporte("config_error", "connect");
    }

    try {
      socket = await fabrica.conectar({
        host: opcoes.host,
        port: opcoes.port,
        seguro: opcoes.mode === "implicit_tls",
        connectTimeoutMs: opcoes.connectTimeoutMs,
        caExtra: opcoes.caExtra,
      });
    } catch (e) {
      const t = traduzirErroDeSocket(e);
      throw new FalhaDeTransporte(t.code, "connect");
    }

    // BARREIRA DE CREDENCIAL. O estado de cifra é lido do SOCKET, não da
    // configuração: se o modo disser TLS e a conexão não estiver segura, a
    // senha não sai daqui.
    if (opcoes.username !== undefined && !socket.seguro) {
      throw new FalhaDeTransporte("auth_over_insecure_transport", "auth");
    }

    const c = new Conversa(socket);

    const saudacao = await c.esperar("greeting", readTimeoutMs);
    exigirClasse(saudacao, "greeting", 2);
    if (saudacao.code !== 220) throw new FalhaDeTransporte("unexpected_greeting", "greeting");

    await c.escrever(`EHLO ${clientName}\r\n`, "ehlo", readTimeoutMs);
    const ehlo = await c.esperar("ehlo", readTimeoutMs);
    exigirClasse(ehlo, "ehlo", 2);

    if (opcoes.username !== undefined && opcoes.password !== undefined) {
      if (!anunciaAuthPlain(ehlo.linhas)) {
        // Não tentar mecanismo não anunciado: evita mandar credencial a um
        // servidor que talvez nem esteja esperando AUTH.
        throw new FalhaDeTransporte("auth_mechanism_unavailable", "auth");
      }
      const carga = codificarAuthPlain(opcoes.username, opcoes.password);
      await c.escrever(`AUTH PLAIN ${carga}\r\n`, "auth", readTimeoutMs);
      const rAuth = await c.esperar("auth", readTimeoutMs);
      exigirClasse(rAuth, "auth", 2);
    }

    await c.escrever(`MAIL FROM:<${mailFrom}>\r\n`, "mail_from", readTimeoutMs);
    exigirClasse(await c.esperar("mail_from", readTimeoutMs), "mail_from", 2);

    await c.escrever(`RCPT TO:<${rcptTo}>\r\n`, "rcpt_to", readTimeoutMs);
    exigirClasse(await c.esperar("rcpt_to", readTimeoutMs), "rcpt_to", 2);

    await c.escrever("DATA\r\n", "data", readTimeoutMs);
    const r354 = await c.esperar("data", readTimeoutMs);
    exigirClasse(r354, "data", 3);
    if (r354.code !== 354) throw new FalhaDeTransporte("unexpected_data_reply", "data");

    await c.escrever(payloadData, "payload", readTimeoutMs);
    const rFinal = await c.esperar("payload", readTimeoutMs);
    exigirClasse(rFinal, "payload", 2);

    // Mensagem ACEITA. Falha depois deste ponto não desfaz a entrega e, por
    // isso, não pode transformar sucesso em erro — reprocessar duplicaria.
    try {
      await c.escrever("QUIT\r\n", "quit", readTimeoutMs);
      await c.esperar("quit", readTimeoutMs);
    } catch {
      /* encerramento sujo não invalida a aceitação já confirmada */
    }

    return {
      estado: "enviado",
      codigo: rFinal.code,
      linhaFinal: rFinal.linhas[rFinal.linhas.length - 1],
    };
  } catch (e) {
    if (e instanceof RecusaDoServidor) {
      return e.resposta.classe === 4
        ? { estado: "recusa_temporaria", codigo: e.resposta.code, fase: e.fase }
        : { estado: "recusa_permanente", codigo: e.resposta.code, fase: e.fase };
    }
    if (e instanceof FalhaDeTransporte) {
      return { estado: "falha_transporte", codigo: e.codigo, fase: e.fase };
    }
    if (e instanceof SmtpSerializationError) {
      return { estado: "falha_transporte", codigo: "serialization_error", fase: "connect" };
    }
    if (e instanceof SmtpProtocolError) {
      return { estado: "falha_transporte", codigo: e.code, fase: "payload" };
    }
    // Nada de mensagem crua: pode carregar credencial ou corpo.
    return { estado: "falha_transporte", codigo: "internal_error", fase: "connect" };
  } finally {
    socket?.destroy();
  }
}
