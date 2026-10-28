import {
  FORMACAO_REFERENCIA,
  TOTAL_UNIDADES_REFERENCIA,
} from "../../content/institucional";

/**
 * Formação comercial de referência: seis nichos → 84 unidades.
 *
 * A régua mostra a proporção entre os nichos; cada segmento é um nicho
 * INTEIRO, sem subdivisão por unidade, porque o nicho é contratado por
 * completo. A régua é decorativa (aria-hidden) e a lista abaixo carrega a
 * informação — nada depende de cor.
 */
export default function FormacaoReferencia({
  tom = "claro",
}: {
  tom?: "claro" | "escuro";
}) {
  const escuro = tom === "escuro";
  // A régua percorre a sequência de cores do ícone, nicho a nicho: lida em
  // conjunto, é o gradiente da marca em degraus. Decorativa — a lista abaixo
  // carrega a informação.
  const SEQUENCIA_MARCA = [
    "bg-vivo-ciano",
    "bg-vivo-azul",
    "bg-vivo-verde",
    "bg-vivo-amarelo",
    "bg-vivo-laranja",
    "bg-vivo-magenta",
  ];
  const corSeg = (i: number) => SEQUENCIA_MARCA[i % SEQUENCIA_MARCA.length];

  return (
    <figure>
      <div className="flex flex-wrap items-end justify-between gap-x-8 gap-y-3">
        <p className="display t-numero texto-marca pb-1">
          {TOTAL_UNIDADES_REFERENCIA}
        </p>
        <p
          className={`max-w-[15rem] text-sm leading-6 ${
            escuro ? "text-white/70" : "text-tinta/70"
          }`}
        >
          unidades distribuídas em{" "}
          <span className={escuro ? "font-semibold text-white" : "font-semibold text-tinta"}>
            seis nichos
          </span>
          , cada um contratado integralmente.
        </p>
      </div>

      <div aria-hidden className="mt-7 flex h-2.5 w-full gap-1 overflow-hidden rounded-full">
        {FORMACAO_REFERENCIA.map((n, i) => (
          <span
            key={n.nome}
            style={{ flexGrow: n.unidades, flexBasis: 0 }}
            className={corSeg(i)}
          />
        ))}
      </div>

      <figcaption className="sr-only">
        Formação comercial de referência: {TOTAL_UNIDADES_REFERENCIA} unidades em seis
        nichos, cada nicho contratado integralmente.
      </figcaption>

      <ul className="mt-7 grid gap-x-10 gap-y-0 sm:grid-cols-2">
        {FORMACAO_REFERENCIA.map((n, i) => (
          <li
            key={n.nome}
            className={`flex items-baseline justify-between gap-4 border-b py-3 text-sm ${
              escuro ? "border-white/15" : "border-tinta/10"
            }`}
          >
            <span className="flex items-baseline gap-2.5">
              <span
                aria-hidden
                className={`inline-block h-2 w-2 shrink-0 translate-y-[-1px] rounded-full ${corSeg(i)}`}
              />
              <span className={escuro ? "text-white" : "text-tinta"}>{n.nome}</span>
            </span>
            <span
              className={`shrink-0 font-semibold tabular-nums ${
                escuro ? "text-white/75" : "text-tinta/70"
              }`}
            >
              {n.unidades}
            </span>
          </li>
        ))}
      </ul>
    </figure>
  );
}
