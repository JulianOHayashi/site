import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";

/**
 * M0.5 — prova de fiação dos sinks de login.
 *
 * Complementa navegacaoSegura.spec.tsx, que cobre /selecionar-localidade.
 * Aqui cobrimos os outros dois sinks USER_CONTROLLED reais:
 * /admin/login e /portal/login.
 *
 * O mock é feito SOMENTE na fronteira externa (`src/lib/supabase`), não
 * nos hooks da própria aplicação: assim `useAuth` e `usePortalSiteAuth`
 * rodam de verdade e o teste exercita o caminho real
 *   sessão detectada → efeito → navigate(destino).
 * Nenhum código de produção foi alterado para viabilizar estes testes.
 */

const sessaoFalsa = {
  access_token: "token-de-teste",
  user: { id: "00000000-0000-0000-0000-000000000001" },
} as unknown as Session;

vi.mock("../lib/supabase", () => {
  const auth = {
    getSession: vi.fn(async () => ({ data: { session: sessaoFalsa } })),
    onAuthStateChange: vi.fn(() => ({
      data: { subscription: { unsubscribe: vi.fn() } },
    })),
    signInWithPassword: vi.fn(),
  };
  return { supabase: { auth }, supabaseConfigurado: true };
});

import AdminLogin from "../pages/AdminLogin";
import PortalLogin from "../pages/portal/PortalLogin";

/** Espia o destino final da navegação dentro do MemoryRouter. */
function Espiao() {
  const location = useLocation();
  return (
    <div data-testid="destino-final">
      {location.pathname}
      {location.search}
    </div>
  );
}

function montar(rota: string, caminho: string, elemento: React.ReactElement) {
  return render(
    <MemoryRouter initialEntries={[rota]}>
      <Routes>
        <Route path={caminho} element={elemento} />
        <Route path="*" element={<Espiao />} />
      </Routes>
    </MemoryRouter>
  );
}

async function destinoFinal() {
  const el = await waitFor(() => screen.getByTestId("destino-final"));
  return el.textContent;
}

function entrada(base: string, next: string) {
  return `${base}?next=${encodeURIComponent(next)}`;
}

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("/admin/login — destino do ?next=", () => {
  const montarAdmin = (next: string) =>
    montar(entrada("/admin/login", next), "/admin/login", <AdminLogin />);

  it("permite destino legítimo dentro de /admin", async () => {
    montarAdmin("/admin/relatorios?periodo=2026-08");
    expect(await destinoFinal()).toBe("/admin/relatorios?periodo=2026-08");
  });

  it("rejeita bypass por backslash e cai em /admin", async () => {
    montarAdmin("/\\evil.com");
    expect(await destinoFinal()).toBe("/admin");
  });

  it("rejeita prefixo colado /administrador e cai em /admin", async () => {
    montarAdmin("/administrador");
    expect(await destinoFinal()).toBe("/admin");
  });

  it("rejeita destino interno fora da subárvore /admin", async () => {
    montarAdmin("/portal/dashboard");
    expect(await destinoFinal()).toBe("/admin");
  });

  it("normaliza o destino pelo parser em vez de repassar a string crua", async () => {
    // A validação antiga devolvia "/admin\\relatorios" literalmente.
    montarAdmin("/admin\\relatorios");
    expect(await destinoFinal()).toBe("/admin/relatorios");
  });

  // Documenta o contrato de normalização. Não discrimina antigo x novo:
  // o próprio roteador resolve "../" mesmo recebendo a string crua.
  it("resolve segmentos relativos antes de navegar", async () => {
    montarAdmin("/admin/x/../y");
    expect(await destinoFinal()).toBe("/admin/y");
  });
});

describe("/portal/login — destino do ?next=", () => {
  const montarPortal = (next: string) =>
    montar(entrada("/portal/login", next), "/portal/login", <PortalLogin />);

  it("permite destino legítimo dentro de /portal", async () => {
    montarPortal("/portal/validar?qt=XYZ");
    expect(await destinoFinal()).toBe("/portal/validar?qt=XYZ");
  });

  it("rejeita bypass por backslash e cai em /portal/dashboard", async () => {
    montarPortal("/\\evil.com");
    expect(await destinoFinal()).toBe("/portal/dashboard");
  });

  it("rejeita prefixo colado /portalfalso e cai em /portal/dashboard", async () => {
    montarPortal("/portalfalso");
    expect(await destinoFinal()).toBe("/portal/dashboard");
  });

  it("rejeita destino interno fora da subárvore /portal", async () => {
    montarPortal("/admin");
    expect(await destinoFinal()).toBe("/portal/dashboard");
  });

  it("normaliza o destino pelo parser em vez de repassar a string crua", async () => {
    // A validação antiga devolvia "/portal\\validar" literalmente.
    montarPortal("/portal\\validar");
    expect(await destinoFinal()).toBe("/portal/validar");
  });

  // -------------------------------------------------------------------------
  // Gate E — /beneficios/validar passou a ser a SEGUNDA subárvore que pode
  // iniciar autenticação. O QR do aplicativo cai nessa rota antes do login, e
  // sem isso o parceiro era jogado no painel e perdia o benefício em mãos.
  //
  // A allowlist é de duas subárvores, aplicada DEPOIS da normalização — não
  // um prefixo único. Estas provas são de comportamento: exercitam
  // sessão → efeito → navigate, sem ler o código-fonte.
  // -------------------------------------------------------------------------

  it("permite a rota de validação de benefício vinda do QR", async () => {
    montarPortal("/beneficios/validar/11111111-2222-4333-8444-555555555555");
    expect(await destinoFinal()).toBe(
      "/beneficios/validar/11111111-2222-4333-8444-555555555555"
    );
  });

  it("permite a raiz exata da subárvore de validação", async () => {
    montarPortal("/beneficios/validar");
    expect(await destinoFinal()).toBe("/beneficios/validar");
  });

  it("rejeita prefixo colado /beneficios/validarfalso", async () => {
    // Fronteira de segmento: "validarfalso" não é filho de "validar".
    montarPortal("/beneficios/validarfalso");
    expect(await destinoFinal()).toBe("/portal/dashboard");
  });

  it("rejeita irmã da subárvore permitida dentro de /beneficios", async () => {
    montarPortal("/beneficios/resgatar/abc");
    expect(await destinoFinal()).toBe("/portal/dashboard");
  });

  it("rejeita URL absoluta externa", async () => {
    for (const externo of [
      "https://evil.com/x",
      "http://evil.com",
      "//evil.com/x",
      "javascript:alert(1)",
      "data:text/html,<script>1</script>",
    ]) {
      cleanup();
      montarPortal(externo);
      expect(await destinoFinal(), externo).toBe("/portal/dashboard");
    }
  });

  it("rejeita fuga de origem por backslash que se disfarça de rota de benefício", async () => {
    // Backslash na posição 1 é protocolo-relativo disfarçado: o parser o
    // trata como "/", a origem muda, e o destino reprova antes mesmo da
    // allowlist. Não confundir com backslash NO MEIO do caminho, que apenas
    // normaliza para "/" e continua interno — esse caso é legítimo e cai
    // numa rota inexistente, tratada pelo roteador.
    montarPortal("/\\\\beneficios/validar/abc");
    expect(await destinoFinal()).toBe("/portal/dashboard");
  });

  it("preserva a query do destino de validação, que carrega contexto legítimo", async () => {
    montarPortal("/beneficios/validar/abc?origem=qr");
    expect(await destinoFinal()).toBe("/beneficios/validar/abc?origem=qr");
  });
});
