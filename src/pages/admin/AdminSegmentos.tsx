import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { NICHES } from "../../domain/commercial/niches";
import {
  adminArquivarSegmento,
  adminCarregarSegmentos,
  adminDecidirSolicitacao,
  mensagemSegmento,
  type SegmentoAdmin,
  type SolicitacaoAdmin,
} from "../../services/commercialSegmentService";

/**
 * /admin/segmentos — catálogo de segmentos de Outros e decisão das
 * solicitações de segmento não listado.
 *
 * A autoridade é do backend (`m1_exigir_admin` em cada RPC, auditoria e
 * imutabilidade após decisão). Esta tela tenta a ação e mostra a resposta.
 *
 * CLASSIFICAÇÃO: a chave de classificação é a identidade comercial do
 * segmento — exclusividade e fidelidade usam ela, não o nome. Ao aprovar um
 * pedido que é sinônimo de um segmento existente, vincule ao existente.
 */

const ROTULO_STATUS: Record<string, string> = {
  pending: "Em análise",
  approved: "Aprovada",
  rejected: "Rejeitada",
  cancelled: "Cancelada",
};

const POSICOES_SOBREPONIVEIS = NICHES.filter((n) => n.code !== "others");

function sugerirCodigo(rotulo: string): string {
  return rotulo
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48);
}

export default function AdminSegmentos() {
  const [estado, setEstado] = useState<
    | { fase: "carregando" }
    | { fase: "erro"; mensagem: string }
    | { fase: "ok"; segmentos: SegmentoAdmin[]; solicitacoes: SolicitacaoAdmin[] }
  >({ fase: "carregando" });
  const [aviso, setAviso] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    const r = await adminCarregarSegmentos();
    setEstado(
      r.tipo === "ok"
        ? { fase: "ok", segmentos: r.segmentos, solicitacoes: r.solicitacoes }
        : { fase: "erro", mensagem: mensagemSegmento(r.codigo) }
    );
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const arquivar = async (s: SegmentoAdmin) => {
    const r = await adminArquivarSegmento(s.id);
    setAviso(
      r.tipo === "ok"
        ? `Segmento "${s.name}" arquivado. Reservas e pedidos existentes mantêm o registro.`
        : mensagemSegmento(r.codigo)
    );
    await carregar();
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-12">
        <Link to="/admin" className="text-sm font-medium text-ciano hover:underline">
          ← Painel administrativo
        </Link>
        <h1 className="mt-3 text-3xl">Segmentos de Outros</h1>
        <p className="mt-2 max-w-2xl text-sm text-tinta/70">
          Segmentos que podem ocupar a posição Outros ou substituir Farmácia, Roupas
          femininas, Roupas masculinas ou Calçados. Supermercado nunca é substituído.
        </p>

        {aviso && (
          <p className="aviso-atencao mt-4 p-3 text-sm" role="status">
            {aviso}
          </p>
        )}

        {estado.fase === "carregando" && (
          <p className="mt-8 text-sm text-tinta/60" role="status">
            Carregando...
          </p>
        )}
        {estado.fase === "erro" && (
          <p className="aviso-erro mt-8 p-4" role="alert">
            {estado.mensagem}
          </p>
        )}

        {estado.fase === "ok" && (
          <>
            <section className="mt-8" aria-labelledby="sol-titulo">
              <h2 id="sol-titulo" className="text-xl">
                Solicitações
              </h2>
              {estado.solicitacoes.length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhuma solicitação.</p>
              ) : (
                <ul className="mt-3 space-y-4">
                  {estado.solicitacoes.map((r) => (
                    <li key={r.id} className="card p-5">
                      <div className="flex flex-wrap items-baseline justify-between gap-2">
                        <p className="font-semibold">{r.label}</p>
                        <span className="text-xs font-semibold">{ROTULO_STATUS[r.status]}</span>
                      </div>
                      <p className="text-sm text-tinta/60">{r.companyName}</p>
                      {r.justification && <p className="mt-2 text-sm">{r.justification}</p>}
                      {r.decisionNote && (
                        <p className="mt-2 text-xs text-tinta/60">Nota: {r.decisionNote}</p>
                      )}
                      {r.status === "pending" && (
                        <Decisao
                          solicitacao={r}
                          segmentos={estado.segmentos.filter((s) => s.status === "approved")}
                          onFeito={async (msg) => {
                            setAviso(msg);
                            await carregar();
                          }}
                        />
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </section>

            <section className="mt-10" aria-labelledby="cat-titulo">
              <h2 id="cat-titulo" className="text-xl">
                Catálogo
              </h2>
              {estado.segmentos.length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhum segmento cadastrado.</p>
              ) : (
                <ul className="mt-3 divide-y divide-tinta/10 rounded-2xl border border-borda">
                  {estado.segmentos.map((s) => (
                    <li key={s.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
                      <div>
                        <p className="font-semibold">
                          {s.name}{" "}
                          <span className="text-xs font-normal text-tinta/60">
                            {s.code} · classificação {s.classificationKey}
                          </span>
                        </p>
                        {s.overlapsNicheCode && (
                          <p className="text-xs text-tinta/60">
                            Sobrepõe {s.overlapsNicheCode}: {s.delimitationPolicy}
                          </p>
                        )}
                      </div>
                      {s.status === "approved" ? (
                        <button type="button" className="btn-secondary" onClick={() => void arquivar(s)}>
                          Arquivar
                        </button>
                      ) : (
                        <span className="text-xs text-tinta/60">Arquivado</span>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </>
        )}
      </main>
    </>
  );
}

function Decisao({
  solicitacao,
  segmentos,
  onFeito,
}: {
  solicitacao: SolicitacaoAdmin;
  segmentos: SegmentoAdmin[];
  onFeito: (mensagem: string) => Promise<void>;
}) {
  const [modo, setModo] = useState<"novo" | "existente" | "rejeitar">("novo");
  const [existente, setExistente] = useState<string>(segmentos[0]?.id ?? "");
  const [nome, setNome] = useState(solicitacao.label);
  const [codigo, setCodigo] = useState(sugerirCodigo(solicitacao.label));
  const [classe, setClasse] = useState(sugerirCodigo(solicitacao.label));
  const [sobrepoe, setSobrepoe] = useState<string>("");
  const [delimitacao, setDelimitacao] = useState("");
  const [nota, setNota] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const enviar = async () => {
    setEnviando(true);
    setErro(null);
    const r =
      modo === "rejeitar"
        ? await adminDecidirSolicitacao(solicitacao.id, { decisao: "reject", nota })
        : modo === "existente"
          ? await adminDecidirSolicitacao(solicitacao.id, {
              decisao: "approve",
              segmentoExistenteId: existente,
              nota,
            })
          : await adminDecidirSolicitacao(solicitacao.id, {
              decisao: "approve",
              novo: {
                code: codigo,
                displayName: nome,
                classificationKey: classe,
                overlapsNicheCode: sobrepoe || null,
                delimitationPolicy: delimitacao || null,
              },
              nota,
            });
    setEnviando(false);
    if (r.tipo === "ok") {
      await onFeito(
        r.status === "rejected" ? "Solicitação rejeitada." : "Solicitação aprovada."
      );
    } else {
      setErro(mensagemSegmento(r.codigo));
    }
  };

  return (
    <div className="mt-4 space-y-3 border-t border-tinta/10 pt-4 text-sm">
      <fieldset className="flex flex-wrap gap-4">
        <legend className="sr-only">Decisão</legend>
        <label className="flex items-center gap-2">
          <input type="radio" checked={modo === "novo"} onChange={() => setModo("novo")} />
          Aprovar como novo segmento
        </label>
        <label className="flex items-center gap-2">
          <input
            type="radio"
            checked={modo === "existente"}
            disabled={segmentos.length === 0}
            onChange={() => setModo("existente")}
          />
          Vincular a segmento existente
        </label>
        <label className="flex items-center gap-2">
          <input type="radio" checked={modo === "rejeitar"} onChange={() => setModo("rejeitar")} />
          Rejeitar
        </label>
      </fieldset>

      {modo === "novo" && (
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block">
            Nome exibido
            <input className="mt-1 w-full rounded-xl border border-borda px-3 py-2" value={nome} onChange={(e) => setNome(e.target.value)} />
          </label>
          <label className="block">
            Código
            <input className="mt-1 w-full rounded-xl border border-borda px-3 py-2" value={codigo} onChange={(e) => setCodigo(e.target.value)} />
          </label>
          <label className="block">
            Classificação administrativa
            <input className="mt-1 w-full rounded-xl border border-borda px-3 py-2" value={classe} onChange={(e) => setClasse(e.target.value)} />
          </label>
          <label className="block">
            Sobrepõe nicho canônico?
            <select className="mt-1 w-full rounded-xl border border-borda px-3 py-2" value={sobrepoe} onChange={(e) => setSobrepoe(e.target.value)}>
              <option value="">Não</option>
              {POSICOES_SOBREPONIVEIS.map((n) => (
                <option key={n.code} value={n.code}>
                  {n.displayName}
                </option>
              ))}
            </select>
          </label>
          {sobrepoe && (
            <label className="block sm:col-span-2">
              Política de delimitação (obrigatória quando sobrepõe)
              <textarea className="mt-1 w-full rounded-xl border border-borda px-3 py-2" rows={2} value={delimitacao} onChange={(e) => setDelimitacao(e.target.value)} />
            </label>
          )}
        </div>
      )}

      {modo === "existente" && (
        <label className="block">
          Segmento
          <select className="mt-1 w-full rounded-xl border border-borda px-3 py-2" value={existente} onChange={(e) => setExistente(e.target.value)}>
            {segmentos.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} ({s.classificationKey})
              </option>
            ))}
          </select>
        </label>
      )}

      <label className="block">
        {modo === "rejeitar" ? "Motivo da rejeição (obrigatório)" : "Nota (opcional)"}
        <input className="mt-1 w-full rounded-xl border border-borda px-3 py-2" value={nota} onChange={(e) => setNota(e.target.value)} />
      </label>

      <button type="button" className="btn-primary" disabled={enviando} onClick={() => void enviar()}>
        {enviando ? "Enviando..." : "Confirmar decisão"}
      </button>
      {erro && (
        <p className="text-vermelho" role="alert">
          {erro}
        </p>
      )}
    </div>
  );
}
