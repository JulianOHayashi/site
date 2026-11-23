import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import CampanhaNatalInstagram from "../components/commercial/CampanhaNatalInstagram";

afterEach(() => cleanup());

describe("Página de detalhe — campanha de Natal pelo Instagram", () => {
  it("mostra o canal correto e não representa o Instagram como assinatura", () => {
    render(<CampanhaNatalInstagram />);
    expect(
      screen.getByRole("heading", { name: "Solicite seu contrato de Natal pelo Instagram" })
    ).toBeDefined();

    const link = screen.getByRole("link", {
      name: /Solicitar contrato pelo Instagram/,
    });
    expect(link.getAttribute("href")).toBe("https://www.instagram.com/smallflags/");
    expect(link.getAttribute("target")).toBe("_blank");
    expect(link.getAttribute("rel")?.split(" ")).toEqual(
      expect.arrayContaining(["noopener", "noreferrer"])
    );
    expect(link.textContent).toContain("@smallflags");
    expect(screen.getByText(/documento físico ou eletrônico/)).toBeDefined();
    expect(screen.getByText(/não constitui reserva, contratação ou assinatura/)).toBeDefined();
  });

  it("não cria checkout, formulário, pagamento ou assinatura pelo site", () => {
    const { container } = render(<CampanhaNatalInstagram />);
    expect(container.querySelector("form")).toBeNull();
    expect(container.querySelector("button")).toBeNull();
    expect(container.querySelector('a[href^="/checkout"]')).toBeNull();
    expect(container.querySelector('input')).toBeNull();
  });

  it("é exibido depois das condições comerciais na página das oportunidades", () => {
    const fonte = readFileSync(
      resolve(process.cwd(), "src/pages/OportunidadeDetalhe.tsx"),
      "utf8"
    );
    expect(fonte).toContain('import CampanhaNatalInstagram from "../components/commercial/CampanhaNatalInstagram"');
    expect(fonte).toContain("<CampanhaNatalInstagram />");
    expect(fonte.indexOf("<CampanhaNatalInstagram />")).toBeGreaterThan(fonte.indexOf("<PainelPreco"));
    expect(fonte).toContain("<PainelPreco");
    expect(fonte).toContain("registrarInteresseFuturo");
  });
});
