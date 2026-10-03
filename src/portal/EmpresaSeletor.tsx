import { useEmpresaSelecionada } from "./empresaContexto";

/**
 * Superfícies compartilhadas da seleção de empresa.
 *
 * `EmpresaPortao` envolve uma tela do Portal e só entrega os filhos quando há
 * uma empresa válida escolhida. Carregando, erro, ausência de vínculo e
 * necessidade de escolha são estados distintos — nenhum deles é tratado como
 * "cadastre sua empresa".
 */

/** Barra discreta mostrando a empresa ativa, com troca quando há mais de uma. */
export function EmpresaAtualBarra() {
  const ctx = useEmpresaSelecionada();
  if (ctx.fase !== "pronta") return null;
  const varias = ctx.vinculos.length > 1;

  return (
    <div className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-borda bg-white/85 px-4 py-3">
      <p className="text-sm">
        <span className="text-tinta/60">Empresa ativa: </span>
        <strong>{ctx.atual.trade_name}</strong>
        <span className="text-tinta/60">
          {" · "}
          {ctx.atual.role === "partner_owner" ? "Responsável" : "Manager"}
        </span>
      </p>
      {varias && (
        <div className="flex flex-col items-start gap-1 sm:items-end">
          <button
            type="button"
            onClick={ctx.limparSelecao}
            disabled={ctx.trocaBloqueada}
            aria-describedby={ctx.trocaBloqueada ? "troca-bloqueada" : undefined}
            className="min-h-[44px] rounded-xl border border-borda px-4 py-2 text-sm font-semibold transition hover:border-tinta disabled:cursor-not-allowed disabled:opacity-50"
          >
            Trocar de empresa
          </button>
          {ctx.trocaBloqueada && (
            <p id="troca-bloqueada" className="text-xs text-tinta/70">
              Há uma operação em andamento. Aguarde a conclusão para trocar de empresa.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

/** Lista de escolha. Identifica pelo nome verificado e pelo papel, nada mais. */
export function EscolhaEmpresa() {
  const ctx = useEmpresaSelecionada();
  if (ctx.fase !== "escolher") return null;

  return (
    <section
      aria-labelledby="escolha-empresa-titulo"
      className="mt-8 rounded-3xl border border-borda bg-white p-6 sm:p-8"
    >
      <h2 id="escolha-empresa-titulo" className="text-xl font-bold">
        Escolha a empresa desta sessão
      </h2>
      {ctx.selecaoAnteriorInvalida && (
        <p
          role="status"
          className="mt-3 rounded-xl border border-amarelo/60 bg-amarelo/15 px-4 py-3 text-sm text-tinta"
        >
          A empresa que você estava usando não está mais disponível para a sua
          conta. Nada foi ativado automaticamente: confirme abaixo com qual empresa
          deseja continuar.
        </p>
      )}
      <p className="mt-2 text-sm leading-6 text-tinta/70">
        {ctx.vinculos.length === 1
          ? "Sua conta tem vínculo ativo em 1 empresa."
          : `Sua conta tem vínculo ativo em ${ctx.vinculos.length} empresas.`}{" "}
        Cada uma tem o seu próprio acesso: o que você faz em uma não vale para a
        outra.
      </p>
      <ul className="mt-5 space-y-2">
        {ctx.vinculos.map((v) => (
          <li key={v.company_id}>
            <button
              type="button"
              onClick={() => ctx.selecionar(v.company_id)}
              className="flex min-h-[44px] w-full flex-wrap items-center justify-between gap-3 rounded-2xl border border-borda px-4 py-3 text-left transition hover:border-tinta"
            >
              <span>
                <strong>{v.trade_name}</strong>
                {v.city && (
                  <span className="block text-sm text-tinta/60">
                    {v.city}
                    {v.uf ? `/${v.uf}` : ""}
                  </span>
                )}
              </span>
              <span className="rounded-full bg-papel2 px-3 py-1 text-xs font-semibold">
                {v.role === "partner_owner" ? "Responsável" : "Manager"}
              </span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}

/** Estado de erro de consulta — distinto de "não tem empresa". */
export function ErroContexto() {
  const ctx = useEmpresaSelecionada();
  if (ctx.fase !== "erro") return null;
  return (
    <section role="alert" className="mt-8 rounded-3xl border border-borda bg-white p-8 text-center">
      <p className="font-semibold">Não foi possível carregar suas empresas.</p>
      <p className="mt-2 text-sm text-tinta/70">
        Isto é uma falha de consulta, não a ausência de vínculo. Nada foi
        alterado na sua conta.
      </p>
      <button type="button" onClick={ctx.recarregar} className="btn-secondary mt-5">
        Tentar novamente
      </button>
    </section>
  );
}

/**
 * Portão por empresa. Entrega os filhos só com empresa válida escolhida, e
 * passa `geracao` para que a tela descarte dados da empresa anterior.
 */
export function EmpresaPortao({
  children,
  semVinculo,
}: {
  children: (p: {
    companyId: string;
    papel: "partner_owner" | "partner_manager";
    nome: string;
    geracao: number;
  }) => React.ReactNode;
  semVinculo?: React.ReactNode;
}) {
  const ctx = useEmpresaSelecionada();

  if (ctx.fase === "carregando") {
    return (
      <p role="status" className="mt-10 text-center text-sm text-tinta/60">
        Carregando suas empresas...
      </p>
    );
  }
  if (ctx.fase === "erro") return <ErroContexto />;
  if (ctx.fase === "sem_vinculo") return <>{semVinculo ?? null}</>;
  if (ctx.fase === "escolher") return <EscolhaEmpresa />;

  return (
    <>
      {children({
        companyId: ctx.atual.company_id,
        papel: ctx.atual.role,
        nome: ctx.atual.trade_name,
        geracao: ctx.geracao,
      })}
    </>
  );
}

/**
 * Aviso para quando uma operação já despachada termina DEPOIS de a pessoa ou a
 * sessão terem mudado de empresa. O resultado não é mostrado como sucesso nem
 * como erro da empresa atual — seria atribuí-lo à empresa errada — e o texto
 * não afirma que a operação foi cancelada, porque não foi: o servidor decide.
 */
export function AvisoOperacaoOutroContexto({ onFechar }: { onFechar: () => void }) {
  return (
    <div
      role="status"
      className="mt-5 flex flex-wrap items-start justify-between gap-3 rounded-2xl border border-amarelo/60 bg-amarelo/15 px-4 py-3 text-sm text-tinta"
    >
      <p className="max-w-xl">
        Uma operação iniciada para a empresa anterior só teve a resposta recebida
        depois da mudança de empresa. Não dá para saber por aqui em que momento o
        servidor a processou, e nada foi cancelado. O resultado não é exibido
        aqui: confira no contexto da empresa anterior antes de repeti-la.
      </p>
      <button
        type="button"
        onClick={onFechar}
        className="min-h-[44px] rounded-xl border border-borda px-4 py-2 font-semibold"
      >
        Entendi
      </button>
    </div>
  );
}
