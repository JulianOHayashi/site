import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";
import PortalCadastroRedirect from "../../pages/portal/PortalCadastroRedirect";

/** Página-alvo fictícia que revela a query string recebida no destino. */
function DestinoFake() {
  const loc = useLocation();
  return <div>DESTINO_PARCEIROS_CADASTRO{loc.search}</div>;
}

function renderComRota(inicial: string) {
  return render(
    <MemoryRouter initialEntries={[inicial]}>
      <Routes>
        <Route path="/portal/cadastro" element={<PortalCadastroRedirect />} />
        <Route path="/parceiros/cadastro" element={<DestinoFake />} />
      </Routes>
    </MemoryRouter>
  );
}

describe("CORREÇÃO 1 — /portal/cadastro redireciona", () => {
  it("redireciona incondicionalmente para /parceiros/cadastro", () => {
    renderComRota("/portal/cadastro");
    expect(screen.getByText("DESTINO_PARCEIROS_CADASTRO")).toBeInTheDocument();
  });

  it("preserva a query string exata: ?ref=x&y=1 chega ao destino", () => {
    renderComRota("/portal/cadastro?ref=x&y=1");
    // /portal/cadastro?ref=x&y=1 → /parceiros/cadastro?ref=x&y=1
    expect(
      screen.getByText("DESTINO_PARCEIROS_CADASTRO?ref=x&y=1")
    ).toBeInTheDocument();
  });

  it("não renderiza formulário antigo de cadastro", () => {
    renderComRota("/portal/cadastro");
    expect(screen.queryByText(/Cadastrar empresa parceira/i)).toBeNull();
    expect(screen.queryByLabelText(/CNPJ/i)).toBeNull();
  });
});
