import { useEffect, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { fetchPublicPricing } from "../../services/commercialService";
import {
  formatarCentavos,
  type PublicNichePricing,
} from "../../domain/pricing/contractPricing";
import {
  apresentacaoOportunidade,
  type ApresentacaoOportunidade,
  type CondicaoApresentada,
} from "../../domain/pricing/apresentacaoComercial";

/**
 * Apresentação comercial do valor de UMA oportunidade (página de detalhe).
 *
 * Ordem de leitura:
 *   1. valor total da contratação, em destaque, e a renovação fidelizada como
 *      condição definida pela SmallFlags (nunca selecionável);
 *   2. as duas formas de cumprir a contraprestação dos participantes —
 *      benefício direto em produtos ou dinheiro — com o MESMO valor total;
 *   3. composição técnica, recolhida;
 *   4. contratação, que só existe com a autoridade vigente no servidor.
 *
 * Os números vêm de `get_public_niche_pricing` (via `apresentacaoOportunidade`).
 * Resposta incompleta ou incoerente: nenhum valor é exibido. A prévia SF-v1.5
 * nunca abre a contratação. A contratação só é oferecida quando o servidor
 * declara a versão vigente E as duas modalidades com composição aprovada
 * (`ap.contratavel`).
 *
 * Regra R3: a QA existe só no benefício direto, em produtos para testes
 * locais; não é cobrada em dinheiro e não existe na forma em dinheiro. A
 * igualdade de valor entre as formas só é afirmada quando o servidor a publica.
 */
export default function PainelPreco({
  nicheCode,
  segmentId = null,
  segmentoPendente = false,
  antesDaContratacao = null,
}: {
  nicheCode: string;
  /** Segmento de Outros escolhido para a posição (o servidor valida). */
  segmentId?: string | null;
  /** Posição Outros sem segmento escolhido: não há o que contratar ainda. */
  segmentoPendente?: boolean;
  /** Conteúdo exibido logo antes da contratação (ex.: seletor de segmento). */
  antesDaContratacao?: ReactNode;
}) {
  const [estado, setEstado] = useState<
    | { fase: "carregando" }
    | { fase: "indisponivel" }
    | { fase: "ok"; preco: PublicNichePricing; ap: ApresentacaoOportunidade }
  >({ fase: "carregando" });

  useEffect(() => {
    let ativo = true;
    fetchPublicPricing()
      .then((lista) => {
        if (!ativo) return;
        const preco = lista.find((p) => p.nicheCode === nicheCode) ?? null;
        const ap = apresentacaoOportunidade(preco);
        setEstado(preco && ap ? { fase: "ok", preco, ap } : { fase: "indisponivel" });
      })
      .catch(() => {
        if (ativo) setEstado({ fase: "indisponivel" });
      });
    return () => {
      ativo = false;
    };
  }, [nicheCode]);

  if (estado.fase === "carregando") {
    return (
      <div className="card mt-6 p-6 text-sm text-tinta/60" aria-live="polite">
        Carregando condições comerciais...
      </div>
    );
  }

  if (estado.fase === "indisponivel") {
    return (
      <>
        <section className="card mt-6 p-6" aria-live="polite">
          <h2 className="text-lg font-bold">Condições comerciais</h2>
          <p className="mt-2 text-sm text-tinta/70">
            As condições vigentes não estão disponíveis no momento. Fale com a
            SmallFlags para receber a proposta atualizada.
          </p>
          <p className="mt-2 text-sm font-semibold">
            Contratação temporariamente indisponível.
          </p>
          <Link to="/contato" className="btn-secondary mt-4 inline-block">
            Falar com a SmallFlags
          </Link>
        </section>
        {antesDaContratacao}
      </>
    );
  }

  const { ap, preco } = estado;
  return (
    <>
      <ResumoValor ap={ap} />
      <Modalidades ap={ap} />
      <Composicao ap={ap} preco={preco} />
      {antesDaContratacao}
      <Contratacao
        ap={ap}
        nicheCode={nicheCode}
        segmentId={segmentId}
        segmentoPendente={segmentoPendente}
      />
    </>
  );
}

/* ------------------------------------------------------------------------- */

function ResumoValor({ ap }: { ap: ApresentacaoOportunidade }) {
  return (
    <section
      className="card mt-6 overflow-hidden"
      aria-labelledby="valor-total-titulo"
      data-testid="resumo-valor"
    >
      <div aria-hidden className="h-1 bg-marca" />
      <div className="p-6">
        <p
          id="valor-total-titulo"
          className="text-xs font-semibold uppercase tracking-wide text-tinta/55"
        >
          Valor total da contratação
        </p>
        <p className="mt-2 font-display text-4xl font-bold leading-none tabular-nums sm:text-5xl">
          {formatarCentavos(somenteDinheiro(ap) ? ap.novo.valorDinheiroCentavos! : ap.novo.valorTotalCentavos)}
        </p>
        <p className="mt-2 text-sm text-tinta/70" data-testid="condicao-novo">
          Condição para novo anunciante
          {somenteDinheiro(ap) ? ", em dinheiro" : ap.mesmoValorNasDuasFormas ? "" : ", com benefício direto"}.
          Inclui a produção das bandeiras da sua marca e as contraprestações
          potenciais dos motoristas participantes.
        </p>

        {ap.estado === "previa" && (
          <div
            className="mt-4 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-950"
            role="note"
            data-testid="aviso-previa"
          >
            <p className="font-semibold">Novo valor proposto · ainda não contratável</p>
            <p className="mt-1">
              Estes valores são informativos. Eles passam a valer quando a
              SmallFlags ativar a nova tabela no sistema; até lá, a contratação
              pelo site fica suspensa.
            </p>
          </div>
        )}

        <div className="mt-5 border-t border-borda pt-4" data-testid="condicao-fidelizada">
          <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <p className="text-sm font-semibold">Renovação para anunciante fidelizado</p>
            <p className="font-display text-xl font-bold tabular-nums">
              {formatarCentavos(somenteDinheiro(ap) ? ap.fidelizado.valorDinheiroCentavos! : ap.fidelizado.valorTotalCentavos)}
            </p>
          </div>
          <p className="mt-1 text-xs text-tinta/65">
            Condição aplicada pela SmallFlags a empresas que renovam a mesma
            posição na mesma cidade, conforme o histórico registrado. Não é uma
            opção a escolher. A fidelidade é mantida mesmo quando a empresa
            muda a frase ou a arte. Bandeiras já produzidas podem ser
            reutilizadas após inspeção; se houver nova fabricação por mudança
            voluntária, ela exige orçamento e aceite, com custo do fornecedor
            cobrado à parte, sem margem de fabricação da SmallFlags.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------------- */

/** R4.3: o servidor vende só o DINHEIRO nesta versão (com preço publicado). */
function somenteDinheiro(ap: ApresentacaoOportunidade): boolean {
  return ap.estado === "vigente" && !ap.beneficioDiretoHabilitado && ap.novo.valorDinheiroCentavos !== null;
}

function Modalidades({ ap }: { ap: ApresentacaoOportunidade }) {
  const total = formatarCentavos(ap.novo.valorTotalCentavos);
  const participantes = formatarCentavos(ap.participantes.contraprestacaoPotencialCentavos);
  const dinheiro =
    ap.novo.valorDinheiroCentavos === null ? null : formatarCentavos(ap.novo.valorDinheiroCentavos);
  return (
    <section className="mt-8" aria-labelledby="modalidades-titulo" data-testid="modalidades">
      <h2 id="modalidades-titulo" className="text-2xl">
        Como sua empresa pode cumprir o valor contratado
      </h2>
      <p className="mt-2 max-w-leitura text-sm text-tinta/70">
        Uma parte do valor corresponde às contraprestações dos motoristas que
        exibem a sua marca pelo SmallFlags App.{" "}
        {somenteDinheiro(ap) ? (
          <span data-testid="total-modalidades">
            No momento, a contratação está disponível somente em dinheiro:
            valor total de{" "}
            <strong className="tabular-nums text-tinta">{dinheiro}</strong>. O
            benefício direto ainda não está disponível.
          </span>
        ) : ap.mesmoValorNasDuasFormas ? (
          <span data-testid="total-modalidades">
            Nas duas formas, o valor total é o mesmo:{" "}
            <strong className="tabular-nums text-tinta">{total}</strong>.
          </span>
        ) : (
          <span data-testid="total-modalidades">
            Sua empresa escolhe como cumprir essa parte. Com benefício direto, o valor total é{" "}
            <strong className="tabular-nums text-tinta">{total}</strong>. Em
            dinheiro não há testes com produtos, e o valor total dessa forma{" "}
            {dinheiro ? (
              <>é <strong className="tabular-nums text-tinta">{dinheiro}</strong>.</>
            ) : (
              "é confirmado na proposta comercial."
            )}
          </span>
        )}
      </p>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <article
          className={`card flex flex-col p-5 ${somenteDinheiro(ap) ? "opacity-60" : "border-vivo-ciano/60"}`}
          aria-labelledby="modalidade-beneficio"
          data-testid="modalidade-beneficio-direto"
        >
          <p className="text-xs font-semibold uppercase tracking-wide text-ciano">
            Benefício direto
            {somenteDinheiro(ap) && (
              <span className="ml-2 text-tinta/70" data-testid="beneficio-direto-indisponivel">
                · indisponível no momento
              </span>
            )}
          </p>
          <h3 id="modalidade-beneficio" className="mt-1 text-lg font-bold leading-snug">
            Parte do investimento pode ser cumprida em benefícios aos motoristas
          </h3>
          <p className="mt-3 font-display text-2xl font-bold tabular-nums">
            Até {participantes} do total
          </p>
          <p className="text-sm text-tinta/70">
            cumpridos em produtos das suas lojas, como benefícios aos motoristas
            participantes
          </p>
          <p className="mt-1 text-xs text-tinta/60">
            {ap.participantes.participacoesPotenciais} participações potenciais ×{" "}
            {formatarCentavos(ap.participantes.valorPorParticipacaoCentavos)} por
            participação aprovada
          </p>
          <ul className="mt-4 space-y-2 text-sm text-tinta/75">
            <Item>
              Sua empresa disponibiliza os benefícios diretamente aos
              participantes elegíveis do SmallFlags App, em produtos das suas
              lojas, nas condições contratadas.
            </Item>
            <Item>
              O App verifica a elegibilidade e confirma cada participação.
            </Item>
            <Item>
              O benefício precisa estar realmente disponível: crédito fictício,
              apenas nominal ou indisponível não conta como cumprimento.
            </Item>
            <li className="flex gap-2" data-testid="dinheiro-beneficio-direto">
              <span aria-hidden className="mt-[0.45rem] h-1.5 w-1.5 shrink-0 rounded-full bg-tinta/40" />
              <span>
                Em dinheiro, nesta forma, só a parcela da SmallFlags:{" "}
                <span className="font-semibold tabular-nums">
                  {formatarCentavos(ap.novo.parcelaSmallFlagsCentavos)}
                </span>
                .
              </span>
            </li>
            <li className="flex gap-2" data-testid="qa-produtos">
              <span aria-hidden className="mt-[0.45rem] h-1.5 w-1.5 shrink-0 rounded-full bg-tinta/40" />
              <span>
                Sua empresa também disponibiliza{" "}
                <span className="font-semibold tabular-nums">
                  {formatarCentavos(ap.qaEmProdutosCentavos)}
                </span>{" "}
                em produtos para testes locais de qualidade autorizados pela
                SmallFlags. Esses produtos não são cobrados em dinheiro e não
                são dos motoristas.
              </span>
            </li>
          </ul>
        </article>

        <article
          className="card flex flex-col p-5"
          aria-labelledby="modalidade-dinheiro"
          data-testid="modalidade-dinheiro"
        >
          <p className="text-xs font-semibold uppercase tracking-wide text-tinta/60">
            Dinheiro
          </p>
          <h3 id="modalidade-dinheiro" className="mt-1 text-lg font-bold leading-snug">
            Prefere não oferecer benefícios diretamente?
          </h3>
          <p className="mt-3 font-display text-2xl font-bold">Tudo em dinheiro</p>
          <p className="text-sm text-tinta/70">
            inclusive os {participantes} dos motoristas, repassados pela
            SmallFlags
          </p>
          {!ap.mesmoValorNasDuasFormas && (
            <p className="mt-1 text-xs text-tinta/60" data-testid="valor-dinheiro">
              {dinheiro
                ? `Valor total nesta forma: ${dinheiro}.`
                : "Valor total nesta forma: confirmado na proposta comercial."}
            </p>
          )}
          <ul className="mt-4 space-y-2 text-sm text-tinta/75">
            <Item>Sua empresa paga o valor integral da contratação em dinheiro.</Item>
            <Item>
              A SmallFlags separa a parcela dos participantes e administra os
              repasses aos elegíveis.
            </Item>
            <Item>
              Os repasses dependem da aprovação das participações e da
              documentação aplicável.
            </Item>
            <Item>
              Os motoristas continuam recebendo a contraprestação; muda apenas
              a forma de cumprir.
            </Item>
            <Item>Nesta forma não há testes com produtos.</Item>
          </ul>
        </article>
      </div>

      <div
        className="mt-4 rounded-xl bg-papel2 px-4 py-3 text-sm text-tinta/80"
        data-testid="mesmo-valor"
      >
        {ap.mesmoValorNasDuasFormas ? (
          <p>
            <strong>As duas formas têm o mesmo valor total.</strong>{" "}
            Benefício direto não é desconto. O que muda é como a parcela dos
            participantes é cumprida.
          </p>
        ) : (
          <p>
            <strong>Benefício direto não é desconto.</strong> As duas formas
            têm a mesma parcela dos participantes e a mesma parcela da
            SmallFlags; só o benefício direto inclui os produtos para testes.
          </p>
        )}
        <p className="mt-1.5 text-xs text-tinta/65">
          A forma de cumprimento não é o meio de pagamento. Pix ou cartão seguem
          as regras do checkout, independentemente da forma escolhida.
        </p>
      </div>
    </section>
  );
}

function Item({ children }: { children: ReactNode }) {
  return (
    <li className="flex gap-2">
      <span aria-hidden className="mt-[0.45rem] h-1.5 w-1.5 shrink-0 rounded-full bg-tinta/40" />
      <span>{children}</span>
    </li>
  );
}

/* ------------------------------------------------------------------------- */

function Composicao({ ap, preco }: { ap: ApresentacaoOportunidade; preco: PublicNichePricing }) {
  const meios =
    ap.estado === "vigente" &&
    preco.founding.paymentMethod === "pix" &&
    preco.fidelized.paymentMethod === "credit_card";
  return (
    <details className="card group mt-8" data-testid="composicao-tecnica">
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 rounded-2xl p-5 font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ciano">
        <span>Detalhes da composição do valor</span>
        <span aria-hidden className="text-tinta/50 transition-transform group-open:rotate-180">
          ▾
        </span>
      </summary>
      <div className="border-t border-borda p-5 text-sm">
        <div className="grid gap-4 sm:grid-cols-2">
          <Bloco
            titulo="Novo anunciante"
            c={ap.novo}
            participantes={ap.participantes.contraprestacaoPotencialCentavos}
          />
          <Bloco
            titulo="Renovação fidelizada"
            c={ap.fidelizado}
            participantes={ap.participantes.contraprestacaoPotencialCentavos}
          />
        </div>
        <ul className="mt-4 space-y-2 text-xs text-tinta/70">
          <Item>
            Contraprestações potenciais: dependem das participações aprovadas pelo
            App. Não são saldo garantido nem liberação automática.
          </Item>
          <Item>
            A parcela de qualidade (QA), de{" "}
            {formatarCentavos(ap.qaEmProdutosCentavos)}, existe só no benefício
            direto: são produtos para testes locais autorizados pela SmallFlags.
            Não é cobrada em dinheiro, não é contraprestação dos participantes e
            não existe na forma em dinheiro.
          </Item>
          <Item>
            Na primeira contratação, o valor inclui a produção inicial das bandeiras
            da marca. Na renovação fidelizada, a reutilização depende de inspeção,
            mas mudar a frase ou a arte não elimina a fidelidade. Se a empresa pedir
            fabricação de nova arte, o custo comprovado do fornecedor é orçado e
            aceito à parte, sem margem da SmallFlags. A reposição por dano continua
            sujeita à política específica, ainda não liberada.
          </Item>
          <Item>
            {meios
              ? "Meio de pagamento no checkout vigente: Pix na primeira contratação e cartão de crédito na renovação fidelizada. Ele não depende da forma de cumprimento."
              : "O meio de pagamento é definido pelo checkout vigente e não depende da forma de cumprimento."}
          </Item>
        </ul>
      </div>
    </details>
  );
}

function Bloco({
  titulo,
  c,
  participantes,
}: {
  titulo: string;
  c: CondicaoApresentada;
  participantes: number;
}) {
  return (
    <div className="rounded-xl border border-borda p-4">
      <p className="font-semibold">{titulo}</p>
      <dl className="mt-2 space-y-1.5">
        <Linha rotulo="Valor total com benefício direto" valor={c.valorTotalCentavos} forte />
        <Linha rotulo="Contraprestações potenciais dos participantes" valor={participantes} />
        <Linha rotulo="Parcela da SmallFlags (em dinheiro)" valor={c.parcelaSmallFlagsCentavos} />
        <Linha rotulo="Produtos para testes locais (QA)" valor={c.qaEmProdutosCentavos} />
        {c.valorDinheiroCentavos !== null && (
          <Linha rotulo="Valor total em dinheiro (sem QA)" valor={c.valorDinheiroCentavos} forte />
        )}
      </dl>
    </div>
  );
}

function Linha({ rotulo, valor, forte = false }: { rotulo: string; valor: number; forte?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="text-tinta/70">{rotulo}</dt>
      <dd className={`shrink-0 tabular-nums ${forte ? "font-bold" : "font-semibold"}`}>
        {formatarCentavos(valor)}
      </dd>
    </div>
  );
}

/* ------------------------------------------------------------------------- */

function Contratacao({
  ap,
  nicheCode,
  segmentId,
  segmentoPendente,
}: {
  ap: ApresentacaoOportunidade;
  nicheCode: string;
  segmentId: string | null;
  segmentoPendente: boolean;
}) {
  if (!ap.contratavel) {
    return (
      <section className="card mt-6 p-6" data-testid="contratacao-suspensa">
        <p className="font-semibold">Contratação temporariamente indisponível</p>
        <p className="mt-1 text-sm text-tinta/70">
          {ap.estado === "previa"
            ? "Os novos valores ainda não estão ativos no sistema. Para conversar sobre esta oportunidade, fale com a SmallFlags."
            : "A contratação pelo site ainda não foi liberada. A SmallFlags confirma as condições na proposta comercial; fale conosco para conversar sobre esta oportunidade."}
        </p>
        <Link to="/contato" className="btn-secondary mt-4 inline-block">
          Falar com a SmallFlags
        </Link>
      </section>
    );
  }

  if (segmentoPendente) {
    return (
      <section className="card mt-6 p-6">
        <p className="font-semibold">Escolha o segmento para continuar</p>
        <p className="mt-1 text-sm text-tinta/70">
          A posição Outros só pode ser contratada com um segmento definido.
        </p>
      </section>
    );
  }

  const destino =
    `/checkout?nicho=${encodeURIComponent(nicheCode)}` +
    (segmentId ? `&segmento=${encodeURIComponent(segmentId)}` : "");
  return (
    <section className="card mt-6 p-6">
      <Link to={destino} className="btn-primary inline-block w-full text-center">
        Solicitar contratação
      </Link>
      <p className="mt-2 text-center text-xs text-tinta/60">
        No checkout, o titular autenticado escolhe a forma de cumprimento,
        reserva a oportunidade por 30 minutos e avança após o aceite dos termos.
      </p>
    </section>
  );
}
