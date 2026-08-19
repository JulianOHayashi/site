import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { StrictMode } from "react";

/**
 * B2 frontend — confirmação, dedupe sob StrictMode, claim por e-mail,
 * divergência de identidade e recuperação anti-enumeração.
 */
const rpcMock = vi.fn();
const signUpMock = vi.fn(async () => ({ data: { session: { access_token: "t" } }, error: null }));
const signInMock = vi.fn(async () => ({ data: {}, error: null }));

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      signUp: (...a: unknown[]) => signUpMock(...(a as [])),
      signInWithPassword: (...a: unknown[]) => signInMock(...(a as [])),
      getSession: vi.fn(async () => ({ data: { session: null } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
    },
  },
  supabaseConfigurado: true,
}));

import ConfirmarEmail from "../pages/parceiros/ConfirmarEmail";
import RecuperarAcesso from "../pages/parceiros/RecuperarAcesso";

function montarConfirmacao(query: string, strict = false) {
  const arvore = (
    <MemoryRouter initialEntries={[`/parceiros/confirmar${query}`]}>
      <ConfirmarEmail />
    </MemoryRouter>
  );
  return render(strict ? <StrictMode>{arvore}</StrictMode> : arvore);
}

beforeEach(() => {
  rpcMock.mockReset();
  signUpMock.mockClear();
  signInMock.mockClear();
  localStorage.clear();
  sessionStorage.clear();
});
afterEach(() => cleanup());

describe("B2 — dedupe sob StrictMode", () => {
  it("StrictMode NAO consome o token duas vezes", async () => {
    rpcMock.mockResolvedValue({
      data: { ok: true, application_id: "a1", status: "pending_account_setup",
              already_confirmed: false, claim_token: "c".repeat(64) },
      error: null,
    });
    montarConfirmacao(`?token=${"t".repeat(64)}-strict`, true);
    await waitFor(() => expect(screen.getByText(/crie seu acesso provisório/i)).toBeDefined());
    const confirmacoes = rpcMock.mock.calls.filter(
      (c) => c[0] === "confirm_partner_application_email"
    );
    expect(confirmacoes.length).toBe(1);
  });

  it("token invalido nao vira sucesso e oferece recuperacao", async () => {
    rpcMock.mockResolvedValue({ data: { ok: false, reason: "token_expired" }, error: null });
    montarConfirmacao(`?token=${"x".repeat(64)}-exp`);
    await waitFor(() => expect(screen.getByText(/este link expirou/i)).toBeDefined());
    expect(screen.getByText(/reenviar link de acesso/i)).toBeDefined();
  });

  it("token ja consumido mostra mensagem propria", async () => {
    rpcMock.mockResolvedValue({ data: { ok: false, reason: "token_already_used" }, error: null });
    montarConfirmacao(`?token=${"y".repeat(64)}-used`);
    await waitFor(() => expect(screen.getByText(/já foi utilizado/i)).toBeDefined());
  });

  it("sem token nem claim, recusa com seguranca", async () => {
    montarConfirmacao("");
    await waitFor(() => expect(screen.getByText(/não é válido/i)).toBeDefined());
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("B2 — claim por e-mail e identidade", () => {
  it("?claim= abre direto a criacao de acesso, sem confirmar de novo", async () => {
    montarConfirmacao(`?claim=${"k".repeat(64)}`);
    await waitFor(() => expect(screen.getByText(/crie seu acesso provisório/i)).toBeDefined());
    const confirmacoes = rpcMock.mock.calls.filter(
      (c) => c[0] === "confirm_partner_application_email"
    );
    expect(confirmacoes.length).toBe(0);
  });

  it("email divergente mostra erro seguro e nao conclui", async () => {
    // O claim agora vem DEPOIS da etapa juridica: sessao -> termos -> aceite
    // vinculado -> claim. Aqui o backend recusa por identidade de e-mail.
    signUpMock.mockResolvedValue({ data: { session: { access_token: "t" } }, error: null });
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_provisional_account_terms") {
        return { data: { ok: true, documents: [
          { legal_document_id: "p1", doc_type: "privacy_notice", version: "v1",
            title: "Aviso de privacidade", content: "t", content_url: null },
        ] }, error: null };
      }
      if (nome === "record_bound_legal_acceptance") {
        return { data: { ok: true, acceptance_id: "a1", legal_document_id: "p1" }, error: null };
      }
      return { data: { ok: false, reason: "email_mismatch" }, error: null };
    });
    montarConfirmacao(`?claim=${"m".repeat(64)}`);
    await waitFor(() => expect(screen.getByLabelText(/^e-mail$/i)).toBeDefined());
    fireEvent.change(screen.getByLabelText(/^e-mail$/i), { target: { value: "outro@gmail.com" } });
    fireEvent.change(screen.getByLabelText(/senha/i), { target: { value: "senha-forte-1" } });
    fireEvent.click(screen.getByRole("button", { name: /continuar/i }));

    await waitFor(() => expect(screen.getByLabelText(/aceito: aviso de privacidade/i)).toBeDefined());
    fireEvent.click(screen.getByLabelText(/aceito: aviso de privacidade/i));
    fireEvent.click(screen.getByRole("button", { name: /aceitar e ativar acesso/i }));

    await waitFor(() => expect(screen.getByText(/não é o mesmo que confirmamos/i)).toBeDefined());
    expect(screen.queryByText(/tudo certo/i)).toBeNull();
  });
});

describe("B2 — recuperacao anti-enumeracao", () => {
  const RESPOSTA = /se houver uma solicitação elegível/i;

  it("dados existentes e inexistentes produzem a MESMA resposta", async () => {
    // Caso 1: backend responde normalmente.
    rpcMock.mockResolvedValue({ data: { ok: true }, error: null });
    const { unmount } = render(<MemoryRouter><RecuperarAcesso /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "12.345.678/0001-95" } });
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "a@b.com.br" } });
    fireEvent.click(screen.getByRole("button", { name: /enviar instruções/i }));
    await waitFor(() => expect(screen.getByText(RESPOSTA)).toBeDefined());
    const texto1 = screen.getByRole("status").textContent;
    unmount();

    // Caso 2: erro de transporte — mesmo desfecho visual.
    rpcMock.mockResolvedValue({ data: null, error: { message: "boom" } });
    render(<MemoryRouter><RecuperarAcesso /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "12.345.678/0001-95" } });
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "zzz@nao-existe.com" } });
    fireEvent.click(screen.getByRole("button", { name: /enviar instruções/i }));
    await waitFor(() => expect(screen.getByText(RESPOSTA)).toBeDefined());
    expect(screen.getByRole("status").textContent).toBe(texto1);
  });

  it("nao revela status interno, contagem de tokens nem identificadores", async () => {
    rpcMock.mockResolvedValue({ data: { ok: true }, error: null });
    render(<MemoryRouter><RecuperarAcesso /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "12.345.678/0001-95" } });
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "a@b.com.br" } });
    fireEvent.click(screen.getByRole("button", { name: /enviar instruções/i }));
    await waitFor(() => expect(screen.getByText(RESPOSTA)).toBeDefined());
    const txt = document.body.textContent ?? "";
    for (const proibido of ["pending_email_verification", "pending_account_setup",
                            "under_review", "application_id", "token"]) {
      expect(txt.toLowerCase()).not.toContain(proibido);
    }
  });

  it("valida formato sem consultar o backend", async () => {
    render(<MemoryRouter><RecuperarAcesso /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "123" } });
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "a@b.com.br" } });
    fireEvent.click(screen.getByRole("button", { name: /enviar instruções/i }));
    await waitFor(() => expect(screen.getByText(/informe um cnpj válido/i)).toBeDefined());
    expect(rpcMock).not.toHaveBeenCalled();
  });
});
