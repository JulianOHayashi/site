import { useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import Header from "../components/Header";
import ShirtPreview from "../components/ShirtPreview";
import { useProductsByState } from "../hooks/useProductsByState";
import { obterUF } from "../lib/estado";
import { formatarCNPJ, validarCNPJ } from "../lib/cnpj";
import { formatarPreco } from "../lib/format";
import {
  consultarDescontoFidelidade,
  DESCONTO_FIDELIDADE_DEMO,
} from "../lib/fidelidade";
import {
  QUANTIDADE_MINIMA,
  FAIXAS_PADRAO,
  carregarFaixas,
  descontoPorQuantidade,
  type Faixa,
} from "../lib/precificacao";
import { supabaseConfigurado } from "../lib/supabase";
import type { Customization } from "../types";

/*
 * DECISÕES JÁ TOMADAS (integrações a implementar):
 * - Pagamento: MERCADO PAGO (Pix, cartão, parcelas)
 * - Nota fiscal: BLING (NF-e automática após o pagamento, via API)
 * - Precificação: mínimo 10 un. (preço cheio) + desconto por volume
 *   em faixas + fidelidade por CNPJ em cascata. O cálculo REAL é do
 *   banco (trigger aplicar_precificacao); aqui apenas exibimos.
 *
 * ⚠️ AINDA A DEFINIR: percentuais finais (volume e fidelidade),
 * parcelamento, email transacional, políticas/termos.
 */

export default function Checkout() {
  const { state } = useLocation() as { state?: Customization };
  const { products } = useProductsByState(obterUF() ?? "");
  const produto = products.find((p) => p.slug === state?.productSlug);
  const quantidade = Math.max(
    QUANTIDADE_MINIMA,
    state?.quantidade ?? QUANTIDADE_MINIMA
  );

  const [empresa, setEmpresa] = useState("");
  const [email, setEmail] = useState("");
  const [cnpj, setCnpj] = useState("");
  const [erroCnpj, setErroCnpj] = useState<string | null>(null);
  const [descontoFid, setDescontoFid] = useState<number | null>(null);
  const [faixas, setFaixas] = useState<Faixa[]>(FAIXAS_PADRAO);

  useEffect(() => {
    carregarFaixas().then(setFaixas);
  }, []);

  const cnpjValido = validarCNPJ(cnpj);
  const formularioOk = empresa.trim() && email.includes("@") && cnpjValido;

  useEffect(() => {
    if (!cnpjValido) {
      setDescontoFid(null);
      return;
    }
    let ativo = true;
    consultarDescontoFidelidade(cnpj).then((pct) => {
      if (ativo) setDescontoFid(pct);
    });
    return () => {
      ativo = false;
    };
  }, [cnpj, cnpjValido]);

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

  // ---- Cálculo exibido (o oficial é feito pelo banco no pedido) ----
  const descVolume = descontoPorQuantidade(quantidade, faixas);
  const fidPct = descontoFid ?? 0;
  const temFidelidade = fidPct > 0;

  const subtotal = produto.preco * quantidade;
  const valorVolume = subtotal * (descVolume / 100);
  const aposVolume = subtotal - valorVolume;
  const valorFid = aposVolume * (fidPct / 100);
  const total = aposVolume - valorFid;

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
                Você receberá a confirmação do pedido e a nota fiscal (emitida
                via Bling) por e-mail.
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

          {/* FIDELIDADE — dinâmico conforme o CNPJ digitado */}
          {cnpjValido && descontoFid !== null ? (
            temFidelidade ? (
              <div className="mt-4 rounded-2xl border-2 border-green-200 bg-green-50 p-4 text-sm">
                💚 <span className="font-semibold">Bem-vindo de volta!</span>{" "}
                Cliente que retorna paga menos:{" "}
                <span className="font-bold">{fidPct}% de fidelidade</span>{" "}
                aplicado por cima do desconto de volume.
              </div>
            ) : (
              <div className="mt-4 rounded-2xl bg-papel2 p-4 text-sm">
                💛 <span className="font-semibold">Primeira compra?</span> O
                desconto por volume já vale pra você — e na próxima, seu CNPJ
                ganha{" "}
                <span className="font-bold">
                  +{DESCONTO_FIDELIDADE_DEMO}% de fidelidade
                </span>{" "}
                automaticamente.
                <span className="ml-1 text-tinta/40">(% a confirmar)</span>
              </div>
            )
          ) : (
            <div className="mt-4 rounded-2xl bg-papel2 p-4 text-sm">
              💛 Pedido mínimo de {QUANTIDADE_MINIMA} unidades; quanto maior o
              volume, menor o preço — e quem retorna ganha fidelidade extra
              pelo CNPJ.
            </div>
          )}

          {/* PAGAMENTO — MERCADO PAGO (integração a implementar) */}
          <div className="mt-6 rounded-2xl border-2 border-dashed border-borda p-6">
            <h2 className="text-xl">Pagamento</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Via <span className="font-semibold">Mercado Pago</span> — Pix,
              cartão e parcelamento. Integração em configuração.
              <span className="ml-1 text-tinta/40">
                (condições de parcelamento a definir)
              </span>
            </p>
            <button
              disabled
              className="btn-primary mt-4"
              title="Disponível em breve"
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
            {descVolume > 0 && (
              <div className="flex justify-between text-[#0B7A3E]">
                <dt>Volume ({descVolume}%)</dt>
                <dd>−{formatarPreco(valorVolume)}</dd>
              </div>
            )}
            {temFidelidade && (
              <div className="flex justify-between text-green-700">
                <dt>Fidelidade ({fidPct}%)</dt>
                <dd>−{formatarPreco(valorFid)}</dd>
              </div>
            )}
            <div className="flex justify-between border-t border-borda pt-2 text-base">
              <dt className="font-semibold">Total</dt>
              <dd className="font-bold">{formatarPreco(total)}</dd>
            </div>
          </dl>
          {!supabaseConfigurado && (
            <p className="mt-3 text-xs text-tinta/40">
              Modo demonstração: o cálculo oficial (volume + fidelidade) é
              feito pelo banco quando o Supabase estiver conectado.
            </p>
          )}
        </aside>
      </main>
    </>
  );
}
