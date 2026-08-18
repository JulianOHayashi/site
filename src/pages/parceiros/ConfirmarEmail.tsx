import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import {
  confirmarEmail,
  vincularContaProvisoria,
  mensagemDeMotivo,
} from "../../services/partnerApplicationService";
import { emailValido } from "../../lib/onboardingValidacao";
import RecuperarAcesso from "./RecuperarAcesso";

/**
 * /parceiros/confirmar — confirma o e-mail pré-Auth e ativa o acesso
 * provisório.
 *
 * Aceita dois parâmetros, correspondentes às duas etapas do fluxo:
 *   ?token=<verificação>  confirma o e-mail e devolve o claim em trânsito
 *   ?claim=<reivindicação> chega por e-mail quando a resposta acima se perde
 *
 * DEDUPLICAÇÃO (StrictMode): em desenvolvimento o React monta, desmonta e
 * remonta, executando efeitos duas vezes. Sem trava, o segundo disparo
 * consumiria o mesmo token e a tela mostraria "link já utilizado" para um
 * usuário legítimo. A trava é um ref de módulo por VALOR de token, e não
 * um flag por montagem — um ref de instância não sobrevive à remontagem.
 * Removê-la desligando o StrictMode seria esconder o problema, não resolvê-lo.
 */

/** Tokens já processados nesta sessão de página, com a promessa em curso. */
const emProcessamento = new Map<string, Promise<unknown>>();

type Etapa = "verificando" | "definir_senha" | "concluido" | "erro";

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
  const montado = useRef(true);

  useEffect(() => {
    montado.current = true;
    return () => {
      montado.current = false;
    };
  }, []);

  const confirmar = useCallback(async (valor: string) => {
    // Uma única chamada por token, ainda que o efeito rode duas vezes.
    let promessa = emProcessamento.get(valor);
    if (!promessa) {
      promessa = confirmarEmail(valor);
      emProcessamento.set(valor, promessa);
    }
    return (await promessa) as Awaited<ReturnType<typeof confirmarEmail>>;
  }, []);

  useEffect(() => {
    let ativo = true;

    (async () => {
      if (!supabaseConfigurado) {
        if (ativo) {
          setEtapa("erro");
          setMotivo("not_configured");
          setMensagem(mensagemDeMotivo("not_configured"));
        }
        return;
      }

      // Caminho do link de reivindicação recebido por e-mail.
      if (claimDaUrl) {
        if (ativo) setEtapa("definir_senha");
        return;
      }

      if (!token) {
        if (ativo) {
          setEtapa("erro");
          setMotivo("invalid_token");
          setMensagem(mensagemDeMotivo("invalid_token"));
        }
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
      setClaimToken(r.dados.claim_token);
      setEtapa("definir_senha");
    })();

    return () => {
      ativo = false;
    };
  }, [token, claimDaUrl, confirmar]);

  const criarAcesso = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || !claimToken || enviando) return;
    if (!emailValido(email)) {
      setMensagem("Informe um e-mail válido.");
      return;
    }
    if (senha.length < 8) {
      setMensagem("A senha precisa ter ao menos 8 caracteres.");
      return;
    }

    setEnviando(true);
    setMensagem("");
    const normalizado = email.trim().toLowerCase();

    const cadastro = await supabase.auth.signUp({ email: normalizado, password: senha });
    if (cadastro.error) {
      // Pode já existir: tentamos entrar com as mesmas credenciais.
      const login = await supabase.auth.signInWithPassword({ email: normalizado, password: senha });
      if (login.error) {
        setEnviando(false);
        setMensagem("Não foi possível criar ou acessar a conta com esses dados.");
        return;
      }
    }

    const r = await vincularContaProvisoria(claimToken);
    setEnviando(false);
    if (!r.ok) {
      setMotivo(r.motivo);
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }
    setEtapa("concluido");
    setMensagem("Acesso provisório criado.");
  };

  // Estados em que oferecer recuperação faz sentido.
  const ofereceRecuperacao =
    motivo === "token_expired" ||
    motivo === "token_invalidated" ||
    motivo === "token_already_used" ||
    motivo === "invalid_token" ||
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
              <p className="mt-4 text-sm text-tinta/70" role="alert">
                {mensagem}
              </p>
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
            {mensagem ? (
              <p className="text-sm text-red-700" role="alert">
                {mensagem}
              </p>
            ) : null}
            <button type="submit" disabled={enviando} className="btn-primary w-full">
              {enviando ? "Criando..." : "Criar acesso"}
            </button>
          </form>
        ) : null}

        {etapa === "concluido" ? (
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Tudo certo</h1>
            <p className="mt-4 text-sm text-tinta/70" role="status">
              {mensagem}
            </p>
            <Link to="/parceiros/solicitacao" className="btn-primary mt-6 inline-block">
              Acompanhar solicitação
            </Link>
          </div>
        ) : null}
      </main>
    </>
  );
}
