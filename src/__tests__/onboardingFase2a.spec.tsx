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

describe("/parceiros/cadastro", () => {
  it("bloqueia envio com dados inválidos e não chama o backend", async () => {
    render(
      <MemoryRouter initialEntries={["/parceiros/cadastro"]}>
        <ParceirosCadastro />
      </MemoryRouter>
    );
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(screen.getByText(/informe um cnpj válido/i)).toBeDefined());
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it("exige o aceite antes de enviar", async () => {
    render(
      <MemoryRouter initialEntries={["/parceiros/cadastro"]}>
        <ParceirosCadastro />
      </MemoryRouter>
    );
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() =>
      expect(screen.getByText(/necessário aceitar os termos/i)).toBeDefined()
    );
  });

  it("envia pela RPC nova e nunca pela RPC legada", async () => {
    render(
      <MemoryRouter initialEntries={["/parceiros/cadastro"]}>
        <ParceirosCadastro />
      </MemoryRouter>
    );
    fireEvent.change(screen.getByLabelText(/cnpj/i), { target: { value: "12.345.678/0001-95" } });
    fireEvent.change(screen.getByLabelText(/razão social/i), { target: { value: "Supermercado Teste LTDA" } });
    fireEvent.change(screen.getByLabelText(/e-mail de contato/i), { target: { value: "Contato@Teste.com.BR" } });
    fireEvent.change(screen.getByLabelText(/^cidade/i), { target: { value: "Vila Velha" } });
    fireEvent.change(screen.getByLabelText(/nome completo/i), { target: { value: "Maria Souza" } });
    fireEvent.change(screen.getByLabelText(/^cpf/i), { target: { value: "529.982.247-25" } });
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));

    await waitFor(() => expect(rpcMock).toHaveBeenCalledTimes(1));
    const [nome, args] = rpcMock.mock.calls[0] as unknown as [string, { p_payload: Record<string, string> }];
    expect(nome).toBe("create_partner_application");
    expect(nome).not.toBe("create_my_partner_owner_registration");
    // Normalização já sai limpa do cliente; o backend normaliza de novo.
    expect(args.p_payload.cnpj).toBe("12345678000195");
    expect(args.p_payload.contact_email).toBe("contato@teste.com.br");
    expect(args.p_payload.representative_cpf).toBe("52998224725");

    await waitFor(() => expect(screen.getByText(/confirme seu e-mail/i)).toBeDefined());
  });
});
