import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, fireEvent, within } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Sessão em vários aparelhos — com o cliente supabase-js REAL.
 *
 * Nada de mock em `../lib/supabase`. Um servidor de Auth falso reproduz a
 * semântica do GoTrue para refresh token e logout:
 *   scope=local  → revoga só a sessão que chamou;
 *   scope=global → revoga TODAS as sessões da conta (default do supabase-js).
 *
 * Aparelho A = o app de verdade (src/lib/supabase.ts + localStorage do jsdom).
 * Aparelho B = outro cliente supabase-js com armazenamento próprio.
 */

const URL_SUPABASE = "https://mock.supabase.test";
const CHAVE_SESSAO = "sb-mock-auth-token";
const CHAVE_LEGADA = "bdflow_partner_portal_auth";

const usuario = {
  id: "u-1",
  aud: "authenticated",
  role: "authenticated",
  email: "dono@exemplo.com.br",
  app_metadata: {},
  user_metadata: {},
  created_at: "2026-10-01T00:00:00Z",
};

const contextoParceiro = {
  ok: true,
  authorized: true,
  memberships: [
    {
      company_id: "c-1",
      trade_name: "Mercado Exemplo",
      company_status: "active",
      member_id: "m-1",
      role: "partner_owner",
      member_status: "active",
    },
  ],
};

/* ------------------------- servidor de Auth falso ------------------------ */
type SessaoServidor = { id: string; revogada: boolean; refreshAtual: string };
let sessoes: Map<string, SessaoServidor>;
let seq: number;
let logouts: string[];
let refreshes: { ok: boolean }[];

function emitir(sessaoId: string, expiraEmSeg = 3600) {
  const s = sessoes.get(sessaoId)!;
  seq += 1;
  s.refreshAtual = `rt-${sessaoId}-${seq}`;
  const agora = Math.floor(Date.now() / 1000);
  return {
    access_token: `at-${sessaoId}-${seq}`,
    refresh_token: s.refreshAtual,
    token_type: "bearer",
    expires_in: expiraEmSeg,
    expires_at: agora + expiraEmSeg,
    user: usuario,
  };
}

function novaSessaoServidor(expiraEmSeg = 3600) {
  const id = `s${sessoes.size + 1}`;
  sessoes.set(id, { id, revogada: false, refreshAtual: "" });
  return emitir(id, expiraEmSeg);
}

function resposta(corpo: unknown, status = 200) {
  return new Response(status === 204 ? null : JSON.stringify(corpo), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const fetchServidor = vi.fn(async (entrada: RequestInfo | URL, init?: RequestInit) => {
  const u = new URL(typeof entrada === "string" ? entrada : entrada instanceof URL ? entrada.href : entrada.url);
  const corpo = init?.body ? JSON.parse(String(init.body)) : {};
  const auth = new Headers(init?.headers).get("authorization") ?? "";
  const sessaoDoToken = /^Bearer at-(s\d+)-/.exec(auth)?.[1];

  if (u.pathname === "/auth/v1/token") {
    const grant = u.searchParams.get("grant_type");
    if (grant === "password") return resposta(novaSessaoServidor());
    if (grant === "refresh_token") {
      const s = [...sessoes.values()].find((x) => x.refreshAtual === corpo.refresh_token);
      if (!s || s.revogada) {
        refreshes.push({ ok: false });
        return resposta({ error: "invalid_grant", error_description: "Invalid Refresh Token" }, 400);
      }
      refreshes.push({ ok: true });
      return resposta(emitir(s.id));
    }
  }
  if (u.pathname === "/auth/v1/logout") {
    const escopo = u.searchParams.get("scope") ?? "global";
    logouts.push(escopo);
    for (const s of sessoes.values()) {
      if (escopo === "global" || (escopo === "local" && s.id === sessaoDoToken) || (escopo === "others" && s.id !== sessaoDoToken)) {
        s.revogada = true;
      }
    }
    return resposta(null, 204);
  }
  if (u.pathname.startsWith("/auth/v1/user")) return resposta(usuario);
  if (u.pathname === "/rest/v1/rpc/get_my_partner_application") return resposta({});
  if (u.pathname === "/rest/v1/rpc/get_my_partner_context") return resposta(contextoParceiro);
  if (u.pathname.startsWith("/rest/v1/")) return resposta([]);
  return resposta({});
});

/** Aparelho B: outro cliente, com armazenamento próprio (outro telefone). */
function aparelhoB(): SupabaseClient {
  const memoria = new Map<string, string>();
  return createClient(URL_SUPABASE, "chave-anon-de-teste", {
    auth: {
      persistSession: true,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      storage: {
        getItem: (k) => memoria.get(k) ?? null,
        setItem: (k, v) => void memoria.set(k, v),
        removeItem: (k) => void memoria.delete(k),
      },
    },
    global: { fetch: fetchServidor as unknown as typeof fetch },
  });
}

/** Aparelho A: monta o app do zero (módulos novos), como abrir o navegador. */
async function montarAppA(rota: string) {
  vi.resetModules();
  const { default: PortalGuard } = await import("../components/PortalGuard");
  const { default: PortalLayout } = await import("../portal/PortalLayout");
  const { default: PortalDashboard } = await import("../pages/portal/PortalDashboard");
  const { default: PortalLogin } = await import("../pages/portal/PortalLogin");
  const { supabase } = await import("../lib/supabase");
  render(
    <MemoryRouter initialEntries={[rota]}>
      <Routes>
        <Route element={<PortalLayout />}>
          <Route
            path="/portal/dashboard"
            element={
              <PortalGuard>
                <PortalDashboard />
              </PortalGuard>
            }
          />
        </Route>
        <Route path="/portal/login" element={<PortalLogin />} />
      </Routes>
    </MemoryRouter>
  );
  return supabase!;
}

function gravarSessaoA(expiraEmSeg = 3600) {
  localStorage.setItem(CHAVE_SESSAO, JSON.stringify(novaSessaoServidor(expiraEmSeg)));
}

beforeEach(() => {
  sessoes = new Map();
  seq = 0;
  logouts = [];
  refreshes = [];
  fetchServidor.mockClear();
  localStorage.clear();
  sessionStorage.clear();
  vi.stubEnv("VITE_SUPABASE_URL", URL_SUPABASE);
  vi.stubEnv("VITE_SUPABASE_ANON_KEY", "chave-anon-de-teste");
  vi.stubGlobal("fetch", fetchServidor);
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("cliente do navegador", () => {
  it("persistSession, autoRefreshToken e detectSessionInUrl ligados; chave de storage padrão", async () => {
    vi.resetModules();
    const { supabase } = await import("../lib/supabase");
    const auth = supabase!.auth as unknown as Record<string, unknown>;
    expect(auth.persistSession).toBe(true);
    expect(auth.autoRefreshToken).toBe(true);
    expect(auth.detectSessionInUrl).toBe(true);
    expect(auth.storageKey).toBe(CHAVE_SESSAO);
    expect(auth.storage).toBe(globalThis.localStorage);
  });

  it("nova instância do cliente com o mesmo storage restaura a sessão sem novo login", async () => {
    vi.resetModules();
    const { supabase: primeira } = await import("../lib/supabase");
    const { data: login } = await primeira!.auth.signInWithPassword({ email: usuario.email, password: "x" });
    expect(login.session).not.toBeNull();

    vi.resetModules();
    const { supabase: segunda } = await import("../lib/supabase");
    expect(segunda).not.toBe(primeira);
    const { data } = await segunda!.auth.getSession();
    expect(data.session?.access_token).toBe(login.session!.access_token);
    expect(fetchServidor.mock.calls.filter(([u]) => String(u).includes("grant_type=password"))).toHaveLength(1);
  });
});

describe("reload e reabertura no mesmo aparelho", () => {
  it("sessão gravada → F5 → guard NÃO manda ao login", async () => {
    gravarSessaoA();
    await montarAppA("/portal/dashboard");
    expect(await screen.findByRole("heading", { name: "Painel do parceiro" })).toBeDefined();
    expect(screen.queryByRole("heading", { name: /Entrar no portal/i })).toBeNull();
  });

  it("access token expirado na reabertura → refresh → continua autenticado", async () => {
    gravarSessaoA(-60);
    await montarAppA("/portal/dashboard");
    expect(await screen.findByRole("heading", { name: "Painel do parceiro" })).toBeDefined();
    expect(refreshes).toEqual([{ ok: true }]);
  });

  it("limpeza legada remove só bdflow_partner_portal_auth", async () => {
    gravarSessaoA();
    localStorage.setItem(CHAVE_LEGADA, "{}");
    await montarAppA("/portal/dashboard");
    await screen.findByRole("heading", { name: "Painel do parceiro" });
    expect(localStorage.getItem(CHAVE_LEGADA)).toBeNull();
    expect(localStorage.getItem(CHAVE_SESSAO)).not.toBeNull();
  });
});

describe("dois aparelhos", () => {
  it("A e B logados; Sair no A encerra só o A e o B continua renovando", async () => {
    gravarSessaoA();
    const b = aparelhoB();
    await b.auth.signInWithPassword({ email: usuario.email, password: "x" });

    await montarAppA("/portal/dashboard");
    await screen.findByRole("heading", { name: "Painel do parceiro" });
    fireEvent.click(within(screen.getByRole("main")).getByRole("button", { name: "Sair" }));
    await screen.findByRole("heading", { name: /Entrar no portal/i });

    expect(logouts).toEqual(["local"]);
    expect(localStorage.getItem(CHAVE_SESSAO)).toBeNull();

    const { data, error } = await b.auth.refreshSession();
    expect(error).toBeNull();
    expect(data.session).not.toBeNull();
  });

  it("controle: logout GLOBAL derrubaria o B (prova que o teste acima detectaria a regressão)", async () => {
    const a = aparelhoB();
    const b = aparelhoB();
    await a.auth.signInWithPassword({ email: usuario.email, password: "x" });
    await b.auth.signInWithPassword({ email: usuario.email, password: "x" });
    await a.auth.signOut(); // default do supabase-js = global
    expect(logouts).toEqual(["global"]);
    const { error } = await b.auth.refreshSession();
    expect(error).not.toBeNull();
  });
});

describe("todos os logouts normais são locais", () => {
  it("nenhum signOut no código do navegador usa o escopo global (default)", () => {
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
    const chamadas: string[] = [];
    for (const f of arquivos) {
      const texto = readFileSync(f, "utf8");
      for (const m of texto.matchAll(/\.signOut\(([^)]*)\)/g)) chamadas.push(`${f.slice(raiz.length)}: ${m[1].trim()}`);
    }
    expect(chamadas.length).toBeGreaterThanOrEqual(5);
    const naoLocais = chamadas.filter((c) => !/scope:\s*["']local["']/.test(c));
    expect(naoLocais).toEqual([]);
  });
});

describe("navegador que não guarda dados", () => {
  it("localStorage recusando escrita → aviso no login (e sem aviso no navegador normal)", async () => {
    await montarAppA("/portal/login");
    await screen.findByRole("heading", { name: /Entrar no portal/i });
    expect(screen.queryByText(/não está guardando dados do site/i)).toBeNull();
    cleanup();

    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("bloqueado", "SecurityError");
    });
    const { armazenamentoDeSessaoDisponivel } = await import("../lib/armazenamentoSessao");
    expect(armazenamentoDeSessaoDisponivel()).toBe(false);
    await montarAppA("/portal/login");
    expect(await screen.findByText(/não está guardando dados do site/i)).toBeDefined();
  });
});
