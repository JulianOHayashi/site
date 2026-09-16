import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve, join } from "node:path";

/**
 * AUDITORIA ESTÁTICA DA MIGRATION 28.
 *
 * POR QUE ESTE ARQUIVO EXISTE
 * A migration 28 continha um defeito que passou por typecheck, 631 testes,
 * dois builds e todas as varreduras: ela acrescentava
 * `ADD CONSTRAINT ceo_invariante_economica` sobre uma tabela onde a
 * constraint com esse mesmo nome já era criada por
 * 20260822124000_m2_contracts.sql. PostgreSQL recusa nome duplicado e a
 * migration inteira falharia — mas nenhuma ferramenta de TypeScript enxerga
 * isso.
 *
 * A lição não é "não repetir aquele nome". É que colisão de nome entre a
 * migration nova e as 27 históricas é uma CLASSE de defeito invisível ao
 * gate local. Este arquivo audita a classe, não o caso.
 *
 * ISTO NÃO SUBSTITUI EXECUÇÃO EM PostgreSQL. É análise de texto: pega
 * colisão de nome, não erro de sintaxe, de tipo ou de dependência.
 */

const RAIZ = process.cwd();
const DIR = resolve(RAIZ, "supabase/migrations");
const NOVA = "20260905120000_post_r16_commercial_v2.sql";

const arquivos = readdirSync(DIR).filter((f) => f.endsWith(".sql")).sort();
// "Historicas" = as que PRECEDEM a migration 28, por ordem de timestamp no
// nome. Migrations posteriores (ex.: 20260907190000) nao entram: comparar a
// 28 com algo que veio depois inverteria o sentido desta auditoria.
const historicas = arquivos.filter((f) => f < NOVA);
const ler = (f: string) => readFileSync(join(DIR, f), "utf8");
const semComentarios = (sql: string) => sql.replace(/^\s*--.*$/gm, "");

/** Nomes de constraint declarados, tanto inline quanto por ALTER TABLE. */
function constraintsDeclaradas(sql: string): string[] {
  const limpo = semComentarios(sql);
  const nomes: string[] = [];
  for (const m of limpo.matchAll(/\bCONSTRAINT\s+([a-zA-Z_][a-zA-Z0-9_]*)/g)) {
    nomes.push(m[1]);
  }
  return nomes;
}

/** Nomes que a migration nova ACRESCENTA a uma tabela já existente. */
function constraintsAdicionadas(sql: string): string[] {
  const limpo = semComentarios(sql);
  const nomes: string[] = [];
  for (const m of limpo.matchAll(/\bADD\s+CONSTRAINT\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi)) {
    nomes.push(m[1]);
  }
  return nomes;
}

describe("COMMERCIAL_V2_DUPLICATE_HISTORICAL_CONSTRAINTS", () => {
  it("o inventário histórico não está vazio (controle do próprio varredor)", () => {
    // Sem este controle, um regex quebrado devolveria zero colisões e o teste
    // passaria por não estar olhando para nada.
    expect(historicas.length).toBe(27);
    const todas = historicas.flatMap((f) => constraintsDeclaradas(ler(f)));
    expect(todas.length).toBeGreaterThan(50);
    expect(todas).toContain("ceo_invariante_economica");
  });

  it("nenhum ADD CONSTRAINT da migration 28 colide com nome histórico", () => {
    const historicos = new Set(historicas.flatMap((f) => constraintsDeclaradas(ler(f))));
    const adicionados = constraintsAdicionadas(ler(NOVA));
    expect(adicionados.length).toBeGreaterThan(0);

    const colisoes = adicionados.filter((n) => historicos.has(n));
    expect(colisoes, `colisões: ${colisoes.join(", ")}`).toEqual([]);
  });

  it("nenhum nome de constraint se repete DENTRO da migration 28", () => {
    const nomes = constraintsDeclaradas(ler(NOVA));
    const vistos = new Set<string>();
    const repetidos: string[] = [];
    for (const n of nomes) {
      if (vistos.has(n)) repetidos.push(n);
      vistos.add(n);
    }
    expect(repetidos, `repetidos: ${repetidos.join(", ")}`).toEqual([]);
  });

  it("a invariante econômica continua sendo imposta pela constraint histórica", () => {
    const hist = ler("20260822124000_m2_contracts.sql");
    expect(hist).toContain("CONSTRAINT ceo_invariante_economica");
    expect(hist).toMatch(
      /economic_value_cents\s*=\s*contractual_pool_cents\s*\+\s*bdflow_due_cents/
    );
    // A migration 28 não a recria, não a renomeia e não a remove.
    const nova = semComentarios(ler(NOVA));
    expect(nova).not.toMatch(/ADD\s+CONSTRAINT\s+ceo_invariante_economica/i);
    expect(nova).not.toMatch(/DROP\s+CONSTRAINT\s+ceo_invariante_economica/i);
    expect(nova).not.toMatch(/RENAME\s+CONSTRAINT\s+ceo_invariante_economica/i);
  });

  it("a migration 28 não solta nem renomeia constraint histórica alguma", () => {
    const historicos = new Set(historicas.flatMap((f) => constraintsDeclaradas(ler(f))));
    const nova = semComentarios(ler(NOVA));
    for (const m of nova.matchAll(
      /\b(?:DROP|RENAME)\s+CONSTRAINT\s+(?:IF\s+EXISTS\s+)?([a-zA-Z_][a-zA-Z0-9_]*)/gi
    )) {
      expect(historicos.has(m[1]), `constraint histórica tocada: ${m[1]}`).toBe(false);
    }
  });

  it("a migration 28 não recria índice ou trigger de nome histórico", () => {
    const nomeHist = new Set<string>();
    for (const f of historicas) {
      const limpo = semComentarios(ler(f));
      for (const m of limpo.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi))
        nomeHist.add(m[1]);
      for (const m of limpo.matchAll(/CREATE\s+TRIGGER\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi))
        nomeHist.add(m[1]);
    }
    const limpoNovo = semComentarios(ler(NOVA));
    const novos: string[] = [];
    for (const m of limpoNovo.matchAll(/CREATE\s+(?:UNIQUE\s+)?INDEX\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi))
      novos.push(m[1]);
    for (const m of limpoNovo.matchAll(/CREATE\s+TRIGGER\s+([a-zA-Z_][a-zA-Z0-9_]*)/gi))
      novos.push(m[1]);
    expect(novos.length).toBeGreaterThan(0);
    const colisoes = novos.filter((n) => nomeHist.has(n));
    expect(colisoes, `colisões: ${colisoes.join(", ")}`).toEqual([]);
  });

  it("a migration 28 não cria tabela com nome já existente", () => {
    const tabHist = new Set<string>();
    for (const f of historicas) {
      for (const m of semComentarios(ler(f)).matchAll(
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.([a-zA-Z_][a-zA-Z0-9_]*)/gi
      ))
        tabHist.add(m[1]);
    }
    const novas: string[] = [];
    for (const m of semComentarios(ler(NOVA)).matchAll(
      /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.([a-zA-Z_][a-zA-Z0-9_]*)/gi
    ))
      novas.push(m[1]);
    expect(novas).toEqual(["commercial_pool_share_ratios", "commercial_checkout_intents"]);
    expect(novas.filter((n) => tabHist.has(n))).toEqual([]);
  });

  it("CREATE FUNCTION sem OR REPLACE não colide com função histórica", () => {
    // Recriar função existente sem OR REPLACE também aborta a migration.
    const fnHist = new Set<string>();
    for (const f of historicas) {
      for (const m of semComentarios(ler(f)).matchAll(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.([a-zA-Z_][a-zA-Z0-9_]*)/gi
      ))
        fnHist.add(m[1]);
    }
    const limpo = semComentarios(ler(NOVA));
    const semReplace: string[] = [];
    for (const m of limpo.matchAll(/CREATE\s+FUNCTION\s+public\.([a-zA-Z_][a-zA-Z0-9_]*)/gi))
      semReplace.push(m[1]);

    for (const nome of semReplace) {
      if (!fnHist.has(nome)) continue;
      // Colide com histórica: só é seguro se houver DROP antes na mesma migration.
      const iDrop = limpo.indexOf(`DROP FUNCTION IF EXISTS public.${nome}`);
      const iCreate = limpo.indexOf(`CREATE FUNCTION public.${nome}`);
      expect(iDrop, `${nome} recriada sem DROP prévio`).toBeGreaterThan(-1);
      expect(iDrop).toBeLessThan(iCreate);
    }
  });
});

describe("COMMERCIAL_V2_SETTLEMENT_TERMINOLOGY_CANONICAL", () => {
  const alvos = [
    join("supabase/migrations", NOVA),
    "supabase/tests/200_commercial_v2.sql",
    "src/domain/pricing/commercialV2.ts",
    "src/domain/operational/residualAllocation.ts",
    "src/pages/RevisaoContratacao.tsx",
    "src/components/commercial/PainelPreco.tsx",
    "src/components/commercial/ResumoFormacao.tsx",
  ];

  it("nenhum identificador executável usa o termo obsoleto", () => {
    for (const rel of alvos) {
      const bruto = readFileSync(resolve(RAIZ, rel), "utf8");
      // Comentários podem citar a história; código, não.
      const codigo = bruto
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .replace(/(^|[^:])\/\/.*$/gm, "$1")
        .replace(/^\s*--.*$/gm, "");
      expect(codigo, rel).not.toMatch(/benefit_fulfillment_mode/);
      expect(codigo, rel).not.toMatch(/invalid_fulfillment_mode/);
      expect(codigo, rel).not.toMatch(/fulfillment_mode/);
      // 'direct_benefit' no singular é o valor pré-canônico.
      expect(codigo, rel).not.toMatch(/["']direct_benefit["']/);
    }
  });

  it("o motivo de runtime da RPC é o canônico", () => {
    const sql = readFileSync(resolve(RAIZ, "supabase/migrations", NOVA), "utf8");
    expect(sql).toContain("'invalid_settlement_mode'");
    expect(sql).not.toContain("'invalid_fulfillment_mode'");
  });

  it("os dois valores canônicos aparecem, e só eles", () => {
    const sql = readFileSync(resolve(RAIZ, "supabase/migrations", NOVA), "utf8");
    expect(sql).toMatch(/ARRAY\['direct_benefits','cash'\]/);
    expect(sql).toContain("benefit_settlement_mode");
  });
});

describe("Auditoria estática da migration 28 — invariantes gerais", () => {
  const sql = readFileSync(resolve(RAIZ, "supabase/migrations", NOVA), "utf8");
  const codigo = semComentarios(sql);

  it("exatamente 34 migrations", () => {
    // 28 ate a Comercial V2; 20260907190000 aposenta a RPC legada;
    // 20260908120000 endurece o snapshot de provisionamento; 20260909120000
    // acrescenta a RPC de autoridade de uso de beneficio; 20260915120000
    // corrige o portao de titular e implementa a reserva de 30 minutos.
    expect(arquivos.length).toBe(34);
  });

  it("a migration 30 traz os marcadores do endurecimento V2", () => {
    const m30 = readFileSync(
      resolve(DIR, "20260908120000_commercial_v2_provisioning_snapshot_hardening.sql"),
      "utf8"
    );
    const c30 = semComentarios(m30);
    // Payload versionado e politica 2.
    expect(c30).toContain("bdflow.commercial_provisioning.v2");
    expect(c30).toContain("'distribution_policy_version', 2");
    expect(c30).toContain("'participant_target', 84");
    // Os quatro campos V2 entram na protecao de imutabilidade.
    for (const campo of [
      "benefit_settlement_mode",
      "cash_user_pool_funding_cents",
      "total_monetary_funding_required_cents",
      "benefit_distribution_policy_version",
    ]) {
      expect(c30, campo).toContain(`NEW.${campo}`);
    }
    // Falha fechada, nunca coercao silenciosa para a politica 2.
    expect(c30).toContain("incompatible_distribution_policy");
    expect(c30).toContain("stale_schema_version");
    // Minimizacao: contabilidade do lado Site NAO entra no payload.
    const payload = c30.slice(
      c30.indexOf("'partner_network_bridge_id'"),
      c30.indexOf("RETURN pg_catalog.jsonb_build_object(\n    'ok', true,")
    );
    for (const proibido of ["bdflow_due_cents", "economic_value_cents", "payment_method"]) {
      expect(payload, proibido).not.toContain(`'${proibido}'`);
    }
    // Nenhuma aritmetica monetaria de ponto flutuante.
    expect(c30).not.toMatch(/::\s*(float|double|numeric|real)/i);
    // Sem alargamento de privilegio para papeis de API.
    expect(c30).not.toMatch(/GRANT\s+EXECUTE[^;]*TO\s+anon/i);
  });

  it("nenhum ponto-base falso como autoridade executável da V2", () => {
    for (const falso of ["7178", "7177", "6678", "6677"]) {
      expect(codigo, falso).not.toContain(falso);
    }
    // A V2 grava NULL, não um número plausível.
    expect(codigo).toMatch(/NULL,\s*NULL,\s*'exact_ratio'/);
  });

  it("nenhuma aritmética monetária de ponto flutuante", () => {
    expect(codigo).not.toMatch(/::\s*(float|double|numeric|real)/i);
    expect(codigo).not.toMatch(/\bround\s*\(/i);
  });

  it("toda função nova é SECURITY DEFINER com search_path fixo", () => {
    const nomes = [...codigo.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)/gi)]
      .map((m) => m[1]);
    expect(nomes.length).toBeGreaterThan(3);
    for (const n of nomes) {
      const i = codigo.indexOf(`FUNCTION public.${n}`);
      const cabecalho = codigo.slice(i, i + 1200);
      expect(cabecalho, n).toContain("SECURITY DEFINER");
      expect(cabecalho, n).toContain("SET search_path TO 'pg_catalog'");
    }
  });

  it("nenhuma concessão de escrita direta a papéis de navegador", () => {
    const encontradas = [
      ...codigo.matchAll(
        /GRANT\s+([^;]+?)\s+ON\s+(?:TABLE\s+)?(public\.[a-zA-Z_][a-zA-Z0-9_]*)\s+TO\s+([^;]+);/gi
      ),
    ];
    // Controle do varredor: zero concessões encontradas significaria regex
    // quebrada, e o teste passaria por não estar olhando para nada.
    expect(encontradas.length).toBeGreaterThan(0);
    // `ON TABLE` é opcional em PostgreSQL: exigi-lo deixava passar
    // exatamente a concessão perigosa que este teste deve pegar.
    for (const m of codigo.matchAll(
      /GRANT\s+([^;]+?)\s+ON\s+(?:TABLE\s+)?(public\.[a-zA-Z_][a-zA-Z0-9_]*)\s+TO\s+([^;]+);/gi
    )) {
      const privilegios = m[1].toUpperCase();
      const papeis = m[3].toLowerCase();
      if (/anon|authenticated/.test(papeis)) {
        expect(privilegios, `${m[2]} -> ${m[3]}`).not.toMatch(/INSERT|UPDATE|DELETE|ALL/);
      }
    }
  });

  it("anon não executa RPC comercial que cria ou confirma compromisso", () => {
    for (const f of [
      "create_commercial_checkout_intent",
      "admin_register_manual_commercial_order",
      "admin_confirm_commercial_funding",
    ]) {
      const revoga = new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${f}[\\s\\S]{0,220}FROM anon`);
      expect(codigo, f).toMatch(revoga);
      const concede = new RegExp(`GRANT\\s+EXECUTE ON FUNCTION public\\.${f}[\\s\\S]{0,220}TO ([^;]+);`);
      const m = codigo.match(concede);
      expect(m, f).not.toBeNull();
      expect(m![1].toLowerCase(), f).not.toContain("anon");
    }
  });

  it("uma única assinatura executável de venda manual", () => {
    const criacoes = [
      ...codigo.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.admin_register_manual_commercial_order/gi),
    ];
    expect(criacoes.length).toBe(1);
    expect(codigo).toMatch(/DROP FUNCTION IF EXISTS public\.admin_register_manual_commercial_order/);
  });

  it("a V1 vira histórica e a V2 é a única ativa no estado pretendido", () => {
    expect(codigo).toMatch(/SET status = 'superseded'\s*\n\s*WHERE version = 1/);
    expect(codigo).toMatch(/\(2, 'active',/);
  });

  it("nenhuma afirmação de custódia ou repasse já executado", () => {
    for (const proibido of ["escrow", "custodia", "custódia", "segregad", "payout_executed', true"]) {
      expect(sql.toLowerCase(), proibido).not.toContain(proibido.toLowerCase());
    }
    expect(codigo).toContain("'user_payout_executed', false");
  });
});
