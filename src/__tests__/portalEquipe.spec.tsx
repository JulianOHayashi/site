import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

const obterVinculosParceiro = vi.fn();
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
    render(<MemoryRouter><PortalEquipe /></MemoryRouter>);
    await screen.findByText("Empresa QA");

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
    render(<MemoryRouter><PortalEquipe /></MemoryRouter>);
    await screen.findByText("Empresa QA");

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

    render(<MemoryRouter><PortalEquipe /></MemoryRouter>);
    await screen.findByText("Manager QA");
    fireEvent.click(screen.getByRole("button", { name: "Suspender" }));

    await waitFor(() =>
      expect(ownerDefinirStatusManager).toHaveBeenCalledWith(
        expect.objectContaining({ id: "m-manager" }),
        "suspend"
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

    render(<MemoryRouter><PortalEquipe /></MemoryRouter>);
    await screen.findByText("Manager QA");
    fireEvent.click(screen.getByRole("checkbox"));

    await waitFor(() =>
      expect(ownerDefinirVinculoManager).toHaveBeenCalledWith(
        expect.objectContaining({ id: "m-manager" }),
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

    render(<MemoryRouter><PortalEquipe /></MemoryRouter>);
    expect(
      await screen.findByText(/Acesso restrito ao responsável da empresa/i)
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Enviar convite" })).toBeNull();
  });
});
