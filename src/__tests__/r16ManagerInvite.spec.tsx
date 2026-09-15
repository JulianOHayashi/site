import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor, act } from "@testing-library/react";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";
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

/**
 * `useAuth` obtém a sessão por DOIS caminhos: `getSession()` na montagem e
 * `onAuthStateChange(cb)` depois. Mockar apenas o primeiro deixaria o caminho
 * de login bem-sucedido sem prova — que é exatamente o achado corrigido aqui.
 * Os callbacks reais registrados pelo hook ficam guardados para que o teste
 * possa emitir a transição de sessão como o Supabase emitiria.
 */
type OuvinteAuth = (evento: string, sessao: unknown) => void;
const ouvintesAuth: OuvinteAuth[] = [];

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      signInWithPassword: (...a: unknown[]) => signInMock(...(a as [])),
      getSession: (...a: unknown[]) => getSessionMock(...(a as [])),
      onAuthStateChange: (cb: OuvinteAuth) => {
        ouvintesAuth.push(cb);
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      },
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

/**
 * Observador da localização DO ROTEADOR.
 *
 * `MemoryRouter` mantém o histórico em memória e NÃO escreve em
 * `window.location`. Afirmar sobre `window.location.search` passaria mesmo se
 * o token continuasse na rota — a asserção seria vazia. Este componente lê a
 * localização real do roteador.
 */
let historicoBusca: string[] = [];
function ObservadorDeLocalizacao() {
  const busca = useLocation().search;
  if (historicoBusca[historicoBusca.length - 1] !== busca) historicoBusca.push(busca);
  return null;
}

function montar(query = `?token=${TOKEN}`) {
  return render(
    <MemoryRouter initialEntries={[`/parceiros/convite${query}`]}>
      <ObservadorDeLocalizacao />
      <Routes>
        <Route path="/parceiros/convite" element={<AceitarConviteManager />} />
        <Route path="/parceiros/painel" element={<div data-testid="painel">painel</div>} />
        <Route path="/parceiros" element={<div data-testid="parceiros">parceiros</div>} />
      </Routes>
    </MemoryRouter>
  );
}

/** Emite a transição de sessão como o Supabase emitiria após o login. */
async function emitirSessaoAutenticada(sessao: unknown) {
  await act(async () => {
    for (const cb of ouvintesAuth) cb("SIGNED_IN", sessao);
  });
}

beforeEach(() => {
  rpcMock.mockReset();
  signInMock.mockReset();
  getSessionMock.mockReset();
  ouvintesAuth.length = 0;
  historicoBusca = [];
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

  it("o token não permanece na URL do navegador", async () => {
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

  it("o convite permanece ISOLADO do fluxo ?next= do PortalLogin", () => {
    // Esta asserção cobria também o PortalLogin, exigindo a string
    // 'requiredPrefix: "/portal"' no fonte. Isso acoplava o teste a UMA
    // implementação: o Gate E passou a normalizar o destino primeiro e a
    // aplicar depois a allowlist das duas subárvores que podem iniciar
    // autenticação (/portal e /beneficios/validar). O contrato de segurança
    // ficou mais forte, e ainda assim a asserção antiga reprovava.
    //
    // O comportamento do redirecionamento agora é provado por
    // loginRedirectSinks.spec.tsx, que exercita o caminho real
    // (sessão → efeito → navigate) em vez de ler o código-fonte.
    //
    // O que permanece aqui é o invariante do CONVITE, que é de acoplamento
    // legítimo: a página de aceite não participa daquele fluxo. Se um dia
    // participar, este teste tem de ser reaberto de propósito.
    const convite = lerFonte("src/pages/parceiros/AceitarConviteManager.tsx");
    expect(convite).not.toContain("safeInternalDestination");
    expect(convite).not.toContain("next=");
    expect(convite).not.toContain("/portal/login");
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

describe("R16_MANAGER_INVITE_URL_REDACTION_ROUTER_PROOF", () => {
  it("a localização DO ROTEADOR perde o token depois da captura", async () => {
    montar();
    await waitFor(() => expect(chamadasRpc().length).toBe(1));

    // Controle: o roteador REALMENTE começou com o segredo na query. Sem esta
    // asserção, "não contém token" poderia ser verdade por nunca ter contido.
    expect(historicoBusca.length).toBeGreaterThanOrEqual(2);
    expect(historicoBusca[0]).toContain(TOKEN);

    // E a localização corrente do roteador não o contém mais.
    const atual = historicoBusca[historicoBusca.length - 1];
    expect(atual).not.toContain(TOKEN);
    expect(atual).not.toContain("token=");
  });

  it("parâmetros vizinhos inofensivos são preservados intactos", async () => {
    montar(`?origem=email&token=${TOKEN}&campanha=convite-2026`);
    await waitFor(() => expect(chamadasRpc().length).toBe(1));

    const atual = historicoBusca[historicoBusca.length - 1];
    expect(atual).not.toContain(TOKEN);
    const p = new URLSearchParams(atual);
    expect(p.get("origem")).toBe("email");
    expect(p.get("campanha")).toBe("convite-2026");
    expect(p.get("token")).toBeNull();
  });

  it("a remoção usa replace, sem empilhar entrada no histórico", () => {
    const convite = lerFonte("src/pages/parceiros/AceitarConviteManager.tsx");
    // Uma entrada nova no histórico deixaria o segredo alcançável pelo botão
    // "voltar" do navegador.
    expect(convite).toMatch(/setParams\(\s*limpos\s*,\s*\{\s*replace:\s*true\s*\}\s*\)/);
  });
});

describe("R16_MANAGER_INVITE_POST_LOGIN_TOKEN_CONTINUITY", () => {
  it("caminho completo não autenticado → login → MESMO token, exatamente uma vez", async () => {
    getSessionMock.mockImplementation(semSessao);
    signInMock.mockResolvedValue({ data: { user: { id: "u1" } }, error: null });

    montar();

    // 1-3. sem sessão, token capturado, nenhuma chamada à RPC.
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /entrar e aceitar/i })).toBeDefined()
    );
    expect(chamadasRpc()).toHaveLength(0);
    expect(historicoBusca[0]).toContain(TOKEN);

    // 4-5. credenciais válidas; signInWithPassword é bem-sucedido.
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "g@empresa.com.br" } });
    fireEvent.change(screen.getByLabelText(/senha/i), { target: { value: "senha-forte-1" } });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /entrar e aceitar/i }));
    });
    expect(signInMock).toHaveBeenCalledTimes(1);
    // Ainda sem RPC: a sessão só existe quando o Auth emitir a transição.
    expect(chamadasRpc()).toHaveLength(0);

    // 6. o Auth emite a sessão autenticada pelo mesmo canal do useAuth real.
    await emitirSessaoAutenticada({ access_token: "novo", user: { id: "u1" } });

    // 7-8. exatamente uma chamada, com o token original byte a byte.
    await waitFor(() => expect(chamadasRpc()).toHaveLength(1));
    expect((chamadasRpc()[0][1] as { p_token: string }).p_token).toBe(TOKEN);
    await waitFor(() => expect(screen.getByText(/acesso de gerente ativado/i)).toBeDefined());
  });

  it("o token sobrevive ao login mesmo já tendo saído da URL", async () => {
    getSessionMock.mockImplementation(semSessao);
    signInMock.mockResolvedValue({ data: { user: { id: "u1" } }, error: null });

    montar();
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /entrar e aceitar/i })).toBeDefined()
    );

    // A URL já foi limpa ANTES do login; o token vive apenas em memória.
    expect(historicoBusca[historicoBusca.length - 1]).not.toContain(TOKEN);

    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "g@empresa.com.br" } });
    fireEvent.change(screen.getByLabelText(/senha/i), { target: { value: "senha-forte-1" } });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /entrar e aceitar/i }));
    });
    await emitirSessaoAutenticada({ access_token: "novo", user: { id: "u1" } });

    await waitFor(() => expect(chamadasRpc()).toHaveLength(1));
    expect((chamadasRpc()[0][1] as { p_token: string }).p_token).toBe(TOKEN);
  });

  it("uma segunda emissão de sessão NÃO reenvia a RPC após SUCESSO", async () => {
    montar();
    await waitFor(() => expect(chamadasRpc()).toHaveLength(1));
    // Renovação de token emite novo evento; o convite não pode ser reaceito.
    await emitirSessaoAutenticada({ access_token: "b", user: { id: "u1" } });
    expect(chamadasRpc()).toHaveLength(1);
  });

  it("uma segunda emissão de sessão NÃO reenvia a RPC após FALHA", async () => {
    // Caminho onde a guarda de tentativa única é a ÚNICA proteção: no sucesso
    // o token é anulado e isso bastaria; na falha ele permanece em memória, e
    // sem a guarda a renovação de sessão dispararia uma nova tentativa.
    rpcMock.mockResolvedValue({ data: { ok: false, reason: "expired" }, error: null });
    montar();
    await waitFor(() => expect(chamadasRpc()).toHaveLength(1));
    await waitFor(() => expect(screen.getByText(/expirou/i)).toBeDefined());

    await emitirSessaoAutenticada({ access_token: "b", user: { id: "u1" } });
    await emitirSessaoAutenticada({ access_token: "c", user: { id: "u1" } });
    expect(chamadasRpc()).toHaveLength(1);
  });

  it("o mock de onAuthStateChange é realmente consumido pelo useAuth", async () => {
    getSessionMock.mockImplementation(semSessao);
    montar();
    await waitFor(() => expect(ouvintesAuth.length).toBeGreaterThanOrEqual(1));
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
