import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, fireEvent } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";

/**
 * Gate E — precedência de render do sucesso sobre a guarda de QR pré-envio.
 *
 * O DEFEITO QUE ESTE TESTE TRAVA
 * Descartar o segredo cru logo após o sucesso é obrigatório e continua
 * acontecendo. Mas `segredoPresente` é recalculado a cada render; no render
 * seguinte ao descarte ele vira falso, e a guarda de QR inválido — que é uma
 * verificação PRÉ-envio — retornava antes da UI de sucesso.
 *
 * O resultado era a pior mensagem possível: "Código de benefício inválido ou
 * incompleto. Nenhuma validação foi encaminhada." exibida logo depois de a
 * solicitação ter sido criada no App. O balconista repetiria a operação.
 *
 * As asserções abaixo olham as duas direções: o sucesso tem de sobreviver ao
 * descarte, e a guarda tem de continuar valendo quando nunca houve sucesso.
 */

const rpcMock = vi.fn();

vi.mock("../lib/supabase", () => {
  const auth = {
    getSession: vi.fn(async () => ({
      data: { session: { access_token: "t", user: { id: "u1" } } },
    })),
    onAuthStateChange: vi.fn(() => ({
      data: { subscription: { unsubscribe: vi.fn() } },
    })),
    signOut: vi.fn(async () => ({})),
  };
  return {
    supabase: { auth, rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
    supabaseConfigurado: true,
  };
});

const enviarMock = vi.fn();
const statusMock = vi.fn();
vi.mock("../services/benefitUsageService", () => ({
  enviarUsoDeBeneficio: (...a: unknown[]) => enviarMock(...(a as [])),
  obterStatusUsoDeBeneficio: (...a: unknown[]) => statusMock(...(a as [])),
}));

import BeneficiosValidar from "../pages/beneficios/BeneficiosValidar";
import {
  capturarFragmento,
  descartarSegredoCapturado,
  lerSegredoCapturado,
} from "../lib/benefitTokenFragment";

const LOCATOR = "11111111-2222-4333-8444-555555555555";
const SEGREDO = "a".repeat(64);
const CORRELACAO = "99999999-0000-4000-8000-000000000000";

const VINCULO = {
  company_id: "c1",
  trade_name: "Rede Um",
  company_status: "active",
  member_id: "m1",
  role: "partner_owner",
  member_status: "active",
};

const CONTEXTO = {
  ok: true,
  eligible: true,
  role: "partner_owner",
  units: [{ unit_id: "u-1", name: "Loja Centro", branch_bridge_id: "b-1" }],
};

/** Captura o segredo pelo caminho real do produto, não por atalho. */
function capturarSegredoReal() {
  capturarFragmento({
    location: {
      pathname: `/beneficios/validar/${LOCATOR}`,
      search: "",
      hash: `#${SEGREDO}`,
    },
    history: { replaceState: vi.fn() },
  } as unknown as Window);
}

function renderizar() {
  return render(
    <MemoryRouter initialEntries={[`/beneficios/validar/${LOCATOR}`]}>
      <Routes>
        <Route
          path="/beneficios/validar/:publicLookupId"
          element={<BeneficiosValidar />}
        />
      </Routes>
    </MemoryRouter>
  );
}

beforeEach(() => {
  rpcMock.mockReset();
  enviarMock.mockReset();
  statusMock.mockReset();
  statusMock.mockResolvedValue({
    tipo: "ok",
    status: "awaiting_user_confirmation",
  });
  descartarSegredoCapturado();
  rpcMock.mockImplementation(async (fn: string) => {
    if (fn === "get_my_partner_context") {
      return {
        data: { ok: true, authorized: true, memberships: [VINCULO] },
        error: null,
      };
    }
    if (fn === "get_my_validator_context") {
      return { data: CONTEXTO, error: null };
    }
    return { data: null, error: { message: "rpc inesperada" } };
  });
});

afterEach(() => {
  cleanup();
  descartarSegredoCapturado();
});

describe("BeneficiosValidar — sucesso sobrevive ao descarte do segredo", () => {
  it("envia uma vez, descarta o segredo e mostra o sucesso com a correlação", async () => {
    capturarSegredoReal();
    expect(lerSegredoCapturado()).toBe(SEGREDO);
    enviarMock.mockResolvedValue({
      tipo: "ok",
      correlationId: CORRELACAO,
      appStatus: "awaiting_user_confirmation",
    });

    renderizar();

    const checkbox = await screen.findByRole("checkbox");
    fireEvent.click(checkbox);
    const botao = screen.getByRole("button", { name: /Enviar solicitação/i });
    fireEvent.click(botao);

    // UI de sucesso presente...
    await screen.findByText("Solicitação enviada ao aplicativo.");
    expect(
      screen.getByText(/confirmar ou recusar no aplicativo BDFlow/i)
    ).toBeTruthy();

    // ...o segredo foi descartado...
    expect(lerSegredoCapturado()).toBeNull();

    // ...e mesmo assim a tela NAO caiu na guarda de QR inválido.
    expect(screen.queryByText("Código de benefício inválido ou incompleto.")).toBeNull();
    expect(screen.queryByText(/Nenhuma validação foi encaminhada/i)).toBeNull();

    // A correlação devolvida pelo backend continua visível.
    expect(screen.getByText(CORRELACAO)).toBeTruthy();

    // Exatamente UM envio: o patch nao reintroduziu reenvio.
    expect(enviarMock).toHaveBeenCalledTimes(1);
    expect(enviarMock.mock.calls[0][0]).toMatchObject({
      publicLookupId: LOCATOR,
      rawSecret: SEGREDO,
      unitId: "u-1",
      physicalPhotoIdChecked: true,
    });

    // E o formulario sumiu, entao nem ha botao para clicar de novo.
    expect(screen.queryByRole("button", { name: /Enviar solicitação/i })).toBeNull();
  });

  it("atualiza a tela quando o App confirma o uso", async () => {
    capturarSegredoReal();
    enviarMock.mockResolvedValue({
      tipo: "ok",
      correlationId: CORRELACAO,
      appStatus: "awaiting_user_confirmation",
    });
    statusMock.mockResolvedValue({ tipo: "ok", status: "confirmed" });

    renderizar();

    const checkbox = await screen.findByRole("checkbox");
    fireEvent.click(checkbox);
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));

    await screen.findByText("Uso confirmado com sucesso.");
    expect(screen.getByText(/benefício foi consumido/i)).toBeTruthy();
    expect(statusMock).toHaveBeenCalledWith({
      correlationId: CORRELACAO,
      unitId: "u-1",
    });
  });

  it("sem segredo e SEM sucesso anterior, a guarda de QR inválido continua valendo", async () => {
    // Nenhuma captura: chega-se a rota sem fragmento.
    expect(lerSegredoCapturado()).toBeNull();

    renderizar();

    await screen.findByText("Código de benefício inválido ou incompleto.");
    expect(screen.getByText(/Nenhuma validação foi encaminhada/i)).toBeTruthy();
    // Nada foi enviado e nenhuma autorização foi consultada.
    expect(enviarMock).not.toHaveBeenCalled();
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it("falha do backend NAO vira sucesso nem esconde o formulario", async () => {
    capturarSegredoReal();
    enviarMock.mockResolvedValue({ tipo: "erro", codigo: "request_denied" });

    renderizar();

    const checkbox = await screen.findByRole("checkbox");
    fireEvent.click(checkbox);
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));

    await screen.findByText(/O aplicativo recusou este benefício/i);
    expect(screen.queryByText("Solicitação enviada ao aplicativo.")).toBeNull();
    // O segredo NAO foi descartado numa falha, entao a guarda tambem nao
    // dispara: a tela continua utilizavel.
    expect(lerSegredoCapturado()).toBe(SEGREDO);
    expect(screen.queryByText("Código de benefício inválido ou incompleto.")).toBeNull();
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));
  });
});
