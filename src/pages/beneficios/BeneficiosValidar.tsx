import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "../portal/portalUi";
import {
  descartarSegredoCapturado,
  lerSegredoCapturado,
  consumirSegredoParaEnvio,
  fragmentoJaEnviado,
  liberarFragmentoAposFalha,
} from "../../lib/benefitTokenFragment";
import { UUID_RE } from "../../server/benefitUsage/benefitUsageContract";
import {
  obterContextoValidador,
  type ContextoValidador,
} from "../../services/partnerApplicationService";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import {
  AvisoOperacaoOutroContexto,
  EmpresaAtualBarra,
  EscolhaEmpresa,
} from "../../portal/EmpresaSeletor";
import {
  enviarUsoDeBeneficio,
  obterStatusUsoDeBeneficio,
  type BenefitUsageRequestStatus,
} from "../../services/benefitUsageService";

/**
 * /beneficios/validar/:publicLookupId#<segredo> — validação de benefício
 * vinda do QR do aplicativo.
 *
 * Reusa a experiência e o modelo de autorização de /portal/validar: mesmo
 * cabeçalho, mesmo contexto de validador, mesma seleção de unidade. O que
 * muda é a origem do código (fragmento, não digitação) e o fato de a chamada
 * ao App acontecer de verdade, pelo endpoint de servidor.
 *
 * O segredo já foi capturado e removido da URL no import de
 * `benefitTokenFragment`. Esta tela apenas o lê da memória e o descarta ao
 * final — ele nunca entra em estado do React que possa parar num devtools
 * serializado, nem em armazenamento do navegador.
 */
type Estado =
  | { fase: "carregando" }
  | { fase: "sem_vinculo" }
  | { fase: "escolher" }
  | { fase: "inelegivel" }
  | { fase: "erro" }
  | {
      fase: "pronto";
      ctx: Extract<ContextoValidador, { tipo: "elegivel" }>;
      companyId: string;
    };

export default function BeneficiosValidar() {
  const { publicLookupId = "" } = useParams();
  const locatorValido = useMemo(() => UUID_RE.test(publicLookupId), [publicLookupId]);
  const segredoPresente = lerSegredoCapturado() !== null;

  const [estadoBruto, setEstado] = useState<Estado>({ fase: "carregando" });
  const [unidade, setUnidade] = useState("");
  const [documentoConferido, setDocumentoConferido] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [falha, setFalha] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<{
    correlationId: string;
    unitId: string;
  } | null>(null);
  const [statusUso, setStatusUso] =
    useState<BenefitUsageRequestStatus | null>(null);
  const [falhaStatus, setFalhaStatus] = useState(false);

  const empresa = useEmpresaSelecionada();
  const companyAtual = empresa.fase === "pronta" ? empresa.atual.company_id : null;
  const chaveAtual = empresa.fase === "pronta" ? empresa.chave : null;

  // Unidades e envio de uma empresa que NÃO é a atual do contexto nunca são
  // renderizados, nem por um render.
  const estado: Estado =
    estadoBruto.fase === "pronto" && estadoBruto.companyId !== companyAtual
      ? { fase: "carregando" }
      : estadoBruto;

  // Incrementa em TODA transição do contexto: A -> tela de escolha, logout,
  // revalidação que falha e troca de conta. Senão a resposta de A chegaria
  // durante a escolha e repovoaria a tela.
  const versao = useRef(0);
  const chaveRef = useRef<string | null>(null);
  chaveRef.current = chaveAtual;
  const [avisoOutroContexto, setAvisoOutroContexto] = useState(false);
  // Um envio terminou depois de a empresa ter mudado: o segredo foi descartado
  // e o resultado não é exibido (ver `enviar`).
  const [despachadaSemResultado, setDespachadaSemResultado] = useState(false);
  // Um envio foi despachado e o desfecho NÃO é conhecido por aqui.
  const [desfechoDesconhecido, setDesfechoDesconhecido] = useState(false);

  const carregar = useCallback(async () => {
    const minha = ++versao.current;
    if (empresa.fase === "carregando") return setEstado({ fase: "carregando" });
    if (empresa.fase === "erro") return setEstado({ fase: "erro" });
    if (empresa.fase === "sem_vinculo") return setEstado({ fase: "sem_vinculo" });
    // Chegada por QR com várias empresas e nenhuma escolhida: a escolha vem
    // ANTES de pedir unidades. O segredo já foi capturado em memória no import
    // do módulo e continua lá, intocado — escolher empresa não o lê, não o
    // move e não o descarta.
    if (empresa.fase === "escolher") return setEstado({ fase: "escolher" });
    // Se um envio já começou com este QR, a tela não volta a oferecer o
    // formulário sob outra empresa: o fragmento está travado e a guarda abaixo
    // explica a situação.
    if (fragmentoJaEnviado() && !sucesso) return setEstado({ fase: "carregando" });

    setEstado({ fase: "carregando" });
    const ctx = await obterContextoValidador(empresa.atual.company_id);
    if (minha !== versao.current) return; // resposta de empresa anterior
    if (ctx.tipo === "erro") return setEstado({ fase: "erro" });
    if (ctx.tipo === "inelegivel") return setEstado({ fase: "inelegivel" });
    setUnidade(ctx.unidades[0]?.unit_id ?? "");
    setEstado({ fase: "pronto", ctx, companyId: empresa.atual.company_id });
  }, [empresa]);

  useEffect(() => {
    // `fragmentoJaEnviado()` mantém o efeito ativo depois da trava: sem isto a
    // tela ficaria presa no contexto da empresa anterior.
    if (locatorValido && (segredoPresente || fragmentoJaEnviado())) void carregar();
    // Valores estáveis, não a identidade de `carregar`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locatorValido, segredoPresente, chaveAtual, empresa.fase, empresa.geracao]);

  useEffect(
    () => () => {
      versao.current++;
    },
    []
  );

  // Troca de empresa descarta a unidade e o resultado da empresa anterior. O
  // segredo NÃO é tocado aqui: ele só é descartado ao sair da tela.
  useEffect(() => {
    setUnidade("");
    setDocumentoConferido(false);
    setFalha(null);
    setSucesso(null);
    setStatusUso(null);
    setFalhaStatus(false);
    setEnviando(false);
    setDesfechoDesconhecido(false);
  }, [chaveAtual, empresa.fase, empresa.geracao]);

  // Ao sair da tela o segredo some da memória do módulo.
  useEffect(() => () => descartarSegredoCapturado(), []);

  useEffect(() => {
    if (!sucesso) return;
    if (statusUso && statusUso !== "awaiting_user_confirmation") return;

    let cancelado = false;
    let emAndamento = false;

    const consultar = async () => {
      if (emAndamento) return;
      emAndamento = true;
      const r = await obterStatusUsoDeBeneficio({
        correlationId: sucesso.correlationId,
        unitId: sucesso.unitId,
      });
      emAndamento = false;
      if (cancelado) return;

      if (r.tipo === "ok") {
        setStatusUso(r.status);
        setFalhaStatus(false);
      } else {
        setFalhaStatus(true);
      }
    };

    void consultar();
    const timer = window.setInterval(() => void consultar(), 2000);
    return () => {
      cancelado = true;
      window.clearInterval(timer);
    };
  }, [statusUso, sucesso]);

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!unidade || !documentoConferido || enviando) return;
    // Consome ANTES de despachar: a partir daqui este QR não serve para um
    // segundo envio, mesmo que a empresa mude enquanto a resposta não chega.
    const segredo = consumirSegredoParaEnvio();
    if (!segredo) return;
    setEnviando(true);
    setFalha(null);
    // Operação sensível: bloqueia a troca VOLUNTÁRIA de empresa enquanto durar.
    // Se mesmo assim a conta ou a empresa mudarem (logout, revalidação), o
    // resultado NÃO é apresentado nesta tela: seria atribuí-lo à empresa
    // errada. O servidor/App decide o desfecho e nada aqui o cancela.
    const origem = chaveRef.current;
    const fim = empresa.iniciarOperacao();
    let r: Awaited<ReturnType<typeof enviarUsoDeBeneficio>>;
    try {
      r = await enviarUsoDeBeneficio({
        publicLookupId,
        rawSecret: segredo,
        unitId: unidade,
        physicalPhotoIdChecked: true,
      });
    } finally {
      fim();
    }
    if (origem === null || chaveRef.current !== origem) {
      // O segredo foi entregue ao envio: não fica em memória para reutilização
      // sob outra empresa.
      descartarSegredoCapturado();
      setDespachadaSemResultado(true);
      setAvisoOutroContexto(true);
      return;
    }
    setEnviando(false);
    if (r.tipo !== "ok") {
      // SÓ falha PROVADAMENTE anterior ao despacho libera o QR, e só no mesmo
      // contexto. "Provadamente" aqui significa que o serviço retornou antes
      // do fetch: sem credencial, sem backend, sem conferência de documento.
      //
      // Qualquer outro desfecho fica travado, inclusive `network_error`: um
      // fetch rejeitado pode ter entregue o POST e perdido só a resposta, e
      // nesse caso um segundo envio criaria uma nova solicitação no App com
      // outra correlação. Não se pode depender de o App recusar a duplicata.
      if (r.fase === "pre_despacho") liberarFragmentoAposFalha();
      else setDesfechoDesconhecido(true);
    }
    if (r.tipo === "ok") {
      const statusInicial: BenefitUsageRequestStatus =
        r.appStatus === "confirmed" ||
        r.appStatus === "refused" ||
        r.appStatus === "expired" ||
        r.appStatus === "cancelled"
          ? r.appStatus
          : "awaiting_user_confirmation";
      setStatusUso(statusInicial);
      setFalhaStatus(false);
      setSucesso({ correlationId: r.correlationId, unitId: unidade });
      descartarSegredoCapturado();
    } else {
      setFalha(r.codigo);
    }
  };

  // A guarda de QR inválido é PRÉ-envio. Depois de um envio bem-sucedido o
  // segredo já foi descartado de propósito, e `segredoPresente` passa a ser
  // falso no render seguinte — sem `!sucesso` aqui, a tela cairia em "código
  // inválido ou incompleto" logo apos ter criado a solicitação no App, que e
  // a mensagem mais enganosa possível: diz "nenhuma validação foi
  // encaminhada" quando uma foi.
  if (
    !sucesso &&
    !enviando &&
    (!locatorValido || !segredoPresente || fragmentoJaEnviado())
  ) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
          <PortalTopo titulo="Validar benefício" />
          {avisoOutroContexto && (
            <AvisoOperacaoOutroContexto onFechar={() => setAvisoOutroContexto(false)} />
          )}
          {despachadaSemResultado || fragmentoJaEnviado() ? (
            // Aqui NÃO se pode dizer "nenhuma validação foi encaminhada": um
            // envio FOI despachado e o desfecho não é mostrado nesta tela.
            <div role="alert" className="card mt-8 p-6 text-center">
              <p className="font-semibold">
                {desfechoDesconhecido
                  ? "O envio deste QR começou e o resultado não pôde ser confirmado."
                  : "Este QR já foi enviado nesta sessão."}
              </p>
              {desfechoDesconhecido ? (
                <p className="mt-2 text-sm text-tinta/70">
                  A tentativa de envio começou, mas esta tela não tem como
                  determinar se uma solicitação chegou a ser criada ou
                  processada. Nada foi cancelado por aqui, e o estado do
                  benefício é desconhecido nesta tela. Por isso este QR não é
                  reenviado: confira a solicitação anterior antes de pedir um
                  novo QR ao divulgador.
                </p>
              ) : (
                <p className="mt-2 text-sm text-tinta/70">
                  A solicitação foi despachada e pode ter sido processada pelo
                  servidor; nada foi cancelado por aqui. Este código não pode ser
                  reenviado. Confira o resultado no contexto em que o envio começou
                  ou peça ao divulgador um novo QR no aplicativo.
                </p>
              )}
              <Link to="/portal/dashboard" className="btn-secondary mt-4 inline-block">
                Voltar ao painel
              </Link>
            </div>
          ) : (
            <div role="alert" className="card mt-8 p-6 text-center">
              <p className="font-semibold">Código de benefício inválido ou incompleto.</p>
              <p className="mt-2 text-sm text-tinta/70">
                Peça ao usuário para apresentar o QR novamente no aplicativo.
                Nenhuma validação foi encaminhada.
              </p>
              <Link to="/portal/dashboard" className="btn-secondary mt-4 inline-block">
                Voltar ao painel
              </Link>
            </div>
          )}
        </main>
      </>
    );
  }

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

        {estado.fase === "escolher" && <EscolhaEmpresa />}

        {/* Sempre presente: sem ela não há como trocar de empresa durante o
            carregamento, nem quando a empresa atual não é elegível. */}
        <EmpresaAtualBarra />

        {estado.fase === "sem_vinculo" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Esta conta não possui rede parceira ativa.</p>
          </div>
        )}

        {estado.fase === "inelegivel" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Você não está autorizado a validar.</p>
          </div>
        )}

        {estado.fase === "pronto" && !sucesso && (
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
              disabled={enviando || !documentoConferido || !unidade}
              className="btn-primary w-full disabled:opacity-50"
            >
              {enviando ? "Enviando..." : "Enviar solicitação"}
            </button>

            {falha && (
              <div role="alert" className="rounded-xl bg-magenta/10 p-3 text-sm text-magenta">
                {falha === "not_authorized"
                  ? "Você não está autorizado a validar nesta unidade."
                  : falha === "token_open_denied" || falha === "request_denied"
                    ? "O aplicativo recusou este benefício. Nada foi consumido."
                    : "Não foi possível concluir. Nenhum benefício foi consumido."}
              </div>
            )}
          </form>
        )}

        {sucesso && (
          <div className="card mt-8 space-y-2 p-6" role="status" aria-live="polite">
            {statusUso === "confirmed" ? (
              <>
                <p className="font-semibold">Uso confirmado com sucesso.</p>
                <p className="text-sm text-tinta/70">
                  O aplicativo confirmou o uso e o benefício foi consumido.
                </p>
              </>
            ) : statusUso === "refused" ? (
              <>
                <p className="font-semibold">Uso recusado pelo usuário.</p>
                <p className="text-sm text-tinta/70">
                  O benefício permanece disponível para o usuário.
                </p>
              </>
            ) : statusUso === "expired" ? (
              <>
                <p className="font-semibold">Tempo para confirmação expirou.</p>
                <p className="text-sm text-tinta/70">
                  O benefício não foi consumido.
                </p>
              </>
            ) : statusUso === "cancelled" ? (
              <>
                <p className="font-semibold">Solicitação cancelada.</p>
                <p className="text-sm text-tinta/70">
                  O benefício não foi consumido.
                </p>
              </>
            ) : (
              <>
                <p className="font-semibold">Solicitação enviada ao aplicativo.</p>
                <p className="text-sm text-tinta/70">
                  O usuário precisa confirmar ou recusar no aplicativo SmallFlags. O
                  benefício só é consumido depois dessa confirmação.
                </p>
                {falhaStatus && (
                  <p className="text-xs text-tinta/50">
                    Não foi possível atualizar o resultado agora. Tentando novamente...
                  </p>
                )}
              </>
            )}
            <p className="text-xs text-tinta/50">
              Referência: <span className="font-mono">{sucesso.correlationId}</span>
            </p>
          </div>
        )}
      </main>
    </>
  );
}
