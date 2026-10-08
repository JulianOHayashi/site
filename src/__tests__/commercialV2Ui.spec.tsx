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
    direct_benefit_deliverable_cents: pool,
    funding_direct_benefits_cents: economic - pool,
    funding_cash_cents: economic,
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

function blocoV14(
  niche: string,
  qtd: number,
  fidelized: boolean,
  economic: number,
  mei: number,
  qa: number,
  principal: number,
  totalSmallFlags: number
) {
  return {
    ok: true,
    pricing_rule_version: 3,
    pool_precision_model: "explicit_schedule",
    niche_code: niche,
    niche_category: niche === "supermarket" ? "supermarket" : "common",
    nominal_quantity: qtd,
    fidelized,
    currency: "BRL",
    pool_bps: null,
    display_pool_percent: null,
    display_bdflow_percent: null,
    payment_method: fidelized ? "credit_card" : "pix",
    contract_economics_version: "SF-v1.4",
    economic_value_cents: economic,
    contractual_pool_cents: mei + qa,
    bdflow_due_cents: principal,
    mei_consideration_cents: mei,
    smallflags_qa_cents: qa,
    smallflags_main_fee_cents: principal,
    smallflags_total_remuneration_cents: totalSmallFlags,
    ordinary_participation_value_cents: 14_199,
    direct_benefit_deliverable_cents: mei,
    funding_direct_benefits_cents: totalSmallFlags,
    funding_cash_cents: economic,
  };
}

const RESPOSTA_V14 = {
  ok: true,
  pricing_rule_version: 3,
  currency: "BRL",
  niches: [
    {
      niche_code: "supermarket",
      display_name: "Supermercado",
      nominal_quantity: 24,
      founding: blocoV14("supermarket", 24, false, 2_999_900, 2_385_432, 12_168, 602_300, 614_468),
      fidelized: blocoV14("supermarket", 24, true, 2_817_600, 2_385_432, 12_168, 420_000, 432_168),
    },
    {
      niche_code: "pharmacy",
      display_name: "Farmácia",
      nominal_quantity: 12,
      founding: blocoV14("pharmacy", 12, false, 1_999_900, 1_192_716, 6_084, 801_100, 807_184),
      fidelized: blocoV14("pharmacy", 12, true, 1_618_800, 1_192_716, 6_084, 420_000, 426_084),
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

  it("leva a oportunidade ao checkout preservando o nicho", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    const link = await screen.findByRole("link", { name: /Solicitar contratação/i });
    expect(link.getAttribute("href")).toBe("/checkout?nicho=supermarket");
  });

  it("o detalhe não afirma mais que reserva e pagamento on-line não existem", () => {
    const fonte = semComentarios(lerFonte("src/pages/OportunidadeDetalhe.tsx"));
    expect(fonte).not.toContain("sem reserva ou pagamento");
    expect(fonte).toContain("avançar ao checkout");
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


describe("SF-v1.4 UI — autoridade server-side sem fórmula V2", () => {
  beforeEach(() => {
    rpcMock.mockResolvedValue({ data: RESPOSTA_V14, error: null });
  });

  it("supermercado mostra 29.999 fundador e 28.176 fidelizado, nunca 35.587", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => temTexto("R$ 29.999,00"));
    temTexto("R$ 28.176,00");
    expect(screen.queryByText("R$ 35.587,00")).toBeNull();
    expect(screen.queryByText(/12 primeiras unidades/)).toBeNull();
    expect(screen.queryByText(/12 unidades adicionais/)).toBeNull();
  });

  it("nicho comum mostra 19.999 fundador e 16.188 fidelizado", async () => {
    montar(<PainelPreco nicheCode="pharmacy" />);
    await waitFor(() => temTexto("R$ 19.999,00"));
    temTexto("R$ 16.188,00");
  });

  it("expõe MEI, QA, principal e remuneração total sem atribuir QA ao MEI", async () => {
    montar(<PainelPreco nicheCode="supermarket" />);
    await waitFor(() => temTexto("R$ 23.854,32"));
    temTexto("R$ 121,68");
    temTexto("R$ 6.023,00");
    temTexto("R$ 6.144,68");
    expect(screen.getAllByText(/Parcela de QA da SmallFlags/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Remuneração contratual total da SmallFlags/).length).toBeGreaterThan(0);
  });

  it("a fórmula histórica só pode aparecer sob versão <= 2", () => {
    const fonte = semComentarios(lerFonte("src/components/commercial/PainelPreco.tsx"));
    const guarda = fonte.indexOf("founding.pricingRuleVersion <= 2");
    const uso = fonte.indexOf("FOUNDING_BLOCK_PRICE_CENTS", fonte.indexOf("export default function"));
    expect(guarda).toBeGreaterThan(-1);
    expect(uso).toBeGreaterThan(guarda);
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

/**
 * Resposta da vitrine agregada sob a autoridade ativa SF-v1.4, com a
 * decomposição explícita do pool. Os centavos são exatamente os congelados.
 */
const ECONOMIA_V14 = {
  ok: true,
  pricing_rule_version: 3,
  currency: "BRL",
  participant_target: 84,
  economic_value_cents: 12999400,
  user_pool_cents: 8391600,
  bdflow_ops_investment_cents: 4607800,
  per_complete_user_base_cents: 99900,
  pool_remainder_cents: 0,
  contract_economics_version: "SF-v1.4",
  mei_consideration_cents: 8349012,
  smallflags_qa_cents: 42588,
  per_complete_mei_base_cents: 99393,
  mei_remainder_cents: 0,
};

describe("COMERCIAL V2 UI — resumo agregado da formação", () => {
  it("mostra os números da autoridade ativa, vindos do servidor", async () => {
    rpcMock.mockResolvedValue({ data: ECONOMIA_V14, error: null });
    montar(<ResumoFormacao />);
    await waitFor(() => {
      expect(screen.getByText("R$ 129.994,00")).toBeDefined();
    });
    expect(screen.getByText("R$ 83.490,12")).toBeDefined(); // contraprestação MEIs
    expect(screen.getByText("R$ 425,88")).toBeDefined();    // parcela QA
    expect(screen.getByText("R$ 83.916,00")).toBeDefined(); // pool total
    expect(screen.getByText("R$ 46.078,00")).toBeDefined();
    expect(screen.getByText("R$ 993,93")).toBeDefined();    // por MEI elegível
  });

  it("NAO apresenta o pool inteiro como dinheiro dos usuários", async () => {
    rpcMock.mockResolvedValue({ data: ECONOMIA_V14, error: null });
    montar(<ResumoFormacao />);
    await waitFor(() => {
      expect(screen.getByText("R$ 83.916,00")).toBeDefined();
    });
    // O pool aparece como "pool contratual total", nunca como destinado aos
    // usuários: a parcela QA está dentro dele e é da SmallFlags.
    expect(screen.queryByText(/[Pp]ool destinado aos/)).toBeNull();
    expect(screen.getByText(/Pool contratual total/)).toBeDefined();
    expect(screen.getByText(/Parcela de QA da SmallFlags/)).toBeDefined();
    expect(
      screen.getByText(/pertence à SmallFlags — não é contraprestação do MEI/)
    ).toBeDefined();
  });

  it("o valor por participante deriva da contraprestação dos MEIs, não do pool", async () => {
    rpcMock.mockResolvedValue({ data: ECONOMIA_V14, error: null });
    montar(<ResumoFormacao />);
    await waitFor(() => {
      expect(screen.getByText("R$ 993,93")).toBeDefined();
    });
    // 99.900 = pool/84 e superdeclararia R$ 5,07 por participante.
    expect(screen.queryByText("R$ 999,00")).toBeNull();
  });

  it("qualifica o valor por usuário; não é saldo automático de cadastro", async () => {
    rpcMock.mockResolvedValue({ data: ECONOMIA_V14, error: null });
    montar(<ResumoFormacao />);
    await waitFor(() => {
      expect(screen.getByText(/cumpre\s+todos os requisitos operacionais/)).toBeDefined();
    });
    expect(screen.getByText(/Não é saldo em dinheiro devido pelo/)).toBeDefined();
  });

  it("falha de consulta NAO e ausencia de formacao: nao inventa numero", async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: "ops" } });
    montar(<ResumoFormacao />);
    await waitFor(() => {
      expect(
        screen.getByText(/Não foi possível carregar os valores da formação/)
      ).toBeDefined();
    });
    expect(screen.getByText(/falha de consulta, não a ausência de formação/)).toBeDefined();
    expect(screen.queryByText(/^R\$/)).toBeNull();
  });

  it("le a economia do SERVIDOR; nao recalcula preco no navegador", () => {
    const fonte = semComentarios(lerFonte("src/components/commercial/ResumoFormacao.tsx"));
    expect(fonte).toContain("fetchFormationEconomics");
    // O calculo local da V2 nao pode voltar: depois da SF-v1.4 ele exibiria
    // numeros que o servidor ja nao reconhece.
    expect(fonte).not.toContain("formationEconomicsV2");
    // Nenhum literal monetario digitado a mao.
    expect(fonte).not.toMatch(/12_?999_?400|8_?391_?600|8_?349_?012|99_?393|109_?900/);
  });

  it("está montado na página pública de oportunidades", () => {
    const fonte = lerFonte("src/pages/Oportunidades.tsx");
    expect(fonte).toContain("<ResumoFormacao />");
  });

  it("não anuncia mais a contratação como fase futura", () => {
    const fonte = semComentarios(lerFonte("src/pages/Oportunidades.tsx"));
    expect(fonte).not.toContain("A contratação será implementada em uma fase posterior");
    expect(fonte).toContain("avançar");
    expect(fonte).toContain("checkout");
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

  beforeEach(() => {
    rpcMock.mockResolvedValue({ data: RESPOSTA_V14, error: null });
  });

  it("mostra a composição SF-v1.4 do nicho escolhido a partir do servidor", async () => {
    montarCheckout("/checkout?nicho=supermarket");
    await waitFor(() => temTexto("R$ 29.999,00"));
    temTexto("R$ 23.854,32");
    temTexto("R$ 121,68");
    temTexto("R$ 6.023,00");
    temTexto("R$ 6.144,68");
    expect(screen.queryByText("R$ 35.587,00")).toBeNull();
  });

  it("o seletor de liquidação é operável e acessível por teclado", async () => {
    montarCheckout();
    const diretos = await screen.findByRole("radio", { name: /Benefícios diretos/ });
    const dinheiro = screen.getByRole("radio", { name: /Dinheiro real/ });
    expect((diretos as HTMLInputElement).checked).toBe(true);
    fireEvent.click(dinheiro);
    expect((dinheiro as HTMLInputElement).checked).toBe(true);
  });

  it("a seleção não é comunicada apenas por cor", async () => {
    montarCheckout();
    expect(await screen.findByText(/Benefícios diretos — selecionado/)).toBeDefined();
  });

  it("modo direto: cobrança é a remuneração total SmallFlags, QA inclusa", async () => {
    montarCheckout("/checkout?nicho=supermarket");
    expect(await screen.findByText("Contraprestação cumprida em benefício direto")).toBeDefined();
    const cobranca = screen.getByText("Valor financeiro da cobrança").parentElement as HTMLElement;
    expect(cobranca.textContent).toContain("R$ 6.144,68");
  });

  it("modo dinheiro: cobrança é o valor econômico completo", async () => {
    montarCheckout("/checkout?nicho=supermarket");
    const dinheiro = await screen.findByRole("radio", { name: /Dinheiro real/ });
    fireEvent.click(dinheiro);
    expect(screen.getByText("Contraprestação dos MEIs financiada em dinheiro")).toBeDefined();
    const cobranca = screen.getByText("Valor financeiro da cobrança").parentElement as HTMLElement;
    expect(cobranca.textContent).toContain("R$ 29.999,00");
  });

  it("o trilho é leitura derivada, nunca um seletor Pix/cartão", async () => {
    montarCheckout();
    expect(await screen.findByText("Forma de pagamento")).toBeDefined();
    expect(screen.getByText("Pix")).toBeDefined();
    const radios = screen.getAllByRole("radio");
    for (const r of radios) {
      expect((r as HTMLInputElement).name).toBe("benefit_settlement_mode");
    }
    expect(screen.queryByRole("radio", { name: /Pix/ })).toBeNull();
    expect(screen.queryByRole("radio", { name: /Cartão/ })).toBeNull();
  });

  it("mudar o modo NÃO altera os fatos econômicos v1.4", async () => {
    montarCheckout("/checkout?nicho=supermarket");
    const dinheiro = await screen.findByRole("radio", { name: /Dinheiro real/ });
    fireEvent.click(dinheiro);
    temTexto("R$ 29.999,00");
    temTexto("R$ 23.854,32");
    temTexto("R$ 121,68");
    temTexto("R$ 6.144,68");
  });

  it("valor vindo por query string é ignorado como autoridade", async () => {
    montarCheckout("/checkout?nicho=supermarket&economic_value_cents=1&pool=1&preco=1");
    await waitFor(() => temTexto("R$ 29.999,00"));
    expect(screen.queryByText("R$ 0,01")).toBeNull();
  });

  it("nicho explícito desconhecido falha fechado; não cai em supermercado", async () => {
    montarCheckout("/checkout?nicho=loja_de_camisas");
    expect(await screen.findByText("Condições comerciais indisponíveis")).toBeDefined();
    expect(screen.queryByText("R$ 29.999,00")).toBeNull();
  });

  it("a revisão vigente lê a autoridade e não contém cálculo monetário V2", () => {
    const fonte = semComentarios(lerFonte("src/pages/RevisaoContratacao.tsx"));
    expect(fonte).toContain("fetchPublicPricing");
    for (const proibido of [
      "computeCommercialCompositionV2",
      "fundingForSettlementMode",
      "FOUNDING_BLOCK_PRICE_CENTS",
      "EXTRA_UNIT_PRICE_CENTS",
      "FIDELIZED_UNIT_PRICE_CENTS",
      "NICHOS_REFERENCIA",
    ]) {
      expect(fonte).not.toContain(proibido);
    }
  });

  it("explica a fronteira entre reserva e pagamento sem alegar integração ausente", async () => {
    montarCheckout();
    expect(
      await screen.findByText(/A reserva não cobra valores\. O pagamento só é iniciado após a reserva/i)
    ).toBeDefined();
    expect(
      screen.queryByText(/Nenhum provedor de pagamento está integrado/i)
    ).toBeNull();
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
