/**
 * /portal/meu-acesso — manager-only.
 *
 * Somente leitura: o manager não edita papel, CPF validado, empresa, status,
 * permissão financeira nem vínculos administrativos.
 */

import Header from "../../components/Header";
import { CampoInfo, PortalCabecalho } from "./portalUi";
import {
  ManagerOnlyGate,
  PortalAviso,
} from "../../components/portal/PortalGuards";
import { portalNavigation } from "../../domain/portal/navigation";
import { roleLabel } from "../../domain/portal/capabilities";

const STATUS: Record<string, string> = {
  active: "Ativo",
  pending_admin_review: "Em análise administrativa",
  suspended: "Suspenso",
  archived: "Encerrado",
};

export default function PortalMeuAcesso() {
  return (
    <ManagerOnlyGate>
      {({ membership, capabilities, email }) => (
        <>
          <Header />
          <main className="mx-auto max-w-3xl px-4 pb-24 pt-10">
            <PortalCabecalho
              titulo="Meu acesso"
              itens={portalNavigation(membership.role, capabilities)}
            />

            <section className="mt-6 grid gap-5 rounded-3xl border border-borda bg-white/85 p-6 sm:grid-cols-2">
              <CampoInfo rotulo="Conta" valor={email} />
              <CampoInfo rotulo="Papel" valor={roleLabel(membership.role)} />
              <CampoInfo
                rotulo="Empresa vinculada"
                valor={membership.company.partnerDisplayName}
              />
              <CampoInfo
                rotulo="Situação do acesso"
                valor={STATUS[membership.status] ?? membership.status}
              />
              <CampoInfo
                rotulo="Validar benefícios"
                valor={capabilities.canValidateBenefits ? "Autorizado" : "Não autorizado"}
              />
              <CampoInfo rotulo="Acesso financeiro" valor="Não concedido" />
            </section>

            <PortalAviso
              titulo="Alterações dependem da administração"
              descricao="Papel, CPF validado, empresa, situação e permissões não podem ser alterados por aqui. O acesso financeiro não é concedido a gerentes operacionais."
            />
          </main>
        </>
      )}
    </ManagerOnlyGate>
  );
}
