import { useEffect, useState, useCallback } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import Header from "../components/Header";
import ReferenciaOperacional from "../components/commercial/ReferenciaOperacional";
import { obterTerritorio } from "../lib/commercialTerritory";
import { fetchCurrentFormation } from "../services/commercialService";
import {
  nicheByCode,
  nicheCodeFromSlug,
  canonicalSlugFromLegacy,
} from "../domain/commercial/niches";
import {
  OPPORTUNITY_STATUS_LABEL,
  EXCLUSIVITY_STATUS_LABEL,
} from "../domain/commercial/status";
import type { CommercialFormationResponse } from "../domain/commercial/types";

type Estado =
  | { fase: "loading" }
  | { fase: "erro" }
  | { fase: "codigo_invalido" }
  | { fase: "nao_encontrada" }
  | { fase: "ok"; dados: CommercialFormationResponse };

/**
 * /oportunidades/:nicheCode — detalhe de uma oportunidade.
 * Valida o código do nicho e apresenta dados públicos. Nenhuma ação de
 * quantidade, unidade, CNPJ, reserva, pagamento ou contrato.
 */
export default function OportunidadeDetalhe() {
  const { nicheSlug: rota } = useParams();
  // URL legada com underscore → redireciona UMA vez ao slug canônico (hífen).
  const redirecionarPara = rota ? canonicalSlugFromLegacy(rota) : null;
  // Aceita SOMENTE o slug canônico (hífen). Desconhecido → null → inválido.
  const codigo = rota ? nicheCodeFromSlug(rota) : null;
  const [estado, setEstado] = useState<Estado>({ fase: "loading" });

  const carregar = useCallback(async () => {
    if (!codigo) {
      setEstado({ fase: "codigo_invalido" });
      return;
    }
    const territorio = obterTerritorio();
    if (!territorio) {
      setEstado({ fase: "erro" });
      return;
    }
    setEstado({ fase: "loading" });
    try {
      const dados = await fetchCurrentFormation(territorio.uf, territorio.city);
      if (!dados.exclusivityAvailable) {
        setEstado({ fase: "nao_encontrada" });
        return;
      }
      const existe = dados.opportunities.some((o) => o.nicheCode === codigo);
      if (!existe) {
        setEstado({ fase: "nao_encontrada" });
        return;
      }
      setEstado({ fase: "ok", dados });
    } catch {
      setEstado({ fase: "erro" });
    }
  }, [codigo]);

  useEffect(() => {
    carregar();
  }, [carregar]);

  const meta = codigo ? nicheByCode(codigo) : null;

  // Redirecionamento interno único de URL legada (underscore) → hífen.
  // Sem loop: o slug de destino já é canônico e cai em nicheCodeFromSlug.
  if (redirecionarPara) {
    return <Navigate to={`/oportunidades/${redirecionarPara}`} replace />;
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-3xl px-4 pb-24 pt-10">
        <Link
          to="/oportunidades"
          className="text-sm font-medium text-ciano hover:underline"
        >
          ← Voltar às oportunidades
        </Link>

        {estado.fase === "loading" && (
          <div className="flex flex-col items-center gap-3 py-24" aria-live="polite">
            <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
            <p className="text-sm text-tinta/60">
              Carregando oportunidades comerciais...
            </p>
          </div>
        )}

        {estado.fase === "codigo_invalido" && (
          <div className="card mt-6 p-8 text-center">
            <p className="font-semibold">Oportunidade não reconhecida.</p>
            <Link to="/oportunidades" className="btn-secondary mt-4 inline-block">
              Ver todas as oportunidades
            </Link>
          </div>
        )}

        {estado.fase === "nao_encontrada" && (
          <div className="card mt-6 p-8 text-center">
            <p className="font-semibold">
              Esta oportunidade não está disponível na região atual.
            </p>
            <Link to="/oportunidades" className="btn-secondary mt-4 inline-block">
              Ver oportunidades
            </Link>
          </div>
        )}

        {estado.fase === "erro" && (
          <div className="card mt-6 p-8 text-center" aria-live="polite">
            <p className="font-semibold">Não foi possível carregar o detalhe.</p>
            <button onClick={carregar} className="btn-primary mt-4">
              Tentar novamente
            </button>
          </div>
        )}

        {estado.fase === "ok" && meta && (() => {
          const opp = estado.dados.opportunities.find(
            (o) => o.nicheCode === meta.code
          )!;
          return (
            <>
              <header className="mt-4 flex items-center gap-3">
                <span aria-hidden className="text-4xl">
                  {meta.icon}
                </span>
                <div>
                  <h1 className="text-3xl">{meta.displayName}</h1>
                  <p className="text-sm text-tinta/60">
                    {estado.dados.region?.regionName} · Exclusividade{" "}
                    {estado.dados.exclusivity?.sequenceNumber}
                  </p>
                </div>
              </header>

              <div className="card mt-6 space-y-4 p-6">
                <div className="flex items-center justify-between">
                  <span className="text-tinta/60">Status</span>
                  <span className="rounded-full bg-papel2 px-3 py-1 text-sm font-semibold">
                    {OPPORTUNITY_STATUS_LABEL[opp.status]}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-tinta/60">Quantidade</span>
                  <span className="font-bold">
                    {opp.contractedQuantity} unidades
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-tinta/60">Exclusividade</span>
                  <span className="font-semibold">
                    {estado.dados.exclusivity
                      ? EXCLUSIVITY_STATUS_LABEL[estado.dados.exclusivity.status]
                      : "—"}
                  </span>
                </div>
              </div>

              <div className="card mt-4 p-6">
                <h2 className="text-lg font-bold">Sobre esta oportunidade</h2>
                <p className="mt-2 text-sm text-tinta/70">
                  {meta.shortDescription} O nicho é contratado integralmente,
                  com {opp.contractedQuantity} unidades — não há venda de
                  unidades avulsas.
                </p>
                <p className="mt-3 rounded-xl border border-amarelo bg-amarelo/15 px-4 py-3 text-sm text-tinta/70">
                  A contratação será liberada em uma fase posterior. Esta tela
                  apresenta a oportunidade comercial, sem reserva ou pagamento.
                </p>
              </div>

              <div className="mt-6">
                <ReferenciaOperacional />
              </div>
            </>
          );
        })()}
      </main>
    </>
  );
}
