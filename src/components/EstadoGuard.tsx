import { Navigate, useLocation } from "react-router-dom";
import { obterUF } from "../lib/estado";

/**
 * EstadoGuard — protege as rotas COMERCIAIS (Home, catálogo, detalhe,
 * personalização, checkout): sem UF válida salva, o visitante vai para
 * a tela de seleção, preservando o destino original em ?next=.
 *
 * A leitura do localStorage é síncrona: nenhum produto de UF errada
 * pisca na tela e nenhuma UF padrão incorreta é assumida.
 *
 * /portal, /parceiros e /admin NÃO usam este guard — funcionam sem
 * passar pelo mapa.
 */
export default function EstadoGuard({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const uf = obterUF();

  if (!uf) {
    const destino = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/selecionar-estado?next=${destino}`} replace />;
  }

  return <>{children}</>;
}
