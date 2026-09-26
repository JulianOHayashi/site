import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

/**
 * B4 provisional — ativação da conta provisória.
 *
 * A distinção que o desenho anterior não fazia:
 *   CONTA SUPABASE AUTH CRIADA  ≠  CONTA PROVISÓRIA ATIVADA
 * Entre uma e outra existe a etapa jurídica, e o claim apenas verifica.
 */
const rpcMock = vi.fn();
const signUpMock = vi.fn();
const signInMock = vi.fn();

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

const PRIV_A = { legal_document_id: "priv-A", doc_type: "privacy_notice", version: "A",
  title: "Aviso de privacidade", content: "texto", content_url: null };
const PRIV_B = { ...PRIV_A, legal_document_id: "priv-B", version: "B" };
const TERM_A = { legal_document_id: "term-A", doc_type: "provisional_account_terms", version: "A",
  title: "Termos da conta provisória", content: "texto", content_url: null };

const CLAIM = "k".repeat(64);

function montar() {
  return render(
    <MemoryRouter initialEntries={[`/parceiros/confirmar?claim=${CLAIM}`]}>
      <ConfirmarEmail />
    </MemoryRouter>
  );
}

async function criarConta() {
  await waitFor(() => expect(screen.getByLabelText(/^e-mail$/i)).toBeDefined());
  fireEvent.change(screen.getByLabelText(/^e-mail$/i), { target: { value: "contato@teste.com.br" } });
  fireEvent.change(screen.getByLabelText(/senha/i), { target: { value: "senha-forte-1" } });
  fireEvent.click(screen.getByRole("button", { name: /continuar/i }));
}

const chamadas = (nome: string) => rpcMock.mock.calls.filter((c) => c[0] === nome);

beforeEach(() => {
  rpcMock.mockReset(); signUpMock.mockReset(); signInMock.mockReset();
  localStorage.clear(); sessionStorage.clear();
  signUpMock.mockResolvedValue({ data: { session: { access_token: "t" } }, error: null });
});
afterEach(() => cleanup());

describe("A — signUp devolve sessao", () => {
  it("carrega termos, exige aceite vinculado e so entao reivindica", async () => {
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_provisional_account_terms")
        return { data: { ok: true, documents: [PRIV_A, TERM_A] }, error: null };
      if (nome === "record_bound_legal_acceptance")
        return { data: { ok: true, acceptance_id: "a", legal_document_id: "x" }, error: null };
      return { data: { ok: true, application_id: "app-1", account_kind: "provisional",
                       status: "under_review", already_linked: false }, error: null };
    });
    montar();
    await criarConta();

    await waitFor(() => expect(screen.getByLabelText(/aceito: aviso de privacidade/i)).toBeDefined());
    // Antes do aceite, o claim NÃO foi chamado.
    expect(chamadas("claim_partner_application_account").length).toBe(0);

    fireEvent.click(screen.getByLabelText(/aceito: aviso de privacidade/i));
    fireEvent.click(screen.getByLabelText(/aceito: termos da conta/i));
    fireEvent.click(screen.getByRole("button", { name: /aceitar e ativar acesso/i }));

    await waitFor(() => expect(screen.getByText(/tudo certo/i)).toBeDefined());

    const aceites = chamadas("record_bound_legal_acceptance");
    expect(aceites.length).toBe(2);
    // Cada aceite carrega o ID EXATO que a tela exibiu.
    expect((aceites[0][1] as { p_legal_document_id: string }).p_legal_document_id).toBe("priv-A");
    expect((aceites[1][1] as { p_legal_document_id: string }).p_legal_document_id).toBe("term-A");
    expect(chamadas("claim_partner_application_account").length).toBe(1);
    expect(screen.getByRole("link", { name: /acompanhar solicitação/i })).toBeDefined();
  });
});

describe("B — signUp NAO devolve sessao", () => {
  it("nao aceita, nao reivindica, nao finge sucesso", async () => {
    signUpMock.mockResolvedValue({ data: { user: { id: "u1" }, session: null }, error: null });
    rpcMock.mockResolvedValue({ data: { ok: true, documents: [PRIV_A, TERM_A] }, error: null });
    montar();
    await criarConta();

    await waitFor(() => expect(screen.getByText(/confirme seu e-mail para continuar/i)).toBeDefined());
    expect(chamadas("record_bound_legal_acceptance").length).toBe(0);
    expect(chamadas("claim_partner_application_account").length).toBe(0);
    expect(chamadas("get_provisional_account_terms").length).toBe(0);
    expect(screen.queryByText(/tudo certo/i)).toBeNull();
    expect(screen.queryByRole("link", { name: /acompanhar solicitação/i })).toBeNull();
  });

  it("nao guarda o claim token no navegador", async () => {
    signUpMock.mockResolvedValue({ data: { user: { id: "u1" }, session: null }, error: null });
    montar();
    await criarConta();
    await waitFor(() => expect(screen.getByText(/confirme seu e-mail/i)).toBeDefined());
    const guardado = JSON.stringify(localStorage) + JSON.stringify(sessionStorage);
    expect(guardado).not.toContain(CLAIM);
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
  });

  it("oferece caminho de continuacao seguro", async () => {
    signUpMock.mockResolvedValue({ data: { user: { id: "u1" }, session: null }, error: null });
    montar();
    await criarConta();
    await waitFor(() => {
      const link = screen.getByRole("link", {
        name: /entrar para acompanhar/i,
      }) as HTMLAnchorElement;
      expect(link.getAttribute("href")).toBe(
        "/parceiros/acesso?next=%2Fparceiros%2Fsolicitacao"
      );
    });
    expect(screen.getByText(/reenviar link de acesso/i)).toBeDefined();
  });
});

describe("C — claim responde provisional_terms_required", () => {
  it("recarrega termos, limpa o aceite e nao repete o claim", async () => {
    let rodada = 0;
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_provisional_account_terms") {
        rodada += 1;
        return { data: { ok: true, documents: rodada === 1 ? [PRIV_A, TERM_A] : [PRIV_B, TERM_A] },
                 error: null };
      }
      if (nome === "record_bound_legal_acceptance")
        return { data: { ok: true, acceptance_id: "a", legal_document_id: "x" }, error: null };
      return { data: { ok: false, reason: "provisional_terms_required" }, error: null };
    });
    montar();
    await criarConta();
    await waitFor(() => expect(screen.getByLabelText(/aceito: aviso de privacidade/i)).toBeDefined());
    fireEvent.click(screen.getByLabelText(/aceito: aviso de privacidade/i));
    fireEvent.click(screen.getByLabelText(/aceito: termos da conta/i));
    fireEvent.click(screen.getByRole("button", { name: /aceitar e ativar acesso/i }));

    await waitFor(() => expect(screen.getByText(/aceitar os termos da conta/i)).toBeDefined());
    await waitFor(() => expect(screen.getByText(/versão b/i)).toBeDefined());
    for (const cb of screen.getAllByRole("checkbox")) {
      expect((cb as HTMLInputElement).checked).toBe(false);
    }
    expect(chamadas("claim_partner_application_account").length).toBe(1);
    expect(screen.queryByText(/tudo certo/i)).toBeNull();
  });
});

describe("D — wrapper responde acceptance_stale", () => {
  it("recarrega, limpa o aceite e NAO tenta o claim", async () => {
    let rodada = 0;
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_provisional_account_terms") {
        rodada += 1;
        return { data: { ok: true, documents: rodada === 1 ? [PRIV_A, TERM_A] : [PRIV_B, TERM_A] },
                 error: null };
      }
      if (nome === "record_bound_legal_acceptance")
        return { data: { ok: false, reason: "acceptance_stale" }, error: null };
      return { data: { ok: true }, error: null };
    });
    montar();
    await criarConta();
    await waitFor(() => expect(screen.getByLabelText(/aceito: aviso de privacidade/i)).toBeDefined());
    fireEvent.click(screen.getByLabelText(/aceito: aviso de privacidade/i));
    fireEvent.click(screen.getByLabelText(/aceito: termos da conta/i));
    fireEvent.click(screen.getByRole("button", { name: /aceitar e ativar acesso/i }));

    await waitFor(() => expect(screen.getByText(/termos foram atualizados/i)).toBeDefined());
    expect(chamadas("claim_partner_application_account").length).toBe(0);
    await waitFor(() => expect(screen.getByText(/versão b/i)).toBeDefined());
    for (const cb of screen.getAllByRole("checkbox")) {
      expect((cb as HTMLInputElement).checked).toBe(false);
    }
  });
});

describe("E — falha em um dos dois aceites", () => {
  it("o claim NAO e chamado quando o segundo aceite falha", async () => {
    let aceites = 0;
    rpcMock.mockImplementation(async (nome: string) => {
      if (nome === "get_provisional_account_terms")
        return { data: { ok: true, documents: [PRIV_A, TERM_A] }, error: null };
      if (nome === "record_bound_legal_acceptance") {
        aceites += 1;
        return aceites === 1
          ? { data: { ok: true, acceptance_id: "a", legal_document_id: "priv-A" }, error: null }
          : { data: { ok: false, reason: "acceptance_failed" }, error: null };
      }
      return { data: { ok: true }, error: null };
    });
    montar();
    await criarConta();
    await waitFor(() => expect(screen.getByLabelText(/aceito: aviso de privacidade/i)).toBeDefined());
    fireEvent.click(screen.getByLabelText(/aceito: aviso de privacidade/i));
    fireEvent.click(screen.getByLabelText(/aceito: termos da conta/i));
    fireEvent.click(screen.getByRole("button", { name: /aceitar e ativar acesso/i }));

    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(chamadas("record_bound_legal_acceptance").length).toBe(2);
    expect(chamadas("claim_partner_application_account").length).toBe(0);
    expect(screen.queryByText(/tudo certo/i)).toBeNull();
  });

  it("o botao fica bloqueado enquanto nem todos os documentos estao aceitos", async () => {
    rpcMock.mockImplementation(async (nome: string) =>
      nome === "get_provisional_account_terms"
        ? { data: { ok: true, documents: [PRIV_A, TERM_A] }, error: null }
        : { data: { ok: true }, error: null }
    );
    montar();
    await criarConta();
    await waitFor(() => expect(screen.getByLabelText(/aceito: aviso de privacidade/i)).toBeDefined());
    const botao = screen.getByRole("button", { name: /aceitar e ativar acesso/i }) as HTMLButtonElement;
    expect(botao.disabled).toBe(true);
    fireEvent.click(screen.getByLabelText(/aceito: aviso de privacidade/i));
    expect(botao.disabled).toBe(true);
    fireEvent.click(screen.getByLabelText(/aceito: termos da conta/i));
    await waitFor(() => expect(botao.disabled).toBe(false));
  });
});
