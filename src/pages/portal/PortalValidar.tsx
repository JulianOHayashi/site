import { useCallback, useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import {
  obterVinculosParceiro,
  obterContextoValidador,
  prepararValidacaoBeneficio,
  type ContextoValidador,
  type ResultadoPreparacao,
} from "../../services/partnerApplicationService";

/**
 * /portal/validar?qt=... — validação de benefício, LADO SITE.
 *
 * O Site prova QUEM valida, EM QUE unidade e por QUAL rede, e encaminha ao
 * gateway do App. O desfecho do benefício é autoridade do App: enquanto o
 * repositório do App não estiver disponível, a tela informa de forma
 * explícita que o encaminhamento não conclui a validação
 * (BLOCKED_APP_REPOSITORY). Nada aqui afirma que o benefício foi usado.
 *
 * O parâmetro qt é preservado através do login pelo PortalGuard.
 */
type Estado =
  | { fase: "carregando" }
  | { fase: "sem_vinculo" }
  | { fase: "inelegivel" }
  | { fase: "erro" }
  | { fase: "pronto"; ctx: Extract<ContextoValidador, { tipo: "elegivel" }>; companyId: string };

export default function PortalValidar() {
  const [params] = useSearchParams();
  const qt = (params.get("qt") ?? "").trim();

  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });
  const [unidade, setUnidade] = useState("");
  const [token, setToken] = useState(qt);
  const [enviando, setEnviando] = useState(false);
  const [resultado, setResultado] = useState<ResultadoPreparacao | null>(null);

  const carregar = useCallback(async () => {
    setEstado({ fase: "carregando" });
    const vinculos = await obterVinculosParceiro();
    if (vinculos.tipo === "erro") return setEstado({ fase: "erro" });
    const primeiro = vinculos.vinculos[0];
    if (!primeiro) return setEstado({ fase: "sem_vinculo" });

    const ctx = await obterContextoValidador(primeiro.company_id);
    if (ctx.tipo === "erro") return setEstado({ fase: "erro" });
    if (ctx.tipo === "inelegivel") return setEstado({ fase: "inelegivel" });
    setUnidade(ctx.unidades[0]?.unit_id ?? "");
    setEstado({ fase: "pronto", ctx, companyId: primeiro.company_id });
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "pronto" || !unidade || !token.trim()) return;
    setEnviando(true);
    setResultado(
      await prepararValidacaoBeneficio(estado.companyId, unidade, token.trim())
    );
    setEnviando(false);
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Validar benefício" />

        {estado.fase === "carregando" && (
          <p className="mt-8 text-sm text-tinta/60" role="status">
            Verificando sua autorização de validação...
          </p>
        )}

        {estado.fase === "erro" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Não foi possível verificar sua autorização.</p>
            <p className="mt-2 text-sm text-tinta/70">
              Por segurança, nenhuma validação foi encaminhada.
            </p>
            <button onClick={carregar} className="btn-primary mt-4">
              Tentar novamente
            </button>
          </div>
        )}

        {estado.fase === "sem_vinculo" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Esta conta não possui rede parceira ativa.</p>
            <Link to="/portal/dashboard" className="btn-secondary mt-4 inline-block">
              Voltar ao painel
            </Link>
          </div>
        )}

        {estado.fase === "inelegivel" && (
          <div role="alert" className="card mt-8 p-6 text-center">
            <p className="font-semibold">Você não está autorizado a validar.</p>
            <p className="mt-2 text-sm text-tinta/70">
              A validação exige vínculo ativo com ao menos uma unidade ativa.
              Fale com o responsável da empresa.
            </p>
          </div>
        )}

        {estado.fase === "pronto" && (
          <form onSubmit={enviar} className="card mt-8 space-y-4 p-6">
            <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
              {estado.ctx.papel === "partner_owner" ? "Responsável" : "Gestor"} autorizado
            </p>

            <label className="block text-sm">
              <span className="font-semibold">Unidade</span>
              <select
                value={unidade}
                onChange={(e) => setUnidade(e.target.value)}
                className="mt-1 w-full rounded-xl border-2 border-borda px-3 py-2"
              >
                {estado.ctx.unidades.map((u) => (
                  <option key={u.unit_id} value={u.unit_id}>
                    {u.name}
                  </option>
                ))}
              </select>
            </label>

            <label className="block text-sm">
              <span className="font-semibold">Código do benefício</span>
              <input
                value={token}
                onChange={(e) => setToken(e.target.value)}
                className="mt-1 w-full rounded-xl border-2 border-borda px-3 py-2 font-mono"
                placeholder="Código apresentado pelo usuário"
              />
            </label>

            <button
              type="submit"
              disabled={enviando || !token.trim()}
              className="btn-primary w-full disabled:opacity-50"
            >
              {enviando ? "Encaminhando..." : "Encaminhar validação"}
            </button>

            {resultado?.tipo === "negado" && (
              <div role="alert" className="rounded-xl bg-magenta/10 p-3 text-sm text-magenta">
                Validação negada para esta unidade.
              </div>
            )}
            {resultado?.tipo === "erro" && (
              <div role="alert" className="rounded-xl bg-magenta/10 p-3 text-sm text-magenta">
                Não foi possível encaminhar. Nenhuma validação foi registrada como
                concluída.
              </div>
            )}
            {resultado?.tipo === "encaminhado" && (
              <div className="rounded-xl bg-amarelo/25 p-4 text-sm">
                <p className="font-semibold">Encaminhado — ainda NÃO concluído.</p>
                <p className="mt-2 text-tinta/70">
                  O Site confirmou seu papel, sua unidade e sua rede, e registrou a
                  tentativa. A conclusão depende do aplicativo BDFlow, que valida o
                  benefício e pede a confirmação do usuário.
                </p>
                {resultado.appGateway === "BLOCKED_APP_REPOSITORY" && (
                  <p className="mt-2 text-tinta/70">
                    A integração com o aplicativo ainda não está ativa nesta
                    instalação: nenhum benefício foi consumido.
                  </p>
                )}
              </div>
            )}
          </form>
        )}

        {qt && estado.fase !== "pronto" && (
          <div className="mx-auto mt-6 max-w-sm rounded-2xl border border-borda bg-white px-4 py-3 text-sm">
            <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
              Código recebido
            </p>
            <p className="mt-1 break-all font-mono font-semibold">{qt}</p>
          </div>
        )}
      </main>
    </>
  );
}
