import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { supabase, supabaseConfigurado } from "../../lib/supabase";
import {
  confirmarEmail,
  vincularContaProvisoria,
  mensagemDeMotivo,
} from "../../services/partnerApplicationService";
import { emailValido } from "../../lib/onboardingValidacao";

/**
 * /parceiros/confirmar — confirma o e-mail pré-Auth e ativa o acesso
 * provisório.
 *
 * Sequência:
 *   1. confirma o token (uso único, expirável, idempotente no efeito);
 *   2. o backend devolve um claim_token de curta duração;
 *   3. o usuário define a senha (signUp no Auth);
 *   4. claim vincula a conta à solicitação — a autoridade é auth.uid(),
 *      nenhum identificador de usuário é enviado pelo navegador.
 */
type Etapa = "verificando" | "definir_senha" | "concluido" | "erro";

export default function ConfirmarEmail() {
  const [params] = useSearchParams();
  const [etapa, setEtapa] = useState<Etapa>("verificando");
  const [mensagem, setMensagem] = useState<string>("");
  const [claimToken, setClaimToken] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    let ativo = true;
    const token = params.get("token");

    (async () => {
      if (!supabaseConfigurado) {
        if (ativo) { setEtapa("erro"); setMensagem("Serviço em configuração."); }
        return;
      }
      if (!token) {
        if (ativo) { setEtapa("erro"); setMensagem("Link inválido."); }
        return;
      }
      const r = await confirmarEmail(token);
      if (!ativo) return;
      if (!r.ok) {
        setEtapa("erro");
        setMensagem(mensagemDeMotivo(r.motivo));
        return;
      }
      if (r.dados.already_confirmed || !r.dados.claim_token) {
        setEtapa("concluido");
        setMensagem("Seu e-mail já estava confirmado.");
        return;
      }
      setClaimToken(r.dados.claim_token);
      setEtapa("definir_senha");
    })();

    return () => { ativo = false; };
  }, [params]);

  const criarAcesso = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supabase || !claimToken) return;
    if (!emailValido(email)) { setMensagem("Informe um e-mail válido."); return; }
    if (senha.length < 8) { setMensagem("A senha precisa ter ao menos 8 caracteres."); return; }

    setEnviando(true);
    setMensagem("");
    const { error } = await supabase.auth.signUp({ email: email.trim().toLowerCase(), password: senha });
    if (error) {
      setEnviando(false);
      setMensagem("Não foi possível criar o acesso. Verifique o e-mail informado.");
      return;
    }
    const r = await vincularContaProvisoria(claimToken);
    setEnviando(false);
    if (!r.ok) { setMensagem(mensagemDeMotivo(r.motivo)); return; }
    setEtapa("concluido");
    setMensagem("Acesso provisório criado.");
  };

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
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Não foi possível confirmar</h1>
            <p className="mt-4 text-sm text-tinta/70" role="alert">{mensagem}</p>
            <Link to="/parceiros/cadastro" className="btn-primary mt-6 inline-block">
              Voltar ao cadastro
            </Link>
          </div>
        ) : null}

        {etapa === "definir_senha" ? (
          <form onSubmit={criarAcesso} noValidate className="card space-y-5 p-6">
            <h1 className="text-2xl font-bold">Crie seu acesso provisório</h1>
            <p className="text-sm text-tinta/60">
              O acesso provisório serve para acompanhar a análise, responder
              correções e enviar documentos. Ele não dá acesso ao portal de
              parceiro aprovado.
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
              {enviando ? "Criando..." : "Criar acesso"}
            </button>
          </form>
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
