import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import {
  AvisoOperacaoOutroContexto,
  EmpresaAtualBarra,
  EscolhaEmpresa,
} from "../../portal/EmpresaSeletor";
import {
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
  | { fase: "escolher" }
  | { fase: "inelegivel" }
  | { fase: "erro" }
  | { fase: "pronto"; ctx: Extract<ContextoValidador, { tipo: "elegivel" }>; companyId: string };

export default function PortalValidar() {
  const [estadoBruto, setEstado] = useState<Estado>({ fase: "carregando" });
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

  const empresa = useEmpresaSelecionada();
  const companyAtual = empresa.fase === "pronta" ? empresa.atual.company_id : null;
  const chaveAtual = empresa.fase === "pronta" ? empresa.chave : null;

  // Unidades e ações de uma empresa que NÃO é a atual do contexto nunca são
  // renderizadas, nem por um render: o estado guardado pode ficar atrás da troca.
  const estado: Estado =
    estadoBruto.fase === "pronto" && estadoBruto.companyId !== companyAtual
      ? { fase: "carregando" }
      : estadoBruto;

  // Incrementa em TODA transição do contexto (inclusive A -> tela de escolha,
  // logout e revalidação que falha), para que a resposta de A não repovoe a
  // tela enquanto a pessoa ainda escolhe a próxima empresa.
  const versao = useRef(0);
  const chaveRef = useRef<string | null>(null);
  chaveRef.current = chaveAtual;
  const [avisoOutroContexto, setAvisoOutroContexto] = useState(false);

  const carregar = useCallback(async () => {
    const minha = ++versao.current;
    if (empresa.fase === "carregando") return setEstado({ fase: "carregando" });
    if (empresa.fase === "erro") return setEstado({ fase: "erro" });
    if (empresa.fase === "sem_vinculo") return setEstado({ fase: "sem_vinculo" });
    if (empresa.fase === "escolher") return setEstado({ fase: "escolher" });

    // EMPRESA é diferente de UNIDADE. A empresa vem do contexto do Portal; as
    // unidades autorizadas vêm do servidor, para ESTA empresa, e a filial é
    // escolhida abaixo. Uma empresa com várias filiais não usa o seletor de
    // empresa — usa o seletor de unidade.
    setEstado({ fase: "carregando" });
    const ctx = await obterContextoValidador(empresa.atual.company_id);
    if (minha !== versao.current) return; // resposta de empresa anterior
    if (ctx.tipo === "erro") return setEstado({ fase: "erro" });
    if (ctx.tipo === "inelegivel") return setEstado({ fase: "inelegivel" });
    setUnidade(ctx.unidades[0]?.unit_id ?? "");
    setEstado({ fase: "pronto", ctx, companyId: empresa.atual.company_id });
  }, [empresa]);

  // Troca de empresa limpa tudo que era específico da anterior antes de pedir
  // qualquer coisa nova.
  useEffect(() => {
    setCodigo("");
    setUnidade("");
    setDocumentoConferido(false);
    setFalha(null);
    setSucesso(null);
    setEnviando(false);
    void carregar();
    // Valores estáveis, não a identidade de `carregar`: re-render do contexto
    // sem troca de empresa não pode apagar o código digitado.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chaveAtual, empresa.fase, empresa.geracao]);

  useEffect(
    () => () => {
      versao.current++;
    },
    []
  );

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "pronto" || !unidade || !canonico
        || !documentoConferido || enviando) return;
    setEnviando(true);
    setFalha(null);
    // Operação sensível: bloqueia a troca voluntária de empresa enquanto durar
    // e só apresenta o resultado se conta e empresa forem as mesmas de quando
    // o envio começou. O servidor/App decide o desfecho; nada aqui o cancela.
    const origem = chaveRef.current;
    const fim = empresa.iniciarOperacao();
    let r: Awaited<ReturnType<typeof enviarUsoDeBeneficioPorCodigo>>;
    try {
      r = await enviarUsoDeBeneficioPorCodigo({
        displayCode: canonico,
        unitId: unidade,
        physicalPhotoIdChecked: true,
      });
    } finally {
      fim();
    }
    if (origem === null || chaveRef.current !== origem) {
      setAvisoOutroContexto(true);
      return;
    }
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
        {avisoOutroContexto && (
          <AvisoOperacaoOutroContexto onFechar={() => setAvisoOutroContexto(false)} />
        )}

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

        {estado.fase === "escolher" && <EscolhaEmpresa />}

        {/* Sempre presente: sem ela não há como trocar de empresa durante o
            carregamento, nem quando a empresa atual não é elegível. */}
        <EmpresaAtualBarra />

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
                  O usuário precisa confirmar ou recusar no aplicativo SmallFlags. O
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