/**
 * R16 — PARSER DE RESPOSTA SMTP.
 *
 * Puro e sem rede: recebe bytes acumulados, devolve respostas completas.
 *
 * SEMÂNTICA DE CONTINUAÇÃO (RFC 5321 §4.2.1)
 *   "250-PIPELINING"  → hífen: há mais linhas
 *   "250 OK"          → espaço: última linha da resposta
 *
 * LIMITES SÃO PARTE DA SEGURANÇA
 * Um servidor malicioso ou defeituoso pode nunca enviar a linha final, ou
 * enviar linhas infinitas. Sem teto, o worker acumularia memória até morrer.
 * Por isso há limite de tamanho de linha, de número de linhas e de buffer
 * total, e estourá-los é erro de protocolo — não um 4xx/5xx do servidor.
 */

export class SmtpProtocolError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "SmtpProtocolError";
    this.code = code;
  }
}

/** Limite por linha. RFC 5321 §4.5.3.1.5 fixa 512 octetos; damos folga. */
export const MAX_LINHA = 1000;
/** Máximo de linhas numa única resposta multilinha. */
export const MAX_LINHAS_RESPOSTA = 100;
/** Teto do buffer acumulado enquanto uma resposta não se completa. */
export const MAX_BUFFER = 64 * 1024;

export type RespostaSmtp = {
  /** Código de três dígitos da linha final. */
  code: number;
  /** Primeiro dígito: 2 sucesso, 3 intermediário, 4 temporário, 5 permanente. */
  classe: 2 | 3 | 4 | 5;
  /** Linhas de texto, sem o código e sem CRLF. */
  linhas: string[];
};

/** Classificação de falha exigida pelo contrato de retry do dispatchOutbox. */
export function classificarResposta(r: RespostaSmtp): "ok" | "temporario" | "permanente" {
  if (r.classe === 2 || r.classe === 3) return "ok";
  if (r.classe === 4) return "temporario";
  return "permanente";
}

/**
 * Acumulador de bytes que emite respostas SMTP completas.
 *
 * Uso: `push(chunk)` a cada `data` do socket; quando devolve uma resposta,
 * ela está completa. `null` significa "ainda incompleta, continue lendo".
 */
export class LeitorRespostaSmtp {
  #buffer = "";

  /** Bytes ainda não consumidos. Exposto só para diagnóstico em teste. */
  get pendente(): string {
    return this.#buffer;
  }

  push(chunk: string): void {
    this.#buffer += chunk;
    if (this.#buffer.length > MAX_BUFFER) {
      throw new SmtpProtocolError(
        "response_buffer_overflow",
        "resposta SMTP excedeu o buffer máximo"
      );
    }
  }

  /**
   * Tenta extrair uma resposta completa do buffer.
   * Devolve `null` se ainda não há linha final.
   */
  proxima(): RespostaSmtp | null {
    const linhasCompletas: string[] = [];
    let consumido = 0;

    while (true) {
      const fim = this.#buffer.indexOf("\r\n", consumido);
      if (fim === -1) {
        // Sem CRLF: se já passou do limite de linha, é servidor defeituoso.
        if (this.#buffer.length - consumido > MAX_LINHA) {
          throw new SmtpProtocolError("response_line_too_long", "linha SMTP longa demais");
        }
        return null;
      }

      const linha = this.#buffer.slice(consumido, fim);
      consumido = fim + 2;

      if (linha.length > MAX_LINHA) {
        throw new SmtpProtocolError("response_line_too_long", "linha SMTP longa demais");
      }
      linhasCompletas.push(linha);
      if (linhasCompletas.length > MAX_LINHAS_RESPOSTA) {
        throw new SmtpProtocolError(
          "response_too_many_lines",
          "resposta SMTP com linhas demais"
        );
      }

      // "250-texto" continua; "250 texto" encerra.
      const m = /^(\d{3})([ -])?(.*)$/.exec(linha);
      if (!m) {
        throw new SmtpProtocolError("response_malformed", "linha de status SMTP inválida");
      }
      const separador = m[2];
      if (separador === "-") continue;

      // Linha final: `separador` é espaço ou ausente (ex.: "250").
      const code = Number(m[1]);
      const primeiroDigito = Math.floor(code / 100);
      if (primeiroDigito < 2 || primeiroDigito > 5) {
        throw new SmtpProtocolError("response_bad_code", "código SMTP fora da faixa");
      }

      this.#buffer = this.#buffer.slice(consumido);
      return {
        code,
        classe: primeiroDigito as 2 | 3 | 4 | 5,
        linhas: linhasCompletas.map((l) => l.replace(/^\d{3}[ -]?/, "")),
      };
    }
  }

  /**
   * Chamado no fechamento do socket. Se restou buffer, o servidor cortou a
   * conexão no meio de uma resposta — falha de protocolo, não do servidor.
   */
  fimDeFluxo(): void {
    if (this.#buffer.trim().length > 0) {
      throw new SmtpProtocolError(
        "response_truncated",
        "conexão encerrada com resposta SMTP incompleta"
      );
    }
  }
}
