import { useEffect, useState, useCallback } from "react";
import { Link } from "react-router-dom";
import Header from "../components/Header";
import OpportunityCard from "../components/commercial/OpportunityCard";
import FormationProgress from "../components/commercial/FormationProgress";
import ReferenciaOperacional from "../components/commercial/ReferenciaOperacional";
import { obterTerritorio } from "../lib/commercialTerritory";
import { fetchCurrentFormation } from "../services/commercialService";
import type { CommercialFormationResponse } from "../domain/commercial/types";
import { EXCLUSIVITY_STATUS_LABEL } from "../domain/commercial/status";

type Estado =
  | { fase: "loading" }
  | { fase: "erro" }
  | { fase: "sem_regiao"; uf: string; city: string }
  | { fase: "sem_exclusividade"; regionName: string }
  | { fase: "inconsistente" }
  | { fase: "ok"; dados: CommercialFormationResponse };

/**
 * /oportunidades — protegida por CommercialTerritoryGuard.
 * Mostra a exclusividade atual, o progresso da formação e as seis
 * oportunidades. Sem seletor de quantidade, carrinho, preço ou reserva.
 */
export default function Oportunidades() {
  const [estado, setEstado] = useState<Estado>({ fase: "loading" });

  const carregar = useCallback(async () => {
    const territorio = obterTerritorio();
    if (!territorio) {
      setEstado({ fase: "erro" });
      return;
    }
    setEstado({ fase: "loading" });
    try {
      const dados = await fetchCurrentFormation(territorio.uf, territorio.city);

      if (!dados.regionAvailable) {
        setEstado({
          fase: "sem_regiao",
          uf: territorio.uf,
          city: territorio.city,
        });
        return;
      }
      if (!dados.exclusivityAvailable || !dados.exclusivity || !dados.summary) {
        setEstado({
          fase: "sem_exclusividade",
          regionName: dados.region?.regionName ?? "",
        });
        return;
      }
      // Formação deve ter exatamente seis oportunidades.
      if (dados.opportunities.length !== 6) {
        console.error(
          "Formação inconsistente: esperado 6 oportunidades, recebido",
          dados.opportunities.length
        );
        setEstado({ fase: "inconsistente" });
        return;
      }
      setEstado({ fase: "ok", dados });
    } catch {
      setEstado({ fase: "erro" });
    }
  }, []);

  useEffect(() => {
    carregar();
  }, [carregar]);

  return (
    <>
      <Header />
      <main className="mx-auto max-w-6xl px-4 pb-24 pt-10">
        {estado.fase === "loading" && (
          <div className="flex flex-col items-center gap-3 py-24" aria-live="polite">
            <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
            <p className="text-sm text-tinta/60">
              Carregando oportunidades comerciais...
            </p>
          </div>
        )}

        {estado.fase === "erro" && (
          <div className="card mx-auto max-w-md p-8 text-center" aria-live="polite">
            <p className="font-semibold">
              Não foi possível carregar as oportunidades comerciais.
            </p>
            <button onClick={carregar} className="btn-primary mt-4">
              Tentar novamente
            </button>
          </div>
        )}

        {estado.fase === "sem_regiao" && (
          <div className="card mx-auto max-w-lg p-8 text-center">
            <p className="font-semibold">
              Ainda não há uma região comercial BDFlow ativa para{" "}
              {estado.city}/{estado.uf}.
            </p>
            <p className="mt-2 text-sm text-tinta/60">
              O registro de interesse territorial será disponibilizado em uma
              próxima etapa.
            </p>
            <Link to="/selecionar-localidade" className="btn-secondary mt-5 inline-block">
              Escolher outra localidade
            </Link>
          </div>
        )}

        {estado.fase === "sem_exclusividade" && (
          <div className="card mx-auto max-w-lg p-8 text-center">
            <p className="font-semibold">
              A região comercial está ativa, mas ainda não há uma exclusividade
              atual publicada.
            </p>
            <p className="mt-2 text-sm text-tinta/60">{estado.regionName}</p>
          </div>
        )}

        {estado.fase === "inconsistente" && (
          <div className="card mx-auto max-w-md p-8 text-center" aria-live="polite">
            <p className="font-semibold">
              Não foi possível exibir a formação comercial no momento.
            </p>
            <button onClick={carregar} className="btn-primary mt-4">
              Tentar novamente
            </button>
          </div>
        )}

        {estado.fase === "ok" && estado.dados.exclusivity && estado.dados.summary && (
          <>
            <header className="mb-8">
              <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
                {estado.dados.region?.regionName} ·{" "}
                {EXCLUSIVITY_STATUS_LABEL[estado.dados.exclusivity.status]}
              </p>
              <h1 className="mt-2 text-3xl sm:text-4xl">
                Oportunidades comerciais
              </h1>
              <p className="mt-2 max-w-2xl text-sm text-tinta/60">
                Cada nicho é uma oportunidade comercial contratada integralmente.
                A contratação será implementada em uma fase posterior.
              </p>
              {estado.dados.exclusivity.plannedStartAt && (
                <p className="mt-2 text-sm font-semibold">
                  Início previsto da operação:{" "}
                  {new Date(
                    estado.dados.exclusivity.plannedStartAt
                  ).toLocaleDateString("pt-BR")}
                </p>
              )}
            </header>

            <FormationProgress
              summary={estado.dados.summary}
              status={estado.dados.exclusivity.status}
            />

            <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {estado.dados.opportunities.map((o) => (
                <OpportunityCard key={o.nicheCode} opportunity={o} />
              ))}
            </div>

            <div className="mt-10">
              <ReferenciaOperacional />
            </div>
          </>
        )}
      </main>
    </>
  );
}
