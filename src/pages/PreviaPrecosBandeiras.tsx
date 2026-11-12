import { Link } from "react-router-dom";
import SiteHeader from "../components/SiteHeader";
import SiteFooter from "../components/SiteFooter";
import { PREVIA_SF15, resumoPrevia } from "../content/previaPrecosBandeiras";

const moeda = (centavos: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(centavos / 100);

/**
 * Prévia informativa isolada: não lê preço de RPC, não cria pedidos ou cobranças.
 * NÃO usar como origem de preço comercial.
 * O preço vigente para contratar continua sendo o resolvido pelo backend.
 */
export default function PreviaPrecosBandeiras() {
  return (
    <div className="min-h-screen bg-white text-tinta">
      <SiteHeader />
      <main className="mx-auto max-w-6xl px-5 pb-24 pt-12 sm:px-8">
        <div className="mb-8 rounded-2xl border-2 border-amber-500 bg-amber-50 px-5 py-4 text-amber-950" role="status">
          <strong className="block text-lg">PRÉVIA DE PREÇOS — NÃO VIGENTE</strong>
          <p className="mt-1 text-sm leading-6">
            Esta página apresenta a proposta {PREVIA_SF15.versao} para revisão visual.
            Não é cotação, oferta, contrato ou autorização de cobrança. O checkout e o Supabase
            continuam utilizando exclusivamente a precificação vigente.
          </p>
        </div>

        <div className="max-w-3xl">
          <p className="text-sm font-semibold uppercase tracking-widest text-tinta/60">
            SmallFlags · Publicidade visual em veículos
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-5xl">
            Preços propostos das bandeiras publicitárias
          </h1>
          <p className="mt-5 text-lg leading-8 text-tinta/70">
            Cada novo anunciante exige a fabricação de 84 bandeiras, com custo nominal
            de {moeda(PREVIA_SF15.custoUnitarioBandeiraCentavos)} por peça. O custo de
            {moeda(PREVIA_SF15.custoUnitarioBandeiraCentavos * PREVIA_SF15.bandeirasPorAnuncianteNovo)}
            já está incluído uma única vez no preço proposto para não fidelizados.
            Parceiros fidelizados só reutilizam as peças após inspeção que confirme
            condições adequadas de conservação.
          </p>
        </div>

        <section className="mt-10 grid gap-4 md:grid-cols-3" aria-label="Resumo da proposta">
          <div className="rounded-2xl border border-tinta/15 p-6">
            <p className="text-sm text-tinta/60">Conjunto novo · 6 anunciantes</p>
            <p className="mt-2 text-3xl font-bold tabular-nums">{resumoPrevia.bandeirasNovas} bandeiras</p>
            <p className="mt-2 text-sm text-tinta/65">{moeda(resumoPrevia.custoProducaoCentavos)} em fabricação nominal</p>
          </div>
          <div className="rounded-2xl border border-tinta/15 p-6">
            <p className="text-sm text-tinta/60">Todos novos · valor econômico</p>
            <p className="mt-2 text-3xl font-bold tabular-nums">{moeda(resumoPrevia.novosCentavos)}</p>
            <p className="mt-2 text-sm text-tinta/65">Seis posições comerciais</p>
          </div>
          <div className="rounded-2xl border border-tinta/15 p-6">
            <p className="text-sm text-tinta/60">Todos fidelizados · reutilização</p>
            <p className="mt-2 text-3xl font-bold tabular-nums">{moeda(resumoPrevia.fidelizadosCentavos)}</p>
            <p className="mt-2 text-sm text-tinta/65">Sem fabricar novas peças, se aprovadas</p>
          </div>
        </section>

        <section className="mt-12" aria-labelledby="tabela-precos">
          <h2 id="tabela-precos" className="text-2xl font-bold">Comparação por posição comercial</h2>
          <p className="mt-2 text-sm leading-6 text-tinta/65">
            As 84 unidades comerciais de uma formação (24 + 5 × 12) não são a quantidade de bandeiras.
            Cada um dos seis anunciantes novos recebe 84 peças físicas.
          </p>
          <div className="mt-5 overflow-x-auto rounded-2xl border border-tinta/15">
            <table className="w-full min-w-[720px] border-collapse text-left">
              <thead className="bg-tinta/5 text-sm">
                <tr>
                  <th scope="col" className="p-4">Posição</th>
                  <th scope="col" className="p-4 text-right">Unidades comerciais</th>
                  <th scope="col" className="p-4 text-right">Novo anunciante</th>
                  <th scope="col" className="p-4 text-right">Fidelizado com reuso</th>
                </tr>
              </thead>
              <tbody>
                {PREVIA_SF15.nichos.map((n) => (
                  <tr key={n.nome} className="border-t border-tinta/10">
                    <th scope="row" className="p-4 font-semibold">{n.nome}</th>
                    <td className="p-4 text-right tabular-nums">{n.unidadesComerciais}</td>
                    <td className="p-4 text-right tabular-nums">{moeda(n.novoCentavos)}</td>
                    <td className="p-4 text-right tabular-nums">{moeda(n.fidelizadoCentavos)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="border-t-2 border-tinta/20 bg-tinta/5 font-bold">
                <tr>
                  <th scope="row" className="p-4">Formação completa</th>
                  <td className="p-4 text-right">84</td>
                  <td className="p-4 text-right tabular-nums">{moeda(resumoPrevia.novosCentavos)}</td>
                  <td className="p-4 text-right tabular-nums">{moeda(resumoPrevia.fidelizadosCentavos)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        </section>

        <section className="mt-10 rounded-2xl border border-tinta/15 bg-tinta/5 p-6">
          <h2 className="text-xl font-bold">Condições ainda não liberadas</h2>
          <p className="mt-3 leading-7 text-tinta/75">
            A contraprestação potencial permanece {moeda(PREVIA_SF15.participacaoAprovadaCentavos)}
            por participação aprovada. A parcela QA da formação permanece
            {moeda(PREVIA_SF15.qaFormacaoCentavos)}. A reposição de bandeiras danificadas,
            os critérios de inspeção, o licenciamento e a aprovação jurídica dos
            novos instrumentos ainda dependem de definições. Nenhuma cobrança de
            reposição está representada nesta prévia.
          </p>
          <p className="mt-3 text-sm text-tinta/60">
            Valores econômicos projetados, não necessariamente caixa recebido nem lucro líquido.
            O preço efetivo de contratação é sempre o retornado pelo servidor.
          </p>
        </section>

        <Link to="/" className="mt-8 inline-flex min-h-11 items-center font-semibold underline underline-offset-4">
          Voltar ao site
        </Link>
      </main>
      <SiteFooter />
    </div>
  );
}
