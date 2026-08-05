import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Header from "../components/Header";
import { UFS } from "../lib/brazilStates";
import { useCommercialTerritory } from "../hooks/useCommercialTerritory";

/**
 * /selecionar-localidade — seleção de UF + cidade.
 *
 * As 27 UFs continuam disponíveis; a primeira região ativa é apenas no ES.
 * A cidade é texto validado — o BACKEND decide se pertence a uma região
 * ativa (não listamos só as cinco cidades como se fossem as únicas do ES).
 */
export default function SelecionarLocalidade() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { selectLocation, loading, error } = useCommercialTerritory();

  const [uf, setUf] = useState("ES");
  const [cidade, setCidade] = useState("");
  const [resultado, setResultado] = useState<
    { ativa: boolean; regionName: string | null } | null
  >(null);

  const destino = (() => {
    const next = params.get("next");
    return next && next.startsWith("/") && !next.startsWith("//")
      ? next
      : "/oportunidades";
  })();

  const confirmar = async () => {
    setResultado(null);
    const t = await selectLocation(uf, cidade);
    if (!t) return;
    setResultado({
      ativa: t.regionStatus === "active",
      regionName: t.regionName,
    });
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-xl px-4 pb-24 pt-10">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
          Região comercial
        </p>
        <h1 className="mt-3 text-3xl sm:text-4xl">
          Escolha sua localidade
          <span className="mt-3 block h-2 w-24 rounded-full bg-magenta" />
        </h1>
        <p className="mt-3 text-sm text-tinta/60">
          Informe seu estado e cidade para ver as oportunidades comerciais
          disponíveis na sua região.
        </p>

        <div className="card mt-6 space-y-5 p-6">
          <div>
            <label htmlFor="uf" className="mb-1.5 block text-sm font-semibold">
              Estado (UF)
            </label>
            <select
              id="uf"
              value={uf}
              onChange={(e) => {
                setUf(e.target.value);
                setResultado(null);
              }}
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-magenta"
            >
              {Object.entries(UFS).map(([sigla, nome]) => (
                <option key={sigla} value={sigla}>
                  {sigla} — {nome}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label htmlFor="cidade" className="mb-1.5 block text-sm font-semibold">
              Cidade
            </label>
            <input
              id="cidade"
              value={cidade}
              onChange={(e) => {
                setCidade(e.target.value);
                setResultado(null);
              }}
              placeholder="Digite o nome da cidade"
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-magenta"
            />
          </div>

          {error && (
            <p
              className="rounded-xl bg-magenta/10 px-4 py-2.5 text-sm font-medium text-magenta"
              aria-live="polite"
            >
              {error}
            </p>
          )}

          <button
            onClick={confirmar}
            disabled={loading || cidade.trim().length === 0}
            className="btn-primary w-full"
          >
            {loading ? "Verificando..." : "Confirmar localidade"}
          </button>
        </div>

        {/* Resultado da resolução */}
        {resultado && (
          <div className="mt-6" aria-live="polite">
            {resultado.ativa ? (
              <div className="rounded-3xl border-2 border-green-200 bg-green-50 p-6">
                <p className="font-display text-lg font-bold text-green-800">
                  Região comercial encontrada: {resultado.regionName}
                </p>
                <button
                  onClick={() => navigate(destino, { replace: true })}
                  className="btn-primary mt-4"
                >
                  Ver oportunidades
                </button>
              </div>
            ) : (
              <div className="rounded-3xl bg-papel2 p-6">
                <p className="font-semibold">
                  Ainda não há uma região comercial BDFlow ativa para esta
                  cidade.
                </p>
                <p className="mt-2 text-sm text-tinta/70">
                  O registro de interesse territorial será disponibilizado em
                  uma próxima etapa.
                </p>
              </div>
            )}
          </div>
        )}
      </main>
    </>
  );
}
