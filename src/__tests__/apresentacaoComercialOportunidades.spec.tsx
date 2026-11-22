import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, within } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Apresentação comercial dos preços em /oportunidades e no detalhe.
 *
 * Fixtures: respostas REAIS de Production (somente leitura, 13/11/2026),
 * conferidas por md5 do jsonb canônico:
 *   get_public_niche_pricing()                    9fa027579866dd2cde79388545ac2787
 *   get_current_commercial_formation('ES','Vitória') 24c6a3dc1dccde7d23dc94d184cbde90
 * A SF-v1.4 está vigente; a tela mostra a prévia SF-v1.5, não contratável.
 *
 * Versão 4 (R3): respostas do banco LOCAL com a migration R3 ativada por
 * fixture (preco-publico-sf-v15-r3-cenario{A,B}-20261113.json). O preço da
 * modalidade DINHEIRO nelas é FICTÍCIO (Cenário A: sem a QA; B: preço mantido
 * com componente fundamentado). `semDinheiro` deriva o estado "DINHEIRO ainda
 * sem preço aprovado" (cash: null), que é o estado real enquanto A/B estiver
 * pendente.
 */
const lerFonte = (rel: string) => readFileSync(resolve(process.cwd(), rel), "utf8");
const semComentarios = (src: string) =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");
const fixture = (nome: string) =>
  JSON.parse(lerFonte(`src/__tests__/fixtures/${nome}`)) as Record<string, unknown>;

const PRECO_PRODUCTION = fixture("preco-publico-production-sf-v14-20261113.json");
const FORMACAO_PRODUCTION = fixture("formacao-production-grande-vitoria-20261113.json");

type Bloco = Record<string, unknown>;
type Nicho = { niche_code: string; founding: Bloco; fidelized: Bloco };
const copia = <T,>(x: T): T => JSON.parse(JSON.stringify(x));

const V4_A = fixture("preco-publico-sf-v15-r3-cenarioA-20261113.json");
const V4_B = fixture("preco-publico-sf-v15-r3-cenarioB-20261113.json");

/** DINHEIRO sem preço aprovado (cash: null) nas condições indicadas. */
function semDinheiro(base: unknown = V4_A,
                     condicoes: ("founding" | "fidelized")[] = ["founding", "fidelized"]) {
  const r = copia(base) as { niches: Nicho[] };
  for (const n of r.niches) {
    for (const c of condicoes) {
      (n[c].settlement_modes as Record<string, unknown>).cash = null;
      n[c].funding_cash_cents = null;
    }
  }
  return r;
}
/** Altera os dois blocos de todas as posições. */
function mexerV4(base: unknown, f: (b: Bloco) => void) {
  const r = copia(base) as { niches: Nicho[] };
  for (const n of r.niches) { f(n.founding); f(n.fidelized); }
  return r;
}
const modo = (b: Bloco, m: "direct_benefits" | "cash") =>
  (b.settlement_modes as Record<string, Bloco>)[m];

const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));
vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/commercialTerritory", () => ({
  obterTerritorio: () => ({ uf: "ES", city: "Vitória" }),
}));
vi.mock("../services/partnerApplicationService", () => ({
  obterVinculosParceiro: async () => ({ tipo: "sem_sessao" }),
}));

import Oportunidades from "../pages/Oportunidades";
import OportunidadeDetalhe from "../pages/OportunidadeDetalhe";
import ReferenciaOperacional from "../components/commercial/ReferenciaOperacional";
import { apresentacaoOportunidade } from "../domain/pricing/apresentacaoComercial";
import { interpretarPrecoPublico } from "../domain/pricing/contractPricing";
import { permiteCheckoutSF15 } from "../domain/pricing/pricingGateSF15";

function servir(preco: unknown) {
  rpcMock.mockImplementation(async (nome: string) => {
    if (nome === "get_public_niche_pricing") return { data: preco, error: null };
    if (nome === "get_current_commercial_formation") return { data: FORMACAO_PRODUCTION, error: null };
    return { data: null, error: { message: `rpc nao servida: ${nome}` } };
  });
}
const lista = () =>
  render(
    <MemoryRouter initialEntries={["/oportunidades"]}>
      <Routes><Route path="/oportunidades" element={<Oportunidades />} /></Routes>
    </MemoryRouter>,
  );
const detalhe = (slug: string) =>
  render(
    <MemoryRouter initialEntries={[`/oportunidades/${slug}`]}>
      <Routes><Route path="/oportunidades/:nicheSlug" element={<OportunidadeDetalhe />} /></Routes>
    </MemoryRouter>,
  );
const rpcsChamadas = () => rpcMock.mock.calls.map((c) => c[0] as string);
const ESCRITA = /reserv|create_|checkout_intent|payment|finaliz|admin_|join|register/i;

beforeEach(() => {
  rpcMock.mockReset();
  servir(PRECO_PRODUCTION);
});
afterEach(() => cleanup());

describe("/oportunidades — card comercial", () => {
  it("o valor total da contratação é a informação em evidência", async () => {
    lista();
    const card = await screen.findByTestId("card-supermarket");
    const total = await within(card).findByTestId("valor-total");
    const valor = within(total).getByText("R$ 32.939,00");
    expect(valor.className).toMatch(/font-display/);
    expect(valor.className).toMatch(/text-\[2rem\]|text-4xl/);
    expect(within(total).getByText("Valor total da contratação")).toBeDefined();
  });

  it("valores corretos em centavos: supermercado e as cinco posições comuns", async () => {
    lista();
    const sup = await screen.findByTestId("card-supermarket");
    await within(sup).findByText("R$ 32.939,00");
    expect(within(sup).getByText("R$ 23.854,32")).toBeDefined();
    for (const c of ["pharmacy", "womens_clothing", "mens_clothing", "footwear", "others"]) {
      const card = screen.getByTestId(`card-${c}`);
      expect(within(card).getByText("R$ 22.939,00")).toBeDefined();
      expect(within(card).getByText("R$ 11.927,16")).toBeDefined();
    }
  });

  it("explica o benefício direto e a alternativa em dinheiro no próprio card", async () => {
    lista();
    const card = await screen.findByTestId("card-pharmacy");
    await within(card).findByText("R$ 22.939,00");
    expect(within(card).getByTestId("destaque-beneficio-direto").textContent).toMatch(
      /benefícios em produtos das suas lojas/,
    );
    expect(within(card).getByTestId("alternativa-dinheiro").textContent).toMatch(
      /tudo em dinheiro.*repasses aos participantes/,
    );
  });

  it("R4.2: o card mostra o DINHEIRO do Cenário A e não afirma igualdade entre as formas", async () => {
    lista();
    const card = await screen.findByTestId("card-supermarket");
    await within(card).findByText("R$ 32.939,00");
    expect(within(card).getByText(/Para novo anunciante, com benefício direto/)).toBeDefined();
    expect(within(card).getByTestId("alternativa-dinheiro").textContent).toMatch(/valor total R\$ 32\.817,32/);
    expect(within(card).getByTestId("alternativa-dinheiro").textContent).not.toMatch(/32\.939/);
    cleanup();
    servir(V4_A);
    lista();
    const cardA = await screen.findByTestId("card-supermarket");
    await within(cardA).findByText("R$ 32.939,00");
    expect(within(cardA).getByTestId("alternativa-dinheiro").textContent).toMatch(/valor total R\$ 32\.817,32/);
    cleanup();
    servir(V4_B);
    lista();
    const cardB = await screen.findByTestId("card-supermarket");
    await within(cardB).findByText("R$ 32.939,00");
    expect(within(cardB).getByText("Para novo anunciante")).toBeDefined();
    expect(within(cardB).getByTestId("alternativa-dinheiro").textContent).not.toMatch(/32\.939|proposta comercial/);
  });

  it("não exibe faturamento agregado dos seis anunciantes nem da formação", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    const texto = document.body.textContent ?? "";
    for (const agregado of [
      "147.634,00", "109.116,00", "83.490,12", "129.994,00", "64.143,88",
      "25.625,88", "17.640,00", "425,88",
    ]) {
      expect(texto).not.toContain(agregado);
    }
  });

  it("sem soma dupla: o total não soma de novo a parte dos participantes", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    const texto = document.body.textContent ?? "";
    expect(texto).not.toContain("56.793,32"); // 32.939,00 + 23.854,32
    expect(texto).not.toContain("34.866,16"); // 22.939,00 + 11.927,16
  });

  it("prévia SF-v1.5 identificada como não contratável em cada card", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    expect(screen.getAllByTestId("selo-previa")).toHaveLength(6);
    expect(screen.getAllByTestId("selo-previa")[0].textContent).toMatch(/ainda não contratável/);
  });

  it("não expõe custo do fornecedor, valor por peça nem margens; só o total nominal de produção autorizado", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    const texto = document.body.textContent ?? "";
    // Permitido agora (pedido de 21/11/2026): o TOTAL nominal de fabricação, incluído no preço.
    expect(texto).toContain("R$ 2.940,00");
    // Continua proibido: valor por peça, fornecedor, margem, composição interna.
    expect(texto).not.toMatch(/R\$ ?35,00|fornecedor|unitári|por bandeira|por peça|\(R\$[^)]*cada\)/i);
    // "margem" só aparece na garantia negativa pedida.
    const semGarantia = texto.split("sem margem de fabricação da SmallFlags").join("");
    expect(semGarantia).not.toMatch(/margem/i);
    expect(texto).not.toMatch(/8\.963,00|10\.951,00|121,68|60,84|4\.200,00/); // parcelas internas e QA
    for (const f of ["src/components/commercial/OpportunityCard.tsx", "src/domain/pricing/apresentacaoComercial.ts"]) {
      expect(semComentarios(lerFonte(f))).not.toMatch(/flagUnitReferenceCents|flag_unit_reference/);
    }
  });
});

describe("/oportunidades — produção inicial, participação e renovação nos seis cards", () => {
  const SO_DINHEIRO = fixture("preco-publico-sf-v15-r43-somente-dinheiro-20261116.json");
  const POSICOES = [
    ["supermarket", "168", "R$ 23.854,32", "R$ 32.939,00", "R$ 28.176,00"],
    ["pharmacy", "84", "R$ 11.927,16", "R$ 22.939,00", "R$ 16.188,00"],
    ["womens_clothing", "84", "R$ 11.927,16", "R$ 22.939,00", "R$ 16.188,00"],
    ["mens_clothing", "84", "R$ 11.927,16", "R$ 22.939,00", "R$ 16.188,00"],
    ["footwear", "84", "R$ 11.927,16", "R$ 22.939,00", "R$ 16.188,00"],
    ["others", "84", "R$ 11.927,16", "R$ 22.939,00", "R$ 16.188,00"],
  ] as const;
  const card = (c: string) => screen.getByTestId(`card-${c}`);
  const semFabricacao = (base: unknown) => mexerV4(base, (b) => {
    for (const k of ["new_flag_units", "flag_unit_reference_cents", "flag_production_charge_cents", "flag_reuse_required"]) delete b[k];
  });

  it.each([["prévia SF-v1.5", PRECO_PRODUCTION], ["v4 vigente (cenário A)", V4_A]] as const)(
    "%s: as três informações em todos os seis cards", async (_n, resposta) => {
    servir(resposta);
    lista();
    await screen.findAllByText("R$ 22.939,00");
    for (const [c, part, mei, total, renov] of POSICOES) {
      const k = card(c);
      expect(within(within(k).getByTestId("valor-total")).getByText(total)).toBeDefined();
      const prod = within(k).getByTestId("producao-inicial");
      expect(prod.textContent).toMatch(/84 bandeiras físicas/);
      expect(prod.textContent).toMatch(/Custo nominal de R\$ 2\.940,00, já incluído no valor total acima\. Não some esse valor de novo\./);
      expect(prod.textContent).toMatch(/Só na primeira contratação/);
      const p = within(k).getByTestId("destaque-beneficio-direto");
      expect(within(p).getByTestId("valor-por-participacao").textContent).toBe("R$ 141,99 por participação aprovada");
      expect(p.textContent).toContain(`${part} participações potenciais: até ${mei} deste valor`);
      expect(p.textContent).toMatch(/não são motoristas distintos nem pagamentos\s+garantidos/);
      const r = within(k).getByTestId("renovacao-fidelizada");
      expect(r.textContent).toContain(renov);
      expect(r.textContent).toMatch(/Na renovação, com benefício direto/);
      expect(r.textContent).toMatch(/inspeção.*histórico de fidelidade.*manutenção da posição/);
      expect(r.textContent).toMatch(/não uma opção a escolher/);
      expect(r.textContent).toMatch(/orçadas e aceitas\s+separadamente, sem margem de fabricação da SmallFlags/);
    }
  });

  it("prévia: selo mantido em cada card e renovação marcada como valor proposto; v4 sem selo", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    expect(screen.getAllByTestId("selo-previa")).toHaveLength(6);
    expect(screen.getAllByTestId("renovacao-fidelizada").every((r) => /valor proposto na prévia/.test(r.textContent!))).toBe(true);
    cleanup();
    servir(V4_A);
    lista();
    await screen.findAllByText("R$ 22.939,00");
    expect(screen.queryAllByTestId("selo-previa")).toHaveLength(0);
    expect(document.body.textContent).not.toMatch(/valor proposto na prévia/);
  });

  it("o valor total continua sendo o maior destaque do card", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    for (const [c] of POSICOES) {
      const k = card(c);
      const grandes = Array.from(k.querySelectorAll("[class*='text-[2rem]'], [class*='text-4xl'], [class*='text-3xl'], [class*='text-2xl'], [class*='text-xl']"))
        .filter((e) => /R\$/.test(e.textContent ?? ""));
      expect(grandes).toHaveLength(1);
      expect(within(k).getByTestId("valor-total").contains(grandes[0])).toBe(true);
    }
  });

  it("sem soma dupla nem confusão entre peças, unidades comerciais e participações", async () => {
    lista();
    await screen.findAllByText("R$ 22.939,00");
    const texto = document.body.textContent ?? "";
    expect(texto).not.toMatch(/35\.879,00|25\.879,00/); // total + fabricação
    expect(texto).not.toMatch(/(12|24|168) bandeiras/);
    expect(within(card("supermarket")).getByTestId("producao-inicial").textContent).not.toMatch(/168|24/);
    expect(within(card("supermarket")).getByTestId("destaque-beneficio-direto").textContent).not.toMatch(/\b84 participações/);
    expect(within(card("pharmacy")).getByTestId("producao-inicial").textContent).not.toMatch(/\b12\b/);
  });

  it("cenário B (mesmo valor nas duas formas): renovação sem rótulo de modalidade", async () => {
    servir(V4_B);
    lista();
    await screen.findAllByText("R$ 22.939,00");
    const r = within(card("supermarket")).getByTestId("renovacao-fidelizada");
    expect(r.textContent).toContain("R$ 28.176,00");
    expect(r.textContent).toMatch(/Na renovaçãoReutiliza/);
  });

  it("somente DINHEIRO habilitado: totais em dinheiro; nenhum valor do benefício direto como contratável", async () => {
    servir(SO_DINHEIRO);
    lista();
    await screen.findAllByText("R$ 22.878,16");
    const sup = card("supermarket");
    expect(within(within(sup).getByTestId("valor-total")).getByText("R$ 32.817,32")).toBeDefined();
    const r = within(sup).getByTestId("renovacao-fidelizada");
    expect(r.textContent).toContain("R$ 28.054,32");
    expect(r.textContent).toMatch(/Na renovação, em dinheiro/);
    expect(within(within(card("pharmacy")).getByTestId("renovacao-fidelizada")).getByText("R$ 16.127,16")).toBeDefined();
    const texto = document.body.textContent ?? "";
    expect(texto).not.toMatch(/32\.939,00|22\.939,00|28\.176,00|16\.188,00/);
    expect(texto).not.toMatch(/com benefício direto/);
    expect(within(sup).getByTestId("destaque-beneficio-direto").textContent).toMatch(/financiada em dinheiro/);
    // Produção e participação continuam iguais: fazem parte das duas modalidades.
    expect(within(sup).getByTestId("producao-inicial").textContent).toMatch(/84 bandeiras físicas.*R\$ 2\.940,00/);
    expect(within(sup).getByTestId("valor-por-participacao").textContent).toBe("R$ 141,99 por participação aprovada");
  });

  it("v4 sem produção declarada pelo servidor: nada de produção nem de renovação sem bandeiras é inferido", async () => {
    const r = semFabricacao(V4_A);
    expect(interpretarPrecoPublico(r)).not.toBeNull();
    servir(r);
    lista();
    await screen.findAllByText("R$ 22.939,00");
    expect(screen.queryAllByTestId("producao-inicial")).toHaveLength(0);
    expect(screen.queryAllByTestId("renovacao-fidelizada")).toHaveLength(0);
    expect(document.body.textContent).not.toMatch(/2\.940,00|bandeiras físicas|sem novas bandeiras/);
    expect(screen.getAllByTestId("valor-por-participacao")).toHaveLength(6);
  });

  it.each([
    ["quantidade de peças diferente de 84", (b: Bloco) => {
      if (b.new_flag_units) { b.new_flag_units = 80; b.flag_production_charge_cents = 80 * (b.flag_unit_reference_cents as number); }
    }],
    ["custo nominal mínimo, mas declarado e coerente", (b: Bloco) => {
      if (b.new_flag_units) { b.flag_unit_reference_cents = 1; b.flag_production_charge_cents = 84; }
    }],
  ])("produção atípica do servidor (%s): só o validado aparece, nada é inferido", async (_n, f) => {
    const resp = mexerV4(V4_A, f);
    const precos = interpretarPrecoPublico(resp)!;
    expect(precos).not.toBeNull();
    const ap = apresentacaoOportunidade(precos[0])!;
    if (_n.startsWith("quantidade")) expect(ap.novo.producaoInicial).toBeNull();
    servir(resp);
    lista();
    await screen.findAllByText("R$ 22.939,00");
    if (_n.startsWith("quantidade")) {
      expect(screen.queryAllByTestId("producao-inicial")).toHaveLength(0);
      expect(document.body.textContent).not.toMatch(/80 bandeiras|bandeiras físicas/);
    } else {
      // Custo de R$ 0,84 é declarado e coerente: aparece exatamente como o servidor publicou.
      expect(screen.getAllByTestId("producao-inicial")[0].textContent).toMatch(/R\$ 0,84/);
    }
  });

  it("modelo: produção só com 84 peças, custo positivo dentro da parcela; renovação com zero peças novas", () => {
    const prev = apresentacaoOportunidade(interpretarPrecoPublico(PRECO_PRODUCTION)![0])!;
    expect(prev.novo.producaoInicial).toEqual({ bandeirasFisicas: 84, custoNominalCentavos: 294000 });
    expect(prev.fidelizado.reutilizaBandeiras).toBe(true);
    expect(prev.novo.producaoInicial!.custoNominalCentavos).toBeLessThanOrEqual(prev.novo.parcelaSmallFlagsCentavos);
    expect(Object.keys(prev.novo.producaoInicial!)).toEqual(["bandeirasFisicas", "custoNominalCentavos"]);
    const v4 = apresentacaoOportunidade(interpretarPrecoPublico(V4_A)![0])!;
    expect(v4.novo.producaoInicial).toEqual({ bandeirasFisicas: 84, custoNominalCentavos: 294000 });
    const sem = apresentacaoOportunidade(interpretarPrecoPublico(semFabricacao(V4_A))![0])!;
    expect(sem.novo.producaoInicial).toBeNull();
    expect(sem.fidelizado.reutilizaBandeiras).toBe(false);
  });

  it.each([
    ["prévia", PRECO_PRODUCTION],
    ["v4 com DINHEIRO pendente", semDinheiro()],
    ["somente DINHEIRO", SO_DINHEIRO],
    ["v4 cenário A", V4_A],
  ] as const)("%s: os cards não liberam contratação, não oferecem escolha e não gravam nada", async (_n, resposta) => {
    servir(resposta);
    lista();
    await screen.findAllByTestId("destaque-beneficio-direto");
    expect(document.querySelector('a[href^="/checkout"]')).toBeNull();
    for (const a of Array.from(document.querySelectorAll("article a"))) {
      expect(a.getAttribute("href")).toMatch(/^\/oportunidades\/[a-z-]+$/);
    }
    expect(document.querySelectorAll("article input, article select, article button")).toHaveLength(0);
    expect(document.body.textContent).not.toMatch(/sou fidelizad|marcar como fidelizad|desconto|promoç|economize/i);
    expect(rpcsChamadas().filter((n) => ESCRITA.test(n))).toEqual([]);
  });
});

describe("detalhe — duas modalidades de cumprimento da mesma contratação", () => {
  it("R4.2: as duas formas lado a lado, com valores diferentes no Cenário A; igualdade NÃO afirmada", async () => {
    detalhe("supermarket");
    const beneficio = await screen.findByTestId("modalidade-beneficio-direto");
    const dinheiro = screen.getByTestId("modalidade-dinheiro");
    expect(beneficio.textContent).toMatch(/Benefício direto/i);
    expect(dinheiro.textContent).toMatch(/Dinheiro/i);
    expect(screen.getByTestId("total-modalidades").textContent).toMatch(
      /Com benefício direto, o valor total é R\$ 32\.939,00\. Em dinheiro não há testes com produtos, e o valor total dessa forma é R\$ 32\.817,32/,
    );
    expect(screen.getByTestId("valor-dinheiro").textContent).toMatch(/R\$ 32\.817,32/);
    const texto = document.body.textContent ?? "";
    expect(texto).not.toMatch(/mesmo valor total|valor total é o mesmo/);
    expect(beneficio.textContent).not.toContain("R$ 32.939,00");
    expect(dinheiro.textContent).not.toContain("R$ 32.939,00");
    expect(screen.getByTestId("condicao-novo").textContent).toMatch(/com benefício direto/);
  });

  it("R3: igualdade só quando o servidor publica as duas formas com o MESMO valor (cenário B de teste)", async () => {
    servir(V4_B);
    detalhe("supermarket");
    expect((await screen.findByTestId("total-modalidades")).textContent).toMatch(
      /Nas duas formas, o valor total é o mesmo: R\$ 32\.939,00/,
    );
    expect(screen.getByTestId("mesmo-valor").textContent).toMatch(/mesmo valor total\./);
    expect(screen.queryByTestId("valor-dinheiro")).toBeNull();
  });

  it("R3: valores diferentes (cenário A de teste) não aparecem como iguais: cada forma com o seu total", async () => {
    servir(V4_A);
    detalhe("supermarket");
    const intro = await screen.findByTestId("total-modalidades");
    expect(intro.textContent).toMatch(/Com benefício direto, o valor total é R\$ 32\.939,00/);
    expect(intro.textContent).toMatch(/Em dinheiro não há testes com produtos, e o valor total dessa forma é R\$ 32\.817,32/);
    expect(screen.getByTestId("valor-dinheiro").textContent).toMatch(/R\$ 32\.817,32/);
    expect(document.body.textContent).not.toMatch(/mesmo valor total|valor total é o mesmo/);
  });

  it("o valor total não se repete no detalhe: resumo e modalidades, fora da composição", async () => {
    detalhe("supermarket");
    await screen.findByTestId("modalidades");
    const composicao = screen.getByTestId("composicao-tecnica");
    const fora = (document.body.textContent ?? "").replace(composicao.textContent ?? "", "");
    expect(fora.split("R$ 32.939,00").length - 1).toBe(2);
  });

  it("a modalidade DINHEIRO continua contemplando os motoristas", async () => {
    detalhe("pharmacy");
    const dinheiro = await screen.findByTestId("modalidade-dinheiro");
    expect(dinheiro.textContent).toContain("R$ 11.927,16");
    expect(dinheiro.textContent).toMatch(/repassad/);
    expect(dinheiro.textContent).toMatch(/motoristas continuam recebendo a contraprestação/);
  });

  it("benefício direto não aparece como desconto promocional", async () => {
    detalhe("supermarket");
    await screen.findByTestId("modalidades");
    const texto = document.body.textContent ?? "";
    expect(texto).not.toMatch(/economize|abatimento|promoç|promocional|off\b|grátis|gratuit/i);
    // "desconto" só pode aparecer negado.
    for (const m of texto.matchAll(/(.{0,12})desconto/gi)) {
      expect(m[1]).toMatch(/não é\s*$/i);
    }
    // A parte dos participantes aparece como fração do total, não como preço alternativo.
    expect(screen.getByTestId("modalidade-beneficio-direto").textContent).toMatch(
      /Até R\$ 23\.854,32 do total/,
    );
  });

  it("valores do detalhe da Farmácia corretos, inclusive a renovação fidelizada", async () => {
    detalhe("pharmacy");
    const resumo = await screen.findByTestId("resumo-valor");
    expect(within(resumo).getByText("R$ 22.939,00")).toBeDefined();
    expect(within(screen.getByTestId("condicao-fidelizada")).getByText("R$ 16.188,00")).toBeDefined();
    expect(screen.getByTestId("modalidade-beneficio-direto").textContent).toMatch(
      /84 participações potenciais × R\$ 141,99/,
    );
  });

  it("fidelizado só como condição definida pela SmallFlags; nada permite escolher", async () => {
    detalhe("supermarket");
    const fid = await screen.findByTestId("condicao-fidelizada");
    expect(fid.textContent).toContain("R$ 28.176,00");
    expect(fid.textContent).toMatch(/Condição aplicada pela SmallFlags/);
    expect(fid.textContent).toMatch(/Não é uma opção a escolher/);
    expect(fid.textContent).toMatch(/após inspeção/);
    expect(fid.textContent).toMatch(/fidelidade é mantida mesmo quando a empresa muda a frase ou a arte/);
    expect(fid.textContent).toMatch(/custo do fornecedor cobrado à parte, sem margem/);
    expect(screen.queryAllByRole("radio")).toHaveLength(0);
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    expect(screen.queryAllByRole("combobox")).toHaveLength(0);
    expect(screen.queryByText(/sou fidelizad|marcar como fidelizad/i)).toBeNull();
  });

  it("R3: QA só no benefício direto, em produtos, nunca dos participantes; inexistente no dinheiro", async () => {
    detalhe("supermarket");
    await screen.findByTestId("modalidades");
    const beneficio = screen.getByTestId("modalidade-beneficio-direto");
    const dinheiro = screen.getByTestId("modalidade-dinheiro");
    // A QA aparece no benefício direto só como produtos para testes, à parte.
    expect(within(beneficio).getByTestId("qa-produtos").textContent).toMatch(
      /R\$ 121,68 em produtos para testes locais de qualidade autorizados pela SmallFlags\. Esses produtos não são cobrados em dinheiro e não são dos motoristas/,
    );
    expect(beneficio.textContent!.replace(within(beneficio).getByTestId("qa-produtos").textContent!, ""))
      .not.toMatch(/121,68/);
    // Dinheiro: nenhuma QA, nenhum teste com produtos.
    expect(dinheiro.textContent).not.toMatch(/QA|121,68/);
    expect(dinheiro.textContent).toMatch(/Nesta forma não há testes com produtos/);
    const comp = screen.getByTestId("composicao-tecnica");
    expect(comp.textContent).toMatch(
      /parcela de qualidade \(QA\), de R\$ 121,68, existe só no benefício\s*direto: são produtos para testes locais autorizados pela SmallFlags\.\s*Não é cobrada em dinheiro, não é contraprestação dos participantes e\s*não existe na forma em dinheiro/,
    );
    const ap = apresentacaoOportunidade(interpretarPrecoPublico(PRECO_PRODUCTION)![0])!;
    expect(ap.participantes.contraprestacaoPotencialCentavos).toBe(168 * 14199);
    expect(ap.participantes.contraprestacaoPotencialCentavos).toBe(2385432);
  });

  it("R3: dinheiro do benefício direto = só a parcela da SmallFlags; a QA nunca é somada à remuneração", async () => {
    detalhe("supermarket");
    await screen.findByTestId("composicao-tecnica");
    expect(screen.getByTestId("dinheiro-beneficio-direto").textContent).toMatch(
      /Em dinheiro, nesta forma, só a parcela da SmallFlags: R\$ 8\.963,00/,
    );
    const texto = document.body.textContent ?? "";
    // 9.084,68 = parcela + QA: a leitura antiga (QA em dinheiro). Não aparece.
    expect(texto).not.toMatch(/9\.084,68|4\.321,68/);
    expect(texto).not.toMatch(/devida em dinheiro|em conciliação|concilia/i);
    expect(screen.queryByTestId("ressalva-beneficio-direto")).toBeNull();
    // Registro interno da decisão.
    expect(lerFonte("docs/release/QA_MODALIDADES_R3_20261113.md")).toMatch(/Cenário A/);
  });

  it("forma de cumprimento não é confundida com meio de pagamento", async () => {
    detalhe("supermarket");
    const mesmo = await screen.findByTestId("mesmo-valor");
    expect(mesmo.textContent).toMatch(/forma de cumprimento não é o meio de pagamento/);
    expect(screen.getByTestId("modalidade-beneficio-direto").textContent).not.toMatch(/Pix|cartão/i);
    expect(screen.getByTestId("modalidade-dinheiro").textContent).not.toMatch(/Pix|cartão/i);
  });
});

describe("detalhe — prévia não é versão ativa; checkout continua bloqueado", () => {
  it("SF-v1.5 preparada: aviso de não contratável e nenhum link ao checkout", async () => {
    detalhe("supermarket");
    expect((await screen.findByTestId("aviso-previa")).textContent).toMatch(/ainda não contratável/);
    expect(screen.getByTestId("contratacao-suspensa").textContent).toMatch(
      /Contratação temporariamente indisponível/,
    );
    expect(screen.queryByRole("link", { name: /Solicitar contratação/ })).toBeNull();
    expect(document.querySelector('a[href^="/checkout"]')).toBeNull();
  });

  it("CONTRAPROVA R3: versão 4 ativa com o DINHEIRO sem preço aprovado não oferece contratação", async () => {
    servir(semDinheiro());
    detalhe("supermarket");
    const resumo = await screen.findByTestId("resumo-valor");
    expect(within(resumo).getByText("R$ 32.939,00")).toBeDefined();
    expect(screen.queryByTestId("aviso-previa")).toBeNull();
    expect(screen.getByTestId("valor-dinheiro").textContent).toMatch(/confirmado na proposta comercial/);
    expect(screen.getByTestId("contratacao-suspensa").textContent).toMatch(
      /Contratação temporariamente indisponível.*ainda não foi liberada/,
    );
    expect(screen.queryByRole("link", { name: /Solicitar contratação/ })).toBeNull();
    expect(document.querySelector('a[href^="/checkout"]')).toBeNull();
    const precos = interpretarPrecoPublico(semDinheiro())!;
    expect(precos.every((p) => p.founding.pricingRuleVersion === 4)).toBe(true);
    expect(permiteCheckoutSF15(precos)).toBe(false);
    expect(precos.every((p) => apresentacaoOportunidade(p)!.contratavel === false)).toBe(true);
  });

  it("CONTRAPROVA R3: DINHEIRO pendente em UMA condição continua bloqueado", () => {
    const precos = interpretarPrecoPublico(semDinheiro(V4_A, ["fidelized"]))!;
    expect(permiteCheckoutSF15(precos)).toBe(false);
    expect(apresentacaoOportunidade(precos[0])!.contratavel).toBe(false);
  });

  it.each([
    ["A", V4_A],
    ["B", V4_B],
  ] as const)("versão 4 com as duas modalidades definidas pelo servidor (cenário %s de teste): contratação disponível", async (_c, resposta) => {
    servir(resposta);
    detalhe("supermarket");
    await screen.findByTestId("resumo-valor");
    expect(screen.queryByTestId("aviso-previa")).toBeNull();
    expect(screen.queryByTestId("contratacao-suspensa")).toBeNull();
    expect(screen.getByRole("link", { name: /Solicitar contratação/ }).getAttribute("href")).toBe(
      "/checkout?nicho=supermarket",
    );
    expect(permiteCheckoutSF15(interpretarPrecoPublico(resposta)!)).toBe(true);
  });

  it.each([
    ["QA monetária no benefício direto", (b: Bloco) => { modo(b, "direct_benefits").qa_cash_cents = 12168; }],
    ["benefício direto cobrando a QA em dinheiro", (b: Bloco) => {
      const d = modo(b, "direct_benefits");
      d.total_monetary_funding_required_cents = (d.total_monetary_funding_required_cents as number) + (d.qa_in_kind_cents as number);
    }],
    ["chaves legadas cobrando a QA em dinheiro (leitura antiga)", (b: Bloco) => {
      b.funding_direct_benefits_cents = (b.funding_direct_benefits_cents as number) + (b.smallflags_qa_cents as number);
      b.smallflags_total_remuneration_cents = b.funding_direct_benefits_cents;
    }],
    ["DINHEIRO com QA em produtos", (b: Bloco) => {
      const c = modo(b, "cash"); c.qa_in_kind_cents = 6084;
      c.economic_value_cents = (c.economic_value_cents as number) + 6084;
      c.total_monetary_funding_required_cents = c.economic_value_cents;
      b.funding_cash_cents = c.economic_value_cents;
    }],
    ["DINHEIRO com QA monetária", (b: Bloco) => { modo(b, "cash").qa_cash_cents = 6084; }],
    ["DINHEIRO com a QA renomeada como remuneração (principal maior)", (b: Bloco) => {
      const c = modo(b, "cash");
      c.smallflags_main_fee_cents = (c.smallflags_main_fee_cents as number) + 6084;
      c.economic_value_cents = (c.economic_value_cents as number) + 6084;
      c.total_monetary_funding_required_cents = c.economic_value_cents;
      b.funding_cash_cents = c.economic_value_cents;
    }],
    ["DINHEIRO cobrando menos que o próprio total", (b: Bloco) => {
      modo(b, "cash").total_monetary_funding_required_cents = 1;
    }],
    ["participantes diferentes entre as formas", (b: Bloco) => { modo(b, "cash").mei_consideration_cents = 1; }],
    ["sem política de QA", (b: Bloco) => { delete b.qa_policy; }],
    ["sem blocos por modalidade", (b: Bloco) => { delete b.settlement_modes; }],
    ["DINHEIRO nulo mas cobrança em dinheiro declarada", (b: Bloco) => {
      (b.settlement_modes as Record<string, unknown>).cash = null;
    }],
    ["chave R2 qa_settlement_mode (fora do contrato R3)", (b: Bloco) => { b.qa_settlement_mode = "in_kind"; }],
  ])("frontend rejeita resposta v4 inconsistente: %s", async (_nome, f) => {
    const r = mexerV4(V4_A, f);
    expect(interpretarPrecoPublico(r)).toBeNull();
    servir(r);
    detalhe("supermarket");
    await screen.findByText(/não estão disponíveis no momento/);
    expect(document.body.textContent).not.toMatch(/R\$/);
    expect(document.querySelector('a[href^="/checkout"]')).toBeNull();
  });

  it("versões históricas não recebem QA por modalidade (SF-v1.4 com blocos R3 é recusada)", () => {
    const r = copia(PRECO_PRODUCTION) as { niches: Nicho[] };
    for (const n of r.niches) n.founding.qa_policy = "in_kind_direct_benefits_only";
    expect(interpretarPrecoPublico(r)).toBeNull();
  });

  it("a autorização não vem de constante do navegador", () => {
    for (const f of [
      "src/domain/pricing/apresentacaoComercial.ts",
      "src/components/commercial/PainelPreco.tsx",
      "src/domain/pricing/pricingGateSF15.ts",
    ]) {
      expect(lerFonte(f)).not.toMatch(/QA_BENEFICIO_DIRETO_CONCILIADA|qaSettlementMode/);
    }
    const ap = semComentarios(lerFonte("src/domain/pricing/apresentacaoComercial.ts"));
    expect(ap).toMatch(/const definidas = b\.estado === "vigente" && modalidadesDefinidas\(preco\)/);
    expect(ap).toMatch(/contratavel: definidas/);
    const gate = semComentarios(lerFonte("src/domain/pricing/pricingGateSF15.ts"));
    // R4.3: toda modalidade HABILITADA pelo servidor precisa de preço; DINHEIRO
    // habilitado sem preço continua bloqueando.
    expect(gate).toMatch(/x === "cash" \? m\.cash !== null/);
    expect(gate).toMatch(/qaPolicy !== "in_kind_direct_benefits_only"/);
    expect(gate).toMatch(/m\.habilitadas \?\? AS_DUAS/);
  });

  it("nenhum clique na apresentação altera preço nem registra reserva", async () => {
    detalhe("supermarket");
    await screen.findByTestId("modalidades");
    const antes = document.body.textContent;
    fireEvent.click(screen.getByText("Detalhes da composição do valor"));
    fireEvent.click(screen.getByTestId("modalidade-beneficio-direto"));
    fireEvent.click(screen.getByTestId("modalidade-dinheiro"));
    expect(screen.getByTestId("resumo-valor").textContent).toContain("R$ 32.939,00");
    expect(rpcsChamadas().filter((n) => ESCRITA.test(n))).toEqual([]);
    expect(antes).toContain("R$ 32.939,00");
  });

  it("a guarda do checkout exige a SF-v1.5 ativa e as duas modalidades definidas nas seis posições", () => {
    expect(permiteCheckoutSF15(interpretarPrecoPublico(PRECO_PRODUCTION)!)).toBe(false);
    expect(permiteCheckoutSF15(interpretarPrecoPublico(semDinheiro())!)).toBe(false);
    expect(permiteCheckoutSF15(interpretarPrecoPublico(V4_A)!)).toBe(true);
    expect(permiteCheckoutSF15(interpretarPrecoPublico(V4_B)!)).toBe(true);
    const app = semComentarios(lerFonte("src/App.tsx"));
    expect(app).toMatch(/CheckoutPrecificacaoGuard/);
    expect(lerFonte("src/components/CheckoutPrecificacaoGuard.tsx")).toMatch(/permiteCheckoutSF15/);
  });
});

describe("falha fechada — resposta incompleta ou incompatível não exibe valor", () => {
  const mexer = (f: (n: Nicho) => void) => {
    const r = copia(PRECO_PRODUCTION) as { niches: Nicho[] };
    r.niches.forEach(f);
    return r;
  };
  it.each([
    ["sem contraprestação dos MEIs", mexer((n) => { delete n.founding.mei_consideration_cents; })],
    ["MEI incompatível com 168/84 participações", mexer((n) => { n.founding.mei_consideration_cents = (n.founding.mei_consideration_cents as number) + 1; n.founding.contractual_pool_cents = (n.founding.contractual_pool_cents as number) + 1; n.founding.economic_value_cents = (n.founding.economic_value_cents as number) + 1; n.founding.funding_cash_cents = (n.founding.funding_cash_cents as number) + 1; })],
    ["versão desconhecida", mexer((n) => { n.founding.pricing_rule_version = 9; n.fidelized.pricing_rule_version = 9; })],
    ["SF-v1.4 com valor inesperado", mexer((n) => { n.fidelized.economic_value_cents = 1; })],
  ])("%s", async (_nome, resposta) => {
    servir(resposta);
    lista();
    await screen.findAllByTestId("valor-indisponivel");
    expect(screen.queryByTestId("valor-total")).toBeNull();
    expect(document.body.textContent).not.toMatch(/R\$/);
    cleanup();
    detalhe("supermarket");
    await screen.findByText(/não estão disponíveis no momento/);
    expect(document.body.textContent).not.toMatch(/R\$/);
  });

  it("modelo de apresentação: total do benefício direto = participantes + parcela + QA em produtos, sem soma dupla", () => {
    const p = interpretarPrecoPublico(PRECO_PRODUCTION)![0];
    expect(apresentacaoOportunidade(p)).not.toBeNull();
    expect(apresentacaoOportunidade(null)).toBeNull();
    const ap = apresentacaoOportunidade(p)!;
    for (const c of [ap.novo, ap.fidelizado]) {
      expect(c.valorTotalCentavos).toBe(
        ap.participantes.contraprestacaoPotencialCentavos + c.parcelaSmallFlagsCentavos + c.qaEmProdutosCentavos,
      );
      // R4.2: prévia com o DINHEIRO do Cenário A = participantes + parcela, sem QA.
      expect(c.valorDinheiroCentavos).toBe(
        ap.participantes.contraprestacaoPotencialCentavos + c.parcelaSmallFlagsCentavos,
      );
    }
    expect(ap.novo.valorDinheiroCentavos).toBe(3281732);
    expect(ap.fidelizado.valorDinheiroCentavos).toBe(2805432);
    expect(ap.contratavel).toBe(false);
    const a = apresentacaoOportunidade(interpretarPrecoPublico(V4_A)![0])!;
    expect(a.novo.valorDinheiroCentavos).toBe(3281732);
    expect(a.novo.valorDinheiroCentavos).toBe(
      a.participantes.contraprestacaoPotencialCentavos + a.novo.parcelaSmallFlagsCentavos,
    );
    expect(a.mesmoValorNasDuasFormas).toBe(false);
    expect(apresentacaoOportunidade(interpretarPrecoPublico(V4_B)![0])!.mesmoValorNasDuasFormas).toBe(true);
  });
});

describe("layout responsivo e acessível", () => {
  const FONTES = [
    "src/components/commercial/OpportunityCard.tsx",
    "src/components/commercial/PainelPreco.tsx",
    "src/pages/OportunidadeDetalhe.tsx",
  ];
  it("sem tabelas largas nem larguras fixas que forcem rolagem horizontal", () => {
    for (const f of FONTES) {
      const src = semComentarios(lerFonte(f));
      expect(src).not.toMatch(/<table/);
      expect(src).not.toMatch(/min-w-\[\d{3,}px\]|w-\[\d{3,}px\]/);
    }
    expect(lerFonte("src/components/commercial/PainelPreco.tsx")).toMatch(/md:grid-cols-2/);
  });

  it("composição técnica é recolhível e operável por teclado (details/summary nativos)", async () => {
    detalhe("supermarket");
    const det = (await screen.findByTestId("composicao-tecnica")) as HTMLDetailsElement;
    expect(det.tagName).toBe("DETAILS");
    expect(det.open).toBe(false);
    expect(det.querySelector("summary")).not.toBeNull();
  });

  it("cada card é um artigo rotulado pelo nome da posição", async () => {
    lista();
    expect(await screen.findByRole("article", { name: "Supermercado" })).toBeDefined();
    expect(screen.getAllByRole("article")).toHaveLength(6);
  });
});

describe("referência operacional — sete participações potenciais", () => {
  it("reconcilia o texto legado de seis benefícios", () => {
    render(<ReferenciaOperacional />);
    expect(
      screen.getByText(
        "Sete participações potenciais por usuário: duas no supermercado e uma em cada uma das outras cinco posições",
      ),
    ).toBeDefined();
    expect(screen.queryByText(/Seis benefícios/)).toBeNull();
    expect(screen.getByText("84 usuários-produto na operação de referência")).toBeDefined();
  });
});
