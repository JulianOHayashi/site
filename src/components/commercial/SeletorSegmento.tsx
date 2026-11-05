import { useEffect, useId, useState } from "react";
import type {
  CommercialOpportunity,
  CommercialSegment,
} from "../../domain/commercial/types";
import { nicheByCode } from "../../domain/commercial/niches";
import {
  listarSegmentos,
  mensagemSegmento,
  solicitarSegmento,
} from "../../services/commercialSegmentService";

/**
 * Escolha do SEGMENTO efetivo para uma posição comercial.
 *
 * - Posição Outros: o segmento é obrigatório.
 * - Farmácia, Roupas F/M e Calçados: a empresa pode contratar a posição como
 *   o próprio nicho (padrão) ou como um segmento de Outros (substituição).
 * - Supermercado: este componente nem é exibido (a posição não aceita).
 *
 * Tudo aqui é apresentação. Se o segmento está aprovado, livre na
 * exclusividade e cabe na posição, quem decide é o servidor na reserva.
 * Solicitar um segmento não listado não reserva nada.
 */
export default function SeletorSegmento({
  oportunidade,
  ocupados,
  ownerCompanyId,
  valor,
  onChange,
}: {
  oportunidade: CommercialOpportunity;
  /** Códigos de segmento já ocupando OUTRAS posições desta exclusividade. */
  ocupados: ReadonlySet<string>;
  ownerCompanyId: string | null;
  valor: CommercialSegment | null;
  onChange: (s: CommercialSegment | null) => void;
}) {
  const grupo = useId();
  const posicao = nicheByCode(oportunidade.nicheCode);
  const exige = oportunidade.requiresSegment;
  const [comoOutros, setComoOutros] = useState<boolean>(exige || valor !== null);
  const [catalogo, setCatalogo] = useState<
    { fase: "carregando" } | { fase: "erro" } | { fase: "ok"; lista: CommercialSegment[] }
  >({ fase: "carregando" });
  const [pedindo, setPedindo] = useState(false);
  const [rotulo, setRotulo] = useState("");
  const [descricao, setDescricao] = useState("");
  const [envio, setEnvio] = useState<
    | { fase: "parado" }
    | { fase: "enviando" }
    | { fase: "ok"; already: boolean }
    | { fase: "erro"; mensagem: string }
  >({ fase: "parado" });

  useEffect(() => {
    let ativo = true;
    void listarSegmentos().then((r) => {
      if (!ativo) return;
      setCatalogo(r.tipo === "ok" ? { fase: "ok", lista: r.segmentos } : { fase: "erro" });
    });
    return () => {
      ativo = false;
    };
  }, []);

  const alternar = (outros: boolean) => {
    setComoOutros(outros);
    if (!outros) onChange(null);
  };

  const enviarSolicitacao = async () => {
    if (!ownerCompanyId || envio.fase === "enviando") return;
    setEnvio({ fase: "enviando" });
    const r = await solicitarSegmento({
      companyId: ownerCompanyId,
      label: rotulo,
      justification: descricao,
      intendedNicheCode: oportunidade.nicheCode,
    });
    if (r.tipo === "ok") {
      setEnvio({ fase: "ok", already: r.already });
      setRotulo("");
      setDescricao("");
    } else {
      setEnvio({ fase: "erro", mensagem: mensagemSegmento(r.codigo) });
    }
  };

  return (
    <section
      aria-labelledby={`${grupo}-titulo`}
      className="card mt-4 p-6"
      data-testid="seletor-segmento"
    >
      <h2 id={`${grupo}-titulo`} className="text-lg font-bold">
        {exige ? "Segmento da sua empresa" : "Contratar como Outros"}
      </h2>
      <p className="mt-2 text-sm text-tinta/70">
        {exige
          ? "A posição Outros é ocupada por um segmento comercial autorizado pela SmallFlags. Escolha o segmento da sua empresa."
          : `Esta posição pode ser contratada como ${posicao.displayName} ou ocupada por um segmento de Outros. As ${oportunidade.contractedQuantity} unidades são as mesmas nos dois casos, e a posição só pode ser vendida uma vez.`}
      </p>

      {!exige && (
        <fieldset className="mt-4 space-y-2">
          <legend className="sr-only">Forma de contratação</legend>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="radio"
              name={`${grupo}-forma`}
              checked={!comoOutros}
              onChange={() => alternar(false)}
            />
            Contratar como {posicao.displayName}
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="radio"
              name={`${grupo}-forma`}
              checked={comoOutros}
              onChange={() => alternar(true)}
            />
            Contratar esta posição como Outros (outro segmento)
          </label>
        </fieldset>
      )}

      {comoOutros && (
        <div className="mt-4">
          {catalogo.fase === "carregando" && (
            <p className="text-sm text-tinta/60" aria-live="polite">
              Carregando segmentos...
            </p>
          )}
          {catalogo.fase === "erro" && (
            <p className="text-sm text-vermelho" role="alert">
              Não foi possível carregar os segmentos agora.
            </p>
          )}
          {catalogo.fase === "ok" && catalogo.lista.length === 0 && (
            <p className="text-sm text-tinta/70">
              Ainda não há segmentos aprovados. Solicite o seu abaixo.
            </p>
          )}
          {catalogo.fase === "ok" && catalogo.lista.length > 0 && (
            <fieldset className="space-y-2">
              <legend className="text-sm font-semibold">Segmentos disponíveis</legend>
              <p className="text-xs text-tinta/60" data-testid="aviso-disponibilidade-segmento">
                A disponibilidade do segmento nesta exclusividade é confirmada no momento da reserva.
              </p>
              {catalogo.lista.map((s) => {
                const ocupado = ocupados.has(s.code);
                return (
                  <label
                    key={s.id}
                    className={`flex items-start gap-2 text-sm ${ocupado ? "opacity-50" : ""}`}
                  >
                    <input
                      type="radio"
                      name={`${grupo}-segmento`}
                      value={s.id}
                      checked={valor?.id === s.id}
                      disabled={ocupado}
                      onChange={() => onChange(s)}
                    />
                    <span>
                      <span className="font-medium">{s.name}</span>
                      {ocupado && (
                        <span className="ml-1 text-xs">
                          (já ocupa outra posição desta exclusividade)
                        </span>
                      )}
                      {s.description && (
                        <span className="block text-xs text-tinta/60">{s.description}</span>
                      )}
                    </span>
                  </label>
                );
              })}
            </fieldset>
          )}

          <div className="mt-4 border-t border-tinta/10 pt-4">
            {!pedindo ? (
              <button
                type="button"
                className="text-sm font-medium text-ciano hover:underline"
                onClick={() => setPedindo(true)}
              >
                Meu segmento não está na lista
              </button>
            ) : ownerCompanyId ? (
              <div className="space-y-3">
                <label className="block text-sm">
                  <span className="font-semibold">Qual é o segmento da sua empresa?</span>
                  <input
                    type="text"
                    value={rotulo}
                    maxLength={80}
                    onChange={(e) => setRotulo(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borda px-3 py-2"
                  />
                </label>
                <label className="block text-sm">
                  <span className="font-semibold">Descreva a atividade (opcional)</span>
                  <textarea
                    value={descricao}
                    maxLength={1000}
                    rows={3}
                    onChange={(e) => setDescricao(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-borda px-3 py-2"
                  />
                </label>
                <button
                  type="button"
                  className="btn-secondary"
                  disabled={envio.fase === "enviando" || rotulo.trim().length < 3}
                  onClick={enviarSolicitacao}
                >
                  {envio.fase === "enviando" ? "Enviando..." : "Enviar para análise"}
                </button>
                <p className="text-xs text-tinta/60">
                  A solicitação é analisada pela SmallFlags. Ela não reserva a
                  posição, não cria contrato e não garante aprovação.
                </p>
                {envio.fase === "ok" && (
                  <p className="aviso-ok p-3 text-sm" role="status">
                    {envio.already
                      ? "Esta solicitação já está em análise."
                      : "Solicitação enviada para análise da SmallFlags."}
                  </p>
                )}
                {envio.fase === "erro" && (
                  <p className="text-sm text-vermelho" role="alert">
                    {envio.mensagem}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-sm text-tinta/70">
                Entre como responsável da empresa para solicitar um novo segmento.
              </p>
            )}
          </div>
        </div>
      )}

      {comoOutros && valor && (
        <p className="mt-4 rounded-xl bg-superficie2 p-3 text-sm" data-testid="resumo-segmento">
          Posição: <strong>{posicao.displayName}</strong> · Segmento:{" "}
          <strong>{valor.name}</strong> · {oportunidade.contractedQuantity} unidades
        </p>
      )}
    </section>
  );
}
