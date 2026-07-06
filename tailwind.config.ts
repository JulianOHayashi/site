import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        magenta: "#E5007E",
        ciano: "#00A8E0",
        amarelo: "#FFC400",
        tinta: "#17121F",
        papel: "#FBFAF6",
        papel2: "#F1EFE8",
        borda: "#E5E2D9",
      },
      fontFamily: {
        display: ["'Space Grotesk'", "sans-serif"],
        body: ["'Inter'", "sans-serif"],
      },
    },
  },
  plugins: [],
} satisfies Config;
