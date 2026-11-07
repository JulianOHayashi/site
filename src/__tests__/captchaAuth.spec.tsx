import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor, act } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * CAPTCHA (Cloudflare Turnstile) nas operações do Supabase Auth.
 *
 * Invariantes:
 *  - sem token válido, NENHUMA operação de Auth sai da tela;
 *  - o token chega em `options.captchaToken` e é de uso único: depois de cada
 *    tentativa ele é descartado e o widget é resetado;
 *  - erro de CAPTCHA e erros desconhecidos não vazam detalhe do servidor;
 *  - credencial inválida continua com a mensagem genérica de sempre;
 *  - build de Production sem site key falha FECHADO.
 *
 * Site key de teste: "1x00000000000000000000AA" é a chave PÚBLICA de teste
 * documentada pela Cloudflare (sempre passa). Não é credencial. O secret do
 * Turnstile não existe em lugar nenhum deste repositório.
 */
const SITE_KEY_TESTE = "1x00000000000000000000AA";

const signIn = vi.fn();
const signUp = vi.fn();
const resetSenha = vi.fn();
const rpcMock = vi.fn();

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (...a: unknown[]) => rpcMock(...(a as [])),
    auth: {
      signInWithPassword: (...a: unknown[]) => signIn(...a),
      signUp: (...a: unknown[]) => signUp(...a),
      resetPasswordForEmail: (...a: unknown[]) => resetSenha(...a),
      getSession: vi.fn(async () => ({ data: { session: null } })),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
    },
  },
  supabaseConfigurado: true,
}));

/* ------------------------------ Turnstile falso ----------------------------- */
type Opcoes = {
  sitekey: string;
  action?: string;
  callback?: (t: string) => void;
  "expired-callback"?: () => void;
  "error-callback"?: () => void;
};
let widgets: Opcoes[];
let resets: string[];
function instalarTurnstileFalso() {
  widgets = [];
  resets = [];
  window.turnstile = {
    render: (_el: HTMLElement, o: Opcoes) => {
      widgets.push(o);
      return `w${widgets.length}`;
    },
    reset: (id?: string) => void resets.push(String(id)),
    remove: vi.fn(),
  };
}
/** O widget emite um token (como quando o desafio é resolvido). */
async function resolverCaptcha(token: string) {
  await waitFor(() => expect(widgets.length).toBeGreaterThan(0));
  await act(async () => widgets[widgets.length - 1].callback!(token));
}

const opcoesDe = (fn: ReturnType<typeof vi.fn>, i = 0) => {
  const args = fn.mock.calls[i];
  return (args.length === 1 ? args[0].options : args[1]) as { captchaToken?: string } | undefined;
};

async function montar(rota: string, carregar: () => Promise<{ default: React.ComponentType }>) {
  vi.resetModules();
  const { default: Tela } = await carregar();
  render(
    <MemoryRouter initialEntries={[rota]}>
      <Routes>
        <Route path="*" element={<Tela />} />
      </Routes>
    </MemoryRouter>
  );
}

function preencherLogin() {
  fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "pessoa@exemplo.com.br" } });
  fireEvent.change(screen.getByLabelText(/^senha$/i), { target: { value: "senha-qualquer-1" } });
}
const enviar = () => fireEvent.submit(screen.getByLabelText(/e-mail/i).closest("form")!);

beforeEach(() => {
  signIn.mockReset();
  signUp.mockReset();
  resetSenha.mockReset();
  rpcMock.mockReset();
  localStorage.clear();
  sessionStorage.clear();
  instalarTurnstileFalso();
  vi.stubEnv("VITE_TURNSTILE_SITE_KEY", SITE_KEY_TESTE);
  signIn.mockResolvedValue({ data: { session: null }, error: { code: "invalid_credentials", message: "Invalid login credentials" } });
});

afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
  delete window.turnstile;
});

/* ---------------------------- três telas de login --------------------------- */
const LOGINS = [
  { nome: "Portal", rota: "/portal/login", acao: "login_portal", carregar: () => import("../pages/portal/PortalLogin") },
  { nome: "Admin", rota: "/admin/login", acao: "login_admin", carregar: () => import("../pages/AdminLogin") },
  { nome: "provisório", rota: "/parceiros/acesso", acao: "login_provisorio", carregar: () => import("../pages/ParceirosAcesso") },
] as const;

describe.each(LOGINS)("login $nome", ({ rota, acao, carregar }) => {
  it("não envia Auth sem CAPTCHA válido (botão travado e envio forçado bloqueado)", async () => {
    await montar(rota, carregar);
    await waitFor(() => expect(widgets).toHaveLength(1));
    expect(widgets[0].sitekey).toBe(SITE_KEY_TESTE);
    expect(widgets[0].action).toBe(acao);
    preencherLogin();
    expect((screen.getByRole("button", { name: /entrar/i }) as HTMLButtonElement).disabled).toBe(true);
    enviar(); // contorna o botão: o handler também recusa
    expect(signIn).not.toHaveBeenCalled();
    expect(await screen.findByText(/Conclua a verificação de segurança/i)).toBeDefined();
  });

  it("token chega ao Supabase, é descartado e o widget resetado após a tentativa", async () => {
    await montar(rota, carregar);
    await resolverCaptcha("tok-1");
    preencherLogin();
    enviar();
    await waitFor(() => expect(signIn).toHaveBeenCalledTimes(1));
    expect(opcoesDe(signIn)?.captchaToken).toBe("tok-1");
    expect(resets).toEqual(["w1"]);
    // Credencial inválida: mensagem genérica de sempre (não diz se a conta existe).
    expect(await screen.findByText("E-mail ou senha incorretos.")).toBeDefined();

    // Sem novo token, a segunda tentativa não sai (token usado não é reaproveitado).
    enviar();
    await new Promise((r) => setTimeout(r, 20));
    expect(signIn).toHaveBeenCalledTimes(1);

    // Novo token → nova tentativa permitida, com o token NOVO.
    await resolverCaptcha("tok-2");
    enviar();
    await waitFor(() => expect(signIn).toHaveBeenCalledTimes(2));
    expect(opcoesDe(signIn, 1)?.captchaToken).toBe("tok-2");
  });

  it("erro de CAPTCHA e erro desconhecido não vazam detalhe interno", async () => {
    signIn.mockResolvedValueOnce({
      data: { session: null },
      error: { code: "captcha_failed", status: 400, message: "captcha protection: request disallowed (secret-xyz invalid)" },
    });
    await montar(rota, carregar);
    await resolverCaptcha("tok-1");
    preencherLogin();
    enviar();
    expect(await screen.findByText(/Não foi possível confirmar a verificação de segurança/i)).toBeDefined();
    expect(document.body.textContent).not.toMatch(/secret-xyz|request disallowed|captcha protection/i);

    signIn.mockResolvedValueOnce({
      data: { session: null },
      error: { code: "unexpected_failure", status: 500, message: "db timeout at node-7" },
    });
    await resolverCaptcha("tok-2");
    enviar();
    expect(await screen.findByText("Não foi possível entrar. Tente novamente.")).toBeDefined();
    expect(document.body.textContent).not.toMatch(/node-7|db timeout/i);
  });

  it("Production sem site key falha FECHADO: nada é enviado ao Auth", async () => {
    vi.stubEnv("VITE_TURNSTILE_SITE_KEY", "");
    vi.stubEnv("PROD", true);
    await montar(rota, carregar);
    expect(await screen.findByText(/verificação de segurança não está configurada/i)).toBeDefined();
    expect(widgets).toHaveLength(0);
    preencherLogin();
    expect((screen.getByRole("button", { name: /entrar/i }) as HTMLButtonElement).disabled).toBe(true);
    enviar();
    await new Promise((r) => setTimeout(r, 20));
    expect(signIn).not.toHaveBeenCalled();
  });
});

/* ------------------------------ recuperação --------------------------------- */
describe("recuperação de senha", () => {
  const carregar = () => import("../pages/portal/PortalForgotPassword");
  const preencher = () =>
    fireEvent.change(screen.getByLabelText(/e-mail/i), { target: { value: "pessoa@exemplo.com.br" } });

  it("sem token não envia; com token envia captchaToken + redirectTo e mantém resposta invariável", async () => {
    resetSenha.mockResolvedValue({ data: {}, error: null });
    await montar("/portal/recuperar-senha", carregar);
    preencher();
    enviar();
    expect(resetSenha).not.toHaveBeenCalled();

    await resolverCaptcha("tok-r");
    enviar();
    await waitFor(() => expect(resetSenha).toHaveBeenCalledTimes(1));
    expect(resetSenha.mock.calls[0][0]).toBe("pessoa@exemplo.com.br");
    expect(opcoesDe(resetSenha)).toEqual({
      redirectTo: `${window.location.origin}/portal/redefinir-senha?mode=recovery`,
      captchaToken: "tok-r",
    });
    expect(widgets[0].action).toBe("reset_senha");
    expect(resets).toEqual(["w1"]);
    expect(await screen.findByText(/Se houver uma conta para este e-mail/i)).toBeDefined();
  });

  it("CAPTCHA recusado: não finge que enviou, pede nova tentativa e não vaza detalhe", async () => {
    resetSenha.mockResolvedValue({ data: {}, error: { code: "captcha_failed", message: "captcha protection: x" } });
    await montar("/portal/recuperar-senha", carregar);
    preencher();
    await resolverCaptcha("tok-r");
    enviar();
    expect(await screen.findByText(/Não foi possível confirmar a verificação de segurança/i)).toBeDefined();
    expect(screen.queryByText(/Se houver uma conta para este e-mail/i)).toBeNull();
    expect(document.body.textContent).not.toMatch(/captcha protection/i);
  });

  it("qualquer outro erro mantém a resposta invariável (não revela se a conta existe)", async () => {
    resetSenha.mockResolvedValue({ data: {}, error: { code: "user_not_found", message: "User not found" } });
    await montar("/portal/recuperar-senha", carregar);
    preencher();
    await resolverCaptcha("tok-r");
    enviar();
    expect(await screen.findByText(/Se houver uma conta para este e-mail/i)).toBeDefined();
    expect(document.body.textContent).not.toMatch(/not found/i);
  });
});

/* -------------------------- cadastro (signUp) ------------------------------- */
describe("cadastro do acesso provisório", () => {
  const CLAIM = "k".repeat(64);
  const carregar = () => import("../pages/parceiros/ConfirmarEmail");
  const preencher = async () => {
    await waitFor(() => expect(screen.getByLabelText(/^e-mail$/i)).toBeDefined());
    fireEvent.change(screen.getByLabelText(/^e-mail$/i), { target: { value: "contato@teste.com.br" } });
    fireEvent.change(screen.getByLabelText(/^senha$/i), { target: { value: "senha-forte-1" } });
  };
  const continuar = () => fireEvent.submit(screen.getByLabelText(/^e-mail$/i).closest("form")!);

  beforeEach(() => {
    rpcMock.mockResolvedValue({ data: [], error: null });
  });

  it("signUp não sai sem CAPTCHA e, com token, recebe captchaToken", async () => {
    signUp.mockResolvedValue({ data: { session: { access_token: "t" } }, error: null });
    await montar(`/parceiros/confirmar?claim=${CLAIM}`, carregar);
    await preencher();
    continuar();
    expect(signUp).not.toHaveBeenCalled();

    await resolverCaptcha("tok-s");
    continuar();
    await waitFor(() => expect(signUp).toHaveBeenCalledTimes(1));
    expect(signUp.mock.calls[0][0]).toMatchObject({
      email: "contato@teste.com.br",
      options: { captchaToken: "tok-s" },
    });
    expect(widgets[0].action).toBe("cadastro_provisorio");
    expect(signIn).not.toHaveBeenCalled();
  });

  it("conta já existente: o login de fallback usa um token NOVO, nunca o já gasto", async () => {
    signUp.mockResolvedValue({ data: { session: null }, error: { code: "user_already_exists", message: "User already registered" } });
    signIn.mockResolvedValue({ data: { session: { access_token: "t" } }, error: null });
    await montar(`/parceiros/confirmar?claim=${CLAIM}`, carregar);
    await preencher();
    await resolverCaptcha("tok-1");
    continuar();
    await waitFor(() => expect(signUp).toHaveBeenCalledTimes(1));
    expect(signIn).not.toHaveBeenCalled(); // esperando o token novo
    await resolverCaptcha("tok-2"); // widget resetado emite o próximo
    await waitFor(() => expect(signIn).toHaveBeenCalledTimes(1));
    expect(opcoesDe(signIn)?.captchaToken).toBe("tok-2");
  });

  it("signUp recusado por CAPTCHA não tenta login e não vaza detalhe", async () => {
    signUp.mockResolvedValue({ data: { session: null }, error: { code: "captcha_failed", message: "captcha protection: bad" } });
    await montar(`/parceiros/confirmar?claim=${CLAIM}`, carregar);
    await preencher();
    await resolverCaptcha("tok-1");
    continuar();
    expect(await screen.findByText(/Não foi possível confirmar a verificação de segurança/i)).toBeDefined();
    expect(signIn).not.toHaveBeenCalled();
    expect(document.body.textContent).not.toMatch(/captcha protection/i);
  });
});

/* ------------------------------ widget ------------------------------------- */
describe("widget", () => {
  it("expiração e erro do widget apagam o token e travam o envio até novo token", async () => {
    await montar("/portal/login", () => import("../pages/portal/PortalLogin"));
    await resolverCaptcha("tok-1");
    const botao = () => screen.getByRole("button", { name: /entrar/i }) as HTMLButtonElement;
    expect(botao().disabled).toBe(false);
    await act(async () => widgets[0]["expired-callback"]!());
    expect(botao().disabled).toBe(true);
    await resolverCaptcha("tok-2");
    expect(botao().disabled).toBe(false);
    await act(async () => widgets[0]["error-callback"]!());
    expect(botao().disabled).toBe(true);
    preencherLogin();
    enviar();
    expect(signIn).not.toHaveBeenCalled();
  });
});

/* ------------------------------ configuração -------------------------------- */
describe("lerConfigCaptcha", () => {
  it("site key → turnstile; Production sem key → erro_config; dev sem key → desligado", async () => {
    const { lerConfigCaptcha } = await import("../lib/captcha");
    expect(lerConfigCaptcha({ VITE_TURNSTILE_SITE_KEY: SITE_KEY_TESTE, PROD: true })).toEqual({ modo: "turnstile", siteKey: SITE_KEY_TESTE });
    expect(lerConfigCaptcha({ VITE_TURNSTILE_SITE_KEY: "", PROD: true })).toEqual({ modo: "erro_config" });
    expect(lerConfigCaptcha({ VITE_TURNSTILE_SITE_KEY: "   ", PROD: true })).toEqual({ modo: "erro_config" });
    expect(lerConfigCaptcha({ PROD: false })).toEqual({ modo: "desligado" });
  });
});

/* --------------------- cobertura estática de todos os fluxos ---------------- */
describe("todas as operações de Auth com CAPTCHA no código do navegador", () => {
  it("signInWithPassword, signUp e resetPasswordForEmail sempre levam opcoesComCaptcha", async () => {
    const { readFileSync, readdirSync, statSync } = await import("node:fs");
    const { join, resolve } = await import("node:path");
    const raiz = resolve(__dirname, "..");
    const arquivos: string[] = [];
    const varrer = (dir: string) => {
      for (const nome of readdirSync(dir)) {
        const p = join(dir, nome);
        if (statSync(p).isDirectory()) {
          if (nome === "__tests__" || nome === "server") continue;
          varrer(p);
        } else if (/\.(ts|tsx)$/.test(nome)) arquivos.push(p);
      }
    };
    varrer(raiz);
    const achados: { arquivo: string; op: string; comCaptcha: boolean }[] = [];
    for (const f of arquivos) {
      const texto = readFileSync(f, "utf8");
      for (const m of texto.matchAll(/auth\.(signInWithPassword|signUp|resetPasswordForEmail)\(/g)) {
        // Analisa a chamada até o fechamento do seu parêntese.
        let i = m.index! + m[0].length, nivel = 1;
        while (i < texto.length && nivel > 0) {
          if (texto[i] === "(") nivel++;
          else if (texto[i] === ")") nivel--;
          i++;
        }
        achados.push({
          arquivo: f.slice(raiz.length),
          op: m[1],
          comCaptcha: texto.slice(m.index!, i).includes("opcoesComCaptcha("),
        });
      }
    }
    // Inventário auditado: 7 chamadas em 6 arquivos.
    expect(achados).toHaveLength(7);
    expect(achados.filter((a) => !a.comCaptcha)).toEqual([]);
  });
});
