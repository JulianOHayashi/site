import { useEffect, useState, useCallback } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import Header from "../components/Header";
import ReferenciaOperacional from "../components/commercial/ReferenciaOperacional";
import PainelPreco from "../components/commercial/PainelPreco";
import CampanhaNatalInstagram from "../components/commercial/CampanhaNatalInstagram";
import SeletorSegmento from "../components/commercial/SeletorSegmento";
import { obterTerritorio } from "../lib/commercialTerritory";
import { fetchCurrentFormation } from "../services/commercialService";
import { obterVinculosParceiro } from "../services/partnerApplicationService";
import {
  getFutureInterest,
  joinFutureQueue,
  type FutureInterest,
} from "../services/commercialFutureInterestService";
import { mensagemSegmento } from "../services/commercialSegmentService";
import {
  nicheByCode,
  nicheCodeFromSlug,
  canonicalSlugFromLegacy,
  isLegacyNicheCode,
} from "../domain/commercial/niches";
import {
  OPPORTUNITY_STATUS_LABEL,
  EXCLUSIVITY_STATUS_LABEL,
} from "../domain/commercial/status";
import type {
  CommercialFormationResponse,
  CommercialSegment,
} from "../domain/commercial/types";

const SEGMENT_ERRORS = new Set([
  "segment_required",
  "segment_not_approved",
  "supermarket_not_substitutable",
  "position_not_substitutable",
  "company_already_waitlisted_other_segment",
]);

type Estado =
  | { fase: "loading" }
  | { fase: "erro" }
  | { fase: "codigo_invalido" }
  | { fase: "nao_encontrada" }
  // Link antigo de calçados F/M depois da unificação: leva a Calçados.
  | { fase: "redirecionar_calcados" }
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
  const [ownerCompanyId, setOwnerCompanyId] = useState<string | null>(null);
  const [future, setFuture] = useState<FutureInterest>({ tipo: "none" });
  const [futureBusy, setFutureBusy] = useState(false);
  const [segmento, setSegmento] = useState<CommercialSegment | null>(null);

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
        const temCalcados = dados.opportunities.some((o) => o.nicheCode === "footwear");
        setEstado(
          isLegacyNicheCode(codigo) && temCalcados
            ? { fase: "redirecionar_calcados" }
            : { fase: "nao_encontrada" }
        );
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

  useEffect(() => {
    let ativo = true;
    void (async () => {
      const v = await obterVinculosParceiro();
      if (!ativo || v.tipo !== "ok") return;
      const owner = v.vinculos.find(
        (item) => item.role === "partner_owner" && item.member_status === "active"
      );
      setOwnerCompanyId(owner?.company_id ?? null);
    })();
    return () => {
      ativo = false;
    };
  }, []);

  useEffect(() => {
    if (!ownerCompanyId || !codigo) return;
    let ativo = true;
    void (async () => {
      const r = await getFutureInterest({
        companyId: ownerCompanyId,
        nicheCode: codigo,
      });
      if (ativo) setFuture(r);
    })();
    return () => {
      ativo = false;
    };
  }, [ownerCompanyId, codigo]);

  const registrarInteresseFuturo = async () => {
    if (!ownerCompanyId || !codigo || futureBusy) return;
    setFutureBusy(true);
    const r = await joinFutureQueue({
      companyId: ownerCompanyId,
      nicheCode: codigo,
      segmentId: segmento?.id ?? null,
    });
    setFutureBusy(false);
    setFuture(r);
  };

  const meta = codigo ? nicheByCode(codigo) : null;

  // Redirecionamento interno único de URL legada (underscore) → hífen.
  // Sem loop: o slug de destino já é canônico e cai em nicheCodeFromSlug.
  if (redirecionarPara) {
    return <Navigate to={`/oportunidades/${redirecionarPara}`} replace />;
  }
  if (estado.fase === "redirecionar_calcados") {
    return <Navigate to="/oportunidades/footwear" replace />;
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
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
          // Segmentos que já ocupam OUTRAS posições (dado público da formação).
          const ocupados = new Set(
            estado.dados.opportunities
              .filter((o) => o.id !== opp.id && o.segment)
              .map((o) => o.segment!.code)
          );
          const segmentoPendente = opp.requiresSegment && !segmento;
          return (
            <>
              <header className="mt-4">
                <div className="flex items-center gap-3">
                  <span aria-hidden className="text-4xl leading-none">
                    {meta.icon}
                  </span>
                  <div className="min-w-0">
                    <h1 className="text-3xl leading-tight sm:text-4xl">{meta.displayName}</h1>
                    <p className="mt-1 text-sm text-tinta/60">
                      {estado.dados.region?.regionName} · Exclusividade{" "}
                      {estado.dados.exclusivity?.sequenceNumber}
                    </p>
                  </div>
                </div>
                <ul className="mt-4 flex flex-wrap gap-2 text-sm" aria-label="Resumo da oportunidade">
                  <li className="rounded-full border border-borda bg-superficie px-3 py-1">
                    <span className="font-semibold">{opp.contractedQuantity}</span> unidades comerciais
                  </li>
                  <li className="rounded-full border border-borda bg-superficie px-3 py-1">
                    {OPPORTUNITY_STATUS_LABEL[opp.status]}
                  </li>
                  {opp.segment && (
                    <li className="rounded-full border border-borda bg-superficie px-3 py-1">
                      Segmento: <span className="font-semibold">{opp.segment.name}</span>
                    </li>
                  )}
                  {estado.dados.exclusivity && (
                    <li className="rounded-full border border-borda bg-superficie px-3 py-1">
                      Exclusividade: {EXCLUSIVITY_STATUS_LABEL[estado.dados.exclusivity.status]}
                    </li>
                  )}
                </ul>
                <p className="mt-4 max-w-leitura text-sm text-tinta/70">
                  {meta.shortDescription}{" "}
                  Publicidade visual com bandeiras instaladas sobre veículos
                  de motoristas participantes do SmallFlags App. A posição é contratada integralmente, com{" "}
                  {opp.contractedQuantity} unidades comerciais.
                </p>
              </header>

              <PainelPreco
                nicheCode={meta.code}
                segmentId={segmento?.id ?? null}
                segmentoPendente={segmentoPendente}
                antesDaContratacao={
                  opp.acceptsSegment ? (
                    <SeletorSegmento
                      oportunidade={opp}
                      ocupados={ocupados}
                      ownerCompanyId={ownerCompanyId}
                      valor={segmento}
                      onChange={setSegmento}
                    />
                  ) : null
                }
              />

              <CampanhaNatalInstagram />

              <div className="card mt-6 p-6">
                <h2 className="text-lg font-bold">Sobre esta oportunidade</h2>
                <p className="mt-2 text-sm text-tinta/70">
                  A divulgação depende das condições técnicas da bandeira e das
                  autorizações aplicáveis. Não há venda de unidades avulsas.
                </p>
                {opp.status === "available" ? (
                  <p className="mt-3 aviso-atencao text-tinta/70">
                    Quando a contratação estiver disponível, o titular autenticado
                    avança ao checkout para reservar a oportunidade por 30 minutos
                    e, após o aceite dos termos, iniciar o pagamento.
                  </p>
                ) : (
                  <div className="mt-3 aviso-atencao text-tinta/70">
                    <p>
                      A oportunidade atual não está disponível. O titular da empresa
                      pode registrar interesse na próxima exclusividade. Esse registro
                      não cria contrato, reserva, pagamento nem fidelidade.
                    </p>

                    {ownerCompanyId ? (
                      <div className="mt-4">
                        {future.tipo === "preorder" ? (
                          <div className="rounded-xl bg-superficie2 p-3">
                            <p className="font-semibold">
                              Pré-compra registrada para a exclusividade {future.targetSequenceNumber}.
                            </p>
                            <p className="mt-1 text-xs">
                              Status: {future.status}. A contratação só nasce depois de
                              uma oportunidade real ser oferecida e das etapas comerciais
                              aplicáveis serem concluídas.
                            </p>
                          </div>
                        ) : future.tipo === "sales_waitlist" ? (
                          <div className="rounded-xl bg-superficie2 p-3">
                            <p className="font-semibold">
                              Lista de espera de venda registrada.
                            </p>
                            <p className="mt-1 text-xs">
                              Posição histórica: {future.position}. Primeira exclusividade
                              possível: {future.firstPossibleExclusivitySequence}. A posição
                              não equivale a contrato ou exclusividade.
                            </p>
                          </div>
                        ) : (
                          <button
                            type="button"
                            onClick={registrarInteresseFuturo}
                            disabled={futureBusy || future.tipo === "erro" || segmentoPendente}
                            className="btn-primary w-full disabled:opacity-50"
                          >
                            {futureBusy
                              ? "Registrando..."
                              : segmentoPendente
                                ? "Escolha o segmento para registrar interesse"
                                : "Registrar interesse na próxima exclusividade"}
                          </button>
                        )}

                        {future.tipo === "erro" && (
                          <p className="mt-2 text-sm text-vermelho" role="alert">
                            {future.codigo === "current_opportunity_available"
                              ? "A oportunidade atual voltou a ficar disponível; use o checkout normal."
                              : future.codigo === "company_already_preordered_next_exclusivity"
                                ? "Esta empresa já possui uma pré-compra ativa em outro nicho da próxima exclusividade."
                                : SEGMENT_ERRORS.has(future.codigo)
                                  ? mensagemSegmento(future.codigo)
                                  : "Não foi possível registrar o interesse agora."}
                          </p>
                        )}
                      </div>
                    ) : (
                      <p className="mt-3 text-xs">
                        Entre como responsável da empresa para registrar interesse futuro.
                      </p>
                    )}
                  </div>
                )}
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
