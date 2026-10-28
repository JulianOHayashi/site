import { useEffect, useState } from "react";
import Header from "../../components/Header";
import ConteudoLegal from "../../components/legal/ConteudoLegal";
import {
  listarMeusAceites,
  obterDocumentoPorVersao,
  type LegalAcceptanceRecord,
  type LegalDocument,
} from "../../services/legalDocumentService";
import { PortalTopo } from "./portalUi";

type Item = {
  aceite: LegalAcceptanceRecord;
  documento: LegalDocument | null;
};

type Estado =
  | { fase: "carregando" }
  | { fase: "erro" }
  | { fase: "ok"; itens: Item[] };

const CONTEXTO: Record<string, string> = {
  provisional_account: "Onboarding / conta provisória",
  partner_application: "Solicitação de parceria",
  commercial_contract: "Fechamento comercial",
  owner_authority: "Autoridade do responsável",
  manager_invite: "Convite de manager",
};

export default function PortalDocumentos() {
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });

  useEffect(() => {
    let vivo = true;
    void (async () => {
      const historico = await listarMeusAceites();
      if (!vivo) return;
      if (historico.tipo !== "ok") {
        setEstado({ fase: "erro" });
        return;
      }

      const itens: Item[] = await Promise.all(
        historico.aceites.map(async (aceite) => {
          const r = await obterDocumentoPorVersao(aceite.docType, aceite.version);
          return {
            aceite,
            documento: r.tipo === "ok" ? r.documento : null,
          };
        })
      );
      if (vivo) setEstado({ fase: "ok", itens });
    })();

    return () => {
      vivo = false;
    };
  }, []);

  return (
    <>
      <Header />
      <main className="mx-auto max-w-4xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Documentos e aceites" />

        <section className="mt-8">
          <p className="max-w-2xl text-sm leading-6 text-tinta/70">
            Aqui você consulta os documentos jurídicos vinculados à sua conta,
            com a versão e a data exatas registradas no momento do aceite.
            Esta página é somente leitura.
          </p>

          {estado.fase === "carregando" && (
            <p className="mt-8 text-sm text-tinta/60" role="status">
              Carregando documentos...
            </p>
          )}

          {estado.fase === "erro" && (
            <div className="card mt-8 p-6" role="alert">
              Não foi possível carregar seu histórico jurídico agora.
            </div>
          )}

          {estado.fase === "ok" && estado.itens.length === 0 && (
            <div className="card mt-8 p-6">
              <h2 className="font-bold">Nenhum aceite registrado</h2>
              <p className="mt-2 text-sm text-tinta/70">
                Quando houver documentos jurídicos aceitos nesta conta, eles
                aparecerão aqui com a versão correspondente.
              </p>
            </div>
          )}

          {estado.fase === "ok" && estado.itens.length > 0 && (
            <div className="mt-8 space-y-5">
              {estado.itens.map(({ aceite, documento }) => (
                <article key={aceite.acceptanceId} className="card p-6">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <h2 className="text-xl font-bold">{aceite.title}</h2>
                      <p className="mt-1 text-sm text-tinta/60">
                        Versão <strong className="text-tinta">{aceite.version}</strong>
                      </p>
                    </div>
                    <span className="rounded-full bg-papel2 px-3 py-1 text-xs font-semibold">
                      {aceite.revokedAt ? "Revogado" : "Registrado"}
                    </span>
                  </div>

                  <dl className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
                    <div>
                      <dt className="text-tinta/55">Registrado em</dt>
                      <dd className="font-semibold">
                        {new Date(aceite.acceptedAt).toLocaleString("pt-BR")}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-tinta/55">Contexto</dt>
                      <dd className="font-semibold">
                        {CONTEXTO[aceite.context] ?? aceite.context}
                      </dd>
                    </div>
                  </dl>

                  {aceite.contentHash && (
                    <p className="mt-3 break-all font-mono text-xs text-tinta/55">
                      SHA-256 {aceite.contentHash}
                    </p>
                  )}

                  <details className="mt-5 rounded-2xl border border-borda p-4">
                    <summary className="cursor-pointer font-semibold">
                      Ver documento desta versão
                    </summary>

                    {documento?.content ? (
                      <div className="mt-4">
                        <ConteudoLegal markdown={documento.content} />
                      </div>
                    ) : documento?.contentUrl ? (
                      <a
                        href={documento.contentUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="mt-4 inline-block font-semibold underline"
                      >
                        Abrir documento
                      </a>
                    ) : (
                      <p className="mt-4 text-sm text-tinta/70">
                        O registro do aceite está preservado, mas o conteúdo
                        desta versão não pôde ser carregado agora.
                      </p>
                    )}
                  </details>
                </article>
              ))}
            </div>
          )}
        </section>
      </main>
    </>
  );
}
