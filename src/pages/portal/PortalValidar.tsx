import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { appSupabase, portalConfigurado } from "../../lib/appSupabaseClient";
import {
  CarregandoPortal,
  PortalNaoConfigurado,
  PortalTopo,
  centavos,
  pegar,
  useExigirSessaoPortal,
} from "./portalUi";

/**
 * /portal/validar?qt=<public_lookup_id>
 *
 * Fluxo (spec):
 * 1. Exige sessão do parceiro (sem sessão → login preservando ?qt=)
 * 2. Lê qt da URL → validate_partner_wallet_qr(p_public_lookup_id)
 * 3. Sucesso → mostra APENAS dados seguros retornados pelo RPC
 * 4. Botão "Solicitar uso do benefício" →
 *    create_partner_redemption_request(p_public_lookup_id)
 *    (backend decide valor/usuário/parceiro — o frontend NÃO envia
 *    amount_cents, user_id, partner_id, grant_id ou
 *    benefit_cycle_partner_id)
 */

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Dados = Record<string, unknown>;

function normalizar(data: unknown): Dados | null {
  if (data == null) return null;
  if (Array.isArray(data)) return (data[0] as Dados) ?? null;
  if (typeof data === "object") return data as Dados;
  return null;
}

/** Campos seguros exibíveis do resultado da validação */
const CAMPOS_VALIDACAO: {
  chaves: string[];
  rotulo: string;
  formato?: "brl";
}[] = [
  {
    chaves: ["display_name", "user_display_name", "first_name", "nome"],
    rotulo: "Cliente",
  },
  {
    chaves: ["partial_document", "document_partial", "documento_parcial"],
    rotulo: "Documento",
  },
  {
    chaves: [
      "available_amount_cents",
      "benefit_value_cents",
      "amount_cents",
      "valor_cents",
    ],
    rotulo: "Benefício disponível",
    formato: "brl",
  },
  { chaves: ["benefit_name", "beneficio"], rotulo: "Tipo de benefício" },
  {
    chaves: ["eligible", "eligibility", "partner_eligible"],
    rotulo: "Elegível neste parceiro",
  },
  { chaves: ["status", "qr_status"], rotulo: "Status do QR" },
];

export default function PortalValidar() {
  const [params] = useSearchParams();
  const { session, carregando } = useExigirSessaoPortal();

  const qt = (params.get("qt") ?? "").trim();
  const qtValido = UUID_RE.test(qt);

  const [validando, setValidando] = useState(false);
  const [resultado, setResultado] = useState<Dados | null>(null);
  const [erroValidacao, setErroValidacao] = useState<string | null>(null);

  const [solicitando, setSolicitando] = useState(false);
  const [solicitacaoOk, setSolicitacaoOk] = useState(false);
  const [erroSolicitacao, setErroSolicitacao] = useState<string | null>(null);

  // Validação automática ao carregar com sessão + qt válido
  useEffect(() => {
    if (!appSupabase || !session || !qtValido) return;
    let ativo = true;
    setValidando(true);
    setErroValidacao(null);
    setResultado(null);

    appSupabase
      .rpc("validate_partner_wallet_qr", { p_public_lookup_id: qt })
      .then(({ data, error }) => {
        if (!ativo) return;
        setValidando(false);
        if (error) {
          setErroValidacao(
            "Não foi possível validar este QR Code. Ele pode estar expirado, já utilizado ou não ser elegível neste estabelecimento."
          );
          return;
        }
        const r = normalizar(data);
        if (!r) {
          setErroValidacao("QR Code inválido ou ausente.");
          return;
        }
        setResultado(r);
      });

    return () => {
      ativo = false;
    };
  }, [session, qt, qtValido]);

  const solicitarUso = async () => {
    if (!appSupabase) return;
    setSolicitando(true);
    setErroSolicitacao(null);
    const { error } = await appSupabase.rpc(
      "create_partner_redemption_request",
      { p_public_lookup_id: qt }
    );
    setSolicitando(false);
    if (error) {
      setErroSolicitacao(
        "Não foi possível criar a solicitação. Verifique se o benefício ainda está disponível e tente novamente."
      );
      return;
    }
    setSolicitacaoOk(true);
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

  if (carregando)
    return (
      <>
        <Header />
        <CarregandoPortal />
      </>
    );

  if (!session) return null; // redirecionando ao login (com ?qt= preservado)

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Validar QR code" />

        {/* qt ausente ou malformado */}
        {!qtValido && (
          <div className="mt-8 rounded-2xl border-2 border-magenta/30 bg-magenta/10 p-6 text-center">
            <p className="text-lg font-semibold text-magenta">
              QR Code inválido ou ausente.
            </p>
            <p className="mt-2 text-sm text-tinta/70">
              Escaneie o QR da carteira BDFlow do cliente — o link abre esta
              página automaticamente com o código.
            </p>
          </div>
        )}

        {/* validando */}
        {qtValido && validando && (
          <div className="mt-10 flex flex-col items-center gap-3">
            <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
            <p className="text-sm text-tinta/60">Validando QR code...</p>
          </div>
        )}

        {/* erro de validação */}
        {qtValido && erroValidacao && (
          <div className="mt-8 rounded-2xl border-2 border-magenta/30 bg-magenta/10 p-6 text-center">
            <p className="font-semibold text-magenta">{erroValidacao}</p>
            <Link to="/portal/dashboard" className="btn-secondary mt-4">
              Voltar ao painel
            </Link>
          </div>
        )}

        {/* resultado válido */}
        {qtValido && resultado && !solicitacaoOk && (
          <div className="mt-8 rounded-3xl border-2 border-[#0B7A3E]/30 bg-[#E8F7EE] p-6">
            <p className="text-center text-lg font-bold text-[#0B7A3E]">
              ✓ QR Code válido
            </p>
            <dl className="mt-4 space-y-2">
              {CAMPOS_VALIDACAO.map((c) => {
                const bruto = pegar(resultado, c.chaves);
                if (bruto == null) return null;
                let valor: string | null;
                if (c.formato === "brl") valor = centavos(bruto);
                else if (typeof bruto === "boolean")
                  valor = bruto ? "Sim" : "Não";
                else valor = String(bruto);
                if (valor == null) return null;
                return (
                  <div
                    key={c.rotulo}
                    className="flex justify-between gap-4 border-b border-[#0B7A3E]/15 py-1.5 text-sm"
                  >
                    <dt className="text-tinta/60">{c.rotulo}</dt>
                    <dd className="font-semibold">{valor}</dd>
                  </div>
                );
              })}
            </dl>

            {erroSolicitacao && (
              <p className="mt-4 rounded-xl bg-magenta/10 px-4 py-2.5 text-sm font-medium text-magenta">
                {erroSolicitacao}
              </p>
            )}

            <button
              onClick={solicitarUso}
              disabled={solicitando}
              className="btn-primary mt-5 w-full"
            >
              {solicitando ? "Enviando..." : "Solicitar uso do benefício"}
            </button>
            <p className="mt-2 text-center text-xs text-tinta/50">
              O valor e as condições são definidos pelo sistema BDFlow — o
              cliente confirma no app.
            </p>
          </div>
        )}

        {/* solicitação enviada */}
        {solicitacaoOk && (
          <div className="mt-8 rounded-3xl border-2 border-[#0B7A3E]/30 bg-[#E8F7EE] p-8 text-center">
            <p className="text-2xl">📲</p>
            <p className="mt-2 text-lg font-bold text-[#0B7A3E]">
              Solicitação enviada.
            </p>
            <p className="mt-1 text-sm text-tinta/70">
              O usuário precisa confirmar no app BDFlow.
            </p>
            <div className="mt-5 flex flex-wrap justify-center gap-3">
              <Link to="/portal/solicitacoes" className="btn-primary">
                Acompanhar solicitações
              </Link>
              <Link to="/portal/dashboard" className="btn-secondary">
                Voltar ao painel
              </Link>
            </div>
          </div>
        )}
      </main>
    </>
  );
}
