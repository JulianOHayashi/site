import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { screen, cleanup, fireEvent, waitFor, within } from "@testing-library/react";
import { renderPortal, SESSAO_FALSA } from "./helpers/portalRender";

/**
 * MATRIZ DOS NOVE CENÁRIOS DE ACEITAÇÃO — contexto de empresa no Portal.
 *
 * O que estes testes provam e o que NÃO provam.
 *
 * PROVAM: que a interface lê uma única empresa selecionada, que o papel não
 * atravessa a fronteira da empresa, que trocar de empresa descarta o estado da
 * anterior e que resposta atrasada não repovoa a tela.
 *
 * NÃO PROVAM: autorização. As RPCs são simuladas. Quem autoriza de verdade é o
 * servidor, com papel e RLS, e nenhum teste aqui substitui isso. Um company_id
 * escolhido no navegador nunca é prova de autoridade.
 */

const obterVinculosParceiro = vi.fn();
const obterContextoValidador = vi.fn();
const carregarEquipeOwner = vi.fn();
const ownerCriarUnidade = vi.fn();
const ownerConvidarManager = vi.fn();
const ownerRevogarConviteManager = vi.fn();
const ownerDefinirStatusManager = vi.fn();
const ownerDefinirVinculoManager = vi.fn();
let sessao = SESSAO_FALSA("user-1");

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
  // Exportada pelo serviço real e usada pela tela para traduzir o motivo de
  // recusa. Sem ela o caminho de erro lança — e foi assim que este mock deixou
  // a recusa da RPC sem teste de verdade.
  mensagemDeMotivo: (m: string) => `Falha: ${m}`,
}));
vi.mock("../services/benefitUsageService", () => ({
  enviarUsoDeBeneficioPorCodigo: vi.fn(),
  enviarUsoDeBeneficio: vi.fn(),
  obterStatusUsoDeBeneficio: vi.fn(),
}));

import PortalDashboard from "../pages/portal/PortalDashboard";
import PortalEquipe from "../pages/portal/PortalEquipe";
import PortalValidar from "../pages/portal/PortalValidar";

const A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

const vinculo = (
  id: string,
  nome: string,
  role: "partner_owner" | "partner_manager" = "partner_owner",
  member_status = "active"
) => ({
  company_id: id,
  trade_name: nome,
  company_status: "active",
  member_id: `m-${id}`,
  role,
  member_status,
  city: "Vitória",
  uf: "ES",
});

const equipeDe = (unidade: string) => ({
  ok: true,
  dados: {
    unidades: [{
      id: `u-${unidade}`, company_id: unidade, name: `Filial ${unidade.slice(0, 1).toUpperCase()}`,
      city: "Vitória", uf: "ES", status: "active",
    }],
    convites: [],
    membros: [{
      id: `mg-${unidade}`, role: "partner_manager", status: "active",
      full_name: `Manager ${unidade.slice(0, 1).toUpperCase()}`,
      email: `m@${unidade.slice(0, 1)}.com`,
    }],
    vinculosUnidade: [],
  },
});

beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
  sessao = SESSAO_FALSA("user-1");
  obterContextoValidador.mockResolvedValue({
    tipo: "elegivel",
    unidades: [{ unit_id: "u-1", name: "Filial 1" }],
  });
});
afterEach(() => cleanup());

const escolher = async (nome: RegExp) =>
  fireEvent.click(await screen.findByRole("button", { name: nome }));

/* 1 ------------------------------------------------------------------ */
describe("1. Uma empresa com duas unidades", () => {
  it("não pede escolha de empresa; a filial é que é escolhida na validação", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    obterContextoValidador.mockResolvedValue({
      tipo: "elegivel",
      unidades: [
        { unit_id: "u-1", name: "Matriz" },
        { unit_id: "u-2", name: "Filial Serra" },
      ],
    });
    renderPortal(<PortalValidar />, { rotas: ["/portal/validar"] });

    // Nenhum passo de escolha de EMPRESA.
    await waitFor(() => expect(obterContextoValidador).toHaveBeenCalledWith(A));
    expect(screen.queryByRole("heading", { name: /escolha a empresa/i })).toBeNull();

    // A escolha que existe é de UNIDADE.
    const unidades = await screen.findByLabelText(/unidade/i);
    expect(within(unidades as HTMLElement).getAllByRole("option")).toHaveLength(2);
  });
});

/* 2 ------------------------------------------------------------------ */
describe("2. Duas empresas de owner: escolher B vale em todas as telas", () => {
  beforeEach(() => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A"), vinculo(B, "Empresa B")],
    });
    carregarEquipeOwner.mockResolvedValue(equipeDe(B));
  });

  it("escolhendo B no painel, a equipe carrega B e nunca A", async () => {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await escolher(/Empresa B/);
    await waitFor(() => expect(carregarEquipeOwner).toHaveBeenCalledWith(B));
    expect(carregarEquipeOwner).not.toHaveBeenCalledWith(A);
  });

  it("escolhendo B, a validação pede as unidades de B", async () => {
    renderPortal(<PortalValidar />, { rotas: ["/portal/validar"] });
    await escolher(/Empresa B/);
    await waitFor(() => expect(obterContextoValidador).toHaveBeenCalledWith(B));
    expect(obterContextoValidador).not.toHaveBeenCalledWith(A);
  });

  it("o painel mostra B como empresa ativa, não A", async () => {
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    await escolher(/Empresa B/);
    const barra = (await screen.findByText(/empresa ativa:/i)).closest("p")!;
    expect(barra.textContent).toContain("Empresa B");
    expect(barra.textContent).not.toContain("Empresa A");
  });
});

/* 3 ------------------------------------------------------------------ */
describe("3. Owner em A, manager em B", () => {
  beforeEach(() => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A", "partner_owner"), vinculo(B, "Empresa B", "partner_manager")],
    });
  });

  it("com B selecionada, a equipe nega e NÃO troca para A por baixo", async () => {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await escolher(/Empresa B/);
    expect(await screen.findByText(/acesso restrito ao responsável/i)).toBeDefined();
    // O ponto central: nenhuma carga de equipe, muito menos a de A.
    expect(carregarEquipeOwner).not.toHaveBeenCalled();
  });

  it("com B selecionada, a validação é permitida como manager de B", async () => {
    renderPortal(<PortalValidar />, { rotas: ["/portal/validar"] });
    await escolher(/Empresa B/);
    await waitFor(() => expect(obterContextoValidador).toHaveBeenCalledWith(B));
  });

  it("com B selecionada, o painel não oferece o atalho de equipe", async () => {
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    await escolher(/Empresa B/);
    await screen.findByText(/empresa ativa:/i);
    expect(screen.queryByRole("heading", { name: "Equipe e unidades" })).toBeNull();
  });
});

/* 4 ------------------------------------------------------------------ */
describe("4. Trocar de A para B limpa o estado de A", () => {
  beforeEach(() => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A"), vinculo(B, "Empresa B")],
    });
  });

  it("dados da equipe de A somem ao trocar para B", async () => {
    carregarEquipeOwner.mockImplementation(async (id: string) =>
      id === A ? equipeDe(A) : equipeDe(B)
    );
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await escolher(/Empresa A/);
    expect(await screen.findByText("Filial A")).toBeDefined();

    fireEvent.click(screen.getByRole("button", { name: /trocar de empresa/i }));
    await escolher(/Empresa B/);
    await waitFor(() => expect(screen.queryByText("Filial A")).toBeNull());
    expect(await screen.findByText("Filial B")).toBeDefined();
  });

  it("resposta lenta de A que chega depois de B NÃO repovoa a tela", async () => {
    let liberarA: (v: unknown) => void = () => {};
    carregarEquipeOwner.mockImplementation(
      (id: string) =>
        id === A
          ? new Promise((r) => {
              liberarA = r;
            })
          : Promise.resolve(equipeDe(B))
    );
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await escolher(/Empresa A/);          // fica pendente
    await waitFor(() => expect(carregarEquipeOwner).toHaveBeenCalledWith(A));

    fireEvent.click(await screen.findByRole("button", { name: /trocar de empresa/i }));
    await escolher(/Empresa B/);
    expect(await screen.findByText("Filial B")).toBeDefined();

    liberarA(equipeDe(A));                 // A responde tarde demais
    await waitFor(() => expect(screen.queryByText("Filial A")).toBeNull());
    expect(screen.getByText("Filial B")).toBeDefined();
  });
});

/* 5 ------------------------------------------------------------------ */
describe("5. Lista vazia versus erro de backend", () => {
  it("lista vazia é ausência real de vínculo", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [] });
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    expect(await screen.findByText(/cadastre sua empresa parceira/i)).toBeDefined();
  });

  it("erro NÃO vira ausência de vínculo e oferece nova tentativa", async () => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "erro" });
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    expect(await screen.findByText(/não foi possível carregar suas empresas/i)).toBeDefined();
    expect(screen.queryByText(/cadastre sua empresa parceira/i)).toBeNull();
  });

  it("nova tentativa bem-sucedida restaura a seleção", async () => {
    obterVinculosParceiro.mockResolvedValueOnce({ tipo: "erro" });
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    await screen.findByText(/não foi possível carregar suas empresas/i);

    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    fireEvent.click(screen.getByRole("button", { name: /tentar novamente/i }));
    expect(await screen.findByText(/empresa ativa:/i)).toBeDefined();
  });
});

/* 6 ------------------------------------------------------------------ */
describe("6. Vínculo perdido e troca de conta", () => {
  it("vínculo suspenso deixa de ser operável", async () => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A", "partner_owner", "suspended")],
    });
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    // Nenhum vínculo ATIVO: não há empresa a operar.
    expect(await screen.findByText(/cadastre sua empresa parceira/i)).toBeDefined();
  });

  it("empresa escolhida que some da lista não é mantida", async () => {
    sessionStorage.setItem("smallflags_portal_empresa:user-1", B);
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A"), vinculo("cccccccc-cccc-4ccc-8ccc-cccccccccccc", "Empresa C")],
    });
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    // B não existe mais: volta à escolha, sem cair em A.
    expect(await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i })).toBeDefined();
    expect(screen.queryByText(/empresa ativa:/i)).toBeNull();
  });

  it("outra conta não herda a empresa escolhida pela anterior", async () => {
    sessionStorage.setItem("smallflags_portal_empresa:user-1", B);
    sessao = SESSAO_FALSA("user-2", "outra@example.com");
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A"), vinculo(B, "Empresa B")],
    });
    renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    expect(await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i })).toBeDefined();
  });
});

/* 7 ------------------------------------------------------------------ */
describe("7. Sem empresa escolhida, não há atalho ativável", () => {
  it("os atalhos não existem no DOM, nem como link focável", async () => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A"), vinculo(B, "Empresa B")],
    });
    const { container } = renderPortal(<PortalDashboard />, { rotas: ["/portal/dashboard"] });
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });

    // Não é um link "visualmente desabilitado": simplesmente não está lá, logo
    // não é alcançável por Tab nem por Enter.
    expect(screen.queryByRole("heading", { name: "Validar benefício" })).toBeNull();
    expect(container.querySelector('a[href="/portal/equipe"]')).toBeNull();
  });

  it("acesso direto à equipe sem escolha não carrega dados de empresa nenhuma", async () => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [vinculo(A, "Empresa A"), vinculo(B, "Empresa B")],
    });
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    expect(carregarEquipeOwner).not.toHaveBeenCalled();
  });
});

/* 8 ------------------------------------------------------------------ */
describe("8. Abas por teclado e diálogo de revogação", () => {
  beforeEach(() => {
    obterVinculosParceiro.mockResolvedValue({ tipo: "ok", vinculos: [vinculo(A, "Empresa A")] });
    carregarEquipeOwner.mockResolvedValue(equipeDe(A));
  });

  it("setas movem entre as abas e só a ativa é tabulável", async () => {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    const unidades = await screen.findByRole("tab", { name: /unidades/i });
    const managers = screen.getByRole("tab", { name: /managers/i });
    expect(unidades.getAttribute("tabindex")).toBe("0");
    expect(managers.getAttribute("tabindex")).toBe("-1");

    fireEvent.keyDown(unidades, { key: "ArrowRight" });
    expect(managers.getAttribute("aria-selected")).toBe("true");
    expect(managers.getAttribute("tabindex")).toBe("0");
    expect(unidades.getAttribute("tabindex")).toBe("-1");

    fireEvent.keyDown(managers, { key: "End" });
    expect(screen.getByRole("tab", { name: /convites/i }).getAttribute("aria-selected")).toBe("true");
  });

  it("Escape cancela a revogação sem chamar a RPC", async () => {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    fireEvent.click(await screen.findByRole("button", { name: /revogar acesso definitivamente/i }));

    const dialogo = screen.getByRole("alertdialog");
    // NÃO modal: não há contenção de foco nem exclusão do fundo, então
    // aria-modal="true" seria uma afirmação falsa e não pode estar presente.
    expect(dialogo.hasAttribute("aria-modal")).toBe(false);
    fireEvent.keyDown(dialogo, { key: "Escape" });
    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(ownerDefinirStatusManager).not.toHaveBeenCalled();
  });

  it("foco entra no diálogo e VOLTA ao botão de origem ao cancelar", async () => {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    const gatilho = await screen.findByRole("button", { name: /revogar acesso definitivamente/i });
    fireEvent.click(gatilho);

    const dialogo = screen.getByRole("alertdialog");
    // Foco inicial no botão de confirmar, dentro do diálogo.
    await waitFor(() => expect(dialogo.contains(document.activeElement)).toBe(true));
    expect((document.activeElement as HTMLElement).textContent).toMatch(/sim, revogar/i);

    fireEvent.keyDown(dialogo, { key: "Escape" });
    // O botão de origem é remontado; o foco precisa estar nele, não no <body>.
    await waitFor(() =>
      expect(document.activeElement).toBe(
        screen.getByRole("button", { name: /revogar acesso definitivamente/i })
      )
    );
    expect(document.activeElement).not.toBe(document.body);
  });

  it("status do manager aparece traduzido, não cru", async () => {
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    const painel = document.getElementById("painel-managers")!;
    await within(painel).findByText("Ativo");
    expect(within(painel).queryByText("active")).toBeNull();
  });

  it("confirmação executa de verdade a RPC com o motivo informado", async () => {
    ownerDefinirStatusManager.mockResolvedValue({ ok: true });
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    fireEvent.change(await screen.findByLabelText(/motivo da revogação/i), {
      target: { value: "saiu da empresa" },
    });
    fireEvent.click(screen.getByRole("button", { name: /revogar acesso definitivamente/i }));
    fireEvent.click(
      within(screen.getByRole("alertdialog")).getByRole("button", {
        name: /sim, revogar definitivamente/i,
      })
    );
    await waitFor(() =>
      expect(ownerDefinirStatusManager).toHaveBeenCalledWith(
        `mg-${A}`,
        "revoke",
        "saiu da empresa"
      )
    );
  });

  it("recusa da RPC não é apresentada como sucesso", async () => {
    ownerDefinirStatusManager.mockResolvedValue({ ok: false, motivo: "forbidden" });
    renderPortal(<PortalEquipe />, { rotas: ["/portal/equipe"] });
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    fireEvent.change(await screen.findByLabelText(/motivo da revogação/i), {
      target: { value: "motivo qualquer" },
    });
    fireEvent.click(screen.getByRole("button", { name: /revogar acesso definitivamente/i }));
    fireEvent.click(
      within(screen.getByRole("alertdialog")).getByRole("button", {
        name: /sim, revogar definitivamente/i,
      })
    );
    await waitFor(() => expect(ownerDefinirStatusManager).toHaveBeenCalled());
    // Falso sucesso nunca; e a recusa precisa ser DITA ao usuário.
    expect(screen.queryByText(/acesso do manager revogado/i)).toBeNull();
    expect(await screen.findByText(/falha: forbidden/i)).toBeDefined();
  });
});

/* 9 -> ver beneficiosValidarSucesso.spec.tsx, que captura o fragmento pelo caminho real. */
