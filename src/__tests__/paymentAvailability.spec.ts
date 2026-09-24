import { afterEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { obterDisponibilidadePagamento } from "../services/paymentAvailabilityService";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("payment availability: fail-closed", () => {
  it("libera somente quando o backend confirma explicitamente", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({ ok: true, payment_available: true }),
    })));

    await expect(obterDisponibilidadePagamento()).resolves.toEqual({
      tipo: "disponivel",
    });
  });

  it("erro, resposta invalida ou backend indisponivel bloqueiam", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => {
      throw new Error("offline");
    }));
    await expect(obterDisponibilidadePagamento()).resolves.toEqual({
      tipo: "indisponivel",
    });

    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({ ok: true, payment_available: false }),
    })));
    await expect(obterDisponibilidadePagamento()).resolves.toEqual({
      tipo: "indisponivel",
    });
  });
});

describe("payment provider gate: ordem de execução", () => {
  it("o endpoint valida o provedor antes de abrir tentativa local", () => {
    const src = readFileSync(
      resolve(__dirname, "../../api/payments/create.ts"),
      "utf8"
    );
    const providerPos = src.indexOf("const provedor = createPagarmeClient(process.env)");
    const paymentPos = src.indexOf("const resultado = await criarPagamento(");
    expect(providerPos).toBeGreaterThan(-1);
    expect(paymentPos).toBeGreaterThan(providerPos);
    expect(src).toContain("e instanceof PagarmeConfigError");
    expect(src).toContain('code: e.code');
  });

  it("a tela bloqueia reserva quando pagamento esta indisponivel", () => {
    const src = readFileSync(
      resolve(__dirname, "../pages/RevisaoContratacao.tsx"),
      "utf8"
    );
    expect(src).toContain('disponibilidadePagamento !== "disponivel"');
    expect(src).toContain("Contratação temporariamente indisponível");
    expect(src).toContain("novas contratações estão pausadas");
  });
});
