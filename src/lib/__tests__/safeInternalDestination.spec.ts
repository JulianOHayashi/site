import { describe, it, expect } from "vitest";
import { safeInternalDestination } from "../safeInternalDestination";

/**
 * M0.5 — cobertura de segurança do destino interno.
 *
 * Três camadas:
 *  1. verdade de campo: os payloads realmente escapam de origem quando
 *     resolvidos pelo parser WHATWG (justifica a correção);
 *  2. comportamento do helper novo;
 *  3. comparação explícita com a validação antiga por prefixo, provando
 *     qual bypass existia no main R4.
 */

const ORIGEM = "https://internal.invalid";

/** Payloads que NÃO podem virar destino de navegação. */
const PAYLOADS_HOSTIS = [
  "//evil.com",
  "//evil.com/caminho",
  "/\\evil.com",
  "/\\/evil.com",
  "/\\\\evil.com",
  "\\\\evil.com",
  "\\/evil.com",
  "/\tevil.com".replace("/\t", "/\t/"), // tab interno removido pelo parser
  "/\t/evil.com",
  "/\n/evil.com",
  "/\r/evil.com",
  "https://evil.com",
  "http://evil.com",
  "https:/evil.com",
  "javascript:alert(1)",
  // eslint-disable-next-line no-script-url
  "JavaScript:alert(1)",
  "data:text/html,<script>alert(1)</script>",
  "mailto:alvo@evil.com",
  "vbscript:msgbox(1)",
  "",
  "oportunidades",
  "../admin",
  "./x",
];

// ---------------------------------------------------------------------------
// 1. Verdade de campo
// ---------------------------------------------------------------------------

describe("verdade de campo: o parser realmente muda de origem", () => {
  it("resolve /\\evil.com para outra origem (o bypass é real)", () => {
    expect(new URL("/\\evil.com", ORIGEM).origin).toBe("https://evil.com");
  });

  it("resolve /\\t/evil.com para outra origem após remover o tab", () => {
    expect(new URL("/\t/evil.com", ORIGEM).origin).toBe("https://evil.com");
  });

  it("mantém a origem para um caminho interno legítimo", () => {
    expect(new URL("/oportunidades", ORIGEM).origin).toBe(ORIGEM);
  });
});

// ---------------------------------------------------------------------------
// 2. Helper novo
// ---------------------------------------------------------------------------

describe("safeInternalDestination — rejeição", () => {
  for (const payload of PAYLOADS_HOSTIS) {
    it(`rejeita ${JSON.stringify(payload)}`, () => {
      expect(safeInternalDestination(payload, "/oportunidades")).toBe(
        "/oportunidades"
      );
    });
  }

  it("rejeita null e undefined", () => {
    expect(safeInternalDestination(null, "/oportunidades")).toBe("/oportunidades");
    expect(safeInternalDestination(undefined, "/oportunidades")).toBe(
      "/oportunidades"
    );
  });

  it("nunca devolve destino cuja resolução mude de origem", () => {
    for (const payload of [...PAYLOADS_HOSTIS, null, undefined]) {
      const destino = safeInternalDestination(payload, "/oportunidades");
      expect(new URL(destino, ORIGEM).origin).toBe(ORIGEM);
    }
  });

  it("cai para / quando até o fallback é inseguro", () => {
    expect(safeInternalDestination("//evil.com", "//tambem-evil.com")).toBe("/");
  });
});

describe("safeInternalDestination — aceitação", () => {
  it("aceita caminho interno simples", () => {
    expect(safeInternalDestination("/oportunidades", "/")).toBe("/oportunidades");
  });

  it("preserva query e hash", () => {
    expect(
      safeInternalDestination("/portal/validar?qt=XYZ#topo", "/portal/dashboard")
    ).toBe("/portal/validar?qt=XYZ#topo");
  });

  it("normaliza o caminho pelo parser", () => {
    expect(safeInternalDestination("/portal//dashboard", "/")).toBe(
      "/portal//dashboard"
    );
    expect(safeInternalDestination("/a/../oportunidades", "/")).toBe(
      "/oportunidades"
    );
  });
});

describe("safeInternalDestination — requiredPrefix", () => {
  it("aceita a raiz e a subárvore do prefixo", () => {
    expect(
      safeInternalDestination("/admin", "/admin", { requiredPrefix: "/admin" })
    ).toBe("/admin");
    expect(
      safeInternalDestination("/admin/relatorios", "/admin", {
        requiredPrefix: "/admin",
      })
    ).toBe("/admin/relatorios");
  });

  it("rejeita prefixo colado sem fronteira de segmento", () => {
    expect(
      safeInternalDestination("/administrador", "/admin", {
        requiredPrefix: "/admin",
      })
    ).toBe("/admin");
    expect(
      safeInternalDestination("/portalfalso", "/portal/dashboard", {
        requiredPrefix: "/portal",
      })
    ).toBe("/portal/dashboard");
  });

  it("rejeita destino interno fora da subárvore", () => {
    expect(
      safeInternalDestination("/portal/dashboard", "/admin", {
        requiredPrefix: "/admin",
      })
    ).toBe("/admin");
  });

  it("aceita /portal e /portal/* para o portal", () => {
    expect(
      safeInternalDestination("/portal", "/portal/dashboard", {
        requiredPrefix: "/portal",
      })
    ).toBe("/portal");
    expect(
      safeInternalDestination("/portal/solicitacoes", "/portal/dashboard", {
        requiredPrefix: "/portal",
      })
    ).toBe("/portal/solicitacoes");
  });
});

// ---------------------------------------------------------------------------
// 3. Comparação antigo × novo
// ---------------------------------------------------------------------------

/** Validação exata que existia em SelecionarLocalidade.tsx no main R4. */
function antigoSelecionarLocalidade(next: string | null): string {
  return next && next.startsWith("/") && !next.startsWith("//")
    ? next
    : "/oportunidades";
}

/** Validação exata que existia em AdminLogin.tsx no main R4. */
function antigoAdminLogin(next: string | null): string {
  if (next && next.startsWith("/admin") && !next.startsWith("//")) return next;
  return "/admin";
}

/** Validação exata que existia em PortalLogin.tsx no main R4. */
function antigoPortalLogin(next: string | null): string {
  return next && next.startsWith("/portal") ? next : "/portal/dashboard";
}

describe("comparação antigo × novo", () => {
  it("a validação antiga de /selecionar-localidade aceitava bypass por backslash", () => {
    expect(antigoSelecionarLocalidade("/\\evil.com")).toBe("/\\evil.com");
    expect(new URL(antigoSelecionarLocalidade("/\\evil.com"), ORIGEM).origin).toBe(
      "https://evil.com"
    );
  });

  it("a validação antiga aceitava bypass por caractere removido pelo parser", () => {
    expect(new URL(antigoSelecionarLocalidade("/\t/evil.com"), ORIGEM).origin).toBe(
      "https://evil.com"
    );
  });

  it("o helper novo rejeita exatamente os mesmos payloads", () => {
    for (const payload of PAYLOADS_HOSTIS) {
      const antigo = antigoSelecionarLocalidade(payload);
      const novo = safeInternalDestination(payload, "/oportunidades");
      expect(new URL(novo, ORIGEM).origin).toBe(ORIGEM);
      if (new URL(antigo, ORIGEM).origin !== ORIGEM) {
        expect(novo).not.toBe(antigo);
      }
    }
  });

  it("as validações antigas de /admin e /portal permanecem cobertas pelo helper", () => {
    for (const payload of PAYLOADS_HOSTIS) {
      expect(
        new URL(
          safeInternalDestination(payload, "/admin", { requiredPrefix: "/admin" }),
          ORIGEM
        ).origin
      ).toBe(ORIGEM);
      expect(
        new URL(
          safeInternalDestination(payload, "/portal/dashboard", {
            requiredPrefix: "/portal",
          }),
          ORIGEM
        ).origin
      ).toBe(ORIGEM);
    }
    // A grafia sem fronteira de segmento passava no antigo e não passa no novo.
    expect(antigoAdminLogin("/administrador")).toBe("/administrador");
    expect(antigoPortalLogin("/portalfalso")).toBe("/portalfalso");
  });
});
