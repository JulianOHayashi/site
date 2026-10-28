import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../components/Header";
import {
  formatarCentavos,
  type PublicNichePricing,
} from "../domain/pricing/contractPricing";
import {
  BENEFIT_SETTLEMENT_MODES,
  type BenefitSettlementMode,
} from "../domain/pricing/commercialV2";
import { fetchPublicPricing } from "../services/commercialService";

/**
 * /checkout — superfície de REVISÃO da contratação vigente.
 *
 * NOME DO ARQUIVO
 * O componente NÃO se chama Checkout.tsx de propósito. Esse caminho pertence
 * à loja de camisas revogada e o verificador de legado o proíbe, com razão:
 * a rota comercial é nova, e reaproveitar o nome do arquivo antigo faria o
 * guarda permanente acusar reconstrução do legado. A rota pública continua
 * sendo /checkout; só o módulo mudou de nome.
 *
 * POR QUE ISTO NÃO CRIA PEDIDO
 * O ciclo de vida aceito é manual-first: o pedido de exclusividade nasce de
 * um caminho servidor com contrato assinado e conferência de fidelidade. Uma
 * rota pública que criasse pedido contornaria essa autoridade. Então esta
 * página REVISA e explica, e a criação da intenção comercial exige titular
 * autenticado pela RPC create_commercial_checkout_intent.
 *
 * O QUE O NAVEGADOR PODE E NÃO PODE
 * Pode escolher: a forma de disponibilização dos benefícios.
 * Não pode escolher, e não há caminho para isso: fidelidade, versão da
 * tabela, preço unitário, valor econômico, pool, parcela SmallFlags, forma de
 * pagamento ou valor da cobrança. Os números abaixo são REFERÊNCIA pública da
 * tabela vigente; a proposta vinculante é sempre a que o servidor calcula.
 *
 * A condição fidelizada nunca é escolhida aqui: ela é derivada pelo servidor
 * a partir de CNPJ, cidade e nicho. A pré-visualização de referência mostra a
 * condição fundadora, que é a de quem ainda não tem histórico.
 */

const ROTULO_MODO: Record<BenefitSettlementMode, string> = {
  direct_benefits: "Benefícios diretos",
  cash: "Dinheiro real",
};

import {
  reservarOportunidade,
  type ReservaComercial,
} from "../services/commercialReservationService";
import { obterVinculosParceiro } from "../services/partnerApplicationService";
import { obterDisponibilidadePagamento } from "../services/paymentAvailabilityService";
import EtapasContratacao from "./comercial/EtapasContratacao";

/**
 * Bloco de reserva — só aparece para TITULAR ativo com vínculo durável.
 *
 * Tudo que ele mostra vem da resposta do servidor: o prazo é `reserved_until`
 * calculado com `now()` do banco, não um relógio do navegador. Um contador
 * regressivo pode ser somado depois, mas ele exibe, não decide.
 */
export default function RevisaoContratacao() {
  const [params] = useSearchParams();
  // Apenas a SELEÇÃO de nicho vem da URL. Catálogo, quantidade e todos os
  // valores materiais vêm da autoridade pública do servidor. Um nicho explícito
  // desconhecido falha fechado — nunca cai silenciosamente em supermercado.
  const nichoParam = params.get("nicho");
  const [precos, setPrecos] = useState<
    | { fase: "carregando" }
    | { fase: "indisponivel" }
    | { fase: "ok"; lista: PublicNichePricing[] }
  >({ fase: "carregando" });
  const [modo, setModo] = useState<BenefitSettlementMode>("direct_benefits");

  const [empresa, setEmpresa] = useState<string | null>(null);
  const [perfilComercial, setPerfilComercial] = useState<
    "carregando" | "owner" | "manager" | "sem_vinculo" | "erro"
  >("carregando");
  const [reserva, setReserva] = useState<ReservaComercial | null>(null);
  const [reservando, setReservando] = useState(false);
  const [falhaReserva, setFalhaReserva] = useState<string | null>(null);
  const [disponibilidadePagamento, setDisponibilidadePagamento] = useState<
    "carregando" | "disponivel" | "indisponivel"
  >("carregando");

  useEffect(() => {
    let vivo = true;
    void fetchPublicPricing()
      .then((lista) => {
        if (!vivo) return;
        setPrecos(lista.length > 0 ? { fase: "ok", lista } : { fase: "indisponivel" });
      })
      .catch(() => {
        if (vivo) setPrecos({ fase: "indisponivel" });
      });
    return () => {
      vivo = false;
    };
  }, []);

  const nicho = useMemo(() => {
    if (precos.fase !== "ok") return null;
    if (nichoParam === null) return precos.lista[0] ?? null;
    return precos.lista.find((item) => item.nicheCode === nichoParam) ?? null;
  }, [nichoParam, precos]);

  const composicao = nicho?.founding ?? null;

  // O checkout só abre quando o runtime server-side confirma que o provedor
  // está configurado. Qualquer falha nessa consulta bloqueia (fail-closed).
  useEffect(() => {
    let vivo = true;
    void (async () => {
      const r = await obterDisponibilidadePagamento();
      if (!vivo) return;
      setDisponibilidadePagamento(
        r.tipo === "disponivel" ? "disponivel" : "indisponivel"
      );
    })();
    return () => {
      vivo = false;
    };
  }, []);

  // Só descobrimos se há vínculo de titular; a autorização real é do servidor.
  useEffect(() => {
    let vivo = true;
    void (async () => {
      const v = await obterVinculosParceiro();
      if (!vivo) return;

      if (v.tipo !== "ok") {
        setEmpresa(null);
        setPerfilComercial("erro");
        return;
      }

      const owner = v.vinculos.find(
        (item) => item.role === "partner_owner" && item.member_status === "active"
      );
      if (owner) {
        setEmpresa(owner.company_id);
        setPerfilComercial("owner");
        return;
      }

      const manager = v.vinculos.find(
        (item) => item.role === "partner_manager" && item.member_status === "active"
      );
      setEmpresa(null);
      setPerfilComercial(manager ? "manager" : "sem_vinculo");
    })();
    return () => {
      vivo = false;
    };
  }, []);

  const reservar = useCallback(async () => {
    if (!empresa || !nicho || reservando || disponibilidadePagamento !== "disponivel") return;
    setReservando(true);
    setFalhaReserva(null);
    const r = await reservarOportunidade({
      companyId: empresa,
      nicheCode: nicho.nicheCode,
      benefitSettlementMode: modo,
    });
    setReservando(false);
    if (r.tipo === "ok") setReserva(r.reserva);
    else setFalhaReserva(r.codigo);
  }, [disponibilidadePagamento, empresa, modo, nicho, reservando]);

  return (
    <>
      <Header />
      <main className="mx-auto max-w-3xl px-4 py-10">
        <h1 className="text-3xl">Revisão da contratação</h1>
        <p className="mt-2 text-sm text-tinta/60">
          Referência pública da tabela vigente. A proposta vinculante é emitida
          pela SmallFlags após a análise do cadastro.
        </p>

        {precos.fase === "carregando" ? (
          <section className="card mt-6 p-6" role="status">
            Carregando condições comerciais...
          </section>
        ) : precos.fase === "indisponivel" || !nicho || !composicao ? (
          <section className="card mt-6 p-6" role="alert">
            <h2 className="text-lg font-bold">Condições comerciais indisponíveis</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Não foi possível validar o nicho e a tabela vigente no servidor.
              Nenhum valor foi estimado localmente e nenhuma contratação foi liberada.
            </p>
          </section>
        ) : (
          <>
        <section className="card mt-6 p-6" aria-labelledby="nicho-titulo">
          <h2 id="nicho-titulo" className="text-lg font-bold">
            {nicho.displayName}
          </h2>
          <p className="mt-1 text-xs text-tinta/60">
            Nicho contratado integralmente — {nicho.nominalQuantity} unidades.
          </p>

          <dl className="mt-4 divide-y divide-tinta/10">
            <Linha
              rotulo="Valor econômico da contratação"
              valor={formatarCentavos(composicao.economicValueCents)}
            />
            {composicao.meiConsiderationCents !== null &&
            composicao.smallflagsQaCents !== null &&
            composicao.smallflagsMainFeeCents !== null &&
            composicao.smallflagsTotalRemunerationCents !== null ? (
              <>
                <Linha
                  rotulo="Contraprestação dos MEIs"
                  valor={formatarCentavos(composicao.meiConsiderationCents)}
                />
                <Linha
                  rotulo="Parcela de QA da SmallFlags"
                  valor={formatarCentavos(composicao.smallflagsQaCents)}
                />
                <Linha
                  rotulo="Pool contratual total (MEIs + QA)"
                  valor={formatarCentavos(composicao.contractualPoolCents)}
                />
                <Linha
                  rotulo="Parcela operacional principal da SmallFlags"
                  valor={formatarCentavos(composicao.smallflagsMainFeeCents)}
                />
                <Linha
                  rotulo="Remuneração contratual total da SmallFlags"
                  valor={formatarCentavos(composicao.smallflagsTotalRemunerationCents)}
                />
              </>
            ) : (
              <>
                <Linha
                  rotulo={`Pool contratual total${composicao.displayPoolPercent ? ` (${composicao.displayPoolPercent})` : ""}`}
                  valor={formatarCentavos(composicao.contractualPoolCents)}
                />
                <Linha
                  rotulo="SmallFlags + operação + investimentos"
                  valor={formatarCentavos(composicao.bdflowDueCents)}
                />
              </>
            )}
          </dl>
        </section>

        <section className="card mt-6 p-6" aria-labelledby="modo-titulo">
          <h2 id="modo-titulo" className="text-lg font-bold">
            Como a empresa deseja cumprir a parcela destinada aos benefícios?
          </h2>

          <fieldset className="mt-4 space-y-3">
            <legend className="sr-only">
              Forma de disponibilização dos benefícios
            </legend>
            {BENEFIT_SETTLEMENT_MODES.map((m) => (
              <label
                key={m}
                className={`flex cursor-pointer gap-3 rounded-xl border p-4 ${
                  modo === m
                    ? "border-tinta bg-papel2 font-semibold"
                    : "border-tinta/15"
                }`}
              >
                <input
                  type="radio"
                  name="benefit_settlement_mode"
                  value={m}
                  checked={modo === m}
                  onChange={() => setModo(m)}
                  className="mt-1"
                />
                <span className="text-sm">
                  {/* Seleção nunca é comunicada só por cor: o rótulo marcado
                      também é textual e o radio é operável por teclado. */}
                  <span className="block">
                    {ROTULO_MODO[m]}
                    {modo === m ? " — selecionado" : ""}
                  </span>
                  <span className="mt-1 block font-normal text-tinta/70">
                    {m === "direct_benefits"
                      ? composicao.pricingRuleVersion >= 3
                        ? "A empresa cumpre diretamente perante os MEIs elegíveis a contraprestação prevista; a remuneração da SmallFlags, inclusive QA, permanece devida em dinheiro."
                        : "A empresa disponibiliza os benefícios diretamente aos usuários elegíveis, conforme as regras operacionais."
                      : composicao.pricingRuleVersion >= 3
                        ? "A empresa aporta em dinheiro a contraprestação dos MEIs elegíveis, além da remuneração contratual da SmallFlags."
                        : "A empresa aporta em dinheiro o valor do pool destinado aos usuários elegíveis que cumprirem as tarefas e requisitos aplicáveis."}
                  </span>
                </span>
              </label>
            ))}
          </fieldset>
        </section>

        <section className="card mt-6 p-6" aria-labelledby="cobranca-titulo">
          <h2 id="cobranca-titulo" className="text-lg font-bold">
            Resumo da cobrança
          </h2>

          <dl className="mt-4 divide-y divide-tinta/10">
            <Linha
              rotulo="Condição comercial"
              valor={
                composicao.fidelized ? "Fidelizada" : "Não fidelizada"
              }
            />
            {/* Trilho é DERIVADO da fidelidade no servidor: leitura, não
                escolha. Não existe seletor Pix/cartão nesta tela. */}
            <Linha
              rotulo="Forma de pagamento"
              valor={
                composicao.paymentMethod === "pix"
                  ? "Pix"
                  : composicao.paymentMethod === "credit_card"
                    ? "Cartão de crédito"
                    : "Definida pelo servidor"
              }
            />
            <Linha
              rotulo={
                modo === "cash"
                  ? composicao.pricingRuleVersion >= 3
                    ? "Contraprestação dos MEIs financiada em dinheiro"
                    : "Pool em dinheiro para usuários"
                  : composicao.pricingRuleVersion >= 3
                    ? "Contraprestação cumprida em benefício direto"
                    : "Pool em benefícios diretos"
              }
              valor={formatarCentavos(composicao.directBenefitDeliverableCents)}
            />
            {composicao.smallflagsTotalRemunerationCents !== null ? (
              <Linha
                rotulo="Remuneração contratual da SmallFlags"
                valor={formatarCentavos(composicao.smallflagsTotalRemunerationCents)}
              />
            ) : (
              <Linha
                rotulo="SmallFlags + operação + investimentos"
                valor={formatarCentavos(composicao.bdflowDueCents)}
              />
            )}
            <Linha
              rotulo="Valor financeiro da cobrança"
              valor={formatarCentavos(
                modo === "cash"
                  ? composicao.fundingCashCents
                  : composicao.fundingDirectBenefitsCents
              )}
              destaque
            />
          </dl>

          <p className="mt-3 text-xs text-tinta/60">
            {composicao.pricingRuleVersion >= 3
              ? modo === "cash"
                ? "A cobrança em dinheiro corresponde ao valor econômico integral. A contraprestação dos MEIs e a remuneração da SmallFlags permanecem contabilmente separadas."
                : "A contraprestação ordinária dos MEIs é cumprida diretamente pela empresa. A remuneração contratual da SmallFlags, inclusive a parcela de QA, continua devida em dinheiro."
              : modo === "cash"
                ? "O aporte em dinheiro corresponde ao pool contratual dos usuários elegíveis; a liberação individual continua sujeita às regras operacionais do App."
                : "O pool histórico é cumprido pela empresa em benefícios diretos, e a parcela operacional permanece devida à SmallFlags."}
          </p>
        </section>

        <p className="mt-6 text-center text-sm text-tinta/60">
          A reserva não cobra valores. O pagamento só é iniciado após a
          reserva, o aceite dos termos vigentes e a finalização do pedido pelo
          servidor.
        </p>

        {reserva ? (
          <section className="card mt-6 p-6" aria-labelledby="reserva-titulo">
            <h2 id="reserva-titulo" className="text-lg font-bold">
              Oportunidade reservada por {reserva.reservationMinutes} minutos
            </h2>
            <p className="mt-2 text-sm text-tinta/70">
              O nicho inteiro está reservado para a sua empresa até{" "}
              <strong>
                {new Date(reserva.reservedUntil).toLocaleString("pt-BR")}
              </strong>
              . Passado esse prazo a oportunidade volta a ficar disponível.
            </p>
            <p className="mt-2 text-xs text-tinta/60">
              Reserva não é pagamento nem contrato. Nenhum valor foi cobrado.
            </p>
            {reserva.already && (
              <p className="mt-2 text-xs text-tinta/60">
                Você já tinha esta reserva em andamento; o prazo original foi
                mantido.
              </p>
            )}
          </section>
        ) : null}

        {disponibilidadePagamento === "carregando" ? (
          <p className="mt-6 text-center text-sm text-tinta/60" role="status">
            Verificando disponibilidade do pagamento...
          </p>
        ) : disponibilidadePagamento === "indisponivel" ? (
          <section className="card mt-6 p-6 text-center" role="alert">
            <h2 className="text-lg font-bold">Contratação temporariamente indisponível</h2>
            <p className="mt-2 text-sm text-tinta/70">
              O processamento de pagamentos está temporariamente indisponível.
              Para evitar uma reserva ou contrato sem possibilidade de cobrança,
              novas contratações estão pausadas. Nenhum valor foi cobrado.
            </p>
          </section>
        ) : reserva ? (
          // Contrato e pagamento só aparecem DEPOIS da reserva viva, e todos
          // os valores vêm da resposta do servidor.
          <EtapasContratacao
            intentId={reserva.intentId}
            amountCents={reserva.totalMonetaryFundingRequiredCents}
            fidelizado={reserva.fidelized}
          />
        ) : perfilComercial === "owner" && empresa ? (
          <>
            <button
              onClick={reservar}
              disabled={reservando}
              className="btn-primary mt-4 w-full disabled:opacity-50"
            >
              {reservando ? "Reservando..." : "Reservar por 30 minutos"}
            </button>
            {falhaReserva && (
              <div
                role="alert"
                className="mt-3 aviso-erro p-3"
              >
                {falhaReserva === "opportunity_reserved"
                  ? "Esta oportunidade está reservada por outra empresa no momento."
                  : falhaReserva === "not_company_owner"
                    ? "Apenas o responsável da empresa pode reservar."
                    : falhaReserva === "company_already_contracted_in_exclusivity"
                      ? "Esta empresa já possui um nicho contratado nesta exclusividade. Cada CNPJ pode contratar apenas um nicho por exclusividade."
                      : falhaReserva === "region_not_operating"
                        ? "Ainda não operamos na cidade cadastrada para a sua empresa."
                        : "Não foi possível reservar agora. Nada foi cobrado."}
              </div>
            )}
          </>
        ) : perfilComercial === "manager" ? (
          <section className="card mt-6 p-6 text-center" role="alert">
            <h2 className="text-lg font-bold">Acesso comercial restrito ao responsável da empresa</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Managers podem operar as validações das unidades autorizadas, mas não podem
              reservar oportunidades, aceitar termos comerciais, finalizar contratos ou
              iniciar pagamentos.
            </p>
          </section>
        ) : perfilComercial === "carregando" ? (
          <p className="mt-6 text-center text-sm text-tinta/60" role="status">
            Verificando acesso comercial...
          </p>
        ) : perfilComercial === "erro" ? (
          <div role="alert" className="mt-6 aviso-erro p-3">
            Não foi possível verificar o acesso comercial. Nenhuma contratação foi liberada.
          </div>
        ) : (
          <Link
            to="/parceiros/cadastro"
            className="btn-primary mt-4 inline-block w-full text-center"
          >
            Solicitar contratação
          </Link>
        )}
          </>
        )}
      </main>
    </>
  );
}

function Linha({
  rotulo,
  valor,
  destaque,
}: {
  rotulo: string;
  valor: string;
  destaque?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2">
      <dt className="text-sm text-tinta/70">{rotulo}</dt>
      <dd className={destaque ? "text-lg font-bold" : "text-sm font-semibold"}>
        {valor}
      </dd>
    </div>
  );
}
