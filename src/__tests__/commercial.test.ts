/**
 * Testes locais da Fase 1 comercial (sem framework novo; funções puras).
 * Rodar via esbuild + node. Cobre:
 *   • Seção 26 — normalização/resolução territorial (ESPELHO local do SQL).
 *   • Seções 27/8–11 — validação de respostas (parser real), incluindo os
 *     cenários adicionais da correção pré-migration.
 *   • Seção 28 — slugs públicos e conversão de rota (funções reais).
 */
import {
  parseFormationResponse,
  CommercialError,
} from "../services/commercialResponse";
import {
  slugByCode,
  nicheCodeFromSlug,
  canonicalSlugFromLegacy,
  NICHE_SLUG_BY_CODE,
} from "../domain/commercial/niches";
import type { CommercialNicheCode } from "../domain/commercial/types";

let pass = 0;
let fail = 0;
const results: string[] = [];
function check(name: string, cond: boolean) {
  if (cond) {
    pass++;
    results.push(`PASS  ${name}`);
  } else {
    fail++;
    results.push(`FAIL  ${name}`);
  }
}
function expectUnexpected(name: string, data: unknown) {
  try {
    parseFormationResponse(data);
    check(name + " → unexpected_response", false);
  } catch (e) {
    check(
      name + " → unexpected_response",
      e instanceof CommercialError && e.kind === "unexpected_response"
    );
  }
}

// ===========================================================================
// Seção 26 — ESPELHO local da normalização/resolução do SQL
// ===========================================================================
const ACC_FROM = "áàâãäéèêëíìîïóòôõöúùûüç";
const ACC_TO = "aaaaaeeeeiiiiooooouuuuc";
function cityKey(city: string): string {
  const lowered = (city ?? "").trim().toLowerCase();
  let translated = "";
  for (const ch of lowered) {
    const i = ACC_FROM.indexOf(ch);
    translated += i >= 0 ? ACC_TO[i] : ch;
  }
  return translated.replace(/\s+/g, "-");
}
const UFS27 = new Set(
  "AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO".split(
    " "
  )
);
function isValidUf(uf: string): boolean {
  return UFS27.has((uf ?? "").trim().toUpperCase());
}
const SEED: Record<string, string> = {};
for (const c of ["Vitória", "Vila Velha", "Serra", "Cariacica", "Viana"]) {
  SEED[`ES|${cityKey(c)}`] = "Grande Vitória";
}
type Resolve = { ok: boolean; reason?: string; region?: string };
function resolveRegion(uf: string, city: string): Resolve {
  if (!isValidUf(uf)) return { ok: false, reason: "invalid_uf" };
  const key = cityKey(city);
  if (key.length === 0) return { ok: false, reason: "empty_city" };
  const region = SEED[`${uf.trim().toUpperCase()}|${key}`];
  return region ? { ok: true, region } : { ok: false, reason: "no_match" };
}

for (const v of ["Vitória", "VITÓRIA", "Vitoria", "vitória"]) {
  const r = resolveRegion("ES", v);
  check(`ES + ${v} → Grande Vitória`, r.ok && r.region === "Grande Vitória");
}
for (const c of ["Vila Velha", "Serra", "Cariacica", "Viana"]) {
  const r = resolveRegion("ES", c);
  check(`ES + ${c} → Grande Vitória`, r.ok && r.region === "Grande Vitória");
}
check("ES + Guarapari → não resolve", !resolveRegion("ES", "Guarapari").ok);
check("RJ + Vitória → não resolve", !resolveRegion("RJ", "Vitória").ok);
check(
  "XX + Vitória → UF inválida",
  resolveRegion("XX", "Vitória").reason === "invalid_uf"
);
check("UF vazia → rejeitada", resolveRegion("", "Vitória").reason === "invalid_uf");
check("cidade vazia → rejeitada", resolveRegion("ES", "").reason === "empty_city");

// ===========================================================================
// Seção 28 — slugs públicos (funções reais)
// ===========================================================================
check(
  "slugByCode(womens_clothing) = womens-clothing",
  slugByCode("womens_clothing") === "womens-clothing"
);
check(
  "nicheCodeFromSlug(womens-clothing) = womens_clothing",
  nicheCodeFromSlug("womens-clothing") === "womens_clothing"
);
check(
  "nicheCodeFromSlug(supermarket) = supermarket",
  nicheCodeFromSlug("supermarket") === "supermarket"
);
check(
  "nicheCodeFromSlug(womens_clothing) = null (underscore não canônico)",
  nicheCodeFromSlug("womens_clothing") === null
);
check(
  "nicheCodeFromSlug(codigo-invalido) = null",
  nicheCodeFromSlug("codigo-invalido") === null
);
check(
  "canonicalSlugFromLegacy(womens_clothing) = womens-clothing",
  canonicalSlugFromLegacy("womens_clothing") === "womens-clothing"
);
check(
  "canonicalSlugFromLegacy(womens-clothing) = null (já canônico)",
  canonicalSlugFromLegacy("womens-clothing") === null
);
check(
  "canonicalSlugFromLegacy(supermarket) = null (já canônico)",
  canonicalSlugFromLegacy("supermarket") === null
);
check(
  "canonicalSlugFromLegacy(codigo_invalido) = null",
  canonicalSlugFromLegacy("codigo_invalido") === null
);
(Object.keys(NICHE_SLUG_BY_CODE) as CommercialNicheCode[]).forEach((code) => {
  check(`round-trip ${code}`, nicheCodeFromSlug(slugByCode(code)) === code);
});

// ===========================================================================
// Parser — base válida completa (com ids) e validações (seções 8–11)
// ===========================================================================
type Opp = {
  id: string;
  exclusivity_id: string;
  niche_code: string;
  display_name: string;
  contracted_quantity: number;
  status: string;
  sort_order: number;
};
function validBase() {
  return {
    region_available: true,
    region: {
      region_id: "r1",
      region_name: "Grande Vitória",
      region_slug: "grande-vitoria",
      uf: "ES",
      city_name: "Vitória",
      is_active: true,
    },
    exclusivity_available: true,
    exclusivity: {
      id: "e1",
      region_id: "r1",
      sequence_number: 1,
      status: "forming",
      is_current: true,
      planned_start_at: null,
    },
    summary: {
      total_opportunities: 6,
      contracted_opportunities: 0,
      total_units: 84,
      contracted_units: 0,
      formation_percent: 0,
      is_complete: false,
    },
    opportunities: [
      { id: "o1", exclusivity_id: "e1", niche_code: "supermarket", display_name: "Supermercado", contracted_quantity: 24, status: "available", sort_order: 1 },
      { id: "o2", exclusivity_id: "e1", niche_code: "pharmacy", display_name: "Farmácia", contracted_quantity: 12, status: "available", sort_order: 2 },
      { id: "o3", exclusivity_id: "e1", niche_code: "womens_clothing", display_name: "Roupas femininas", contracted_quantity: 12, status: "available", sort_order: 3 },
      { id: "o4", exclusivity_id: "e1", niche_code: "mens_clothing", display_name: "Roupas masculinas", contracted_quantity: 12, status: "available", sort_order: 4 },
      { id: "o5", exclusivity_id: "e1", niche_code: "womens_footwear", display_name: "Calçados femininos", contracted_quantity: 12, status: "available", sort_order: 5 },
      { id: "o6", exclusivity_id: "e1", niche_code: "mens_footwear", display_name: "Calçados masculinos", contracted_quantity: 12, status: "available", sort_order: 6 },
    ] as Opp[],
  };
}

// positivo
try {
  const r = parseFormationResponse(validBase());
  check(
    "resposta válida parseia (6 opps, total 84)",
    r.regionAvailable &&
      r.exclusivityAvailable &&
      r.opportunities.length === 6 &&
      r.summary!.totalUnits === 84
  );
} catch {
  check("resposta válida parseia (6 opps, total 84)", false);
}

// estados de ausência VÁLIDOS (não lançam)
check("region_available:false → estado válido", (() => {
  const r = parseFormationResponse({ region_available: false });
  return !r.regionAvailable && r.opportunities.length === 0;
})());
check("exclusivity_available:false → estado válido", (() => {
  const r = parseFormationResponse({
    region_available: true,
    region: validBase().region,
    exclusivity_available: false,
  });
  return r.regionAvailable && !r.exclusivityAvailable;
})());

// --- flags de disponibilidade exigem booleano REAL → unexpected_response ---
expectUnexpected("region_available ausente", { region: validBase().region });
expectUnexpected("region_available como string", {
  region_available: "true",
  region: validBase().region,
});
expectUnexpected("region_available como número", {
  region_available: 1,
  region: validBase().region,
});
expectUnexpected("exclusivity_available ausente (region_available=true)", {
  region_available: true,
  region: validBase().region,
});
expectUnexpected("exclusivity_available como string", {
  region_available: true,
  region: validBase().region,
  exclusivity_available: "true",
});
expectUnexpected("exclusivity_available como número", {
  region_available: true,
  region: validBase().region,
  exclusivity_available: 1,
});

// --- inconsistências originais → unexpected_response ---
let b = validBase();
b.opportunities = b.opportunities.slice(0, 5);
expectUnexpected("5 oportunidades", b);

b = validBase();
b.opportunities.push({ ...b.opportunities[0], id: "o7" });
expectUnexpected("7 oportunidades", b);

b = validBase();
b.opportunities[1].niche_code = "supermarket";
b.opportunities[1].contracted_quantity = 24;
b.opportunities[1].sort_order = 1;
expectUnexpected("nicho duplicado", b);

b = validBase();
b.opportunities[0].niche_code = "bakery";
expectUnexpected("nicho desconhecido", b);

b = validBase();
b.opportunities[0].contracted_quantity = 12;
expectUnexpected("supermercado com 12", b);

b = validBase();
b.opportunities[1].contracted_quantity = 24;
expectUnexpected("farmácia com 24", b);

b = validBase();
b.opportunities[0].contracted_quantity = 12; // soma 72
expectUnexpected("total 72", b);

b = validBase();
b.opportunities[0].contracted_quantity = 36; // soma 96
expectUnexpected("total 96", b);

b = validBase();
b.opportunities[0].contracted_quantity = 24.5;
expectUnexpected("quantidade decimal", b);

b = validBase();
b.opportunities[0].contracted_quantity = -12;
expectUnexpected("quantidade negativa", b);

b = validBase();
b.opportunities[0].status = "pendente";
expectUnexpected("status desconhecido", b);

b = validBase();
b.summary.contracted_opportunities = 6; // cards continuam available
expectUnexpected("resumo diz 6 contratados com cards disponíveis", b);

b = validBase();
b.summary.is_complete = true; // sem os 6 nichos contratados
expectUnexpected("formação completa sem os seis nichos", b);

// --- NOVOS cenários (seção 12) → unexpected_response ---
b = validBase();
b.region.region_name = "";
expectUnexpected("region_name vazio", b);

b = validBase();
b.region.region_slug = "";
expectUnexpected("region_slug vazio", b);

b = validBase();
b.region.uf = "XX";
expectUnexpected("UF XX", b);

b = validBase();
b.region.is_active = false;
expectUnexpected("região inativa", b);

b = validBase();
b.exclusivity.is_current = false;
expectUnexpected("exclusividade não atual", b);

b = validBase();
b.opportunities[2].display_name = "";
expectUnexpected("oportunidade com nome vazio", b);

b = validBase();
b.opportunities[1].sort_order = 3; // repete a ordem 3 (womens_clothing também 3)
expectUnexpected("sort_order repetido", b);

b = validBase();
b.opportunities[0].sort_order = 2; // supermarket deveria ser 1
expectUnexpected("ordem incorreta para o nicho", b);

b = validBase();
b.summary.formation_percent = 99; // 0 contratados, percent 99
expectUnexpected("percentual 99 com zero contratados", b);

b = validBase();
b.opportunities[0].status = "contracted";
b.opportunities[1].status = "contracted";
b.opportunities[2].status = "contracted";
b.summary.contracted_opportunities = 3;
b.summary.contracted_units = 48; // 24+12+12
b.summary.formation_percent = 10; // esperado 50
expectUnexpected("percentual incoerente com os cards", b);

b = validBase();
b.exclusivity.region_id = "OUTRA";
expectUnexpected("região da exclusividade divergente", b);

b = validBase();
b.exclusivity.id = "";
expectUnexpected("identificador vazio", b);

// ===========================================================================
// Saída
// ===========================================================================
console.log(results.join("\n"));
console.log(`\nTOTAL: ${pass} PASS / ${fail} FAIL`);
if (fail > 0) {
  throw new Error(`${fail} teste(s) falharam`);
}
