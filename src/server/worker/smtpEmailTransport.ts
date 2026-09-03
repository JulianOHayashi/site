/**
 * R16 — ADAPTADOR ENTRE O DESPACHANTE E O TRANSPORTE SMTP CONCRETO.
 *
 * O `dispatchPending` conhece a porta `EmailTransport`. Este arquivo é a
 * única implementação que fala SMTP de verdade, e concentra três decisões que
 * não pertencem nem ao despachante nem ao motor de protocolo:
 *
 *   1. POLÍTICA DE DESTINATÁRIO, aplicada ANTES de o endereço virar envelope.
 *      Em staging, um smoke apontado para o banco real enviaria e-mail a
 *      cliente de verdade. Quando a política nega, o retorno é falha SEM
 *      transmissão — não há destinatário alternativo inventado.
 *
 *   2. RENDERIZAÇÃO, restrita aos três templates com posse atômica. Template
 *      fora do escopo falha fechado aqui também, como segunda barreira.
 *
 *   3. TRADUÇÃO DE DESFECHO para o contrato `SendResult`, preservando na
 *      etiqueta de erro a distinção que o transporte produziu: recusa
 *      temporária do servidor, recusa permanente e falha de transporte são
 *      códigos diferentes e reconhecíveis na coluna de erro.
 *
 * SEGREDO
 * O token cunhado chega em `message.data.token`, entra no corpo e não sai
 * daqui por nenhum outro caminho. Nenhum retorno, log ou erro o carrega.
 */

import type {
  EmailMessage,
  EmailTransport,
  SendResult,
} from "../notifications/emailProvider";
import { renderizar, montarMensagemSmtp, RenderError } from "./emailRenderer";
import { SmtpSerializationError } from "./smtpWire";
import {
  enviarMensagemSmtp,
  classificarParaRetry,
  type OpcoesTransporte,
  type ResultadoTransporte,
} from "./smtpTransport";
import { criarFabricaSocketNode, type FabricaSocket } from "./nodeSmtpSocket";
import {
  aplicarPoliticaDestinatario,
  type WorkerConfig,
} from "./workerConfig";

export const NOME_TRANSPORTE_SMTP = "smtp";

/**
 * Nome anunciado no EHLO, derivado do endereço remetente.
 *
 * Não é configurável de propósito: mais uma variável de ambiente para errar,
 * sem ganho. Se o domínio não puder ser extraído, o envio falha por
 * configuração em vez de anunciar um nome inventado.
 */
export function derivarClientName(fromAddress: string): string {
  const at = fromAddress.lastIndexOf("@");
  const dominio = at >= 0 ? fromAddress.slice(at + 1).trim() : "";
  if (dominio.length === 0 || /[\r\n\0\s]/.test(dominio)) {
    throw new SmtpSerializationError(
      "invalid_from_domain",
      "SMTP_FROM_ADDRESS sem domínio utilizável"
    );
  }
  return dominio;
}

/**
 * Extrai um identificador rastreável da resposta final do servidor.
 *
 * SMTP não define um id de mensagem canônico na resposta; provedores costumam
 * embutir a chave da fila no texto do 250. Ele é útil para rastrear com o
 * provedor, então é preservado — porém sanitizado e limitado, porque é texto
 * arbitrário de terceiro que vai para uma coluna do banco. Sem texto
 * aproveitável, cai para a chave de idempotência, que já existe na linha.
 *
 *   R16_SMTP_PROVIDER_MESSAGE_ID=TEXTO_DA_RESPOSTA_FINAL_SANITIZADO
 */
export function identificadorDeEntrega(
  linhaFinal: string | undefined,
  idempotencyKey: string
): string {
  const limpo = (linhaFinal ?? "")
    // Só imprimíveis ASCII; nada de controle indo para o banco.
    .replace(/[^\x20-\x7E]/g, " ")
    .trim()
    .slice(0, 180);
  return limpo.length > 0 ? `smtp:${limpo}` : `smtp:${idempotencyKey}`;
}

/** Etiqueta de erro que preserva a natureza do desfecho. */
export function etiquetaDeErro(r: ResultadoTransporte): string {
  switch (r.estado) {
    case "enviado":
      return "ok";
    case "recusa_temporaria":
      return `smtp_temporario_${r.codigo}_${r.fase}`;
    case "recusa_permanente":
      return `smtp_permanente_${r.codigo}_${r.fase}`;
    case "falha_transporte":
      return `smtp_transporte_${r.codigo}_${r.fase}`;
  }
}

export type OpcoesTransporteSmtp = {
  config: WorkerConfig;
  /** Injetável para teste; em produção é a fábrica real do Node. */
  fabrica?: FabricaSocket;
  /** Observador de desfecho, já sanitizado. Nunca recebe segredo. */
  aoDesfecho?: (info: {
    outcome: ResultadoTransporte["estado"];
    retry: "ok" | "temporario" | "permanente";
    error_code: string;
  }) => void;
};

/**
 * Cria o transporte SMTP real.
 *
 * A configuração é capturada em campo privado de JavaScript (`#`): o
 * `private` do TypeScript desaparece na compilação e deixaria a senha
 * visível em `JSON.stringify(transporte)` — caminho clássico para segredo em
 * log.
 */
export function criarTransporteSmtp(opcoes: OpcoesTransporteSmtp): EmailTransport {
  const { config } = opcoes;
  const fabrica = opcoes.fabrica ?? criarFabricaSocketNode();

  class TransporteSmtp implements EmailTransport {
    readonly name = NOME_TRANSPORTE_SMTP;
    readonly #config = config;

    /** Serialização segura: jamais inclui configuração ou credencial. */
    toJSON(): { name: string } {
      return { name: this.name };
    }

    async send(message: EmailMessage): Promise<SendResult> {
      const c = this.#config;

      // 1. POLÍTICA DE DESTINATÁRIO — antes de qualquer renderização.
      const decisao = aplicarPoliticaDestinatario(message.to, c.stagingRecipient);
      if (!decisao.enviar) {
        return {
          ok: false,
          provider: this.name,
          errorCode: decisao.motivo,
          errorMessage: "destinatário bloqueado pela política do ambiente",
        };
      }

      // 2. RENDERIZAÇÃO e montagem do payload.
      let payload: string;
      let clientName: string;
      try {
        clientName = derivarClientName(c.smtp.fromAddress);
        const renderizada = renderizar(message.templateKey, message.data, c.siteBaseUrl);
        payload = montarMensagemSmtp(
          decisao.destino,
          c.smtp.fromAddress,
          c.smtp.fromName,
          renderizada
        );
      } catch (e) {
        // Mensagem crua não é propagada: pode conter o token cunhado.
        const codigo =
          e instanceof RenderError || e instanceof SmtpSerializationError
            ? e.code
            : "render_failed";
        return {
          ok: false,
          provider: this.name,
          errorCode: `render_${codigo}`,
          errorMessage: "falha ao montar a mensagem",
        };
      }

      // 3. TRANSMISSÃO.
      const opcoesTransporte: OpcoesTransporte = {
        host: c.smtp.host,
        port: c.smtp.port,
        mode: c.smtp.mode,
        username: c.smtp.username,
        password: c.smtp.password,
        connectTimeoutMs: c.smtp.connectTimeoutMs,
        readTimeoutMs: c.smtp.readTimeoutMs,
        clientName,
      };

      const r = await enviarMensagemSmtp(
        opcoesTransporte,
        { mailFrom: c.smtp.fromAddress, rcptTo: decisao.destino },
        payload,
        fabrica
      );

      const etiqueta = etiquetaDeErro(r);
      opcoes.aoDesfecho?.({
        outcome: r.estado,
        retry: classificarParaRetry(r),
        error_code: etiqueta,
      });

      if (r.estado === "enviado") {
        return {
          ok: true,
          provider: this.name,
          providerMessageId: identificadorDeEntrega(r.linhaFinal, message.idempotencyKey),
        };
      }

      return {
        ok: false,
        provider: this.name,
        errorCode: etiqueta,
        // Texto fixo por desfecho. Nada de servidor nem de corpo aqui.
        errorMessage:
          r.estado === "falha_transporte"
            ? "falha de transporte SMTP"
            : "servidor SMTP recusou a mensagem",
      };
    }
  }

  return new TransporteSmtp();
}
