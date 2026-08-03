/**
 * Painel de equipe e convites (dashboard do owner e página /portal/equipe).
 *
 * Convites: token e batchId gerados pelo BACKEND (nunca no navegador), uso
 * único, validade de 48 horas corridas, vinculados à empresa (não a uma
 * filial), revogáveis individualmente ou por lote. Os links completos
 * aparecem SOMENTE no resultado imediato da geração; a listagem posterior
 * conserva rótulo, lote, datas e estado, sem exigir segredo recuperável.
 *
 * Proteção contra quantidades enormes: identificações paginadas (20/página),
 * rótulos esparsos, sem materializar arrays do tamanho total.
 */

import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  createInvitationBatch,
  listInvitations,
  listManagers,
  replaceInvitation,
  revokeInvitation,
  revokeInvitationBatch,
} from "../../services/partnerTeamService";
import { FuncaoIndisponivel } from "./PortalGuards";
import {
  buildBatchInput,
  canReplaceInvitation,
  canRevokeInvitation,
  formatInvitationList,
  invitationStateLabel,
  invitationStateTone,
  invitationVisualState,
  labelPageCount,
  labelPositionsForPage,
  LABELS_PAGE_SIZE,
  validateBatchQuantity,
} from "../../domain/portal/invitations";
import {
  INVITATION_TTL_HOURS,
  PORTAL_ERROR_LABEL,
  type ManagerInvitation,
  type ManagerInvitationBatch,
  type PartnerManagerSummary,
  type PortalCapabilities,
  type PortalErrorCode,
} from "../../domain/portal/types";
import { dataBr } from "../../pages/portal/portalUi";
import {
  loteCurto,
  resumirLotes,
  type ResumoLote,
} from "../../domain/portal/batches";

// Reexport para compatibilidade de importações existentes.
export { loteCurto, resumirLotes };

type Filtro = "todos" | "not_used" | "used" | "expired" | "revoked";

const FILTROS: { valor: Filtro; rotulo: string }[] = [
  { valor: "todos", rotulo: "Todos" },
  { valor: "not_used", rotulo: "Não utilizados" },
  { valor: "used", rotulo: "Utilizados" },
  { valor: "expired", rotulo: "Expirados" },
  { valor: "revoked", rotulo: "Revogados" },
];

async function copiar(texto: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(texto);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Formulário de geração em lote (identificações paginadas)
// ---------------------------------------------------------------------------

function FormularioLote({
  habilitado,
  onGerado,
}: {
  habilitado: boolean;
  onGerado: (lote: ManagerInvitationBatch) => void;
}) {
  const [quantidade, setQuantidade] = useState("1");
  const [rotulos, setRotulos] = useState<Map<number, string>>(new Map());
  const [pagina, setPagina] = useState(1);
  const [erroQtd, setErroQtd] = useState<string | null>(null);
  const [erroEnvio, setErroEnvio] = useState<PortalErrorCode | null>(null);
  const [enviando, setEnviando] = useState(false);

  const check = validateBatchQuantity(quantidade);
  const qtdValida = check.ok ? check.quantity : 0;
  const totalPaginas = labelPageCount(qtdValida);
  const posicoes = useMemo(
    () => labelPositionsForPage(qtdValida, pagina),
    [qtdValida, pagina]
  );

  const aplicarQuantidade = (valor: string) => {
    setQuantidade(valor);
    setErroQtd(null);
    setPagina(1);
  };

  const gerar = async () => {
    setErroEnvio(null);
    if (!check.ok) {
      setErroQtd(check.motivo);
      return;
    }
    // Rótulos ESPARSOS: só as posições preenchidas entram no payload.
    const input = buildBatchInput(check.quantity, rotulos);
    setEnviando(true);
    const res = await createInvitationBatch(input);
    setEnviando(false);
    // Nunca apresentar sucesso quando o backend não concluiu.
    if (!res.ok) {
      setErroEnvio(res.error.code);
      return;
    }
    onGerado(res.data);
  };

  return (
    <div className="rounded-2xl border border-borda bg-white/85 p-5">
      <h3 className="font-bold">Gerar convites de gerente</h3>
      <p className="mt-1 text-sm text-tinta/60">
        Cada convite é um link individual, de uso único, válido por{" "}
        {INVITATION_TTL_HOURS} horas. Pode ser enviado por e-mail, WhatsApp ou
        qualquer outro canal — informar o e-mail do destinatário não é
        obrigatório.
      </p>

      <div className="mt-4 max-w-xs">
        <label htmlFor="lote-qtd" className="mb-1.5 block text-sm font-semibold">
          Quantidade de convites
        </label>
        <input
          id="lote-qtd"
          type="number"
          inputMode="numeric"
          min={1}
          step={1}
          value={quantidade}
          onChange={(e) => aplicarQuantidade(e.target.value)}
          className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
        />
        {erroQtd && (
          <p className="mt-1 text-xs font-medium text-magenta">{erroQtd}</p>
        )}
      </div>

      {qtdValida > 0 && (
        <fieldset className="mt-4">
          <legend className="text-sm font-semibold">
            Identificação de cada vaga{" "}
            <span className="font-normal text-tinta/40">(opcional)</span>
          </legend>

          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {posicoes.map((pos) => (
              <div key={pos}>
                <label htmlFor={`lote-rot-${pos}`} className="sr-only">
                  Identificação do convite {pos}
                </label>
                <input
                  id={`lote-rot-${pos}`}
                  type="text"
                  value={rotulos.get(pos) ?? ""}
                  placeholder={`Convite ${pos} — ex.: turno da manhã`}
                  onChange={(e) =>
                    setRotulos((atuais) => {
                      const novo = new Map(atuais);
                      if (e.target.value) novo.set(pos, e.target.value);
                      else novo.delete(pos);
                      return novo;
                    })
                  }
                  className="w-full rounded-xl border border-borda px-3 py-2 text-sm outline-none focus:border-ciano"
                />
              </div>
            ))}
          </div>

          {totalPaginas > 1 && (
            <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
              <button
                type="button"
                onClick={() => setPagina((p) => Math.max(1, p - 1))}
                disabled={pagina <= 1}
                className="rounded-lg border border-borda px-3 py-1.5 font-semibold disabled:opacity-40"
              >
                Anterior
              </button>
              <span aria-live="polite" className="font-medium text-tinta/70">
                Página {pagina} de {totalPaginas}
              </span>
              <button
                type="button"
                onClick={() => setPagina((p) => Math.min(totalPaginas, p + 1))}
                disabled={pagina >= totalPaginas}
                className="rounded-lg border border-borda px-3 py-1.5 font-semibold disabled:opacity-40"
              >
                Próxima
              </button>
              <span className="text-xs text-tinta/40">
                ({LABELS_PAGE_SIZE} identificações por página)
              </span>
            </div>
          )}
        </fieldset>
      )}

      <button
        onClick={gerar}
        disabled={enviando || !habilitado}
        className={
          habilitado
            ? "btn-primary mt-5"
            : "mt-5 cursor-not-allowed rounded-xl border-2 border-borda px-4 py-2.5 text-sm font-semibold text-tinta/40"
        }
        title={habilitado ? undefined : "Permissão concedida pelo servidor ainda indisponível"}
      >
        {enviando ? "Gerando convites..." : "Gerar convites"}
      </button>

      {erroEnvio && (
        <div className="mt-4 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[erroEnvio]} Nenhum convite foi criado.
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Resultado imediato (única tela que mostra os links completos)
// ---------------------------------------------------------------------------

function ResultadoGeracao({
  lote,
  onFechar,
}: {
  lote: ManagerInvitationBatch;
  onFechar: () => void;
}) {
  const [copiado, setCopiado] = useState<string | null>(null);
  const convites = lote.invitations;

  return (
    <div className="mt-4 rounded-2xl border-2 border-ciano/40 bg-ciano/5 p-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="font-bold">
          Lote {loteCurto(lote.batchId)} — {convites.length} convite(s) gerado(s)
        </h3>
        <button onClick={onFechar} className="btn-secondary text-sm">
          Fechar
        </button>
      </div>
      <p className="mt-1 text-sm text-tinta/70">
        Por segurança, os links completos aparecem apenas nesta tela. Depois,
        a listagem conserva identificação, lote, datas e estado.
      </p>

      <button
        onClick={async () => {
          const ok = await copiar(formatInvitationList(convites));
          setCopiado(ok ? "todos" : null);
        }}
        className="btn-primary mt-4 text-sm"
      >
        {copiado === "todos" ? "Lista copiada ✓" : "Copiar todos como lista numerada"}
      </button>

      <ol className="mt-4 space-y-2">
        {convites.map((c, i) => (
          <li
            key={c.invitationId}
            className="rounded-xl border border-borda bg-white px-4 py-3 text-sm"
          >
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="font-semibold">
                {i + 1}. {c.label || `Convite ${i + 1}`}
              </span>
              <button
                onClick={async () => {
                  const ok = await copiar(c.url ?? "");
                  setCopiado(ok ? c.invitationId : null);
                }}
                className="rounded-lg border border-borda px-2 py-1 text-xs font-semibold transition hover:border-tinta"
              >
                {copiado === c.invitationId ? "Copiado ✓" : "Copiar link"}
              </button>
            </div>
            <p className="mt-1 break-all font-mono text-xs text-tinta/70">
              {c.url ?? "[link não retornado pelo servidor]"}
            </p>
          </li>
        ))}
      </ol>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Resumo por lote
// ---------------------------------------------------------------------------

function ResumoLotes({
  convites,
  podeRevogar,
  onRevogarLote,
}: {
  convites: readonly ManagerInvitation[];
  podeRevogar: boolean;
  onRevogarLote: (batchId: string) => void;
}) {
  const lotes = resumirLotes(convites);
  if (lotes.length === 0) return null;

  return (
    <div className="mt-4 overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse text-sm">
        <caption className="sr-only">Resumo de convites por lote</caption>
        <thead>
          <tr className="border-b-2 border-borda text-left text-xs uppercase tracking-widest text-tinta/50">
            <th className="py-2 pr-4">Lote</th>
            <th className="py-2 pr-4">Criado</th>
            <th className="py-2 pr-4">Total</th>
            <th className="py-2 pr-4">Disponíveis</th>
            <th className="py-2 pr-4">Utilizados</th>
            <th className="py-2 pr-4">Expirados</th>
            <th className="py-2 pr-4">Revogados</th>
            <th className="py-2">Ação</th>
          </tr>
        </thead>
        <tbody>
          {lotes.map((l) => (
            <tr key={l.batchId} className="border-b border-borda">
              <td className="py-2 pr-4 font-mono">{loteCurto(l.batchId)}</td>
              <td className="py-2 pr-4">{dataBr(l.createdAt) ?? "—"}</td>
              <td className="py-2 pr-4">{l.total}</td>
              <td className="py-2 pr-4">{l.disponiveis}</td>
              <td className="py-2 pr-4">{l.utilizados}</td>
              <td className="py-2 pr-4">{l.expirados}</td>
              <td className="py-2 pr-4">{l.revogados}</td>
              <td className="py-2">
                {podeRevogar && l.disponiveis > 0 ? (
                  <button
                    onClick={() => onRevogarLote(l.batchId)}
                    className="rounded-lg border border-borda px-3 py-1.5 text-xs font-semibold transition hover:border-magenta hover:text-magenta"
                  >
                    Revogar convites disponíveis deste lote
                  </button>
                ) : (
                  <span className="text-xs text-tinta/40">—</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Lista de convites (individual: revogar / substituir)
// ---------------------------------------------------------------------------

export function ListaConvites({
  convites,
  onMudou,
  podeRevogar,
}: {
  convites: readonly ManagerInvitation[];
  onMudou: () => void;
  podeRevogar: boolean;
}) {
  const [filtro, setFiltro] = useState<Filtro>("todos");
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const agora = new Date();

  const visiveis = convites.filter((c) =>
    filtro === "todos" ? true : invitationVisualState(c, agora) === filtro
  );

  return (
    <div className="mt-4">
      <div className="flex flex-wrap gap-2" role="group" aria-label="Filtrar convites">
        {FILTROS.map((f) => (
          <button
            key={f.valor}
            onClick={() => setFiltro(f.valor)}
            aria-pressed={filtro === f.valor}
            className={`rounded-full px-3 py-1.5 text-xs font-semibold transition ${
              filtro === f.valor
                ? "bg-tinta text-papel"
                : "border border-borda text-tinta/70 hover:border-tinta"
            }`}
          >
            {f.rotulo}
          </button>
        ))}
      </div>

      {erro && (
        <p className="mt-3 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[erro]} Nenhuma alteração foi aplicada.
        </p>
      )}

      {visiveis.length === 0 ? (
        <p className="mt-4 rounded-2xl border border-dashed border-borda p-8 text-center text-sm text-tinta/60">
          Nenhum convite neste filtro.
        </p>
      ) : (
        <ul className="mt-4 space-y-3">
          {visiveis.map((c) => {
            const estado = invitationVisualState(c, agora);
            return (
              <li
                key={c.invitationId}
                className="rounded-2xl border border-borda bg-white/85 p-4"
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="font-semibold">
                      {c.label || "Convite sem identificação"}
                    </p>
                    <p className="mt-0.5 text-xs text-tinta/50">
                      Lote {loteCurto(c.batchId)} · criado em{" "}
                      {dataBr(c.createdAt) ?? "data não informada"}
                    </p>
                  </div>
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-semibold ${invitationStateTone(estado)}`}
                  >
                    {invitationStateLabel(c, agora)}
                  </span>
                </div>

                {estado === "used" && (
                  <p className="mt-2 text-sm text-tinta/70">
                    Utilizado em {dataBr(c.usedAt) ?? "data não informada"}
                    {c.usedByMemberId && (
                      <>
                        {" · "}
                        <Link
                          to={`/portal/equipe/${c.usedByMemberId}`}
                          className="font-semibold text-ciano underline"
                        >
                          {c.usedByName ?? "abrir gerente"}
                        </Link>
                      </>
                    )}
                  </p>
                )}

                <div className="mt-3 flex flex-wrap gap-2">
                  {podeRevogar && canRevokeInvitation(c, agora) && (
                    <button
                      onClick={async () => {
                        const r = await revokeInvitation(c.invitationId);
                        if (!r.ok) setErro(r.error.code);
                        else onMudou();
                      }}
                      className="rounded-lg border border-borda px-3 py-1.5 text-xs font-semibold transition hover:border-magenta hover:text-magenta"
                    >
                      Revogar convite
                    </button>
                  )}
                  {podeRevogar && canReplaceInvitation(c, agora) && (
                    <button
                      onClick={async () => {
                        const r = await replaceInvitation(c.invitationId);
                        if (!r.ok) setErro(r.error.code);
                        else onMudou();
                      }}
                      className="rounded-lg border border-ciano/40 px-3 py-1.5 text-xs font-semibold text-ciano transition hover:bg-ciano/10"
                    >
                      Gerar substituto
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Painel completo
// ---------------------------------------------------------------------------

export default function EquipeConvitesPainel({
  capabilities,
  mostrarManagers = true,
}: {
  capabilities: PortalCapabilities;
  mostrarManagers?: boolean;
}) {
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const [convites, setConvites] = useState<ManagerInvitation[]>([]);
  const [managers, setManagers] = useState<PartnerManagerSummary[]>([]);
  const [gerado, setGerado] = useState<ManagerInvitationBatch | null>(null);
  const [erroAcao, setErroAcao] = useState<PortalErrorCode | null>(null);

  const carregar = useCallback(() => {
    setCarregando(true);
    Promise.all([listInvitations(), listManagers()]).then(([ci, cm]) => {
      if (ci.ok) setConvites(ci.data);
      else setErro(ci.error.code);
      if (cm.ok) setManagers(cm.data);
      setCarregando(false);
    });
  }, []);

  useEffect(carregar, [carregar]);

  const revogarLote = async (batchId: string) => {
    setErroAcao(null);
    const r = await revokeInvitationBatch(batchId);
    if (!r.ok) setErroAcao(r.error.code);
    else carregar();
  };

  return (
    <div className="mt-4 space-y-4">
      <FormularioLote
        habilitado={capabilities.canInviteManagers}
        onGerado={(lote) => {
          setGerado(lote);
          carregar();
        }}
      />

      {gerado && (
        <ResultadoGeracao lote={gerado} onFechar={() => setGerado(null)} />
      )}

      {erroAcao && (
        <p className="rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[erroAcao]} Nenhuma alteração foi aplicada.
        </p>
      )}

      {carregando ? (
        <p className="text-sm text-tinta/60">Carregando convites...</p>
      ) : erro === "BACKEND_NOT_AVAILABLE" ? (
        <FuncaoIndisponivel
          titulo="Convites ainda não disponíveis"
          descricao="A emissão e o acompanhamento de convites dependem de uma camada de servidor que ainda não foi ativada. Nenhum link é gerado pelo navegador."
        />
      ) : erro ? (
        <p className="rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
          {PORTAL_ERROR_LABEL[erro]}
        </p>
      ) : (
        <>
          <ResumoLotes
            convites={convites}
            podeRevogar={capabilities.canManageManagers}
            onRevogarLote={revogarLote}
          />
          <ListaConvites
            convites={convites}
            onMudou={carregar}
            podeRevogar={capabilities.canManageManagers}
          />
        </>
      )}

      {mostrarManagers && managers.length > 0 && (
        <p className="text-sm text-tinta/60">
          {managers.length} gerente(s) vinculado(s).{" "}
          <Link to="/portal/equipe" className="font-semibold text-ciano underline">
            Ver equipe completa
          </Link>
        </p>
      )}
    </div>
  );
}
