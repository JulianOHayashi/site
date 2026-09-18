import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import { useAuth } from "../../hooks/useAuth";
import { emailValido } from "../../lib/onboardingValidacao";

/**
 * /parceiros/convite — aceite de convite de gerente.
 *
 * POR QUE ESTA PÁGINA EXISTE
 * O e-mail `manager_invite` aponta para esta rota. Sem ela, o link chegava a
 * uma rota inexistente e o convite era inaceitável na prática, embora a RPC
 * canônica `accept_manager_invite` já existisse e funcionasse.
 *
 * AUTORIDADE
 * Chama EXCLUSIVAMENTE `accept_manager_invite(p_token)`. Nenhuma RPC
 * substituta, nenhuma escrita direta em tabela de membros. O banco decide
 * validade do token, expiração, empresa ativa, correspondência de e-mail e
 * duplicidade de vínculo.
 *
 * SEGREDO NA URL
 * O token chega necessariamente na query string. Ele é capturado para estado
 * de componente e REMOVIDO da URL visível na primeira renderização, para não
 * ficar no histórico do navegador, no título da aba nem em um eventual
 * `Referer`. Nunca vai para localStorage, log ou telemetria.
 *
 * Recarregar a página depois disso exige reabrir o link do e-mail. É aceitável
 * e mais seguro do que persistir o segredo.
 *
 * FRONTEIRA DE REDIRECT
 * Esta página NÃO usa o `next` do PortalLogin. A proteção existente restringe
 * destinos a `/portal`, e afrouxá-la só para caber `/parceiros/convite` seria
 * ampliar uma fronteira de segurança por conveniência. O fluxo de
 * autenticação é local e autocontido.
 */

type Estado =
  | { fase: "carregando" }
  | { fase: "sem_token" }
  | { fase: "precisa_login" }
  | { fase: "enviando" }
  | { fase: "sucesso" }
  | { fase: "erro"; motivo: string };

const MENSAGENS: Record<string, string> = {
  not_authenticated: "Entre com o e-mail que recebeu o convite para continuar.",
  invalid_token: "Este convite não é válido ou já foi utilizado.",
  expired: "Este convite expirou. Peça um novo ao responsável pela empresa.",
  company_inactive: "A empresa deste convite não está ativa no momento.",
  email_mismatch:
    "O e-mail desta conta não é o mesmo que recebeu o convite. Entre com o e-mail convidado.",
  already_member: "Você já faz parte desta empresa.",
  access_revoked: "Este acesso de manager foi revogado definitivamente e não pode ser reativado por este convite.",
  not_configured: "Serviço em configuração.",
  rpc_error: "Não foi possível concluir. Tente novamente.",
};

function mensagemDe(motivo: string): string {
  return MENSAGENS[motivo] ?? MENSAGENS.rpc_error;
}

export default function AceitarConviteManager() {
  const [params, setParams] = useSearchParams();
  const { session, carregando } = useAuth();

  // O token vive APENAS aqui. Nunca em storage, nunca em log.
  const tokenRef = useRef<string | null>(null);
  const [temToken, setTemToken] = useState(false);
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erroLogin, setErroLogin] = useState<string | null>(null);
  const jaTentou = useRef(false);

  // Captura o token e o remove da URL visível o quanto antes.
  useEffect(() => {
    if (tokenRef.current !== null) return;
    const bruto = params.get("token");
    if (bruto && bruto.trim().length > 0) {
      tokenRef.current = bruto;
      setTemToken(true);
      const limpos = new URLSearchParams(params);
      limpos.delete("token");
      setParams(limpos, { replace: true });
    } else {
      setEstado({ fase: "sem_token" });
    }
  }, [params, setParams]);

  const aceitar = useCallback(async () => {
    const token = tokenRef.current;
    if (!supabase || !token) return;
    setEstado({ fase: "enviando" });

    const { data, error } = await supabase.rpc("accept_manager_invite", {
      p_token: token,
    });

    if (error) {
      // Mensagem crua do banco nunca chega à tela, e o token não é anexado
      // a nenhum diagnóstico.
      setEstado({ fase: "erro", motivo: "rpc_error" });
      return;
    }
    const r = data as { ok?: boolean; reason?: string } | null;
    if (!r || typeof r !== "object") {
      setEstado({ fase: "erro", motivo: "rpc_error" });
      return;
    }
    if (r.ok === true) {
      tokenRef.current = null; // consumido; não precisa mais existir
      setEstado({ fase: "sucesso" });
      return;
    }
    setEstado({ fase: "erro", motivo: r.reason ?? "rpc_error" });
  }, []);

  // Só chama a RPC quando há sessão. Sem sessão, nem tenta.
  useEffect(() => {
    if (!supabaseConfigurado) {
      setEstado({ fase: "erro", motivo: "not_configured" });
      return;
    }
    if (!temToken || carregando) return;
    if (!session) {
      setEstado({ fase: "precisa_login" });
      return;
    }
    if (jaTentou.current) return;
    jaTentou.current = true;
    void aceitar();
  }, [temToken, carregando, session, aceitar]);

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase) return;
    if (!emailValido(email)) {
      setErroLogin("Informe um e-mail válido.");
      return;
    }
    if (senha.length < 8) {
      setErroLogin("Informe sua senha.");
      return;
    }
    setErroLogin(null);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password: senha,
    });
    if (error) {
      // Não revela se o e-mail existe nem quem foi convidado.
      setErroLogin("Não foi possível entrar com esses dados.");
      return;
    }
    // A sessão nova dispara o efeito acima, que chama a mesma RPC com o
    // MESMO token capturado.
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        {estado.fase === "carregando" || estado.fase === "enviando" ? (
          <p className="text-center text-sm text-tinta/60" role="status">
            {estado.fase === "enviando" ? "Ativando seu acesso..." : "Verificando convite..."}
          </p>
        ) : null}

        {estado.fase === "sem_token" ? (
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Convite não encontrado</h1>
            <p className="mt-4 text-sm text-tinta/70" role="alert">
              Abra o link exatamente como recebeu no e-mail do convite.
            </p>
          </div>
        ) : null}

        {estado.fase === "precisa_login" ? (
          <form onSubmit={entrar} noValidate className="card space-y-5 p-6">
            <h1 className="text-2xl font-bold">Aceitar convite</h1>
            <p className="text-sm text-tinta/60">
              Entre com o e-mail que recebeu o convite para ativar seu acesso de
              gerente.
            </p>
            <div>
              <label htmlFor="email" className="mb-1.5 block text-sm font-semibold">
                E-mail
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full rounded-xl border border-borda px-4 py-2.5"
              />
            </div>
            <div>
              <label htmlFor="senha" className="mb-1.5 block text-sm font-semibold">
                Senha
              </label>
              <input
                id="senha"
                type="password"
                value={senha}
                onChange={(e) => setSenha(e.target.value)}
                className="w-full rounded-xl border border-borda px-4 py-2.5"
              />
            </div>
            {erroLogin ? (
              <p className="text-sm text-red-700" role="alert">
                {erroLogin}
              </p>
            ) : null}
            <button type="submit" className="btn-primary w-full">
              Entrar e aceitar
            </button>
          </form>
        ) : null}

        {estado.fase === "sucesso" ? (
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Acesso de gerente ativado</h1>
            <p className="mt-4 text-sm text-tinta/70" role="status">
              Seu vínculo foi confirmado. As permissões são definidas pela
              empresa; acesso financeiro não é concedido automaticamente.
            </p>
            <Link to="/portal/dashboard" className="btn-primary mt-6 inline-block">
              Ir para o Portal BDFlow
            </Link>
          </div>
        ) : null}

        {estado.fase === "erro" ? (
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Não foi possível aceitar</h1>
            <p className="mt-4 text-sm text-tinta/70" role="alert">
              {mensagemDe(estado.motivo)}
            </p>
            {estado.motivo === "email_mismatch" ? (
              <p className="mt-3 text-sm text-tinta/60">
                Saia da conta atual e entre com o e-mail convidado.
              </p>
            ) : null}
            <Link to="/parceiros" className="btn-secondary mt-6 inline-block">
              Voltar
            </Link>
          </div>
        ) : null}
      </main>
    </>
  );
}
