/**
 * /portal/cadastro — redirecionamento INCONDICIONAL para o novo fluxo público.
 *
 * O antigo formulário (PortalCadastro) chamava a RPC
 * `create_my_partner_owner_registration`, hoje PROIBIDA no caminho público.
 * Esta rota não renderiza mais o formulário, não usa PortalGuard e não
 * executa RPC alguma: apenas redireciona, com replace, para
 * /parceiros/cadastro, preservando somente a query string interna (sem
 * permitir open redirect — a busca é reanexada como está, sem host/scheme).
 */

import { Navigate, useLocation } from "react-router-dom";

export default function PortalCadastroRedirect() {
  const location = useLocation();
  // Apenas a query string é preservada; o destino (path) é fixo e interno.
  const destino = `/parceiros/cadastro${location.search ?? ""}`;
  return <Navigate to={destino} replace />;
}
