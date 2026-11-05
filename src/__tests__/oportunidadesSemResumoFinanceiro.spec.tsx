import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import formacao from "./fixtures/formation-pg17-backend-novo-20261104.json";

/**
 * /oportunidades não exibe mais o bloco "A formação completa em números"
 * (ResumoFormacao). O componente continua existindo; só deixa de ser
 * renderizado nesta página. Cards, progresso e navegação continuam.
 */
const rpcMock = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...(a as [])) },
  supabaseConfigurado: true,
}));
vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../lib/commercialTerritory", () => ({
  obterTerritorio: () => ({ uf: "ES", city: "Vitória" }),
}));

import Oportunidades from "../pages/Oportunidades";

const montar = () =>
  render(
    <MemoryRouter initialEntries={["/oportunidades"]}>
      <Routes>
        <Route path="/oportunidades" element={<Oportunidades />} />
      </Routes>
    </MemoryRouter>
  );

describe("/oportunidades sem o resumo financeiro da formação", () => {
  beforeEach(() => {
    rpcMock.mockReset();
    rpcMock.mockImplementation(async (nome: string) =>
      nome === "get_current_commercial_formation"
        ? { data: formacao, error: null }
        : { data: null, error: { message: `rpc inesperada: ${nome}` } }
    );
  });
  afterEach(() => cleanup());

  it("mantém cabeçalho, progresso e os seis cards com navegação", async () => {
    montar();
    expect(await screen.findByRole("heading", { name: "Oportunidades comerciais" })).toBeDefined();
    expect(screen.getByRole("progressbar", { name: "Percentual de formação comercial" })).toBeDefined();
    const links = screen
      .getAllByRole("link")
      .map((a) => a.getAttribute("href"))
      .filter((h): h is string => !!h && /^\/oportunidades\/.+/.test(h));
    expect(new Set(links).size).toBe(6);
    expect(links).toEqual(
      expect.arrayContaining([
        "/oportunidades/supermarket",
        "/oportunidades/pharmacy",
        "/oportunidades/womens-clothing",
        "/oportunidades/mens-clothing",
        "/oportunidades/footwear",
        "/oportunidades/others",
      ])
    );
  });

  it("não renderiza o bloco financeiro nem busca a economia da formação", async () => {
    montar();
    await screen.findByRole("heading", { name: "Oportunidades comerciais" });
    await waitFor(() =>
      expect(rpcMock).toHaveBeenCalledWith("get_current_commercial_formation", expect.anything())
    );
    for (const texto of [
      /A formação completa em números/,
      /Referência da primeira formação/,
      /Valor econômico total da formação/,
      /Contraprestação dos 84 MEIs/,
      /Pool contratual total/,
      /SmallFlags \+ operação \+ investimentos/,
      /Contraprestação potencial por MEI/,
    ]) {
      expect(screen.queryByText(texto)).toBeNull();
    }
    expect(rpcMock.mock.calls.map((c) => c[0])).not.toContain("get_public_formation_economics");
  });

  it("a página não importa nem monta ResumoFormacao; o componente segue existindo", () => {
    const pagina = readFileSync(resolve(__dirname, "../pages/Oportunidades.tsx"), "utf8");
    expect(pagina).not.toContain("ResumoFormacao");
    expect(pagina).toContain("<ReferenciaOperacional />");
    const componente = readFileSync(
      resolve(__dirname, "../components/commercial/ResumoFormacao.tsx"),
      "utf8"
    );
    expect(componente).toContain("A formação completa em números");
  });
});
