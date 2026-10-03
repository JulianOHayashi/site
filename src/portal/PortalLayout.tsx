import { Outlet } from "react-router-dom";
import { EmpresaProvider } from "./empresaContexto";

/**
 * Casca das telas operacionais do Portal.
 *
 * Existe por um motivo só: manter UMA instância de `EmpresaProvider` viva
 * enquanto a pessoa navega entre painel, equipe e validação. Com o provider
 * dentro de cada rota, ele remontaria a cada troca e a empresa escolhida se
 * perderia; na raiz da aplicação, toda visita pública dispararia consulta de
 * sessão à toa.
 *
 * Não decide autorização: isso continua com o PortalGuard de cada rota e com
 * as RPCs do servidor.
 */
export default function PortalLayout() {
  return (
    <EmpresaProvider>
      <Outlet />
    </EmpresaProvider>
  );
}
