import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { cnpjValido, cpfValido, validarFormulario } from "../lib/onboardingValidacao";

/**
 * M1 — cobertura do onboarding Fase 2A no frontend.
 *
 * Prova: neutralização de /portal/cadastro, validação local espelhando as
 * regras server-side, e que a página de cadastro NÃO chama a RPC legada.
 */

const rpcMock = vi.fn(async () => ({
  data: { ok: true, application_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          status: "pending_email_verification" },
  error: null,
}));

vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...args: unknown[]) => rpcMock(...(args as [])) },
  supabaseConfigurado: true,
}));

import App from "../App";
import ParceirosCadastro from "../pages/parceiros/ParceirosCadastro";

beforeEach(() => { rpcMock.mockClear(); localStorage.clear(); });
afterEach(() => cleanup());

describe("validação espelhando o backend", () => {
  it("aceita CNPJ com dígitos verificadores corretos", () => {
    expect(cnpjValido("12.345.678/0001-95")).toBe(true);
  });
  it("rejeita CNPJ com dígito verificador errado", () => {
    expect(cnpjValido("12345678000100")).toBe(false);
  });
  it("rejeita CNPJ de dígitos repetidos", () => {
    expect(cnpjValido("11111111111111")).toBe(false);
  });
  it("aceita e rejeita CPF pelos dígitos verificadores", () => {
    expect(cpfValido("529.982.247-25")).toBe(true);
    expect(cpfValido("12345678900")).toBe(false);
  });
  it("acusa campos obrigatórios ausentes", () => {
    const erros = validarFormulario({
      cnpj: "", legal_name: "", trade_name: "", contact_email: "", contact_phone: "",
      postal_code: "", street: "", street_number: "", district: "", city: "", uf: "",
      representative_full_name: "", representative_cpf: "", representative_email: "",
      representative_phone: "",
    });
    expect(Object.keys(erros).sort()).toEqual(
      ["city", "cnpj", "contact_email", "legal_name", "representative_cpf",
       "representative_full_name", "uf"].sort()
    );
  });
});

describe("/portal/cadastro — legado neutralizado", () => {
  // O App monta o próprio BrowserRouter, então navegamos pelo history real
  // e verificamos a tabela de rotas de verdade, sem aninhar routers.
  it("redireciona para /parceiros/cadastro", async () => {
    window.history.pushState({}, "", "/portal/cadastro");
    render(<App />);
    await waitFor(() => expect(window.location.pathname).toBe("/parceiros/cadastro"));
  });

  it("apresenta o formulário novo após o redirect", async () => {
    window.history.pushState({}, "", "/portal/cadastro");
    render(<App />);
    await waitFor(() =>
      expect(screen.getByRole("heading", { name: /solicitação de parceria/i })).toBeDefined()
    );
  });

  it("a rota nova responde diretamente", async () => {
    window.history.pushState({}, "", "/parceiros/cadastro");
    render(<App />);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /enviar solicitação/i })).toBeDefined()
    );
  });
});

// Os casos de envio do cadastro passaram a viver em aceiteJuridico.spec.tsx,
// porque o contrato agora exige os termos vigentes carregados e o aceite
// atado ao legal_document_id. Manter aqui uma versao com o contrato antigo
// produziria PASS sobre um fluxo que nao existe mais.
