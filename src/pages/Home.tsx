import { useRef, useState } from "react";
import { Link } from "react-router-dom";
import BrazilMap from "../components/BrazilMap";
import DemoBanner from "../components/DemoBanner";

/**
 * HOME — novo visual "identidade em primeiro lugar":
 *
 * Fundo papel claro com MANCHAS suaves e desfocadas nas cores de
 * serigrafia (magenta/ciano/amarelo) flutuando devagar — moderno,
 * leve e 100% da marca (sem foto de terceiros).
 *
 * Fluxo normal, de cima para baixo:
 *   1. HERO       · título + mapa do Brasil (bandeira suavizada;
 *                   estaduais no hover). Clicar num estado rola até
 *                   a faixa de presença logo abaixo.
 *   2. LACUNAS    · três blocos elegantes com espaços marcados
 *                   (⚠️ A DEFINIR) para preencher com o estilo do
 *                   negócio depois.
 *   3. QUEM SOMOS · na base, com contato e rodapé.
 *
 * Sem venda de produtos na home por enquanto (rotas /produtos etc.
 * continuam existindo, apenas não são o foco).
 */

export default function Home() {
  const presencaRef = useRef<HTMLDivElement>(null);
  const sobreRef = useRef<HTMLDivElement>(null);
  const trabalhoRef = useRef<HTMLDivElement>(null);
  const [selecao, setSelecao] = useState<{ nome: string; es: boolean } | null>(
    null
  );

  const reduzMovimento =
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const irAte = (ref: React.RefObject<HTMLDivElement>) =>
    ref.current?.scrollIntoView({
      behavior: reduzMovimento ? "auto" : "smooth",
      block: "start",
    });

  const aoEscolherEstado = (nome: string, es: boolean) => {
    setSelecao({ nome, es });
    presencaRef.current?.scrollIntoView({
      behavior: reduzMovimento ? "auto" : "smooth",
      block: "center",
    });
  };

  return (
    <main className="relative overflow-x-clip">
      {/* ===== MANCHAS DE COR (fundo da marca) ===== */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
        <div
          className="mancha"
          style={{ top: "-6%", left: "-12%", width: 520, height: 520, background: "#E5007E", animationDelay: "0s" }}
        />
        <div
          className="mancha"
          style={{ top: "8%", right: "-14%", width: 560, height: 560, background: "#00A8E0", animationDelay: "-6s" }}
        />
        <div
          className="mancha"
          style={{ top: "46%", left: "-10%", width: 440, height: 440, background: "#FFC400", animationDelay: "-12s" }}
        />
        <div
          className="mancha"
          style={{ top: "68%", right: "-8%", width: 480, height: 480, background: "#E5007E", animationDelay: "-9s", opacity: 0.35 }}
        />
        <div
          className="mancha"
          style={{ bottom: "-10%", left: "22%", width: 520, height: 520, background: "#00A8E0", animationDelay: "-3s", opacity: 0.35 }}
        />
      </div>

      <DemoBanner />

      {/* ===== CABEÇALHO ===== */}
      <header className="sticky top-0 z-40 border-b border-borda/60 bg-papel/80 backdrop-blur-md">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
          <Link to="/" className="display text-xl">
            camisas<span className="text-magenta">.</span>es
          </Link>
          <nav className="flex items-center gap-6 text-sm font-medium">
            <button onClick={() => irAte(trabalhoRef)} className="hover:text-magenta">
              O que fazemos
            </button>
            <button onClick={() => irAte(sobreRef)} className="hover:text-magenta">
              Quem somos
            </button>
          </nav>
        </div>
      </header>

      {/* ===== 1 · HERO com o MAPA ===== */}
      <section className="relative mx-auto max-w-5xl px-4 pb-16 pt-16 text-center sm:pt-24">
        <p className="text-xs font-bold uppercase tracking-[0.25em] text-magenta">
          Feito no Espírito Santo
        </p>
        <h1 className="mt-4 text-4xl leading-[1.02] sm:text-6xl md:text-7xl">
          UMA MARCA QUE
          <br />
          VESTE O <span className="text-magenta">SEU</span>{" "}
          <span className="text-ciano">BRASIL</span>
          <span className="text-amarelo">.</span>
        </h1>
        {/* ⚠️ SUBTÍTULO PROVISÓRIO — A DEFINIR conforme o estilo do negócio */}
        <p className="mx-auto mt-6 max-w-xl text-lg text-tinta/70">
          Estampamos identidade. Passe o mouse pelo mapa e descubra as cores
          de cada estado — clique no seu.
        </p>

        <div className="mx-auto mt-10 max-w-2xl">
          <BrazilMap onSelectState={aoEscolherEstado} />
        </div>
      </section>

      {/* ===== FAIXA DE PRESENÇA (resposta ao clique no mapa) ===== */}
      <div ref={presencaRef} className="relative mx-auto max-w-3xl px-4 pb-20">
        {selecao ? (
          <div className="rounded-3xl border border-borda bg-white/80 p-8 text-center shadow-lg backdrop-blur">
            {selecao.es ? (
              <>
                <h2 className="text-2xl sm:text-3xl">
                  Já estamos no{" "}
                  <span className="text-magenta">Espírito Santo</span>! 🎉
                </h2>
                <p className="mt-3 text-tinta/70">
                  É daqui que tudo começa. Em breve, esta área mostrará o que
                  preparamos para você.
                  <span className="ml-1 text-tinta/40">(⚠️ A DEFINIR)</span>
                </p>
              </>
            ) : (
              <>
                <h2 className="text-2xl sm:text-3xl">
                  Em breve em {selecao.nome}!
                  <span className="mx-auto mt-3 block h-1.5 w-28 rounded-full bg-amarelo" />
                </h2>
                <p className="mt-3 text-tinta/70">
                  Estamos começando pelo Espírito Santo — seu estado está no
                  nosso mapa.
                </p>
              </>
            )}
          </div>
        ) : (
          <p className="text-center text-sm text-tinta/40">
            👆 Clique num estado para ver nossa presença por lá.
          </p>
        )}
      </div>

      {/* ===== 2 · LACUNAS ELEGANTES (preencher com o negócio) ===== */}
      <section ref={trabalhoRef} className="relative mx-auto max-w-6xl scroll-mt-24 px-4 pb-24">
        <h2 className="text-center text-3xl sm:text-5xl">O que fazemos</h2>
        <p className="mx-auto mt-3 max-w-md text-center text-tinta/60">
          {/* ⚠️ A DEFINIR — descrição curta do negócio */}
          Três espaços prontos para contar a sua história.
        </p>

        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {[
            {
              cor: "bg-magenta",
              titulo: "Nosso trabalho",
              texto:
                "Espaço para apresentar o que você cria — fotos, processo, resultado. (⚠️ A DEFINIR)",
            },
            {
              cor: "bg-ciano",
              titulo: "Como funciona",
              texto:
                "Espaço para explicar o passo a passo do seu serviço, do pedido à entrega. (⚠️ A DEFINIR)",
            },
            {
              cor: "bg-amarelo",
              titulo: "Diferenciais",
              texto:
                "Espaço para os motivos de confiar em você: qualidade, prazo, atendimento. (⚠️ A DEFINIR)",
            },
          ].map((b) => (
            <article
              key={b.titulo}
              className="group rounded-3xl border border-borda bg-white/80 p-8 shadow-sm backdrop-blur transition hover:-translate-y-1 hover:shadow-xl"
            >
              <span
                className={`inline-block h-3 w-12 rounded-full ${b.cor} transition-all group-hover:w-20`}
              />
              <h3 className="mt-5 text-2xl">{b.titulo}</h3>
              <p className="mt-3 text-sm leading-relaxed text-tinta/60">
                {b.texto}
              </p>
            </article>
          ))}
        </div>
      </section>

      {/* ===== 3 · QUEM SOMOS (base) ===== */}
      <section ref={sobreRef} className="relative scroll-mt-24 border-t border-borda/60 bg-white/60 backdrop-blur">
        <div className="mx-auto grid max-w-6xl gap-10 px-4 py-20 md:grid-cols-[1.2fr_1fr]">
          <div>
            <h2 className="text-3xl sm:text-5xl">
              Quem somos
              <span className="mt-4 block h-2 w-28 rounded-full bg-ciano" />
            </h2>
            {/* ⚠️ TEXTO PROVISÓRIO — A DEFINIR pelo dono do site */}
            <p className="mt-6 max-w-xl text-tinta/75">
              Somos uma marca capixaba apaixonada por transformar identidade em
              algo que se pode vestir e tocar. Este espaço receberá a história
              real do negócio — de onde viemos, o que acreditamos e para onde
              vamos.
            </p>
            <p className="mt-3 max-w-xl text-tinta/75">
              Começamos pelo Espírito Santo, com o mapa inteiro do Brasil pela
              frente.
            </p>
          </div>

          <div className="space-y-4">
            {/* ⚠️ CONTATOS PROVISÓRIOS — A DEFINIR */}
            <div className="rounded-2xl border border-borda bg-papel p-5">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Contato
              </p>
              <p className="mt-1 font-semibold">contato@exemplo.com.br</p>
            </div>
            <div className="rounded-2xl border border-borda bg-papel p-5">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Onde estamos
              </p>
              <p className="mt-1 font-semibold">Espírito Santo, Brasil</p>
            </div>
            <div className="rounded-2xl border border-borda bg-papel p-5">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Redes
              </p>
              <p className="mt-1 font-semibold text-tinta/50">
                @instagram · @whatsapp (⚠️ A DEFINIR)
              </p>
            </div>
          </div>
        </div>

        {/* rodapé */}
        <div className="border-t border-borda/60">
          <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-6 text-xs text-tinta/40">
            <span>
              camisas.es — CNPJ 00.000.000/0000-00 (⚠️ A DEFINIR) · Espírito
              Santo, Brasil
            </span>
            <span className="flex items-center gap-4">
              <span>Termos (em breve) · Privacidade (em breve)</span>
              <Link to="/admin" className="hover:text-tinta">
                Admin
              </Link>
            </span>
          </div>
        </div>
      </section>
    </main>
  );
}
