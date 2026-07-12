import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../components/Header";
import { formatarCNPJ, validarCNPJ } from "../lib/cnpj";
import { supabase, supabaseConfigurado } from "../lib/supabase";
import { useAuth } from "../hooks/useAuth";

/**
 * ÁREA DE PARCEIROS — login e cadastro.
 *
 * - Cadastro: nome da empresa + CNPJ (validação real de dígitos)
 *   + e-mail + senha. Os dados da empresa vão em user_metadata e
 *   viram um registro em `profiles` no primeiro acesso ao painel
 *   (isso conecta o parceiro ao desconto fidelidade automaticamente).
 * - Login: e-mail + senha → /parceiros/painel.
 * - Requer Supabase conectado (Auth por e-mail habilitado). Em modo
 *   demonstração os formulários ficam desativados com aviso.
 */

type Aba = "entrar" | "cadastrar";

export default function Parceiros() {
  const navigate = useNavigate();
  const { session, carregando } = useAuth();
  const [aba, setAba] = useState<Aba>("entrar");

  // campos
  const [empresa, setEmpresa] = useState("");
  const [cnpj, setCnpj] = useState("");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  const cnpjValido = validarCNPJ(cnpj);

  // Já logado? Vai direto ao painel.
  useEffect(() => {
    if (!carregando && session) navigate("/parceiros/painel");
  }, [carregando, session, navigate]);

  const entrar = async () => {
    if (!supabase) return;
    setErro(null);
    setEnviando(true);
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password: senha,
    });
    setEnviando(false);
    if (error) {
      setErro(
        error.message.includes("Invalid login")
          ? "E-mail ou senha incorretos."
          : "Não foi possível entrar. Tente novamente."
      );
      return;
    }
    navigate("/parceiros/painel");
  };

  const cadastrar = async () => {
    if (!supabase) return;
    setErro(null);
    if (!empresa.trim()) return setErro("Informe o nome da empresa.");
    if (!cnpjValido) return setErro("CNPJ inválido. Confira os números.");
    if (senha.length < 6)
      return setErro("A senha precisa de pelo menos 6 caracteres.");

    setEnviando(true);
    const { data, error } = await supabase.auth.signUp({
      email,
      password: senha,
      options: {
        data: { nome_empresa: empresa.trim(), cnpj },
      },
    });
    setEnviando(false);

    if (error) {
      setErro(
        error.message.includes("already registered")
          ? "Este e-mail já tem cadastro. Use a aba Entrar."
          : "Não foi possível cadastrar. Tente novamente."
      );
      return;
    }

    if (data.session) {
      navigate("/parceiros/painel");
    } else {
      // projeto com confirmação de e-mail ligada
      setAviso(
        "Cadastro criado! Enviamos um link de confirmação para o seu e-mail — confirme e depois entre por aqui."
      );
      setAba("entrar");
    }
  };

  const enviar = (e: React.FormEvent) => {
    e.preventDefault();
    if (aba === "entrar") entrar();
    else cadastrar();
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">
        <h1 className="text-center text-3xl sm:text-4xl">
          Área de parceiros
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-ciano" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          {/* ⚠️ TEXTO PROVISÓRIO — A DEFINIR */}
          Empresas e anunciantes: entre para acompanhar pedidos, descontos e
          materiais.
        </p>

        {!supabaseConfigurado && (
          <div className="mt-6 rounded-2xl bg-amarelo/25 p-4 text-center text-sm">
            Modo demonstração — o login real será ativado quando o Supabase
            estiver conectado (Auth por e-mail).
          </div>
        )}

        {/* abas */}
        <div className="mt-8 grid grid-cols-2 rounded-2xl border border-borda bg-white p-1">
          {(["entrar", "cadastrar"] as Aba[]).map((a) => (
            <button
              key={a}
              onClick={() => {
                setAba(a);
                setErro(null);
              }}
              className={`rounded-xl py-2.5 text-sm font-semibold capitalize transition ${
                aba === a ? "bg-tinta text-white" : "text-tinta/60 hover:text-tinta"
              }`}
            >
              {a}
            </button>
          ))}
        </div>

        {aviso && (
          <div className="mt-4 rounded-2xl border-2 border-green-200 bg-green-50 p-4 text-sm">
            ✅ {aviso}
          </div>
        )}

        {/* formulário */}
        <form onSubmit={enviar} className="card mt-4 space-y-4 p-6">
          {aba === "cadastrar" && (
            <>
              <div>
                <label htmlFor="p-empresa" className="mb-1.5 block text-sm font-semibold">
                  Nome da empresa
                </label>
                <input
                  id="p-empresa"
                  value={empresa}
                  onChange={(e) => setEmpresa(e.target.value)}
                  className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
                />
              </div>
              <div>
                <label htmlFor="p-cnpj" className="mb-1.5 block text-sm font-semibold">
                  CNPJ
                </label>
                <input
                  id="p-cnpj"
                  inputMode="numeric"
                  value={cnpj}
                  onChange={(e) => setCnpj(formatarCNPJ(e.target.value))}
                  placeholder="00.000.000/0000-00"
                  className={`w-full rounded-xl border px-4 py-3 outline-none transition ${
                    cnpj && !cnpjValido
                      ? "border-magenta"
                      : cnpjValido
                        ? "border-green-500"
                        : "border-borda focus:border-ciano"
                  }`}
                />
                {cnpjValido && (
                  <p className="mt-1 text-xs font-medium text-green-600">
                    CNPJ válido ✓ — seu desconto fidelidade fica vinculado a ele
                  </p>
                )}
              </div>
            </>
          )}

          <div>
            <label htmlFor="p-email" className="mb-1.5 block text-sm font-semibold">
              E-mail
            </label>
            <input
              id="p-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
            />
          </div>

          <div>
            <label htmlFor="p-senha" className="mb-1.5 block text-sm font-semibold">
              Senha
            </label>
            <input
              id="p-senha"
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              minLength={6}
              className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
            />
            {aba === "cadastrar" && (
              <p className="mt-1 text-xs text-tinta/50">Mínimo de 6 caracteres.</p>
            )}
          </div>

          {erro && (
            <p className="rounded-xl bg-magenta/10 px-4 py-2.5 text-sm font-medium text-magenta">
              {erro}
            </p>
          )}

          <button
            type="submit"
            disabled={!supabaseConfigurado || enviando}
            className="btn-primary w-full"
          >
            {enviando
              ? "Aguarde..."
              : aba === "entrar"
                ? "Entrar"
                : "Criar cadastro"}
          </button>
        </form>

        <p className="mt-6 text-center text-xs text-tinta/40">
          Ao se cadastrar você concorda com os Termos de uso e a Política de
          privacidade (em breve).
        </p>
        <p className="mt-2 text-center text-sm">
          <Link to="/" className="font-medium text-ciano hover:underline">
            ← Voltar ao início
          </Link>
        </p>
      </main>
    </>
  );
}
