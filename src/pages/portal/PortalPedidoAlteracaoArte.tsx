import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import { EmpresaAtualBarra, EmpresaPortao } from "../../portal/EmpresaSeletor";
import { SemAcesso } from "./PortalPedidos";
import { formatarCentavos } from "../../domain/pricing/contractPricing";
import { ACCEPT_ATTR, MENSAGEM_ARQUIVO, validarArquivo } from "../../services/customizationImageService";
import {
  ROTULO_NAO_INCLUIDO,
  ROTULO_STATUS,
  aceitarOrcamento,
  urlDocumentoFornecedor,
  type DocumentoFornecedor,
  cancelarSolicitacao,
  criarSolicitacao,
  enviarArte,
  enviarParaAnalise,
  estaAberta,
  listarSolicitacoes,
  mensagemArte,
  type AlvoCampanha,
  type ListaSolicitacoes,
  type SolicitacaoArte,
} from "../../services/artworkChangeService";

/**
 * /portal/pedidos/:orderId/alteracao-arte — solicitação de alteração de
 * frase ou arte (R4.2). Não troca a arte em execução: a nova arte vale na
 * próxima campanha, ou na atual só por exceção aprovada pela SmallFlags.
 * O custo ao parceiro é o custo comprovado do fornecedor, sem margem, e só
 * existe depois do orçamento registrado pela SmallFlags. A fidelidade não
 * muda por causa da alteração.
 */
export default function PortalPedidoAlteracaoArte() {
  const { orderId = "" } = useParams();
  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Alteração de frase ou arte" />
        <EmpresaAtualBarra />
        <EmpresaPortao semVinculo={<SemAcesso />}>
          {({ companyId, geracao }) => <Alteracao key={`${companyId}:${geracao}:${orderId}`} orderId={orderId} />}
        </EmpresaPortao>
      </main>
    </>
  );
}

type Carga =
  | { fase: "carregando" }
  | { fase: "erro"; mensagem: string }
  | { fase: "ok"; lista: ListaSolicitacoes };

function Alteracao({ orderId }: { orderId: string }) {
  const empresa = useEmpresaSelecionada();
  const ativo = empresa.fase === "pronta" && empresa.atual.member_status === "active";
  const [carga, setCarga] = useState<Carga>({ fase: "carregando" });
  const [aviso, setAviso] = useState<{ tipo: "ok" | "erro"; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const vivo = useRef(true);
  useEffect(() => {
    vivo.current = true;
    return () => {
      vivo.current = false;
    };
  }, []);

  const carregar = useCallback(async () => {
    const r = await listarSolicitacoes(orderId);
    if (!vivo.current) return;
    setCarga(r.tipo === "ok" ? { fase: "ok", lista: r.valor } : { fase: "erro", mensagem: mensagemArte(r.motivo) });
  }, [orderId]);
  useEffect(() => {
    if (ativo) void carregar();
  }, [ativo, carregar]);

  const executar = async (acao: () => Promise<{ tipo: "ok" } | { tipo: "erro"; motivo: string }>, sucesso: string) => {
    if (ocupado) return;
    setOcupado(true);
    setAviso(null);
    const r = await acao();
    if (!vivo.current) return;
    setOcupado(false);
    setAviso(r.tipo === "ok" ? { tipo: "ok", texto: sucesso } : { tipo: "erro", texto: mensagemArte(r.motivo) });
    await carregar();
  };

  if (!ativo) return <SemAcesso />;
  if (carga.fase === "carregando") {
    return <p role="status" className="mt-10 text-center text-sm text-tinta/60">Carregando solicitações...</p>;
  }
  if (carga.fase === "erro") {
    return <p role="alert" className="aviso-erro mt-8 p-4">{carga.mensagem}</p>;
  }
  const { lista } = carga;
  const aberta = lista.solicitacoes.find(estaAberta) ?? null;
  const owner = lista.podeSolicitar;

  return (
    <div className="mt-8 space-y-6">
      <section className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8" data-testid="regras-alteracao">
        <h2 className="text-lg font-bold">Como funciona</h2>
        <ul className="mt-3 list-disc space-y-1 pl-5 text-sm leading-6 text-tinta/75">
          <li>A arte em uso continua valendo até a nova ser aplicada. A solicitação não troca a arte agora.</li>
          <li>A nova arte vale, em regra, na <strong>próxima campanha</strong>. Na campanha atual, só com autorização extraordinária da SmallFlags.</li>
          <li>Trocar a frase ou a arte não muda a condição de anunciante fidelizado nem o valor da contratação.</li>
          <li>A produção da nova arte é cobrada à parte, pelo custo comprovado do fornecedor, sem margem. O valor só existe depois do orçamento e só vale com o seu aceite.</li>
          <li>Frete, criação de arte, instalação, tributos e outros serviços não estão incluídos nem autorizados automaticamente.</li>
        </ul>
        {!owner && (
          <p className="mt-3 text-sm font-semibold text-tinta/80" data-testid="somente-owner">
            Somente o responsável pela empresa solicita a alteração e aceita o orçamento.
          </p>
        )}
      </section>

      <div aria-live="polite">
        {aviso && (
          <p role={aviso.tipo === "ok" ? "status" : "alert"} className={`${aviso.tipo === "ok" ? "aviso-ok" : "aviso-erro"} p-3 text-sm`}>
            {aviso.texto}
          </p>
        )}
      </div>

      {owner && !aberta && (
        <NovaSolicitacao
          ocupado={ocupado}
          onCriar={(alvo, frase) => executar(async () => {
            const r = await criarSolicitacao(orderId, alvo, frase);
            return r.tipo === "ok" ? { tipo: "ok" } : r;
          }, "Solicitação aberta. Envie a arte para continuar.")}
        />
      )}

      {lista.solicitacoes.map((s) => (
        <CartaoSolicitacao key={s.requestId} s={s} owner={owner} ocupado={ocupado} executar={executar} />
      ))}

      <Link to="/portal/pedidos" className="btn-secondary inline-flex">Voltar aos pedidos</Link>
    </div>
  );
}

function NovaSolicitacao({ ocupado, onCriar }: { ocupado: boolean; onCriar: (alvo: AlvoCampanha, frase: string) => void }) {
  const [alvo, setAlvo] = useState<AlvoCampanha>("next_campaign");
  const [frase, setFrase] = useState("");
  return (
    <section className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8" aria-labelledby="nova-titulo">
      <h2 id="nova-titulo" className="text-lg font-bold">Solicitar alteração de frase ou arte</h2>
      <label htmlFor="frase-nova" className="mt-4 block text-sm font-semibold">Nova frase (opcional)</label>
      <textarea id="frase-nova" maxLength={280} value={frase} onChange={(e) => setFrase(e.target.value)}
        className="mt-2 block w-full rounded-xl border border-borda p-3 text-sm" rows={2} />
      <fieldset className="mt-4">
        <legend className="text-sm font-semibold">Quando a nova arte deve valer</legend>
        <label className="mt-2 flex items-center gap-2 text-sm">
          <input type="radio" name="alvo" checked={alvo === "next_campaign"} onChange={() => setAlvo("next_campaign")} />
          Na próxima campanha
        </label>
        <label className="mt-1 flex items-center gap-2 text-sm">
          <input type="radio" name="alvo" checked={alvo === "current_campaign"} onChange={() => setAlvo("current_campaign")} />
          Na campanha atual (depende de autorização extraordinária da SmallFlags)
        </label>
      </fieldset>
      <button type="button" className="btn-primary mt-5 disabled:opacity-60" disabled={ocupado}
        onClick={() => onCriar(alvo, frase)}>
        Abrir solicitação
      </button>
    </section>
  );
}

/** Documento original do fornecedor: link temporário do bucket privado. */
async function abrirDocumento(doc: DocumentoFornecedor): Promise<void> {
  const r = await urlDocumentoFornecedor(doc);
  if (r.tipo === "ok") window.open(r.valor, "_blank", "noopener,noreferrer");
}

type Executar = (acao: () => Promise<{ tipo: "ok" } | { tipo: "erro"; motivo: string }>, sucesso: string) => Promise<void>;

function CartaoSolicitacao({ s, owner, ocupado, executar }: { s: SolicitacaoArte; owner: boolean; ocupado: boolean; executar: Executar }) {
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [erroArquivo, setErroArquivo] = useState<string | null>(null);
  const [concordo, setConcordo] = useState(false);
  const [motivo, setMotivo] = useState("");
  const podeEnviarArte = owner && ["draft", "submitted", "under_review", "quoted"].includes(s.status);
  const q = s.orcamento;

  return (
    <section className="rounded-3xl border border-borda bg-superficie p-6 sm:p-8" data-testid={`solicitacao-${s.status}`}>
      <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
        {s.alvo === "next_campaign" ? "Próxima campanha" : "Campanha atual (exceção)"}
      </p>
      <h3 className="mt-1 text-lg font-bold">{ROTULO_STATUS[s.status]}</h3>
      {s.frase && <p className="mt-2 text-sm text-tinta/75">Frase: “{s.frase}”</p>}
      <p className="mt-2 text-sm text-tinta/65">Versões de arte enviadas: {s.versoes.length}</p>
      {s.alvo === "current_campaign" && (
        <p className="mt-2 text-sm text-tinta/75" data-testid="excecao">
          {s.excecaoAprovada
            ? "Autorização extraordinária registrada pela SmallFlags."
            : "Aguardando decisão da SmallFlags sobre a exceção para a campanha atual."}
        </p>
      )}

      {q && q.status !== "superseded" && (
        <div className="mt-4 rounded-2xl border border-borda p-4" data-testid="orcamento">
          <p className="text-sm font-semibold">Orçamento do fornecedor nº {q.numero}</p>
          <dl className="mt-2 grid grid-cols-1 gap-1 text-sm sm:grid-cols-2">
            <dt className="text-tinta/65">Fornecedor</dt><dd>{q.fornecedor} · {q.documentoFornecedor}</dd>
            <dt className="text-tinta/65">Escopo</dt><dd>{q.escopo}</dd>
            <dt className="text-tinta/65">Peças</dt><dd>{q.pecas}</dd>
            <dt className="text-tinta/65">Custo total do fornecedor</dt><dd>{formatarCentavos(q.totalFornecedorCentavos)}</dd>
            <dt className="font-semibold">Valor a pagar à parte (sem margem)</dt>
            <dd className="font-semibold" data-testid="valor-parceiro">{formatarCentavos(q.valorParceiroCentavos)}</dd>
            <dt className="text-tinta/65">Teto aprovado</dt><dd>{formatarCentavos(q.tetoCentavos)}</dd>
          </dl>
          <table className="mt-3 w-full text-left text-sm" data-testid="itens-orcamento">
            <caption className="sr-only">Itens do documento do fornecedor</caption>
            <thead className="text-xs text-tinta/65">
              <tr><th className="py-1 font-normal">Item (no documento)</th><th className="py-1 font-normal">Qtd.</th>
                <th className="py-1 font-normal">Unitário</th><th className="py-1 font-normal">Total</th></tr>
            </thead>
            <tbody>
              {q.itens.map((i) => (
                <tr key={i.linha} className="border-t border-borda">
                  <td className="py-1">{i.descricao} <span className="text-tinta/55">({i.localizacaoNoDocumento})</span></td>
                  <td className="py-1">{i.quantidade}</td>
                  <td className="py-1">{formatarCentavos(i.unitarioCentavos)}</td>
                  <td className="py-1">{formatarCentavos(i.totalLinhaCentavos)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="mt-2 break-all text-xs text-tinta/65" data-testid="documento-fornecedor">
            Documento original do fornecedor conferido pelo servidor (SHA-256 {q.documento.sha256}).{" "}
            <button type="button" className="underline" onClick={() => void abrirDocumento(q.documento)}>
              Ver documento
            </button>
          </p>
          <p className="mt-2 text-xs text-tinta/65" data-testid="nao-incluidos">
            Não incluídos: {q.naoIncluidos.map((x) => ROTULO_NAO_INCLUIDO[x] ?? x).join(", ")}.
          </p>
        </div>
      )}

      {s.status === "production_authorized" && (
        <p className="mt-4 text-sm text-tinta/75" data-testid="producao-autorizada">
          Produção autorizada com o valor aceito de {formatarCentavos(s.valorAceitoCentavos ?? 0)}. A cobrança e o
          acompanhamento da produção são feitos pela SmallFlags e ainda não estão disponíveis neste site.
          {!s.pronta && " Enquanto a cobrança e a fabricação não forem registradas, a renovação com a nova arte fica bloqueada."}
        </p>
      )}
      {(s.status === "cancelled" || s.status === "rejected") && s.motivoEncerramento && (
        <p className="mt-3 text-sm text-tinta/65">Motivo: {s.motivoEncerramento}</p>
      )}

      {podeEnviarArte && (
        <div className="mt-5">
          <label htmlFor={`arte-${s.requestId}`} className="block text-sm font-semibold">
            {s.versoes.length ? "Enviar nova versão da arte" : "Enviar a arte"}
          </label>
          {s.status === "quoted" && (
            <p className="mt-1 text-xs text-tinta/65">Uma nova versão cancela o orçamento atual e volta para análise.</p>
          )}
          <input id={`arte-${s.requestId}`} type="file" accept={ACCEPT_ATTR} className="mt-2 block w-full text-sm"
            disabled={ocupado}
            onChange={(e) => {
              const f = e.target.files?.[0] ?? null;
              if (!f) return setArquivo(null);
              const v = validarArquivo(f);
              if (!v.ok) {
                setArquivo(null);
                setErroArquivo(MENSAGEM_ARQUIVO[v.erro]);
              } else {
                setErroArquivo(null);
                setArquivo(f);
              }
            }} />
          {erroArquivo && <p role="alert" className="aviso-erro mt-2 p-2 text-sm">{erroArquivo}</p>}
          <button type="button" className="btn-secondary mt-3 disabled:opacity-60" disabled={!arquivo || ocupado}
            onClick={() => arquivo && executar(() => enviarArte(s.requestId, s.rowVersion, arquivo, s.frase ?? ""), "Arte registrada.")}>
            Enviar arte
          </button>
        </div>
      )}

      {owner && s.status === "draft" && (
        <button type="button" className="btn-primary mt-4 disabled:opacity-60" disabled={ocupado || s.versoes.length === 0}
          onClick={() => executar(() => enviarParaAnalise(s.requestId, s.rowVersion), "Solicitação enviada para análise da SmallFlags.")}>
          Enviar para análise
        </button>
      )}

      {owner && s.status === "quoted" && q?.status === "open" && (
        <div className="mt-4">
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" checked={concordo} onChange={(e) => setConcordo(e.target.checked)} />
            <span>
              Aceito pagar à parte {formatarCentavos(q.valorParceiroCentavos)} pela produção da nova arte, conforme
              o orçamento do fornecedor. Qualquer aumento exigirá novo aceite.
            </span>
          </label>
          <button type="button" className="btn-primary mt-3 disabled:opacity-60" disabled={!concordo || ocupado}
            onClick={() => executar(() => aceitarOrcamento(s), "Orçamento aceito. A SmallFlags vai autorizar a produção.")}>
            Aceitar orçamento
          </button>
        </div>
      )}

      {owner && estaAberta(s) && (
        <div className="mt-5 border-t border-borda pt-4">
          <label htmlFor={`motivo-${s.requestId}`} className="block text-sm font-semibold">Cancelar solicitação</label>
          <input id={`motivo-${s.requestId}`} value={motivo} onChange={(e) => setMotivo(e.target.value)}
            placeholder="Motivo" className="mt-2 block w-full rounded-xl border border-borda p-2 text-sm" />
          <button type="button" className="btn-secondary mt-2 disabled:opacity-60" disabled={motivo.trim().length < 3 || ocupado}
            onClick={() => executar(() => cancelarSolicitacao(s.requestId, s.rowVersion, motivo), "Solicitação cancelada.")}>
            Cancelar solicitação
          </button>
        </div>
      )}
    </section>
  );
}
