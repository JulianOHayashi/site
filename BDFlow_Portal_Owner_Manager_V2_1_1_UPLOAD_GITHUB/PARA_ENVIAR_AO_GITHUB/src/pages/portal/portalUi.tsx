import { Link } from "react-router-dom";

/* =====================================================================
   Utilitários visuais das páginas /portal.
   Nesta etapa o portal autentica no Supabase do SITE; nenhum helper
   aqui importa ou referencia o cliente do aplicativo.
===================================================================== */

/** Rótulos PT-BR dos status de solicitação (reuso futuro) */
export const STATUS_SOLICITACAO: Record<
  string,
  { rotulo: string; classes: string }
> = {
  pending_user_confirmation: {
    rotulo: "Aguardando confirmação do usuário",
    classes: "bg-amarelo/25 text-tinta",
  },
  approved_pending_settlement: {
    rotulo: "Aprovada — aguardando liquidação",
    classes: "bg-[#E8F7EE] text-[#0B7A3E]",
  },
  rejected: { rotulo: "Recusada", classes: "bg-magenta/10 text-magenta" },
  expired: { rotulo: "Expirada", classes: "bg-papel2 text-tinta/60" },
  cancelled: { rotulo: "Cancelada", classes: "bg-papel2 text-tinta/60" },
};

export function BadgeStatus({ status }: { status: string }) {
  const s = STATUS_SOLICITACAO[status] ?? {
    rotulo: status,
    classes: "bg-papel2 text-tinta/70",
  };
  return (
    <span
      className={`inline-block rounded-full px-3 py-1 text-xs font-semibold ${s.classes}`}
    >
      {s.rotulo}
    </span>
  );
}

/** Formata *_cents para BRL */
export function centavos(v: unknown): string | null {
  if (typeof v !== "number") return null;
  return (v / 100).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });
}

/** Formata datas ISO para pt-BR */
export function dataBr(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const d = new Date(v);
  if (isNaN(d.getTime())) return null;
  return d.toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Extrai o primeiro campo presente entre candidatos */
export function pegar(
  obj: Record<string, unknown> | null | undefined,
  chaves: string[]
): unknown {
  if (!obj) return undefined;
  for (const k of chaves) {
    if (obj[k] !== undefined && obj[k] !== null) return obj[k];
  }
  return undefined;
}

/** Cabeçalho comum das páginas internas do portal */
export function PortalTopo({
  titulo,
  onSair,
}: {
  titulo: string;
  onSair?: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
        </p>
        <h1 className="mt-1 text-3xl sm:text-4xl">{titulo}</h1>
      </div>
      <nav className="flex items-center gap-2 text-sm font-semibold">
        <Link
          to="/portal/dashboard"
          className="rounded-xl border-2 border-borda px-3 py-2 transition hover:border-tinta"
        >
          Início
        </Link>
        <Link
          to="/portal/validar"
          className="rounded-xl border-2 border-borda px-3 py-2 transition hover:border-tinta"
        >
          Validar QR
        </Link>
        <Link
          to="/portal/solicitacoes"
          className="rounded-xl border-2 border-borda px-3 py-2 transition hover:border-tinta"
        >
          Solicitações
        </Link>
        {onSair && (
          <button
            onClick={onSair}
            className="rounded-xl border-2 border-tinta px-3 py-2 transition hover:bg-tinta hover:text-white"
          >
            Sair
          </button>
        )}
      </nav>
    </div>
  );
}

export function CarregandoPortal() {
  return (
    <div className="mt-24 flex flex-col items-center gap-3">
      <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
      <p className="text-sm text-tinta/60">Carregando portal...</p>
    </div>
  );
}

export function PortalNaoConfigurado() {
  return (
    <div className="mx-auto mt-10 max-w-md rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
      Portal em configuração — defina VITE_SUPABASE_URL e
      VITE_SUPABASE_ANON_KEY na Vercel e faça Redeploy.
    </div>
  );
}

/* =====================================================================
   Cabeçalho calculado pelo CONTEXTO AUTORIZADO.

   Diferente de `PortalTopo` (legado, links fixos), este cabeçalho recebe
   a navegação já derivada de papel + capacidades. Itens proibidos nunca
   são renderizados — nem durante o carregamento, pois as páginas só o
   montam depois que o contexto está resolvido.
===================================================================== */
export function PortalCabecalho({
  titulo,
  itens,
  onSair,
}: {
  titulo: string;
  itens: readonly { rotulo: string; to: string }[];
  onSair?: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
        </p>
        <h1 className="mt-1 text-3xl sm:text-4xl">{titulo}</h1>
      </div>
      <nav
        aria-label="Navegação do portal"
        className="flex flex-wrap items-center gap-2 text-sm font-semibold"
      >
        {itens.map((i) => (
          <Link
            key={i.to}
            to={i.to}
            className="rounded-xl border-2 border-borda px-3 py-2 transition hover:border-tinta focus:outline-none focus-visible:ring-2 focus-visible:ring-ciano"
          >
            {i.rotulo}
          </Link>
        ))}
        {onSair && (
          <button
            onClick={onSair}
            className="rounded-xl border-2 border-tinta px-3 py-2 transition hover:bg-tinta hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-ciano"
          >
            Sair
          </button>
        )}
      </nav>
    </div>
  );
}

/** Linha rótulo/valor que mostra ausência real em vez de inventar dado. */
export function CampoInfo({
  rotulo,
  valor,
}: {
  rotulo: string;
  valor: string | number | null | undefined;
}) {
  const vazio = valor === null || valor === undefined || valor === "";
  return (
    <div>
      <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
        {rotulo}
      </p>
      <p className={`mt-0.5 ${vazio ? "text-sm text-tinta/40" : "font-semibold"}`}>
        {vazio ? "Não informado pelo sistema" : valor}
      </p>
    </div>
  );
}
