import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../components/Header";
import { formatarCentavos } from "../domain/pricing/contractPricing";
import {
  computeCommercialCompositionV2,
  fundingForSettlementMode,
  BENEFIT_SETTLEMENT_MODES,
  type BenefitSettlementMode,
} from "../domain/pricing/commercialV2";

/**
 * /checkout — superfície de REVISÃO da contratação, Comercial V2.
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
 * tabela, preço unitário, valor econômico, pool, parcela BDFlow, forma de
 * pagamento ou valor da cobrança. Os números abaixo são REFERÊNCIA pública da
 * tabela vigente; a proposta vinculante é sempre a que o servidor calcula.
 *
 * A condição fidelizada nunca é escolhida aqui: ela é derivada pelo servidor
 * a partir de CNPJ, cidade e nicho. A pré-visualização de referência mostra a
 * condição fundadora, que é a de quem ainda não tem histórico.
 */

const NICHOS_REFERENCIA = [
  { code: "supermarket", nome: "Supermercado", quantidade: 24 },
  { code: "pharmacy", nome: "Farmácia", quantidade: 12 },
  { code: "womens_clothing", nome: "Roupas femininas", quantidade: 12 },
  { code: "mens_clothing", nome: "Roupas masculinas", quantidade: 12 },
  { code: "womens_footwear", nome: "Calçados femininos", quantidade: 12 },
  { code: "mens_footwear", nome: "Calçados masculinos", quantidade: 12 },
];

const ROTULO_MODO: Record<BenefitSettlementMode, string> = {
  direct_benefits: "Benefícios diretos",
  cash: "Dinheiro real",
};

export default function RevisaoContratacao() {
  const [params] = useSearchParams();
  // Apenas SELEÇÃO de nicho vem da URL. Nenhum valor monetário é aceito de
  // query string, e nada aqui lê localStorage.
  const nichoParam = params.get("nicho");
  const nicho =
    NICHOS_REFERENCIA.find((n) => n.code === nichoParam) ?? NICHOS_REFERENCIA[0];

  const [modo, setModo] = useState<BenefitSettlementMode>("direct_benefits");

  // Condição fundadora: quem revisa publicamente ainda não tem histórico.
  const composicao = useMemo(
    () => computeCommercialCompositionV2(nicho.code, nicho.quantidade, false),
    [nicho.code, nicho.quantidade]
  );
  const funding = useMemo(
    () => fundingForSettlementMode(composicao, modo),
    [composicao, modo]
  );

  return (
    <>
      <Header />
      <main className="mx-auto max-w-3xl px-4 py-10">
        <h1 className="text-3xl">Revisão da contratação</h1>
        <p className="mt-2 text-sm text-tinta/60">
          Referência pública da tabela vigente. A proposta vinculante é emitida
          pela BDFlow após a análise do cadastro.
        </p>

        <section className="card mt-6 p-6" aria-labelledby="nicho-titulo">
          <h2 id="nicho-titulo" className="text-lg font-bold">
            {nicho.nome}
          </h2>
          <p className="mt-1 text-xs text-tinta/50">
            Nicho contratado integralmente — {nicho.quantidade} unidades.
          </p>

          <dl className="mt-4 divide-y divide-tinta/10">
            <Linha
              rotulo="Valor econômico da contratação"
              valor={formatarCentavos(composicao.economicValueCents)}
            />
            <Linha
              rotulo={`Pool destinado aos usuários BDFlow (${composicao.displayPoolPercent})`}
              valor={formatarCentavos(composicao.userPoolCents)}
            />
            <Linha
              rotulo="BDFlow + operação + investimentos"
              valor={formatarCentavos(composicao.bdflowOpsInvestmentCents)}
            />
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
                      ? "A empresa disponibiliza os benefícios diretamente aos usuários elegíveis, conforme as regras operacionais."
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
                composicao.paymentMethod === "pix" ? "Pix" : "Cartão de crédito"
              }
            />
            <Linha
              rotulo={
                modo === "cash"
                  ? "Pool em dinheiro para usuários"
                  : "Pool em benefícios diretos"
              }
              valor={formatarCentavos(funding.userPoolCents)}
            />
            <Linha
              rotulo="BDFlow + operação + investimentos"
              valor={formatarCentavos(funding.bdflowOpsInvestmentCents)}
            />
            <Linha
              rotulo="Valor financeiro da cobrança"
              valor={formatarCentavos(funding.commercialChargeCents)}
              destaque
            />
          </dl>

          <p className="mt-3 text-xs text-tinta/60">
            {modo === "cash"
              ? "O aporte em dinheiro é economicamente destinado aos usuários elegíveis que cumprirem os requisitos operacionais. A liberação de cada benefício é determinada pelas regras operacionais do App."
              : "O valor do pool é cumprido pela empresa em benefícios diretos, sob as regras operacionais. À BDFlow é devida apenas a parcela de BDFlow, operação e investimentos."}
          </p>
        </section>

        <p className="mt-6 text-center text-sm text-tinta/60">
          Esta página não realiza pagamento, não gera contrato e não confirma
          contratação. Nenhum provedor de pagamento está integrado.
        </p>
        <Link
          to="/parceiros/cadastro"
          className="btn-primary mt-4 inline-block w-full text-center"
        >
          Solicitar contratação
        </Link>
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
