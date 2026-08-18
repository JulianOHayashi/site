import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";

/**
 * M0.5 — prova de fiação dos sinks.
 *
 * O teste unitário prova o helper. Este prova que as páginas realmente o
 * usam: se alguém reintroduzir validação por prefixo, o destino hostil
 * volta a passar e estes casos falham.
 *
 * O serviço comercial é mockado porque a resolução territorial é do
 * backend e não é o objeto deste teste.
 */

vi.mock("../services/commercialService", () => ({
  CommercialError: class CommercialError extends Error {},
  fetchCurrentFormation: vi.fn(async () => ({
    regionAvailable: true,
    region: { regionId: "ES-GV", regionName: "Grande Vitória" },
    exclusivity: null,
    cards: [],
    summary: null,
  })),
}));

import SelecionarLocalidade from "../pages/SelecionarLocalidade";

/** Espia o destino final da navegação dentro do MemoryRouter. */
function Espiao() {
  const location = useLocation();
  return (
    <div data-testid="destino-final">
      {location.pathname}
      {location.search}
    </div>
  );
}

function montarSelecionarLocalidade(next: string) {
  const entrada = `/selecionar-localidade?next=${encodeURIComponent(next)}`;
  return render(
    <MemoryRouter initialEntries={[entrada]}>
      <Routes>
        <Route path="/selecionar-localidade" element={<SelecionarLocalidade />} />
        <Route path="*" element={<Espiao />} />
      </Routes>
    </MemoryRouter>
  );
}

async function confirmarESeguir() {
  fireEvent.change(screen.getByLabelText(/cidade/i), {
    target: { value: "Vitória" },
  });
  fireEvent.click(screen.getByRole("button", { name: /confirmar localidade/i }));
  const seguir = await screen.findByRole("button", { name: /ver oportunidades/i });
  fireEvent.click(seguir);
  return waitFor(() => screen.getByTestId("destino-final"));
}

beforeEach(() => {
  localStorage.clear();
});

afterEach(() => {
  cleanup();
});

describe("/selecionar-localidade — destino do ?next=", () => {
  it("segue um destino interno legítimo", async () => {
    montarSelecionarLocalidade("/oportunidades/supermercado");
    const destino = await confirmarESeguir();
    expect(destino.textContent).toBe("/oportunidades/supermercado");
  });

  it("ignora bypass por backslash e cai no destino padrão", async () => {
    montarSelecionarLocalidade("/\\evil.com");
    const destino = await confirmarESeguir();
    expect(destino.textContent).toBe("/oportunidades");
  });

  it("ignora protocolo-relativo", async () => {
    montarSelecionarLocalidade("//evil.com");
    const destino = await confirmarESeguir();
    expect(destino.textContent).toBe("/oportunidades");
  });

  it("ignora URL absoluta externa", async () => {
    montarSelecionarLocalidade("https://evil.com");
    const destino = await confirmarESeguir();
    expect(destino.textContent).toBe("/oportunidades");
  });
});
