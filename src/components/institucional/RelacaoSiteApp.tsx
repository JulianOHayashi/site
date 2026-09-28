/**
 * Relação Site ↔ App, em HTML/CSS.
 *
 * Duas trilhas paralelas com domínios distintos, e um ponto de encontro único:
 * a validação do uso de benefício. A leitura não depende de cor, hover ou
 * animação — cada trilha tem rótulo textual, e a ordem no DOM é a ordem lógica
 * de leitura em qualquer largura.
 *
 * Não é um diagrama genérico: a geometria existe para deixar claro que o Site
 * NÃO administra a jornada operacional do participante.
 */

type Trilha = {
  atorRotulo: string;
  ator: string;
  sistema: string;
  dominioRotulo: string;
  dominio: string;
  itens: string[];
};

const TRILHAS: Trilha[] = [
  {
    atorRotulo: "Trilha comercial",
    ator: "Empresa parceira",
    sistema: "BDFlow Site",
    dominioRotulo: "Domínio comercial",
    dominio: "Relação comercial",
    itens: [
      "Oportunidades por região e nicho",
      "Exclusividade comercial",
      "Solicitação e análise de parceria",
      "Contratos, pagamentos e Portal do Parceiro",
    ],
  },
  {
    atorRotulo: "Trilha operacional",
    ator: "Participante",
    sistema: "BDFlow App",
    dominioRotulo: "Domínio operacional",
    dominio: "Jornada e benefícios",
    itens: [
      "Jornada operacional do participante",
      "Acesso aos benefícios das empresas parceiras",
      "Confirmação do uso pelo próprio participante",
    ],
  },
];

function Trilha({ t, escuro }: { t: Trilha; escuro: boolean }) {
  const borda = escuro ? "border-white/20" : "border-tinta/15";
  const texto = escuro ? "text-white" : "text-tinta";
  const suave = escuro ? "text-white/70" : "text-tinta/70";
  const sup = escuro ? "bg-white/5" : "bg-white";

  return (
    <section aria-label={t.atorRotulo} className={`rounded-3xl border ${borda} ${sup} px-6 py-6 sm:px-8 sm:py-7`}>
      <p className={`rotulo ${escuro ? "text-white/60" : "text-tinta/60"}`}>{t.atorRotulo}</p>

      {/* Ator → Sistema → Domínio. A fileira quebra em vez de estourar: em
          larguras apertadas os passos caem para linhas próprias mantendo a
          ordem, e a seta acompanha o passo que ela introduz. */}
      <ol className="mt-5 flex flex-wrap items-center gap-x-3 gap-y-2">
        {[t.ator, t.sistema, t.dominio].map((passo, i) => (
          <li key={passo} className="flex min-w-0 items-center gap-3">
            {i > 0 && (
              <span aria-hidden className={`shrink-0 ${suave}`}>
                →
              </span>
            )}
            <span
              className={`inline-flex min-h-[44px] min-w-0 items-center rounded-xl px-4 py-2 text-sm font-semibold ${
                i === 1
                  ? escuro
                    ? "bg-white text-tinta"
                    : "bg-tinta text-white"
                  : `border ${borda} ${texto}`
              }`}
            >
              {passo}
            </span>
          </li>
        ))}
      </ol>

      <p className={`mt-6 ${suave} text-xs font-semibold uppercase tracking-wider`}>
        {t.dominioRotulo}
      </p>
      <ul className={`mt-2 space-y-1.5 text-sm leading-6 ${suave}`}>
        {t.itens.map((i) => (
          <li key={i} className="flex gap-2.5">
            <span aria-hidden className={escuro ? "text-white/40" : "text-tinta/35"}>
              ·
            </span>
            {i}
          </li>
        ))}
      </ul>
    </section>
  );
}

export default function RelacaoSiteApp({ tom = "claro" }: { tom?: "claro" | "escuro" }) {
  const escuro = tom === "escuro";
  return (
    <div>
      {/* Empilhadas: estas trilhas costumam viver numa coluna de conteúdo
          (8 de 12), estreita demais para duas colunas sem quebrar a fileira
          de passos. A leitura vertical também deixa a separação mais clara. */}
      <div className="grid gap-4">
        {TRILHAS.map((t) => (
          <Trilha key={t.ator} t={t} escuro={escuro} />
        ))}
      </div>

      <div
        className={`mt-4 rounded-3xl border px-6 py-6 sm:px-8 sm:py-7 ${
          escuro ? "border-amarelo/40 bg-amarelo/10" : "border-tinta/15 bg-papel2"
        }`}
      >
        <p className={`rotulo ${escuro ? "text-amarelo" : "text-tinta/60"}`}>
          Onde as duas se encontram
        </p>
        <p
          className={`mt-3 max-w-3xl text-sm leading-7 sm:text-base ${
            escuro ? "text-white/85" : "text-tinta/75"
          }`}
        >
          Na validação do uso de um benefício: o participante apresenta o QR code do App,
          a empresa parceira registra a solicitação pelo Portal do Parceiro e o participante
          confirma o uso no próprio App. Fora desse encontro, cada ambiente decide o que é seu.
        </p>
      </div>
    </div>
  );
}
