/**
 * Resumo de matriz e filiais.
 *
 * Usa exclusivamente os campos públicos definidos na Fase 2A. `trade_name`,
 * `city` e `state` NÃO são usados como substitutos definitivos: quando o
 * campo público não vier, a ausência é exibida como ausência.
 */

import { useEffect, useState } from "react";
import { listUnits } from "../../services/partnerUnitService";
import { FuncaoIndisponivel } from "./PortalGuards";
import { CarregandoPortal } from "../../pages/portal/portalUi";
import {
  PORTAL_ERROR_LABEL,
  type PartnerUnit,
  type PortalErrorCode,
} from "../../domain/portal/types";

const STATUS_UNIDADE: Record<string, { rotulo: string; classes: string }> = {
  active: { rotulo: "Ativa", classes: "bg-[#E8F7EE] text-[#0B7A3E]" },
  suspended: { rotulo: "Suspensa", classes: "bg-magenta/10 text-magenta" },
  archived: { rotulo: "Arquivada", classes: "bg-papel2 text-tinta/60" },
};

export function UnidadeCard({ unidade }: { unidade: PartnerUnit }) {
  const st = unidade.status ? STATUS_UNIDADE[unidade.status] : null;
  return (
    <li className="rounded-2xl border border-borda bg-white/85 p-5">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
            {unidade.isHeadquarters ? "Matriz" : "Filial"}
          </p>
          <h3 className="mt-1 font-bold">
            {unidade.branchDisplayName ?? "Nome público não informado"}
          </h3>
          <p className="mt-0.5 text-sm text-tinta/70">
            {unidade.branchLocationLabel ?? "Referência de local não informada"}
          </p>
          <p className="mt-0.5 text-sm text-tinta/60">
            {unidade.branchCityName && unidade.branchStateCode
              ? `${unidade.branchCityName} · ${unidade.branchStateCode}`
              : "Cidade/UF não informadas"}
          </p>
        </div>
        <div className="flex flex-col items-end gap-2">
          {st && (
            <span className={`rounded-full px-3 py-1 text-xs font-semibold ${st.classes}`}>
              {st.rotulo}
            </span>
          )}
          <span
            className={`rounded-full px-3 py-1 text-xs font-semibold ${
              unidade.benefitsAuthorized
                ? "bg-ciano/15 text-ciano"
                : "bg-papel2 text-tinta/60"
            }`}
          >
            {unidade.benefitsAuthorized
              ? "Autorizada a liberar benefícios"
              : "Não autorizada a liberar benefícios"}
          </span>
        </div>
      </div>

      <div className="mt-4 border-t border-borda pt-3 text-sm">
        {unidade.activeManagersCount === null ? (
          <p className="text-tinta/50">
            Quantidade de gerentes ativos não informada pelo sistema.
          </p>
        ) : unidade.activeManagersCount === 0 ? (
          <p className="font-medium text-magenta">
            Nenhum gerente ativo nesta unidade.
          </p>
        ) : (
          <p className="text-tinta/70">
            {unidade.activeManagersCount}{" "}
            {unidade.activeManagersCount === 1
              ? "gerente ativo"
              : "gerentes ativos"}
          </p>
        )}
      </div>
    </li>
  );
}

export default function UnidadesResumo() {
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<PortalErrorCode | null>(null);
  const [unidades, setUnidades] = useState<PartnerUnit[]>([]);

  useEffect(() => {
    let ativo = true;
    listUnits().then((r) => {
      if (!ativo) return;
      if (r.ok) setUnidades(r.data);
      else setErro(r.error.code);
      setCarregando(false);
    });
    return () => {
      ativo = false;
    };
  }, []);

  if (carregando) return <CarregandoPortal />;

  if (erro === "BACKEND_NOT_AVAILABLE") {
    return (
      <FuncaoIndisponivel
        titulo="Filiais ainda não disponíveis"
        descricao="O cadastro e a listagem de matriz e filiais dependem de uma camada de servidor que ainda não foi ativada. Nenhum dado de filial é exibido por suposição."
      />
    );
  }
  if (erro) {
    return (
      <div className="mt-4 rounded-2xl border-2 border-magenta/30 bg-magenta/10 p-5 text-sm font-medium text-magenta">
        {PORTAL_ERROR_LABEL[erro]}
      </div>
    );
  }
  if (unidades.length === 0) {
    return (
      <div className="mt-4 rounded-3xl border border-dashed border-borda p-10 text-center text-sm text-tinta/60">
        Nenhuma unidade cadastrada até o momento.
      </div>
    );
  }

  return (
    <ul className="mt-4 grid gap-4 sm:grid-cols-2">
      {unidades.map((u) => (
        <UnidadeCard key={u.unitId} unidade={u} />
      ))}
    </ul>
  );
}
