import { useState } from "react";
import { Link, useLocation } from "react-router-dom";
import Header from "../components/Header";
import ShirtPreview from "../components/ShirtPreview";
import { useProducts } from "../hooks/useProducts";
import { formatarCNPJ, validarCNPJ } from "../lib/cnpj";
import { formatarPreco } from "../lib/format";
import type { Customization } from "../types";

/*
 * ⚠️ TODOs desta página (decisões futuras — manter como placeholders):
 * - Integração de pagamento: Stripe OU Mercado Pago
 * - Regras de parcelamento e absorção de taxas
 * - Desconto fidelidade: % A DEFINIR, calculado pelo histórico do CNPJ (Supabase)
 * - Criação real do pedido (INSERT em orders — o trigger do banco baixa o estoque)
 * - Emissão de NF-e/NFS-e (NFe.io, Bling ou outro) enviada por email
 * - Email transacional de confirmação (Resend, SendGrid ou outro)
 * - Política de trocas/devoluções e termos LGPD
 */

export default function Checkout() {
  const { state } = useLocation() as { state?: Customization };
  const { products } = useProducts();
  const produto = products.find((p) => p.slug === state?.productSlug);

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
                Você receberá a confirmação do pedido e a nota fiscal por
                e-mail.
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

          {/* Fidelidade — visual apenas; regra real virá do Supabase */}
          <div className="mt-4 rounded-2xl bg-papel2 p-4 text-sm">
            💛 Clientes com compras anteriores recebem{" "}
            <span className="font-semibold">desconto fidelidade</span>{" "}
            automaticamente. <span className="text-tinta/50">(% a definir)</span>
          </div>

          {/* PAGAMENTO — PLACEHOLDER */}
          <div className="mt-6 rounded-2xl border-2 border-dashed border-borda p-6">
            <h2 className="text-xl">Pagamento</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Integração de pagamento em configuração (Stripe ou Mercado Pago —
              a definir). Parcelamento: condições a definir.
            </p>
            <button
              disabled
              className="btn-primary mt-4"
              title="Disponível em breve"
            >
              Pagar {formularioOk ? formatarPreco(produto.preco) : ""}
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
            {state.fraseCustomizada && (
              <div className="flex justify-between">
                <dt className="text-tinta/60">Sua frase</dt>
                <dd className="font-semibold">“{state.fraseCustomizada}”</dd>
              </div>
            )}
            <div className="flex justify-between border-t border-borda pt-2 text-base">
              <dt className="font-semibold">Total</dt>
              <dd className="font-bold">{formatarPreco(produto.preco)}</dd>
            </div>
          </dl>
        </aside>
      </main>
    </>
  );
}
