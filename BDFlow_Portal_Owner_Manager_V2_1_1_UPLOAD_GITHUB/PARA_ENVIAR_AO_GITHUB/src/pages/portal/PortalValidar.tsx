/**
 * /portal/validar — operação COMPARTILHADA por owner e manager.
 *
 * Regras:
 *  • o convite do manager NÃO fixa filial: a filial é escolhida em CADA
 *    validação, pelo operador autenticado;
 *  • só aparecem filiais da empresa cadastradas, ativas e autorizadas;
 *  • o owner também pode validar a qualquer momento, mesmo havendo managers;
 *  • o navegador NUNCA valida o token, NUNCA consulta o banco privado do App
 *    e NUNCA decide liberação — isso caberá à camada server-side Site→App;
 *  • o parâmetro `qt` e a rota completa são preservados através do login.
 */

import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import Header from "../../components/Header";
import { PortalCabecalho } from "./portalUi";
import {
  FuncaoIndisponivel,
  PortalAviso,
  PortalMemberGate,
} from "../../components/portal/PortalGuards";
import {
  filterValidatableUnits,
  listValidatableUnits,
} from "../../services/partnerUnitService";
import { startValidation } from "../../services/partnerValidationService";
import { portalNavigation } from "../../domain/portal/navigation";
import { roleLabel } from "../../domain/portal/capabilities";
import {
  PORTAL_ERROR_LABEL,
  type PartnerUnit,
  type PortalCapabilities,
  type PortalErrorCode,
  type PortalMembership,
  type ValidationOutcome,
} from "../../domain/portal/types";

function Conteudo({
  capabilities,
  membership,
}: {
  capabilities: PortalCapabilities;
  membership: PortalMembership;
}) {
  const [params] = useSearchParams();
  const qt = (params.get("qt") ?? "").trim();

  const [unidades, setUnidades] = useState<PartnerUnit[]>([]);
  const [erroUnidades, setErroUnidades] = useState<PortalErrorCode | null>(null);
  const [carregandoUnidades, setCarregandoUnidades] = useState(true);

  const [unidadeId, setUnidadeId] = useState("");
  const [codigo, setCodigo] = useState(qt);
  const [enviando, setEnviando] = useState(false);
  const [erroEnvio, setErroEnvio] = useState<PortalErrorCode | null>(null);
  const [resultado, setResultado] = useState<ValidationOutcome | null>(null);

  const nav = portalNavigation(membership.role, capabilities);

  useEffect(() => {
    let ativo = true;
    listValidatableUnits().then((r) => {
      if (!ativo) return;
      if (r.ok) setUnidades(r.data);
      else setErroUnidades(r.error.code);
      setCarregandoUnidades(false);
    });
    return () => {
      ativo = false;
    };
  }, []);

  const elegiveis = useMemo(() => filterValidatableUnits(unidades), [unidades]);

  const validar = async () => {
    setErroEnvio(null);
    setResultado(null);
    if (!unidadeId || !codigo.trim()) return;
    setEnviando(true);
    const r = await startValidation({ unitId: unidadeId, code: codigo.trim() });
    setEnviando(false);
    // Sem backend não há sucesso — jamais simular consulta ou aprovação.
    if (!r.ok) setErroEnvio(r.error.code);
    else setResultado(r.data);
  };

  return (
    <main className="mx-auto max-w-2xl px-4 pb-24 pt-10">
      <PortalCabecalho titulo="Validar benefício" itens={nav} />

      <p className="mt-4 text-sm text-tinta/60">
        Operando como {roleLabel(membership.role)}. A filial é escolhida a cada
        validação.
      </p>

      {!capabilities.canValidateBenefits ? (
        <FuncaoIndisponivel
          titulo="Validação ainda não disponível"
          descricao="A liberação de benefícios depende da camada segura de servidor entre o Site e o aplicativo, que ainda não foi ativada. Nenhum código é consultado ou consumido por aqui."
        />
      ) : (
        <>
          <section className="mt-6 rounded-2xl border border-borda bg-white/85 p-5">
            <label htmlFor="val-unidade" className="mb-1.5 block text-sm font-semibold">
              Filial em que você está trabalhando agora
            </label>
            {carregandoUnidades ? (
              <p className="text-sm text-tinta/60">Carregando filiais...</p>
            ) : erroUnidades ? (
              <p className="rounded-xl bg-papel2 px-4 py-3 text-sm text-tinta/70">
                {PORTAL_ERROR_LABEL[erroUnidades]}
              </p>
            ) : elegiveis.length === 0 ? (
              <p className="rounded-xl bg-amarelo/20 px-4 py-3 text-sm">
                Nenhuma filial ativa e autorizada a liberar benefícios está
                disponível para a sua empresa.
              </p>
            ) : (
              <select
                id="val-unidade"
                value={unidadeId}
                onChange={(e) => setUnidadeId(e.target.value)}
                className="w-full rounded-xl border border-borda px-4 py-3 outline-none focus:border-ciano"
              >
                <option value="">Selecione a filial</option>
                {elegiveis.map((u) => (
                  <option key={u.unitId} value={u.unitId}>
                    {u.branchDisplayName ?? "Unidade"} —{" "}
                    {u.branchLocationLabel ?? "local não informado"}
                  </option>
                ))}
              </select>
            )}
          </section>

          <section className="mt-4 rounded-2xl border border-borda bg-white/85 p-5">
            <label htmlFor="val-codigo" className="mb-1.5 block text-sm font-semibold">
              Código da solicitação (QR)
            </label>
            <input
              id="val-codigo"
              type="text"
              value={codigo}
              onChange={(e) => setCodigo(e.target.value)}
              placeholder="Leia o QR ou digite o código"
              className="w-full rounded-xl border border-borda px-4 py-3 font-mono outline-none focus:border-ciano"
            />
            <button
              onClick={validar}
              disabled={enviando || !unidadeId || !codigo.trim()}
              className="btn-primary mt-4 w-full disabled:cursor-not-allowed disabled:opacity-50"
            >
              {enviando ? "Solicitando validação..." : "Solicitar validação"}
            </button>
          </section>

          {erroEnvio && (
            <div className="mt-4 rounded-xl bg-magenta/10 px-4 py-3 text-sm font-medium text-magenta">
              {PORTAL_ERROR_LABEL[erroEnvio]} Nenhum benefício foi consultado ou
              utilizado.
            </div>
          )}

          {resultado && (
            <div className="mt-4 rounded-2xl border-2 border-borda bg-white p-5 text-sm">
              <p className="font-bold">Resultado: {resultado.state}</p>
              <p className="mt-1 text-tinta/70">
                {resultado.benefitTypeLabel ?? "Tipo de benefício não informado"}{" "}
                · {resultado.unitLabel ?? "filial não informada"}
              </p>
            </div>
          )}
        </>
      )}

      {qt && (
        <div className="mt-6 rounded-2xl border border-borda bg-white px-4 py-3 text-sm">
          <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
            Código recebido no link
          </p>
          <p className="mt-1 break-all font-mono font-semibold">{qt}</p>
          <p className="mt-1 text-xs text-tinta/50">
            O código foi preservado — inclusive através do login.
          </p>
        </div>
      )}

      <PortalAviso
        titulo="Dados pessoais não são exibidos"
        descricao="São mostradas apenas informações indispensáveis da solicitação: tipo de benefício, filial, estado, prazo e resultado. Jornada, horas, sessões, documentos, grupo e localização do usuário do aplicativo não pertencem ao Portal."
      />

      <Link to="/portal/dashboard" className="btn-secondary mt-6 inline-block">
        Voltar ao início
      </Link>
    </main>
  );
}

export default function PortalValidar() {
  return (
    <PortalMemberGate exigirAtivo>
      {({ membership, capabilities }) => (
        <>
          <Header />
          <Conteudo membership={membership} capabilities={capabilities} />
        </>
      )}
    </PortalMemberGate>
  );
}
