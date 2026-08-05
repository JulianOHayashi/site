import { existsSync, readFileSync } from "node:fs";

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

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("CHECK_LEGADO_LIMPO");
