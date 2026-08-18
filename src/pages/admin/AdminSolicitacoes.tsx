import { useCallback, useEffect, useState } from "react";
import Header from "../../components/Header";
import {
  listarSolicitacoesAdmin,
  analisarEmpresa,
  analisarAutoridade,
  solicitarCorrecao,
  decidirSolicitacao,
  mensagemDeMotivo,
  type SolicitacaoAdmin,
} from "../../services/partnerApplicationService";

/**
 * /admin/solicitacoes — fundação administrativa da análise.
 *
 * Toda ação sensível é autorizada SERVER-SIDE (is_site_admin no banco).
 * Esta tela não esconde botões para "proteger": se um não-admin chamar a
 * RPC diretamente, o backend recusa. A UI apenas reflete o resultado.
 */
export default function AdminSolicitacoes() {
  const [itens, setItens] = useState<SolicitacaoAdmin[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<string>("under_review");

  const carregar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    const r = await listarSolicitacoesAdmin(filtro || undefined);
    setCarregando(false);
    if (!r.ok) { setErro(mensagemDeMotivo(r.motivo)); setItens([]); return; }
    setItens(r.dados.items ?? []);
  }, [filtro]);

  useEffect(() => { void carregar(); }, [carregar]);

  const agir = async (id: string, acao: () => Promise<{ ok: boolean; motivo?: string }>) => {
    setOcupado(id);
    setErro(null);
    const r = (await acao()) as { ok: boolean; motivo?: string };
    setOcupado(null);
    if (!r.ok) { setErro(mensagemDeMotivo(r.motivo ?? "rpc_error")); return; }
    await carregar();
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <h1 className="text-3xl">
          Solicitações de parceria
          <span className="mt-3 block h-2 w-24 rounded-full bg-magenta" />
        </h1>

        <div className="mt-6 flex items-center gap-3">
          <label htmlFor="filtro" className="text-sm font-semibold">Situação</label>
          <select
            id="filtro"
            value={filtro}
            onChange={(e) => setFiltro(e.target.value)}
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
          <div role="alert" className="mt-4 rounded-xl bg-red-50 p-4 text-sm text-red-800">{erro}</div>
        ) : null}

        {carregando ? (
          <p className="mt-8 text-sm text-tinta/60" role="status">Carregando...</p>
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
                <p className="mt-1 text-sm text-tinta/60">{s.city} / {s.uf}</p>

                <dl className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
                  <div>
                    <dt className="text-tinta/60">Empresa</dt>
                    <dd className="font-semibold">{s.company_review_status}</dd>
                  </div>
                  <div>
                    <dt className="text-tinta/60">Autoridade do responsável</dt>
                    <dd className="font-semibold">
                      {s.authority_review_status}
                      {s.representative ? ` — ${s.representative.full_name}` : ""}
                    </dd>
                  </div>
                </dl>

                <div className="mt-5 flex flex-wrap gap-2">
                  <button
                    disabled={ocupado === s.application_id}
                    onClick={() => agir(s.application_id, () => analisarEmpresa(s.application_id, "approved"))}
                    className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold"
                  >
                    Aprovar empresa
                  </button>
                  <button
                    disabled={ocupado === s.application_id}
                    onClick={() => agir(s.application_id, () => analisarAutoridade(s.application_id, "approved"))}
                    className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold"
                  >
                    Aprovar autoridade
                  </button>
                  <button
                    disabled={ocupado === s.application_id}
                    onClick={() =>
                      agir(s.application_id, () =>
                        solicitarCorrecao(s.application_id, "documents", "Documentação adicional necessária.")
                      )
                    }
                    className="rounded-xl border border-borda px-3 py-2 text-sm font-semibold"
                  >
                    Pedir correção
                  </button>
                  <button
                    disabled={ocupado === s.application_id}
                    onClick={() => agir(s.application_id, () => decidirSolicitacao(s.application_id, "approved"))}
                    className="btn-primary px-3 py-2 text-sm"
                  >
                    Aprovar solicitação
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </main>
    </>
  );
}
