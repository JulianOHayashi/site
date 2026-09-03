import { defineConfig } from "vite";

/**
 * R16 — BUILD DO WORKER (SERVER-ONLY).
 *
 * Separado de `vite.config.ts` de propósito. O build do Site produz artefato
 * de NAVEGADOR; este produz um bundle de Node. Misturar os dois em uma
 * configuração só é como um artefato de servidor acaba no cliente.
 *
 * Decisões e por quê:
 *
 *   ssr: entrada do worker         builtins do Node ficam externos, como
 *                                  devem: nada de polyfill de `node:tls`.
 *   publicDir: false               o worker não serve estáticos; copiar
 *                                  `public/` para a saída do worker só
 *                                  produziria lixo na imagem de execução.
 *   target: node22                 é o runtime declarado; transpilar para
 *                                  baixo esconderia incompatibilidade real.
 *   minify: false                  em worker, rastreabilidade de stack vale
 *                                  mais que bytes. Não há download aqui.
 *   sourcemap                      diagnóstico de produção sem precisar
 *                                  reproduzir o bundle.
 *
 * `noExternal` NÃO é usado: dependências ficam externas e são resolvidas de
 * `node_modules` em execução. Embutir `@supabase/supabase-js` no bundle
 * duplicaria código já auditado pelo lockfile e mascararia a origem da
 * versão em uso.
 */
export default defineConfig({
  publicDir: false,
  build: {
    ssr: "src/server/worker/main.ts",
    outDir: "dist-worker",
    emptyOutDir: true,
    target: "node22",
    minify: false,
    sourcemap: true,
    rollupOptions: {
      output: { format: "esm", entryFileNames: "main.mjs" },
    },
  },
});
