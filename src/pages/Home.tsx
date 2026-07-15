import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import BrazilMap from "../components/BrazilMap";
import DemoBanner from "../components/DemoBanner";
import ScrollTilt from "../components/ScrollTilt";

/**
 * HOME — formato "agência moderna" (referência: spun.com.br),
 * adaptado à identidade serigrafia (magenta/ciano/amarelo sobre papel).
 *
 * Blocos, na ordem:
 *   1. Hero de declaração (tipografia gigante) + CTAs
 *   2. Letreiro em movimento (marquee)
 *   3. Mapa do Brasil — momento assinatura + faixa de presença
 *   4. Números grandes com contadores animados
 *   5. Divisão de públicos: Para empresas / Para anunciantes
 *   6. Pilares (4 frentes)
 *   7. Parede de credibilidade (logos placeholder)
 *   8. Quem está por trás (time placeholder)
 *   9. FAQ em acordeão
 *  10. CTA final dramático + rodapé completo
 *
 * Todo conteúdo de negócio está marcado com ⚠️ A DEFINIR para ser
 * substituído depois pelo estilo/dados reais.
 */

/* ---------- Revelar ao rolar (fade + sobe) ---------- */
function Revelar({
  children,
  atraso = 0,
  className = "",
}: {
  children: React.ReactNode;
  atraso?: number;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visivel, setVisivel] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setVisivel(true);
      return;
    }
    const obs = new IntersectionObserver(
      ([e]) => {
        // reanima sempre: aparece ao entrar na tela, esconde ao sair
        setVisivel(e.isIntersecting);
      },
      { threshold: 0.15 }
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      style={{ transitionDelay: `${atraso}ms` }}
      className={`transition-all duration-700 ease-out ${
        visivel ? "translate-y-0 opacity-100" : "translate-y-8 opacity-0"
      } ${className}`}
    >
      {children}
    </div>
  );
}

/* ---------- Contador animado ---------- */
function Contador({
  ate,
  prefixo = "",
  sufixo = "",
}: {
  ate: number;
  prefixo?: string;
  sufixo?: string;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const [valor, setValor] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setValor(ate);
      return;
    }
    let raf = 0;
    const obs = new IntersectionObserver(
      ([e]) => {
        cancelAnimationFrame(raf);
        if (!e.isIntersecting) {
          // saiu da tela: zera para recontar na próxima visita
          setValor(0);
          return;
        }
        const inicio = performance.now();
        const dur = 1600;
        const tick = (agora: number) => {
          const t = Math.min(1, (agora - inicio) / dur);
          const suave = 1 - Math.pow(1 - t, 3); // ease-out cúbico
          setValor(Math.round(ate * suave));
          if (t < 1) raf = requestAnimationFrame(tick);
        };
        raf = requestAnimationFrame(tick);
      },
      { threshold: 0.5 }
    );
    obs.observe(el);
    return () => {
      cancelAnimationFrame(raf);
      obs.disconnect();
    };
  }, [ate]);

  return (
    <span ref={ref}>
      {prefixo}
      {valor.toLocaleString("pt-BR")}
      {sufixo}
    </span>
  );
}

/* ---------- Letreiro (marquee) ---------- */
function Letreiro({
  itens,
  invertido = false,
  className = "",
}: {
  itens: string[];
  invertido?: boolean;
  className?: string;
}) {
  const sequencia = [...itens, ...itens, ...itens, ...itens];
  return (
    <div className={`overflow-hidden ${className}`}>
      <div
        className="letreiro-faixa"
        style={invertido ? { animationDirection: "reverse" } : undefined}
      >
        {sequencia.map((t, i) => (
          <span
            key={i}
            className="flex shrink-0 items-center gap-8 font-display text-lg font-bold uppercase tracking-wider"
          >
            {t} <span className="text-amarelo">✦</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/* ---------- Página ---------- */
export default function Home() {
  const mapaRef = useRef<HTMLDivElement>(null);
  const solucoesRef = useRef<HTMLDivElement>(null);
  const timeRef = useRef<HTMLDivElement>(null);
  const faqRef = useRef<HTMLDivElement>(null);
  const contatoRef = useRef<HTMLDivElement>(null);
  const presencaRef = useRef<HTMLDivElement>(null);
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
      {/* MANCHAS DE COR (fundo da marca) */}
      <div
        className="pointer-events-none absolute inset-0 overflow-hidden"
        aria-hidden
      >
        <div className="mancha" style={{ top: "-4%", left: "-12%", width: 520, height: 520, background: "#E5007E" }} />
        <div className="mancha" style={{ top: "12%", right: "-14%", width: 560, height: 560, background: "#00A8E0", animationDelay: "-7s" }} />
        <div className="mancha" style={{ top: "38%", left: "-10%", width: 460, height: 460, background: "#FFC400", animationDelay: "-12s" }} />
        <div className="mancha" style={{ top: "62%", right: "-10%", width: 500, height: 500, background: "#E5007E", animationDelay: "-4s", opacity: 0.3 }} />
        <div className="mancha" style={{ bottom: "-8%", left: "20%", width: 520, height: 520, background: "#00A8E0", animationDelay: "-9s", opacity: 0.3 }} />
      </div>

      <DemoBanner />

      {/* ===== CABEÇALHO ===== */}
      <header className="sticky top-0 z-40 border-b border-borda/60 bg-papel/80 backdrop-blur-md">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
          <Link to="/" className="display text-xl">
            camisas<span className="text-magenta">.</span>es
          </Link>
          <nav className="hidden items-center gap-6 text-sm font-medium sm:flex">
            <button onClick={() => irAte(mapaRef)} className="hover:text-magenta">O mapa</button>
            <button onClick={() => irAte(solucoesRef)} className="hover:text-magenta">Soluções</button>
            <button onClick={() => irAte(timeRef)} className="hover:text-magenta">Quem somos</button>
            <button onClick={() => irAte(faqRef)} className="hover:text-magenta">FAQ</button>
            <Link to="/parceiros" className="hover:text-magenta">Parceiros</Link>
            <Link
              to="/produtos"
              className="rounded-full bg-amarelo px-4 py-1.5 font-bold text-tinta transition hover:bg-magenta hover:text-white"
            >
              Loja 👕
            </Link>
          </nav>
          <button
            onClick={() => irAte(contatoRef)}
            className="rounded-full bg-tinta px-5 py-2 text-sm font-semibold text-white transition hover:bg-magenta"
          >
            Fale conosco
          </button>
        </div>
      </header>

      {/* ===== 1 · HERO DE DECLARAÇÃO ===== */}
      <section className="relative mx-auto max-w-6xl px-4 pb-20 pt-20 sm:pt-28">
        <p className="entrar inline-flex items-center gap-2 rounded-full border border-borda bg-white/70 px-4 py-1.5 text-xs font-bold uppercase tracking-[0.3em] text-magenta backdrop-blur">
          <span className="h-2 w-2 animate-pulse rounded-full bg-magenta" />
          Espírito Santo → Brasil
        </p>
        <h1 className="entrar entrar-2 mt-6 text-5xl leading-[0.98] sm:text-7xl md:text-8xl">
          IDENTIDADE
          <br />
          <span className="text-magenta">→</span> EM{" "}
          <span className="relative inline-block">
            MOVIMENTO
            <span className="absolute -bottom-1 left-0 -z-10 h-4 w-full -rotate-1 rounded bg-amarelo/70 sm:h-6" />
          </span>
        </h1>
        {/* ⚠️ SUBTÍTULO PROVISÓRIO — A DEFINIR */}
        <p className="entrar entrar-3 mt-7 max-w-xl text-lg text-tinta/70">
          Vestimos marcas e movemos mensagens: da estampa que a sua empresa
          usa ao anúncio que o Brasil inteiro vê.
        </p>
        <div className="entrar entrar-4 mt-9 flex flex-wrap gap-3">
          <Link to="/produtos" className="btn-primary group">
            Comprar camisas{" "}
            <span className="transition-transform group-hover:translate-x-1">→</span>
          </Link>
          <button
            onClick={() => irAte(solucoesRef)}
            className="btn-secondary group"
          >
            Para empresas{" "}
            <span className="transition-transform group-hover:translate-x-1">→</span>
          </button>
          <button
            onClick={() => irAte(solucoesRef)}
            className="btn-secondary group"
          >
            Para anunciantes{" "}
            <span className="transition-transform group-hover:translate-x-1">→</span>
          </button>
        </div>
      </section>

      {/* ===== 2 · LETREIRO EM MOVIMENTO ===== */}
      <div className="relative -rotate-1 border-y-2 border-tinta bg-magenta py-3 text-white">
        <Letreiro itens={["Somos feitos de identidade", "Somos feitos de cor", "Somos feitos de movimento"]} />
      </div>
      <div className="relative rotate-1 border-b-2 border-tinta bg-papel py-3 text-tinta">
        <Letreiro invertido itens={["Estampa", "Mídia", "Design", "Espírito Santo", "Brasil"]} />
      </div>

      {/* ===== 3 · MAPA — MOMENTO ASSINATURA ===== */}
      <section ref={mapaRef} className="relative mx-auto max-w-5xl scroll-mt-24 px-4 pb-10 pt-24 text-center">
        <Revelar>
          <h2 className="text-3xl sm:text-5xl">
            Um Brasil inteiro para a sua marca
            <span className="mx-auto mt-4 block h-2 w-32 rounded-full bg-ciano" />
          </h2>
          <p className="mx-auto mt-4 max-w-lg text-tinta/60">
            Passe o mouse e veja cada estado vestir a própria bandeira.
            Clique no seu.
          </p>
        </Revelar>
        <Revelar atraso={150}>
          <div className="mx-auto mt-12 max-w-3xl">
            <ScrollTilt>
              {/* moldura de "tela" onde o mapa pousa em 3D */}
              <div className="rounded-[2rem] border-2 border-tinta bg-white p-3 shadow-[0_30px_80px_rgba(23,18,31,0.25)] sm:p-5">
                <div className="mb-3 flex items-center gap-1.5 px-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-magenta" />
                  <span className="h-2.5 w-2.5 rounded-full bg-amarelo" />
                  <span className="h-2.5 w-2.5 rounded-full bg-ciano" />
                  <span className="ml-3 text-[10px] font-semibold uppercase tracking-widest text-tinta/30">
                    brasil.mapa
                  </span>
                </div>
                <BrazilMap onSelectState={aoEscolherEstado} />
              </div>
            </ScrollTilt>
          </div>
        </Revelar>
      </section>

      {/* faixa de presença */}
      <div ref={presencaRef} className="relative mx-auto max-w-3xl px-4 pb-24">
        {selecao ? (
          <div className="rounded-3xl border border-borda bg-white/85 p-8 text-center shadow-lg backdrop-blur">
            {selecao.es ? (
              <>
                <h3 className="text-2xl sm:text-3xl">
                  Já estamos no <span className="text-magenta">Espírito Santo</span>! 🎉
                </h3>
                <p className="mt-3 text-tinta/70">
                  É daqui que tudo parte. Escolha um modelo e comece agora.
                </p>
                <Link to="/produtos" className="btn-primary mt-5">
                  Ver modelos e comprar →
                </Link>
              </>
            ) : (
              <>
                <h3 className="text-2xl sm:text-3xl">
                  Em breve em {selecao.nome}!
                  <span className="mx-auto mt-3 block h-1.5 w-28 rounded-full bg-amarelo" />
                </h3>
                <p className="mt-3 text-tinta/70">
                  Estamos chegando. Deixe seu contato e avisamos quando o seu
                  estado acender no mapa.
                </p>
                <button onClick={() => irAte(contatoRef)} className="btn-secondary mt-5">
                  Quero ser avisado
                </button>
              </>
            )}
          </div>
        ) : (
          <p className="text-center text-sm text-tinta/40">
            👆 Clique num estado para ver nossa presença por lá.
          </p>
        )}
      </div>

      {/* ===== 4 · NÚMEROS GRANDES ===== */}
      <section className="relative border-y-2 border-tinta bg-tinta py-20 text-papel">
        <div className="mx-auto grid max-w-6xl gap-12 px-4 text-center sm:grid-cols-2 lg:grid-cols-4">
          {/* ⚠️ NÚMEROS PROVISÓRIOS — A DEFINIR com dados reais */}
          {[
            { ate: 1200, sufixo: "+", rotulo: "camisas estampadas", cor: "text-magenta" },
            { ate: 80, sufixo: "+", rotulo: "empresas atendidas", cor: "text-ciano" },
            { ate: 27, sufixo: "", rotulo: "estados no radar", cor: "text-amarelo" },
            { ate: 100, sufixo: "%", rotulo: "feito no Espírito Santo", cor: "text-papel" },
          ].map((n, i) => (
            <Revelar key={n.rotulo} atraso={i * 120}>
              <p className={`font-display text-5xl font-bold sm:text-6xl ${n.cor}`}>
                <Contador ate={n.ate} sufixo={n.sufixo} />
              </p>
              <p className="mt-2 text-sm uppercase tracking-widest text-papel/60">
                {n.rotulo}
              </p>
            </Revelar>
          ))}
        </div>
        <p className="mt-10 text-center text-xs text-papel/30">
          ⚠️ números ilustrativos — a definir com dados reais
        </p>
      </section>

      {/* ===== 5 · DIVISÃO DE PÚBLICOS ===== */}
      <section ref={solucoesRef} className="relative mx-auto max-w-6xl scroll-mt-24 px-4 py-24">
        <Revelar>
          <h2 className="text-center text-3xl sm:text-5xl">Dois caminhos, um só movimento</h2>
        </Revelar>
        <div className="mt-12 grid gap-6 md:grid-cols-2">
          <Revelar>
            <article className="group flex h-full flex-col rounded-3xl bg-magenta p-9 text-white shadow-lg transition hover:-translate-y-1 hover:shadow-[0_24px_70px_rgba(229,0,126,0.45)]">
              <p className="text-xs font-bold uppercase tracking-[0.25em] opacity-80">Para empresas</p>
              <h3 className="mt-3 text-3xl sm:text-4xl">Sua marca, vestida.</h3>
              {/* ⚠️ TEXTO PROVISÓRIO — A DEFINIR */}
              <p className="mt-4 text-white/85">
                Camisas e materiais com a identidade da sua empresa, produzidos
                no ES com arte revisada uma a uma.
              </p>
              <ul className="mt-6 space-y-2 text-sm text-white/90">
                <li>✦ Estampa personalizada com sua arte</li>
                <li>✦ Produção própria e controle de qualidade</li>
                <li>✦ Do pedido à entrega, sem intermediários</li>
              </ul>
              <Link
                to="/produtos"
                className="mt-auto w-fit rounded-xl bg-white px-6 py-3 pt-3 font-semibold text-magenta transition group-hover:scale-105"
                style={{ marginTop: "2rem" }}
              >
                Quero vestir minha marca →
              </Link>
            </article>
          </Revelar>
          <Revelar atraso={150}>
            <article className="group flex h-full flex-col rounded-3xl border-2 border-tinta bg-tinta p-9 text-papel shadow-lg transition hover:-translate-y-1 hover:shadow-[0_24px_70px_rgba(0,168,224,0.4)]">
              <p className="text-xs font-bold uppercase tracking-[0.25em] text-ciano">Para anunciantes</p>
              <h3 className="mt-3 text-3xl sm:text-4xl">Sua mensagem, em movimento.</h3>
              {/* ⚠️ TEXTO PROVISÓRIO — A DEFINIR (modelo de anúncios) */}
              <p className="mt-4 text-papel/80">
                Anuncie nos nossos espaços e leve sua mensagem junto com quem
                veste e circula por todo o estado — e logo, pelo Brasil.
              </p>
              <ul className="mt-6 space-y-2 text-sm text-papel/85">
                <li>✦ Espaços de mídia da marca (⚠️ a definir)</li>
                <li>✦ Público segmentado por estado</li>
                <li>✦ Formatos sob medida para sua campanha</li>
              </ul>
              <button
                onClick={() => irAte(contatoRef)}
                className="mt-auto w-fit rounded-xl bg-ciano px-6 py-3 font-semibold text-tinta transition group-hover:scale-105"
                style={{ marginTop: "2rem" }}
              >
                Quero anunciar →
              </button>
            </article>
          </Revelar>
        </div>
      </section>

      {/* ===== 6 · PILARES ===== */}
      <section className="relative mx-auto max-w-6xl px-4 pb-24">
        <Revelar>
          <h2 className="text-center text-3xl sm:text-5xl">Nossas frentes</h2>
          <p className="mx-auto mt-3 max-w-md text-center text-tinta/60">
            {/* ⚠️ A DEFINIR — frentes reais do negócio */}
            Quatro pilares, uma identidade.
          </p>
        </Revelar>
        <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {[
            { icone: "👕", titulo: "Estamparia", texto: "Produção própria de camisas personalizadas. (⚠️ A DEFINIR)", cor: "group-hover:bg-magenta" },
            { icone: "📣", titulo: "Mídia & anúncios", texto: "Espaços publicitários da marca para anunciantes. (⚠️ A DEFINIR)", cor: "group-hover:bg-ciano" },
            { icone: "🎨", titulo: "Design", texto: "Criação e revisão de artes que representam sua marca. (⚠️ A DEFINIR)", cor: "group-hover:bg-amarelo" },
            { icone: "🚚", titulo: "ES → Brasil", texto: "Logística que começa capixaba e mira o país inteiro. (⚠️ A DEFINIR)", cor: "group-hover:bg-magenta" },
          ].map((p, i) => (
            <Revelar key={p.titulo} atraso={i * 100}>
              <article className="group h-full rounded-3xl border border-borda bg-white/85 p-7 shadow-sm backdrop-blur transition hover:-translate-y-1 hover:shadow-xl">
                <span className={`flex h-12 w-12 items-center justify-center rounded-2xl bg-papel2 text-2xl transition-colors ${p.cor}`}>
                  {p.icone}
                </span>
                <h3 className="mt-5 text-xl">{p.titulo}</h3>
                <p className="mt-2 text-sm leading-relaxed text-tinta/60">{p.texto}</p>
              </article>
            </Revelar>
          ))}
        </div>
      </section>

      {/* ===== 7 · PAREDE DE CREDIBILIDADE ===== */}
      <section className="relative border-y border-borda bg-white/60 py-16 backdrop-blur">
        <Revelar>
          <h2 className="text-center text-2xl text-tinta/70 sm:text-3xl">
            Quando o mercado fala em identidade,
            <br className="hidden sm:block" /> queremos que fale na gente.
          </h2>
        </Revelar>
        {/* ⚠️ LOGOS PROVISÓRIOS — trocar por logos reais de clientes/parceiros/imprensa */}
        <div className="mx-auto mt-10 grid max-w-5xl grid-cols-2 gap-4 px-4 sm:grid-cols-4">
          {["Parceiro 1", "Parceiro 2", "Parceiro 3", "Parceiro 4", "Cliente 1", "Cliente 2", "Cliente 3", "Cliente 4"].map((l, i) => (
            <Revelar key={l} atraso={i * 60}>
              <div className="flex h-16 items-center justify-center rounded-2xl border border-dashed border-borda bg-papel text-sm font-semibold text-tinta/30">
                {l}
              </div>
            </Revelar>
          ))}
        </div>
        <p className="mt-6 text-center text-xs text-tinta/30">⚠️ espaços para logos reais — a definir</p>
      </section>

      {/* ===== 8 · QUEM ESTÁ POR TRÁS ===== */}
      <section ref={timeRef} className="relative mx-auto max-w-6xl scroll-mt-24 px-4 py-24">
        <Revelar>
          <h2 className="text-center text-3xl sm:text-5xl">Quem está por trás</h2>
          <p className="mx-auto mt-3 max-w-md text-center text-tinta/60">
            Gente real, do Espírito Santo, tocando cada etapa.
          </p>
        </Revelar>
        {/* ⚠️ TIME PROVISÓRIO — trocar por fotos, nomes e cargos reais */}
        <div className="mt-12 grid gap-6 sm:grid-cols-3">
          {[
            { iniciais: "JH", nome: "Nome Sobrenome", cargo: "Fundador(a) · (⚠️ A DEFINIR)", cor: "bg-magenta" },
            { iniciais: "??", nome: "Nome Sobrenome", cargo: "Cargo · (⚠️ A DEFINIR)", cor: "bg-ciano" },
            { iniciais: "??", nome: "Nome Sobrenome", cargo: "Cargo · (⚠️ A DEFINIR)", cor: "bg-amarelo" },
          ].map((m, i) => (
            <Revelar key={i} atraso={i * 120}>
              <article className="rounded-3xl border border-borda bg-white/85 p-8 text-center shadow-sm backdrop-blur transition hover:-translate-y-1 hover:shadow-xl">
                <span className={`mx-auto flex h-24 w-24 items-center justify-center rounded-full ${m.cor} font-display text-3xl font-bold text-white`}>
                  {m.iniciais}
                </span>
                <h3 className="mt-5 text-xl">{m.nome}</h3>
                <p className="mt-1 text-sm text-tinta/50">{m.cargo}</p>
              </article>
            </Revelar>
          ))}
        </div>
      </section>

      {/* ===== 9 · FAQ ===== */}
      <section ref={faqRef} className="relative mx-auto max-w-3xl scroll-mt-24 px-4 pb-24">
        <Revelar>
          <h2 className="text-center text-3xl sm:text-5xl">Perguntas frequentes</h2>
        </Revelar>
        <div className="mt-10 space-y-3">
          {/* ⚠️ PERGUNTAS/RESPOSTAS PROVISÓRIAS — A DEFINIR */}
          {[
            { p: "O que exatamente vocês fazem?", r: "Estampamos camisas personalizadas para empresas e oferecemos espaços de mídia para anunciantes. (⚠️ resposta a definir)" },
            { p: "Vocês atendem fora do Espírito Santo?", r: "Estamos começando pelo ES, com expansão planejada para todo o Brasil — clique no seu estado no mapa e deixe seu contato. (⚠️ a definir)" },
            { p: "Como funciona para anunciar com vocês?", r: "Fale com a gente pelo contato no rodapé e apresentamos os formatos e espaços disponíveis. (⚠️ modelo de anúncios a definir)" },
            { p: "Qual o prazo de produção e entrega?", r: "Depende do volume e do destino — respondemos com o prazo exato no orçamento. (⚠️ prazos a definir)" },
            { p: "Posso enviar minha própria arte?", r: "Sim! Toda arte enviada passa por revisão da nossa equipe antes da produção. (⚠️ política de revisões a definir)" },
          ].map((f, i) => (
            <Revelar key={i} atraso={i * 60}>
              <details className="group rounded-2xl border border-borda bg-white/85 backdrop-blur open:shadow-md">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 px-6 py-4 font-semibold [&::-webkit-details-marker]:hidden">
                  {f.p}
                  <span className="text-xl text-magenta transition-transform group-open:rotate-45">+</span>
                </summary>
                <p className="px-6 pb-5 text-sm leading-relaxed text-tinta/70">{f.r}</p>
              </details>
            </Revelar>
          ))}
        </div>
      </section>

      {/* ===== 10 · CTA FINAL ===== */}
      <section ref={contatoRef} className="relative scroll-mt-24 overflow-hidden border-t-2 border-tinta bg-tinta py-24 text-center text-papel">
        {/* palavra gigante de contorno ao fundo */}
        <span
          aria-hidden
          className="texto-contorno pointer-events-none absolute left-1/2 top-6 -translate-x-1/2 whitespace-nowrap font-display text-[22vw] font-bold leading-none"
        >
          MOVIMENTO
        </span>
        <Revelar>
          <h2 className="mx-auto max-w-3xl px-4 text-4xl leading-[1.02] sm:text-6xl">
            VAMOS COLOCAR A SUA MARCA{" "}
            <span className="text-magenta">EM</span>{" "}
            <span className="text-ciano">MOVI</span>
            <span className="text-amarelo">MENTO</span>?
          </h2>
          {/* ⚠️ CONTATO PROVISÓRIO — A DEFINIR (email/WhatsApp reais) */}
          <a
            href="mailto:contato@exemplo.com.br"
            className="mt-10 inline-block rounded-2xl bg-magenta px-10 py-5 font-display text-lg font-bold text-white transition hover:scale-105 hover:bg-white hover:text-magenta"
          >
            Fale com a gente →
          </a>
          <p className="mt-4 text-sm text-papel/50">contato@exemplo.com.br (⚠️ a definir)</p>
        </Revelar>

        {/* rodapé */}
        <footer className="mt-20 border-t border-papel/15 pt-10">
          <div className="mx-auto grid max-w-6xl gap-8 px-4 text-left sm:grid-cols-3">
            <div>
              <p className="display text-lg">camisas<span className="text-magenta">.</span>es</p>
              <p className="mt-2 text-sm text-papel/50">
                Identidade em movimento, do Espírito Santo para o Brasil.
              </p>
            </div>
            <div className="text-sm text-papel/60">
              <p className="font-semibold text-papel">Contato</p>
              <p className="mt-2">contato@exemplo.com.br (⚠️)</p>
              <p>WhatsApp: (27) 90000-0000 (⚠️)</p>
              <p>Espírito Santo, Brasil</p>
            </div>
            <div className="text-sm text-papel/60">
              <p className="font-semibold text-papel">Institucional</p>
              <p className="mt-2">
                <Link to="/parceiros" className="hover:text-papel">Área de parceiros</Link>
              </p>
              <p>Termos de uso (em breve)</p>
              <p>Privacidade (em breve)</p>
              <Link to="/admin" className="hover:text-papel">Admin</Link>
            </div>
          </div>
          <p className="mt-10 pb-2 text-center text-xs text-papel/30">
            © 2026 camisas.es · CNPJ 00.000.000/0000-00 (⚠️ a definir)
          </p>
        </footer>
      </section>
    </main>
  );
}
