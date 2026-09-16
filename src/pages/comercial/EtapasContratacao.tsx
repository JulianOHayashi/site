import { useCallback, useEffect, useRef, useState } from "react";
import {
  aceitarTermos,
  avancarParaContrato,
  criarPagamento,
  ehFalha,
  ehTerminal,
  finalizarPedido,
  lerEstadoPagamento,
  obterTermosVigentes,
  type Pagamento,
  type TermosVigentes,
} from "../../services/commercialContractService";

/**
 * Etapas de contrato e pagamento do /checkout.
 *
 * TODA autoridade é do servidor. A tela exibe o que as RPCs e o endpoint
 * devolveram e nada mais: não calcula preço, não deriva método, não conta o
 * prazo com relógio próprio e não conclui pagamento por parâmetro de URL.
 *
 * DOIS ESTADOS BLOQUEADOS, DE PROPÓSITO
 * Sem termos publicados e sem acordo mestre vigente, a tela para e explica.
 * Nenhum dos dois é contornável daqui — o backend também recusa —, e
 * fabricar texto de contrato ou acordo seria exatamente o que o projeto
 * proíbe.
 */

const BRL = (centavos: number) =>
  (centavos / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

type Fase =
  | { f: "carregando" }
  | { f: "sem_termos" }
  | { f: "termos"; termos: Extract<TermosVigentes, { tipo: "publicados" }> }
  | { f: "pagamento"; pagamento: Pagamento }
  | { f: "bloqueado"; codigo: string };

export default function EtapasContratacao(props: {
  intentId: string;
  /** Total contratual autoritativo, vindo da reserva. */
  amountCents: number;
  fidelizado: boolean;
}) {
  const { intentId, amountCents, fidelizado } = props;
  const [fase, setFase] = useState<Fase>({ f: "carregando" });
  const [aceito, setAceito] = useState(false);
  const [parcelas, setParcelas] = useState(1);
  const [ocupado, setOcupado] = useState(false);
  const [falha, setFalha] = useState<string | null>(null);
  const [copiado, setCopiado] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    void (async () => {
      const t = await obterTermosVigentes();
      setFase(t.tipo === "ausentes" ? { f: "sem_termos" } : { f: "termos", termos: t });
    })();
  }, []);

  // Consulta de estado: para em estado terminal, sempre a partir do banco.
  const acompanhar = useCallback((paymentId: string) => {
    const tick = async () => {
      const r = await lerEstadoPagamento(paymentId);
      if (ehFalha(r)) return;
      const status = String(r.status);
      setFase((atual) =>
        atual.f === "pagamento"
          ? { f: "pagamento", pagamento: { ...atual.pagamento, status } }
          : atual
      );
      if (!ehTerminal(status)) timer.current = setTimeout(() => void tick(), 5000);
    };
    timer.current = setTimeout(() => void tick(), 5000);
  }, []);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    []
  );

  const contratarEPagar = async () => {
    if (!aceito || ocupado) return;
    setOcupado(true);
    setFalha(null);

    const etapas = [
      () => avancarParaContrato(intentId),
      () => aceitarTermos(intentId),
      () => finalizarPedido(intentId),
    ];
    let pedido: Record<string, unknown> | null = null;
    for (const etapa of etapas) {
      const r = await etapa();
      if (ehFalha(r)) {
        setOcupado(false);
        // Acordo mestre ausente é bloqueio, não erro de formulário.
        if (r.codigo === "master_agreement_missing") {
          setFase({ f: "bloqueado", codigo: r.codigo });
          return;
        }
        setFalha(r.codigo);
        return;
      }
      pedido = r;
    }

    const orderId = String(pedido?.order_id ?? "");
    const p = await criarPagamento({
      orderId,
      ...(fidelizado ? { installments: parcelas } : {}),
    });
    setOcupado(false);
    if (p.tipo === "erro") {
      setFalha(p.codigo);
      return;
    }
    setFase({ f: "pagamento", pagamento: p.pagamento });
    acompanhar(p.pagamento.paymentId);
  };

  if (fase.f === "carregando") {
    return (
      <p role="status" className="mt-6 text-sm text-tinta/60">
        Carregando os termos da contratação...
      </p>
    );
  }

  if (fase.f === "sem_termos") {
    return (
      <div role="alert" className="card mt-6 p-6">
        <h3 className="font-bold">Contratação indisponível no momento</h3>
        <p className="mt-2 text-sm text-tinta/70">
          Os termos do pedido comercial ainda não foram publicados. Sem o
          documento vigente não é possível contratar, e nenhum valor foi
          cobrado.
        </p>
      </div>
    );
  }

  if (fase.f === "bloqueado") {
    return (
      <div role="alert" className="card mt-6 p-6">
        <h3 className="font-bold">Contrato-quadro pendente</h3>
        <p className="mt-2 text-sm text-tinta/70">
          Sua empresa ainda não possui contrato-quadro assinado e registrado.
          Ele é exigido antes de qualquer pedido. Fale com a BDFlow para
          concluir essa etapa. Nenhum valor foi cobrado.
        </p>
      </div>
    );
  }

  if (fase.f === "pagamento") {
    const p = fase.pagamento;
    const pago = p.status === "paid";
    return (
      <section className="card mt-6 space-y-3 p-6" aria-labelledby="pg-titulo">
        <h3 id="pg-titulo" className="text-lg font-bold">
          {pago
            ? "Pagamento confirmado"
            : p.status === "expired"
              ? "Prazo encerrado"
              : p.status === "late_unreconciled"
                ? "Pagamento em conferência"
                : "Aguardando pagamento"}
        </h3>

        {pago && (
          // Confirmado pelo ESTADO LOCAL, depois da conciliação com o
          // provedor. Retorno do provedor por si só nunca confirma nada.
          <p className="text-sm text-tinta/70">
            Recebemos a confirmação do pagamento de {BRL(p.amountCents)} e a
            exclusividade está contratada.
          </p>
        )}

        {p.status === "expired" && (
          <p className="text-sm text-tinta/70">
            O prazo da reserva terminou sem confirmação de pagamento. A
            oportunidade voltou a ficar disponível e é preciso reservá-la
            novamente. Seu histórico de contratação foi preservado.
          </p>
        )}

        {p.status === "late_unreconciled" && (
          // Nem "falhou" nem "contratado": conferência manual.
          <p className="text-sm text-tinta/70">
            Recebemos uma confirmação do provedor após o prazo. A BDFlow vai
            conferir manualmente e entrar em contato. A exclusividade não foi
            contratada automaticamente.
          </p>
        )}

        {!ehTerminal(p.status) && p.paymentMethod === "pix" && (
          <div className="space-y-3">
            <p className="text-sm text-tinta/70">
              Pague {BRL(p.amountCents)} por Pix até{" "}
              <strong>{new Date(p.expiresAt).toLocaleString("pt-BR")}</strong>.
            </p>
            {p.pixQrCodeUrl && (
              <img
                src={p.pixQrCodeUrl}
                alt="QR Code do Pix"
                className="mx-auto h-48 w-48"
              />
            )}
            {p.pixCopyPaste && (
              <>
                <code className="block break-all rounded-xl bg-tinta/5 p-3 text-xs">
                  {p.pixCopyPaste}
                </code>
                <button
                  type="button"
                  onClick={() => {
                    void navigator.clipboard?.writeText(p.pixCopyPaste as string);
                    setCopiado(true);
                  }}
                  className="btn-secondary w-full"
                >
                  {copiado ? "Código copiado" : "Copiar código Pix"}
                </button>
              </>
            )}
            <p className="text-xs text-tinta/50" role="status">
              Status: aguardando confirmação do pagamento.
            </p>
          </div>
        )}

        {!ehTerminal(p.status) && p.paymentMethod === "credit_card" && p.checkoutUrl && (
          <a href={p.checkoutUrl} className="btn-primary block w-full text-center">
            Abrir checkout seguro do cartão
          </a>
        )}
      </section>
    );
  }

  // ---- termos publicados: exibir, aceitar, contratar
  const t = fase.termos;
  return (
    <section className="card mt-6 space-y-4 p-6" aria-labelledby="termos-titulo">
      <div>
        <h3 id="termos-titulo" className="text-lg font-bold">
          {t.title}
        </h3>
        <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
          Versão {t.version}
        </p>
      </div>

      {t.content ? (
        <div className="max-h-64 overflow-y-auto rounded-xl bg-tinta/5 p-4 text-sm whitespace-pre-wrap">
          {t.content}
        </div>
      ) : t.contentUrl ? (
        <a href={t.contentUrl} className="text-sm underline" target="_blank" rel="noreferrer">
          Ler os termos completos
        </a>
      ) : null}

      <label className="flex items-start gap-3 text-sm">
        <input
          type="checkbox"
          checked={aceito}
          onChange={(e) => setAceito(e.target.checked)}
          className="mt-1"
        />
        <span>
          Li e aceito os termos do pedido comercial, versão {t.version}.
        </span>
      </label>

      {fidelizado && (
        <fieldset className="space-y-2">
          <legend className="text-sm font-semibold">Parcelamento no cartão</legend>
          {[1, 2, 3, 4, 5, 6].map((n) => (
            <label key={n} className="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="parcelas"
                value={n}
                checked={parcelas === n}
                onChange={() => setParcelas(n)}
              />
              <span>
                {n}x de {BRL(Math.round(amountCents / n))}
                {n > 1 ? " sem juros" : ""}
              </span>
            </label>
          ))}
          {/* O total exibido é SEMPRE o contratual: o parcelamento divide,
              nunca acrescenta. O custo do provedor é da BDFlow. */}
          <p className="text-sm font-semibold">Total: {BRL(amountCents)}</p>
        </fieldset>
      )}

      <button
        onClick={contratarEPagar}
        disabled={!aceito || ocupado}
        className="btn-primary w-full disabled:opacity-50"
      >
        {ocupado ? "Processando..." : "Aceitar e ir para o pagamento"}
      </button>

      {falha && (
        <div role="alert" className="rounded-xl bg-magenta/10 p-3 text-sm text-magenta">
          {falha === "reservation_expired"
            ? "O prazo da reserva terminou. Reserve a oportunidade novamente."
            : falha === "terms_not_published"
              ? "Os termos do pedido ainda não foram publicados."
              : falha === "not_company_owner"
                ? "Apenas o responsável da empresa pode contratar."
                : "Não foi possível concluir agora. Nenhum valor foi cobrado."}
        </div>
      )}
    </section>
  );
}
