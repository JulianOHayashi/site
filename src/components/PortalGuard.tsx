import { useEffect, useState } from "react";
import { Link, Navigate, useLocation } from "react-router-dom";
import SiteHeader from "./SiteHeader";
import { usePortalSiteAuth } from "../hooks/usePortalSiteAuth";
import { supabaseConfigurado } from "../lib/supabase";
import {
  obterContextoConta,
  obterEstadoBloqueioParceiro,
  type ContextoConta,
  type EstadoBloqueioParceiro,
} from "../services/partnerApplicationService";

/**
 * PortalGuard — acesso ao Portal do parceiro APROVADO.
 *
 * Regra absoluta: os filhos só são renderizados diante de PROVA POSITIVA de
 * que a conta é um parceiro autorizado. Tudo o mais nega.
 *
 *   carregando            -> nada renderiza
 *   sem sessão            -> login, preservando o destino
 *   erro                  -> DENY (falha de consulta nunca vira permissão)
 *   provisória            -> redireciona à área de acompanhamento
 *   sem_contexto_parceiro -> DENY
 *   parceiro_autorizado   -> ALLOW
 *
 * POR QUE NINGUÉM ENTRA HOJE
 * `parceiro_autorizado` não é produzido no M1: a promoção a parceiro
 * aprovado pertence ao M2. Ausência de solicitação NÃO é autorização — uma
 * conta Auth qualquer, sem vínculo nenhum, satisfaria essa condição. Como o
 * M1 ainda não sabe dizer "esta conta é parceira", o guard permanece
 * fechado em vez de inventar um contexto positivo. Nada de
 * site_partner_members, que sequer existe no banco.
 *
 * Quando o M2 introduzir o vínculo operacional, basta obterContextoConta
 * passar a devolver `parceiro_autorizado`: este arquivo não muda.
 */
type Decisao = "carregando" | "erro" | "provisoria" | "sem_contexto" | "liberado";

/** Exposto para teste da unidade de decisão; não usado em produção. */
export function decidirParaTeste(ctx: ContextoConta | null): Decisao {
  return decidir(ctx);
}

function decidir(ctx: ContextoConta | null): Decisao {
  if (ctx === null) return "carregando";
  switch (ctx.tipo) {
    case "parceiro_autorizado":
      return "liberado";
    case "provisoria":
      return "provisoria";
    case "sem_contexto_parceiro":
      return "sem_contexto";
    // "erro", "carregando" e "nao_autenticado" nunca liberam.
    default:
      return "erro";
  }
}

export default function PortalGuard({ children }: { children: React.ReactNode }) {
  const { session, carregando } = usePortalSiteAuth();
  const location = useLocation();
  const [contexto, setContexto] = useState<ContextoConta | null>(null);
  const [bloqueio, setBloqueio] = useState<EstadoBloqueioParceiro | "carregando" | "erro">("carregando");

  useEffect(() => {
    let ativo = true;
    if (carregando || !session) {
      setContexto(null);
      setBloqueio("carregando");
      return;
    }
    (async () => {
      try {
        const ctx = await obterContextoConta();
        if (!ativo) return;
        setContexto(ctx);

        if (ctx.tipo === "sem_contexto_parceiro") {
          const estado = await obterEstadoBloqueioParceiro(session.user.id);
          if (!ativo) return;
          setBloqueio(estado.tipo === "ok" ? estado.estado : "erro");
        } else {
          setBloqueio(null);
        }
      } catch {
        // Exceção inesperada também é erro, e erro nega.
        if (ativo) {
          setContexto({ tipo: "erro" });
          setBloqueio("erro");
        }
      }
    })();
    return () => {
      ativo = false;
    };
  }, [carregando, session]);

  if (!supabaseConfigurado) {
    return (
      <>
        <SiteHeader />
        <main className="mx-auto mt-16 max-w-md px-4">
          <div className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
            Portal em configuração.
          </div>
        </main>
      </>
    );
  }

  if (carregando) return <Carregando texto="Carregando..." />;

  if (!session) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/portal/login?next=${next}`} replace />;
  }

  const decisao = decidir(contexto);

  if (decisao === "carregando") return <Carregando texto="Verificando acesso..." />;

  if (decisao === "provisoria") return <Navigate to="/parceiros/solicitacao" replace />;

  if (decisao === "erro") {
    return (
      <Negado
        titulo="Não foi possível verificar seu acesso."
        detalhe="Por segurança, o portal não foi aberto. Tente novamente em instantes."
      />
    );
  }

  if (decisao === "sem_contexto") {
    if (bloqueio === "carregando") {
      return <Carregando texto="Verificando acesso..." />;
    }

    if (bloqueio === "suspended") {
      return (
        <Negado
          titulo="Acesso temporariamente suspenso."
          detalhe="Seu acesso de manager foi suspenso pelo responsável da empresa. Enquanto estiver suspenso, o Portal e as validações permanecem bloqueados."
        />
      );
    }

    if (bloqueio === "revoked") {
      return (
        <Negado
          titulo="Acesso de manager revogado."
          detalhe="Este vínculo foi revogado definitivamente. Um novo convite não reativa automaticamente este acesso."
        />
      );
    }

    return (
      <Negado
        titulo="Portal indisponível para esta conta."
        detalhe="Esta conta não possui um vínculo ativo de parceiro com acesso ao Portal."
      />
    );
  }

  return <>{children}</>;
}

function Negado({
  titulo,
  detalhe,
  acao,
}: {
  titulo: string;
  detalhe: string;
  acao?: { para: string; rotulo: string };
}) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto mt-16 max-w-md px-4">
        <div role="alert" className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
          <p className="font-semibold">{titulo}</p>
          <p className="mt-2 text-tinta/70">{detalhe}</p>
          {acao ? (
            <Link to={acao.para} className="btn-primary mt-5 inline-block">
              {acao.rotulo}
            </Link>
          ) : null}
        </div>
      </main>
    </>
  );
}

function Carregando({ texto }: { texto: string }) {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto mt-24 flex max-w-md flex-col items-center gap-3 px-4">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
        <p className="text-sm text-tinta/60" role="status">
          {texto}
        </p>
      </main>
    </>
  );
}
