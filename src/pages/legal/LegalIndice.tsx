import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  PaginaInstitucional,
  Abertura,
} from "../../components/institucional/Institucional";
import {
  listarDocumentosVigentes,
  type LegalDocument,
} from "../../services/legalDocumentService";

/**
 * /legal — índice da área legal pública.
 *
 * Pública, sem autenticação, somente leitura. Lista apenas o que está
 * efetivamente publicado e vigente: o índice não promete documento que não
 * existe. Privacidade e Termos entram aqui sozinhos quando forem publicados,
 * sem mexer na página — por isso o índice é dirigido por dado, e não por uma
 * lista fixa no código.
 */

/** Rótulos dos tipos que têm página própria. */
const COM_PAGINA: Partial<Record<string, { rotulo: string; to: string }>> = {
  master_agreement: {
    rotulo: "Acordo Mestre de Parceria Comercial",
    to: "/legal/acordo-mestre-parceiros",
  },
};

const NOME_TIPO: Record<string, string> = {
  master_agreement: "Acordo Mestre de Parceria Comercial",
  privacy_notice: "Aviso de Privacidade",
  provisional_account_terms: "Termos da conta provisória",
  truthfulness_declaration: "Declaração de veracidade",
  document_analysis_authorization: "Autorização de análise documental",
  representation_declaration: "Declaração de representação",
  future_commercial_terms: "Termos comerciais futuros",
  commercial_order_terms: "Termos do Pedido Comercial",
};

type Estado =
  | { fase: "carregando" }
  | { fase: "indisponivel" }
  | { fase: "ok"; documentos: LegalDocument[] };

export default function LegalIndice() {
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });

  useEffect(() => {
    let vivo = true;
    void listarDocumentosVigentes().then((r) => {
      if (!vivo) return;
      setEstado(
        r.tipo === "ok" ? { fase: "ok", documentos: r.documentos } : { fase: "indisponivel" }
      );
    });
    return () => {
      vivo = false;
    };
  }, []);

  return (
    <PaginaInstitucional titulo="Documentos legais">
      <Abertura
        rotulo="Legal"
        titulo="Documentos legais"
        texto={
          <p>
            Os documentos publicados pela SmallFlags, com versão, data e hash de
            conteúdo.
          </p>
        }
      />

      <section aria-labelledby="docs-titulo" className="faixa">
        <div className="fio">
          <h2 id="docs-titulo" className="sr-only">
            Documentos publicados
          </h2>

          {estado.fase === "carregando" && (
            <p role="status" className="text-sm text-tinta/70">
              Carregando documentos...
            </p>
          )}

          {/* Falha de consulta NÃO é "não há documento publicado". */}
          {estado.fase === "indisponivel" && (
            <div role="alert" className="rounded-3xl border border-borda bg-superficie p-8">
              <p className="font-semibold">
                Não foi possível carregar os documentos legais agora.
              </p>
              <p className="mt-2 text-sm leading-6 text-tinta/70">
                Isto é uma falha de consulta, não a ausência de documento
                publicado. Tente novamente em instantes.
              </p>
            </div>
          )}

          {estado.fase === "ok" && estado.documentos.length === 0 && (
            <div className="rounded-3xl border border-dashed border-tinta/25 p-8">
              <p className="font-semibold">Nenhum documento publicado no momento.</p>
              <p className="mt-2 max-w-xl text-sm leading-6 text-tinta/70">
                Os documentos legais aparecerão aqui assim que forem publicados.
              </p>
            </div>
          )}

          {estado.fase === "ok" && estado.documentos.length > 0 && (
            <ul className="divide-y divide-tinta/10 border-y border-tinta/10">
              {estado.documentos.map((d) => {
                const pagina = COM_PAGINA[d.docType];
                return (
                  <li key={`${d.docType}:${d.version}`} className="py-5">
                    <div className="flex flex-wrap items-baseline justify-between gap-3">
                      <h3 className="text-lg font-semibold">
                        {pagina ? (
                          <Link
                            to={pagina.to}
                            className="underline decoration-ciano decoration-2 underline-offset-4"
                          >
                            {d.title}
                          </Link>
                        ) : (
                          d.title
                        )}
                      </h3>
                      <p className="text-sm text-tinta/70">
                        {NOME_TIPO[d.docType] ?? d.docType}
                      </p>
                    </div>
                    <dl className="mt-2 flex flex-wrap gap-x-6 gap-y-1 text-sm text-tinta/70">
                      <div className="flex gap-1.5">
                        <dt>Versão:</dt>
                        <dd className="font-semibold text-tinta">{d.version}</dd>
                      </div>
                      {d.effectiveFrom && (
                        <div className="flex gap-1.5">
                          <dt>Vigente desde:</dt>
                          <dd>{new Date(d.effectiveFrom).toLocaleDateString("pt-BR")}</dd>
                        </div>
                      )}
                    </dl>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>
    </PaginaInstitucional>
  );
}
