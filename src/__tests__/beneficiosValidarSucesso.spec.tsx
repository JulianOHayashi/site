import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor, fireEvent, act } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { renderPortal } from "./helpers/portalRender";

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
import { supabase } from "../lib/supabase";
import { useEmpresaSelecionada } from "../portal/empresaContexto";
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
  // Mesma casca do produto: o contexto de empresa envolve a rota do QR.
  return renderPortal(
    <Routes>
      <Route
        path="/beneficios/validar/:publicLookupId"
        element={<BeneficiosValidar />}
      />
    </Routes>,
    { rotas: [`/beneficios/validar/${LOCATOR}`] }
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
  // A dica de empresa é por sessão e válida entre telas; sem limpar, um teste
  // herdaria a escolha do anterior e "nenhuma empresa escolhida" nunca ocorreria.
  sessionStorage.clear();
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
      screen.getByText(/confirmar ou recusar no aplicativo SmallFlags/i)
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
    // Nada foi enviado e NENHUMA AUTORIZAÇÃO DE VALIDAÇÃO foi consultada.
    // O contexto de empresa, que é da casca do Portal e não desta tela, pode
    // ter carregado — ele não lê o segredo nem autoriza validação. O que não
    // pode acontecer é pedir as unidades autorizadas para um QR inválido.
    expect(enviarMock).not.toHaveBeenCalled();
    const rpcsChamadas = rpcMock.mock.calls.map((c) => c[0]);
    expect(rpcsChamadas).not.toContain("get_my_validator_context");
  });

  it("recusa do servidor NAO vira sucesso e NAO libera o QR", async () => {
    capturarSegredoReal();
    // O servidor respondeu recusando. Do lado do cliente não há como provar
    // que nada foi criado no App, então a fase é indeterminada e o QR fica
    // travado — era aqui que a versão anterior destravava indevidamente.
    enviarMock.mockResolvedValue({
      tipo: "erro",
      codigo: "request_denied",
      fase: "indeterminado",
    });

    renderizar();

    const checkbox = await screen.findByRole("checkbox");
    fireEvent.click(checkbox);
    fireEvent.click(screen.getByRole("button", { name: /Enviar solicitação/i }));

    await screen.findByText(/o envio deste qr começou e o resultado não pôde ser confirmado/i);
    expect(screen.queryByText("Solicitação enviada ao aplicativo.")).toBeNull();
    // Sem formulário: não há segundo envio possível com este código.
    expect(screen.queryByRole("button", { name: /Enviar solicitação/i })).toBeNull();
    expect(lerSegredoCapturado()).toBeNull();
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));
  });
});

describe("9. QR com várias empresas autorizadas e nenhuma escolhida", () => {
  const VINCULO_B = { ...VINCULO, company_id: "c2", trade_name: "Rede Dois", member_id: "m2" };

  function duasEmpresas() {
    rpcMock.mockImplementation(async (fn: string, args?: Record<string, unknown>) => {
      if (fn === "get_my_partner_context") {
        return {
          data: { ok: true, authorized: true, memberships: [VINCULO, VINCULO_B] },
          error: null,
        };
      }
      if (fn === "get_my_validator_context") {
        return { data: { ...CONTEXTO, _company: args?.p_company_id }, error: null };
      }
      return { data: null, error: { message: "rpc inesperada" } };
    });
  }

  it("exige escolher a empresa ANTES de pedir unidades e mantém o segredo intacto", async () => {
    duasEmpresas();
    capturarSegredoReal();
    expect(lerSegredoCapturado()).not.toBeNull();

    renderizar();
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });

    // Nenhuma autorização de validação foi consultada, e nada foi enviado.
    expect(rpcMock.mock.calls.map((c) => c[0])).not.toContain("get_my_validator_context");
    expect(enviarMock).not.toHaveBeenCalled();
    // A etapa de escolha não consumiu nem descartou o segredo capturado.
    expect(lerSegredoCapturado()).not.toBeNull();
    // E o segredo não está em nenhum ponto visível da página.
    expect(document.body.textContent).not.toContain(SEGREDO);
    expect(window.location.href).not.toContain(SEGREDO);
  });

  it("depois de escolher, pede as unidades da empresa escolhida e só dela", async () => {
    duasEmpresas();
    capturarSegredoReal();
    renderizar();

    fireEvent.click(await screen.findByRole("button", { name: /Rede Dois/ }));
    await waitFor(() =>
      expect(
        rpcMock.mock.calls.filter((c) => c[0] === "get_my_validator_context")
      ).toHaveLength(1)
    );
    const chamada = rpcMock.mock.calls.find((c) => c[0] === "get_my_validator_context")!;
    expect(JSON.stringify(chamada[1])).toContain("c2");
    expect(JSON.stringify(chamada[1])).not.toContain("c1");
    // O segredo continua em memória até o envio/saída da tela.
    expect(lerSegredoCapturado()).not.toBeNull();
  });

  it("trocar de empresa depois de escolher descarta a unidade, sem perder o segredo", async () => {
    duasEmpresas();
    capturarSegredoReal();
    renderizar();

    fireEvent.click(await screen.findByRole("button", { name: /Rede Um/ }));
    await screen.findByLabelText(/unidade/i);
    fireEvent.click(screen.getByRole("button", { name: /trocar de empresa/i }));

    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });
    expect(screen.queryByLabelText(/unidade/i)).toBeNull();
    expect(enviarMock).not.toHaveBeenCalled();
    expect(lerSegredoCapturado()).not.toBeNull();
  });
});

/* ===================================================================== */
/* FOLLOW-UP DA AUDITORIA — rota do QR                                    */
/* ===================================================================== */
describe("QR — contexto de empresa: respostas tardias e envio em andamento", () => {
  const VINCULO_B = { ...VINCULO, company_id: "c2", trade_name: "Rede Dois", member_id: "m2" };
  const tick = () => act(async () => { await new Promise((r) => setTimeout(r, 30)); });

  function adiado<T>() {
    let resolver!: (v: T) => void;
    const promessa = new Promise<T>((r) => {
      resolver = r;
    });
    return { promessa, resolver };
  }

  /** Dispara o evento de autenticação como o Supabase faria (ex.: SIGNED_OUT). */
  async function emitirAuth(sessao: unknown) {
    const cb = (supabase!.auth.onAuthStateChange as unknown as ReturnType<typeof vi.fn>).mock
      .calls.at(-1)![0] as (e: string, s: unknown) => void;
    await act(async () => cb("SIGNED_OUT", sessao));
  }

  function espiarConsole() {
    const alvos = ["log", "info", "warn", "error", "debug"] as const;
    const chamadas: string[] = [];
    const espioes = alvos.map((n) =>
      vi.spyOn(console, n).mockImplementation((...a: unknown[]) => {
        chamadas.push(a.map((x) => String(x)).join(" "));
      })
    );
    return { chamadas, restaurar: () => espioes.forEach((e) => e.mockRestore()) };
  }

  it("A responde DURANTE a escolha: nem unidades, nem formulário, e o segredo segue em memória", async () => {
    const lentoC1 = adiado<unknown>();
    rpcMock.mockImplementation(async (fn: string, args?: Record<string, unknown>) => {
      if (fn === "get_my_partner_context") {
        return { data: { ok: true, authorized: true, memberships: [VINCULO, VINCULO_B] }, error: null };
      }
      if (fn === "get_my_validator_context") {
        return args?.p_company_id === "c1"
          ? lentoC1.promessa
          : { data: { ...CONTEXTO, units: [{ unit_id: "u-2", name: "Loja Dois", branch_bridge_id: "b-2" }] }, error: null };
      }
      return { data: null, error: { message: "rpc inesperada" } };
    });
    capturarSegredoReal();
    renderizar();

    fireEvent.click(await screen.findByRole("button", { name: /Rede Um/ }));
    await waitFor(() =>
      expect(rpcMock.mock.calls.some((c) => c[0] === "get_my_validator_context")).toBe(true)
    );
    fireEvent.click(await screen.findByRole("button", { name: /trocar de empresa/i }));
    await screen.findByRole("heading", { name: /escolha a empresa desta sessão/i });

    await act(async () => {
      lentoC1.resolver({ data: CONTEXTO, error: null });
    });
    await tick();

    expect(screen.queryByLabelText(/unidade/i)).toBeNull();
    expect(screen.queryByText("Loja Centro")).toBeNull();
    expect(screen.queryByRole("button", { name: /enviar solicitação/i })).toBeNull();
    expect(enviarMock).not.toHaveBeenCalled();
    expect(lerSegredoCapturado()).not.toBeNull();
  });

  it("a troca de empresa fica bloqueada enquanto o envio do QR não termina", async () => {
    const pend = adiado<unknown>();
    rpcMock.mockImplementation(async (fn: string) =>
      fn === "get_my_partner_context"
        ? { data: { ok: true, authorized: true, memberships: [VINCULO, VINCULO_B] }, error: null }
        : fn === "get_my_validator_context"
          ? { data: CONTEXTO, error: null }
          : { data: null, error: { message: "rpc inesperada" } }
    );
    enviarMock.mockReturnValue(pend.promessa);
    capturarSegredoReal();
    renderizar();

    fireEvent.click(await screen.findByRole("button", { name: /Rede Um/ }));
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));

    const trocar = screen.getByRole("button", { name: /trocar de empresa/i }) as HTMLButtonElement;
    expect(trocar.disabled).toBe(true);
    expect(screen.getByText(/há uma operação em andamento/i)).toBeDefined();

    await act(async () => {
      pend.resolver({ tipo: "ok", correlationId: CORRELACAO, appStatus: "awaiting_user_confirmation" });
    });
    await waitFor(() => expect(document.body.textContent).toContain(CORRELACAO));
  });

  it("envio que termina depois de mudança INVOLUNTÁRIA: sem sucesso, sem correlação, segredo descartado e texto honesto", async () => {
    const pend = adiado<unknown>();
    enviarMock.mockReturnValue(pend.promessa);
    capturarSegredoReal();
    const con = espiarConsole();
    try {
      renderizar();
      fireEvent.click(await screen.findByRole("checkbox"));
      fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
      await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));

      await emitirAuth(null); // perda de sessão no meio do envio
      await act(async () => {
        pend.resolver({ tipo: "ok", correlationId: CORRELACAO, appStatus: "awaiting_user_confirmation" });
      });
      await tick();

      // Nada é apresentado como resultado desta tela…
      expect(document.body.textContent).not.toContain(CORRELACAO);
      expect(screen.queryByText(/solicitação (criada|enviada)/i)).toBeNull();
      // …o segredo, que já foi entregue ao envio, não fica em memória…
      expect(lerSegredoCapturado()).toBeNull();
      // …e o texto é verdadeiro: um envio FOI feito, então não se diz o contrário.
      expect(screen.getByText(/este qr já foi enviado nesta sessão/i)).toBeDefined();
      expect(document.body.textContent).not.toMatch(/nenhuma validação foi encaminhada/i);
      expect(screen.getByText(/resposta recebida depois da mudança de empresa/i)).toBeDefined();
      expect(document.body.textContent).toMatch(/(não foi|nada foi)\s+cancelad[ao]/i);

      // Sem segredo no corpo, na URL nem nos logs.
      expect(document.body.textContent).not.toContain(SEGREDO);
      expect(window.location.href).not.toContain(SEGREDO);
      expect(con.chamadas.join("\n")).not.toContain(SEGREDO);
    } finally {
      con.restaurar();
    }
  });
});

describe("QR inválido ou incompleto: nada é pedido, enviado ou vazado", () => {
  const RPCS_PERMITIDAS = ["get_my_partner_context"]; // contexto da casca; não lê segredo

  function espiarConsole() {
    const alvos = ["log", "info", "warn", "error", "debug"] as const;
    const chamadas: string[] = [];
    const espioes = alvos.map((n) =>
      vi.spyOn(console, n).mockImplementation((...a: unknown[]) => {
        chamadas.push(a.map((x) => String(x)).join(" "));
      })
    );
    return { chamadas, restaurar: () => espioes.forEach((e) => e.mockRestore()) };
  }

  async function verificarInvalido(marcador: string) {
    const fetchEspiao = vi.fn();
    vi.stubGlobal("fetch", fetchEspiao);
    const con = espiarConsole();
    try {
      renderizar();
      await screen.findByText("Código de benefício inválido ou incompleto.");
      expect(screen.getByText(/nenhuma validação foi encaminhada/i)).toBeTruthy();

      // Nenhuma autorização de validação, nenhum open/request, nenhum status.
      const chamadas = rpcMock.mock.calls.map((c) => c[0] as string);
      expect(chamadas).not.toContain("get_my_validator_context");
      expect(chamadas).not.toContain("prepare_benefit_validation");
      expect(chamadas.every((n) => RPCS_PERMITIDAS.includes(n))).toBe(true);
      expect(enviarMock).not.toHaveBeenCalled();
      expect(statusMock).not.toHaveBeenCalled();

      // O conteúdo recebido não aparece em lugar nenhum.
      expect(document.body.textContent).not.toContain(marcador);
      expect(window.location.href).not.toContain(marcador);
      expect(JSON.stringify(rpcMock.mock.calls)).not.toContain(marcador);
      expect(JSON.stringify(fetchEspiao.mock.calls)).not.toContain(marcador);
      expect(con.chamadas.join("\n")).not.toContain(marcador);
      expect(lerSegredoCapturado()).toBeNull();
    } finally {
      con.restaurar();
      vi.unstubAllGlobals();
    }
  }

  it("sem fragmento algum", async () => {
    expect(lerSegredoCapturado()).toBeNull();
    await verificarInvalido("SEM-FRAGMENTO");
  });

  it("com fragmento malformado: é apagado da URL, descartado e nunca usado", async () => {
    const MARCADOR = "fragmento-curto-demais-XYZ";
    const replaceState = vi.fn();
    const r = capturarFragmento({
      location: { pathname: `/beneficios/validar/${LOCATOR}`, search: "", hash: `#${MARCADOR}` },
      history: { replaceState },
    } as unknown as Window);

    expect(r.tipo).toBe("invalido");
    // O fragmento foi removido da barra de endereço, sem sobrar nada além do caminho.
    expect(replaceState).toHaveBeenCalledWith(null, "", `/beneficios/validar/${LOCATOR}`);
    await verificarInvalido(MARCADOR);
  });
});

/* ===================================================================== */
/* QR em voo não pode ser reenviado sob outra empresa                     */
/* ===================================================================== */
describe("QR — um envio iniciado trava o fragmento em qualquer transição", () => {
  /**
   * Controles auxiliares: revalidam o contexto e escolhem uma empresa pelo
   * próprio provider — é assim que "escolher B" acontece mesmo quando a tela
   * do QR já não oferece a lista.
   */
  function ControlesContexto() {
    const ctx = useEmpresaSelecionada();
    return (
      <>
        <button onClick={ctx.recarregar}>revalidar-contexto</button>
        <button onClick={() => ctx.selecionar("c2")}>escolher-B</button>
      </>
    );
  }

  const VINCULO_B2 = { ...VINCULO, company_id: "c2", trade_name: "Rede Dois", member_id: "m2" };
  const tick = () => act(async () => { await new Promise((r) => setTimeout(r, 30)); });

  function adiado<T>() {
    let resolver!: (v: T) => void;
    const promessa = new Promise<T>((r) => { resolver = r; });
    return { promessa, resolver };
  }

  function renderizarComRevalidacao() {
    return renderPortal(
      <>
        <Routes>
          <Route
            path="/beneficios/validar/:publicLookupId"
            element={<BeneficiosValidar />}
          />
        </Routes>
        <ControlesContexto />
      </>,
      { rotas: [`/beneficios/validar/${LOCATOR}`] }
    );
  }

  it("A em voo -> A invalidada -> escolher B -> B NÃO consegue reenviar o mesmo QR", async () => {
    const pend = adiado<unknown>();
    enviarMock.mockReturnValue(pend.promessa);

    // Começa com as duas empresas; depois A desaparece.
    let soB = false;
    rpcMock.mockImplementation(async (fn: string) => {
      if (fn === "get_my_partner_context") {
        return {
          data: {
            ok: true,
            authorized: true,
            memberships: soB ? [VINCULO_B2] : [VINCULO, VINCULO_B2],
          },
          error: null,
        };
      }
      if (fn === "get_my_validator_context") return { data: CONTEXTO, error: null };
      return { data: null, error: { message: "rpc inesperada" } };
    });

    capturarSegredoReal();
    renderizarComRevalidacao();

    // Envio sob a empresa A (Rede Um).
    fireEvent.click(await screen.findByRole("button", { name: /Rede Um/ }));
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));

    // O fragmento já está travado no instante do despacho, não na resposta.
    expect(lerSegredoCapturado()).toBeNull();

    // A some do contexto enquanto a primeira requisição ainda não respondeu.
    soB = true;
    fireEvent.click(screen.getByText("revalidar-contexto"));
    await tick();

    // A tela do QR nem chega a oferecer a lista de empresas: a trava já
    // responde antes disso.
    expect(screen.getByText(/este qr já foi enviado nesta sessão/i)).toBeDefined();

    // Ainda assim, escolhendo B pelo contexto — o caminho que um outro ponto
    // do Portal usaria — o QR continua sem formulário e sem reenvio.
    fireEvent.click(screen.getByText("escolher-B"));
    await tick();
    // Mesmo que B fique elegível, não há formulário para reenviar este QR…
    expect(screen.queryByRole("button", { name: /enviar solicitação/i })).toBeNull();
    expect(screen.getByText(/este qr já foi enviado nesta sessão/i)).toBeDefined();
    // …e a mensagem não promete cancelamento nem nega o despacho.
    expect(document.body.textContent).toMatch(/pode ter sido processada/i);
    expect(document.body.textContent).not.toMatch(/nenhuma validação foi encaminhada/i);

    // A primeira requisição responde tarde: segue valendo UMA só chamada.
    await act(async () => {
      pend.resolver({ tipo: "ok", correlationId: CORRELACAO, appStatus: "awaiting_user_confirmation" });
    });
    await tick();
    expect(enviarMock).toHaveBeenCalledTimes(1);
    // Nenhum resultado é atribuído à empresa B.
    expect(document.body.textContent).not.toContain(CORRELACAO);
    expect(lerSegredoCapturado()).toBeNull();
    expect(document.body.textContent).not.toContain(SEGREDO);
  });

  /**
   * O ponto central da correção: `network_error` vem de um fetch REJEITADO.
   * O POST pode ter chegado e só a resposta ter se perdido, criando uma
   * solicitação no App. Um segundo envio geraria outra correlação. Por isso
   * uma falha indeterminada NÃO libera o QR, nem no mesmo contexto.
   */
  const soUmContexto = () =>
    rpcMock.mockImplementation(async (fn: string) =>
      fn === "get_my_partner_context"
        ? { data: { ok: true, authorized: true, memberships: [VINCULO] }, error: null }
        : fn === "get_my_validator_context"
          ? { data: CONTEXTO, error: null }
          : { data: null, error: { message: "rpc inesperada" } }
    );

  async function enviarUmaVez() {
    capturarSegredoReal();
    renderizar();
    fireEvent.click(await screen.findByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(1));
  }

  for (const [nome, falha] of [
    // fetch rejeitado: nenhuma resposta chegou.
    ["fetch rejeitado (network_error)", { tipo: "erro", codigo: "network_error", fase: "indeterminado" }],
    // Respostas LEGÍVEIS do servidor: aqui nada se perdeu, o servidor
    // respondeu — por isso o texto não pode falar em resposta perdida.
    ["403 legível do servidor", { tipo: "erro", codigo: "forbidden", fase: "indeterminado" }],
    ["409 legível do servidor", { tipo: "erro", codigo: "conflict", fase: "indeterminado" }],
    ["500 legível do servidor", { tipo: "erro", codigo: "internal_error", fase: "indeterminado" }],
    ["corpo ilegível", { tipo: "erro", codigo: "unexpected_error", fase: "indeterminado" }],
  ] as const) {
    it(`falha indeterminada — ${nome} — mantém o QR travado no MESMO contexto`, async () => {
      soUmContexto();
      enviarMock.mockResolvedValue(falha);
      await enviarUmaVez();

      // Sem formulário: um segundo envio é impossível.
      expect(screen.queryByRole("button", { name: /enviar solicitação/i })).toBeNull();
      expect(lerSegredoCapturado()).toBeNull();
      expect(enviarMock).toHaveBeenCalledTimes(1);

      // A mensagem diz que o desfecho é desconhecido, não que nada ocorreu.
      expect(
        await screen.findByText(/a tentativa de envio começou/i)
      ).toBeDefined();
      const texto = document.body.textContent ?? "";
      // Linguagem NEUTRA: não se sabe se houve criação ou processamento.
      expect(texto).toMatch(/não tem como determinar se uma solicitação chegou a ser criada ou\s+processada/i);
      expect(texto).toMatch(/nada foi cancelado/i);
      expect(texto).not.toMatch(/nenhuma validação foi encaminhada/i);
      // Não se afirma que o benefício continua disponível.
      expect(texto).not.toMatch(/benefício (não foi|segue|continua) (consumido|disponível)/i);
      // E não se afirma que a RESPOSTA se perdeu: num 403/409/500 o servidor
      // respondeu, e dizer o contrário seria falso.
      expect(texto).not.toMatch(/resposta se perdeu|resultado não chegou/i);
      expect(texto).not.toContain(SEGREDO);
    });
  }

  it("falha PROVADAMENTE anterior ao despacho libera o QR no mesmo contexto", async () => {
    soUmContexto();
    // Retorno do serviço antes de qualquer fetch: nenhuma requisição saiu.
    enviarMock.mockResolvedValueOnce({
      tipo: "erro",
      codigo: "not_authenticated",
      fase: "pre_despacho",
    });
    await enviarUmaVez();

    expect(await screen.findByRole("button", { name: /enviar solicitação/i })).toBeDefined();
    expect(lerSegredoCapturado()).not.toBeNull();

    enviarMock.mockResolvedValueOnce({
      tipo: "ok", correlationId: CORRELACAO, appStatus: "awaiting_user_confirmation",
    });
    fireEvent.click(screen.getByRole("button", { name: /enviar solicitação/i }));
    await waitFor(() => expect(enviarMock).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(document.body.textContent).toContain(CORRELACAO));
  });
});
