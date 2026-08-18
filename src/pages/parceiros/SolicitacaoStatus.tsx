import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import Header from "../../components/Header";
import { useAuth } from "../../hooks/useAuth";
import {
  obterMinhaSolicitacao,
  type MinhaSolicitacao,
} from "../../services/partnerApplicationService";

/**
 * /parceiros/solicitacao — área da CONTA PROVISÓRIA.
 *
 * Escopo limitado por decisão de negócio: status, correções, documentos e
 * avisos. Nada de contratos, pagamentos, pré-compra ou operações de owner.
 * Esta área é separada de /portal, que pertence ao parceiro aprovado.
 */

const ROTULOS: Record<string, string> = {
  pending_email_verification: "Aguardando confirmação de e-mail",
  under_review: "Em análise",
  changes_requested: "Correções solicitadas",
  approved: "Aprovada",
  rejected: "Não aprovada",
  withdrawn: "Cancelada",
};

const ROTULOS_ANALISE: Record<string, string> = {
  pending: "Pendente",
  approved: "Aprovada",
  rejected: "Não aprovada",
  changes_requested: "Correção solicitada",
};

export default function SolicitacaoStatus() {
  const { session, carregando } = useAuth();
  const [dados, setDados] = useState<MinhaSolicitacao | null>(null);
  const [buscando, setBuscando] = useState(true);

  useEffect(() => {
    let ativo = true;
    if (carregando) return;
    (async () => {
      const r = await obterMinhaSolicitacao();
      if (!ativo) return;
      setDados(r);
      setBuscando(false);
    })();
    return () => { ativo = false; };
  }, [carregando, session]);

  if (carregando || buscando) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-xl px-4 pt-16">
          <p className="text-center text-sm text-tinta/60" role="status">Carregando...</p>
        </main>
      </>
    );
  }

  if (!dados || !dados.application_id) {
    return (
      <>
        <Header />
        <main className="mx-auto max-w-xl px-4 pb-24 pt-14">
          <div className="card p-8 text-center">
            <h1 className="text-2xl font-bold">Nenhuma solicitação encontrada</h1>
            <p className="mt-4 text-sm text-tinta/70">
              Não localizamos uma solicitação vinculada a este acesso.
            </p>
            <Link to="/parceiros/cadastro" className="btn-primary mt-6 inline-block">
              Fazer uma solicitação
            </Link>
          </div>
        </main>
      </>
    );
  }

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
        <p className="text-xs font-bold uppercase tracking-[0.3em] text-magenta">
          Acesso provisório
        </p>
        <h1 className="mt-3 text-3xl">
          {dados.legal_name}
          <span className="mt-3 block h-2 w-24 rounded-full bg-magenta" />
        </h1>

        <div className="card mt-6 space-y-4 p-6">
          <div className="flex items-center justify-between">
            <span className="text-sm text-tinta/60">Situação</span>
            <span className="font-semibold">{ROTULOS[dados.status ?? ""] ?? dados.status}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-tinta/60">Análise da empresa</span>
            <span>{ROTULOS_ANALISE[dados.company_review_status ?? ""] ?? "—"}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-tinta/60">Análise do responsável</span>
            <span>{ROTULOS_ANALISE[dados.authority_review_status ?? ""] ?? "—"}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-tinta/60">CNPJ</span>
            <span>{dados.cnpj}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-tinta/60">Região</span>
            <span>{dados.city} / {dados.uf}</span>
          </div>
        </div>

        {(dados.pending_corrections ?? 0) > 0 ? (
          <div className="mt-6 rounded-2xl bg-amarelo/25 p-5" role="status">
            <p className="font-semibold">
              {dados.pending_corrections} correção(ões) aguardando sua resposta.
            </p>
            <p className="mt-1 text-sm text-tinta/70">
              Responda para que a análise continue.
            </p>
          </div>
        ) : null}

        <div className="card mt-6 p-6">
          <h2 className="text-lg font-bold">Documentos</h2>
          <p className="mt-2 text-sm text-tinta/70">
            {dados.documents ?? 0} documento(s) enviado(s). Os arquivos ficam em
            armazenamento privado e são acessíveis apenas a você e à análise
            autorizada da BDFlow.
          </p>
        </div>

        <p className="mt-8 text-sm text-tinta/60">
          O acesso provisório não dá acesso ao portal de parceiro aprovado nem a
          contratos, pagamentos ou validação de benefício.
        </p>
      </main>
    </>
  );
}
