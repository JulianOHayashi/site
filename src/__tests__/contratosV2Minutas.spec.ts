import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Contratos V2 — publicidade visual em veículos.
 *
 * Os documentos em docs/legal/contratos-v2 são MINUTAS. Estes testes provam
 * o que elas dizem e o que NÃO podem dizer, e amarram cada campo do
 * instrumento a um fato que o servidor realmente produz. A prova em banco
 * (emissão, imutabilidade, fail-closed) está em
 * supabase/tests/280_contract_v2_vehicle_visual_advertising.sql.
 */
const RAIZ = resolve(__dirname, "../..");
const ler = (p: string) => readFileSync(resolve(RAIZ, p), "utf8");
const DIR = "docs/legal/contratos-v2";
const MESTRE = ler(`${DIR}/01_MINUTA_ACORDO_MESTRE_V2_20261110.md`);
const TERMOS = ler(`${DIR}/02_MINUTA_TERMOS_PEDIDO_COMERCIAL_V2_20261110.md`);
const INSTR = ler(`${DIR}/03_MINUTA_INSTRUMENTO_INDIVIDUAL_V2_20261110.md`);
const ANEXO = ler(`${DIR}/04_ANEXO_TECNICO_BANDEIRA_PRELIMINAR_20261110.md`);
const MATRIZ = ler(`${DIR}/05_MATRIZ_REGULATORIA_GRANDE_VITORIA_20261110.md`);
const MIGRATION = ler("supabase/migrations/20261110120000_contract_v2_vehicle_visual_advertising.sql");
const CONTRATUAIS = { MESTRE, TERMOS, INSTR };

/** Fatos que o construtor do snapshot (versão desta migration) emite. */
function fatosDoServidor(): Set<string> {
  const corpo = MIGRATION.slice(
    MIGRATION.indexOf("CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot")
  );
  const chaves = new Set<string>();
  for (const m of corpo.matchAll(/'([a-z_]+)',\s*(?:v_|coalesce|pg_catalog)/g)) chaves.add(m[1]);
  // Campos do próprio pedido emitido (não do snapshot): código e hash.
  chaves.add("instrument_code");
  chaves.add("instrument_snapshot_hash");
  return chaves;
}
const campos = (doc: string) => [...doc.matchAll(/\{\{([a-z_]+)\}\}/g)].map((m) => m[1]);
const frases = (doc: string) =>
  doc.split(/\n|(?<=[.;:])\s+/).map((s) => s.trim()).filter(Boolean);
/** Texto corrido: sem negrito markdown e sem quebras de linha. */
const corrido = (doc: string) => doc.replace(/\*\*/g, "").replace(/\s+/g, " ");
/** Blocos (parágrafo + lista que o segue) separados por linha em branco. */
const blocos = (doc: string) => doc.split(/\n\s*\n/).map(corrido);

describe("Contratos V2 — natureza dos documentos", () => {
  it.each(Object.entries(CONTRATUAIS))("%s é minuta não assinável e não publicável", (_, doc) => {
    expect(doc.split("\n")[0]).toMatch(/MINUTA — NÃO ASSINAR — NÃO PUBLICAR — SUJEITA A REVISÃO JURÍDICA/);
  });
  it("anexo técnico e matriz são preliminares, sem aprovação", () => {
    expect(ANEXO.split("\n")[0]).toMatch(/PRELIMINAR — NÃO APROVADO — SEM VALOR DE HOMOLOGAÇÃO/);
    expect(MATRIZ).toMatch(/análise de conformidade PENDENTE de validação especializada/);
    expect(MATRIZ).toMatch(/\*\*não declara\*\*/);
  });
});

describe("Contratos V2 — objeto: publicidade visual com bandeira sobre veículo", () => {
  it.each(Object.entries(CONTRATUAIS))("%s descreve bandeira publicitária visual sobre veículo", (_, doc) => {
    expect(doc).toMatch(/bandeira publicitária/i);
    expect(doc).toMatch(/visual/i);
    expect(doc).toMatch(/sobre (?:o )?ve[íi]culos?/i);
  });

  it.each(Object.entries(CONTRATUAIS))(
    "%s menciona som/alto-falante só em bloco de EXCLUSÃO do objeto",
    (_, doc) => {
      const sonoros = blocos(doc).filter((b) => /sonor|alto-falante|carro de som|áudio/i.test(b));
      expect(sonoros.length).toBeGreaterThan(0);
      for (const b of sonoros) {
        expect(b).toMatch(/não (?:compreende|inclui|é)|exclusivamente visual|sem som|nunca/i);
      }
    }
  );

  it("anexo técnico define a peça como exclusivamente visual, sem som", () => {
    expect(corrido(ANEXO)).toMatch(/Exclusivamente visual \(sem som, luz ou tela\)/);
  });
});

describe("Contratos V2 — dimensões são referência, não homologação", () => {
  it.each(Object.entries({ ...CONTRATUAIS, ANEXO }))("%s trata 49 × 30,5 cm como referência", (_, doc) => {
    expect(doc).toMatch(/490 mm|49 cm|artwork_reference_width_mm/);
    expect(doc).toMatch(/refer[êe]ncia/i);
    expect(corrido(doc)).toMatch(/n[ãa]o (?:equivale a|é) homologa|sem valor de homologa/i);
  });

  it("nenhum documento afirma que a bandeira já está homologada, aprovada ou autorizada", () => {
    // Afirmações sobre o ESTADO ATUAL; definições condicionais ("versão que
    // foi aprovada por…") não são afirmação de que exista aprovação.
    const afirmacao = /\b(?:já foi|já foram|já está|já estão|está|estão|foi|foram)\s+(?:homologad|certificad|autorizad)|\bé legal\b|\bé permitid[ao]\b/i;
    for (const doc of [MESTRE, TERMOS, INSTR, ANEXO, MATRIZ]) {
      for (const f of frases(corrido(doc).replace(/(?<=[.;:])\s+/g, "\n"))
        .filter((x) => afirmacao.test(x))
        .filter((x) => /bandeira|suporte|conjunto|instala|especificação|circula/i.test(x))) {
        expect(f).toMatch(/\b(?:não|nada|nenhum|nunca|sem)\b/i);
      }
    }
  });
});

describe("Contratos V2 — individualização vem do servidor", () => {
  const fatos = fatosDoServidor();

  it("todo campo do instrumento é um fato emitido pelo servidor", () => {
    const usados = campos(INSTR);
    expect(usados.length).toBeGreaterThan(30);
    expect(usados.filter((c) => !fatos.has(c))).toEqual([]);
  });

  it("todo campo citado nos Termos também é fato do servidor", () => {
    expect(campos(TERMOS).filter((c) => !fatos.has(c))).toEqual([]);
  });

  it("instrumento preserva região, exclusividade, posição, atividade efetiva, quantidade e valores", () => {
    for (const c of [
      "region_name", "region_id", "exclusivity_sequence_number", "exclusivity_id", "position_code",
      "effective_activity_identity", "nominal_quantity", "exclusivity_period_days",
      "economic_value_cents", "mei_consideration_cents", "smallflags_qa_cents",
      "smallflags_main_fee_cents", "smallflags_total_remuneration_cents",
      "total_monetary_funding_required_cents", "participation_value_cents", "benefit_settlement_mode",
    ]) {
      expect(campos(INSTR)).toContain(c);
    }
  });

  it("nenhum valor monetário é fixado no texto", () => {
    for (const doc of Object.values(CONTRATUAIS)) expect(doc).not.toMatch(/R\$\s*\d/);
  });

  it("formação de seis posições e 84 unidades preservada", () => {
    for (const doc of [MESTRE, INSTR]) {
      expect(corrido(doc)).toMatch(/seis posições/);
      expect(corrido(doc)).toMatch(/84 unidades/);
    }
    expect(MESTRE).toMatch(/Supermercado com 24/);
  });

  it("versão e hash do Acordo Mestre, do modelo e do instrumento identificados", () => {
    for (const c of [
      "master_agreement_version", "master_document_hash", "master_legal_document_id",
      "instrument_template_code", "instrument_template_version", "instrument_template_source_hash",
      "instrument_code", "instrument_snapshot_hash",
      "advertising_spec_code", "advertising_spec_version", "advertising_spec_source_hash",
    ]) {
      expect(campos(INSTR)).toContain(c);
    }
  });
});

describe("Contratos V2 — fidelização e segmento", () => {
  it("instrumento distingue fidelizado de não fidelizado e cita a recusa do servidor", () => {
    expect(INSTR).toMatch(/\*\*Pedido não fidelizado\*\*/);
    expect(INSTR).toMatch(/\*\*Pedido fidelizado:\*\*/);
    expect(INSTR).toMatch(/commercial_instrument_template_fidelity_mismatch/);
    expect(campos(INSTR)).toContain("fidelized");
  });

  it("segmento usa a classificação congelada, nunca o nome comercial", () => {
    expect(corrido(INSTR)).toMatch(/segment:<classificação>/);
    expect(corrido(INSTR)).toMatch(/snapshot congelado/);
    expect(corrido(INSTR)).toMatch(/mesma classificação são a mesma atividade/);
    expect(corrido(INSTR)).toMatch(/distinção entre atividades nunca é feita pelo nome/);
    expect(corrido(MESTRE)).toMatch(/Nomes comerciais diferentes da mesma classificação são a mesma atividade/);
  });

  it("segmento e Outros continuam bloqueados até a decisão jurídica (D9)", () => {
    expect(INSTR).toMatch(/commercial_instrument_segment_activity_unavailable/);
    expect(corrido(MESTRE)).toMatch(/contratos de segmento e de Outros permanecem bloqueados/);
  });
});

describe("Contratos V2 — matriz regulatória", () => {
  const municipios = ["Vitória", "Vila Velha", "Serra", "Cariacica", "Viana"];
  it.each(municipios)("%s tem matriz própria com todos os campos", (m) => {
    const ini = MATRIZ.indexOf(`### B.${municipios.indexOf(m) + 1} ${m}`);
    expect(ini).toBeGreaterThan(0);
    const fim = MATRIZ.indexOf("\n### ", ini + 5);
    const sec = MATRIZ.slice(ini, fim > 0 ? fim : MATRIZ.indexOf("\n## C.", ini));
    for (const campo of ["Norma e fonte", "Órgão competente", "Procedimento", "Situação",
                         "Evidências necessárias", "Restrições relevantes"]) {
      expect(sec).toContain(campo);
    }
    expect(sec).toMatch(/\*\*(LIDO|IDENTIFICADO|PENDENTE)/);
    expect(sec).toMatch(/https:\/\//);
  });
  it("fontes federais citadas, com links", () => {
    expect(MATRIZ).toMatch(/Lei nº 9\.503\/1997/);
    expect(MATRIZ).toMatch(/Resolução Contran nº 916\/2022/);
    expect(MATRIZ).toMatch(/planalto\.gov\.br\/ccivil_03\/leis\/l9503compilado\.htm/);
    expect(MATRIZ).toMatch(/resolucao-contran-no-916-de-28-de-marco-de-2022/);
  });
});

describe("Contratos V2 — a migration preparatória não ativa nada", () => {
  it("não publica documento, não cria aceite, não cria nem promove modelo, não aprova especificação", () => {
    expect(MIGRATION).not.toMatch(/INSERT INTO public\.legal_documents/i);
    expect(MIGRATION).not.toMatch(/INSERT INTO public\.legal_acceptances/i);
    expect(MIGRATION).not.toMatch(/INSERT INTO public\.commercial_instrument_templates/i);
    expect(MIGRATION).not.toMatch(/UPDATE public\.commercial_instrument_templates/i);
    expect(MIGRATION).not.toMatch(/INSERT INTO public\.commercial_advertising_specs/i);
    expect(MIGRATION).not.toMatch(/admin_publish_legal_document\s*\(/);
  });

  it("não toca preço, reserva, pagamento, provisionamento ou benefícios do App", () => {
    const recriadas = [...MIGRATION.matchAll(/CREATE (?:OR REPLACE )?FUNCTION public\.([a-z_]+)/g)].map((m) => m[1]);
    expect(recriadas.sort()).toEqual([
      "commercial_advertising_specs_protect",
      "commercial_build_instrument_snapshot",
      "commercial_order_effective_activity",
    ]);
    expect(MIGRATION).not.toMatch(/commercial_pricing_schedule\s+(SET|VALUES)|INSERT INTO public\.commercial_pricing|UPDATE public\.commercial_(?:pricing|checkout|exclusivity_orders|niches)/i);
  });

  it("o bloqueio D9 continua antes dos fatos V2", () => {
    const corpo = MIGRATION.slice(
      MIGRATION.indexOf("CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot"));
    const d9 = corpo.indexOf("'commercial_instrument_segment_activity_unavailable'");
    const v2 = corpo.indexOf("'commercial_advertising_spec_not_approved'");
    expect(d9).toBeGreaterThan(0);
    expect(v2).toBeGreaterThan(d9);
  });
});
