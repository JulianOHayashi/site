import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const forbiddenPaths = [
  "BDFlow_Portal_Owner_Manager_V2_1_1_UPLOAD_GITHUB",
  "PARA_ENVIAR_AO_GITHUB",
  "src/pages/HomeClassica.tsx",
  "src/pages/Produtos.tsx",
  "src/pages/ProdutoDetalhe.tsx",
  "src/pages/Personalizar.tsx",
  "src/pages/Checkout.tsx",
  "src/components/ShirtPreview.tsx",
  "src/data/mockProducts.ts",
  "src/data/mockOrders.ts",
  "supabase/schema.sql",
  "supabase/site-schema-v2.sql",
];

const forbiddenText = [
  ["package.json", '"name": "camisas-es"'],
  ["index.html", "Camisas que contam a sua marca"],
  ["src/App.tsx", 'element={<HomeClassica />}'],
  ["src/App.tsx", 'element={<Produtos />}'],
  ["src/App.tsx", 'element={<Checkout />}'],
  ["src/pages/Admin.tsx", "mockOrders"],
  ["src/pages/Admin.tsx", "useProducts"],
];

const failures = [];

for (const path of forbiddenPaths) {
  if (existsSync(path)) failures.push(`caminho legado presente: ${path}`);
}

for (const [path, token] of forbiddenText) {
  const content = readFileSync(path, "utf8");
  if (content.includes(token)) {
    failures.push(`texto legado em ${path}: ${token}`);
  }
}

// ---------------------------------------------------------------------------
// M2/R3 — nenhum CÓDIGO VIVO pode consultar tabelas ausentes do schema
// canônico. Comentários explicativos são permitidos; chamadas não.
// A varredura remove comentários antes de procurar, e o controle positivo
// abaixo prova que o scanner realmente detecta o padrão proibido.
// ---------------------------------------------------------------------------
const TABELAS_INEXISTENTES = ["site_partner_members", "site_monthly_partners"];

function semComentarios(codigo) {
  return codigo
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
}

function consultasProibidas(codigo) {
  const limpo = semComentarios(codigo);
  const achados = [];
  for (const tabela of TABELAS_INEXISTENTES) {
    const padrao = new RegExp(`\\.from\\(\\s*["'\`]${tabela}["'\`]`, "g");
    if (padrao.test(limpo)) achados.push(tabela);
  }
  return achados;
}

function varrer(dir, aoAchar) {
  for (const entrada of readdirSync(dir)) {
    const caminho = join(dir, entrada);
    if (statSync(caminho).isDirectory()) varrer(caminho, aoAchar);
    else if (/\.(ts|tsx|js|jsx|mjs)$/.test(entrada)) {
      aoAchar(caminho, readFileSync(caminho, "utf8"));
    }
  }
}

// CONTROLE POSITIVO: o scanner precisa acusar um alvo plantado.
const alvoPlantado = `const q = supabase.from("site_partner_members").select("*");`;
if (consultasProibidas(alvoPlantado).length !== 1) {
  failures.push(
    "controle positivo falhou: o scanner de tabelas inexistentes nao detecta o padrao proibido"
  );
}
// E precisa IGNORAR menção em comentário (senão vira ruído inútil).
if (consultasProibidas('// nada de site_partner_members aqui').length !== 0) {
  failures.push(
    "controle negativo falhou: o scanner acusa mencao em comentario"
  );
}

varrer("src", (caminho, conteudo) => {
  for (const tabela of consultasProibidas(conteudo)) {
    failures.push(`consulta a tabela inexistente em ${caminho}: ${tabela}`);
  }
});

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("CHECK_LEGADO_LIMPO");
