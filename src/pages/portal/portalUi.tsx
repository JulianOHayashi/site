import { NavLink } from "react-router-dom";
import { useEmpresaOpcional } from "../../portal/empresaContexto";

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
    classes: "bg-amarelo/10 text-amarelo",
  },
  approved_pending_settlement: {
    rotulo: "Aprovada — aguardando liquidação",
    classes: "bg-verde/10 text-verde",
  },
  rejected: { rotulo: "Recusada", classes: "bg-vermelho/10 text-vermelho" },
  expired: { rotulo: "Expirada", classes: "bg-superficie2 text-tinta/65" },
  cancelled: { rotulo: "Cancelada", classes: "bg-superficie2 text-tinta/65" },
};

export function BadgeStatus({ status }: { status: string }) {
  const s = STATUS_SOLICITACAO[status] ?? {
    rotulo: status,
    classes: "bg-superficie2 text-tinta/70",
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

/**
 * Cabeçalho comum das páginas internas do portal.
 *
 * "Validar QR" e "Solicitações" dependem de uma empresa. Sem empresa
 * selecionada (escolhendo, carregando, com erro ou sem vínculo) eles ficam
 * fora do DOM, para não oferecer um destino que ainda não pode agir. "Início"
 * (que leva de volta à escolha) e "Sair" permanecem sempre. Isto é só
 * apresentação: as rotas e o servidor continuam se protegendo sozinhos diante
 * de uma URL digitada.
 */
/** Abas do Portal: estado ativo discreto (superfície elevada + traço da marca). */
const classeNavPortal = ({ isActive }: { isActive: boolean }) =>
  `relative inline-flex min-h-[40px] items-center rounded-xl px-3 py-2 transition ${
    isActive
      ? "bg-superficie3 text-tinta after:absolute after:inset-x-3 after:-bottom-px after:h-0.5 after:rounded-full after:bg-marca"
      : "text-tinta/70 hover:bg-superficie2 hover:text-tinta"
  }`;

export function PortalTopo({
  titulo,
  onSair,
}: {
  titulo: string;
  onSair?: () => void;
}) {
  const empresa = useEmpresaOpcional();
  // Fora da casca do Portal não há contexto para consultar: mantém o
  // comportamento anterior.
  const dependenteDeEmpresa = empresa === null || empresa.fase === "pronta";
  const podeGerenciarEquipe =
    empresa !== null &&
    empresa.fase === "pronta" &&
    empresa.atual.role === "partner_owner" &&
    empresa.atual.member_status === "active";
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p className="rotulo-marca">
          Portal do parceiro SmallFlags
        </p>
        <h1 className="mt-3 text-3xl sm:text-4xl">{titulo}</h1>
      </div>
      <nav aria-label="Portal" className="flex flex-wrap items-center gap-1 rounded-2xl border border-borda bg-superficie p-1 text-sm font-semibold">
        <NavLink
          to="/portal/dashboard"
          className={classeNavPortal}
        >
          Início
        </NavLink>
        <NavLink
          to="/portal/documentos"
          className={classeNavPortal}
        >
          Documentos
        </NavLink>
        {dependenteDeEmpresa && (
          <>
            <NavLink
              to="/portal/validar"
              className={classeNavPortal}
            >
              Validar QR
            </NavLink>
            <NavLink
              to="/portal/solicitacoes"
              className={classeNavPortal}
            >
              Solicitações
            </NavLink>
            {podeGerenciarEquipe && (
              <NavLink
                to="/portal/equipe"
                className={classeNavPortal}
              >
                Equipe
              </NavLink>
            )}
          </>
        )}
        {onSair && (
          <button
            onClick={onSair}
            className="min-h-[40px] rounded-xl px-3 py-2 text-tinta/70 transition hover:bg-superficie2 hover:text-tinta"
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
      <div className="h-9 w-9 animate-spin rounded-full border-[3px] border-borda border-t-ciano" />
      <p className="text-sm text-tinta/60">Carregando portal...</p>
    </div>
  );
}

export function PortalNaoConfigurado() {
  return (
    <div className="aviso-atencao mx-auto mt-10 max-w-md p-5 text-center">
      Portal em configuração — defina VITE_SUPABASE_URL e
      VITE_SUPABASE_ANON_KEY na Vercel e faça Redeploy.
    </div>
  );
}
