import { describe, it, expect } from "vitest";
import {
  readFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  symlinkSync,
} from "node:fs";
import { dirname, resolve, normalize, join, relative } from "node:path";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

/**
 * FRONTEIRA ESM DO NODE NA VERCEL.
 *
 * O QUE ESTE TESTE GUARDA
 * O repositório é ESM (`"type": "module"`) e o TypeScript resolve com
 * `moduleResolution: "bundler"`, que aceita especificador relativo SEM
 * extensão. O Node nativo NÃO aceita. A Vercel emite a função como
 * `validate.js` e a executa com o resolvedor do Node — então um import
 * extensionless que passa no typecheck, passa no build e passa em todo teste
 * de lógica explode em produção com ERR_MODULE_NOT_FOUND.
 *
 * Foi exatamente o que aconteceu: o Preview subiu, a função crashou antes do
 * handler responder, e nenhum teste de negócio tinha como perceber. Por isso
 * a asserção aqui é sobre o ESPECIFICADOR, não sobre comportamento.
 *
 * ESCOPO
 * Apenas o grafo de runtime da função serverless, percorrido a partir do
 * ponto de entrada. Não é varredura do repositório: código de navegador é
 * empacotado pelo Vite, que resolve extensionless sem problema, e proibir lá
 * seria ruído.
 */

const RAIZ = resolve(__dirname, "../..");

/**
 * Toda função serverless entra aqui. Acrescentar um endpoint e esquecer esta
 * lista reproduziria o defeito original numa rota nova.
 */
const ENTRADAS = [
  "api/benefit-usage/validate.ts",
  "api/gate-d-probe.ts",
] as const;
const ENTRADA = ENTRADAS[0];

/** Import/export relativo, incluindo `import type` e side-effect import. */
const RE_FROM = /^[ \t]*(?:import|export)\b[^;]*?from\s+["'](\.[^"']+)["']/gm;
const RE_SIDE = /^[ \t]*import\s+["'](\.[^"']+)["']/gm;

function semComentarios(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^[ \t]*\/\/.*$/gm, "");
}

function especificadores(src: string): string[] {
  const limpo = semComentarios(src);
  const achados = new Set<string>();
  for (const re of [RE_FROM, RE_SIDE]) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(limpo)) !== null) achados.add(m[1]);
  }
  return [...achados];
}

/** Resolve o especificador `.js` de volta para o `.ts` que o origina. */
function resolverParaFonte(deArquivo: string, spec: string): string | null {
  const base = normalize(join(dirname(deArquivo), spec));
  const semJs = base.replace(/\.js$/, "");
  for (const cand of [base, `${semJs}.ts`, `${semJs}.tsx`, `${base}.ts`]) {
    if (existsSync(resolve(RAIZ, cand))) return cand;
  }
  return null;
}

type Aresta = { de: string; spec: string; para: string | null };

function percorrerGrafo(
  entradas: readonly string[] = ENTRADAS
): { modulos: string[]; arestas: Aresta[] } {
  const vistos = new Set<string>();
  const arestas: Aresta[] = [];
  const fila = [...entradas];
  while (fila.length > 0) {
    const atual = fila.shift() as string;
    if (vistos.has(atual)) continue;
    vistos.add(atual);
    const src = readFileSync(resolve(RAIZ, atual), "utf8");
    for (const spec of especificadores(src)) {
      const para = resolverParaFonte(atual, spec);
      arestas.push({ de: atual, spec, para });
      if (para && /\.tsx?$/.test(para)) fila.push(para);
    }
  }
  return { modulos: [...vistos].sort(), arestas };
}

describe("fronteira ESM do Node na função serverless", () => {
  const { modulos, arestas } = percorrerGrafo();

  it("todo ponto de entrada declarado existe", () => {
    for (const e of ENTRADAS) {
      expect(existsSync(resolve(RAIZ, e)), e).toBe(true);
    }
  });

  it("a sonda temporaria do Gate D esta no grafo auditado", () => {
    expect(modulos).toContain("api/gate-d-probe.ts");
    expect(modulos).toContain("src/server/gateD/gateDProbe.ts");
  });

  it("nenhum segmento de caminho de entrada comeca com sublinhado", () => {
    // A Vercel trata arquivo/pasta com sublinhado na frente como auxiliar e
    // NAO o transforma em funcao: a rota devolve o 404 de plataforma e o
    // handler nunca roda. Foi exatamente o que aconteceu com
    // api/_internal/gate-d-probe.ts.
    for (const e of ENTRADAS) {
      for (const seg of e.split("/")) {
        expect(seg.startsWith("_"), `${e} :: '${seg}'`).toBe(false);
      }
    }
  });

  it("a entrada do Gate D fica DIRETO em api/, sem subpasta", () => {
    const gateD = ENTRADAS.filter((e) => e.includes("gate-d"));
    expect(gateD).toEqual(["api/gate-d-probe.ts"]);
    expect(gateD[0].split("/")).toHaveLength(2);
    expect(existsSync(resolve(RAIZ, "api/_internal"))).toBe(false);
  });

  it("o grafo de runtime é percorrido por inteiro, não só o primeiro nível", () => {
    // Se o percurso parasse na entrada, o teste daria falso verde: foi um
    // import de segundo nível que quebrou em producao.
    expect(modulos.length).toBeGreaterThanOrEqual(5);
    expect(modulos).toContain(ENTRADA);
    expect(modulos).toContain("src/server/benefitUsage/benefitUsageContract.ts");
    expect(modulos).toContain("src/server/benefitUsage/benefitUsageGatewayClient.ts");
    expect(modulos).toContain("src/server/benefitUsage/validateHandler.ts");
    expect(modulos).toContain("src/server/provisioning/gatewaySigner.ts");
  });

  it("NENHUM import relativo do grafo de runtime é extensionless", () => {
    // Esta é a asserção que teria falhado em 21a774.
    const ruins = arestas.filter((a) => !/\.(js|mjs|json)$/.test(a.spec));
    expect(
      ruins.map((a) => `${a.de} -> '${a.spec}'`),
      "especificador relativo sem extensão quebra o resolvedor ESM do Node"
    ).toEqual([]);
  });

  it("todo especificador .js resolve para um módulo de origem existente", () => {
    const orfaos = arestas.filter((a) => a.para === null);
    expect(orfaos.map((a) => `${a.de} -> '${a.spec}'`)).toEqual([]);
  });

  it("não foram introduzidos especificadores .ts de runtime", () => {
    const ts = arestas.filter((a) => /\.tsx?$/.test(a.spec));
    expect(ts.map((a) => a.spec)).toEqual([]);
  });

  it("o grafo de runtime não arrasta código de navegador", () => {
    // Uma pagina ou componente no grafo significaria React dentro da funcao.
    const cliente = modulos.filter(
      (m) => m.startsWith("src/pages/") || m.startsWith("src/components/")
    );
    expect(cliente).toEqual([]);
  });

  it("emitido como ESM de verdade, o Node importa o grafo sem ERR_MODULE_NOT_FOUND", () => {
    // Prova mais forte que o regex: transpila o grafo para .js com o esbuild
    // que o Vite ja traz, monta o layout de diretorios que a Vercel usa, e
    // pede ao Node para importar o ponto de entrada. Sem deploy, sem rede,
    // sem segredo — o handler nem chega a ser chamado.
    const esbuild = resolve(RAIZ, "node_modules/.bin/esbuild");
    if (!existsSync(esbuild)) return; // ambiente sem esbuild: regex ja cobriu

    const dir = mkdtempSync(join(tmpdir(), "esm-guard-"));
    for (const m of modulos) {
      const destino = join(dir, m.replace(/\.tsx?$/, ".js"));
      mkdirSync(dirname(destino), { recursive: true });
      // `--loader=ts` sem ponto so vale para stdin; lendo arquivo, o esbuild
      // infere o loader pela extensao.
      const js = execFileSync(
        esbuild,
        [resolve(RAIZ, m), "--format=esm", "--platform=node"],
        { encoding: "utf8" }
      );
      writeFileSync(destino, js);
    }
    // A funcao roda como ESM: sem package.json type=module, o Node trataria
    // .js como CommonJS e o teste nao provaria nada.
    writeFileSync(join(dir, "package.json"), JSON.stringify({ type: "module" }));
    // Imports de PACOTE (@supabase/supabase-js, node:crypto) precisam
    // resolver como resolveriam na Vercel, senao o teste acusaria um
    // ERR_MODULE_NOT_FOUND que nao tem nada a ver com o defeito auditado.
    symlinkSync(resolve(RAIZ, "node_modules"), join(dir, "node_modules"), "dir");

    for (const entrada of ENTRADAS) {
      importarComoNode(dir, entrada);
    }
  });
});

function importarComoNode(dir: string, entrada: string): void {
    const alvo = pathToFileURL(
      join(dir, entrada.replace(/\.ts$/, ".js"))
    ).href;
    const script =
      `import(${JSON.stringify(alvo)})` +
      `.then(m => { if (typeof m.default !== "function") { console.error("SEM_HANDLER"); process.exit(2); } ` +
      `console.log("IMPORT_OK"); })` +
      `.catch(e => { console.error((e && e.code ? e.code + " :: " : "") + (e && e.message ? e.message : String(e))); process.exit(1); });`;

    let saida: string;
    try {
      saida = execFileSync(process.execPath, ["--input-type=module", "-e", script], {
        encoding: "utf8",
        cwd: dir,
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (e) {
      const err = e as { stderr?: string; stdout?: string };
      throw new Error(
        `import ESM falhou: ${(err.stderr ?? err.stdout ?? "").trim()}`
      );
    }
    expect(saida, entrada).toContain("IMPORT_OK");
}

describe("relatório do grafo (documental)", () => {
  it("lista o grafo auditado", () => {
    const { modulos, arestas } = percorrerGrafo();
    const rel = modulos.map((m) => relative(".", m));
    expect(rel.length).toBe(modulos.length);
    expect(arestas.length).toBeGreaterThanOrEqual(7);
  });
});
