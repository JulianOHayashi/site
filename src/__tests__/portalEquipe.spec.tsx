import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { renderPortal, SESSAO_FALSA } from "./helpers/portalRender";

const obterVinculosParceiro = vi.fn();

vi.mock("../hooks/usePortalSiteAuth", () => ({
  usePortalSiteAuth: () => SESSAO_FALSA(),
}));
const carregarEquipeOwner = vi.fn();
const ownerCriarUnidade = vi.fn();
const ownerConvidarManager = vi.fn();
const ownerRevogarConviteManager = vi.fn();
const ownerDefinirStatusManager = vi.fn();
const ownerDefinirVinculoManager = vi.fn();

vi.mock("../services/partnerApplicationService", () => ({
  obterVinculosParceiro: (...a: unknown[]) => obterVinculosParceiro(...a),
  carregarEquipeOwner: (...a: unknown[]) => carregarEquipeOwner(...a),
  ownerCriarUnidade: (...a: unknown[]) => ownerCriarUnidade(...a),
  ownerConvidarManager: (...a: unknown[]) => ownerConvidarManager(...a),
  ownerRevogarConviteManager: (...a: unknown[]) => ownerRevogarConviteManager(...a),
  ownerDefinirStatusManager: (...a: unknown[]) => ownerDefinirStatusManager(...a),
  ownerDefinirVinculoManager: (...a: unknown[]) => ownerDefinirVinculoManager(...a),
  mensagemDeMotivo: (m: string) => m,
}));

vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../pages/portal/portalUi", () => ({
  PortalTopo: ({ titulo }: { titulo: string }) => <h1>{titulo}</h1>,
}));

import PortalEquipe from "../pages/portal/PortalEquipe";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const UNIT = "22222222-2222-4222-8222-222222222222";

afterEach(() => cleanup());

beforeEach(() => {
  vi.clearAllMocks();
  obterVinculosParceiro.mockResolvedValue({
    tipo: "ok",
    vinculos: [{
      company_id: COMPANY,
      trade_name: "Empresa QA",
      company_status: "active",
      member_id: "m1",
      role: "partner_owner",
      member_status: "active",
      city: "Vitória",
      uf: "ES",
    }],
  });
  carregarEquipeOwner.mockResolvedValue({
    ok: true,
    dados: {
      unidades: [{
        id: UNIT,
        company_id: COMPANY,
        name: "Matriz",
        city: "Vitória",
        uf: "ES",
        status: "active",
        partner_branch_bridge_id: "b1",
      }],
      convites: [],
      membros: [],
      vinculosUnidade: [],
    },
  });
  ownerCriarUnidade.mockResolvedValue({ ok: true, dados: { unit_id: UNIT } });
  ownerConvidarManager.mockResolvedValue({ ok: true, dados: { invite_id: "i1" } });
  ownerRevogarConviteManager.mockResolvedValue({ ok: true, dados: {} });
  ownerDefinirStatusManager.mockResolvedValue({ ok: true, dados: {} });
  ownerDefinirVinculoManager.mockResolvedValue({ ok: true, dados: {} });
});

describe("PortalEquipe", () => {
  it("owner cria unidade pela RPC canônica", async () => {
    renderPortal(<PortalEquipe />);
    // Espera o FORMULÁRIO, que só existe depois de a equipe carregar. "Empresa
    // QA" não serve de sinal: aparece antes, na barra de empresa ativa.
    await screen.findByLabelText("Nome da unidade");

    fireEvent.change(screen.getByLabelText("Nome da unidade"), {
      target: { value: "Filial Serra" },
    });
    fireEvent.change(screen.getByLabelText("Cidade"), {
      target: { value: "Serra" },
    });
    fireEvent.change(screen.getByLabelText("UF"), {
      target: { value: "es" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Criar unidade" }));

    await waitFor(() =>
      expect(ownerCriarUnidade).toHaveBeenCalledWith(
        COMPANY,
        "Filial Serra",
        "Serra",
        "ES"
      )
    );
  });

  it("owner convida manager vinculado à unidade escolhida", async () => {
    renderPortal(<PortalEquipe />);
    await screen.findByLabelText("Nome");

    fireEvent.change(screen.getByLabelText("Nome"), {
      target: { value: "Manager QA" },
    });
    fireEvent.change(screen.getByLabelText("E-mail"), {
      target: { value: "manager@example.com" },
    });
    fireEvent.change(screen.getByLabelText("Unidade inicial"), {
      target: { value: UNIT },
    });
    fireEvent.click(screen.getByRole("button", { name: "Enviar convite" }));

    await waitFor(() =>
      expect(ownerConvidarManager).toHaveBeenCalledWith(
        COMPANY,
        "manager@example.com",
        "Manager QA",
        UNIT
      )
    );
  });


  it("owner suspende manager pela RPC canônica", async () => {
    carregarEquipeOwner.mockResolvedValue({
      ok: true,
      dados: {
        unidades: [{
          id: UNIT,
          company_id: COMPANY,
          name: "Matriz",
          city: "Vitória",
          uf: "ES",
          status: "active",
          partner_branch_bridge_id: "b1",
        }],
        convites: [],
        membros: [{
          id: "m-manager",
          company_id: COMPANY,
          auth_user_id: "u-manager",
          role: "partner_manager",
          status: "active",
          full_name: "Manager QA",
          email: "manager@example.com",
        }],
        vinculosUnidade: [{
          id: "bind-1",
          member_id: "m-manager",
          unit_id: UNIT,
          status: "active",
          revoked_at: null,
        }],
      },
    });

    renderPortal(<PortalEquipe />);
    // A tela agora separa Unidades / Managers / Convites em abas; os managers
    // vivem na aba Managers. A RPC exercitada abaixo não mudou.
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    await screen.findByText("Manager QA");
    fireEvent.click(screen.getByRole("button", { name: "Suspender" }));

    await waitFor(() =>
      expect(ownerDefinirStatusManager).toHaveBeenCalledWith(
        "m-manager",
        "suspend",
        undefined
      )
    );
  });

  it("owner altera vínculo de unidade pela RPC canônica", async () => {
    carregarEquipeOwner.mockResolvedValue({
      ok: true,
      dados: {
        unidades: [{
          id: UNIT,
          company_id: COMPANY,
          name: "Matriz",
          city: "Vitória",
          uf: "ES",
          status: "active",
          partner_branch_bridge_id: "b1",
        }],
        convites: [],
        membros: [{
          id: "m-manager",
          company_id: COMPANY,
          auth_user_id: "u-manager",
          role: "partner_manager",
          status: "active",
          full_name: "Manager QA",
          email: "manager@example.com",
        }],
        vinculosUnidade: [],
      },
    });

    renderPortal(<PortalEquipe />);
    // A tela agora separa Unidades / Managers / Convites em abas; os managers
    // vivem na aba Managers. A RPC exercitada abaixo não mudou.
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    await screen.findByText("Manager QA");
    fireEvent.click(screen.getByRole("checkbox"));

    await waitFor(() =>
      expect(ownerDefinirVinculoManager).toHaveBeenCalledWith(
        "m-manager",
        UNIT,
        true,
        undefined
      )
    );
  });

  it("manager não recebe superfície de gestão", async () => {
    obterVinculosParceiro.mockResolvedValue({
      tipo: "ok",
      vinculos: [{
        company_id: COMPANY,
        trade_name: "Empresa QA",
        company_status: "active",
        member_id: "m2",
        role: "partner_manager",
        member_status: "active",
      }],
    });

    renderPortal(<PortalEquipe />);
    expect(
      await screen.findByText(/Acesso restrito ao responsável da empresa/i)
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Enviar convite" })).toBeNull();
  });
});

describe("PortalEquipe — separação de visões e ação irreversível", () => {
  function montarComManager() {
    carregarEquipeOwner.mockResolvedValue({
      ok: true,
      dados: {
        unidades: [{
          id: UNIT, company_id: COMPANY, name: "Matriz",
          city: "Vitória", uf: "ES", status: "active",
        }],
        convites: [],
        membros: [{
          id: "m-manager", role: "partner_manager", status: "active",
          full_name: "Manager QA", email: "manager@example.com",
        }],
        vinculosUnidade: [],
      },
    });
    return renderPortal(<PortalEquipe />);
  }

  it("abre em Unidades e só mostra uma visão por vez", async () => {
    montarComManager();
    const abaUnidades = await screen.findByRole("tab", { name: /unidades/i });
    expect(abaUnidades.getAttribute("aria-selected")).toBe("true");
    // Managers está em outra aba: o painel fica hidden até ser escolhida, e
    // getByRole (que respeita acessibilidade) não o alcança.
    expect(document.getElementById("painel-managers")!.hidden).toBe(true);
    expect(screen.queryByRole("button", { name: /^suspender$/i })).toBeNull();

    fireEvent.click(screen.getByRole("tab", { name: /managers/i }));
    expect(document.getElementById("painel-managers")!.hidden).toBe(false);
    expect(document.getElementById("painel-unidades")!.hidden).toBe(true);
    expect(abaUnidades.getAttribute("aria-selected")).toBe("false");
  });

  it("traduz o status da unidade em vez de exibir o valor cru", async () => {
    montarComManager();
    await screen.findByText("Matriz");
    const painel = document.getElementById("painel-unidades")!;
    expect(within(painel).getByText("Ativa")).toBeDefined();
    expect(within(painel).queryByText("active")).toBeNull();
  });

  it("revogação definitiva exige confirmação explícita antes de chamar a RPC", async () => {
    montarComManager();
    fireEvent.click(await screen.findByRole("tab", { name: /managers/i }));
    await screen.findByText("Manager QA");

    fireEvent.click(screen.getByRole("button", { name: /revogar acesso definitivamente/i }));
    // Nada foi chamado ainda: o primeiro clique só abre a confirmação.
    expect(ownerDefinirStatusManager).not.toHaveBeenCalled();

    const dialogo = screen.getByRole("alertdialog");
    expect(dialogo.textContent).toMatch(/não pode ser desfeita/i);

    fireEvent.click(within(dialogo).getByRole("button", { name: /cancelar/i }));
    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(ownerDefinirStatusManager).not.toHaveBeenCalled();
  });
});
