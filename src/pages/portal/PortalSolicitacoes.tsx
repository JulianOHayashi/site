import { useCallback, useEffect, useState } from "react";
import Header from "../../components/Header";
import { appSupabase, portalConfigurado } from "../../lib/appSupabaseClient";
import {
  BadgeStatus,
  CarregandoPortal,
  PortalNaoConfigurado,
  PortalTopo,
  centavos,
  dataBr,
  pegar,
  useExigirSessaoPortal,
} from "./portalUi";

/**
 * /portal/solicitacoes — solicitações de uso criadas pelo parceiro.
 * RPC: get_my_partner_redemption_requests()
 * Cancelamento (apenas pendentes): cancel_partner_redemption_request(p_request_id)
 */

type Dados = Record<string, unknown>;

function normalizarLista(data: unknown): Dados[] {
  if (data == null) return [];
  if (Array.isArray(data)) return data as Dados[];
  if (typeof data === "object") {
    const obj = data as Dados;
    // alguns RPCs retornam { requests: [...] }
    const interna = obj.requests ?? obj.data ?? obj.items;
    if (Array.isArray(interna)) return interna as Dados[];
    return [obj];
  }
  return [];
}

export default function PortalSolicitacoes() {
  const { session, carregando } = useExigirSessaoPortal();
  const [lista, setLista] = useState<Dados[]>([]);
  const [buscando, setBuscando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [cancelando, setCancelando] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    if (!appSupabase) return;
    setBuscando(true);
    setErro(null);
    const { data, error } = await appSupabase.rpc(
      "get_my_partner_redemption_requests"
    );
    setBuscando(false);
    if (error) {
      setErro("Não foi possível carregar as solicitações. Tente novamente.");
      return;
    }
    setLista(normalizarLista(data));
  }, []);

  useEffect(() => {
    if (session) carregar();
  }, [session, carregar]);

  const cancelar = async (id: string) => {
    if (!appSupabase) return;
    setCancelando(id);
    const { error } = await appSupabase.rpc(
      "cancel_partner_redemption_request",
      { p_request_id: id }
    );
    setCancelando(null);
    if (error) {
      setErro("Não foi possível cancelar esta solicitação.");
      return;
    }
    carregar();
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

  if (!session) return null;

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Solicitações" />

        {erro && (
          <p className="mt-6 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
            {erro}
          </p>
        )}

        {lista.length === 0 && !erro ? (
          <div className="mt-10 rounded-3xl border border-dashed border-borda p-14 text-center">
            <p className="text-lg font-semibold">Nenhuma solicitação encontrada.</p>
            <p className="mt-1 text-sm text-tinta/60">
              As solicitações de uso de benefício aparecem aqui após a
              validação de um QR code.
            </p>
          </div>
        ) : (
          <ul className="mt-8 space-y-4">
            {lista.map((s, i) => {
              const id = String(pegar(s, ["id", "request_id"]) ?? i);
              const status = String(pegar(s, ["status", "request_status"]) ?? "");
              const valor = centavos(
                pegar(s, [
                  "amount_cents",
                  "requested_amount_cents",
                  "value_cents",
                  "valor_cents",
                ])
              );
              const cliente = pegar(s, [
                "user_display_name",
                "display_name",
                "first_name",
                "nome",
              ]);
              const criada = dataBr(pegar(s, ["created_at", "criado_em"]));
              const expira = dataBr(pegar(s, ["expires_at", "expira_em"]));
              const pendente = status === "pending_user_confirmation";

              return (
                <li
                  key={id}
                  className="rounded-3xl border border-borda bg-white/85 p-5 backdrop-blur"
                >
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <BadgeStatus status={status} />
                      <div className="mt-2 space-y-0.5 text-sm">
                        {cliente != null && (
                          <p>
                            <span className="text-tinta/50">Cliente:</span>{" "}
                            <span className="font-semibold">{String(cliente)}</span>
                          </p>
                        )}
                        {valor && (
                          <p>
                            <span className="text-tinta/50">Valor:</span>{" "}
                            <span className="font-semibold">{valor}</span>
                          </p>
                        )}
                        {criada && (
                          <p className="text-tinta/50">Criada em {criada}</p>
                        )}
                        {expira && (
                          <p className="text-tinta/50">Expira em {expira}</p>
                        )}
                      </div>
                    </div>

                    {pendente && (
                      <button
                        onClick={() => cancelar(id)}
                        disabled={cancelando === id}
                        className="rounded-xl border-2 border-magenta px-4 py-2 text-sm font-semibold text-magenta transition hover:bg-magenta hover:text-white disabled:opacity-50"
                      >
                        {cancelando === id ? "Cancelando..." : "Cancelar"}
                      </button>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </main>
    </>
  );
}
