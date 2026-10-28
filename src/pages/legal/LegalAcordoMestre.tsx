import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  PaginaInstitucional,
  Abertura,
} from "../../components/institucional/Institucional";
import ConteudoLegal from "../../components/legal/ConteudoLegal";
import {
  obterDocumentoVigente,
  obterDocumentoPorVersao,
  type LegalDocument,
  type ResultadoLegal,
} from "../../services/legalDocumentService";

/**
 * /legal/acordo-mestre-parceiros — Acordo Mestre de Parceria Comercial.
 *
 * Pública, sem autenticação, sem escrita.
 *
 * VERSÃO HISTÓRICA. Com `?versao=X` a página exibe exatamente a versão X,
 * mesmo arquivada. É o que impede que publicar a versão seguinte troque, aos
 * olhos de quem consulta, o texto de um contrato já aceito. Sem o parâmetro,
 * exibe a vigente.
 *
 * FALHA FECHADA. Consulta que falha e documento inexistente são estados
 * DIFERENTES: dizer "não há Acordo publicado" por causa de uma queda de rede
 * seria uma afirmação falsa numa página legal. Nenhum dos dois inventa texto.
 *
 * O conteúdo nunca é injetado como HTML — ver ConteudoLegal.
 */
export default function LegalAcordoMestre() {
  const [params] = useSearchParams();
  const versaoPedida = params.get("versao");
  const [estado, setEstado] = useState<ResultadoLegal | { tipo: "carregando" }>({
    tipo: "carregando",
  });

  useEffect(() => {
    let vivo = true;
    setEstado({ tipo: "carregando" });
    const consulta = versaoPedida
      ? obterDocumentoPorVersao("master_agreement", versaoPedida)
      : obterDocumentoVigente("master_agreement");
    void consulta.then((r) => {
      if (vivo) setEstado(r);
    });
    return () => {
      vivo = false;
    };
  }, [versaoPedida]);

  const doc: LegalDocument | null = estado.tipo === "ok" ? estado.documento : null;

  return (
    <PaginaInstitucional titulo="Acordo Mestre de Parceria Comercial">
      <Abertura
        rotulo="Legal"
        titulo={doc?.title ?? "Acordo Mestre de Parceria Comercial"}
        texto={
          doc ? (
            <p>
              Documento publicado pela SmallFlags. Versão, vigência e hash de
              conteúdo abaixo.
            </p>
          ) : undefined
        }
      />

      <section aria-labelledby="doc-titulo" className="faixa">
        <div className="fio">
          <h2 id="doc-titulo" className="sr-only">
            Documento
          </h2>

          {estado.tipo === "carregando" && (
            <p role="status" className="text-sm text-tinta/70">
              Carregando o documento...
            </p>
          )}

          {estado.tipo === "indisponivel" && (
            <div role="alert" className="rounded-3xl border border-borda bg-superficie p-8">
              <p className="font-semibold">
                Não foi possível carregar o Acordo Mestre agora.
              </p>
              <p className="mt-2 max-w-xl text-sm leading-6 text-tinta/70">
                Isto é uma falha de consulta, não a ausência de documento
                publicado. Nenhum texto é exibido de memória.
              </p>
            </div>
          )}

          {estado.tipo === "ausente" && (
            <div role="alert" className="rounded-3xl border border-dashed border-tinta/25 p-8">
              <p className="font-semibold">
                {versaoPedida
                  ? `A versão ${versaoPedida} não está disponível publicamente.`
                  : "Nenhuma versão do Acordo Mestre está publicada no momento."}
              </p>
              <p className="mt-2 max-w-xl text-sm leading-6 text-tinta/70">
                Esta página só exibe documento efetivamente publicado. Nada é
                substituído por texto provisório.
              </p>
              <Link to="/legal" className="btn-secondary mt-5 inline-block">
                Ver documentos legais
              </Link>
            </div>
          )}

          {doc && (
            <article>
              {/* Identidade do documento: versão e hash sempre juntos. */}
              <dl className="grid gap-4 rounded-3xl border border-borda bg-superficie p-6 sm:grid-cols-2 sm:p-8">
                <div>
                  <dt className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                    Versão
                  </dt>
                  <dd className="mt-1 font-semibold">{doc.version}</dd>
                </div>
                <div>
                  <dt className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                    Situação
                  </dt>
                  <dd className="mt-1 font-semibold">
                    {doc.status === "published" ? "Publicada" : "Versão histórica"}
                  </dd>
                </div>
                {doc.effectiveFrom && (
                  <div>
                    <dt className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                      Vigente desde
                    </dt>
                    <dd className="mt-1">
                      {new Date(doc.effectiveFrom).toLocaleDateString("pt-BR")}
                    </dd>
                  </div>
                )}
                {doc.publishedAt && (
                  <div>
                    <dt className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                      Publicada em
                    </dt>
                    <dd className="mt-1">
                      {new Date(doc.publishedAt).toLocaleDateString("pt-BR")}
                    </dd>
                  </div>
                )}
                {doc.contentHash && (
                  <div className="sm:col-span-2">
                    <dt className="text-xs font-bold uppercase tracking-widest text-tinta/60">
                      Hash do conteúdo (SHA-256)
                    </dt>
                    <dd className="mt-1 break-all font-mono text-sm">{doc.contentHash}</dd>
                  </div>
                )}
              </dl>

              {doc.status === "archived" && (
                <p
                  role="status"
                  className="mt-5 aviso-atencao rounded-2xl"
                >
                  Esta é uma versão histórica, mantida para consulta de contratos
                  celebrados sob ela.{" "}
                  <Link
                    to="/legal/acordo-mestre-parceiros"
                    className="font-semibold underline decoration-ciano decoration-2 underline-offset-4"
                  >
                    Ver a versão vigente
                  </Link>
                  .
                </p>
              )}

              <div className="mt-8 max-w-3xl">
                {doc.content ? (
                  <ConteudoLegal markdown={doc.content} />
                ) : doc.contentUrl ? (
                  <p className="leading-7 text-tinta/80">
                    O texto integral está disponível em{" "}
                    <a
                      href={doc.contentUrl}
                      className="font-semibold underline decoration-ciano decoration-2 underline-offset-4"
                      rel="noopener noreferrer"
                    >
                      documento publicado
                    </a>
                    .
                  </p>
                ) : (
                  <p role="alert" className="leading-7 text-tinta/80">
                    O conteúdo deste documento não está disponível para exibição.
                  </p>
                )}
              </div>
            </article>
          )}
        </div>
      </section>
    </PaginaInstitucional>
  );
}
