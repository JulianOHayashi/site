/**
 * /portal/dashboard — mesma rota, experiências distintas por papel.
 *
 * `partner_owner`  → painel administrativo da própria empresa.
 * `partner_manager`→ painel operacional reduzido.
 *
 * O CTA "Cadastre sua empresa parceira" NÃO existe mais aqui: nenhum owner
 * com vínculo e nenhum manager pode recebê-lo. Quem não possui vínculo
 * elegível recebe estado de acesso indisponível com encaminhamento seguro
 * para a área comercial (sem criar empresa pelo Portal e sem reutilizar a
 * RPC antiga de criação de owner).
 */

import { useNavigate } from "react-router-dom";
import Header from "../../components/Header";
import { supabase } from "../../lib/supabase";
import { PortalMemberGate } from "../../components/portal/PortalGuards";
import OwnerDashboard from "../../components/portal/OwnerDashboard";
import ManagerDashboard from "../../components/portal/ManagerDashboard";

export default function PortalDashboard() {
  const navigate = useNavigate();

  const sair = async () => {
    await supabase?.auth.signOut();
    navigate("/portal/login", { replace: true });
  };

  return (
    <PortalMemberGate>
      {({ membership, capabilities, capabilitiesSource, email }) => (
        <>
          <Header />
          {membership.role === "partner_owner" ? (
            <OwnerDashboard
              membership={membership}
              capabilities={capabilities}
              capabilitiesSource={capabilitiesSource}
              email={email}
              onSair={sair}
            />
          ) : (
            <ManagerDashboard
              membership={membership}
              capabilities={capabilities}
              capabilitiesSource={capabilitiesSource}
              email={email}
              onSair={sair}
            />
          )}
        </>
      )}
    </PortalMemberGate>
  );
}
