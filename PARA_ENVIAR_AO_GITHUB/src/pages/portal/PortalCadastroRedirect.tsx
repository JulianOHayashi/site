/**
 * /portal/cadastro — redirecionamento INCONDICIONAL (Pacote P0).
 *
 * O formulário antigo chamava `create_my_partner_owner_registration`, hoje
 * retirada do caminho público. Esta rota não renderiza formulário algum e
 * não usa PortalGuard: encaminha diretamente para /parceiros/cadastro,
 * preservando apenas a query string (sem permitir open redirect — o destino
 * é sempre interno e fixo).
 */

import { Navigate, useLocation } from "react-router-dom";

export default function PortalCadastroRedirect() {
  const location = useLocation();
  const destino = `/parceiros/cadastro${location.search ?? ""}`;
  return <Navigate to={destino} replace />;
}
