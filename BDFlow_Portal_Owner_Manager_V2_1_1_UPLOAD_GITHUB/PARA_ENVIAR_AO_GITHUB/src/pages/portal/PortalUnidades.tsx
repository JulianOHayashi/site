/**
 * /portal/unidades — owner-only.
 * Gestão detalhada de matriz e filiais. O cadastro de filial só é oferecido
 * quando `canManageUnits` for concedida pelo backend.
 */

import Header from "../../components/Header";
import { PortalCabecalho } from "./portalUi";
import {
  CapabilityGate,
  FuncaoIndisponivel,
  OwnerOnlyGate,
} from "../../components/portal/PortalGuards";
import UnidadesResumo from "../../components/portal/UnidadesResumo";
import { portalNavigation } from "../../domain/portal/navigation";
import { PUBLIC_FIELD_LIMITS } from "../../domain/portal/types";

export default function PortalUnidades() {
  return (
    <OwnerOnlyGate>
      {({ membership, capabilities }) => (
        <>
          <Header />
          <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
            <PortalCabecalho
              titulo="Empresa e filiais"
              itens={portalNavigation(membership.role, capabilities)}
            />

            <p className="mt-3 text-sm text-tinta/60">
              Apenas filiais cadastradas, ativas e autorizadas podem liberar
              benefícios. A filial usada em cada validação é escolhida no
              momento da operação.
            </p>

            <UnidadesResumo />

            <section className="mt-8">
              <h2 className="text-xl font-bold">Cadastrar filial</h2>
              <CapabilityGate
                capabilities={capabilities}
                requer="canManageUnits"
                fallback={
                  <FuncaoIndisponivel
                    titulo="Cadastro de filial ainda não disponível"
                    descricao="A criação de filiais será liberada pelo servidor após a preparação operacional da empresa. Nenhum cadastro é aceito por aqui neste momento."
                  />
                }
              >
                <p className="mt-3 rounded-2xl border border-borda bg-papel2/60 p-5 text-sm text-tinta/70">
                  Campos públicos exigidos: nome de exibição (até{" "}
                  {PUBLIC_FIELD_LIMITS.branch_display_name} caracteres),
                  referência de local (até{" "}
                  {PUBLIC_FIELD_LIMITS.branch_location_label}), cidade (até{" "}
                  {PUBLIC_FIELD_LIMITS.branch_city_name}) e UF com duas letras
                  maiúsculas válidas.
                </p>
              </CapabilityGate>
            </section>
          </main>
        </>
      )}
    </OwnerOnlyGate>
  );
}
