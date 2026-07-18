import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import BrazilMap from "../components/BrazilMap";
import { UFS, nomeParaSigla, salvarUF } from "../lib/estado";

/**
 * /selecionar-estado — PRIMEIRA tela do visitante.
 *
 * Reutiliza o componente BrazilMap existente (sem duplicar lógica) e
 * oferece alternativa acessível por grade de estados. Ao escolher:
 * valida a sigla → salva na fonte única (lib/estado) → segue para o
 * destino original (?next=) ou para a Home.
 *
 * Aqui NÃO há catálogo, checkout, admin nem portal — somente a
 * identificação do estado comercial.
 */
export default function SelecionarEstado() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [confirmando, setConfirmando] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const destino = (() => {
    const next = params.get("next");
    // aceita apenas caminhos internos (evita open redirect)
    return next && next.startsWith("/") && !next.startsWith("//") ? next : "/";
  })();

  const escolher = (entrada: string) => {
    const sigla = nomeParaSigla(entrada);
    if (!sigla) {
      setErro("Não foi possível reconhecer o estado selecionado. Tente novamente.");
      return;
    }
    setErro(null);
    setConfirmando(sigla); // feedback visual imediato
    if (!salvarUF(sigla)) {
      setConfirmando(null);
      setErro("Não foi possível salvar sua seleção neste navegador.");
      return;
    }
    // pequena pausa para o feedback ser perceptível
    window.setTimeout(() => navigate(destino, { replace: true }), 350);
  };

  return (
    <main className="relative flex min-h-screen flex-col items-center overflow-x-clip bg-papel px-4 pb-16 pt-10">
      {/* manchas de cor da identidade */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
        <div className="absolute -left-32 top-10 h-96 w-96 rounded-full bg-magenta/15 blur-3xl" />
        <div className="absolute -right-24 top-1/3 h-80 w-80 rounded-full bg-ciano/15 blur-3xl" />
        <div className="absolute bottom-0 left-1/3 h-72 w-72 rounded-full bg-amarelo/20 blur-3xl" />
      </div>

      {/* marca */}
      <p className="display relative text-2xl">
        camisas<span className="text-magenta">.</span>es
      </p>

      {/* título e instrução */}
      <h1 className="relative mt-8 text-center text-3xl sm:text-5xl">
        Escolha seu estado
        <span className="mx-auto mt-3 block h-2 w-28 rounded-full bg-magenta" />
      </h1>
      <p className="relative mx-auto mt-3 max-w-md text-center text-tinta/60">
        Selecione seu estado para visualizar os produtos e a disponibilidade
        na sua região.
      </p>

      {/* feedback da seleção */}
      <div className="relative mt-4 min-h-8 text-center" aria-live="polite">
        {confirmando && (
          <p className="inline-block rounded-full bg-tinta px-4 py-1.5 text-sm font-semibold text-white">
            ✓ {UFS[confirmando]} selecionado — carregando...
          </p>
        )}
        {erro && (
          <p className="inline-block rounded-full bg-magenta/10 px-4 py-1.5 text-sm font-semibold text-magenta">
            {erro}
          </p>
        )}
      </div>

      {/* mapa interativo (componente existente reutilizado; possui
          fallback interno caso o GeoJSON não carregue) */}
      <div className="relative mt-4 w-full max-w-2xl rounded-[2rem] border-2 border-tinta bg-white p-3 shadow-[0_30px_80px_rgba(23,18,31,0.18)] sm:p-5">
        <div className="mb-2 flex items-center gap-1.5 px-1">
          <span className="h-2.5 w-2.5 rounded-full bg-magenta" />
          <span className="h-2.5 w-2.5 rounded-full bg-amarelo" />
          <span className="h-2.5 w-2.5 rounded-full bg-ciano" />
          <span className="ml-3 text-[10px] font-semibold uppercase tracking-widest text-tinta/30">
            brasil.mapa
          </span>
        </div>
        <BrazilMap onSelectState={(nome) => escolher(nome)} />
      </div>

      {/* alternativa acessível: grade completa de estados */}
      <section className="relative mt-10 w-full max-w-2xl">
        <h2 className="text-center text-sm font-bold uppercase tracking-widest text-tinta/40">
          Ou escolha pela lista
        </h2>
        <div className="mt-4 grid grid-cols-3 gap-2 sm:grid-cols-5 md:grid-cols-6">
          {Object.entries(UFS).map(([sigla, nome]) => (
            <button
              key={sigla}
              type="button"
              onClick={() => escolher(sigla)}
              aria-label={`Selecionar ${nome}`}
              aria-pressed={confirmando === sigla}
              className={`rounded-xl border-2 px-2 py-2.5 text-sm font-bold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-magenta ${
                confirmando === sigla
                  ? "border-tinta bg-tinta text-white"
                  : "border-borda bg-white hover:border-magenta hover:text-magenta"
              }`}
            >
              {sigla}
              <span className="block text-[10px] font-medium text-current/60">
                {nome}
              </span>
            </button>
          ))}
        </div>
      </section>
    </main>
  );
}
