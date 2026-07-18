import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import Header from "../../components/Header";
import { supabase } from "../../lib/supabase";
import { usePortalSiteAuth } from "../../hooks/usePortalSiteAuth";
import { validarCNPJ, formatarCNPJ } from "../../lib/cnpj";
import { validarCPF, formatarCPF, somenteDigitos } from "../../lib/cpf";
import { formatarTelefone, validarTelefoneBr } from "../../lib/telefone";
import { CarregandoPortal } from "./portalUi";

/**
 * /portal/cadastro — cadastro inicial da empresa parceira.
 *
 * - Rota protegida pelo PortalGuard (Supabase do SITE apenas).
 * - Pré-verificação via RLS: se o usuário já possui vínculo de
 *   partner_owner (active/pending_admin_review/suspended), o
 *   formulário NÃO aparece; vínculo archived exige atendimento
 *   administrativo BDFlow.
 * - Envio EXCLUSIVAMENTE pela RPC create_my_partner_owner_registration
 *   (assinatura real conferida no SQL executado). Sem INSERT direto,
 *   sem user_id enviado — auth.uid() é lido pelo banco.
 */

type EstadoVinculo =
  | "verificando"
  | "sem_vinculo"
  | "ja_vinculado"
  | "arquivado";

const ERROS: Record<string, string> = {
  USUARIO_JA_POSSUI_EMPRESA_PARCEIRA:
    "Esta conta já está vinculada a uma empresa parceira.",
  CPF_JA_VINCULADO_A_EMPRESA_PARCEIRA:
    "Este CPF já está vinculado a uma empresa parceira. Entre em contato com a BDFlow caso precise de ajuda.",
  CNPJ_JA_CADASTRADO: "Este CNPJ já está cadastrado no Portal BDFlow.",
  AUTENTICACAO_OBRIGATORIA: "Sua sessão expirou. Entre novamente para continuar.",
  CPF_INVALIDO: "Informe um CPF válido.",
  CNPJ_INVALIDO: "Informe um CNPJ válido.",
  CADASTRO_DUPLICADO:
    "Não foi possível concluir porque já existe um cadastro relacionado a estes dados.",
};

function mensagemDoErro(mensagem: string | undefined): string {
  if (mensagem) {
    for (const codigo of Object.keys(ERROS)) {
      if (mensagem.includes(codigo)) return ERROS[codigo];
    }
  }
  return "Não foi possível concluir o cadastro. Tente novamente.";
}

export default function PortalCadastro() {
  const navigate = useNavigate();
  const { session } = usePortalSiteAuth(); // sessão garantida pelo PortalGuard

  const [vinculo, setVinculo] = useState<EstadoVinculo>("verificando");

  // Responsável principal
  const [nome, setNome] = useState("");
  const [cpf, setCpf] = useState("");
  const [telefone, setTelefone] = useState("");
  // Empresa parceira
  const [razaoSocial, setRazaoSocial] = useState("");
  const [nomeFantasia, setNomeFantasia] = useState("");
  const [cnpj, setCnpj] = useState("");
  const [telefoneEmpresa, setTelefoneEmpresa] = useState("");

  const [erros, setErros] = useState<Record<string, string>>({});
  const [erroEnvio, setErroEnvio] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [sucesso, setSucesso] = useState<{ partner_status: string } | null>(null);

  // ===== Pré-verificação no banco (RLS), não em estado local =====
  useEffect(() => {
    if (!supabase || !session) return;
    let ativo = true;

    supabase
      .from("site_partner_members")
      .select("id, status")
      .eq("user_id", session.user.id)
      .eq("role", "partner_owner")
      .then(({ data, error }) => {
        if (!ativo) return;
        if (error || !data) {
          // sem leitura confiável: por segurança não libera cadastro cego
          setVinculo("sem_vinculo");
          return;
        }
        const naoArquivado = data.find((m) => m.status !== "archived");
        if (naoArquivado) setVinculo("ja_vinculado");
        else if (data.length > 0) setVinculo("arquivado");
        else setVinculo("sem_vinculo");
      });

    return () => {
      ativo = false;
    };
  }, [session]);

  // ===== Validação auxiliar do frontend (autoridade final: banco) =====
  const validar = (): boolean => {
    const e: Record<string, string> = {};
    if (nome.trim().length < 5 || !nome.trim().includes(" "))
      e.nome = "Informe o nome completo.";
    if (!validarCPF(cpf)) e.cpf = "Informe um CPF válido.";
    if (!validarTelefoneBr(telefone))
      e.telefone = "Informe um telefone válido com DDD.";
    if (razaoSocial.trim().length < 3)
      e.razaoSocial = "Informe a razão social.";
    if (nomeFantasia.trim().length < 2)
      e.nomeFantasia = "Informe o nome fantasia.";
    if (!validarCNPJ(cnpj)) e.cnpj = "Informe um CNPJ válido.";
    if (telefoneEmpresa && !validarTelefoneBr(telefoneEmpresa))
      e.telefoneEmpresa = "Telefone da empresa inválido.";
    setErros(e);
    return Object.keys(e).length === 0;
  };

  // ===== Envio: RPC exclusiva, sem user_id, sem INSERT direto =====
  const enviar = async (ev: React.FormEvent) => {
    ev.preventDefault();
    if (enviando || !supabase) return; // anti duplo-clique
    setErroEnvio(null);
    if (!validar()) return;

    setEnviando(true);
    const { data, error } = await supabase.rpc(
      "create_my_partner_owner_registration",
      {
        p_full_name: nome.trim(),
        p_cpf: somenteDigitos(cpf),
        p_phone: somenteDigitos(telefone),
        p_legal_name: razaoSocial.trim(),
        p_trade_name: nomeFantasia.trim(),
        p_cnpj: somenteDigitos(cnpj),
        p_company_phone: telefoneEmpresa
          ? somenteDigitos(telefoneEmpresa)
          : null,
      }
    );
    setEnviando(false);

    if (error) {
      // erro seguro traduzido; sem retry automático, sem log de dados
      setErroEnvio(mensagemDoErro(error.message));
      return;
    }

    // limpa dados sensíveis do estado imediatamente
    setCpf("");
    setCnpj("");
    setTelefone("");
    setTelefoneEmpresa("");
    setSucesso({
      partner_status:
        (data as { partner_status?: string } | null)?.partner_status ??
        "pending",
    });
  };

  // ===== Estados de tela =====

  if (vinculo === "verificando") {
    return (
      <>
        <Header />
        <CarregandoPortal />
      </>
    );
  }

  if (vinculo === "ja_vinculado") {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14 text-center">
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
            Portal do parceiro BDFlow
          </p>
          <h1 className="mt-3 text-3xl">Cadastro da empresa</h1>
          <div className="mt-6 rounded-2xl border-2 border-ciano/30 bg-ciano/10 p-6">
            <p className="font-semibold">
              Esta conta já está vinculada a uma empresa parceira.
            </p>
            <p className="mt-2 text-sm text-tinta/70">
              Cada conta pode ser responsável por somente uma empresa no
              Portal BDFlow.
            </p>
          </div>
          <Link to="/portal/dashboard" className="btn-primary mt-6 inline-block">
            Ir para o painel
          </Link>
        </main>
      </>
    );
  }

  if (vinculo === "arquivado") {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14 text-center">
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
            Portal do parceiro BDFlow
          </p>
          <h1 className="mt-3 text-3xl">Cadastro da empresa</h1>
          <div className="mt-6 rounded-2xl border-2 border-amarelo bg-amarelo/15 p-6">
            <p className="font-semibold">
              Seu vínculo anterior foi arquivado.
            </p>
            <p className="mt-2 text-sm text-tinta/70">
              Um novo cadastro depende de atendimento administrativo da
              BDFlow. Entre em contato pelo canal oficial para continuar.
            </p>
          </div>
          <Link to="/portal/dashboard" className="btn-secondary mt-6 inline-block">
            Voltar ao painel
          </Link>
        </main>
      </>
    );
  }

  if (sucesso) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-md px-4 pb-24 pt-14 text-center">
          <p className="text-xs font-bold uppercase tracking-[0.3em] text-ciano">
            Portal do parceiro BDFlow
          </p>
          <h1 className="mt-3 text-3xl">Cadastro enviado</h1>
          <div className="mt-6 rounded-3xl border-2 border-[#0B7A3E]/30 bg-[#E8F7EE] p-8">
            <p className="text-2xl">✅</p>
            <p className="mt-2 font-bold text-[#0B7A3E]">
              Cadastro enviado com sucesso. Sua empresa está aguardando a
              análise da BDFlow.
            </p>
            <p className="mt-3 text-sm text-tinta/70">
              Você será o responsável principal desta empresa no Portal
              BDFlow.
            </p>
            <p className="mt-3 inline-block rounded-full bg-amarelo/30 px-3 py-1 text-xs font-semibold">
              Status: {sucesso.partner_status === "pending"
                ? "Aguardando análise"
                : sucesso.partner_status}
            </p>
          </div>
          <Link to="/portal/dashboard" className="btn-primary mt-6 inline-block">
            Ir para o painel
          </Link>
        </main>
      </>
    );
  }

  // ===== Formulário =====
  const campo =
    "w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano";
  const rotulo = "mb-1.5 block text-sm font-semibold";
  const erroCss = "mt-1 text-xs font-medium text-magenta";

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-12">
        <p className="text-center text-xs font-bold uppercase tracking-[0.3em] text-ciano">
          Portal do parceiro BDFlow
        </p>
        <h1 className="mt-3 text-center text-3xl sm:text-4xl">
          Cadastrar empresa parceira
          <span className="mx-auto mt-3 block h-2 w-24 rounded-full bg-ciano" />
        </h1>
        <p className="mt-3 text-center text-sm text-tinta/60">
          Preencha os dados do responsável e da empresa. A análise é feita
          pela BDFlow.
        </p>

        <form onSubmit={enviar} className="mt-8 space-y-6">
          {/* ===== Seção 1: Responsável principal ===== */}
          <section className="card space-y-4 p-6">
            <h2 className="text-lg font-bold">
              <span className="mr-2 inline-flex h-7 w-7 items-center justify-center rounded-full bg-ciano text-sm font-bold text-white">
                1
              </span>
              Responsável principal
            </h2>

            <div>
              <label htmlFor="pc-email" className={rotulo}>E-mail da conta</label>
              <input
                id="pc-email"
                type="email"
                value={session?.user.email ?? ""}
                disabled
                className={`${campo} bg-papel2 text-tinta/60`}
              />
              <p className="mt-1 text-xs text-tinta/50">
                Vem da sua sessão autenticada.
              </p>
            </div>

            <div>
              <label htmlFor="pc-nome" className={rotulo}>Nome completo</label>
              <input
                id="pc-nome"
                type="text"
                value={nome}
                onChange={(e) => setNome(e.target.value)}
                autoComplete="name"
                className={campo}
              />
              {erros.nome && <p className={erroCss}>{erros.nome}</p>}
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label htmlFor="pc-cpf" className={rotulo}>CPF</label>
                <input
                  id="pc-cpf"
                  type="text"
                  inputMode="numeric"
                  value={cpf}
                  onChange={(e) => setCpf(formatarCPF(e.target.value))}
                  placeholder="000.000.000-00"
                  className={campo}
                />
                {erros.cpf && <p className={erroCss}>{erros.cpf}</p>}
              </div>
              <div>
                <label htmlFor="pc-tel" className={rotulo}>Telefone</label>
                <input
                  id="pc-tel"
                  type="tel"
                  inputMode="numeric"
                  value={telefone}
                  onChange={(e) => setTelefone(formatarTelefone(e.target.value))}
                  placeholder="(00) 00000-0000"
                  className={campo}
                />
                {erros.telefone && <p className={erroCss}>{erros.telefone}</p>}
              </div>
            </div>
          </section>

          {/* ===== Seção 2: Empresa parceira ===== */}
          <section className="card space-y-4 p-6">
            <h2 className="text-lg font-bold">
              <span className="mr-2 inline-flex h-7 w-7 items-center justify-center rounded-full bg-ciano text-sm font-bold text-white">
                2
              </span>
              Empresa parceira
            </h2>

            <div>
              <label htmlFor="pc-razao" className={rotulo}>Razão social</label>
              <input
                id="pc-razao"
                type="text"
                value={razaoSocial}
                onChange={(e) => setRazaoSocial(e.target.value)}
                className={campo}
              />
              {erros.razaoSocial && <p className={erroCss}>{erros.razaoSocial}</p>}
            </div>

            <div>
              <label htmlFor="pc-fantasia" className={rotulo}>Nome fantasia</label>
              <input
                id="pc-fantasia"
                type="text"
                value={nomeFantasia}
                onChange={(e) => setNomeFantasia(e.target.value)}
                className={campo}
              />
              {erros.nomeFantasia && (
                <p className={erroCss}>{erros.nomeFantasia}</p>
              )}
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label htmlFor="pc-cnpj" className={rotulo}>CNPJ</label>
                <input
                  id="pc-cnpj"
                  type="text"
                  inputMode="numeric"
                  value={cnpj}
                  onChange={(e) => setCnpj(formatarCNPJ(e.target.value))}
                  placeholder="00.000.000/0000-00"
                  className={campo}
                />
                {erros.cnpj && <p className={erroCss}>{erros.cnpj}</p>}
              </div>
              <div>
                <label htmlFor="pc-telemp" className={rotulo}>
                  Telefone da empresa{" "}
                  <span className="font-normal text-tinta/40">(opcional)</span>
                </label>
                <input
                  id="pc-telemp"
                  type="tel"
                  inputMode="numeric"
                  value={telefoneEmpresa}
                  onChange={(e) =>
                    setTelefoneEmpresa(formatarTelefone(e.target.value))
                  }
                  placeholder="(00) 0000-0000"
                  className={campo}
                />
                {erros.telefoneEmpresa && (
                  <p className={erroCss}>{erros.telefoneEmpresa}</p>
                )}
              </div>
            </div>
          </section>

          {/* Aviso pré-envio */}
          <p className="rounded-2xl bg-papel2 px-5 py-4 text-center text-sm text-tinta/70">
            Cada conta e CPF podem ser vinculados a somente uma empresa
            parceira. A alteração do responsável principal depende da
            administração da BDFlow.
          </p>

          {erroEnvio && (
            <p className="rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
              {erroEnvio}
            </p>
          )}

          <button
            type="submit"
            disabled={enviando}
            className="btn-primary w-full"
          >
            {enviando ? "Enviando cadastro..." : "Enviar cadastro"}
          </button>
        </form>
      </main>
    </>
  );
}
