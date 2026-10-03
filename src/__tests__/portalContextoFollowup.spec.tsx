import { useLayoutEffect } from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { screen, cleanup, fireEvent, waitFor, within, act } from "@testing-library/react";
import { renderPortal, SESSAO_FALSA } from "./helpers/portalRender";

/**
 * FOLLOW-UP DA AUDITORIA — contexto de empresa no Portal.
 *
 * Cada bloco corresponde a um apontamento. O que estes testes provam e o que
 * NÃO provam: provam o comportamento da INTERFACE com RPCs simuladas. Não
 * provam autorização — quem autoriza é o servidor. A ordem real de Tab/Shift+Tab
 * não é simulável em jsdom e é verificada no navegador (ver evidência).
 */

const obterVinculosParceiro = vi.fn();
const obterContextoValidador = vi.fn();
const carregarEquipeOwner = vi.fn();
const ownerCriarUnidade = vi.fn();
const ownerConvidarManager = vi.fn();
const ownerRevogarConviteManager = vi.fn();
const ownerDefinirStatusManager = vi.fn();
const ownerDefinirVinculoManager = vi.fn();
const enviarUsoDeBeneficioPorCodigo = vi.fn();
let sessao: { session: { user: { id: string; email: string } } | null } = SESSAO_FALSA("user-1");

vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { signOut: vi.fn() } },
  supabaseConfigurado: true,
}));
vi.mock("../hooks/usePortalSiteAuth", () => ({
  usePortalSiteAuth: () => sessao,
}));
vi.mock("../services/partnerApplicationService", () => ({
  obterVinculosParceiro: (...a: unknown[]) => obterVinculosParceiro(...a),
  obterContextoValidador: (...a: unknown[]) => obterContextoValidador(...a),
  carregarEquipeOwner: (...a: unknown[]) => carregarEquipeOwner(...a),
  ownerCriarUnidade: (...a: unknown[]) => ownerCriarUnidade(...a),
  ownerConvidarManager: (...a: unknown[]) => ownerConvidarManager(...a),
  ownerRevogarConviteManager: (...a: unknown[]) => ownerRevogarConviteManager(...a),
  ownerDefinirStatusManager: (...a: unknown[]) => ownerDefinirStatusManager(...a),
  ownerDefinirVinculoManager: (...a: unknown[]) => ownerDefinirVinculoManager(...a),
  mensagemDeMotivo: (m: string) => `Falha: ${m}`,
}));
vi.mock("../services/benefitUsageService", () => ({
  enviarUsoDeBeneficioPorCodigo: (...a: unknown[]) => enviarUsoDeBeneficioPorCodigo(...a),
  enviarUsoDeBeneficio: vi.fn(),
  obterStatusUsoDeBeneficio: vi.fn(),
}));

import PortalDashboard from "../pages/portal/PortalDashboard";
import PortalEquipe from "../pages/portal/PortalEquipe";
import PortalValidar from "../pages/portal/PortalValidar";
import { useEmpresaSelecionada } from "../portal/empresaContexto";

const A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

const vinculo = (
  id: string,
  nome: string,
  role: "partner_owner" | "partner_manager" = "partner_owner"
) => ({
  company_id: id,
  trade_name: nome,
  company_status: "active",
  member_id: `m-${id}`,
  role,
  member_status: "active",
  city: "Vitória",
  uf: "ES",
});

const equipeDe = (id: string) => ({
  ok: true,
  dados: {
    unidades: [{
      id: `u-${id}`, company_id: id, name: `Filial ${id.slice(0, 1).toUpperCase()}`,
      city: "Vitória", uf: "ES", status: "active",
    }],
    convites: [],
    membros: [{
      id: `mg-${id}`, role: "partner_manager", status: "active",
      full_name: `Manager ${id.slice(0, 1).toUpperCase()}`, email: `m@${id.slice(0, 1)}.com`,
    }],
    vinculosUnidade: [],
  },
});

function adiado<T>() {
  let resolver!: (v: T) => void;
  const promessa = new Promise<T>((r) => {
    resolver = r;
  });
  return { promessa, resolver };
}

const duasOwner = () => ({
  tipo: "ok",
  vinculos: [vinculo(A, "Empresa A"), vinculo(B, "Empresa B")],
});

beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
  sessao = SESSAO_FALSA("user-1");
  obterContextoValidador.mockResolvedValue({
    tipo: "elegivel",
    papel: "partner_owner",
    unidades: [{ unit_id: "u-1", name: "Filial 1", branch_bridge_id: "b1" }],
  });
});
afterEach(() => cleanup());

const escolher = async (nome: RegExp) =>
  fireEvent.click(await screen.findByRole("button", { name: nome }));
const tick = () => act(async () => { await new Promise((r) => setTimeout(r, 30)); });

/** Botão auxiliar que dispara a revalidação do contexto, como um retry faria. */
function RecarregarContexto() {
  const ctx = useEmpresaSelecionada();
  return <button onClick={ctx.recarregar}>revalidar-contexto</button>;
}

/* ===================================================================== */
/* 1. Seleção invalidada não ativa em silêncio a empresa que sobrou       */
/* ===================================================================== */
describe("1. seleção invalidada versus primeira carga", () => {
  it("B escolhida; revalidação devolve só A: B é limpa e A NÃO é ativada", async () => {
    obterVinculosParceiro.mockResolvedValue(duasOwner());
    renderPortal(
      <>
        <PortalDashboard />
        <RecarregarContexto />
      </>
    );
    await escolher(/Empresa B/);
    await screen.findByText(/empresa ativa:/i);

    // O servidor passa a devolver apenas A.
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    fireEvent.click(screen.getByText("revalidar-contexto"));

    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    // A empresa que sobrou NÃO foi ativada: não há "empresa ativa" nem atalhos.
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
    expect(screen.queryByRole("heading", { name: "Validar benefício" })).toBeNull();
    // A pessoa é avisada de que a escolha anterior deixou de valer.
    expect(screen.getByText(/não está mais disponível para a sua conta/i)).toBeDefined();
    expect(screen.getByText(/nada foi ativado automaticamente/i)).toBeDefined();

    // Só ativa quando a pessoa confirma.
    await escolher(/Empresa A/);
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa A");
  });

  it("primeira carga com só A, sem escolha anterior: auto-seleciona A", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    renderPortal(<PortalDashboard />);
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa A");
    expect(screen.queryByRole("heading", { name: /escolha a empresa/i })).toBeNull();
  });

  it("dica de sessão para B inexistente, só A na carga: pede escolha, não ativa A", async () => {
    sessionStorage.setItem("smallflags_portal_empresa:user-1", B);
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    renderPortal(<PortalDashboard />);
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
    // Uma única opção: o texto fica no singular.
    expect(screen.getByText(/vínculo ativo em 1 empresa\./i)).toBeDefined();
  });
});

/* ===================================================================== */
/* 1b. O reconhecimento pendente SOBREVIVE a revalidação e a remontagem   */
/* ===================================================================== */
describe("1b. reconhecimento pendente é persistente", () => {
  const soA = { tipo: "ok", vinculos: [vinculo(A, "Empresa A")] };

  it("B revogada com A restante: escolha agora, de novo na revalidação, de novo após remontagem", async () => {
    obterVinculosParceiro.mockResolvedValue(duasOwner());
    const r1 = renderPortal(
      <>
        <PortalDashboard />
        <RecarregarContexto />
      </>
    );
    await escolher(/Empresa B/);
    await screen.findByText(/empresa ativa:/i);

    // B é revogada; resta apenas A.
    obterVinculosParceiro.mockResolvedValue(soA);
    fireEvent.click(screen.getByText("revalidar-contexto"));

    // (i) escolha imediata, sem ativar A
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();

    // (ii) nova revalidação SEM escolher: continua pedindo o reconhecimento
    fireEvent.click(screen.getByText("revalidar-contexto"));
    await tick();
    expect(
      screen.getByRole("heading", { name: /escolha a empresa desta sessão/i })
    ).toBeDefined();
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
    expect(screen.getByText(/não está mais disponível para a sua conta/i)).toBeDefined();

    // (iii) remontagem completa (equivale a recarregar a página) SEM escolher:
    // o provider parte do zero e NÃO pode tratar isto como primeiro login.
    r1.unmount();
    renderPortal(
      <>
        <PortalDashboard />
        <RecarregarContexto />
      </>
    );
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();

    // (iv) escolha explícita encerra a pendência…
    await escolher(/Empresa A/);
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa A");

    // …e a partir daí uma revalidação mantém A ativa, sem repetir a pergunta.
    fireEvent.click(screen.getByText("revalidar-contexto"));
    await tick();
    expect(screen.getByText(/empresa ativa:/i).closest("p")!.textContent).toContain("Empresa A");
    expect(screen.queryByRole("heading", { name: /escolha a empresa/i })).toBeNull();
  });

  it("primeiro login legítimo com uma empresa continua automático após remontagem", async () => {
    obterVinculosParceiro.mockResolvedValue(soA);
    const r = renderPortal(<PortalDashboard />);
    await screen.findByText(/empresa ativa:/i);
    r.unmount();

    renderPortal(<PortalDashboard />);
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa A");
    expect(screen.queryByRole("heading", { name: /escolha a empresa/i })).toBeNull();
  });

  it("perder todos os vínculos limpa a pendência: um vínculo novo depois não pede reconhecimento", async () => {
    obterVinculosParceiro.mockResolvedValue(duasOwner());
    renderPortal(
      <>
        <PortalDashboard />
        <RecarregarContexto />
      </>
    );
    await escolher(/Empresa B/);
    await screen.findByText(/empresa ativa:/i);

    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [] });
    fireEvent.click(screen.getByText("revalidar-contexto"));
    await screen.findByText(/cadastre sua empresa parceira/i);

    obterVinculosParceiro.mockResolvedValue(soA);
    fireEvent.click(screen.getByText("revalidar-contexto"));
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa A");
  });
});

/* ===================================================================== */
/* 1c. sessionStorage indisponível nunca causa troca silenciosa           */
/* ===================================================================== */
describe("1c. storage indisponível", () => {
  /** Faz sessionStorage lançar em qualquer acesso, como num modo restrito. */
  function quebrarStorage() {
    const real = window.sessionStorage;
    Object.defineProperty(window, "sessionStorage", {
      configurable: true,
      get() {
        throw new DOMException("acesso negado", "SecurityError");
      },
    });
    return () => Object.defineProperty(window, "sessionStorage", {
      configurable: true,
      value: real,
      writable: true,
    });
  }

  /**
   * Substitui sessionStorage por um duplo em que SÓ a leitura falha. É o caso
   * que a sonda anterior não via: ela testava setItem/removeItem, então dava o
   * storage por bom, e `lerPendente` devolvia "sem pendência" — reabrindo a
   * seleção silenciosa de uma empresa única.
   */
  function quebrarSomenteLeitura() {
    const real = window.sessionStorage;
    const dados = new Map<string, string>();
    const duplo = {
      getItem() {
        throw new DOMException("leitura negada", "SecurityError");
      },
      setItem: (k: string, v: string) => void dados.set(k, v),
      removeItem: (k: string) => void dados.delete(k),
      clear: () => dados.clear(),
      key: () => null,
      get length() {
        return dados.size;
      },
    } as unknown as Storage;
    Object.defineProperty(window, "sessionStorage", {
      configurable: true,
      get: () => duplo,
    });
    return () =>
      Object.defineProperty(window, "sessionStorage", {
        configurable: true,
        value: real,
        writable: true,
      });
  }

  it("getItem falhando (set/remove funcionam) NÃO auto-seleciona a empresa única", async () => {
    const restaurar = quebrarSomenteLeitura();
    try {
      obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
      renderPortal(<PortalDashboard />);
      await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
      expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
      expect(screen.queryByRole("heading", { name: "Validar benefício" })).toBeNull();

      // A escolha explícita continua funcionando mesmo sem leitura.
      await escolher(/Empresa A/);
      const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
      expect(barra.textContent).toContain("Empresa A");
    } finally {
      restaurar();
    }
  });

  it("com uma empresa só e storage quebrado, pede confirmação em vez de ativar sozinho", async () => {
    const restaurar = quebrarStorage();
    try {
      obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
      renderPortal(<PortalDashboard />);
      // Fail-closed: sem storage não dá para distinguir primeiro login de
      // sessão que já tinha escolha, então nada é ativado em silêncio.
      await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
      expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
      expect(screen.queryByRole("heading", { name: "Validar benefício" })).toBeNull();

      // A escolha explícita continua funcionando sem storage.
      await escolher(/Empresa A/);
      const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
      expect(barra.textContent).toContain("Empresa A");
    } finally {
      restaurar();
    }
  });

  it("o Portal não quebra: nenhum erro escapa do acesso ao storage", async () => {
    const restaurar = quebrarStorage();
    try {
      obterVinculosParceiro.mockResolvedValue(duasOwner());
      renderPortal(<PortalDashboard />);
      await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
      await escolher(/Empresa B/);
      const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
      expect(barra.textContent).toContain("Empresa B");
    } finally {
      restaurar();
    }
  });
});

/* ===================================================================== */
/* 2. Cargas pendentes invalidadas a cada transição de contexto           */
/* ===================================================================== */
describe("2. resposta pendente de A durante a tela de escolha", () => {
  beforeEach(() => obterVinculosParceiro.mockResolvedValue(duasOwner()));

  it("Equipe: A responde durante a escolha e NADA de A aparece", async () => {
    const lentoA = adiado<unknown>();
    carregarEquipeOwner.mockImplementation((id: string) =>
      id === A ? lentoA.promessa : Promise.resolve(equipeDe(B))
    );
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await escolher(/Empresa A/);
    await waitFor(() => expect(carregarEquipeOwner).toHaveBeenCalledWith(A));

    // Sai de A para a tela de escolha com a carga de A ainda pendente.
    fireEvent.click(await screen.findByRole("button", { name: /trocar de empresa/i }));
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });

    // A responde AGORA, com a pessoa ainda escolhendo.
    await act(async () => {
      lentoA.resolver(equipeDe(A));
    });
    await tick();

    // A tela de escolha continua lá: a resposta de A não a substitui.
    expect(screen.getByRole("heading", { name: /escolha a empresa desta sessão/i })).toBeDefined();
    expect(screen.queryByText("Filial A")).toBeNull();
    expect(screen.queryByText("Manager A")).toBeNull();
    expect(screen.queryByRole("tablist")).toBeNull();
    // Nenhuma ação pode usar a seleção antiga.
    expect(screen.queryByRole("button", { name: /criar unidade/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /enviar convite/i })).toBeNull();

    // E continua correto depois de escolher B.
    await escolher(/Empresa B/);
    expect(await screen.findByText("Filial B")).toBeDefined();
    expect(screen.queryByText("Filial A")).toBeNull();
  });

  it("Validação manual: A responde durante a escolha e o seletor de unidade não aparece", async () => {
    const lentoA = adiado<unknown>();
    obterContextoValidador.mockImplementation((id: string) =>
      id === A
        ? lentoA.promessa
        : Promise.resolve({
            tipo: "elegivel", papel: "partner_owner",
            unidades: [{ unit_id: "u-b", name: "Loja B", branch_bridge_id: "bb" }],
          })
    );
    renderPortal(<PortalValidar />, { rotas: ["/portal/validar"] });
    await escolher(/Empresa A/);
    await waitFor(() => expect(obterContextoValidador).toHaveBeenCalledWith(A));
    fireEvent.click(await screen.findByRole("button", { name: /trocar de empresa/i }));
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });

    await act(async () => {
      lentoA.resolver({
        tipo: "elegivel", papel: "partner_owner",
        unidades: [{ unit_id: "u-a", name: "Loja A", branch_bridge_id: "ba" }],
      });
    });
    await tick();

    expect(screen.getByRole("heading", { name: /escolha a empresa desta sessão/i })).toBeDefined();
    expect(screen.queryByLabelText(/unidade/i)).toBeNull();
    expect(screen.queryByText("Loja A")).toBeNull();
    expect(screen.queryByRole("button", { name: /enviar solicitação/i })).toBeNull();
  });

  it("logout com a carga de contexto pendente: a conta anterior não se aplica", async () => {
    const lento = adiado<unknown>();
    obterVinculosParceiro.mockReturnValue(lento.promessa);
    const r = renderPortal(<PortalDashboard />);
    await screen.findByText(/carregando suas empresas/i);

    sessao = { session: null };
    r.rerenderPortal();
    await act(async () => {
      lento.resolver({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    });
    await tick();

    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
    expect(screen.queryByText("Empresa A")).toBeNull();
    expect(screen.queryByText(/cadastre sua empresa parceira/i)).toBeNull();
  });

  it("troca de conta: a resposta tardia da conta 1 não vale para a conta 2", async () => {
    const lento1 = adiado<unknown>();
    obterVinculosParceiro.mockReturnValueOnce(lento1.promessa);
    const r = renderPortal(<PortalDashboard />);
    await screen.findByText(/carregando suas empresas/i);

    sessao = SESSAO_FALSA("user-2", "outra@example.com");
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(B, "Empresa B")] });
    r.rerenderPortal();
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa B");

    await act(async () => {
      lento1.resolver({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    });
    await tick();
    expect(screen.queryByText("Empresa A")).toBeNull();
    expect(screen.getByText(/empresa ativa:/i).closest("p")!.textContent).toContain("Empresa B");
  });
});

/* ===================================================================== */
/* 2b. O render INTERMEDIÁRIO também não mostra dados de outra empresa    */
/* ===================================================================== */
describe("2b. nenhum commit exibe dados da empresa anterior", () => {
  it("ao sair de A para a escolha, a tela não mostra Filial A nem por um commit", async () => {
    obterVinculosParceiro.mockResolvedValue(duasOwner());
    carregarEquipeOwner.mockImplementation(async (id: string) => equipeDe(id));

    // useLayoutEffect roda no MESMO commit, antes dos efeitos passivos que
    // limpam o estado: é onde um render atrasado em relação à troca apareceria.
    const commits: { fase: string; vendoFilialA: boolean; vendoAcoes: boolean }[] = [];
    function Sonda() {
      const ctx = useEmpresaSelecionada();
      useLayoutEffect(() => {
        commits.push({
          fase: ctx.fase === "pronta" ? `pronta:${ctx.atual.company_id}` : ctx.fase,
          vendoFilialA: document.body.textContent?.includes("Filial A") ?? false,
          vendoAcoes: !!screen.queryByRole("button", { name: /criar unidade/i }),
        });
      });
      return null;
    }

    renderPortal(
      <>
        <PortalEquipe />
        <Sonda />
      </>,
      { rotas: ["/portal/equipe"] }
    );
    await escolher(/Empresa A/);
    await screen.findByText("Filial A");
    commits.length = 0; // só interessa o que acontece a partir da saída de A

    fireEvent.click(screen.getByRole("button", { name: /trocar de empresa/i }));
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    await escolher(/Empresa B/);
    await screen.findByText("Filial B");

    const fora = commits.filter((c) => c.fase !== `pronta:${A}`);
    expect(fora.length).toBeGreaterThan(0);
    // Em NENHUM commit fora de A há dados ou ações de A à vista.
    expect(fora.filter((c) => c.vendoFilialA || c.vendoAcoes)).toEqual([]);
  });
});

/* ===================================================================== */
/* 3. Operação em andamento atravessando troca de empresa                 */
/* ===================================================================== */
describe("3. operação em andamento e troca de empresa", () => {
  beforeEach(() => {
    obterVinculosParceiro.mockResolvedValue(duasOwner());
    carregarEquipeOwner.mockImplementation(async (id: string) => equipeDe(id));
  });

  async function abrirCriacaoDeUnidade() {
    const r = renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await escolher(/Empresa A/);
    await screen.findByText("Filial A");
    fireEvent.change(screen.getByLabelText(/nome da unidade/i), { target: { value: "Filial Nova" } });
    return r;
  }

  it("a troca voluntária fica bloqueada, com explicação, enquanto a mutação não termina", async () => {
    const pend = adiado<unknown>();
    ownerCriarUnidade.mockReturnValue(pend.promessa);
    await abrirCriacaoDeUnidade();
    fireEvent.click(screen.getByRole("button", { name: /criar unidade/i }));
    await waitFor(() => expect(ownerCriarUnidade).toHaveBeenCalledWith(A, "Filial Nova", "Vitória", "ES"));

    const trocar = screen.getByRole("button", { name: /trocar de empresa/i }) as HTMLButtonElement;
    expect(trocar.disabled).toBe(true);
    expect(screen.getByText(/há uma operação em andamento/i)).toBeDefined();
    fireEvent.click(trocar);
    expect(screen.queryByRole("heading", { name: /escolha a empresa/i })).toBeNull();

    await act(async () => {
      pend.resolver({ ok: true });
    });
    expect(await screen.findByText("Unidade criada.")).toBeDefined();
    expect((screen.getByRole("button", { name: /trocar de empresa/i }) as HTMLButtonElement).disabled).toBe(false);
  });

  it("mutação que termina depois de mudança INVOLUNTÁRIA não vira sucesso nem recarrega a empresa antiga", async () => {
    const pend = adiado<unknown>();
    ownerCriarUnidade.mockReturnValue(pend.promessa);
    const r = await abrirCriacaoDeUnidade();
    fireEvent.click(screen.getByRole("button", { name: /criar unidade/i }));
    await waitFor(() => expect(ownerCriarUnidade).toHaveBeenCalled());
    const cargasAntes = carregarEquipeOwner.mock.calls.length;

    // Perda de sessão no meio da operação: o provider relê o hook e a chave
    // conta+empresa deixa de existir.
    sessao = { session: null };
    r.rerenderPortal();
    await act(async () => {
      pend.resolver({ ok: true });
    });
    await tick();

    // Nada é apresentado como sucesso da empresa atual…
    expect(screen.queryByText("Unidade criada.")).toBeNull();
    // …a empresa antiga NÃO é recarregada por um callback obsoleto…
    expect(carregarEquipeOwner.mock.calls.length).toBe(cargasAntes);
    // …e a pessoa é informada, sem afirmar que a operação foi cancelada.
    const aviso = await screen.findByText(/resposta recebida depois da mudança de empresa/i);
    expect(aviso.textContent).toMatch(/(não foi|nada foi)\s+cancelad[ao]/i);
  });
});

/* ===================================================================== */
/* 3b. Envio manual de benefício atravessando mudança de contexto         */
/* ===================================================================== */
describe("3b. envio manual de benefício em andamento", () => {
  beforeEach(() => obterVinculosParceiro.mockResolvedValue(duasOwner()));

  async function prepararEnvio() {
    const r = renderPortal(<PortalValidar />, { rotas: ["/portal/validar"] });
    await escolher(/Empresa A/);
    const campo = (await screen.findByLabelText(/código do benefício/i)) as HTMLInputElement;
    fireEvent.change(campo, { target: { value: "ABCD7K2M" } });
    fireEvent.click(screen.getByRole("checkbox"));
    return r;
  }

  it("bloqueia a troca de empresa durante o envio e depois libera", async () => {
    const pend = adiado<unknown>();
    enviarUsoDeBeneficioPorCodigo.mockReturnValue(pend.promessa);
    await prepararEnvio();
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(enviarUsoDeBeneficioPorCodigo).toHaveBeenCalledTimes(1));

    expect((screen.getByRole("button", { name: /trocar de empresa/i }) as HTMLButtonElement).disabled).toBe(true);

    await act(async () => {
      pend.resolver({ tipo: "ok", correlationId: "corr-123" });
    });
    await waitFor(() =>
      expect((screen.getByRole("button", { name: /trocar de empresa/i }) as HTMLButtonElement).disabled).toBe(false)
    );
  });

  it("resposta que chega depois de mudança involuntária não mostra correlação nem sucesso", async () => {
    const pend = adiado<unknown>();
    enviarUsoDeBeneficioPorCodigo.mockReturnValue(pend.promessa);
    const r = await prepararEnvio();
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(enviarUsoDeBeneficioPorCodigo).toHaveBeenCalledTimes(1));

    sessao = { session: null };
    r.rerenderPortal();
    await act(async () => {
      pend.resolver({ tipo: "ok", correlationId: "corr-123" });
    });
    await tick();

    expect(document.body.textContent).not.toContain("corr-123");
    expect(screen.queryByText(/solicitação (criada|enviada)/i)).toBeNull();
    expect(screen.queryByLabelText(/código do benefício/i)).toBeNull();
  });
});

/* ===================================================================== */
/* 4. Diálogo de revogação: semântica verdadeira                          */
/* ===================================================================== */
describe("4. diálogo de revogação não modal", () => {
  beforeEach(() => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    carregarEquipeOwner.mockResolvedValue(equipeDe(A));
  });

  async function abrirDialogo() {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    fireEvent.change(await screen.findByLabelText(/motivo da revogação/i), {
      target: { value: "saiu da empresa" },
    });
    fireEvent.click(screen.getByRole("button", { name: /revogar acesso definitivamente/i }));
    return screen.getByRole("alertdialog");
  }

  it("não declara aria-modal e tem nome e descrição acessíveis", async () => {
    const dialogo = await abrirDialogo();
    expect(dialogo.hasAttribute("aria-modal")).toBe(false);
    const rotulo = document.getElementById(dialogo.getAttribute("aria-labelledby")!);
    const descricao = document.getElementById(dialogo.getAttribute("aria-describedby")!);
    expect(rotulo?.textContent).toMatch(/revogar definitivamente o acesso de/i);
    expect(descricao?.textContent).toMatch(/não pode ser desfeita/i);
  });

  it("o foco entra no botão de confirmar", async () => {
    const dialogo = await abrirDialogo();
    await waitFor(() => expect(dialogo.contains(document.activeElement)).toBe(true));
    expect((document.activeElement as HTMLElement).textContent).toMatch(/sim, revogar/i);
  });

  it("Escape cancela mesmo com o foco FORA do diálogo, e o foco volta ao gatilho remontado", async () => {
    await abrirDialogo();
    (screen.getByLabelText(/motivo da revogação/i) as HTMLElement).focus();
    expect(screen.getByRole("alertdialog").contains(document.activeElement)).toBe(false);

    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("alertdialog")).toBeNull();
    await waitFor(() =>
      expect(document.activeElement).toBe(
        screen.getByRole("button", { name: /revogar acesso definitivamente/i })
      )
    );
    expect(ownerDefinirStatusManager).not.toHaveBeenCalled();
  });

  it("confirmar chama a RPC uma vez, com o manager e o motivo", async () => {
    ownerDefinirStatusManager.mockResolvedValue({ ok: true });
    const dialogo = await abrirDialogo();
    fireEvent.click(within(dialogo).getByRole("button", { name: /sim, revogar definitivamente/i }));
    await waitFor(() => expect(ownerDefinirStatusManager).toHaveBeenCalledTimes(1));
    expect(ownerDefinirStatusManager).toHaveBeenCalledWith(`mg-${A}`, "revoke", "saiu da empresa");
  });

  it("recusa do servidor é visível e não vira sucesso", async () => {
    ownerDefinirStatusManager.mockResolvedValue({ ok: false, motivo: "forbidden" });
    const dialogo = await abrirDialogo();
    fireEvent.click(within(dialogo).getByRole("button", { name: /sim, revogar definitivamente/i }));
    expect(await screen.findByText(/falha: forbidden/i)).toBeDefined();
    expect(screen.queryByText(/acesso do manager revogado/i)).toBeNull();
  });
});

/* ===================================================================== */
/* 5. Topo do Portal sem empresa selecionada                              */
/* ===================================================================== */
describe("5. navegação do topo enquanto se escolhe a empresa", () => {
  it("esconde Validar QR e Solicitações, mantém Início e Sair", async () => {
    obterVinculosParceiro.mockResolvedValue(duasOwner());
    renderPortal(<PortalDashboard />);
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });

    const nav = screen.getAllByRole("navigation")[0];
    expect(within(nav).getByRole("link", { name: /início/i })).toBeDefined();
    expect(within(nav).queryByRole("link", { name: /validar qr/i })).toBeNull();
    expect(within(nav).queryByRole("link", { name: /solicitações/i })).toBeNull();
    expect(within(nav).getByRole("button", { name: /sair/i })).toBeDefined();
  });

  it("com empresa selecionada, os quatro itens estão presentes", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    renderPortal(<PortalDashboard />);
    await screen.findByText(/empresa ativa:/i);
    const nav = screen.getAllByRole("navigation")[0];
    for (const nome of [/início/i, /validar qr/i, /solicitações/i]) {
      expect(within(nav).getByRole("link", { name: nome })).toBeDefined();
    }
    expect(within(nav).getByRole("button", { name: /sair/i })).toBeDefined();
  });

  it("durante erro de consulta também não oferece destinos dependentes de empresa", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "erro" });
    renderPortal(<PortalDashboard />);
    await screen.findByText(/não foi possível carregar suas empresas/i);
    const nav = screen.getAllByRole("navigation")[0];
    expect(within(nav).queryByRole("link", { name: /validar qr/i })).toBeNull();
    expect(within(nav).getByRole("link", { name: /início/i })).toBeDefined();
  });
});
