import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import { emailValido } from "../../lib/onboardingValidacao";
import { useEmpresaSelecionada } from "../../portal/empresaContexto";
import {
  AvisoOperacaoOutroContexto,
  EmpresaAtualBarra,
  EscolhaEmpresa,
} from "../../portal/EmpresaSeletor";
import {
  carregarEquipeOwner,
  mensagemDeMotivo,
  obterVinculosParceiro,
  ownerConvidarManager,
  ownerCriarUnidade,
  ownerDefinirStatusManager,
  ownerDefinirVinculoManager,
  ownerRevogarConviteManager,
  type ConviteManager,
  type EquipeOwner,
  type MembroEmpresa,
} from "../../services/partnerApplicationService";

type Estado =
  | { fase: "carregando" }
  | { fase: "negado" }
  | { fase: "escolher" }
  | { fase: "erro"; mensagem: string }
  | { fase: "ok"; companyId: string; tradeName: string; dados: EquipeOwner };

const ABAS = [
  { id: "unidades", rotulo: "Unidades" },
  { id: "managers", rotulo: "Managers" },
  { id: "convites", rotulo: "Convites" },
] as const;

const STATUS_MEMBRO: Record<string, string> = {
  active: "Ativo",
  suspended: "Suspenso",
  revoked: "Revogado definitivamente",
};

const STATUS_UNIDADE: Record<string, string> = {
  active: "Ativa",
  suspended: "Suspensa",
  archived: "Arquivada",
};

const STATUS_CONVITE: Record<string, string> = {
  pending: "Pendente",
  accepted: "Aceito",
  revoked: "Revogado",
  expired: "Expirado",
  superseded: "Substituído",
};

export default function PortalEquipe() {
  const [estadoBruto, setEstado] = useState<Estado>({ fase: "carregando" });
  // Id do manager cuja revogação definitiva está aguardando confirmação.
  const [confirmandoRevogacao, setConfirmandoRevogacao] = useState<string | null>(null);
  const [aba, setAba] = useState<"unidades" | "managers" | "convites">("unidades");
  const abasRef = useRef<Record<string, HTMLButtonElement | null>>({});
  const confirmarRef = useRef<HTMLButtonElement | null>(null);
  // Id do botão que abriu a confirmação. O botão é desmontado enquanto o
  // diálogo está aberto, então o foco só pode ser devolvido DEPOIS que ele
  // volta a ser renderizado — por id, não por referência ao nó antigo.
  const gatilhoRevogacaoId = useRef<string | null>(null);

  /**
   * Teclado do tablist, como manda o padrão: setas movem e ativam, Home/End
   * vão aos extremos, e só a aba ativa é tabulável (roving tabIndex) para que
   * Tab atravesse o grupo em vez de parar em cada aba.
   */
  // Ao abrir a confirmação, o foco vai para o botão de confirmar; ao fechar,
  // volta para o gatilho. Sem isso o leitor de tela não percebe o diálogo.
  useEffect(() => {
    if (confirmandoRevogacao) confirmarRef.current?.focus();
  }, [confirmandoRevogacao]);

  const fecharConfirmacao = useCallback(() => {
    setConfirmandoRevogacao(null);
  }, []);

  // Escape cancela a confirmação de qualquer ponto da página enquanto ela
  // estiver aberta — o diálogo é não modal, então o foco pode estar fora dele.
  useEffect(() => {
    if (confirmandoRevogacao === null) return;
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === "Escape") fecharConfirmacao();
    };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, [confirmandoRevogacao, fecharConfirmacao]);

  useEffect(() => {
    if (confirmandoRevogacao !== null || !gatilhoRevogacaoId.current) return;
    const alvo = document.getElementById(gatilhoRevogacaoId.current);
    gatilhoRevogacaoId.current = null;
    alvo?.focus();
  }, [confirmandoRevogacao]);

  const teclasAba = (e: React.KeyboardEvent, indice: number) => {
    const teclas: Record<string, number> = {
      ArrowRight: indice + 1,
      ArrowLeft: indice - 1,
      Home: 0,
      End: ABAS.length - 1,
    };
    const alvo = teclas[e.key];
    if (alvo === undefined) return;
    e.preventDefault();
    const destino = ABAS[(alvo + ABAS.length) % ABAS.length];
    setAba(destino.id);
    abasRef.current[destino.id]?.focus();
  };
  const [nomeUnidade, setNomeUnidade] = useState("");
  const [cidade, setCidade] = useState("");
  const [uf, setUf] = useState("");
  const [nomeManager, setNomeManager] = useState("");
  const [emailManager, setEmailManager] = useState("");
  const [unitId, setUnitId] = useState("");
  const [acao, setAcao] = useState<string | null>(null);
  const [mensagem, setMensagem] = useState<string | null>(null);
  const [motivosRevogacao, setMotivosRevogacao] = useState<Record<string, string>>({});

  const empresa = useEmpresaSelecionada();
  const companyAtual = empresa.fase === "pronta" ? empresa.atual.company_id : null;
  const chaveAtual = empresa.fase === "pronta" ? empresa.chave : null;

  // NUNCA renderizar dados ou ações de uma empresa que não é a atual do
  // contexto. O estado guardado pode ficar um render atrás da troca; este
  // espelho o descarta na hora, antes de o efeito de carga rodar.
  const estado: Estado =
    estadoBruto.fase === "ok" && estadoBruto.companyId !== companyAtual
      ? { fase: "carregando" }
      : estadoBruto;

  // Número de versão da carga. Resposta de uma empresa anterior que chegue
  // atrasada é descartada em vez de repovoar a tela com dados de outra.
  // Incrementa em TODA transição do contexto, não só ao carregar uma empresa:
  // senão A responderia durante a tela de escolha e repovoaria a tela.
  const versao = useRef(0);
  const chaveRef = useRef<string | null>(null);
  chaveRef.current = chaveAtual;
  const [avisoOutroContexto, setAvisoOutroContexto] = useState(false);

  /**
   * Executa uma operação sensível marcando-a no contexto (bloqueia a troca
   * voluntária de empresa enquanto durar) e informa se, ao terminar, a conta e
   * a empresa continuam as mesmas de quando ela começou. Se não continuam, o
   * resultado NÃO é apresentado: seria atribuí-lo à empresa errada. O servidor
   * segue decidindo; nada aqui afirma que a operação foi cancelada.
   */
  const executar = async <T,>(op: () => Promise<T>) => {
    const origem = chaveRef.current;
    const fim = empresa.iniciarOperacao();
    try {
      const r = await op();
      const vigente = origem !== null && chaveRef.current === origem;
      if (!vigente) setAvisoOutroContexto(true);
      return { r, vigente };
    } finally {
      fim();
    }
  };

  const carregar = useCallback(async () => {
    const minha = ++versao.current;
    if (empresa.fase === "carregando") return setEstado({ fase: "carregando" });
    if (empresa.fase === "erro") {
      return setEstado({
        fase: "erro",
        mensagem: "Não foi possível carregar o contexto da empresa.",
      });
    }
    if (empresa.fase === "sem_vinculo") return setEstado({ fase: "negado" });
    if (empresa.fase === "escolher") return setEstado({ fase: "escolher" });

    const atual = empresa.atual;
    // AUTORIDADE POR EMPRESA: só administra quem é responsável ATIVO NESTA
    // empresa. Ser owner de outra não vale aqui, e a tela não troca de
    // empresa por conta própria para encontrar uma onde a pessoa seja owner.
    if (atual.role !== "partner_owner" || atual.member_status !== "active") {
      return setEstado({ fase: "negado" });
    }

    setEstado({ fase: "carregando" });
    const equipe = await carregarEquipeOwner(atual.company_id);
    if (minha !== versao.current) return; // resposta obsoleta
    if (!equipe.ok) {
      setEstado({ fase: "erro", mensagem: mensagemDeMotivo(equipe.motivo) });
      return;
    }

    setEstado({
      fase: "ok",
      companyId: atual.company_id,
      tradeName: atual.trade_name,
      dados: equipe.dados,
    });
    setCidade(atual.city || "");
    setUf(atual.uf || "");
  }, [empresa]);

  // `geracao` muda a cada troca de empresa: tudo que é específico da empresa
  // anterior é descartado antes de qualquer nova requisição.
  useEffect(() => {
    setMensagem(null);
    setMotivosRevogacao({});
    setConfirmandoRevogacao(null);
    setAba("unidades");
    setNomeUnidade("");
    setNomeManager("");
    setEmailManager("");
    setUnitId("");
    setAcao(null);
    void carregar();
    // Depende de valores estáveis, não da identidade de `carregar`: o contexto
    // pode re-renderizar sem que a empresa tenha mudado, e isso não pode
    // apagar formulários nem recarregar.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chaveAtual, empresa.fase, empresa.geracao]);

  // Ao sair da tela, nenhuma carga pendente pode mais aplicar-se.
  useEffect(
    () => () => {
      versao.current++;
    },
    []
  );

  const unidadesAtivas = useMemo(
    () =>
      estado.fase === "ok"
        ? estado.dados.unidades.filter((u) => u.status === "active")
        : [],
    [estado]
  );

  useEffect(() => {
    if (!unitId && unidadesAtivas.length === 1) {
      setUnitId(unidadesAtivas[0].id);
    }
  }, [unitId, unidadesAtivas]);

  const criarUnidade = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "ok") return;
    setMensagem(null);

    if (nomeUnidade.trim().length < 2 || cidade.trim().length < 2 || uf.trim().length !== 2) {
      setMensagem("Informe nome, cidade e UF da unidade.");
      return;
    }

    setAcao("unidade");
    const { r, vigente } = await executar(() =>
      ownerCriarUnidade(
        estado.companyId,
        nomeUnidade.trim(),
        cidade.trim(),
        uf.trim().toUpperCase()
      )
    );
    if (!vigente) return;
    setAcao(null);

    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }

    setNomeUnidade("");
    setMensagem("Unidade criada.");
    await carregar();
  };

  const convidar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "ok") return;
    setMensagem(null);

    if (nomeManager.trim().length < 3) {
      setMensagem("Informe o nome do manager.");
      return;
    }
    if (!emailValido(emailManager)) {
      setMensagem("Informe um e-mail válido.");
      return;
    }
    if (!unitId) {
      setMensagem("Selecione a unidade em que o manager poderá validar.");
      return;
    }

    setAcao("convite");
    const { r, vigente } = await executar(() =>
      ownerConvidarManager(estado.companyId, emailManager, nomeManager, unitId)
    );
    if (!vigente) return;
    setAcao(null);

    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }

    setNomeManager("");
    setEmailManager("");
    setMensagem("Convite criado e colocado na fila de envio. O prazo de 48 horas começa quando o link for despachado.");
    await carregar();
  };

  const revogar = async (convite: ConviteManager) => {
    if (acao || convite.status !== "pending") return;
    setMensagem(null);
    setAcao(convite.id);
    const { r, vigente } = await executar(() => ownerRevogarConviteManager(convite.id));
    if (!vigente) return;
    setAcao(null);
    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }
    setMensagem("Convite revogado.");
    await carregar();
  };

  const alterarStatusManager = async (
    manager: MembroEmpresa,
    action: "suspend" | "reactivate" | "revoke"
  ) => {
    if (acao) return;
    const motivo = motivosRevogacao[manager.id]?.trim() ?? "";
    if (action === "revoke" && motivo.length < 3) {
      setMensagem("Informe o motivo da revogação do manager.");
      return;
    }

    setMensagem(null);
    setAcao(`status:${manager.id}:${action}`);
    const { r, vigente } = await executar(() =>
      ownerDefinirStatusManager(
        manager.id,
        action,
        action === "revoke" ? motivo : undefined
      )
    );
    if (!vigente) return;
    setAcao(null);

    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }

    if (action === "suspend") setMensagem("Manager suspenso.");
    if (action === "reactivate") setMensagem("Manager reativado.");
    if (action === "revoke") setMensagem("Acesso do manager revogado.");

    if (action === "revoke") {
      setMotivosRevogacao((atual) => ({ ...atual, [manager.id]: "" }));
    }
    await carregar();
  };

  const alterarVinculoManager = async (
    manager: MembroEmpresa,
    unitIdAlvo: string,
    bound: boolean
  ) => {
    if (acao || manager.status !== "active") return;

    setMensagem(null);
    setAcao(`binding:${manager.id}:${unitIdAlvo}`);
    const { r, vigente } = await executar(() =>
      ownerDefinirVinculoManager(
        manager.id,
        unitIdAlvo,
        bound,
        bound ? undefined : "Desvinculado pelo responsável da empresa"
      )
    );
    if (!vigente) return;
    setAcao(null);

    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }

    setMensagem(bound ? "Unidade vinculada ao manager." : "Unidade removida do manager.");
    await carregar();
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Equipe e unidades" />

        <EmpresaAtualBarra />
        {avisoOutroContexto && (
          <AvisoOperacaoOutroContexto onFechar={() => setAvisoOutroContexto(false)} />
        )}

        {estado.fase === "carregando" && (
          <p className="mt-10 text-center text-sm text-tinta/60" role="status">
            Carregando equipe...
          </p>
        )}

        {estado.fase === "escolher" && <EscolhaEmpresa />}

        {estado.fase === "negado" && (
          <section className="card mt-8 p-8 text-center" role="alert">
            <h2 className="text-xl font-bold">Acesso restrito ao responsável da empresa</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Nesta empresa você não é o responsável. Managers não convidam
              outros managers nem alteram unidades. Ser responsável em outra
              empresa não dá acesso a esta.
            </p>
          </section>
        )}

        {estado.fase === "erro" && (
          <section className="card mt-8 p-8 text-center" role="alert">
            <p>{estado.mensagem}</p>
            <button className="btn-secondary mt-4" onClick={() => void carregar()}>
              Tentar novamente
            </button>
          </section>
        )}

        {estado.fase === "ok" && (
          <>
            <section className="card mt-5 p-6">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                Empresa
              </p>
              <h2 className="mt-1 text-xl font-bold">{estado.tradeName}</h2>
            </section>

            {mensagem && (
              <p className="mt-5 rounded-xl bg-ciano/10 px-4 py-3 text-sm" role="status">
                {mensagem}
              </p>
            )}

            <div
              role="tablist"
              aria-label="Seções de equipe e unidades"
              className="mt-6 flex flex-wrap gap-2 border-b border-borda"
            >
              {ABAS.map((a, i) => (
                <button
                  key={a.id}
                  type="button"
                  role="tab"
                  id={`aba-${a.id}`}
                  ref={(el) => {
                    abasRef.current[a.id] = el;
                  }}
                  aria-selected={aba === a.id}
                  aria-controls={`painel-${a.id}`}
                  tabIndex={aba === a.id ? 0 : -1}
                  onKeyDown={(e) => teclasAba(e, i)}
                  onClick={() => setAba(a.id)}
                  className={`-mb-px min-h-[44px] border-b-2 px-4 py-2 text-sm font-semibold transition ${
                    aba === a.id
                      ? "border-magenta text-tinta"
                      : "border-transparent text-tinta/60 hover:text-tinta"
                  }`}
                >
                  {a.rotulo}
                  <span className="ml-2 rounded-full bg-papel2 px-2 py-0.5 text-xs tabular-nums">
                    {a.id === "unidades"
                      ? estado.dados.unidades.length
                      : a.id === "managers"
                        ? estado.dados.membros.filter((m) => m.role === "partner_manager").length
                        : estado.dados.convites.length}
                  </span>
                </button>
              ))}
            </div>

            <div
              id="painel-unidades"
              role="tabpanel"
              aria-labelledby="aba-unidades"
              tabIndex={0}
              hidden={aba !== "unidades"}
            >
            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <form onSubmit={criarUnidade} className="card space-y-4 p-6">
                <div>
                  <h2 className="text-xl font-bold">Cadastrar unidade</h2>
                  <p className="mt-1 text-sm text-tinta/60">
                    Managers só validam nas unidades às quais estiverem vinculados.
                  </p>
                </div>
                <div>
                  <label htmlFor="unidade-nome" className="mb-1 block text-sm font-semibold">
                    Nome da unidade
                  </label>
                  <input
                    id="unidade-nome"
                    value={nomeUnidade}
                    onChange={(e) => setNomeUnidade(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                    placeholder="Ex.: Matriz Vitória"
                  />
                </div>
                <div className="grid gap-3 sm:grid-cols-[1fr_100px]">
                  <div>
                    <label htmlFor="unidade-cidade" className="mb-1 block text-sm font-semibold">
                      Cidade
                    </label>
                    <input
                      id="unidade-cidade"
                      value={cidade}
                      onChange={(e) => setCidade(e.target.value)}
                      className="w-full rounded-xl border border-borda px-4 py-3"
                    />
                  </div>
                  <div>
                    <label htmlFor="unidade-uf" className="mb-1 block text-sm font-semibold">
                      UF
                    </label>
                    <input
                      id="unidade-uf"
                      value={uf}
                      onChange={(e) => setUf(e.target.value.toUpperCase())}
                      maxLength={2}
                      className="w-full rounded-xl border border-borda px-4 py-3"
                    />
                  </div>
                </div>
                <button disabled={acao !== null} className="btn-secondary w-full" type="submit">
                  {acao === "unidade" ? "Criando..." : "Criar unidade"}
                </button>
              </form>

              <form onSubmit={convidar} className="card space-y-4 p-6">
                <div>
                  <h2 className="text-xl font-bold">Convidar manager</h2>
                  <p className="mt-1 text-sm text-tinta/60">
                    O convite é pessoal, vinculado ao e-mail informado e expira em 48 horas.
                  </p>
                </div>
                <div>
                  <label htmlFor="manager-nome" className="mb-1 block text-sm font-semibold">
                    Nome
                  </label>
                  <input
                    id="manager-nome"
                    value={nomeManager}
                    onChange={(e) => setNomeManager(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                  />
                </div>
                <div>
                  <label htmlFor="manager-email" className="mb-1 block text-sm font-semibold">
                    E-mail
                  </label>
                  <input
                    id="manager-email"
                    type="email"
                    value={emailManager}
                    onChange={(e) => setEmailManager(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                  />
                </div>
                <div>
                  <label htmlFor="manager-unidade" className="mb-1 block text-sm font-semibold">
                    Unidade inicial
                  </label>
                  <select
                    id="manager-unidade"
                    value={unitId}
                    onChange={(e) => setUnitId(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                  >
                    <option value="">Selecione</option>
                    {unidadesAtivas.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.name} — {u.city}/{u.uf}
                      </option>
                    ))}
                  </select>
                </div>
                <button
                  disabled={acao !== null || unidadesAtivas.length === 0}
                  className="btn-primary w-full"
                  type="submit"
                >
                  {acao === "convite" ? "Criando convite..." : "Enviar convite"}
                </button>
                {unidadesAtivas.length === 0 && (
                  <p className="text-xs text-tinta/60">
                    Cadastre ao menos uma unidade ativa antes de convidar um manager.
                  </p>
                )}
              </form>
            </div>

            <section className="card mt-6 p-6">
              <h2 className="text-xl font-bold">Unidades</h2>
              {estado.dados.unidades.length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhuma unidade cadastrada.</p>
              ) : (
                <div className="mt-4 space-y-3">
                  {estado.dados.unidades.map((u) => (
                    <div key={u.id} className="rounded-xl border border-borda p-4">
                      <div className="flex flex-wrap justify-between gap-2">
                        <strong>{u.name}</strong>
                        <span className="text-sm text-tinta/70">
                          {STATUS_UNIDADE[u.status] ?? u.status}
                        </span>
                      </div>
                      <p className="mt-1 text-sm text-tinta/60">{u.city}/{u.uf}</p>
                    </div>
                  ))}
                </div>
              )}
            </section>
            </div>

            <div
              id="painel-managers"
              role="tabpanel"
              aria-labelledby="aba-managers"
              tabIndex={0}
              hidden={aba !== "managers"}
            >
            <section className="card mt-6 p-6">
              <h2 className="text-xl font-bold">Managers</h2>
              <p className="mt-1 text-sm text-tinta/60">
                Suspenda, reative, revogue o acesso ou altere as unidades em que cada manager pode validar.
              </p>
              {estado.dados.membros.filter((m) => m.role === "partner_manager").length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhum manager ativo ou histórico.</p>
              ) : (
                <div className="mt-4 space-y-4">
                  {estado.dados.membros
                    .filter((m) => m.role === "partner_manager")
                    .map((m) => {
                      const vinculosAtivos = new Set(
                        estado.dados.vinculosUnidade
                          .filter((v) => v.member_id === m.id && v.status === "active")
                          .map((v) => v.unit_id)
                      );
                      const emAcao = acao?.includes(m.id) ?? false;

                      return (
                        <div key={m.id} className="rounded-xl border border-borda p-4">
                          <div className="flex flex-wrap items-start justify-between gap-3">
                            <div>
                              <strong>{m.full_name}</strong>
                              {m.email && <p className="mt-1 text-sm text-tinta/60">{m.email}</p>}
                            </div>
                            <span className="text-sm font-semibold">
                              {STATUS_MEMBRO[m.status] ?? m.status}
                            </span>
                          </div>

                          <div className="mt-4">
                            <p className="text-sm font-semibold">Unidades autorizadas</p>
                            {unidadesAtivas.length === 0 ? (
                              <p className="mt-2 text-sm text-tinta/60">Nenhuma unidade ativa.</p>
                            ) : (
                              <div className="mt-2 grid gap-2 sm:grid-cols-2">
                                {unidadesAtivas.map((u) => {
                                  const vinculado = vinculosAtivos.has(u.id);
                                  return (
                                    <label
                                      key={u.id}
                                      className="flex items-center gap-2 rounded-lg border border-borda px-3 py-2 text-sm"
                                    >
                                      <input
                                        type="checkbox"
                                        checked={vinculado}
                                        disabled={m.status !== "active" || acao !== null}
                                        onChange={(e) =>
                                          void alterarVinculoManager(m, u.id, e.target.checked)
                                        }
                                      />
                                      <span>{u.name} — {u.city}/{u.uf}</span>
                                    </label>
                                  );
                                })}
                              </div>
                            )}
                            {m.status === "suspended" && (
                              <p className="mt-2 text-xs text-tinta/60">
                                Reative o manager antes de alterar os vínculos de unidade.
                              </p>
                            )}
                            {m.status === "revoked" && (
                              <p className="mt-2 text-xs text-tinta/60">
                                Este acesso foi revogado e não pode ser reativado por esta tela.
                              </p>
                            )}
                          </div>

                          {m.status !== "revoked" && (
                            <div className="mt-4 border-t border-borda pt-4">
                              <div className="flex flex-wrap gap-2">
                                {m.status === "active" && (
                                  <button
                                    type="button"
                                    className="btn-secondary"
                                    disabled={acao !== null}
                                    onClick={() => void alterarStatusManager(m, "suspend")}
                                  >
                                    {acao === `status:${m.id}:suspend` ? "Suspendendo..." : "Suspender"}
                                  </button>
                                )}
                                {m.status === "suspended" && (
                                  <button
                                    type="button"
                                    className="btn-secondary"
                                    disabled={acao !== null}
                                    onClick={() => void alterarStatusManager(m, "reactivate")}
                                  >
                                    {acao === `status:${m.id}:reactivate` ? "Reativando..." : "Reativar"}
                                  </button>
                                )}
                              </div>

                              <label
                                htmlFor={`motivo-revogacao-${m.id}`}
                                className="mt-4 block text-sm font-semibold"
                              >
                                Motivo da revogação
                              </label>
                              <input
                                id={`motivo-revogacao-${m.id}`}
                                value={motivosRevogacao[m.id] ?? ""}
                                onChange={(e) =>
                                  setMotivosRevogacao((atual) => ({
                                    ...atual,
                                    [m.id]: e.target.value,
                                  }))
                                }
                                disabled={emAcao}
                                className="mt-1 w-full rounded-xl border border-borda px-4 py-3"
                                placeholder="Obrigatório para revogar"
                              />
                              {confirmandoRevogacao === m.id ? (
                                /* NÃO MODAL, de propósito. Não há contenção de foco
                                    nem exclusão do fundo, então aria-modal="true"
                                    seria uma afirmação falsa. O que existe e é
                                    verdadeiro: o diálogo é anunciado (alertdialog),
                                    recebe o foco ao abrir, fecha com Escape de
                                    qualquer ponto e devolve o foco ao botão de
                                    origem. A ação só ocorre no clique explícito. */
                                <div
                                  role="alertdialog"
                                  aria-labelledby={`confirma-revogacao-${m.id}`}
                                  aria-describedby={`confirma-detalhe-${m.id}`}
                                  className="mt-3 rounded-xl border-2 border-magenta/40 bg-magenta/5 p-4"
                                >
                                  <p
                                    id={`confirma-revogacao-${m.id}`}
                                    className="text-sm font-semibold text-tinta"
                                  >
                                    Revogar definitivamente o acesso de {m.full_name}?
                                  </p>
                                  <p
                                    id={`confirma-detalhe-${m.id}`}
                                    className="mt-1 text-sm text-tinta/75"
                                  >
                                    Esta ação não pode ser desfeita. O acesso não volta
                                    por reativação nem por um novo convite para o mesmo
                                    e-mail. Para afastamento temporário, use Suspender.
                                  </p>
                                  <div className="mt-3 flex flex-wrap gap-2">
                                    <button
                                      type="button"
                                      ref={confirmarRef}
                                      disabled={acao !== null}
                                      onClick={() => void alterarStatusManager(m, "revoke")}
                                      className="min-h-[44px] rounded-xl bg-magenta px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
                                    >
                                      {acao === `status:${m.id}:revoke`
                                        ? "Revogando..."
                                        : "Sim, revogar definitivamente"}
                                    </button>
                                    <button
                                      type="button"
                                      disabled={acao !== null}
                                      onClick={fecharConfirmacao}
                                      className="min-h-[44px] rounded-xl border border-borda px-4 py-2 text-sm font-semibold disabled:opacity-50"
                                    >
                                      Cancelar
                                    </button>
                                  </div>
                                </div>
                              ) : (
                                <button
                                  type="button"
                                  id={`revogar-${m.id}`}
                                  className="mt-2 min-h-[44px] text-sm font-semibold text-magenta hover:underline disabled:opacity-50"
                                  disabled={acao !== null}
                                  onClick={() => {
                                    gatilhoRevogacaoId.current = `revogar-${m.id}`;
                                    setConfirmandoRevogacao(m.id);
                                  }}
                                >
                                  Revogar acesso definitivamente
                                </button>
                              )}
                            </div>
                          )}
                        </div>
                      );
                    })}
                </div>
              )}
            </section>
            </div>

            <div
              id="painel-convites"
              role="tabpanel"
              aria-labelledby="aba-convites"
              tabIndex={0}
              hidden={aba !== "convites"}
            >
            <section className="card mt-6 p-6">
              <h2 className="text-xl font-bold">Convites</h2>
              {estado.dados.convites.length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhum convite criado.</p>
              ) : (
                <div className="mt-4 space-y-3">
                  {estado.dados.convites.map((c) => {
                    const unidade = estado.dados.unidades.find((u) => u.id === c.unit_id);
                    return (
                      <div key={c.id} className="rounded-xl border border-borda p-4">
                        <div className="flex flex-wrap items-start justify-between gap-3">
                          <div>
                            <strong>{c.full_name}</strong>
                            <p className="text-sm text-tinta/60">{c.email}</p>
                            <p className="mt-1 text-xs text-tinta/50">
                              {unidade ? `Unidade: ${unidade.name}` : "Sem unidade vinculada"}
                            </p>
                          </div>
                          <div className="text-right">
                            <span className="text-sm font-semibold">
                              {STATUS_CONVITE[c.status] ?? c.status}
                            </span>
                            {c.status === "pending" && (
                              <button
                                type="button"
                                disabled={acao !== null}
                                onClick={() => void revogar(c)}
                                className="mt-2 block text-sm font-semibold text-magenta hover:underline"
                              >
                                {acao === c.id ? "Revogando..." : "Revogar"}
                              </button>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </section>
            </div>
          </>
        )}
      </main>
    </>
  );
}
