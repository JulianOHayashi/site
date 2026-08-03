import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

const listInvitationsMock = vi.fn();
const listManagersMock = vi.fn();
vi.mock("../../services/partnerTeamService", async (orig) => {
  const real = (await orig()) as any;
  return {
    ...real,
    listInvitations: () => listInvitationsMock(),
    listManagers: () => listManagersMock(),
  };
});

import EquipeConvitesPainel from "../../components/portal/EquipeConvitesPainel";
import { capsFake } from "./fixtures";

beforeEach(() => {
  listInvitationsMock.mockResolvedValue({ ok: true, data: [] });
  listManagersMock.mockResolvedValue({ ok: true, data: [] });
});

function contarCamposIdentificacao(): number {
  return document.querySelectorAll('input[id^="lote-rot-"]').length;
}

describe("CORREÇÃO 7 — Proteção contra quantidade grande", () => {
  it("1000000 renderiza no máximo 20 identificações e mostra 'Página 1 de 50000'", async () => {
    render(<EquipeConvitesPainel capabilities={capsFake({ canInviteManagers: true })} />);
    const qtd = screen.getByLabelText(/Quantidade de convites/i);
    await userEvent.clear(qtd);
    await userEvent.type(qtd, "1000000");

    await waitFor(() => expect(contarCamposIdentificacao()).toBe(20));
    expect(screen.getByText(/Página 1 de 50000/i)).toBeInTheDocument();
  });

  it("navegação por teclado preserva rótulos já preenchidos", async () => {
    render(<EquipeConvitesPainel capabilities={capsFake({ canInviteManagers: true })} />);
    const qtd = screen.getByLabelText(/Quantidade de convites/i);
    await userEvent.clear(qtd);
    await userEvent.type(qtd, "40"); // 2 páginas

    const campo1 = screen.getByLabelText(/Identificação do convite 1$/i);
    await userEvent.type(campo1, "manhã");

    // Avança de página por teclado (foco no botão + Enter)
    const proxima = screen.getByRole("button", { name: /Próxima/i });
    proxima.focus();
    await userEvent.keyboard("{Enter}");
    expect(screen.getByText(/Página 2 de 2/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Identificação do convite 21$/i)).toBeInTheDocument();

    // Volta e confirma que o rótulo foi preservado (estrutura esparsa)
    const anterior = screen.getByRole("button", { name: /Anterior/i });
    anterior.focus();
    await userEvent.keyboard("{Enter}");
    expect(
      (screen.getByLabelText(/Identificação do convite 1$/i) as HTMLInputElement).value
    ).toBe("manhã");
  });

  it("quantidade inválida (0) não renderiza campos", async () => {
    render(<EquipeConvitesPainel capabilities={capsFake({ canInviteManagers: true })} />);
    const qtd = screen.getByLabelText(/Quantidade de convites/i);
    await userEvent.clear(qtd);
    await userEvent.type(qtd, "0");
    await waitFor(() => expect(contarCamposIdentificacao()).toBe(0));
  });
});
