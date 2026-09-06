import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * COMERCIAL V2 — transparência financeira pública.
 *
 * Prova que os valores aprovados chegam à TELA, em reais. Os centavos são a
 * autoridade; os percentuais aparecem declarados como aproximação.
 */

const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");

/**
 * Varre o CÓDIGO, não a explicação. Os comentários citam de propósito as
 * frases e APIs proibidas para registrar por que foram removidas; acusá-las
 * ali seria acusar a documentação da própria correção.
 */
const semComentarios = (src: string) =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

/** O mesmo valor pode aparecer legitimamente em mais de um bloco. */
const temTexto = (t: string | RegExp) => {
  const achados = screen.getAllByText(t);
  expect(achados.length).toBeGreaterThan(0);
};

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));

vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/commercialTerritory", () => ({
  obterTerritorio: () => ({ uf: "ES", cidade: "Vitória" }),
}));

import PainelPreco from "../components/commercial/PainelPreco";
import ResumoFormacao from "../components/commercial/ResumoFormacao";
import RevisaoContratacao from "../pages/RevisaoContratacao";

/** Resposta V2 da RPC pública: pool_bps ausente, razão exata no servidor. */
function blocoV2(
  niche: string,
  qtd: number,
  economic: number,
  pool: number,
  fidelized: boolean,
  pct?: string
) {
  return {
    ok: true,
    pricing_rule_version: 2,
    niche_code: niche,
    nominal_quantity: qtd,
    fidelized,
    currency: "BRL",
    economic_value_cents: economic,
    pool_bps: null,
    contractual_pool_cents: pool,
    bdflow_due_cents: economic - pool,
    display_pool_percent: pct,
    payment_method: fidelized ? "credit_card" : "pix",
  };
}

const RESPOSTA_V2 = {
  ok: true,
  pricing_rule_version: 2,
  currency: "BRL",
  niches: [
    {
      niche_code: "supermarket",
      display_name: "Supermercado",
      nominal_quantity: 24,
      founding: blocoV2("supermarket", 24, 3_558_700, 2_554_305, false, "aprox. 71,7763%"),
      fidelized: blocoV2("supermarket", 24, 3_117_600, 2_237_699, true, "aprox. 71,7763%"),
    },
    {
      niche_code: "pharmacy",
      display_name: "Farmácia",
      nominal_quantity: 12,
      founding: blocoV2("pharmacy", 12, 1_999_900, 1_335_459, false, "aprox. 66,7763%"),
      fidelized: blocoV2("pharmacy", 12, 1_558_800, 1_040_908, true, "aprox. 66,7763%"),
    },
  ],
};

beforeEach(() => {
  rpcMock.mockReset();
  rpcMock.mockResolvedValue({ data: RESPOSTA_V2, error: null });
});
afterEach(() => cleanup());

const montar = (ui: React.ReactElement, rota = "/") =>
  render(<MemoryRouter initialEntries={[rota]}>{ui}</MemoryRouter>);

describe("COMERCIAL V2 UI — composição do supermercado em reais", () => {
  it("mostra econômico, pool e parcela BDFlow com os centavos aprovados", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => temTexto("R$ 35.587,00"));
    temTexto("R$ 25.543,05");
    temTexto("R$ 10.043,95");
  });

  it("o percentual aparece como aproximação declarada, ao lado do valor", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => temTexto("R$ 25.543,05"));
    temTexto(/aprox\. 71,7763%/);
  });

  it("a formação de 12 + 12 unidades fica transparente", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => expect(screen.getByText("R$ 19.999,00")).toBeDefined());
    expect(screen.getByText("R$ 15.588,00")).toBeDefined();
    expect(screen.getByText(/12 primeiras unidades/)).toBeDefined();
    expect(screen.getByText(/12 unidades adicionais/)).toBeDefined();
  });

  it("a composição fidelizada também é exibida, não só o total", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => expect(screen.getByText("R$ 31.176,00")).toBeDefined());
    expect(screen.getByText("R$ 22.376,99")).toBeDefined();
    expect(screen.getByText("R$ 8.799,01")).toBeDefined();
  });

  it("mostra Pix na condição fundadora e cartão na fidelizada", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => expect(screen.getByText("Pix")).toBeDefined());
    expect(screen.getByText("Cartão de crédito")).toBeDefined();
  });

  it("apresenta os dois modos de liquidação", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => expect(screen.getByText(/Benefícios diretos/)).toBeDefined());
    expect(screen.getByText(/Dinheiro real/)).toBeDefined();
  });

  it("não afirma mais, sem condição, que o pool nunca é pago em dinheiro", () => {
    const fonte = semComentarios(lerFonte("src/components/commercial/PainelPreco.tsx"));
    expect(fonte).not.toContain("não é pago à BDFlow");
    expect(fonte).not.toContain("recebe apenas o valor devido");
  });
});

describe("COMERCIAL V2 UI — nicho comum", () => {
  it("mostra os centavos aprovados do nicho de 12 unidades", async () => {
    montar(<PainelPreco nicheCode="pharmacy" />);
    await waitFor(() => temTexto("R$ 19.999,00"));
    temTexto("R$ 13.354,59");
    temTexto("R$ 6.644,41");
    temTexto(/aprox\. 66,7763%/);
  });
});

describe("COMERCIAL V2 UI — falha fechada", () => {
  it("resposta malformada não inventa valor monetário", async () => {
    rpcMock.mockResolvedValue({ data: { ok: true, niches: [{ bagunca: 1 }] }, error: null });
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() =>
      expect(screen.getByText(/não estão disponíveis no momento/)).toBeDefined()
    );
    expect(screen.queryByText(/R\$/)).toBeNull();
  });

  it("resposta que viola econômico = pool + devido é rejeitada", async () => {
    const ruim = JSON.parse(JSON.stringify(RESPOSTA_V2));
    ruim.niches[0].founding.bdflow_due_cents = 1;
    rpcMock.mockResolvedValue({ data: ruim, error: null });
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() =>
      expect(screen.getByText(/não estão disponíveis no momento/)).toBeDefined()
    );
  });

  it("resposta V2 que traz pontos-base mistura modelos e é rejeitada", async () => {
    const ruim = JSON.parse(JSON.stringify(RESPOSTA_V2));
    ruim.niches[0].founding.pool_bps = 7178;
    rpcMock.mockResolvedValue({ data: ruim, error: null });
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() =>
      expect(screen.getByText(/não estão disponíveis no momento/)).toBeDefined()
    );
  });

  it("trilho incoerente com a fidelidade é rejeitado", async () => {
    const ruim = JSON.parse(JSON.stringify(RESPOSTA_V2));
    ruim.niches[0].founding.payment_method = "credit_card"; // não fidelizado
    rpcMock.mockResolvedValue({ data: ruim, error: null });
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() =>
      expect(screen.getByText(/não estão disponíveis no momento/)).toBeDefined()
    );
  });
});

describe("COMERCIAL V2 UI — resumo agregado da formação", () => {
  it("mostra os quatro números aprovados da formação", () => {
    montar(<ResumoFormacao />);
    expect(screen.getByText("R$ 135.582,00")).toBeDefined();
    expect(screen.getByText("R$ 92.316,00")).toBeDefined();
    expect(screen.getByText("R$ 43.266,00")).toBeDefined();
    expect(screen.getByText("R$ 1.099,00")).toBeDefined();
  });

  it("qualifica o valor por usuário; não é saldo automático de cadastro", () => {
    montar(<ResumoFormacao />);
    expect(screen.getByText(/cumpre todos os requisitos operacionais/)).toBeDefined();
    expect(screen.getByText(/Não é saldo em dinheiro devido pelo/)).toBeDefined();
  });

  it("deriva do domínio canônico, sem aritmética avulsa na tela", () => {
    const fonte = lerFonte("src/components/commercial/ResumoFormacao.tsx");
    expect(fonte).toContain("formationEconomicsV2()");
    // Nenhum literal monetário digitado à mão.
    expect(fonte).not.toMatch(/13_?558_?200|9_?231_?600|4_?326_?600|109_?900/);
  });

  it("está montado na página pública de oportunidades", () => {
    const fonte = lerFonte("src/pages/Oportunidades.tsx");
    expect(fonte).toContain("<ResumoFormacao />");
  });
});

describe("COMERCIAL V2 UI — rota /checkout", () => {
  const montarCheckout = (rota = "/checkout") =>
    render(
      <MemoryRouter initialEntries={[rota]}>
        <Routes>
          <Route path="/checkout" element={<RevisaoContratacao />} />
        </Routes>
      </MemoryRouter>
    );

  it("mostra a composição do nicho escolhido", () => {
    montarCheckout("/checkout?nicho=supermarket");
    temTexto("R$ 35.587,00");
    temTexto("R$ 25.543,05");
    temTexto("R$ 10.043,95");
  });

  it("o seletor de liquidação é operável e acessível por teclado", () => {
    montarCheckout();
    const diretos = screen.getByRole("radio", { name: /Benefícios diretos/ });
    const dinheiro = screen.getByRole("radio", { name: /Dinheiro real/ });
    expect((diretos as HTMLInputElement).checked).toBe(true);
    fireEvent.click(dinheiro);
    expect((dinheiro as HTMLInputElement).checked).toBe(true);
  });

  it("a seleção não é comunicada apenas por cor", () => {
    montarCheckout();
    expect(screen.getByText(/Benefícios diretos — selecionado/)).toBeDefined();
  });

  it("modo direto: cobrança é só a parcela BDFlow", () => {
    montarCheckout("/checkout?nicho=supermarket");
    expect(screen.getByText("Pool em benefícios diretos")).toBeDefined();
    const cobranca = screen.getByText("Valor financeiro da cobrança")
      .parentElement as HTMLElement;
    expect(cobranca.textContent).toContain("R$ 10.043,95");
  });

  it("modo dinheiro: cobrança vira o valor econômico completo", () => {
    montarCheckout("/checkout?nicho=supermarket");
    fireEvent.click(screen.getByRole("radio", { name: /Dinheiro real/ }));
    expect(screen.getByText("Pool em dinheiro para usuários")).toBeDefined();
    const cobranca = screen.getByText("Valor financeiro da cobrança")
      .parentElement as HTMLElement;
    expect(cobranca.textContent).toContain("R$ 35.587,00");
  });

  it("o trilho é leitura derivada, nunca um seletor Pix/cartão", () => {
    montarCheckout();
    expect(screen.getByText("Forma de pagamento")).toBeDefined();
    expect(screen.getByText("Pix")).toBeDefined();
    const radios = screen.getAllByRole("radio");
    for (const r of radios) {
      expect((r as HTMLInputElement).name).toBe("benefit_settlement_mode");
    }
    expect(screen.queryByRole("radio", { name: /Pix/ })).toBeNull();
    expect(screen.queryByRole("radio", { name: /Cartão/ })).toBeNull();
  });

  it("mudar o modo NÃO altera econômico, pool nem parcela BDFlow", () => {
    montarCheckout("/checkout?nicho=supermarket");
    fireEvent.click(screen.getByRole("radio", { name: /Dinheiro real/ }));
    temTexto("R$ 35.587,00");
    temTexto("R$ 25.543,05");
    temTexto("R$ 10.043,95");
  });

  it("valor vindo por query string é ignorado como autoridade", () => {
    montarCheckout("/checkout?nicho=supermarket&economic_value_cents=1&pool=1&preco=1");
    temTexto("R$ 35.587,00");
    expect(screen.queryByText("R$ 0,01")).toBeNull();
  });

  it("nicho desconhecido cai no padrão, sem inventar contrato", () => {
    montarCheckout("/checkout?nicho=loja_de_camisas");
    expect(screen.getByText("Supermercado")).toBeDefined();
  });

  it("não afirma pagamento, contrato nem custódia", () => {
    montarCheckout();
    expect(
      screen.getByText(/não realiza pagamento, não gera contrato/)
    ).toBeDefined();
    const fonte = semComentarios(lerFonte("src/pages/RevisaoContratacao.tsx"));
    for (const proibido of ["custodia", "custódia", "escrow", "já pago", "garantido em conta"]) {
      expect(fonte.toLowerCase(), proibido).not.toContain(proibido.toLowerCase());
    }
  });

  it("a rota não lê armazenamento do navegador", () => {
    const fonte = semComentarios(lerFonte("src/pages/RevisaoContratacao.tsx"));
    expect(fonte).not.toMatch(/localStorage|sessionStorage/);
  });

  it("a rota está registrada sob a guarda de território", () => {
    const app = lerFonte("src/App.tsx");
    const trecho = app.slice(app.indexOf('path="/checkout"'), app.indexOf('path="/checkout"') + 260);
    expect(trecho).toContain("CommercialTerritoryGuard");
    expect(trecho).toContain("<RevisaoContratacao />");
  });
});
