import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { ReactNode } from "react";
import { EmpresaProvider } from "../../portal/empresaContexto";

/**
 * Monta uma tela do Portal dentro do provider de empresa, como em produção.
 *
 * As telas do Portal leem a empresa ativa do contexto; montá-las sem o
 * provider lança, e com razão — é o que garante que ninguém volte a escolher
 * empresa por conta própria dentro de uma página.
 *
 * O provider depende de `usePortalSiteAuth` (para o id do usuário) e de
 * `obterVinculosParceiro`. O spec que usar este helper precisa mockar os dois.
 */
export function renderPortal(
  ui: ReactNode,
  { rotas = ["/"] }: { rotas?: string[] } = {}
) {
  const envolver = (conteudo: ReactNode) => (
    <MemoryRouter initialEntries={rotas}>
      <EmpresaProvider>{conteudo}</EmpresaProvider>
    </MemoryRouter>
  );
  const r = render(envolver(ui));
  return {
    ...r,
    /**
     * Re-renderiza a mesma árvore. Serve para simular logout ou troca de conta:
     * o spec muda a sessão simulada e chama isto para o provider reler o hook.
     */
    rerenderPortal: (novo: ReactNode = ui) => r.rerender(envolver(novo)),
  };
}

/** Sessão mínima para o provider. O id separa a dica de sessão por conta. */
export const SESSAO_FALSA = (
  userId = "user-1",
  email = "owner@example.com"
) => ({ session: { user: { id: userId, email } } });
