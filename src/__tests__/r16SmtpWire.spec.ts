import { describe, it, expect } from "vitest";
import {
  montarPayloadData,
  normalizarCRLF,
  aplicarDotStuffing,
  validarValorDeCabecalho,
  validarEnderecoDeEnvelope,
  contarTerminadoresPrematuros,
  temControleProibido,
  SmtpSerializationError,
  TERMINADOR_DATA,
} from "../server/worker/smtpWire";
import {
  LeitorRespostaSmtp,
  SmtpProtocolError,
  classificarResposta,
  MAX_LINHA,
  MAX_LINHAS_RESPOSTA,
} from "../server/worker/smtpReplyParser";

/**
 * R16 — SEGURANÇA DO PROTOCOLO SMTP.
 *
 * O risco central é injeção: um CRLF num cabeçalho forja cabeçalhos; um
 * `\r\n.\r\n` no corpo encerra o DATA e transforma o resto em COMANDOS.
 * Estes testes provam que nenhuma das duas coisas é possível.
 */

const CABECALHOS = {
  from: "BDFlow <nao-responda@bdflow.com.br>",
  to: "destino@teste.com.br",
  subject: "Confirme seu e-mail",
};

describe("R16_SMTP_DATA_SAFETY — normalização CRLF", () => {
  it("LF isolado vira CRLF", () => {
    expect(normalizarCRLF("a\nb")).toBe("a\r\nb");
  });

  it("CR isolado vira CRLF", () => {
    expect(normalizarCRLF("a\rb")).toBe("a\r\nb");
  });

  it("CRLF já canônico não vira CRCRLF", () => {
    expect(normalizarCRLF("a\r\nb")).toBe("a\r\nb");
  });

  it("mistura de finais converge para CRLF", () => {
    expect(normalizarCRLF("a\nb\r\nc\rd")).toBe("a\r\nb\r\nc\r\nd");
  });
});

describe("R16_SMTP_DATA_SAFETY — dot-stuffing", () => {
  it("linha iniciada por ponto recebe ponto extra", () => {
    expect(aplicarDotStuffing("a\r\n.\r\nb")).toBe("a\r\n..\r\nb");
  });

  it("ponto no meio da linha não é alterado", () => {
    expect(aplicarDotStuffing("a.b\r\nc")).toBe("a.b\r\nc");
  });

  it("múltiplos pontos iniciais recebem apenas um extra", () => {
    expect(aplicarDotStuffing("...texto")).toBe("....texto");
  });

  it("corpo hostil com terminador NÃO encerra o DATA cedo", () => {
    // Tentativa clássica: fechar o DATA e injetar comandos.
    const hostil = "ola\r\n.\r\nQUIT\r\nMAIL FROM:<atacante@mal.com>";
    const payload = montarPayloadData(CABECALHOS, hostil);

    expect(contarTerminadoresPrematuros(payload)).toBe(0);
    expect(payload.endsWith(TERMINADOR_DATA)).toBe(true);
    // O ponto solitário foi escapado.
    expect(payload).toContain("\r\n..\r\n");
  });

  it("payload termina com exatamente um terminador", () => {
    const payload = montarPayloadData(CABECALHOS, "corpo simples");
    expect(payload.endsWith(TERMINADOR_DATA)).toBe(true);
    expect(contarTerminadoresPrematuros(payload)).toBe(0);
  });

  it("corpo terminando em ponto não gera terminador duplo", () => {
    const payload = montarPayloadData(CABECALHOS, "linha\r\n.");
    expect(contarTerminadoresPrematuros(payload)).toBe(0);
    expect(payload.endsWith(TERMINADOR_DATA)).toBe(true);
  });
});

describe("R16_INJECTION_AUDIT — cabeçalhos", () => {
  it("detecta CR, LF e NUL", () => {
    expect(temControleProibido("a\rb")).toBe(true);
    expect(temControleProibido("a\nb")).toBe(true);
    expect(temControleProibido("a\0b")).toBe(true);
    expect(temControleProibido("normal")).toBe(false);
  });

  it("Subject com CR é rejeitado", () => {
    expect(() =>
      montarPayloadData({ ...CABECALHOS, subject: "Oi\rBcc: vitima@x.com" }, "c")
    ).toThrow(SmtpSerializationError);
  });

  it("Subject com LF é rejeitado", () => {
    expect(() =>
      montarPayloadData({ ...CABECALHOS, subject: "Oi\nBcc: vitima@x.com" }, "c")
    ).toThrow(SmtpSerializationError);
  });

  it("Subject com CRLF injetando cabeçalho é rejeitado", () => {
    try {
      montarPayloadData(
        { ...CABECALHOS, subject: "Oi\r\nBcc: vitima@x.com\r\nX-Forjado: sim" },
        "c"
      );
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as SmtpSerializationError).code).toBe("header_control_char");
    }
  });

  it("From com CR/LF/NUL é rejeitado", () => {
    for (const mau of ["a\rb@x.com", "a\nb@x.com", "a\0b@x.com"]) {
      expect(() => montarPayloadData({ ...CABECALHOS, from: mau }, "c")).toThrow(
        SmtpSerializationError
      );
    }
  });

  it("To com CR/LF/NUL é rejeitado", () => {
    for (const mau of ["a\rb@x.com", "a\nb@x.com", "a\0b@x.com"]) {
      expect(() => montarPayloadData({ ...CABECALHOS, to: mau }, "c")).toThrow(
        SmtpSerializationError
      );
    }
  });

  it("Reply-To com injeção é rejeitado", () => {
    expect(() =>
      montarPayloadData({ ...CABECALHOS, replyTo: "x@y.com\r\nBcc: z@w.com" }, "c")
    ).toThrow(SmtpSerializationError);
  });

  it("cabeçalho vazio é rejeitado", () => {
    expect(() => validarValorDeCabecalho("Subject", "")).toThrow(SmtpSerializationError);
  });

  it("cabeçalho longo demais é rejeitado", () => {
    expect(() => validarValorDeCabecalho("Subject", "x".repeat(999))).toThrow(
      SmtpSerializationError
    );
  });
});

describe("R16_INJECTION_AUDIT — envelope MAIL FROM / RCPT TO", () => {
  it("endereço válido é aceito", () => {
    expect(validarEnderecoDeEnvelope("RCPT TO", "a@b.com.br")).toBe("a@b.com.br");
  });

  it("CR/LF/NUL no endereço é rejeitado", () => {
    for (const mau of ["a@b.com\r\nRCPT TO:<x@y.com>", "a@b\n.com", "a@b\0.com"]) {
      expect(() => validarEnderecoDeEnvelope("RCPT TO", mau)).toThrow(SmtpSerializationError);
    }
  });

  it("espaço, vírgula, ponto e vírgula e sinais de envelope são rejeitados", () => {
    for (const mau of ["a b@c.com", "a@b.com,c@d.com", "a@b.com;c@d.com", "<a@b.com>"]) {
      expect(() => validarEnderecoDeEnvelope("MAIL FROM", mau)).toThrow(
        SmtpSerializationError
      );
    }
  });

  it("endereço sem @ é rejeitado", () => {
    expect(() => validarEnderecoDeEnvelope("RCPT TO", "semarroba")).toThrow(
      SmtpSerializationError
    );
  });

  it("endereço vazio é rejeitado", () => {
    expect(() => validarEnderecoDeEnvelope("RCPT TO", "")).toThrow(SmtpSerializationError);
  });
});

describe("R16_SMTP_PROTOCOL_AUDIT — parser de resposta", () => {
  it("saudação 220 de linha única", () => {
    const l = new LeitorRespostaSmtp();
    l.push("220 smtp.exemplo.com ESMTP\r\n");
    const r = l.proxima()!;
    expect(r.code).toBe(220);
    expect(r.classe).toBe(2);
    expect(r.linhas).toEqual(["smtp.exemplo.com ESMTP"]);
  });

  it("EHLO multilinha com continuação por hífen", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250-smtp.exemplo.com\r\n250-PIPELINING\r\n250-SIZE 10240000\r\n250 STARTTLS\r\n");
    const r = l.proxima()!;
    expect(r.code).toBe(250);
    expect(r.linhas).toEqual([
      "smtp.exemplo.com",
      "PIPELINING",
      "SIZE 10240000",
      "STARTTLS",
    ]);
  });

  it("resposta em pedaços é remontada", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250-pri");
    expect(l.proxima()).toBeNull();
    l.push("meira\r\n250 fi");
    expect(l.proxima()).toBeNull();
    l.push("nal\r\n");
    const r = l.proxima()!;
    expect(r.linhas).toEqual(["primeira", "final"]);
  });

  it("duas respostas coladas são lidas em sequência", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250 OK\r\n354 Envie os dados\r\n");
    expect(l.proxima()!.code).toBe(250);
    expect(l.proxima()!.code).toBe(354);
    expect(l.proxima()).toBeNull();
  });

  it("linha de status malformada é erro de PROTOCOLO", () => {
    const l = new LeitorRespostaSmtp();
    l.push("nao-e-um-codigo\r\n");
    expect(() => l.proxima()).toThrow(SmtpProtocolError);
  });

  it("código fora da faixa 2xx-5xx é rejeitado", () => {
    const l = new LeitorRespostaSmtp();
    l.push("999 estranho\r\n");
    try {
      l.proxima();
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as SmtpProtocolError).code).toBe("response_bad_code");
    }
  });

  it("resposta truncada devolve null, não resposta parcial", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250 OK sem crlf");
    expect(l.proxima()).toBeNull();
  });

  it("EOF com buffer pendente é erro de protocolo", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250 incompleta");
    expect(() => l.fimDeFluxo()).toThrow(SmtpProtocolError);
  });

  it("EOF limpo não lança", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250 OK\r\n");
    l.proxima();
    expect(() => l.fimDeFluxo()).not.toThrow();
  });
});

describe("R16_SMTP_PROTOCOL_AUDIT — limites contra buffer ilimitado", () => {
  it("linha longa demais sem CRLF é rejeitada", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250-" + "x".repeat(MAX_LINHA + 10));
    expect(() => l.proxima()).toThrow(SmtpProtocolError);
  });

  it("linhas demais numa resposta são rejeitadas", () => {
    const l = new LeitorRespostaSmtp();
    l.push("250-inicio\r\n".repeat(MAX_LINHAS_RESPOSTA + 5));
    try {
      l.proxima();
      throw new Error("deveria ter lançado");
    } catch (e) {
      expect((e as SmtpProtocolError).code).toBe("response_too_many_lines");
    }
  });

  it("buffer total excessivo é rejeitado no push", () => {
    const l = new LeitorRespostaSmtp();
    expect(() => l.push("x".repeat(100 * 1024))).toThrow(SmtpProtocolError);
  });
});

describe("R16_SMTP_PROTOCOL_AUDIT — classificação 4xx/5xx", () => {
  it("2xx e 3xx são sucesso/intermediário", () => {
    expect(classificarResposta({ code: 250, classe: 2, linhas: [] })).toBe("ok");
    expect(classificarResposta({ code: 354, classe: 3, linhas: [] })).toBe("ok");
  });

  it("4xx é temporário", () => {
    expect(classificarResposta({ code: 421, classe: 4, linhas: [] })).toBe("temporario");
    expect(classificarResposta({ code: 451, classe: 4, linhas: [] })).toBe("temporario");
  });

  it("5xx é permanente", () => {
    expect(classificarResposta({ code: 550, classe: 5, linhas: [] })).toBe("permanente");
    expect(classificarResposta({ code: 552, classe: 5, linhas: [] })).toBe("permanente");
  });

  it("erro de parser NÃO vira classificação 4xx/5xx", () => {
    // Bug de protocolo é SmtpProtocolError, não resposta do servidor: o
    // dispatchOutbox não deve tratá-lo como recusa temporária do destino.
    const l = new LeitorRespostaSmtp();
    l.push("lixo\r\n");
    expect(() => l.proxima()).toThrow(SmtpProtocolError);
  });
});

describe("R16 — payload completo", () => {
  it("inclui cabeçalhos obrigatórios e corpo", () => {
    const p = montarPayloadData(CABECALHOS, "Ola mundo");
    expect(p).toContain("From: BDFlow <nao-responda@bdflow.com.br>\r\n");
    expect(p).toContain("To: destino@teste.com.br\r\n");
    expect(p).toContain("Subject: Confirme seu e-mail\r\n");
    expect(p).toContain("\r\n\r\nOla mundo");
  });

  it("versão HTML usa multipart e mantém o terminador único", () => {
    const p = montarPayloadData(CABECALHOS, "texto puro", "<p>html</p>");
    expect(p).toContain("multipart/alternative");
    expect(p).toContain("text/plain");
    expect(p).toContain("text/html");
    expect(contarTerminadoresPrematuros(p)).toBe(0);
    expect(p.endsWith(TERMINADOR_DATA)).toBe(true);
  });

  it("corpo com LF puro sai normalizado em CRLF", () => {
    const p = montarPayloadData(CABECALHOS, "linha1\nlinha2");
    expect(p).toContain("linha1\r\nlinha2");
    expect(p).not.toMatch(/[^\r]\n/);
  });
});
