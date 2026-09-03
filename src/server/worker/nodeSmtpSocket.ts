/**
 * R16 — FRONTEIRA DE SOCKET SMTP (SERVER-ONLY).
 *
 * Este é o ÚNICO arquivo do worker que importa `node:net` e `node:tls`. A
 * separação é deliberada: o motor de protocolo (`smtpTransport.ts`) conversa
 * apenas com a interface `SocketSmtp` e por isso pode ser testado de forma
 * determinística, sem rede e sem servidor externo.
 *
 * NUNCA importar este módulo a partir de código que chega ao navegador. O
 * bundle do Vite não resolve `node:tls`, e mesmo que resolvesse, arrastaria
 * configuração de servidor para o cliente.
 *
 * TLS NÃO É NEGOCIÁVEL AQUI
 * A verificação de certificado e de hostname é fixada em código, não em
 * configuração. Não existe caminho — nem variável de ambiente, nem opção de
 * worker — capaz de produzir `rejectUnauthorized: false`. Material de
 * confiança adicional (`ca`) é aceito para ambientes com CA privada e para
 * teste, mas confiar em uma CA extra NÃO é o mesmo que desligar a
 * verificação: a cadeia continua sendo validada e o hostname conferido.
 */

import net from "node:net";
import tls from "node:tls";
import type { ConnectionOptions as TlsConnectionOptions } from "node:tls";

/** Falha da camada de socket. Nunca carrega credencial nem corpo de mensagem. */
export class SmtpSocketError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "SmtpSocketError";
    this.code = code;
  }
}

/**
 * Contrato mínimo que o motor de protocolo consome.
 *
 * `seguro` é a autoridade sobre o estado de cifra: o motor recusa AUTH
 * enquanto for `false`, independentemente do que a configuração diga.
 */
export interface SocketSmtp {
  readonly seguro: boolean;
  on(evento: "data", fn: (chunk: string) => void): void;
  on(evento: "error", fn: (erro: Error) => void): void;
  on(evento: "close", fn: () => void): void;
  on(evento: "drain", fn: () => void): void;
  /** `false` indica backpressure: aguardar `drain` antes de escrever mais. */
  write(dados: string): boolean;
  /** Encerramento cordial (FIN). */
  end(): void;
  /** Encerramento imediato e liberação de recursos. Idempotente. */
  destroy(): void;
}

export type OpcoesConexao = {
  host: string;
  port: number;
  /** `true` = TLS implícito desde o primeiro byte. */
  seguro: boolean;
  connectTimeoutMs: number;
  /** Âncora de confiança adicional. NÃO desliga verificação alguma. */
  caExtra?: string | string[];
};

export interface FabricaSocket {
  conectar(opcoes: OpcoesConexao): Promise<SocketSmtp>;
}

/** Piso de versão. TLS 1.0/1.1 estão depreciados e são recusados. */
export const TLS_MIN_VERSION = "TLSv1.2" as const;

/**
 * Monta as opções exatas entregues a `tls.connect`.
 *
 * Função pura, exportada para que o teste possa afirmar sobre o objeto real
 * — e não sobre uma reconstrução parecida.
 */
export function opcoesTls(
  host: string,
  port: number,
  caExtra?: string | string[]
): TlsConnectionOptions {
  const base: TlsConnectionOptions = {
    host,
    port,
    // SNI e verificação de identidade usam este nome.
    servername: host,
    rejectUnauthorized: true,
    minVersion: TLS_MIN_VERSION,
  };
  return caExtra === undefined ? base : { ...base, ca: caExtra };
}

/**
 * Barreira fail-closed executada IMEDIATAMENTE antes do handshake.
 *
 * Existe porque a garantia não pode depender de ninguém lembrar de revisar
 * `opcoesTls`. Se um caminho futuro construir opções mais fracas, a conexão
 * não acontece.
 */
export function exigirOpcoesTlsSeguras(o: TlsConnectionOptions): void {
  if (o.rejectUnauthorized !== true) {
    throw new SmtpSocketError(
      "tls_verification_disabled",
      "verificação de certificado não pode ser desabilitada"
    );
  }
  if (typeof o.servername !== "string" || o.servername.length === 0) {
    throw new SmtpSocketError(
      "tls_servername_missing",
      "servername é obrigatório para verificação de hostname e SNI"
    );
  }
  if (o.checkServerIdentity !== undefined) {
    throw new SmtpSocketError(
      "tls_identity_check_overridden",
      "verificação de identidade do servidor não pode ser substituída"
    );
  }
  if (o.minVersion !== TLS_MIN_VERSION) {
    throw new SmtpSocketError("tls_min_version_weak", "versão mínima de TLS inadequada");
  }
}

/**
 * Recusa a variável global do Node que desliga a verificação de certificado
 * em TODO o processo.
 *
 * Sem esta checagem, `NODE_TLS_REJECT_UNAUTHORIZED=0` no ambiente anularia
 * silenciosamente `rejectUnauthorized: true` — a conexão pareceria segura e
 * não seria. É um interruptor global, portanto precisa de recusa explícita.
 */
export function exigirVerificacaoGlobalAtiva(
  env: Record<string, string | undefined> = process.env
): void {
  const v = env.NODE_TLS_REJECT_UNAUTHORIZED;
  if (v !== undefined && v.trim() === "0") {
    throw new SmtpSocketError(
      "tls_verification_disabled_globally",
      "NODE_TLS_REJECT_UNAUTHORIZED=0 desliga a verificação em todo o processo"
    );
  }
}

/** Adapta um socket do Node ao contrato mínimo, fixando a codificação. */
function adaptar(sock: net.Socket, seguro: boolean): SocketSmtp {
  sock.setEncoding("utf8");
  return {
    get seguro() {
      return seguro;
    },
    on(evento: string, fn: (...args: never[]) => void): void {
      sock.on(evento, fn as (...args: unknown[]) => void);
    },
    write(dados: string): boolean {
      return sock.write(dados, "utf8");
    },
    end(): void {
      sock.end();
    },
    destroy(): void {
      sock.destroy();
    },
  } as SocketSmtp;
}

/**
 * Fábrica real sobre `node:net` / `node:tls`.
 *
 * O timeout de conexão é armado aqui e desarmado no primeiro sinal de
 * sucesso ou falha; em qualquer desfecho o socket é destruído antes de a
 * promessa rejeitar, para não deixar descritor pendurado.
 */
export function criarFabricaSocketNode(): FabricaSocket {
  return {
    conectar(opcoes: OpcoesConexao): Promise<SocketSmtp> {
      return new Promise<SocketSmtp>((resolver, rejeitar) => {
        let liquidado = false;
        let sock: net.Socket;

        const temporizador = setTimeout(() => {
          if (liquidado) return;
          liquidado = true;
          sock?.destroy();
          rejeitar(
            new SmtpSocketError("connect_timeout", "tempo esgotado ao abrir a conexão")
          );
        }, opcoes.connectTimeoutMs);

        const falhar = (e: unknown) => {
          if (liquidado) return;
          liquidado = true;
          clearTimeout(temporizador);
          sock?.destroy();
          rejeitar(traduzirErroDeSocket(e));
        };

        const concluir = (seguro: boolean) => {
          if (liquidado) return;
          liquidado = true;
          clearTimeout(temporizador);
          resolver(adaptar(sock, seguro));
        };

        try {
          if (opcoes.seguro) {
            exigirVerificacaoGlobalAtiva();
            const o = opcoesTls(opcoes.host, opcoes.port, opcoes.caExtra);
            exigirOpcoesTlsSeguras(o);
            const tlsSock = tls.connect(o);
            sock = tlsSock;
            tlsSock.once("secureConnect", () => {
              // `authorized` é falso quando a cadeia não valida. Com
              // rejectUnauthorized:true o Node já teria emitido erro, mas a
              // checagem permanece como segunda barreira explícita.
              if (!tlsSock.authorized) {
                falhar(
                  new SmtpSocketError(
                    "tls_certificate_rejected",
                    "certificado do servidor não foi autorizado"
                  )
                );
                return;
              }
              concluir(true);
            });
            tlsSock.once("error", falhar);
          } else {
            const plain = net.connect({ host: opcoes.host, port: opcoes.port });
            sock = plain;
            plain.once("connect", () => concluir(false));
            plain.once("error", falhar);
          }
        } catch (e) {
          falhar(e);
        }
      });
    },
  };
}

/**
 * Converte erro do Node em código interno sanitizado.
 *
 * A distinção importa: nada aqui pode virar "o servidor recusou a mensagem".
 * Um erro de certificado ou de rede é falha de TRANSPORTE, e o despachante
 * precisa dessa diferença para decidir retentativa.
 */
export function traduzirErroDeSocket(e: unknown): SmtpSocketError {
  if (e instanceof SmtpSocketError) return e;

  const codigoNode =
    e && typeof e === "object" && "code" in e && typeof (e as { code: unknown }).code === "string"
      ? (e as { code: string }).code
      : "";

  const tlsCert = new Set([
    "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
    "DEPTH_ZERO_SELF_SIGNED_CERT",
    "SELF_SIGNED_CERT_IN_CHAIN",
    "CERT_HAS_EXPIRED",
    "ERR_TLS_CERT_ALTNAME_INVALID",
    "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
  ]);
  if (tlsCert.has(codigoNode)) {
    return new SmtpSocketError("tls_certificate_error", "certificado do servidor inválido");
  }
  if (codigoNode.startsWith("ERR_TLS") || codigoNode.startsWith("ERR_SSL")) {
    return new SmtpSocketError("tls_handshake_error", "falha no handshake TLS");
  }
  switch (codigoNode) {
    case "ECONNREFUSED":
      return new SmtpSocketError("connection_refused", "conexão recusada");
    case "ENOTFOUND":
    case "EAI_AGAIN":
      return new SmtpSocketError("dns_error", "host não resolvido");
    case "ETIMEDOUT":
      return new SmtpSocketError("connect_timeout", "tempo esgotado na conexão");
    case "ECONNRESET":
      return new SmtpSocketError("connection_reset", "conexão reiniciada pelo par");
    case "EPIPE":
      return new SmtpSocketError("broken_pipe", "escrita em conexão encerrada");
    default:
      // Mensagem crua NÃO é propagada: pode conter host, porta e detalhe de
      // infraestrutura que não precisa circular em log.
      return new SmtpSocketError("socket_error", "falha de socket");
  }
}
