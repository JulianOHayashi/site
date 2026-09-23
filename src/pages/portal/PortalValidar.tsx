import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import {
  obterVinculosParceiro,
  obterContextoValidador,
  type ContextoValidador,
} from "../../services/partnerApplicationService";
import { enviarUsoDeBeneficioPorCodigo } from "../../services/benefitUsageService";
import { normalizarDisplayCode } from "../../server/benefitUsage/benefitUsageContract";

/**
 * /portal/validar — CÓDIGO MANUAL do balcão.
 *
 * O Site prova QUEM valida, EM QUE unidade e por QUAL rede, e encaminha o
 * código ao gateway do App. O desfecho é autoridade do App: aqui nada afirma
 * que o benefício foi validado ou consumido.
 *
 * O CÓDIGO NÃO VIVE NA URL. O antigo preenchimento por parâmetro de busca
 * saiu — a asserção que cobre isto varre o próprio texto deste arquivo, então
 * nem em comentário o nome daquele parâmetro aparece. Um código de benefício
 * no histórico do navegador sobrevive ao atendimento, aparece em captura de
 * tela e vaza por Referer. Ele é digitado, usado e descartado.
 *
 * O QR continua em /beneficios/validar/:publicLookupId e não se cruza com
 * este caminho: lá o portador é `public_lookup_id` + segredo; aqui é um
 * `display_code` digitado.
 */
type Estado =
  | { fase: "carregando" }
  | { fase: "sem_vinculo" }
  | { fase: "inelegivel" }
  | { fase: "erro" }
  | { fase: "pronto"; ctx: Extract<ContextoValidador, { tipo: "elegivel" }>; companyId: string };

export default function PortalValidar() {
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });
  const [unidade, setUnidade] = useState("");
  const [codigo, setCodigo] = useState("");
  const [documentoConferido, setDocumentoConferido] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [falha, setFalha] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<{ correlationId: string } | null>(null);

  // O valor digitado é preservado literalmente até a validação autoritativa.
  // Isso impede TAB, Unicode ou hífens extras de serem "limpos" pelo cliente e
  // acidentalmente virarem um código válido antes de chegar ao servidor.
  const canonico = normalizarDisplayCode(codigo);

  const carregar = useCallback(async () => {
    setEstado({ fase: "carregando" });
    const vinculos = await obterVinculosParceiro();
    if (vinculos.tipo === "erro") return setEstado({ fase: "erro" });
    const primeiro = vinculos.vinculos[0];
    if (!primeiro) return setEstado({ fase: "sem_vinculo" });

    const ctx = await obterContextoValidador(primeiro.company_id);
    if (ctx.tipo === "erro") return setEstado({ fase: "erro" });
    if (ctx.tipo === "inelegivel") return setEstado({ fase: "inelegivel" });
    setUnidade(ctx.unidades[0]?.unit_id ?? "");
    setEstado({ fase: "pronto", ctx, companyId: primeiro.company_id });
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "pronto" || !unidade || !canonico
        || !documentoConferido || enviando) return;
    setEnviando(true);
    setFalha(null);
    const r = await enviarUsoDeBeneficioPorCodigo({
      displayCode: canonico,
      unitId: unidade,
      physicalPhotoIdChecked: true,
    });
    setEnviando(false);
    if (r.tipo === "ok") {
      setSucesso({ correlationId: r.correlationId });
      // O código some da memória da tela assim que a solicitação é criada.
      setCodigo("");
    } else {
      setFalha(r.codigo);
    }
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Validar benefício" />

        {estado.fase === "carregando" && (
          <p className="mt-8 text-sm text-tinta/60" role="status">
            Verificando sua autorização de validação...
          </p>
        )}

        {estado.fase === "erro" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Não foi possível verificar sua autorização.</p>
            <p className="mt-2 text-sm text-tinta/70">
              Por segurança, nenhuma validação foi encaminhada.
            </p>
            <button onClick={carregar} className="btn-primary mt-4">
              Tentar novamente
            </button>
          </div>
        )}

        {estado.fase === "sem_vinculo" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Esta conta não possui rede parceira ativa.</p>
            <Link to="/portal/dashboard" className="btn-secondary mt-4 inline-block">
              Voltar ao painel
            </Link>
          </div>
        )}

        {estado.fase === "inelegivel" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Você não está autorizado a validar.</p>
            <p className="mt-2 text-sm text-tinta/70">
              A validação exige vínculo ativo com ao menos uma unidade ativa.
              Fale com o responsável da empresa.
            </p>
          </div>
        )}

        {estado.fase === "pronto" && (
          <form onSubmit={enviar} className="card mt-8 space-y-4 p-6">
            <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
              {estado.ctx.papel === "partner_owner" ? "Responsável" : "Gestor"} autorizado
            </p>

            <label className="block text-sm">
              <span className="font-semibold">Unidade</span>
              <select
                value={unidade}
                onChange={(e) => setUnidade(e.target.value)}
                className="mt-1 w-full rounded-xl border-2 border-borda px-3 py-2"
              >
                {estado.ctx.unidades.map((u) => (
                  <option key={u.unit_id} value={u.unit_id}>
                    {u.name}
                  </option>
                ))}
              </select>
            </label>

            <label className="block text-sm">
              <span className="font-semibold">Código do benefício</span>
              <input
                value={codigo}
                onChange={(e) => setCodigo(e.target.value)}
                inputMode="text"
                autoComplete="off"
                spellCheck={false}
                maxLength={32}
                className="mt-1 w-full rounded-xl border-2 border-borda px-3 py-2 font-mono tracking-widest"
                placeholder="XXXX-XXXX"
                aria-label="Código do benefício"
              />
              <span className="mt-1 block text-xs text-tinta/50">
                Oito caracteres, como o usuário lê no aplicativo.
              </span>
            </label>

            <label className="flex items-start gap-3 text-sm">
              <input
                type="checkbox"
                checked={documentoConferido}
                onChange={(e) => setDocumentoConferido(e.target.checked)}
                className="mt-1"
              />
              <span>
                <span className="font-semibold">
                  Confirmo que conferi o documento com foto
                </span>
                <span className="mt-1 block text-tinta/70">
                  O benefício é pessoal. Sem essa conferência, a solicitação não
                  é enviada.
                </span>
              </span>
            </label>

            <button
              type="submit"
              disabled={enviando || !canonico || !documentoConferido || !unidade}
              className="btn-primary w-full disabled:opacity-50"
            >
              {enviando ? "Enviando..." : "Enviar solicitação"}
            </button>

            {falha && (
              <div role="alert" className="rounded-xl bg-magenta/10 p-3 text-sm text-magenta">
                {falha === "not_authorized" || falha === "not_company_owner"
                  ? "Você não está autorizado a validar nesta unidade."
                  : falha === "invalid_display_code"
                    ? "Código incompleto. Confira os oito caracteres com o usuário."
                    : falha === "request_denied"
                      ? "O aplicativo recusou esta solicitação. Nada foi consumido."
                      : "Não foi possível concluir. Nenhum benefício foi consumido."}
              </div>
            )}

            {sucesso && (
              <div className="rounded-xl bg-amarelo/25 p-4 text-sm">
                <p className="font-semibold">Solicitação enviada ao aplicativo.</p>
                <p className="mt-2 text-tinta/70">
                  O usuário precisa confirmar ou recusar no aplicativo BDFlow. O
                  benefício só é consumido depois dessa confirmação.
                </p>
                <p className="mt-2 text-xs text-tinta/50">
                  Referência: <span className="font-mono">{sucesso.correlationId}</span>
                </p>
              </div>
            )}
          </form>
        )}

      </main>
    </>
  );
}