import type { Config } from "tailwindcss";

/**
 * Design system SmallFlags — tema claro derivado do ícone da marca.
 *
 * Todas as cores vêm de variáveis CSS em `src/index.css` (canais RGB), para
 * que os modificadores de opacidade do Tailwind (`text-tinta/70`) continuem
 * funcionando e para que a paleta tenha UMA fonte de verdade.
 *
 * Tokens semânticos (o nome descreve o papel, não a cor):
 *   tinta     → texto principal (escuro sobre o fundo branco)
 *   papel     → fundo da página
 *   papel2    → superfície discreta (hover, faixas, chips)
 *   superficie / superficie2 → cartões e painéis
 *   borda / borda-forte      → linhas e contornos
 *   noite     → preto da marca, fixo — texto sobre preenchimentos vivos
 *
 * Cores da marca (do ícone) em duas famílias:
 *   ciano, azul, verde, amarelo, laranja, vermelho, magenta
 *       → versão escurecida, segura para TEXTO sobre branco (AA)
 *   vivo-ciano … vivo-magenta
 *       → as cores exatas do ícone, só para preenchimentos e decoração
 * O gradiente completo é `bg-marca` / `var(--sf-gradiente)`.
 */
const canal = (nome: string) => `rgb(var(${nome}) / <alpha-value>)`;

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        tinta: canal("--sf-fg"),
        suave: canal("--sf-muted"),
        papel: canal("--sf-bg"),
        papel2: canal("--sf-surface"),
        superficie: canal("--sf-surface"),
        superficie2: canal("--sf-surface-2"),
        superficie3: canal("--sf-surface-3"),
        borda: canal("--sf-border"),
        "borda-forte": canal("--sf-border-strong"),
        noite: canal("--sf-noite"),

        ciano: canal("--sf-ciano"),
        azul: canal("--sf-azul"),
        verde: canal("--sf-verde"),
        amarelo: canal("--sf-amarelo"),
        laranja: canal("--sf-laranja"),
        vermelho: canal("--sf-vermelho"),
        magenta: canal("--sf-magenta"),

        vivo: {
          ciano: canal("--sf-v-ciano"),
          azul: canal("--sf-v-azul"),
          verde: canal("--sf-v-verde"),
          amarelo: canal("--sf-v-amarelo"),
          laranja: canal("--sf-v-laranja"),
          vermelho: canal("--sf-v-vermelho"),
          magenta: canal("--sf-v-magenta"),
        },
      },
      backgroundImage: {
        marca: "var(--sf-gradiente)",
        "marca-suave": "var(--sf-gradiente-suave)",
      },
      fontFamily: {
        display: ["'Space Grotesk'", "sans-serif"],
        body: ["'Inter'", "sans-serif"],
      },
      boxShadow: {
        painel: "0 1px 2px 0 rgb(16 24 40 / 0.04), 0 18px 40px -20px rgb(16 24 40 / 0.16)",
        brilho: "0 1px 2px 0 rgb(16 24 40 / 0.05), 0 14px 36px -14px rgb(var(--sf-v-ciano) / 0.45)",
      },
      maxWidth: {
        leitura: "68ch",
      },
    },
  },
  plugins: [],
} satisfies Config;
