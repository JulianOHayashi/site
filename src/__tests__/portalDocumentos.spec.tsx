import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";

const listarMeusAceites = vi.fn();
const obterDocumentoPorVersao = vi.fn();

vi.mock("../services/legalDocumentService", () => ({
  listarMeusAceites: (...a: unknown[]) => listarMeusAceites(...a),
  obterDocumentoPorVersao: (...a: unknown[]) => obterDocumentoPorVersao(...a),
}));

vi.mock("../components/Header", () => ({ default: () => null }));
vi.mock("../pages/portal/portalUi", () => ({
  PortalTopo: ({ titulo }: { titulo: string }) => <h1>{titulo}</h1>,
}));
vi.mock("../components/legal/ConteudoLegal", () => ({
  default: ({ markdown }: { markdown: string }) => <div>{markdown}</div>,
}));

import PortalDocumentos from "../pages/portal/PortalDocumentos";

beforeEach(() => {
  vi.clearAllMocks();
  listarMeusAceites.mockResolvedValue({
    tipo: "ok",
    aceites: [{
      acceptanceId: "a-1",
      docType: "privacy_notice",
      version: "v-historica-1",
      title: "Aviso de Privacidade",
      contentHash: "a".repeat(64),
      isMaterialChange: true,
      context: "provisional_account",
      acceptedAt: "2026-10-27T12:00:00Z",
      revokedAt: null,
    }],
  });
  obterDocumentoPorVersao.mockResolvedValue({
    tipo: "ok",
    documento: {
      docType: "privacy_notice",
      version: "v-historica-1",
      title: "Aviso de Privacidade",
      content: "CONTEUDO HISTORICO EXATO",
      contentUrl: null,
      contentHash: "a".repeat(64),
      status: "archived",
      isMaterialChange: true,
      effectiveFrom: null,
      effectiveTo: null,
      publishedAt: null,
    },
  });
});

afterEach(() => cleanup());

describe("PortalDocumentos", () => {
  it("consulta a versão exata registrada no aceite", async () => {
    render(<MemoryRouter><PortalDocumentos /></MemoryRouter>);

    await screen.findByText("Aviso de Privacidade");
    expect(obterDocumentoPorVersao).toHaveBeenCalledWith(
      "privacy_notice",
      "v-historica-1"
    );
    expect(screen.getByText(/v-historica-1/i)).toBeDefined();
  });

  it("é somente leitura e não oferece novo aceite", async () => {
    render(<MemoryRouter><PortalDocumentos /></MemoryRouter>);

    await screen.findByText("Aviso de Privacidade");
    expect(screen.queryAllByRole("checkbox")).toHaveLength(0);
    expect(screen.getByText(/somente leitura/i)).toBeDefined();
  });

  it("preserva o registro mesmo se o conteúdo histórico estiver indisponível", async () => {
    obterDocumentoPorVersao.mockResolvedValue({ tipo: "ausente" });

    render(<MemoryRouter><PortalDocumentos /></MemoryRouter>);

    await screen.findByText("Aviso de Privacidade");
    expect(
      screen.getByText(/registro do aceite está preservado/i)
    ).toBeDefined();
  });

  it("falha de consulta não vira histórico vazio", async () => {
    listarMeusAceites.mockResolvedValue({ tipo: "indisponivel" });

    render(<MemoryRouter><PortalDocumentos /></MemoryRouter>);

    await waitFor(() =>
      expect(screen.getByRole("alert")).toBeDefined()
    );
    expect(screen.queryByText(/nenhum aceite registrado/i)).toBeNull();
  });
});
