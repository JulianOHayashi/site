import { Navigate, useLocation } from "react-router-dom";
import { obterTerritorio } from "../lib/commercialTerritory";

/**
 * CommercialTerritoryGuard — protege as rotas comerciais novas.
 *
 * Fluxo:
 *  sem UF/cidade  → redireciona para /selecionar-localidade (preservando
 *                   o destino interno em ?next=)
 *  com território → libera a página (a própria página trata "região
 *                   indisponível" a partir da resposta do backend)
 *
 * A leitura é síncrona (localStorage), então não há flash. O guard não
 * decide disponibilidade de região — isso é do backend, refletido na
 * página. Não aceita redirecionamento externo.
 */
export default function CommercialTerritoryGuard({
  children,
}: {
  children: React.ReactNode;
}) {
  const location = useLocation();
  const territorio = obterTerritorio();

  if (!territorio) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/selecionar-localidade?next=${next}`} replace />;
  }

  return <>{children}</>;
}
