import {
  FORMACAO_REFERENCIA,
  TOTAL_UNIDADES_REFERENCIA,
} from "../../content/institucional";

/**
 * Formação comercial de referência como uma régua proporcional.
 *
 * A régua é decorativa (aria-hidden); a lista abaixo carrega a informação
 * para leitores de tela. Cada segmento é um nicho inteiro: a régua não tem
 * subdivisões por unidade de propósito, para não sugerir venda avulsa.
 */
export default function FormacaoReferencia({ tom = "claro" }: { tom?: "claro" | "escuro" }) {
  const escuro = tom === "escuro";
  return (
    <figure>
      <div className="flex items-baseline justify-between gap-4">
        <p className={`display text-5xl sm:text-6xl ${escuro ? "text-white" : "text-tinta"}`}>
          {TOTAL_UNIDADES_REFERENCIA}
        </p>
        <p className={`text-right text-sm ${escuro ? "text-white/70" : "text-tinta/60"}`}>
          unidades em seis nichos
        </p>
      </div>

      <div aria-hidden className="mt-5 flex h-4 w-full gap-1 overflow-hidden rounded-full">
        {FORMACAO_REFERENCIA.map((n, i) => (
          <span
            key={n.nome}
            style={{ flexGrow: n.unidades, flexBasis: 0 }}
            className={
              i === 0
                ? "bg-magenta"
                : escuro
                  ? i % 2
                    ? "bg-white/80"
                    : "bg-white/45"
                  : i % 2
                    ? "bg-tinta"
                    : "bg-tinta/45"
            }
          />
        ))}
      </div>

      <figcaption className="sr-only">
        Formação comercial de referência: {TOTAL_UNIDADES_REFERENCIA} unidades em seis nichos,
        cada nicho contratado integralmente.
      </figcaption>

      <ul className="mt-6 grid gap-x-8 gap-y-3 sm:grid-cols-2">
        {FORMACAO_REFERENCIA.map((n, i) => (
          <li
            key={n.nome}
            className={`flex items-baseline justify-between gap-3 border-b pb-2 text-sm ${
              escuro ? "border-white/15" : "border-tinta/10"
            }`}
          >
            <span className="flex items-center gap-2">
              <span
                aria-hidden
                className={`inline-block h-2.5 w-2.5 rounded-full ${
                  i === 0
                    ? "bg-magenta"
                    : escuro
                      ? i % 2
                        ? "bg-white/80"
                        : "bg-white/45"
                      : i % 2
                        ? "bg-tinta"
                        : "bg-tinta/45"
                }`}
              />
              <span className={escuro ? "text-white" : "text-tinta"}>{n.nome}</span>
            </span>
            <span className={`font-semibold tabular-nums ${escuro ? "text-white/80" : "text-tinta/70"}`}>
              {n.unidades} unidades
            </span>
          </li>
        ))}
      </ul>
    </figure>
  );
}
