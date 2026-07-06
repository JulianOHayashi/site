import { Link } from "react-router-dom";
import BrazilMap from "../components/BrazilMap";
import DemoBanner from "../components/DemoBanner";

export default function Home() {
  return (
    <main>
      <DemoBanner />

      {/* HERO */}
      <section className="mx-auto max-w-5xl px-4 pb-6 pt-14 text-center sm:pt-20">
        <h1 className="text-4xl leading-[1.05] sm:text-6xl md:text-7xl">
          CAMISAS QUE <span className="text-magenta">CONTAM</span>
          <br />A SUA <span className="text-ciano">MARCA</span>
          <span className="text-amarelo">.</span>
        </h1>
        <p className="mx-auto mt-5 max-w-md text-tinta/70">
          Estamos começando pelo Espírito Santo.{" "}
          <span className="font-semibold text-tinta">
            Clique no seu estado para começar.
          </span>
        </p>
      </section>

      {/* MAPA — elemento assinatura */}
      <section className="mx-auto max-w-5xl px-4">
        <BrazilMap />
      </section>

      {/* DOIS CAMINHOS */}
      <section className="mx-auto grid max-w-5xl gap-5 px-4 pb-20 pt-12 md:grid-cols-2">
        <Link
          to="/produtos"
          className="group rounded-2xl bg-magenta p-7 text-white shadow-md transition hover:-translate-y-0.5 hover:shadow-xl"
        >
          <p className="text-xs font-bold uppercase tracking-widest opacity-80">
            Caminho 1
          </p>
          <h2 className="mt-1 text-3xl">Empresarial</h2>
          <p className="mt-2 text-sm opacity-90">
            Camisas para sua empresa. Clique no seu estado no mapa para
            começar — ou entre direto por aqui se você é do ES.
          </p>
          <span className="mt-4 inline-block text-sm font-semibold underline-offset-4 group-hover:underline">
            Ver modelos →
          </span>
        </Link>

        <Link
          to="/em-breve"
          state={{ origem: "individual" }}
          className="group relative rounded-2xl border-2 border-ciano bg-white p-7 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg"
        >
          <span className="absolute right-5 top-5 rounded-full bg-amarelo px-3 py-1 text-[10px] font-bold uppercase tracking-wider text-tinta">
            Em breve
          </span>
          <p className="text-xs font-bold uppercase tracking-widest text-ciano">
            Caminho 2
          </p>
          <h2 className="mt-1 text-3xl">Individual</h2>
          <p className="mt-2 text-sm text-tinta/70">
            Compre uma camisa avulsa para você. Em construção.
          </p>
        </Link>
      </section>
    </main>
  );
}
