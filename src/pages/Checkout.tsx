import { useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import Header from "../components/Header";
import ShirtPreview from "../components/ShirtPreview";
import { useProductsByState } from "../hooks/useProductsByState";
import { obterUF } from "../lib/estado";
import { formatarCNPJ, validarCNPJ } from "../lib/cnpj";
import { formatarPreco } from "../lib/format";
import { supabaseConfigurado } from "../lib/supabase";
import type { Customization } from "../types";

/*
 * TEMPORÁRIO: fluxo legado de camisas mantido apenas até a
 * substituição pelo módulo de exclusividades comerciais BDFlow.
 * Não usar como regra do BDFlow.
 *
 * Nesta fase de estabilização a precificação antiga (desconto por
 * volume/faixas e fidelidade percentual) foi REMOVIDA. O valor aqui
 * é apenas ilustrativo do fluxo legado; o pagamento permanece
 * indisponível e nenhum pedido é criado.
 */

// Mínimo legado, restrito a esta tela. Não é regra do BDFlow.
const QUANTIDADE_MINIMA_LEGADA = 10;

export default function Checkout() {
  const { state } = useLocation() as { state?: Customization };
  const { products } = useProductsByState(obterUF() ?? "");
  const produto = products.find((p) => p.slug === state?.productSlug);
  const quantidade = Math.max(
    QUANTIDADE_MINIMA_LEGADA,
    state?.quantidade ?? QUANTIDADE_MINIMA_LEGADA
  );

  const [empresa, setEmpresa] = useState("");
  const [email, setEmail] = useState("");
  const [cnpj, setCnpj] = useState("");
  const [erroCnpj, setErroCnpj] = useState<string | null>(null);

  const cnpjValido = validarCNPJ(cnpj);
  const formularioOk = empresa.trim() && email.includes("@") && cnpjValido;

  const validarCampoCnpj = () => {
    if (!cnpj) return setErroCnpj(null);
    setErroCnpj(
      cnpjValido ? null : "CNPJ inválido. Confira os números digitados."
    );
  };

  if (!state || !produto) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-3xl px-4 py-24 text-center">
          <h1 className="text-3xl">Nenhum pedido em andamento</h1>
          <p className="mt-3 text-tinta/70">
            Escolha um modelo e personalize sua camisa primeiro.
          </p>
          <Link to="/produtos" className="btn-primary mt-6">
            Ver modelos
          </Link>
        </main>
      </>
    );
  }

  // ---- Cálculo TEMPORÁRIO do fluxo legado (sem desconto) ----
  const subtotal = produto.preco * quantidade;
  const total = subtotal;

  return (
    <>
      <Header />
      <main className="mx-auto grid max-w-6xl gap-10 px-4 pb-20 pt-10 lg:grid-cols-[1fr_400px]">
        {/* CADASTRO */}
        <section>
          <h1 className="text-3xl sm:text-4xl">Finalizar compra</h1>
          <p className="mt-2 text-sm text-tinta/70">
            O cadastro é pedido apenas agora, na finalização.
          </p>

          <div className="mt-4 rounded-2xl border border-amarelo bg-amarelo/15 px-4 py-3 text-xs text-tinta/70">
            Fluxo comercial legado em transição. Os valores desta tela não
            representam as exclusividades comerciais BDFlow. O pagamento
            permanece indisponível.
          </div>

          <div className="card mt-6 space-y-5 p-6">
            <div>
              <label htmlFor="empresa" className="mb-1.5 block font-semibold">
                Nome da empresa
              </label>
              <input
                id="empresa"
                value={empresa}
                onChange={(e) => setEmpresa(e.target.value)}
                className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
              />
            </div>

            <div>
              <label htmlFor="email" className="mb-1.5 block font-semibold">
                E-mail
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
              />
              <p className="mt-1 text-xs text-tinta/50">
                As informações fiscais e a confirmação da contratação serão
                apresentadas no fluxo comercial definitivo.
              </p>
            </div>

            <div>
              <label htmlFor="cnpj" className="mb-1.5 block font-semibold">
                CNPJ
              </label>
              <input
                id="cnpj"
                inputMode="numeric"
                value={cnpj}
                onChange={(e) => setCnpj(formatarCNPJ(e.target.value))}
                onBlur={validarCampoCnpj}
                placeholder="00.000.000/0000-00"
                className={`w-full rounded-xl border px-4 py-3 outline-none transition ${
                  erroCnpj
                    ? "border-magenta"
                    : cnpjValido
                      ? "border-green-500"
                      : "border-borda focus:border-ciano"
                }`}
              />
              {erroCnpj && (
                <p className="mt-1 text-sm font-medium text-magenta">
                  {erroCnpj}
                </p>
              )}
              {cnpjValido && (
                <p className="mt-1 text-sm font-medium text-green-600">
                  CNPJ válido ✓
                </p>
              )}
            </div>
          </div>

          {/* PAGAMENTO — indisponível nesta fase de transição */}
          <div className="mt-6 rounded-2xl border-2 border-dashed border-borda p-6">
            <h2 className="text-xl">Pagamento</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Pagamento indisponível nesta etapa. O checkout de
              exclusividades comerciais BDFlow será implementado nas
              próximas fases.
            </p>
            <button
              disabled
              className="btn-primary mt-4"
              title="Indisponível"
            >
              Pagar {formularioOk ? formatarPreco(total) : ""}
            </button>
          </div>

          <p className="mt-6 text-center text-xs text-tinta/40">
            Política de trocas (em breve) · Termos de uso (em breve) ·
            Privacidade (em breve)
          </p>
        </section>

        {/* RESUMO */}
        <aside className="card h-fit p-6 lg:sticky lg:top-6">
          <h2 className="text-xl">Resumo do pedido</h2>
          <div className="mt-4">
            <ShirtPreview
              corBase={produto.cor_base}
              fraseFixa={produto.frase_fixa}
              fraseCustomizada={state.fraseCustomizada}
              imagemUrl={state.imagemUrl}
              compacto
            />
          </div>
          <dl className="mt-4 space-y-2 text-sm">
            <div className="flex justify-between">
              <dt className="text-tinta/60">Modelo</dt>
              <dd className="font-semibold">{produto.nome}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-tinta/60">Quantidade</dt>
              <dd className="font-semibold">{quantidade} un.</dd>
            </div>
            <div className="flex justify-between border-b border-borda/60 py-2 text-sm">
              <dt className="text-tinta/60">Estado comercial</dt>
              <dd className="font-semibold">{obterUF()}</dd>
            </div>
            {state.fraseCustomizada && (
              <div className="flex justify-between">
                <dt className="text-tinta/60">Sua frase</dt>
                <dd className="font-semibold">“{state.fraseCustomizada}”</dd>
              </div>
            )}
            <div className="flex justify-between border-t border-borda pt-2">
              <dt className="text-tinta/60">
                Subtotal ({formatarPreco(produto.preco)} / un.)
              </dt>
              <dd>{formatarPreco(subtotal)}</dd>
            </div>
            <div className="flex justify-between border-t border-borda pt-2 text-base">
              <dt className="font-semibold">Total</dt>
              <dd className="font-bold">{formatarPreco(total)}</dd>
            </div>
          </dl>
          <p className="mt-3 text-xs text-tinta/40">
            Valores do fluxo legado, apenas ilustrativos. Não representam as
            exclusividades comerciais BDFlow.
          </p>
        </aside>
      </main>
    </>
  );
}
