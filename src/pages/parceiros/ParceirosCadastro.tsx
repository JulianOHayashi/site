import { useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { UFS } from "../../lib/brazilStates";
import {
  validarFormulario,
  somenteDigitos,
  type CamposFormulario,
  type ErrosFormulario,
} from "../../lib/onboardingValidacao";
import { criarSolicitacao, mensagemDeMotivo } from "../../services/partnerApplicationService";
import { supabaseConfigurado } from "../../lib/supabase";

/**
 * /parceiros/cadastro — solicitação empresarial real (Fase 2A).
 *
 * A solicitação nasce ANTES de existir conta Auth. Nenhum owner é criado
 * aqui, e a RPC legada create_my_partner_owner_registration não é usada.
 * O backend decide tudo: esta tela apenas coleta e reflete.
 */

const CAMPOS_INICIAIS: CamposFormulario = {
  cnpj: "",
  legal_name: "",
  trade_name: "",
  contact_email: "",
  contact_phone: "",
  postal_code: "",
  street: "",
  street_number: "",
  district: "",
  city: "",
  uf: "ES",
  representative_full_name: "",
  representative_cpf: "",
  representative_email: "",
  representative_phone: "",
};

export default function ParceirosCadastro() {
  const [campos, setCampos] = useState<CamposFormulario>(CAMPOS_INICIAIS);
  const [erros, setErros] = useState<ErrosFormulario>({});
  const [erroGeral, setErroGeral] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [enviado, setEnviado] = useState(false);
  const [aceite, setAceite] = useState(false);

  const alterar = (nome: keyof CamposFormulario) => (
    e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>
  ) => {
    setCampos((atual) => ({ ...atual, [nome]: e.target.value }));
    setErros((atual) => {
      if (!atual[nome]) return atual;
      const proximo = { ...atual };
      delete proximo[nome];
      return proximo;
    });
  };

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setErroGeral(null);

    const problemas = validarFormulario(campos);
    if (!aceite) problemas.aceite = "É necessário aceitar os termos para continuar.";
    setErros(problemas);
    if (Object.keys(problemas).length > 0) return;

    setEnviando(true);
    const resultado = await criarSolicitacao({
      cnpj: somenteDigitos(campos.cnpj),
      legal_name: campos.legal_name.trim(),
      trade_name: campos.trade_name.trim() || undefined,
      contact_email: campos.contact_email.trim().toLowerCase(),
      contact_phone: somenteDigitos(campos.contact_phone) || undefined,
      postal_code: somenteDigitos(campos.postal_code) || undefined,
      street: campos.street.trim() || undefined,
      street_number: campos.street_number.trim() || undefined,
      district: campos.district.trim() || undefined,
      city: campos.city.trim(),
      uf: campos.uf,
      representative_full_name: campos.representative_full_name.trim(),
      representative_cpf: somenteDigitos(campos.representative_cpf),
      representative_email: campos.representative_email.trim().toLowerCase() || undefined,
      representative_phone: somenteDigitos(campos.representative_phone) || undefined,
    });
    setEnviando(false);

    if (!resultado.ok) {
      setErroGeral(mensagemDeMotivo(resultado.motivo));
      return;
    }
    setEnviado(true);
  };

  if (!supabaseConfigurado) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-xl px-4 pb-24 pt-14">
          <div className="rounded-2xl bg-amarelo/25 p-5 text-center text-sm">
            Cadastro em configuração. Tente novamente mais tarde.
          </div>
        </main>
      </>
    );
  }

  if (enviado) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-xl px-4 pb-24 pt-14">
          <div className="card p-8 text-center" role="status" aria-live="polite">
            <h1 className="text-2xl font-bold">Confirme seu e-mail</h1>
            <p className="mt-4 text-sm text-tinta/70">
              Enviamos um link de confirmação para o e-mail informado. Ele é de
              uso único e expira em 24 horas. Depois de confirmar, você poderá
              criar seu acesso provisório e acompanhar a análise.
            </p>
            <Link to="/" className="btn-primary mt-6 inline-block">
              Voltar ao início
            </Link>
          </div>
        </main>
      </>
    );
  }

  const campo = (
    nome: keyof CamposFormulario,
    rotulo: string,
    extra?: { tipo?: string; placeholder?: string; obrigatorio?: boolean }
  ) => (
    <div>
      <label htmlFor={nome} className="mb-1.5 block text-sm font-semibold">
        {rotulo}
        {extra?.obrigatorio ? <span aria-hidden="true"> *</span> : null}
      </label>
      <input
        id={nome}
        name={nome}
        type={extra?.tipo ?? "text"}
        value={campos[nome]}
        onChange={alterar(nome)}
        placeholder={extra?.placeholder}
        aria-invalid={erros[nome] ? true : undefined}
        aria-describedby={erros[nome] ? `${nome}-erro` : undefined}
        className="w-full rounded-xl border border-borda px-4 py-2.5"
      />
      {erros[nome] ? (
        <p id={`${nome}-erro`} className="mt-1 text-sm text-red-700">
          {erros[nome]}
        </p>
      ) : null}
    </div>
  );

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
          Parceiros BDFlow
        </p>
        <h1 className="mt-3 text-3xl sm:text-4xl">
          Solicitação de parceria
          <span className="mt-3 block h-2 w-24 rounded-full bg-magenta" />
        </h1>
        <p className="mt-3 text-sm text-tinta/60">
          Envie os dados da empresa e do responsável. Após confirmar o e-mail,
          você acompanha a análise por uma área de acesso provisório.
        </p>

        <form onSubmit={enviar} noValidate className="mt-8 space-y-8">
          <section className="card space-y-5 p-6">
            <h2 className="text-lg font-bold">Dados da empresa</h2>
            {campo("cnpj", "CNPJ", { placeholder: "00.000.000/0000-00", obrigatorio: true })}
            {campo("legal_name", "Razão social", { obrigatorio: true })}
            {campo("trade_name", "Nome fantasia")}
            {campo("contact_email", "E-mail de contato", { tipo: "email", obrigatorio: true })}
            {campo("contact_phone", "Telefone")}
          </section>

          <section className="card space-y-5 p-6">
            <h2 className="text-lg font-bold">Endereço</h2>
            {campo("postal_code", "CEP")}
            {campo("street", "Logradouro")}
            {campo("street_number", "Número")}
            {campo("district", "Bairro")}
            {campo("city", "Cidade", { obrigatorio: true })}
            <div>
              <label htmlFor="uf" className="mb-1.5 block text-sm font-semibold">
                UF <span aria-hidden="true">*</span>
              </label>
              <select
                id="uf"
                name="uf"
                value={campos.uf}
                onChange={alterar("uf")}
                aria-invalid={erros.uf ? true : undefined}
                className="w-full rounded-xl border border-borda px-4 py-2.5"
              >
                {Object.entries(UFS).map(([sigla, nome]) => (
                  <option key={sigla} value={sigla}>
                    {sigla} — {nome}
                  </option>
                ))}
              </select>
              {erros.uf ? <p className="mt-1 text-sm text-red-700">{erros.uf}</p> : null}
            </div>
          </section>

          <section className="card space-y-5 p-6">
            <h2 className="text-lg font-bold">Responsável pela empresa</h2>
            <p className="text-sm text-tinta/60">
              A análise da empresa e a análise da autoridade do responsável são
              feitas separadamente.
            </p>
            {campo("representative_full_name", "Nome completo", { obrigatorio: true })}
            {campo("representative_cpf", "CPF", { placeholder: "000.000.000-00", obrigatorio: true })}
            {campo("representative_email", "E-mail do responsável", { tipo: "email" })}
            {campo("representative_phone", "Telefone do responsável")}
          </section>

          <div className="card p-6">
            <label className="flex items-start gap-3 text-sm">
              <input
                type="checkbox"
                checked={aceite}
                onChange={(e) => setAceite(e.target.checked)}
                aria-invalid={erros.aceite ? true : undefined}
                className="mt-1"
              />
              <span>
                Declaro que as informações são verdadeiras e autorizo a análise
                documental para fins de cadastro de parceria.
              </span>
            </label>
            {erros.aceite ? (
              <p className="mt-2 text-sm text-red-700">{erros.aceite}</p>
            ) : null}
          </div>

          {erroGeral ? (
            <div role="alert" className="rounded-xl bg-red-50 p-4 text-sm text-red-800">
              {erroGeral}
            </div>
          ) : null}

          <button type="submit" disabled={enviando} className="btn-primary w-full">
            {enviando ? "Enviando..." : "Enviar solicitação"}
          </button>
        </form>
      </main>
    </>
  );
}
