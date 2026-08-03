/**
 * PortalCadastro — DESATIVADO na V2.
 *
 * O antigo formulário chamava a RPC `create_my_partner_owner_registration`,
 * agora PROIBIDA no caminho público. Nenhuma rota renderiza este componente
 * (ver src/App.tsx: /portal/cadastro usa PortalCadastroRedirect). Este módulo
 * permanece apenas como redirecionamento defensivo, sem formulário e sem RPC,
 * para o caso de algum link antigo importá-lo diretamente.
 *
 * A definição SQL da RPC NÃO foi alterada nem removida — apenas retirada do
 * fluxo de interface público.
 */

import { Navigate, useLocation } from "react-router-dom";

export default function PortalCadastro() {
  const location = useLocation();
  return <Navigate to={`/parceiros/cadastro${location.search ?? ""}`} replace />;
}
