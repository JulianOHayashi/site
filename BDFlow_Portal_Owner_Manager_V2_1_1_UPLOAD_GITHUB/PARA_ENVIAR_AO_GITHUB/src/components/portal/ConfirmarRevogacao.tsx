/**
 * Confirmação de revogação de acesso por desligamento.
 *
 * Encerramento DEFINITIVO do vínculo empresarial — nunca exclusão de
 * cadastro. A conta pessoal do gerente e o histórico anterior permanecem.
 *
 * V2: NÃO há campo de senha. Autenticação adicional será uma PROVA OPACA
 * emitida pelo backend (`sensitiveActionProof`), não uma senha bruta no
 * navegador. Enquanto o backend não existir, a ação retorna
 * BACKEND_NOT_AVAILABLE e nenhuma revogação parece concluída.
 */

import { useEffect, useRef, useState } from "react";
import { revokeManagerMembership } from "../../services/partnerTeamService";
import {
  PORTAL_ERROR_LABEL,
  type PartnerManagerSummary,
  type PortalErrorCode,
} from "../../domain/portal/types";

export default function ConfirmarRevogacao({
  manager,
  onFechar,
  onConcluido,
}: {
  manager: PartnerManagerSummary;
  onFechar: () => void;
  onConcluido: () => void;
}) {
  const [confirmacao, setConfirmacao] = useState("");
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const motivoRef = useRef<HTMLTextAreaElement>(null);

  const nome = manager.name ?? "este gerente";
  const confirmacaoOk = confirmacao.trim().toUpperCase() === "REVOGAR";
  const motivoOk = motivo.trim().length >= 3;
  const podeConfirmar = confirmacaoOk && motivoOk;

  // Foco inicial coerente + fechamento por teclado (Esc).
  useEffect(() => {
    motivoRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onFechar();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onFechar]);

  const revogar = async () => {
    setErro(null);
    if (!podeConfirmar) return;
    setEnviando(true);
    // A prova opaca ainda não existe: enviamos vazio e o serviço responde
    // BACKEND_NOT_AVAILABLE. Nenhuma senha é coletada, guardada ou enviada.
    const r = await revokeManagerMembership({
      memberId: manager.memberId,
      reason: motivo.trim(),
      sensitiveActionProof: "",
    });
    setEnviando(false);
    if (!r.ok) {
      setErro(r.error.code);
      return;
    }
    onConcluido();
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="revogar-titulo"
      className="fixed inset-0 z-50 flex items-center justify-center bg-tinta/50 p-4"
    >
      <div className="max-h-full w-full max-w-lg overflow-y-auto rounded-3xl bg-papel p-6 shadow-2xl">
        <h2 id="revogar-titulo" className="text-2xl font-bold">
          Revogar acesso de {nome}
        </h2>
        <p className="mt-2 text-sm text-tinta/70">
          Esta ação encerra o vínculo do gerente com a sua empresa. Ao confirmar:
        </p>

        <ul className="mt-4 space-y-2 text-sm">
          <li className="rounded-xl bg-papel2 px-4 py-3">
            novas validações serão bloqueadas imediatamente;
          </li>
          <li className="rounded-xl bg-papel2 px-4 py-3">
            o acesso a <strong>todas as filiais</strong> desta empresa será removido;
          </li>
          <li className="rounded-xl bg-papel2 px-4 py-3">
            sessões e autorizações em andamento dependerão do encerramento seguro
            pelo servidor;
          </li>
          <li className="rounded-xl bg-papel2 px-4 py-3">
            o histórico será <strong>preservado para auditoria</strong> — nada é
            excluído;
          </li>
          <li className="rounded-xl bg-papel2 px-4 py-3">
            uma futura recontratação exigirá <strong>novo convite</strong>.
          </li>
        </ul>

        <div className="mt-5">
          <label htmlFor="rev-motivo" className="mb-1.5 block text-sm font-semibold">
            Motivo do desligamento
          </label>
          <textarea
            id="rev-motivo"
            ref={motivoRef}
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            rows={3}
            className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
            placeholder="Descreva brevemente o motivo (registrado na auditoria)."
          />
          {!motivoOk && motivo.length > 0 && (
            <p className="mt-1 text-xs font-medium text-magenta">
              Informe um motivo com pelo menos 3 caracteres.
            </p>
          )}
        </div>

        <div className="mt-4">
          <label htmlFor="rev-conf" className="mb-1.5 block text-sm font-semibold">
            Digite REVOGAR para confirmar
          </label>
          <input
            id="rev-conf"
            type="text"
            value={confirmacao}
            onChange={(e) => setConfirmacao(e.target.value)}
            className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
          />
        </div>

        <p className="mt-4 rounded-xl bg-papel2 px-4 py-3 text-xs text-tinta/60">
          A verificação adicional de segurança (autenticação reforçada) ainda
          não foi ativada no servidor. Por isso, a revogação não é concluída
          neste momento.
        </p>

        {erro && (
          <p className="mt-4 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
            {PORTAL_ERROR_LABEL[erro]} O vínculo <strong>não</strong> foi
            encerrado.
          </p>
        )}

        <div className="mt-6 flex flex-wrap justify-end gap-2">
          <button onClick={onFechar} className="btn-secondary">
            Cancelar
          </button>
          <button
            onClick={revogar}
            disabled={!podeConfirmar || enviando}
            className="rounded-xl bg-magenta px-5 py-2.5 font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-40"
          >
            {enviando ? "Processando..." : "Revogar acesso"}
          </button>
        </div>
      </div>
    </div>
  );
}
