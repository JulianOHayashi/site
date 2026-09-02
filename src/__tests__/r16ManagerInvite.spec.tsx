import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/** Lê fonte do repositório a partir da raiz do projeto (jsdom não resolve import.meta.url como file:). */
const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");
import { renderizar } from "../server/worker/emailRenderer";
import { R16_SUPPORTED_TEMPLATE_KEYS } from "../server/notifications/supportedTemplates";

/**
 * R16 — CONVITE DE GERENTE.
 *
 * O e-mail `manager_invite` apontava para `/parceiros/convite`, rota que não
 * existia no roteador. O convite era, na prática, inaceitável — embora a RPC
 * canônica `accept_manager_invite` já existisse e funcionasse.
 *
 * O teste de auditoria de rota abaixo compara o LINK GERADO PELO RENDERIZADOR
 * com as rotas REALMENTE registradas em App.tsx, para que essa divergência
 * não possa voltar em silêncio.
 */

const rpcMock = vi.fn();
const signInMock = vi.fn();
const getSessionMock = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      signInWithPassword: (...a: unknown[]) => signInMock(...(a as [])),
      getSession: (...a: unknown[]) => getSessionMock(...(a as [])),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
    },
  },
  supabaseConfigurado: true,
}));

import AceitarConviteManager from "../pages/parceiros/AceitarConviteManager";

const TOKEN = "t".repeat(64);
const BASE = "https://bdflow.com.br";

const semSessao = async () => ({ data: { session: null } });
const comSessao = async () => ({
  data: { session: { access_token: "x", user: { id: "u1" } } },
});

const chamadasRpc = () => rpcMock.mock.calls.filter((c) => c[0] === "accept_manager_invite");

function montar(query = `?token=${TOKEN}`) {
  return render(
    <MemoryRouter initialEntries={[`/parceiros/convite${query}`]}>
      <Routes>
        <Route path="/parceiros/convite" element={<AceitarConviteManager />} />
        <Route path="/parceiros/painel" element={<div data-testid="painel">painel</div>} />
        <Route path="/parceiros" element={<div data-testid="parceiros">parceiros</div>} />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => {
  rpcMock.mockReset();
  signInMock.mockReset();
  getSessionMock.mockReset();
  localStorage.clear();
  sessionStorage.clear();
  getSessionMock.mockImplementation(comSessao);
  rpcMock.mockResolvedValue({ data: { ok: true, member_id: "m1" }, error: null });
});
afterEach(() => cleanup());

describe("R16_EMAIL_ACTION_ROUTE_AUDIT", () => {
  const appTsx = lerFonte("src/App.tsx");

  /** Extrai os `path=` registrados no roteador real. */
  const rotasRegistradas = (): string[] =>
    [...appTsx.matchAll(/path="([^"]+)"/g)].map((m) => m[1]);

  it("/parceiros/convite é rota REALMENTE registrada", () => {
    expect(rotasRegistradas()).toContain("/parceiros/convite");
  });

  it("o link do manager_invite aponta para essa rota exata", () => {
    const m = renderizar("manager_invite", { token: TOKEN, company_name: "X LTDA" }, BASE);
    expect(m.texto).toContain("https://bdflow.com.br/parceiros/convite?");
  });

  it("TODOS os três templates apontam para rotas existentes", () => {
    const registradas = rotasRegistradas();
    const dados: Record<string, Record<string, unknown>> = {
      partner_application_email_verification: { token: TOKEN },
      partner_application_account_claim: { token: TOKEN },
      manager_invite: { token: TOKEN, company_name: "X LTDA" },
    };
    for (const chave of R16_SUPPORTED_TEMPLATE_KEYS) {
      const m = renderizar(chave, dados[chave], BASE);
      const url = /https:\/\/bdflow\.com\.br(\/[^\s?]*)/.exec(m.texto);
      expect(url, `template ${chave} sem link`).not.toBeNull();
      expect(registradas, `rota do template ${chave}`).toContain(url![1]);
    }
  });
});

describe("R16_MANAGER_INVITE_TOKEN_HANDLING", () => {
  it("sem token, falha fechada e NÃO chama a RPC", async () => {
    montar("");
    await waitFor(() => expect(screen.getByText(/convite não encontrado/i)).toBeDefined());
    expect(chamadasRpc()).toHaveLength(0);
  });

  it("o token é removido da URL visível após a captura", async () => {
    montar();
    await waitFor(() => expect(chamadasRpc().length).toBe(1));
    expect(window.location.search).not.toContain(TOKEN);
  });

  it("o token NUNCA vai para localStorage ou sessionStorage", async () => {
    montar();
    await waitFor(() => expect(chamadasRpc().length).toBe(1));
    const guardado = JSON.stringify(localStorage) + JSON.stringify(sessionStorage);
    expect(guardado).not.toContain(TOKEN);
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
  });

  it("o token não aparece na tela em nenhum estado", async () => {
    rpcMock.mockResolvedValue({ data: { ok: false, reason: "invalid_token" }, error: null });
    montar();
    await waitFor(() => expect(screen.getByRole("alert")).toBeDefined());
    expect(document.body.textContent ?? "").not.toContain(TOKEN);
  });

  it("erro cru do banco não expõe token nem detalhe interno", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: `falha em manager_invite_tokens token=${TOKEN}` },
    });
    montar();
    await waitFor(() => expect(screen.getByText(/não foi possível concluir/i)).toBeDefined());
    const txt = document.body.textContent ?? "";
    expect(txt).not.toContain(TOKEN);
    expect(txt).not.toContain("manager_invite_tokens");
  });

  it("o token é enviado à RPC sem alteração", async () => {
    montar();
    await waitFor(() => expect(chamadasRpc().length).toBe(1));
    expect((chamadasRpc()[0][1] as { p_token: string }).p_token).toBe(TOKEN);
  });
});

describe("R16_MANAGER_INVITE_ACCEPTANCE_UI — autenticação", () => {
  it("usuário autenticado invoca accept_manager_invite exatamente uma vez", async () => {
    montar();
    await waitFor(() => expect(screen.getByText(/acesso de gerente ativado/i)).toBeDefined());
    expect(chamadasRpc()).toHaveLength(1);
  });

  it("usuário NÃO autenticado não chama a RPC antes de entrar", async () => {
    getSessionMock.mockImplementation(semSessao);
    montar();
    await waitFor(() => expect(screen.getByRole("button", { name: /entrar e aceitar/i })).toBeDefined());
    expect(chamadasRpc()).toHaveLength(0);
  });

  it("login inválido não revela se o e-mail existe nem quem foi convidado", async () => {
    getSessionMock.mockImplementation(semSessao);
    signInMock.mockResolvedValue({ data: {}, error: { message: "Invalid login credentials" } });
    montar();
    await waitFor(() => expect(screen.getByLabelText(/e-mail/i)).toBeDefined());
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "a@b.com.br" } });
    fireEvent.change(screen.getByLabelText(/senha/i), { target: { value: "senha-forte-1" } });
    fireEvent.click(screen.getByRole("button", { name: /entrar e aceitar/i }));
    await waitFor(() => expect(screen.getByText(/não foi possível entrar/i)).toBeDefined());
    const txt = document.body.textContent ?? "";
    expect(txt).not.toMatch(/convidad[oa]/i);
    expect(chamadasRpc()).toHaveLength(0);
  });

  it("a proteção requiredPrefix=/portal do PortalLogin NÃO é enfraquecida", () => {
    const portalLogin = lerFonte("src/pages/portal/PortalLogin.tsx");
    expect(portalLogin).toContain('requiredPrefix: "/portal"');
    // A página de convite não usa o next do PortalLogin.
    const convite = lerFonte("src/pages/parceiros/AceitarConviteManager.tsx");
    expect(convite).not.toContain("safeInternalDestination");
    expect(convite).not.toContain("next=");
  });
});

describe("R16_MANAGER_INVITE_ACCEPTANCE_UI — desfechos canônicos", () => {
  const casos: Array<[string, RegExp]> = [
    ["invalid_token", /não é válido ou já foi utilizado/i],
    ["expired", /expirou/i],
    ["company_inactive", /não está ativa/i],
    ["email_mismatch", /não é o mesmo que recebeu o convite/i],
    ["already_member", /já faz parte/i],
    ["not_authenticated", /entre com o e-mail/i],
  ];

  for (const [motivo, esperado] of casos) {
    it(`mapeia ${motivo} para mensagem sanitizada`, async () => {
      rpcMock.mockResolvedValue({ data: { ok: false, reason: motivo }, error: null });
      montar();
      await waitFor(() => expect(screen.getByText(esperado)).toBeDefined());
      expect(document.body.textContent ?? "").not.toContain(motivo);
    });
  }

  it("sucesso ativa o acesso e não promete permissão financeira", async () => {
    montar();
    await waitFor(() => expect(screen.getByText(/acesso de gerente ativado/i)).toBeDefined());
    expect(screen.getByText(/acesso financeiro não é concedido automaticamente/i)).toBeDefined();
    expect(screen.getByRole("link", { name: /ir para o painel/i })).toBeDefined();
  });
});

describe("R16 — sem mudança de contrato de banco", () => {
  const convite = lerFonte("src/pages/parceiros/AceitarConviteManager.tsx");

  it("usa somente a RPC canônica accept_manager_invite", () => {
    const rpcs = [...convite.matchAll(/\.rpc\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
    expect(rpcs).toEqual(["accept_manager_invite"]);
  });

  it("não escreve direto em tabela de membros", () => {
    // Nenhum acesso a tabela: o unico caminho e a RPC canonica.
    expect(convite).not.toMatch(/supabase\s*\.\s*from\(/);
    // Nenhuma mutacao PostgREST. (limpos.delete e URLSearchParams, nao banco)
    expect(convite).not.toMatch(/supabase[\s\S]{0,80}\.(insert|update|upsert|delete)\(/);
  });
});
