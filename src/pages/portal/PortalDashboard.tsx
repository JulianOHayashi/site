import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../../components/Header";
import { appSupabase, portalConfigurado } from "../../lib/appSupabaseClient";
import {
  CarregandoPortal,
  PortalNaoConfigurado,
  PortalTopo,
  centavos,
  dataBr,
  pegar,
  useExigirSessaoPortal,
} from "./portalUi";

/**
 * /portal/dashboard — visão geral do parceiro comercial.
 * RPCs: get_my_partner_context() + get_partner_cycle_status().
 * Exibição defensiva: somente campos seguros retornados pelos RPCs.
 */

type Dados = Record<string, unknown>;

function normalizar(data: unknown): Dados | null {
  if (data == null) return null;
  if (Array.isArray(data)) return (data[0] as Dados) ?? null;
  if (typeof data === "object") return data as Dados;
  return null;
}

/** Pares rótulo/valor seguros do status do ciclo */
const CAMPOS_CICLO: { chaves: string[]; rotulo: string; formato?: "brl" | "data" }[] = [
  { chaves: ["cycle_name", "cycle", "nome_ciclo"], rotulo: "Ciclo" },
  { chaves: ["status", "cycle_status", "contract_status"], rotulo: "Status" },
  { chaves: ["starts_at", "cycle_starts_at", "inicio"], rotulo: "Início", formato: "data" },
  { chaves: ["ends_at", "cycle_ends_at", "fim"], rotulo: "Fim", formato: "data" },
  { chaves: ["available_amount_cents", "available_cents", "saldo_cents"], rotulo: "Disponível", formato: "brl" },
  { chaves: ["total_amount_cents", "total_cents", "limite_cents"], rotulo: "Total do ciclo", formato: "brl" },
  { chaves: ["redemptions_count", "usos", "validations_count"], rotulo: "Usos no ciclo" },
];

export default function PortalDashboard() {
  const navigate = useNavigate();
  const { session, carregando } = useExigirSessaoPortal();
  const [contexto, setContexto] = useState<Dados | null>(null);
  const [ciclo, setCiclo] = useState<Dados | null>(null);
  const [semVinculo, setSemVinculo] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [buscando, setBuscando] = useState(true);

  useEffect(() => {
    if (!appSupabase || !session) return;
    let ativo = true;

    (async () => {
      const [ctx, cyc] = await Promise.all([
        appSupabase!.rpc("get_my_partner_context"),
        appSupabase!.rpc("get_partner_cycle_status"),
      ]);
      if (!ativo) return;

      if (ctx.error) {
        setErro("Não foi possível carregar seus dados de parceiro. Tente novamente.");
      } else {
        const c = normalizar(ctx.data);
        if (!c) setSemVinculo(true);
        else setContexto(c);
      }

      if (!cyc.error) setCiclo(normalizar(cyc.data));
      setBuscando(false);
    })();

    return () => {
      ativo = false;
    };
  }, [session]);

  const sair = async () => {
    await appSupabase?.auth.signOut();
    navigate("/portal/login");
  };

  if (!portalConfigurado)
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14">
          <PortalNaoConfigurado />
        </main>
      </>
    );

  if (carregando || (session && buscando))
    return (
      <>
        <Header />
        <CarregandoPortal />
      </>
    );

  if (!session) return null; // redirecionando ao login

  const nome =
    pegar(contexto, [
      "trade_name",
      "partner_name",
      "commercial_name",
      "name",
      "nome",
    ]) ?? "Parceiro";
  const papel = pegar(contexto, ["role", "user_role", "papel"]);

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Painel do parceiro" onSair={sair} />

        {erro && (
          <p className="mt-6 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
            {erro}
          </p>
        )}

        {semVinculo ? (
          <div className="mt-8 rounded-2xl border-2 border-amarelo bg-amarelo/15 p-6 text-center">
            <p className="font-semibold">
              Seu usuário ainda não está vinculado a um parceiro comercial
              BDFlow.
            </p>
          </div>
        ) : (
          <>
            {/* Identificação do parceiro */}
            <section className="mt-8 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Estabelecimento
              </p>
              <h2 className="mt-1 text-2xl font-bold">{String(nome)}</h2>
              {papel != null && (
                <p className="mt-1 text-sm text-tinta/60">
                  Seu papel: <span className="font-semibold">{String(papel)}</span>
                </p>
              )}
            </section>

            {/* Status do ciclo */}
            <section className="mt-5 rounded-3xl border border-borda bg-white/85 p-6 backdrop-blur">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Ciclo atual
              </p>
              {ciclo ? (
                <dl className="mt-3 grid gap-x-8 gap-y-2 sm:grid-cols-2">
                  {CAMPOS_CICLO.map((c) => {
                    const bruto = pegar(ciclo, c.chaves);
                    if (bruto == null) return null;
                    const valor =
                      c.formato === "brl"
                        ? centavos(bruto)
                        : c.formato === "data"
                          ? dataBr(bruto)
                          : String(bruto);
                    if (valor == null) return null;
                    return (
                      <div key={c.rotulo} className="flex justify-between gap-4 border-b border-borda/50 py-1.5 text-sm">
                        <dt className="text-tinta/60">{c.rotulo}</dt>
                        <dd className="font-semibold">{valor}</dd>
                      </div>
                    );
                  })}
                </dl>
              ) : (
                <p className="mt-3 text-sm text-tinta/60">
                  Nenhuma informação de ciclo disponível no momento.
                </p>
              )}
            </section>

            {/* Ações */}
            <section className="mt-8 grid gap-4 sm:grid-cols-2">
              <Link
                to="/portal/validar"
                className="group rounded-3xl bg-magenta p-7 text-white shadow-lg transition hover:-translate-y-1 hover:shadow-[0_20px_60px_rgba(229,0,126,0.35)]"
              >
                <span className="text-3xl">🔳</span>
                <h3 className="mt-3 text-2xl font-bold">Validar QR code</h3>
                <p className="mt-1 text-sm text-white/85">
                  Escaneie ou cole o código da carteira do cliente.
                </p>
                <span className="mt-4 inline-block font-semibold transition group-hover:translate-x-1">
                  Validar →
                </span>
              </Link>
              <Link
                to="/portal/solicitacoes"
                className="group rounded-3xl border-2 border-tinta bg-tinta p-7 text-papel shadow-lg transition hover:-translate-y-1 hover:shadow-[0_20px_60px_rgba(0,168,224,0.3)]"
              >
                <span className="text-3xl">📋</span>
                <h3 className="mt-3 text-2xl font-bold">Solicitações</h3>
                <p className="mt-1 text-sm text-papel/80">
                  Acompanhe e gerencie os usos de benefício solicitados.
                </p>
                <span className="mt-4 inline-block font-semibold text-ciano transition group-hover:translate-x-1">
                  Ver lista →
                </span>
              </Link>
            </section>
          </>
        )}
      </main>
    </>
  );
}
