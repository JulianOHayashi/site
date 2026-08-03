/**
 * /portal/convites/:token — estrutura pública/autenticável do convite.
 *
 * GARANTIAS:
 *  • ABRIR esta página NÃO consome o convite. Pré-visualizações de WhatsApp,
 *    verificadores de segurança e cliques acidentais são inofensivos: nenhuma
 *    chamada de consumo é feita aqui. O convite só é marcado como utilizado
 *    quando o backend concluir o cadastro do manager, atomicamente.
 *  • Nada é revelado antes da validação segura do token pelo backend: nem
 *    nome da empresa, nem destinatário, nem qualquer outro dado.
 *  • `pathname + search` é preservado integralmente em `next` no redirect
 *    para /portal/login.
 */

import { useEffect, useState } from "react";
import { Link, useLocation, useParams } from "react-router-dom";
import Header from "../../components/Header";
import { usePortalSiteAuth } from "../../hooks/usePortalSiteAuth";
import { getPublicInvitation } from "../../services/partnerTeamService";
import { invitationVisualState } from "../../domain/portal/invitations";
import {
  INVITATION_TTL_HOURS,
  PORTAL_ERROR_LABEL,
  type ManagerInvitation,
  type PortalErrorCode,
} from "../../domain/portal/types";

type Tela =
  | { kind: "carregando" }
  | { kind: "indisponivel"; code: PortalErrorCode }
  | { kind: "precisa_login" }
  | { kind: "email_divergente" }
  | { kind: "valido"; convite: ManagerInvitation }
  | { kind: "expirado" }
  | { kind: "utilizado" }
  | { kind: "revogado" };

function Moldura({
  titulo,
  children,
}: {
  titulo: string;
  children: React.ReactNode;
}) {
  return (
    <>
      <Header />
      <main className="mx-auto max-w-lg px-4 pb-24 pt-14 text-center">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Convite · Portal BDFlow
        </p>
        <h1 className="mt-3 text-3xl">{titulo}</h1>
        {children}
      </main>
    </>
  );
}

function Cartao({
  texto,
  tom = "neutro",
  acao,
}: {
  texto: string;
  tom?: "neutro" | "alerta" | "erro";
  acao?: React.ReactNode;
}) {
  const cores =
    tom === "erro"
      ? "border-magenta/30 bg-magenta/10"
      : tom === "alerta"
        ? "border-amarelo bg-amarelo/15"
        : "border-borda bg-papel2/60";
  return (
    <div className={`mt-6 rounded-3xl border-2 ${cores} p-6`}>
      <p className="text-sm text-tinta/80">{texto}</p>
      {acao && <div className="mt-5">{acao}</div>}
    </div>
  );
}

export default function PortalConvite() {
  const { token } = useParams();
  const location = useLocation();
  const { session, carregando } = usePortalSiteAuth();
  const [tela, setTela] = useState<Tela>({ kind: "carregando" });

  // Destino completo do convite (pathname + search), preservado integralmente.
  const alvoConvite = location.pathname + location.search;
  // URLSearchParams cuida da codificação — evita dupla codificação manual.
  const loginEntrar = `/portal/login?${new URLSearchParams({ next: alvoConvite }).toString()}`;
  const loginTrocarConta = `/portal/login?${new URLSearchParams({
    next: alvoConvite,
    switch_account: "1",
  }).toString()}`;

  useEffect(() => {
    let ativo = true;
    if (carregando) return;
    if (!token) {
      setTela({ kind: "indisponivel", code: "INVITATION_REVOKED" });
      return;
    }

    // CONSULTA somente-leitura. Nunca consome o convite.
    getPublicInvitation(token).then((r) => {
      if (!ativo) return;

      if (!r.ok) {
        if (r.error.code === "INVITATION_EXPIRED") setTela({ kind: "expirado" });
        else if (r.error.code === "INVITATION_USED") setTela({ kind: "utilizado" });
        else if (r.error.code === "INVITATION_REVOKED") setTela({ kind: "revogado" });
        // Divergência de e-mail: só ocorre APÓS validação segura do token pelo
        // backend. Nunca revela o e-mail esperado, a empresa ou o destinatário.
        else if (r.error.code === "INVITATION_EMAIL_MISMATCH")
          setTela({ kind: "email_divergente" });
        else setTela({ kind: "indisponivel", code: r.error.code });
        return;
      }

      const estado = invitationVisualState(r.data);
      if (estado === "expired") return setTela({ kind: "expirado" });
      if (estado === "used") return setTela({ kind: "utilizado" });
      if (estado === "revoked") return setTela({ kind: "revogado" });

      // Convite válido: exige conta autenticada para prosseguir.
      if (!session) return setTela({ kind: "precisa_login" });
      setTela({ kind: "valido", convite: r.data });
    });

    return () => {
      ativo = false;
    };
  }, [token, session, carregando]);

  if (tela.kind === "carregando") {
    return (
      <Moldura titulo="Verificando convite">
        <div className="mt-10 flex justify-center">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-papel2 border-t-magenta" />
        </div>
      </Moldura>
    );
  }

  if (tela.kind === "indisponivel") {
    return (
      <Moldura titulo="Convite indisponível">
        <Cartao
          tom="alerta"
          texto={`${PORTAL_ERROR_LABEL[tela.code]} Nenhum dado do convite é exibido antes da verificação segura pelo servidor. Abrir este link não o consome — se ele ainda for válido, poderá ser usado quando a função for ativada.`}
          acao={
            <Link to="/" className="btn-secondary">
              Ir para o início
            </Link>
          }
        />
      </Moldura>
    );
  }

  if (tela.kind === "expirado") {
    return (
      <Moldura titulo="Convite expirado">
        <Cartao
          tom="alerta"
          texto={`Este convite não foi utilizado e perdeu a validade de ${INVITATION_TTL_HOURS} horas. Peça um novo link ao responsável principal da empresa.`}
        />
      </Moldura>
    );
  }

  if (tela.kind === "utilizado") {
    return (
      <Moldura titulo="Convite já utilizado">
        <Cartao texto="Este convite já foi usado para criar um acesso. Cada link é de uso único." />
      </Moldura>
    );
  }

  if (tela.kind === "revogado") {
    return (
      <Moldura titulo="Convite indisponível">
        <Cartao
          tom="erro"
          texto="Este convite não está mais disponível. Fale com o responsável principal da empresa."
        />
      </Moldura>
    );
  }

  if (tela.kind === "precisa_login") {
    return (
      <Moldura titulo="Entre para continuar">
        <Cartao
          texto="Para aceitar o convite, entre com a sua conta. Abrir ou fechar esta página não consome o convite."
          acao={
            <Link to={loginEntrar} className="btn-primary">
              Entrar
            </Link>
          }
        />
      </Moldura>
    );
  }

  if (tela.kind === "email_divergente") {
    return (
      <Moldura titulo="Conta diferente do destinatário">
        <Cartao
          tom="alerta"
          texto="Este convite foi protegido por e-mail e a conta autenticada não corresponde ao destinatário. Entre com a conta correta para continuar."
          acao={
            <Link to={loginTrocarConta} className="btn-secondary">
              Trocar de conta
            </Link>
          }
        />
      </Moldura>
    );
  }

  // Convite válido e autenticado: o cadastro real depende do backend.
  return (
    <Moldura titulo="Aceitar convite">
      <Cartao
        texto="O cadastro do gerente (nome, CPF, telefone e aceites aplicáveis) será concluído pelo servidor em uma única operação. Você não escolhe filial no aceite: a filial é selecionada a cada validação."
      />
      <Cartao
        tom="alerta"
        texto={PORTAL_ERROR_LABEL.BACKEND_NOT_AVAILABLE}
      />
    </Moldura>
  );
}
