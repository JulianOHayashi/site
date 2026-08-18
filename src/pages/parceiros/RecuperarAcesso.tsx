import { useState } from "react";
import Header from "../../components/Header";
import { solicitarRecuperacao } from "../../services/partnerApplicationService";
import { somenteDigitos, cnpjValido, emailValido } from "../../lib/onboardingValidacao";

/**
 * Recuperação pública de acesso à solicitação.
 *
 * ANTI-ENUMERAÇÃO: a resposta visual é SEMPRE a mesma, exista ou não uma
 * solicitação para os dados informados. A tela não revela existência de
 * CNPJ ou e-mail, status interno, quantidade de tokens nem identificadores.
 * O backend responde de forma invariante pelo mesmo motivo; aqui apenas
 * não desfazemos essa garantia.
 */
const RESPOSTA_INVARIANTE =
  "Se houver uma solicitação elegível para estes dados, enviaremos as instruções para o e-mail cadastrado.";

export default function RecuperarAcesso({ compacto = false }: { compacto?: boolean }) {
  const [cnpj, setCnpj] = useState("");
  const [email, setEmail] = useState("");
  const [erroFormato, setErroFormato] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [concluido, setConcluido] = useState(false);

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (enviando) return;

    // Validação apenas de FORMATO. Nada aqui informa se os dados existem.
    if (!cnpjValido(cnpj)) {
      setErroFormato("Informe um CNPJ válido.");
      return;
    }
    if (!emailValido(email)) {
      setErroFormato("Informe um e-mail válido.");
      return;
    }
    setErroFormato(null);
    setEnviando(true);
    await solicitarRecuperacao(somenteDigitos(cnpj), email.trim().toLowerCase());
    setEnviando(false);
    // Mesmo desfecho visual em qualquer caso, inclusive falha de transporte:
    // sinalizar erro aqui viraria um oráculo.
    setConcluido(true);
  };

  const conteudo = concluido ? (
    <div className="card p-6 text-center" role="status" aria-live="polite">
      <h2 className="text-lg font-bold">Pedido registrado</h2>
      <p className="mt-3 text-sm text-tinta/70">{RESPOSTA_INVARIANTE}</p>
    </div>
  ) : (
    <form onSubmit={enviar} noValidate className="card space-y-4 p-6">
      <h2 className="text-lg font-bold">Reenviar link de acesso</h2>
      <p className="text-sm text-tinta/60">
        Se o seu link expirou ou você não conseguiu criar o acesso, informe o
        CNPJ e o e-mail usados no cadastro.
      </p>
      <div>
        <label htmlFor="rec-cnpj" className="mb-1.5 block text-sm font-semibold">
          CNPJ
        </label>
        <input
          id="rec-cnpj"
          value={cnpj}
          onChange={(e) => setCnpj(e.target.value)}
          className="w-full rounded-xl border border-borda px-4 py-2.5"
        />
      </div>
      <div>
        <label htmlFor="rec-email" className="mb-1.5 block text-sm font-semibold">
          E-mail do cadastro
        </label>
        <input
          id="rec-email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full rounded-xl border border-borda px-4 py-2.5"
        />
      </div>
      {erroFormato ? (
        <p className="text-sm text-red-700" role="alert">
          {erroFormato}
        </p>
      ) : null}
      <button type="submit" disabled={enviando} className="btn-primary w-full">
        {enviando ? "Enviando..." : "Enviar instruções"}
      </button>
    </form>
  );

  if (compacto) return <div className="mt-6">{conteudo}</div>;

  return (
    <>
      <Header />
      <main className="mx-auto max-w-md px-4 pb-24 pt-14">{conteudo}</main>
    </>
  );
}
