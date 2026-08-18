import { useCallback, useEffect, useState } from "react";
import Header from "../../components/Header";
import {
  listarSolicitacoesAdmin,
  obterDetalheAdmin,
  analisarEmpresa,
  analisarAutoridade,
  substituirRepresentante,
  solicitarCorrecao,
  revisarDocumento,
  decidirSolicitacao,
  abrirReconsideracao,
  urlAssinadaDocumento,
  mensagemDeMotivo,
  type SolicitacaoAdmin,
  type DetalheAdmin,
} from "../../services/partnerApplicationService";

/**
 * /admin/solicitacoes — fundação administrativa da análise.
 *
 * A autoridade é INTEIRAMENTE do backend: `is_site_admin()` no banco decide,
 * e as invariantes (aprovação exige as duas análises, estado revisável,
 * motivo obrigatório na rejeição) vivem em constraints e RPCs. Esta tela não
 * reproduz nem antecipa essas regras: ela tenta a ação e mostra com
 * segurança o que o servidor responder.
 */

const ROTULOS_STATUS: Record<string, string> = {
  pending_email_verification: "Aguardando e-mail",
  pending_account_setup: "Aguardando acesso",
  under_review: "Em análise",
  changes_requested: "Correções solicitadas",
  approved: "Aprovada",
  rejected: "Não aprovada",
  withdrawn: "Cancelada",
};

const ROTULOS_ANALISE: Record<string, string> = {
  pending: "Pendente",
  approved: "Aprovada",
  rejected: "Não aprovada",
  changes_requested: "Correção solicitada",
};

export default function AdminSolicitacoes() {
  const [itens, setItens] = useState<SolicitacaoAdmin[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<string>("under_review");
  const [abertaId, setAbertaId] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    const r = await listarSolicitacoesAdmin(filtro || undefined);
    setCarregando(false);
    if (!r.ok) {
      setErro(mensagemDeMotivo(r.motivo));
      setItens([]);
      return;
    }
    setItens(r.dados.items ?? []);
  }, [filtro]);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <h1 className="text-3xl">
          Solicitações de parceria
          <span className="mt-3 block h-2 w-24 rounded-full bg-magenta" />
        </h1>

        <div className="mt-6 flex items-center gap-3">
          <label htmlFor="filtro" className="text-sm font-semibold">
            Situação
          </label>
          <select
            id="filtro"
            value={filtro}
            onChange={(e) => {
              setFiltro(e.target.value);
              setAbertaId(null);
            }}
            className="rounded-xl border border-borda px-3 py-2"
          >
            <option value="">Todas</option>
            <option value="under_review">Em análise</option>
            <option value="changes_requested">Correções solicitadas</option>
            <option value="approved">Aprovadas</option>
            <option value="rejected">Não aprovadas</option>
          </select>
        </div>

        {erro ? (
          <div role="alert" className="mt-4 rounded-xl bg-red-50 p-4 text-sm text-red-800">
            {erro}
          </div>
        ) : null}

        {carregando ? (
          <p className="mt-8 text-sm text-tinta/60" role="status">
            Carregando...
          </p>
        ) : itens.length === 0 ? (
          <p className="mt-8 text-sm text-tinta/60">Nenhuma solicitação nesta situação.</p>
        ) : (
          <ul className="mt-6 space-y-4">
            {itens.map((s) => (
              <li key={s.application_id} className="card p-6">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <h2 className="text-lg font-bold">{s.legal_name}</h2>
                  <span className="text-sm text-tinta/60">{s.cnpj}</span>
                </div>
                <p className="mt-1 text-sm text-tinta/60">
                  {s.city} / {s.uf} · {ROTULOS_STATUS[s.status] ?? s.status}
                </p>
                <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
                  <div>
                    <dt className="text-tinta/60">Empresa</dt>
                    <dd className="font-semibold">
                      {ROTULOS_ANALISE[s.company_review_status] ?? s.company_review_status}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-tinta/60">Autoridade do responsável</dt>
                    <dd className="font-semibold">
                      {ROTULOS_ANALISE[s.authority_review_status] ?? s.authority_review_status}
                      {s.representative ? ` — ${s.representative.full_name}` : ""}
                    </dd>
                  </div>
                </dl>

                <button
                  type="button"
                  onClick={() =>
                    setAbertaId((atual) => (atual === s.application_id ? null : s.application_id))
                  }
                  className="mt-4 rounded-xl border border-borda px-3 py-2 text-sm font-semibold"
                  aria-expanded={abertaId === s.application_id}
                >
                  {abertaId === s.application_id ? "Fechar" : "Abrir solicitação"}
                </button>

                {abertaId === s.application_id ? (
                  <Detalhe applicationId={s.application_id} aoMudar={carregar} />
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </main>
    </>
  );
}

function Detalhe({ applicationId, aoMudar }: { applicationId: string; aoMudar: () => Promise<void> }) {
  const [detalhe, setDetalhe] = useState<DetalheAdmin | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [mensagemCorrecao, setMensagemCorrecao] = useState("");
  const [escopo, setEscopo] = useState("documents");

  const carregar = useCallback(async () => {
    const r = await obterDetalheAdmin(applicationId);
    if (!r.ok) {
      setErro(mensagemDeMotivo(r.motivo));
      return;
    }
    setErro(null);
    setDetalhe(r.dados);
  }, [applicationId]);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const agir = async (acao: () => Promise<{ ok: boolean; motivo?: string }>) => {
    if (ocupado) return;
    setOcupado(true);
    setErro(null);
    const r = (await acao()) as { ok: boolean; motivo?: string };
    setOcupado(false);
    if (!r.ok) {
      setErro(mensagemDeMotivo(r.motivo ?? "rpc_error"));
      return;
    }
    await carregar();
    await aoMudar();
  };

  const abrirDocumento = async (caminho: string) => {
    const url = await urlAssinadaDocumento(caminho);
    if (!url) {
      setErro("Não foi possível abrir o documento agora.");
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  };

  if (!detalhe) {
    return (
      <p className="mt-4 text-sm text-tinta/60" role="status">
        {erro ?? "Carregando detalhes..."}
      </p>
    );
  }

  const app = detalhe.aplicacao as Record<string, string | null>;
  const repAtual = detalhe.representantes.find((r) => r.is_current) as
    | Record<string, string>
    | undefined;

  return (
    <div className="mt-5 space-y-6 rounded-2xl border border-borda p-5">
      {erro ? (
        <div role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">
          {erro}
        </div>
      ) : null}

      <section>
        <h3 className="font-bold">Empresa</h3>
        <dl className="mt-2 grid gap-1 text-sm sm:grid-cols-2">
          <Item rotulo="Razão social" valor={app.legal_name} />
          <Item rotulo="Nome fantasia" valor={app.trade_name} />
          <Item rotulo="CNPJ" valor={app.cnpj} />
          <Item rotulo="E-mail" valor={app.contact_email} />
          <Item rotulo="Cidade/UF" valor={`${app.city} / ${app.uf}`} />
          <Item rotulo="Estado" valor={ROTULOS_STATUS[app.status ?? ""] ?? app.status} />
          <Item rotulo="Reconsideração" valor={String(app.reconsideration_count ?? "0")} />
          <Item rotulo="Motivo da decisão" valor={app.decision_reason} />
        </dl>
        <div className="mt-3 flex flex-wrap gap-2">
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => analisarEmpresa(applicationId, "approved"))}
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Aprovar empresa
          </button>
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => analisarEmpresa(applicationId, "rejected", motivo))}
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Rejeitar empresa
          </button>
        </div>
      </section>

      <section>
        <h3 className="font-bold">Responsável</h3>
        {repAtual ? (
          <dl className="mt-2 grid gap-1 text-sm sm:grid-cols-2">
            <Item rotulo="Nome" valor={repAtual.full_name} />
            <Item rotulo="E-mail" valor={repAtual.email} />
            <Item rotulo="Autoridade" valor={ROTULOS_ANALISE[repAtual.authority_status] ?? repAtual.authority_status} />
          </dl>
        ) : (
          <p className="mt-2 text-sm text-tinta/60">Sem representante corrente.</p>
        )}
        <div className="mt-3 flex flex-wrap gap-2">
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => analisarAutoridade(applicationId, "approved"))}
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Aprovar autoridade
          </button>
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => analisarAutoridade(applicationId, "rejected", motivo))}
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Rejeitar autoridade
          </button>
          <button type="button" disabled={ocupado}
            onClick={() =>
              void agir(() =>
                substituirRepresentante(applicationId, {
                  full_name: "", cpf: "", email: "",
                })
              )
            }
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Substituir representante
          </button>
        </div>
        <p className="mt-2 text-xs text-tinta/50">
          A substituição exige os dados do novo responsável; o servidor recusa
          dados incompletos e estados não revisáveis.
        </p>
      </section>

      <section>
        <h3 className="font-bold">Documentos</h3>
        {detalhe.documentos.length === 0 ? (
          <p className="mt-2 text-sm text-tinta/60">Nenhum documento enviado.</p>
        ) : (
          <ul className="mt-2 space-y-2">
            {detalhe.documentos.map((d) => (
              <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-borda px-3 py-2 text-sm">
                <span>
                  {d.doc_type} · {d.original_filename} · {d.review_status}
                  {d.superseded_at ? " · substituído" : ""}
                </span>
                <span className="flex gap-2">
                  <button type="button" onClick={() => void abrirDocumento(d.storage_path)}
                    className="rounded-lg border border-borda px-2 py-1 font-semibold">
                    Abrir
                  </button>
                  <button type="button" disabled={ocupado}
                    onClick={() => void agir(() => revisarDocumento(d.id, "accepted"))}
                    className="rounded-lg border border-borda px-2 py-1 font-semibold">
                    Aceitar
                  </button>
                  <button type="button" disabled={ocupado}
                    onClick={() => void agir(() => revisarDocumento(d.id, "rejected", motivo))}
                    className="rounded-lg border border-borda px-2 py-1 font-semibold">
                    Recusar
                  </button>
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <h3 className="font-bold">Correções</h3>
        {detalhe.correcoes.length === 0 ? (
          <p className="mt-2 text-sm text-tinta/60">Nenhuma correção registrada.</p>
        ) : (
          <ul className="mt-2 space-y-2 text-sm">
            {detalhe.correcoes.map((c) => (
              <li key={c.id} className="rounded-xl border border-borda px-3 py-2">
                <p className="font-semibold">{c.scope}</p>
                <p>{c.message}</p>
                {c.response_message ? (
                  <p className="mt-1 text-tinta/70">Resposta: {c.response_message}</p>
                ) : (
                  <p className="mt-1 text-tinta/50">Sem resposta.</p>
                )}
              </li>
            ))}
          </ul>
        )}
        <div className="mt-3">
          <label htmlFor="corr-msg" className="mb-1.5 block text-sm font-semibold">
            Solicitar correção
          </label>
          <select value={escopo} onChange={(e) => setEscopo(e.target.value)}
            aria-label="Escopo da correção"
            className="mb-2 w-full rounded-xl border border-borda px-3 py-2 text-sm">
            <option value="company">Dados da empresa</option>
            <option value="authority">Responsável</option>
            <option value="documents">Documentos</option>
          </select>
          <textarea id="corr-msg" rows={2} value={mensagemCorrecao}
            onChange={(e) => setMensagemCorrecao(e.target.value)}
            className="w-full rounded-xl border border-borda px-3 py-2 text-sm" />
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => solicitarCorrecao(applicationId, escopo, mensagemCorrecao))}
            className="mt-2 rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Enviar pedido de correção
          </button>
        </div>
      </section>

      <section>
        <h3 className="font-bold">Decisão</h3>
        <label htmlFor="motivo" className="mb-1.5 mt-2 block text-sm font-semibold">
          Motivo (obrigatório na rejeição)
        </label>
        <textarea id="motivo" rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)}
          className="w-full rounded-xl border border-borda px-3 py-2 text-sm" />
        <div className="mt-3 flex flex-wrap gap-2">
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => decidirSolicitacao(applicationId, "approved"))}
            className="btn-primary px-3 py-2 text-sm">
            Aprovar solicitação
          </button>
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => decidirSolicitacao(applicationId, "rejected", motivo))}
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Rejeitar solicitação
          </button>
          <button type="button" disabled={ocupado}
            onClick={() => void agir(() => abrirReconsideracao(applicationId))}
            className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold">
            Abrir reconsideração
          </button>
        </div>
      </section>
    </div>
  );
}

function Item({ rotulo, valor }: { rotulo: string; valor: string | null | undefined }) {
  return (
    <div>
      <dt className="text-tinta/60">{rotulo}</dt>
      <dd>{valor && valor !== "" ? valor : "—"}</dd>
    </div>
  );
}
