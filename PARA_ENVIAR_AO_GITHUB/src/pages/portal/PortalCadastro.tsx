/**
 * PortalCadastro — DESATIVADO no Pacote P0.
 *
 * Este arquivo continha o formulário que chamava a RPC
 * `create_my_partner_owner_registration`, cuja contenção está preparada em
 * supabase/p0-contencao-migration.sql, por estar
 * estruturalmente incompatível com o schema atual (referenciava
 * `site_partner_members`, tabela que a auditoria de 2026-08-03 não
 * encontrou no banco remoto).
 *
 * Nenhuma rota importa mais este componente: /portal/cadastro agora usa
 * PortalCadastroRedirect (ver src/App.tsx), que encaminha, sem guarda e sem
 * formulário, para /parceiros/cadastro. Este módulo permanece apenas como
 * redirecionamento defensivo — sem formulário, sem chamada RPC — para o caso
 * de algum link antigo importá-lo diretamente.
 *
 * A definição SQL da RPC NÃO foi alterada nem removida. Seu acesso público e
 * autenticado somente será revogado se a migration for executada manualmente
 * no futuro, após o preflight e a revisão humana previstos no pacote.
 */

import { Navigate, useLocation } from "react-router-dom";

export default function PortalCadastro() {
  const location = useLocation();
  return <Navigate to={`/parceiros/cadastro${location.search ?? ""}`} replace />;
}
