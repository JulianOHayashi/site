import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

/**
 * Configuração de testes do Site (M0.5).
 *
 * `include` é restrito a *.spec.* de propósito: src/__tests__/commercial.test.ts
 * é um script legado executado via esbuild+node, sem describe/it, e seria
 * coletado (e quebraria) pelo padrão default do Vitest. Ele permanece
 * intocado neste marco.
 */
export default defineConfig({
  plugins: [react()],
  test: {
    include: ["src/**/*.spec.{ts,tsx}"],
    environment: "jsdom",
  },
});
