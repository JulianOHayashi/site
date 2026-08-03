import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ConfirmarRevogacao from "../../components/portal/ConfirmarRevogacao";
import type { PartnerManagerSummary } from "../../domain/portal/types";

const manager: PartnerManagerSummary = {
  memberId: "m1",
  name: "Fulano",
  role: "partner_manager",
  status: "active",
  joinedAt: null,
  lastOperationalActivityAt: null,
  validationsCount: null,
};

beforeEach(() => vi.restoreAllMocks());

describe("CORREÇÃO 2 — Modal de revogação", () => {
  it("NÃO possui campo de senha", () => {
    render(
      <ConfirmarRevogacao manager={manager} onFechar={() => {}} onConcluido={() => {}} />
    );
    expect(document.querySelector('input[type="password"]')).toBeNull();
    expect(screen.queryByLabelText(/senha/i)).toBeNull();
  });

  it("tem role=dialog, foco inicial no motivo e fecha por Escape", async () => {
    const onFechar = vi.fn();
    render(
      <ConfirmarRevogacao manager={manager} onFechar={onFechar} onConcluido={() => {}} />
    );
    const dialog = screen.getByRole("dialog");
    expect(dialog).toBeInTheDocument();
    // foco inicial coerente
    expect(screen.getByLabelText(/Motivo do desligamento/i)).toHaveFocus();
    // fechamento por teclado
    await userEvent.keyboard("{Escape}");
    expect(onFechar).toHaveBeenCalled();
  });

  it("exige motivo E confirmação REVOGAR", async () => {
    render(
      <ConfirmarRevogacao manager={manager} onFechar={() => {}} onConcluido={() => {}} />
    );
    const botao = screen.getByRole("button", { name: /^Revogar acesso$/i });
    expect(botao).toBeDisabled();

    await userEvent.type(screen.getByLabelText(/Motivo do desligamento/i), "saída");
    expect(botao).toBeDisabled(); // falta confirmação textual

    await userEvent.type(
      screen.getByLabelText(/Digite REVOGAR para confirmar/i),
      "REVOGAR"
    );
    expect(botao).toBeEnabled();
  });

  it("backend indisponível NÃO produz sucesso", async () => {
    const onConcluido = vi.fn();
    render(
      <ConfirmarRevogacao
        manager={manager}
        onFechar={() => {}}
        onConcluido={onConcluido}
      />
    );
    await userEvent.type(screen.getByLabelText(/Motivo do desligamento/i), "saída");
    await userEvent.type(
      screen.getByLabelText(/Digite REVOGAR para confirmar/i),
      "REVOGAR"
    );
    await userEvent.click(screen.getByRole("button", { name: /^Revogar acesso$/i }));
    expect(onConcluido).not.toHaveBeenCalled();
    // Erro específico pós-clique: o vínculo NÃO foi encerrado.
    expect(await screen.findByText(/não.*foi encerrado/i)).toBeInTheDocument();
    // E o serviço sinaliza indisponibilidade de backend.
    expect(
      screen.getByText(/integração de servidor não foi ativada/i)
    ).toBeInTheDocument();
  });
});
