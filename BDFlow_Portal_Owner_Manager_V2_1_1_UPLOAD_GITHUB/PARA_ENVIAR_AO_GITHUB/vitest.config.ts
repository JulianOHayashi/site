import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    // Testes de INTERFACE (Vitest/RTL) ficam em src/test/ui.
    // Os testes de funções puras continuam rodando via esbuild+node.
    include: ["src/test/**/*.test.ts?(x)"],
  },
});
