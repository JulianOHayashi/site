/**
 * R16 — SERIALIZAÇÃO SMTP.
 *
 * Separado do socket de propósito: toda a lógica perigosa — dot-stuffing,
 * terminação de DATA, rejeição de CR/LF/NUL — é pura e testável sem rede.
 *
 * O risco central deste arquivo é INJEÇÃO. Um `\r\n` num cabeçalho permite ao
 * atacante forjar cabeçalhos novos; um `\r\n.\r\n` no corpo encerra o DATA
 * antes da hora e transforma o resto do corpo em COMANDOS SMTP. Por isso
 * nada aqui aceita entrada sem validação, e a validação recusa em vez de
 * "limpar" — sanear silenciosamente esconderia a tentativa.
 */

/** Erro de serialização. Mensagem sem conteúdo do usuário, para não vazar. */
export class SmtpSerializationError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "SmtpSerializationError";
    this.code = code;
  }
}

const CR = "\r";
const LF = "\n";
const NUL = "\0";

/** Verdadeiro se o texto contém CR, LF ou NUL. */
export function temControleProibido(valor: string): boolean {
  return valor.includes(CR) || valor.includes(LF) || valor.includes(NUL);
}

/**
 * Valida um valor de cabeçalho. Rejeita — não remove — caracteres de
 * controle: remover silenciosamente entregaria o e-mail e esconderia a
 * tentativa de injeção.
 */
export function validarValorDeCabecalho(nome: string, valor: string): string {
  if (typeof valor !== "string" || valor.length === 0) {
    throw new SmtpSerializationError("header_empty", `cabeçalho ${nome} vazio`);
  }
  if (temControleProibido(valor)) {
    throw new SmtpSerializationError(
      "header_control_char",
      `cabeçalho ${nome} contém CR, LF ou NUL`
    );
  }
  if (valor.length > 998) {
    // RFC 5322: linha de até 998 octetos além do CRLF.
    throw new SmtpSerializationError("header_too_long", `cabeçalho ${nome} longo demais`);
  }
  return valor;
}

/**
 * Valida um endereço para uso em MAIL FROM / RCPT TO.
 *
 * Não tenta validar e-mail exaustivamente — isso é impossível e produz falsos
 * negativos. Valida o que importa para o protocolo: nada de CR/LF/NUL, nada
 * de espaço, nada de `<` ou `>` (que quebrariam o envelope), e um `@`.
 */
export function validarEnderecoDeEnvelope(rotulo: string, endereco: string): string {
  if (typeof endereco !== "string" || endereco.length === 0) {
    throw new SmtpSerializationError("address_empty", `${rotulo} vazio`);
  }
  if (temControleProibido(endereco)) {
    throw new SmtpSerializationError(
      "address_control_char",
      `${rotulo} contém CR, LF ou NUL`
    );
  }
  if (/[\s<>,;]/.test(endereco)) {
    throw new SmtpSerializationError(
      "address_invalid_char",
      `${rotulo} contém caractere inválido para o envelope`
    );
  }
  if (!endereco.includes("@")) {
    throw new SmtpSerializationError("address_no_at", `${rotulo} sem @`);
  }
  if (endereco.length > 320) {
    throw new SmtpSerializationError("address_too_long", `${rotulo} longo demais`);
  }
  return endereco;
}

/**
 * Normaliza quebras de linha para CRLF canônico.
 *
 * Aceita LF isolado, CR isolado e CRLF, e produz sempre CRLF. Feito em duas
 * passagens para não gerar CRCRLF quando a entrada já é CRLF.
 */
export function normalizarCRLF(texto: string): string {
  return texto.replace(/\r\n/g, LF).replace(/\r/g, LF).replace(/\n/g, "\r\n");
}

/**
 * Dot-stuffing (RFC 5321 §4.5.2).
 *
 * Toda linha que começa com "." recebe um "." adicional. Sem isso, uma linha
 * do corpo contendo apenas "." encerraria o DATA prematuramente, e o texto
 * seguinte seria interpretado como comando SMTP pelo servidor.
 *
 * Aplicar DEPOIS da normalização CRLF; a ordem importa.
 */
export function aplicarDotStuffing(corpoCRLF: string): string {
  return corpoCRLF
    .split("\r\n")
    .map((linha) => (linha.startsWith(".") ? "." + linha : linha))
    .join("\r\n");
}

export type CabecalhosEmail = {
  from: string;
  to: string;
  subject: string;
  replyTo?: string;
  messageId?: string;
  date?: string;
};

/**
 * Monta o payload completo do DATA: cabeçalhos, linha em branco, corpo com
 * dot-stuffing, e exatamente UM terminador `\r\n.\r\n`.
 */
export function montarPayloadData(
  cabecalhos: CabecalhosEmail,
  corpoTexto: string,
  corpoHtml?: string
): string {
  const from = validarValorDeCabecalho("From", cabecalhos.from);
  const to = validarValorDeCabecalho("To", cabecalhos.to);
  const subject = validarValorDeCabecalho("Subject", cabecalhos.subject);

  const linhas: string[] = [
    `From: ${from}`,
    `To: ${to}`,
    `Subject: ${subject}`,
    "MIME-Version: 1.0",
  ];

  if (cabecalhos.replyTo !== undefined) {
    linhas.push(`Reply-To: ${validarValorDeCabecalho("Reply-To", cabecalhos.replyTo)}`);
  }
  if (cabecalhos.messageId !== undefined) {
    linhas.push(`Message-ID: ${validarValorDeCabecalho("Message-ID", cabecalhos.messageId)}`);
  }
  if (cabecalhos.date !== undefined) {
    linhas.push(`Date: ${validarValorDeCabecalho("Date", cabecalhos.date)}`);
  }

  let corpo: string;
  if (corpoHtml !== undefined) {
    const fronteira = `bdflow-${Math.random().toString(36).slice(2, 12)}`;
    linhas.push(`Content-Type: multipart/alternative; boundary="${fronteira}"`);
    corpo = [
      `--${fronteira}`,
      "Content-Type: text/plain; charset=utf-8",
      "Content-Transfer-Encoding: 8bit",
      "",
      corpoTexto,
      `--${fronteira}`,
      "Content-Type: text/html; charset=utf-8",
      "Content-Transfer-Encoding: 8bit",
      "",
      corpoHtml,
      `--${fronteira}--`,
    ].join("\n");
  } else {
    linhas.push("Content-Type: text/plain; charset=utf-8");
    linhas.push("Content-Transfer-Encoding: 8bit");
    corpo = corpoTexto;
  }

  const cabecalhoCRLF = normalizarCRLF(linhas.join("\n"));
  const corpoCRLF = aplicarDotStuffing(normalizarCRLF(corpo));

  // cabeçalhos + linha em branco + corpo + terminador único.
  return `${cabecalhoCRLF}\r\n\r\n${corpoCRLF}\r\n.\r\n`;
}

/** Terminador canônico do DATA. */
export const TERMINADOR_DATA = "\r\n.\r\n";

/**
 * Confere que o payload termina com exatamente um terminador e que nenhum
 * terminador aparece antes do fim. Usado como asserção defensiva e nos testes.
 */
export function contarTerminadoresPrematuros(payload: string): number {
  const corpo = payload.slice(0, -TERMINADOR_DATA.length);
  let n = 0;
  let i = corpo.indexOf(TERMINADOR_DATA);
  while (i !== -1) {
    n++;
    i = corpo.indexOf(TERMINADOR_DATA, i + 1);
  }
  return n;
}
