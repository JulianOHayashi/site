import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { usePortalSiteAuth } from "../hooks/usePortalSiteAuth";
import {
  obterVinculosParceiro,
  type VinculoParceiro,
} from "../services/partnerApplicationService";

/**
 * EMPRESA SELECIONADA — contexto único do Portal.
 *
 * O PROBLEMA QUE ISTO RESOLVE
 * Dashboard, Equipe, /portal/validar e /beneficios/validar escolhiam a
 * empresa cada uma por conta própria: a primeira da lista, ou o primeiro
 * vínculo de owner. Uma pessoa com vínculo em duas empresas podia estar
 * vendo a empresa A no painel e administrando a equipe da empresa B. Agora
 * existe UMA seleção, lida por todas as telas.
 *
 * O QUE ISTO NÃO É
 * Não é matriz e filial. Não há autoridade cruzada: cada vínculo carrega o
 * seu próprio papel, e escolher a empresa B nunca empresta a B o papel que a
 * pessoa tem em A. Empresa é uma coisa; unidade (filial) é outra, escolhida
 * na hora de validar — uma empresa com várias filiais não usa este seletor.
 *
 * AUTORIDADE
 * Isto é conveniência de interface, não prova de nada. O company_id escolhido
 * aqui é um parâmetro das RPCs já existentes, que continuam aplicando papel e
 * RLS no servidor. Interface travada não substitui verificação de backend.
 *
 * ERRO ≠ LISTA VAZIA
 * Falha de rede ou de contrato vira `erro` com nova tentativa. Só uma
 * resposta bem-sucedida e vazia vira `sem_vinculo`. Confundir os dois levava
 * o Dashboard a oferecer cadastro de empresa para quem já tem uma.
 *
 * RESPOSTA ATRASADA
 * Cada carga recebe um número de versão. Resposta de uma carga antiga que
 * chegue depois de outra mais nova é descartada, para que a empresa A não
 * reapareça depois de a pessoa ter trocado para a B.
 */

export type EstadoEmpresa =
  | { fase: "carregando" }
  | { fase: "erro" }
  | { fase: "sem_vinculo" }
  /**
   * A pessoa precisa escolher. `selecaoAnteriorInvalida` marca o caso em que
   * havia uma escolha (ativa ou guardada) e ela deixou de valer: nesse caso a
   * tela PRECISA mostrar a escolha mesmo que reste uma única empresa, porque
   * ativar a que sobrou em silêncio seria trocar de empresa sem que a pessoa
   * perceba — a mesma falha que este contexto existe para impedir.
   */
  | { fase: "escolher"; vinculos: VinculoParceiro[]; selecaoAnteriorInvalida: boolean }
  | {
      fase: "pronta";
      vinculos: VinculoParceiro[];
      atual: VinculoParceiro;
      /**
       * Identifica conta + empresa. Operações assíncronas guardam esta chave ao
       * começar e só apresentam resultado se ela continuar a mesma ao terminar.
       */
      chave: string;
    };

type Contexto = EstadoEmpresa & {
  /** Troca a empresa ativa. Ignora id que não esteja entre os vínculos. */
  selecionar: (companyId: string) => void;
  /** Volta ao passo de escolha sem perder a lista. */
  limparSelecao: () => void;
  recarregar: () => void;
  /**
   * Marca uma operação sensível em andamento (mutação de equipe, envio de
   * benefício). Enquanto houver alguma, a troca VOLUNTÁRIA de empresa fica
   * bloqueada. Devolve a função que encerra a marca; é idempotente.
   * Não cancela nada no servidor: só impede que a pessoa troque de empresa no
   * meio de uma operação cujo resultado ainda vai chegar.
   */
  iniciarOperacao: () => () => void;
  trocaBloqueada: boolean;
  /**
   * Muda a cada troca de empresa (e a cada recarga). As telas usam este valor
   * como chave de efeito para descartar dados da empresa anterior.
   */
  geracao: number;
};

const Ctx = createContext<Contexto | null>(null);

/** Dica de UX por usuário. NUNCA fonte de autoridade: é sempre revalidada. */
const chaveDica = (userId: string) => `smallflags_portal_empresa:${userId}`;

function lerDica(userId: string): string | null {
  try {
    return window.sessionStorage.getItem(chaveDica(userId));
  } catch {
    return null;
  }
}

/**
 * Marca de RECONHECIMENTO PENDENTE, por usuário.
 *
 * Quando uma escolha deixa de valer, apagar só a dica não basta: na carga
 * seguinte (revalidação, F5, remontagem) o estado fica idêntico ao de um
 * primeiro login, e uma empresa única voltaria a ser ativada sozinha — a troca
 * silenciosa que isto existe para impedir. A marca sobrevive a recarga e só é
 * removida quando a pessoa escolhe explicitamente uma empresa válida.
 */
const chavePendente = (userId: string) => `smallflags_portal_pendente:${userId}`;

/**
 * Espelho em memória da marca, por usuário.
 *
 * Com sessionStorage indisponível (modo restrito, cota, política do navegador)
 * a marca gravada se perderia e a carga seguinte pareceria um primeiro login,
 * reabrindo a seleção silenciosa. O espelho mantém o invariante enquanto a
 * aba viver; o que se perde sem storage é apenas a sobrevivência a um F5, e
 * isso é dito abaixo em `storageIndisponivel`.
 */
const pendenteEmMemoria = new Map<string, boolean>();

/**
 * Sonda pontual, não um sinalizador persistente: o storage pode falhar por
 * cota num momento e voltar a funcionar depois, e um sinalizador travado
 * deixaria o Portal pedindo confirmação para sempre.
 */
function storageUtilizavel(): boolean {
  try {
    const k = "smallflags_portal_sonda";
    const v = String(Date.now());
    window.sessionStorage.setItem(k, v);
    // A LEITURA é o que importa aqui: a marca de pendência é lida, não só
    // escrita. Um storage que aceita gravar mas falha ao ler devolveria
    // "sem pendência" e reabriria a seleção silenciosa — por isso o valor é
    // lido de volta e tem de bater exatamente.
    const lido = window.sessionStorage.getItem(k);
    window.sessionStorage.removeItem(k);
    return lido === v;
  } catch {
    return false;
  }
}

function lerPendente(userId: string): boolean {
  try {
    return window.sessionStorage.getItem(chavePendente(userId)) === "1";
  } catch {
    // Sem conseguir ler, o espelho é a única fonte — e, na dúvida, fecha.
    return pendenteEmMemoria.get(userId) ?? false;
  }
}

function gravarPendente(userId: string, pendente: boolean) {
  try {
    if (pendente) window.sessionStorage.setItem(chavePendente(userId), "1");
    else window.sessionStorage.removeItem(chavePendente(userId));
    // Storage é a fonte: o espelho não pode sobreviver a ele e ressuscitar
    // uma pendência já reconhecida.
    pendenteEmMemoria.delete(userId);
  } catch {
    // Só aqui o espelho entra em jogo, para manter o invariante nesta aba.
    if (pendente) pendenteEmMemoria.set(userId, true);
    else pendenteEmMemoria.delete(userId);
  }
}

function gravarDica(userId: string, companyId: string | null) {
  try {
    if (companyId === null) window.sessionStorage.removeItem(chaveDica(userId));
    else window.sessionStorage.setItem(chaveDica(userId), companyId);
  } catch {
    /* storage indisponível não pode quebrar o Portal */
  }
}

/** Um vínculo só é operável se o membro estiver ativo. */
function ativos(vinculos: VinculoParceiro[]): VinculoParceiro[] {
  return vinculos.filter((v) => v.member_status === "active");
}

export function EmpresaProvider({ children }: { children: ReactNode }) {
  const { session } = usePortalSiteAuth();
  const userId = session?.user.id ?? null;

  const [estado, setEstado] = useState<EstadoEmpresa>({ fase: "carregando" });
  const [geracao, setGeracao] = useState(0);
  const versao = useRef(0);
  // Guardado fora do estado para o efeito de carga não depender dele.
  const escolhaRef = useRef<string | null>(null);
  const pendentes = useRef(0);
  const estadoRef = useRef<EstadoEmpresa>({ fase: "carregando" });
  const [trocaBloqueada, setTrocaBloqueada] = useState(false);

  const aplicar = useCallback(
    (vinculos: VinculoParceiro[], uid: string) => {
      const lista = ativos(vinculos);

      if (lista.length === 0) {
        escolhaRef.current = null;
        gravarDica(uid, null);
        // Sem vínculo não há o que reconhecer: a marca não pode sobreviver a
        // isto e reaparecer se um vínculo for concedido mais tarde.
        gravarPendente(uid, false);
        setEstado({ fase: "sem_vinculo" });
        return;
      }

      // Reconhecimento ainda pendente de uma invalidação anterior.
      const pendente = lerPendente(uid);

      // Reconciliação: a escolha vigente (ou a dica da sessão) só vale se
      // ainda constar entre os vínculos ativos devolvidos pelo servidor.
      // Vínculo removido, suspenso ou revogado some daqui sozinho.
      const anterior = escolhaRef.current ?? lerDica(uid);
      const valido = pendente
        ? null // nada vale enquanto a pessoa não reconhecer
        : lista.find((v) => v.company_id === anterior) ?? null;

      if (valido) {
        escolhaRef.current = valido.company_id;
        gravarDica(uid, valido.company_id);
        setEstado({
          fase: "pronta",
          vinculos: lista,
          atual: valido,
          chave: `${uid}:${valido.company_id}`,
        });
        return;
      }

      escolhaRef.current = null;
      gravarDica(uid, null);

      // Havia escolha e ela perdeu a validade: NUNCA ativar em silêncio a
      // empresa que sobrou. A pessoa vê a lista (mesmo com um só item) e
      // confirma. A marca persiste até essa confirmação, para que a carga
      // seguinte não se pareça com um primeiro login.
      if (anterior !== null || pendente) {
        gravarPendente(uid, true);
        setEstado({ fase: "escolher", vinculos: lista, selecaoAnteriorInvalida: true });
        return;
      }

      // Sem storage não há como distinguir um primeiro login de uma sessão que
      // já tinha escolha: fecha e pede a confirmação em vez de ativar sozinho.
      if (!storageUtilizavel()) {
        setEstado({ fase: "escolher", vinculos: lista, selecaoAnteriorInvalida: false });
        return;
      }

      // Primeiro login legítimo com uma única empresa: seleciona sozinho.
      if (lista.length === 1) {
        escolhaRef.current = lista[0].company_id;
        gravarDica(uid, lista[0].company_id);
        setEstado({
          fase: "pronta",
          vinculos: lista,
          atual: lista[0],
          chave: `${uid}:${lista[0].company_id}`,
        });
        return;
      }

      setEstado({ fase: "escolher", vinculos: lista, selecaoAnteriorInvalida: false });
    },
    []
  );

  const carregar = useCallback(async () => {
    if (!userId) {
      // Logout: uma carga pendente da conta anterior NÃO pode mais aplicar-se.
      versao.current++;
      escolhaRef.current = null;
      setEstado({ fase: "carregando" });
      return;
    }
    const minha = ++versao.current;
    setEstado({ fase: "carregando" });
    let ctx: Awaited<ReturnType<typeof obterVinculosParceiro>>;
    try {
      ctx = await obterVinculosParceiro();
    } catch {
      if (minha === versao.current) setEstado({ fase: "erro" });
      return;
    }
    // Resposta obsoleta: outra carga começou depois desta.
    if (minha !== versao.current) return;
    if (ctx.tipo === "erro") {
      setEstado({ fase: "erro" });
      return;
    }
    aplicar(ctx.vinculos, userId);
    setGeracao((g) => g + 1);
  }, [userId, aplicar]);

  // Troca de conta zera a escolha: a empresa de uma conta nunca é herdada por
  // outra. A dica em sessionStorage é por usuário, então também não vaza.
  useEffect(() => {
    escolhaRef.current = null;
    void carregar();
  }, [carregar]);

  const selecionar = useCallback(
    (companyId: string) => {
      if (!userId) return;
      // Trocar DE uma empresa ativa durante operação em andamento é bloqueado.
      // Escolher a partir da tela de escolha é permitido: nesse ponto a tela da
      // empresa anterior já não existe e os retornos dela são descartados.
      if (pendentes.current > 0 && estadoRef.current.fase === "pronta") return;
      setEstado((atual) => {
        if (atual.fase !== "escolher" && atual.fase !== "pronta") return atual;
        const alvo = atual.vinculos.find((v) => v.company_id === companyId);
        if (!alvo) return atual; // id fora da lista não seleciona nada
        escolhaRef.current = alvo.company_id;
        gravarDica(userId, alvo.company_id);
        // Escolha explícita e válida: a pendência está reconhecida.
        gravarPendente(userId, false);
        return {
          fase: "pronta",
          vinculos: atual.vinculos,
          atual: alvo,
          chave: `${userId}:${alvo.company_id}`,
        };
      });
      // Invalida o que as telas carregaram para a empresa anterior.
      setGeracao((g) => g + 1);
    },
    [userId]
  );

  const limparSelecao = useCallback(() => {
    if (!userId) return;
    if (pendentes.current > 0) return; // há operação em andamento
    escolhaRef.current = null;
    gravarDica(userId, null);
    setEstado((atual) =>
      atual.fase === "pronta" || atual.fase === "escolher"
        ? { fase: "escolher", vinculos: atual.vinculos, selecaoAnteriorInvalida: false }
        : atual
    );
    setGeracao((g) => g + 1);
  }, [userId]);

  const iniciarOperacao = useCallback(() => {
    pendentes.current += 1;
    setTrocaBloqueada(true);
    let encerrada = false;
    return () => {
      if (encerrada) return;
      encerrada = true;
      pendentes.current -= 1;
      if (pendentes.current === 0) setTrocaBloqueada(false);
    };
  }, []);

  estadoRef.current = estado;

  // Valor memoizado: sem isso, QUALQUER re-render do provider (por exemplo o
  // refresh de token da sessão) criava um objeto novo, e as telas que dependem
  // dele reiniciavam formulários e recarregavam dados sem motivo.
  const valor = useMemo<Contexto>(
    () => ({
      ...estado,
      selecionar,
      limparSelecao,
      recarregar: carregar,
      iniciarOperacao,
      trocaBloqueada,
      geracao,
    }),
    [estado, selecionar, limparSelecao, carregar, iniciarOperacao, trocaBloqueada, geracao]
  );

  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

export function useEmpresaSelecionada(): Contexto {
  const v = useContext(Ctx);
  if (!v) throw new Error("useEmpresaSelecionada exige EmpresaProvider");
  return v;
}

/**
 * Papel na empresa ATUAL. Owner em A e manager em B devolve "partner_manager"
 * quando B está selecionada — o papel nunca atravessa a fronteira da empresa.
 */
export function usePapelAtual(): VinculoParceiro["role"] | null {
  const ctx = useEmpresaSelecionada();
  return ctx.fase === "pronta" ? ctx.atual.role : null;
}

/**
 * Variante que NÃO lança fora do provider. Serve a componentes compartilhados
 * (como o topo do Portal) que também possam ser montados sem a casca.
 */
export function useEmpresaOpcional(): Contexto | null {
  return useContext(Ctx);
}
