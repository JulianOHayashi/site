import { useCallback, useEffect, useMemo, useState } from "react";
import Header from "../../components/Header";
import { PortalTopo } from "./portalUi";
import { emailValido } from "../../lib/onboardingValidacao";
import {
  carregarEquipeOwner,
  mensagemDeMotivo,
  obterVinculosParceiro,
  ownerConvidarManager,
  ownerCriarUnidade,
  ownerRevogarConviteManager,
  type ConviteManager,
  type EquipeOwner,
} from "../../services/partnerApplicationService";

type Estado =
  | { fase: "carregando" }
  | { fase: "negado" }
  | { fase: "erro"; mensagem: string }
  | { fase: "ok"; companyId: string; tradeName: string; dados: EquipeOwner };

const STATUS_CONVITE: Record<string, string> = {
  pending: "Pendente",
  accepted: "Aceito",
  revoked: "Revogado",
  expired: "Expirado",
  superseded: "Substituído",
};

export default function PortalEquipe() {
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });
  const [nomeUnidade, setNomeUnidade] = useState("");
  const [cidade, setCidade] = useState("");
  const [uf, setUf] = useState("");
  const [nomeManager, setNomeManager] = useState("");
  const [emailManager, setEmailManager] = useState("");
  const [unitId, setUnitId] = useState("");
  const [acao, setAcao] = useState<string | null>(null);
  const [mensagem, setMensagem] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    setEstado({ fase: "carregando" });
    const ctx = await obterVinculosParceiro();
    if (ctx.tipo !== "ok") {
      setEstado({ fase: "erro", mensagem: "Não foi possível carregar o contexto da empresa." });
      return;
    }

    const owner = ctx.vinculos.find(
      (v) => v.role === "partner_owner" && v.member_status === "active"
    );
    if (!owner) {
      setEstado({ fase: "negado" });
      return;
    }

    const equipe = await carregarEquipeOwner(owner.company_id);
    if (!equipe.ok) {
      setEstado({ fase: "erro", mensagem: mensagemDeMotivo(equipe.motivo) });
      return;
    }

    setEstado({
      fase: "ok",
      companyId: owner.company_id,
      tradeName: owner.trade_name,
      dados: equipe.dados,
    });
    setCidade((atual) => atual || owner.city || "");
    setUf((atual) => atual || owner.uf || "");
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const unidadesAtivas = useMemo(
    () =>
      estado.fase === "ok"
        ? estado.dados.unidades.filter((u) => u.status === "active")
        : [],
    [estado]
  );

  useEffect(() => {
    if (!unitId && unidadesAtivas.length === 1) {
      setUnitId(unidadesAtivas[0].id);
    }
  }, [unitId, unidadesAtivas]);

  const criarUnidade = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "ok") return;
    setMensagem(null);

    if (nomeUnidade.trim().length < 2 || cidade.trim().length < 2 || uf.trim().length !== 2) {
      setMensagem("Informe nome, cidade e UF da unidade.");
      return;
    }

    setAcao("unidade");
    const r = await ownerCriarUnidade(
      estado.companyId,
      nomeUnidade.trim(),
      cidade.trim(),
      uf.trim().toUpperCase()
    );
    setAcao(null);

    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }

    setNomeUnidade("");
    setMensagem("Unidade criada.");
    await carregar();
  };

  const convidar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (estado.fase !== "ok") return;
    setMensagem(null);

    if (nomeManager.trim().length < 3) {
      setMensagem("Informe o nome do manager.");
      return;
    }
    if (!emailValido(emailManager)) {
      setMensagem("Informe um e-mail válido.");
      return;
    }
    if (!unitId) {
      setMensagem("Selecione a unidade em que o manager poderá validar.");
      return;
    }

    setAcao("convite");
    const r = await ownerConvidarManager(
      estado.companyId,
      emailManager,
      nomeManager,
      unitId
    );
    setAcao(null);

    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }

    setNomeManager("");
    setEmailManager("");
    setMensagem("Convite criado. O link é válido por 48 horas após o despacho.");
    await carregar();
  };

  const revogar = async (convite: ConviteManager) => {
    if (acao || convite.status !== "pending") return;
    setMensagem(null);
    setAcao(convite.id);
    const r = await ownerRevogarConviteManager(convite.id);
    setAcao(null);
    if (!r.ok) {
      setMensagem(mensagemDeMotivo(r.motivo));
      return;
    }
    setMensagem("Convite revogado.");
    await carregar();
  };

  return (
    <>
      <Header />
      <main className="mx-auto max-w-5xl px-4 pb-24 pt-10">
        <PortalTopo titulo="Equipe e unidades" />

        {estado.fase === "carregando" && (
          <p className="mt-10 text-center text-sm text-tinta/60" role="status">
            Carregando equipe...
          </p>
        )}

        {estado.fase === "negado" && (
          <section className="card mt-8 p-8 text-center" role="alert">
            <h2 className="text-xl font-bold">Acesso restrito ao responsável da empresa</h2>
            <p className="mt-2 text-sm text-tinta/70">
              Managers não podem convidar outros managers nem alterar unidades.
            </p>
          </section>
        )}

        {estado.fase === "erro" && (
          <section className="card mt-8 p-8 text-center" role="alert">
            <p>{estado.mensagem}</p>
            <button className="btn-secondary mt-4" onClick={() => void carregar()}>
              Tentar novamente
            </button>
          </section>
        )}

        {estado.fase === "ok" && (
          <>
            <section className="card mt-8 p-6">
              <p className="text-xs font-bold uppercase tracking-widest text-tinta/40">
                Empresa
              </p>
              <h2 className="mt-1 text-xl font-bold">{estado.tradeName}</h2>
            </section>

            {mensagem && (
              <p className="mt-5 rounded-xl bg-ciano/10 px-4 py-3 text-sm" role="status">
                {mensagem}
              </p>
            )}

            <div className="mt-6 grid gap-6 lg:grid-cols-2">
              <form onSubmit={criarUnidade} className="card space-y-4 p-6">
                <div>
                  <h2 className="text-xl font-bold">Cadastrar unidade</h2>
                  <p className="mt-1 text-sm text-tinta/60">
                    Managers só validam nas unidades às quais estiverem vinculados.
                  </p>
                </div>
                <div>
                  <label htmlFor="unidade-nome" className="mb-1 block text-sm font-semibold">
                    Nome da unidade
                  </label>
                  <input
                    id="unidade-nome"
                    value={nomeUnidade}
                    onChange={(e) => setNomeUnidade(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                    placeholder="Ex.: Matriz Vitória"
                  />
                </div>
                <div className="grid gap-3 sm:grid-cols-[1fr_100px]">
                  <div>
                    <label htmlFor="unidade-cidade" className="mb-1 block text-sm font-semibold">
                      Cidade
                    </label>
                    <input
                      id="unidade-cidade"
                      value={cidade}
                      onChange={(e) => setCidade(e.target.value)}
                      className="w-full rounded-xl border border-borda px-4 py-3"
                    />
                  </div>
                  <div>
                    <label htmlFor="unidade-uf" className="mb-1 block text-sm font-semibold">
                      UF
                    </label>
                    <input
                      id="unidade-uf"
                      value={uf}
                      onChange={(e) => setUf(e.target.value.toUpperCase())}
                      maxLength={2}
                      className="w-full rounded-xl border border-borda px-4 py-3"
                    />
                  </div>
                </div>
                <button disabled={acao !== null} className="btn-secondary w-full" type="submit">
                  {acao === "unidade" ? "Criando..." : "Criar unidade"}
                </button>
              </form>

              <form onSubmit={convidar} className="card space-y-4 p-6">
                <div>
                  <h2 className="text-xl font-bold">Convidar manager</h2>
                  <p className="mt-1 text-sm text-tinta/60">
                    O convite é pessoal, vinculado ao e-mail informado e expira em 48 horas.
                  </p>
                </div>
                <div>
                  <label htmlFor="manager-nome" className="mb-1 block text-sm font-semibold">
                    Nome
                  </label>
                  <input
                    id="manager-nome"
                    value={nomeManager}
                    onChange={(e) => setNomeManager(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                  />
                </div>
                <div>
                  <label htmlFor="manager-email" className="mb-1 block text-sm font-semibold">
                    E-mail
                  </label>
                  <input
                    id="manager-email"
                    type="email"
                    value={emailManager}
                    onChange={(e) => setEmailManager(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                  />
                </div>
                <div>
                  <label htmlFor="manager-unidade" className="mb-1 block text-sm font-semibold">
                    Unidade inicial
                  </label>
                  <select
                    id="manager-unidade"
                    value={unitId}
                    onChange={(e) => setUnitId(e.target.value)}
                    className="w-full rounded-xl border border-borda px-4 py-3"
                  >
                    <option value="">Selecione</option>
                    {unidadesAtivas.map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.name} — {u.city}/{u.uf}
                      </option>
                    ))}
                  </select>
                </div>
                <button
                  disabled={acao !== null || unidadesAtivas.length === 0}
                  className="btn-primary w-full"
                  type="submit"
                >
                  {acao === "convite" ? "Criando convite..." : "Enviar convite"}
                </button>
                {unidadesAtivas.length === 0 && (
                  <p className="text-xs text-tinta/60">
                    Cadastre ao menos uma unidade ativa antes de convidar um manager.
                  </p>
                )}
              </form>
            </div>

            <section className="card mt-6 p-6">
              <h2 className="text-xl font-bold">Unidades</h2>
              {estado.dados.unidades.length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhuma unidade cadastrada.</p>
              ) : (
                <div className="mt-4 space-y-3">
                  {estado.dados.unidades.map((u) => (
                    <div key={u.id} className="rounded-xl border border-borda p-4">
                      <div className="flex flex-wrap justify-between gap-2">
                        <strong>{u.name}</strong>
                        <span className="text-sm">{u.status}</span>
                      </div>
                      <p className="mt-1 text-sm text-tinta/60">{u.city}/{u.uf}</p>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <section className="card mt-6 p-6">
              <h2 className="text-xl font-bold">Managers</h2>
              {estado.dados.membros.filter((m) => m.role === "partner_manager").length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhum manager ativo ou histórico.</p>
              ) : (
                <div className="mt-4 space-y-3">
                  {estado.dados.membros
                    .filter((m) => m.role === "partner_manager")
                    .map((m) => (
                      <div key={m.id} className="rounded-xl border border-borda p-4">
                        <div className="flex flex-wrap justify-between gap-2">
                          <strong>{m.full_name}</strong>
                          <span className="text-sm">{m.status}</span>
                        </div>
                        {m.email && <p className="mt-1 text-sm text-tinta/60">{m.email}</p>}
                      </div>
                    ))}
                </div>
              )}
            </section>

            <section className="card mt-6 p-6">
              <h2 className="text-xl font-bold">Convites</h2>
              {estado.dados.convites.length === 0 ? (
                <p className="mt-3 text-sm text-tinta/60">Nenhum convite criado.</p>
              ) : (
                <div className="mt-4 space-y-3">
                  {estado.dados.convites.map((c) => {
                    const unidade = estado.dados.unidades.find((u) => u.id === c.unit_id);
                    return (
                      <div key={c.id} className="rounded-xl border border-borda p-4">
                        <div className="flex flex-wrap items-start justify-between gap-3">
                          <div>
                            <strong>{c.full_name}</strong>
                            <p className="text-sm text-tinta/60">{c.email}</p>
                            <p className="mt-1 text-xs text-tinta/50">
                              {unidade ? `Unidade: ${unidade.name}` : "Sem unidade vinculada"}
                            </p>
                          </div>
                          <div className="text-right">
                            <span className="text-sm font-semibold">
                              {STATUS_CONVITE[c.status] ?? c.status}
                            </span>
                            {c.status === "pending" && (
                              <button
                                type="button"
                                disabled={acao !== null}
                                onClick={() => void revogar(c)}
                                className="mt-2 block text-sm font-semibold text-magenta hover:underline"
                              >
                                {acao === c.id ? "Revogando..." : "Revogar"}
                              </button>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </section>
          </>
        )}
      </main>
    </>
  );
}
