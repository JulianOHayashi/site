import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import {
  obterContextoConta,
  listarCorrecoes,
  listarDocumentos,
  responderCorrecao,
  enviarDocumento,
  urlAssinadaDocumento,
  mensagemDeMotivo,
  type ContextoConta,
  type Correcao,
  type Documento,
  type Solicitacao,
} from "../../services/partnerApplicationService";

/**
 * /parceiros/solicitacao — jornada da CONTA PROVISÓRIA.
 *
 * Escopo por decisão de negócio: status, correções e documentos. Nada de
 * contratos, pagamentos, pré-compra ou operações de owner — isso pertence
 * ao portal do parceiro aprovado, que esta conta não acessa.
 *
 * Nenhuma mensagem de erro do banco chega à tela: só rótulos mapeados.
 */

const ROTULOS: Record<string, string> = {
  pending_email_verification: "Aguardando confirmação de e-mail",
  pending_account_setup: "Aguardando criação do acesso",
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

const ROTULOS_DOC: Record<string, string> = {
  received: "Recebido",
  accepted: "Aceito",
  rejected: "Não aceito",
};

const ROTULOS_ESCOPO: Record<string, string> = {
  company: "Dados da empresa",
  authority: "Responsável",
  documents: "Documentos",
};

const TIPOS_DOC: { valor: string; rotulo: string }[] = [
  { valor: "contrato_social", rotulo: "Contrato social" },
  { valor: "cartao_cnpj", rotulo: "Cartão CNPJ" },
  { valor: "documento_representante", rotulo: "Documento do responsável" },
  { valor: "procuracao", rotulo: "Procuração" },
  { valor: "comprovante_endereco", rotulo: "Comprovante de endereço" },
  { valor: "outro", rotulo: "Outro" },
];

function dataCurta(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("pt-BR");
}

export default function SolicitacaoStatus() {
  const [contexto, setContexto] = useState<ContextoConta>({ tipo: "carregando" });
  const [correcoes, setCorrecoes] = useState<Correcao[]>([]);
  const [documentos, setDocumentos] = useState<Documento[]>([]);
  const [aviso, setAviso] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    const ctx = await obterContextoConta();
    setContexto(ctx);
    if (ctx.tipo !== "provisoria") return;
    const id = ctx.solicitacao.application_id;
    const [c, d] = await Promise.all([listarCorrecoes(id), listarDocumentos(id)]);
    if (c.ok) setCorrecoes(c.dados);
    if (d.ok) setDocumentos(d.dados);
    if (!c.ok || !d.ok) setAviso(mensagemDeMotivo("rpc_error"));
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  if (contexto.tipo === "carregando") {
    return (
      <Moldura>
        <p className="text-center text-sm text-tinta/60" role="status">
          Carregando...
        </p>
      </Moldura>
    );
  }

  if (contexto.tipo === "erro") {
    return (
      <Moldura>
        <div role="alert" className="card p-8 text-center">
          <h1 className="text-2xl font-bold">Não foi possível carregar</h1>
          <p className="mt-4 text-sm text-tinta/70">
            Tente novamente em instantes.
          </p>
        </div>
      </Moldura>
    );
  }

  if (contexto.tipo !== "provisoria") {
    return (
      <Moldura>
        <div className="card p-8 text-center">
          <h1 className="text-2xl font-bold">Nenhuma solicitação encontrada</h1>
          <p className="mt-4 text-sm text-tinta/70">
            Não localizamos uma solicitação vinculada a este acesso.
          </p>
          <Link to="/parceiros/cadastro" className="btn-primary mt-6 inline-block">
            Fazer uma solicitação
          </Link>
        </div>
      </Moldura>
    );
  }

  const s: Solicitacao = contexto.solicitacao;
  const podeEnviar = s.status === "under_review" || s.status === "changes_requested";

  return (
    <Moldura>
      <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
        Acesso provisório
      </p>
      <h1 className="mt-3 text-3xl">
        {s.legal_name}
        <span className="mt-3 block h-2 w-24 rounded-full bg-magenta" />
      </h1>

      {aviso ? (
        <div role="alert" className="mt-4 rounded-xl bg-amarelo/25 p-4 text-sm">
          {aviso}
        </div>
      ) : null}

      <section className="card mt-6 space-y-3 p-6">
        <h2 className="text-lg font-bold">Situação</h2>
        <Linha rotulo="Estado" valor={ROTULOS[s.status] ?? s.status} destaque />
        <Linha rotulo="Análise da empresa" valor={ROTULOS_ANALISE[s.company_review_status] ?? "—"} />
        <Linha rotulo="Análise do responsável" valor={ROTULOS_ANALISE[s.authority_review_status] ?? "—"} />
        <Linha rotulo="CNPJ" valor={s.cnpj} />
        <Linha rotulo="Região" valor={`${s.city} / ${s.uf}`} />
        <Linha rotulo="Solicitada em" valor={dataCurta(s.created_at)} />
      </section>

      <Correcoes correcoes={correcoes} aoResponder={carregar} />

      <Documentos
        documentos={documentos}
        applicationId={s.application_id}
        podeEnviar={podeEnviar}
        aoEnviar={carregar}
      />

      <p className="mt-8 text-sm text-tinta/60">
        O acesso provisório não dá acesso ao portal de parceiro aprovado nem a
        contratos, pagamentos ou validação de benefício.
      </p>
    </Moldura>
  );
}

function Moldura({ children }: { children: React.ReactNode }) {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">{children}</main>
    </>
  );
}

function Linha({ rotulo, valor, destaque }: { rotulo: string; valor: string; destaque?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-sm text-tinta/60">{rotulo}</span>
      <span className={destaque ? "font-semibold" : ""}>{valor}</span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Correções
// ---------------------------------------------------------------------------
function Correcoes({ correcoes, aoResponder }: { correcoes: Correcao[]; aoResponder: () => Promise<void> }) {
  const [respostas, setRespostas] = useState<Record<string, string>>({});
  const [enviando, setEnviando] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const responder = async (id: string) => {
    const texto = (respostas[id] ?? "").trim();
    if (texto.length === 0) {
      setErro("Escreva uma resposta antes de enviar.");
      return;
    }
    // Trava por item: evita envio duplicado por clique repetido.
    if (enviando) return;
    setEnviando(id);
    setErro(null);
    const r = await responderCorrecao(id, texto);
    setEnviando(null);
    if (!r.ok) {
      setErro(mensagemDeMotivo(r.motivo));
      return;
    }
    setRespostas((atual) => ({ ...atual, [id]: "" }));
    await aoResponder();
  };

  return (
    <section className="card mt-6 p-6">
      <h2 className="text-lg font-bold">Correções solicitadas</h2>
      {erro ? (
        <p role="alert" className="mt-3 text-sm text-red-700">
          {erro}
        </p>
      ) : null}

      {correcoes.length === 0 ? (
        <p className="mt-3 text-sm text-tinta/60">Nenhuma correção pendente.</p>
      ) : (
        <ul className="mt-4 space-y-5">
          {correcoes.map((c) => (
            <li key={c.id} className="rounded-2xl border border-borda p-4">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="font-semibold">{ROTULOS_ESCOPO[c.scope] ?? c.scope}</span>
                <span className="text-sm text-tinta/60">{dataCurta(c.requested_at)}</span>
              </div>
              <p className="mt-2 text-sm">{c.message}</p>

              {c.responded_at ? (
                <div className="mt-3 rounded-xl bg-papel2 p-3 text-sm">
                  <p className="font-semibold">Sua resposta ({dataCurta(c.responded_at)})</p>
                  <p className="mt-1">{c.response_message}</p>
                </div>
              ) : (
                <div className="mt-3">
                  <label htmlFor={`resp-${c.id}`} className="mb-1.5 block text-sm font-semibold">
                    Responder
                  </label>
                  <textarea
                    id={`resp-${c.id}`}
                    rows={3}
                    value={respostas[c.id] ?? ""}
                    onChange={(e) =>
                      setRespostas((atual) => ({ ...atual, [c.id]: e.target.value }))
                    }
                    className="w-full rounded-xl border border-borda px-3 py-2"
                  />
                  <button
                    type="button"
                    onClick={() => void responder(c.id)}
                    disabled={enviando !== null}
                    className="btn-primary mt-2 px-4 py-2 text-sm"
                  >
                    {enviando === c.id ? "Enviando..." : "Enviar resposta"}
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Documentos
// ---------------------------------------------------------------------------
function Documentos({
  documentos,
  applicationId,
  podeEnviar,
  aoEnviar,
}: {
  documentos: Documento[];
  applicationId: string;
  podeEnviar: boolean;
  aoEnviar: () => Promise<void>;
}) {
  const [tipo, setTipo] = useState<string>("contrato_social");
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const enviar = async () => {
    const arquivo = inputRef.current?.files?.[0];
    if (!arquivo) {
      setErro("Selecione um arquivo.");
      return;
    }
    if (enviando) return;
    setEnviando(true);
    setErro(null);
    const r = await enviarDocumento(applicationId, tipo, arquivo);
    setEnviando(false);
    if (!r.ok) {
      setErro(mensagemDeMotivo(r.motivo));
      return;
    }
    if (inputRef.current) inputRef.current.value = "";
    await aoEnviar();
  };

  const abrir = async (caminho: string) => {
    const url = await urlAssinadaDocumento(caminho);
    if (!url) {
      setErro("Não foi possível abrir o documento agora.");
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  };

  const ativos = documentos.filter((d) => d.superseded_at === null);
  const historico = documentos.filter((d) => d.superseded_at !== null);

  return (
    <section className="card mt-6 p-6">
      <h2 className="text-lg font-bold">Documentos</h2>
      <p className="mt-2 text-sm text-tinta/70">
        Os arquivos ficam em armazenamento privado, acessíveis apenas a você e
        à análise autorizada da BDFlow.
      </p>

      {erro ? (
        <p role="alert" className="mt-3 text-sm text-red-700">
          {erro}
        </p>
      ) : null}

      <ListaDocumentos titulo="Atuais" itens={ativos} aoAbrir={abrir} vazio="Nenhum documento enviado." />
      {historico.length > 0 ? (
        <ListaDocumentos titulo="Versões anteriores" itens={historico} aoAbrir={abrir} vazio="" />
      ) : null}

      {podeEnviar ? (
        <div className="mt-6 rounded-2xl border border-borda p-4">
          <h3 className="font-semibold">Enviar documento</h3>
          <p className="mt-1 text-sm text-tinta/60">
            Um envio novo não substitui o anterior: ele cria uma nova versão e
            o histórico é preservado.
          </p>
          <div className="mt-3">
            <label htmlFor="doc-tipo" className="mb-1.5 block text-sm font-semibold">
              Tipo
            </label>
            <select
              id="doc-tipo"
              value={tipo}
              onChange={(e) => setTipo(e.target.value)}
              className="w-full rounded-xl border border-borda px-3 py-2"
            >
              {TIPOS_DOC.map((t) => (
                <option key={t.valor} value={t.valor}>
                  {t.rotulo}
                </option>
              ))}
            </select>
          </div>
          <div className="mt-3">
            <label htmlFor="doc-arquivo" className="mb-1.5 block text-sm font-semibold">
              Arquivo (PDF ou imagem, até 20 MB)
            </label>
            <input
              id="doc-arquivo"
              ref={inputRef}
              type="file"
              accept="application/pdf,image/jpeg,image/png,image/webp"
              className="w-full text-sm"
            />
          </div>
          <button
            type="button"
            onClick={() => void enviar()}
            disabled={enviando}
            className="btn-primary mt-4 px-4 py-2 text-sm"
          >
            {enviando ? "Enviando..." : "Enviar documento"}
          </button>
        </div>
      ) : null}
    </section>
  );
}

function ListaDocumentos({
  titulo,
  itens,
  aoAbrir,
  vazio,
}: {
  titulo: string;
  itens: Documento[];
  aoAbrir: (caminho: string) => Promise<void>;
  vazio: string;
}) {
  return (
    <div className="mt-4">
      <h3 className="text-sm font-bold uppercase tracking-wide text-tinta/60">{titulo}</h3>
      {itens.length === 0 ? (
        vazio ? <p className="mt-2 text-sm text-tinta/60">{vazio}</p> : null
      ) : (
        <ul className="mt-2 space-y-2">
          {itens.map((d) => (
            <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-borda px-3 py-2">
              <div>
                <p className="font-semibold">
                  {TIPOS_DOC.find((t) => t.valor === d.doc_type)?.rotulo ?? d.doc_type}
                </p>
                <p className="text-sm text-tinta/60">
                  {d.original_filename} · {dataCurta(d.created_at)} ·{" "}
                  {ROTULOS_DOC[d.review_status] ?? d.review_status}
                  {d.superseded_at ? " · substituído" : ""}
                </p>
              </div>
              <button
                type="button"
                onClick={() => void aoAbrir(d.storage_path)}
                className="rounded-xl border border-borda px-3 py-1.5 text-sm font-semibold"
              >
                Abrir
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
