import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import {
  confirmarEmail,
  vincularContaProvisoria,
  obterTermosContaProvisoria,
  registrarAceiteConta,
  mensagemDeMotivo,
  type TermosEstado,
} from "../../services/partnerApplicationService";
import { emailValido } from "../../lib/onboardingValidacao";
import RecuperarAcesso from "./RecuperarAcesso";

/**
 * /parceiros/confirmar — confirma o e-mail pré-Auth e ativa o acesso
 * provisório.
 *
 *   ?token=<verificação>   confirma o e-mail e devolve o claim em trânsito
 *   ?claim=<reivindicação> chega por e-mail quando a resposta acima se perde
 *
 * DUAS DISTINÇÕES QUE O DESENHO ANTERIOR NÃO FAZIA
 *
 * 1. CONTA SUPABASE AUTH CRIADA ≠ CONTA PROVISÓRIA ATIVADA.
 *    Entre uma e outra existe a etapa jurídica: o usuário precisa aceitar
 *    explicitamente os documentos vigentes da conta provisória. O claim
 *    apenas VERIFICA esses aceites; ele nunca os cria.
 *
 * 2. signUp pode devolver usuário SEM sessão (quando a confirmação de e-mail
 *    está ativa no Auth). A configuração remota não foi provada equivalente à
 *    local, então tratamos esse caso explicitamente: nada de aceite, nada de
 *    claim, nada de sucesso — só instrução para entrar depois. O claim é
 *    retomado pelo link de recuperação, sem guardar segredo no navegador.
 *
 * DEDUPLICAÇÃO (StrictMode): trava de módulo por VALOR de token. Um ref de
 * instância não sobreviveria à remontagem que o StrictMode provoca.
 */

const emProcessamento = new Map<string, Promise<unknown>>();

type Etapa =
  | "verificando"
  | "definir_senha"
  | "aguardando_login"
  | "aceite_termos"
  | "concluido"
  | "erro";

export default function ConfirmarEmail() {
  const [params] = useSearchParams();
  const token = params.get("token");
  const claimDaUrl = params.get("claim");

  const [etapa, setEtapa] = useState<Etapa>("verificando");
  const [mensagem, setMensagem] = useState<string>("");
  const [motivo, setMotivo] = useState<string | null>(null);
  const [claimToken, setClaimToken] = useState<string | null>(claimDaUrl);
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [termos, setTermos] = useState<TermosEstado>({ tipo: "carregando" });
  const [aceitos, setAceitos] = useState<Set<string>>(new Set());
  const claimRef = useRef<string | null>(claimDaUrl);

  const confirmar = useCallback(async (valor: string) => {
    let promessa = emProcessamento.get(valor);
    if (!promessa) {
      promessa = confirmarEmail(valor);
      emProcessamento.set(valor, promessa);
    }
    return (await promessa) as Awaited<ReturnType<typeof confirmarEmail>>;
  }, []);

  const carregarTermos = useCallback(async () => {
    setTermos({ tipo: "carregando" });
    // Recarregar SEMPRE descarta o aceite anterior.
    setAceitos(new Set());
    setTermos(await obterTermosContaProvisoria());
  }, []);

  useEffect(() => {
    let ativo = true;

    (async () => {
      if (!supabaseConfigurado) {
        if (ativo) { setEtapa("erro"); setMotivo("not_configured"); setMensagem(mensagemDeMotivo("not_configured")); }
        return;
      }
      if (claimDaUrl) {
        if (ativo) setEtapa("definir_senha");
        return;
      }
      if (!token) {
        if (ativo) { setEtapa("erro"); setMotivo("invalid_token"); setMensagem(mensagemDeMotivo("invalid_token")); }
        return;
      }

      const r = await confirmar(token);
      if (!ativo) return;

      if (!r.ok) {
        setEtapa("erro");
        setMotivo(r.motivo);
        setMensagem(mensagemDeMotivo(r.motivo));
        return;
      }
      if (!r.dados.claim_token) {
        setEtapa("concluido");
        setMensagem("Seu e-mail já estava confirmado.");
        return;
      }
      claimRef.current = r.dados.claim_token;
      setClaimToken(r.dados.claim_token);
      setEtapa("definir_senha");
    })();

    return () => { ativo = false; };
  }, [token, claimDaUrl, confirmar]);

  /** Cria ou entra na conta Auth. Não conclui nada por conta própria. */
  const criarAcesso = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || !claimToken || enviando) return;
    if (!emailValido(email)) { setMensagem("Informe um e-mail válido."); return; }
    if (senha.length < 8) { setMensagem("A senha precisa ter ao menos 8 caracteres."); return; }

    setEnviando(true);
    setMensagem("");
    const normalizado = email.trim().toLowerCase();

    const cadastro = await supabase.auth.signUp({ email: normalizado, password: senha });

    let temSessao = Boolean(cadastro.data?.session);
    if (cadastro.error) {
      // Conta possivelmente já existente: tentamos entrar.
      const login = await supabase.auth.signInWithPassword({ email: normalizado, password: senha });
      if (login.error) {
        setEnviando(false);
        setMensagem("Não foi possível criar ou acessar a conta com esses dados.");
        return;
      }
      temSessao = Boolean(login.data?.session);
    }

    setEnviando(false);

    if (!temSessao) {
      // signUp criou o usuário mas o Auth exige confirmação de e-mail: NÃO
      // seguimos para aceite nem para claim, e não fingimos sucesso.
      setEtapa("aguardando_login");
      return;
    }

    setEtapa("aceite_termos");
    void carregarTermos();
  };

  const alternarAceite = (id: string) =>
    setAceitos((atual) => {
      const proximo = new Set(atual);
      if (proximo.has(id)) proximo.delete(id);
      else proximo.add(id);
      return proximo;
    });

  const documentos = termos.tipo === "carregado" ? termos.documentos : [];
  const todosAceitos =
    documentos.length > 0 && documentos.every((d) => aceitos.has(d.legal_document_id));

  /** Registra cada aceite e, só então, tenta o claim. */
  const aceitarEConcluir = async () => {
    if (enviando || termos.tipo !== "carregado" || !todosAceitos) return;
    const claim = claimRef.current ?? claimToken;
    if (!claim) { setMensagem(mensagemDeMotivo("invalid_token")); return; }

    setEnviando(true);
    setMensagem("");

    for (const doc of documentos) {
      // O id vai junto: é o vínculo com o texto que o usuário realmente viu.
      const r = await registrarAceiteConta(doc.doc_type, doc.legal_document_id);
      if (!r.ok) {
        setEnviando(false);
        setMensagem(mensagemDeMotivo(r.motivo));
        if (r.motivo === "acceptance_stale") {
          // Os termos mudaram entre o clique e a chamada: recarrega e exige
          // aceite explícito da nova versão.
          void carregarTermos();
        }
        return; // uma falha de aceite impede o claim
      }
    }

    const claimResp = await vincularContaProvisoria(claim);
    setEnviando(false);

    if (!claimResp.ok) {
      setMotivo(claimResp.motivo);
      setMensagem(mensagemDeMotivo(claimResp.motivo));
      if (claimResp.motivo === "provisional_terms_required") {
        void carregarTermos(); // documento mudou: exige novo aceite explícito
      }
      return;
    }
    setEtapa("concluido");
    setMensagem("Acesso provisório criado.");
  };

  const ofereceRecuperacao =
    motivo === "token_expired" || motivo === "token_invalidated" ||
    motivo === "token_already_used" || motivo === "invalid_token" ||
    motivo === "not_claimable";

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        {etapa === "verificando" ? (
          <p className="text-center text-sm text-tinta/60" role="status" aria-live="polite">
            Verificando seu link...
          </p>
        ) : null}

        {etapa === "erro" ? (
          <>
            <div className="card p-8 text-center">
              <h1 className="text-2xl font-bold">Não foi possível confirmar</h1>
              <p className="mt-4 text-sm text-tinta/70" role="alert">{mensagem}</p>
              <Link to="/parceiros/cadastro" className="btn-secondary mt-6 inline-block">
                Voltar ao cadastro
              </Link>
            </div>
            {ofereceRecuperacao ? <RecuperarAcesso compacto /> : null}
          </>
        ) : null}

        {etapa === "definir_senha" ? (
          <form onSubmit={criarAcesso} noValidate className="card space-y-5 p-6">
            <h1 className="text-2xl font-bold">Crie seu acesso provisório</h1>
            <p className="text-sm text-tinta/60">
              Use o mesmo e-mail informado no cadastro. O acesso provisório serve
              para acompanhar a análise, responder correções e enviar documentos;
              ele não dá acesso ao portal de parceiro aprovado.
            </p>
            <div>
              <label htmlFor="email" className="mb-1.5 block text-sm font-semibold">E-mail</label>
              <input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                     className="w-full rounded-xl border border-borda px-4 py-2.5" />
            </div>
            <div>
              <label htmlFor="senha" className="mb-1.5 block text-sm font-semibold">Senha</label>
              <input id="senha" type="password" value={senha} onChange={(e) => setSenha(e.target.value)}
                     className="w-full rounded-xl border border-borda px-4 py-2.5" />
            </div>
            {mensagem ? <p className="text-sm text-red-700" role="alert">{mensagem}</p> : null}
            <button type="submit" disabled={enviando} className="btn-primary w-full">
              {enviando ? "Criando..." : "Continuar"}
            </button>
          </form>
        ) : null}

        {etapa === "aguardando_login" ? (
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Confirme seu e-mail para continuar</h1>
            <p className="mt-4 text-sm text-tinta/70" role="status">
              Sua conta foi criada, mas ainda não está ativa. Verifique sua caixa
              de entrada, confirme o e-mail e faça login para concluir a ativação
              do acesso provisório.
            </p>
            <p className="mt-3 text-sm text-tinta/60">
              Se o link de ativação expirar, você pode pedir um novo abaixo.
            </p>
            <Link to="/parceiros" className="btn-primary mt-6 inline-block">
              Ir para o login
            </Link>
            <RecuperarAcesso compacto />
          </div>
        ) : null}

        {etapa === "aceite_termos" ? (
          <div className="card space-y-4 p-6">
            <h1 className="text-2xl font-bold">Termos da conta</h1>
            <p className="text-sm text-tinta/60">
              Para ativar o acesso provisório, leia e aceite os documentos abaixo.
            </p>

            {termos.tipo === "carregando" ? (
              <p className="text-sm text-tinta/60" role="status">Carregando os termos...</p>
            ) : null}

            {termos.tipo === "erro" ? (
              <div role="alert" className="rounded-xl bg-amarelo/25 p-4 text-sm">
                <p>{mensagemDeMotivo(termos.motivo)}</p>
                <button type="button" onClick={() => void carregarTermos()}
                        className="mt-3 rounded-xl border border-borda px-3 py-2 font-semibold">
                  Tentar novamente
                </button>
              </div>
            ) : null}

            {documentos.map((doc) => (
              <div key={doc.legal_document_id} className="rounded-2xl border border-borda p-4">
                <p className="font-semibold">{doc.title}</p>
                <p className="text-xs text-tinta/50">Versão {doc.version}</p>
                {doc.content_url ? (
                  <a href={doc.content_url} target="_blank" rel="noopener noreferrer"
                     className="mt-2 inline-block text-sm underline">Ler o documento</a>
                ) : null}
                {doc.content ? (
                  <p className="mt-2 max-h-40 overflow-auto text-sm text-tinta/70">{doc.content}</p>
                ) : null}
                <label className="mt-3 flex items-start gap-3 text-sm">
                  <input type="checkbox" checked={aceitos.has(doc.legal_document_id)}
                         onChange={() => alternarAceite(doc.legal_document_id)}
                         aria-label={`Aceito: ${doc.title}`} className="mt-1" />
                  <span>Li e aceito este documento.</span>
                </label>
              </div>
            ))}

            {mensagem ? <p className="text-sm text-red-700" role="alert">{mensagem}</p> : null}

            <button type="button" onClick={() => void aceitarEConcluir()}
                    disabled={enviando || termos.tipo !== "carregado" || !todosAceitos}
                    className="btn-primary w-full">
              {enviando ? "Ativando..." : "Aceitar e ativar acesso"}
            </button>
          </div>
        ) : null}

        {etapa === "concluido" ? (
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Tudo certo</h1>
            <p className="mt-4 text-sm text-tinta/70" role="status">{mensagem}</p>
            <Link to="/parceiros/solicitacao" className="btn-primary mt-6 inline-block">
              Acompanhar solicitação
            </Link>
          </div>
        ) : null}
      </main>
    </>
  );
}
