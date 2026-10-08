import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { QUADRO_V14, FORMACAO_REFERENCIA } from "../content/institucional";

/**
 * Item D — instrumento comercial por pedido.
 *
 * As asserções de SQL leem a migration: provam o CONTRATO escrito, não o
 * comportamento em execução. Só a aceitação autenticada em staging prova o
 * segundo.
 *
 * Fonte congelada conferida contra o manifesto oficial:
 * SF-0001..SF-0006 v1.4, SHA-256 03f36670...0c73.
 */
const MIG = readFileSync(
  resolve(
    __dirname,
    "../../supabase/migrations/20261005160000_commercial_order_instrument_snapshot.sql"
  ),
  "utf8"
);

const reais = (c: number) => (c / 100).toFixed(2);

/* Quadro financeiro ------------------------------------------------------ */
describe("quadro financeiro v1.4 congelado", () => {
  it("o hash do modelo é o do manifesto oficial", () => {
    expect(QUADRO_V14.templateHash).toBe(
      "03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73"
    );
    expect(QUADRO_V14.templateVersion).toBe("1.4");
  });

  it("supermercado: pool = MEIs + QA, e pool + operacional = valor econômico", () => {
    const s = QUADRO_V14.supermercado;
    expect(reais(s.meiCents)).toBe("23854.32");
    expect(reais(s.qaCents)).toBe("121.68");
    expect(reais(s.meiCents + s.qaCents)).toBe("23976.00");
    expect(s.meiCents + s.qaCents + s.operacionalCents).toBe(s.valorEconomicoCents);
    // Remuneração contratual total da SmallFlags = operacional + QA.
    expect(reais(s.operacionalCents + s.qaCents)).toBe("6144.68");
  });

  it("demais posições: mesma identidade aritmética", () => {
    const o = QUADRO_V14.demaisPosicoes;
    expect(reais(o.meiCents)).toBe("11927.16");
    expect(reais(o.qaCents)).toBe("60.84");
    expect(reais(o.meiCents + o.qaCents)).toBe("11988.00");
    expect(o.meiCents + o.qaCents + o.operacionalCents).toBe(o.valorEconomicoCents);
    expect(reais(o.operacionalCents + o.qaCents)).toBe("8071.84");
  });

  it("as quantidades batem com a formação de referência", () => {
    expect(QUADRO_V14.supermercado.quantidade).toBe(24);
    expect(QUADRO_V14.demaisPosicoes.quantidade).toBe(12);
    const sm = FORMACAO_REFERENCIA.find((n) => /supermercado/i.test(n.nome))!;
    expect(sm.unidades).toBe(QUADRO_V14.supermercado.quantidade);
    for (const n of FORMACAO_REFERENCIA.filter((x) => !/supermercado/i.test(x.nome))) {
      expect(n.unidades).toBe(QUADRO_V14.demaisPosicoes.quantidade);
    }
  });

  it("a parcela QA nunca é contada como contraprestação do MEI", () => {
    for (const x of [QUADRO_V14.supermercado, QUADRO_V14.demaisPosicoes]) {
      expect(x.qaCents).toBeGreaterThan(0);
      // Pertence à SmallFlags: entra na remuneração dela, não na dos MEIs.
      expect(x.meiCents).not.toBe(x.meiCents + x.qaCents);
    }
    expect(QUADRO_V14.supermercado.qaCents).toBe(QUADRO_V14.demaisPosicoes.qaCents * 2);
  });
});

/* Seis posições, não sete ------------------------------------------------ */
describe("seis posições comerciais, não sete", () => {
  it("a formação tem seis posições e 84 unidades", () => {
    expect(FORMACAO_REFERENCIA).toHaveLength(6);
    expect(FORMACAO_REFERENCIA.reduce((s, n) => s + n.unidades, 0)).toBe(84);
  });

  it("supermercado é UM pedido comercial, apesar das duas etapas no App", () => {
    const sm = FORMACAO_REFERENCIA.filter((n) => /supermercado/i.test(n.nome));
    expect(sm).toHaveLength(1);
    // Um único quadro econômico para a posição inteira: se as duas etapas
    // operacionais do App virassem dois pedidos, o pool seria contado duas
    // vezes e o valor econômico deixaria de fechar.
    expect(
      QUADRO_V14.supermercado.meiCents +
        QUADRO_V14.supermercado.qaCents +
        QUADRO_V14.supermercado.operacionalCents
    ).toBe(QUADRO_V14.supermercado.valorEconomicoCents);
  });

  it("não há numeração de instrumento fixada no código", () => {
    // SF-0001..SF-0006 são os seis primeiros pedidos, não regra permanente.
    expect(MIG).not.toContain("'SF-0001'");
    expect(MIG).not.toContain("'SF-0006'");
    // O formato é validado; quais existem, não.
    expect(MIG).toContain("^SF-[0-9]{4}$");
  });
});

/* Migration -------------------------------------------------------------- */
describe("snapshot do instrumento no banco", () => {
  it("decompõe o pool em parcela do MEI e parcela QA", () => {
    expect(MIG).toContain("mei_consideration_cents");
    expect(MIG).toContain("smallflags_qa_cents");
    // A soma tem de fechar com o pool contratado.
    expect(MIG).toContain(
      "mei_consideration_cents + smallflags_qa_cents = contractual_pool_cents"
    );
    expect(MIG).toContain("ceo_pool_decomposition_nonneg");
  });

  it("guarda identidade, versão e hash do modelo mais o snapshot dos fatos", () => {
    for (const c of [
      "instrument_code",
      "instrument_template_version",
      "instrument_template_hash",
      "instrument_snapshot",
    ]) {
      expect(MIG).toContain(c);
    }
    expect(MIG).toContain("CREATE UNIQUE INDEX IF NOT EXISTS ceo_instrument_code_uidx");
  });

  it("depois de assinado, o instrumento é imutável por trava do banco", () => {
    expect(MIG).toContain("CREATE TRIGGER ceo_instrumento_imutavel");
    expect(MIG).toContain("BEFORE UPDATE ON public.commercial_exclusivity_orders");
    expect(MIG).toContain("IF OLD.signed_at IS NULL THEN");
    // Nenhum dos campos congelados pode mudar depois da assinatura.
    for (const c of [
      "NEW.instrument_snapshot IS DISTINCT FROM OLD.instrument_snapshot",
      "NEW.mei_consideration_cents IS DISTINCT FROM OLD.mei_consideration_cents",
      "NEW.smallflags_qa_cents IS DISTINCT FROM OLD.smallflags_qa_cents",
      "NEW.document_hash IS DISTINCT FROM OLD.document_hash",
    ]) {
      expect(MIG).toContain(c);
    }
  });

  it("colunas novas são nullable: pedidos antigos não são reescritos", () => {
    expect(MIG).not.toMatch(/mei_consideration_cents bigint[^,;]*NOT NULL/);
    expect(MIG).not.toMatch(/instrument_snapshot\s+jsonb[^,;]*NOT NULL/);
    // CHECKs entram NOT VALID: nada de revalidar linha histórica.
    const checks = MIG.match(/ADD CONSTRAINT ceo_[a-z_]+\s+CHECK/g) ?? [];
    expect(checks.length).toBeGreaterThanOrEqual(3);
    expect((MIG.match(/NOT VALID/g) ?? []).length).toBeGreaterThanOrEqual(3);
    expect(MIG).not.toMatch(/UPDATE public\.commercial_exclusivity_orders\s+SET instrument_/i);
  });

  it("a leitura do instrumento exige titular ativo e falha fechada", () => {
    expect(MIG).toContain("get_order_instrument");
    expect(MIG).toContain("'not_company_owner'");
    expect(MIG).toContain("'instrument_snapshot_missing'");
    expect(MIG).toMatch(/REVOKE EXECUTE ON FUNCTION public\.get_order_instrument\(uuid\) FROM anon/);
  });

  it("os seis instrumentos NÃO viram documentos legais públicos", () => {
    // Nada de INSERT em legal_documents: a fonte v1.4 é modelo, não publicação.
    expect(MIG).not.toMatch(/INSERT INTO public\.legal_documents/i);
    expect(MIG).not.toContain("master_agreement");
  });
});
