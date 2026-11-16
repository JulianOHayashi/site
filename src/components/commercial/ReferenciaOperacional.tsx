/**
 * Referência operacional apresentada ao parceiro.
 *
 * O Site EXPLICA a referência da operação, mas não a administra. A jornada
 * dos usuários e o ciclo operacional pertencem ao aplicativo SmallFlags. Nenhuma
 * tela de escala ou participantes é criada aqui.
 */
export default function ReferenciaOperacional() {
  const itens = [
    "84 usuários-produto na operação de referência",
    "Seis posições comerciais",
    "Referência de 28 dias de operação",
    "Supermercado: capacidade de 24",
    "Demais nichos: capacidade de 12 cada",
    "Supermercado: referência de 8 dias",
    "Demais nichos: referência de 4 dias cada",
    "Sete participações potenciais por usuário: duas no supermercado e uma em cada uma das outras cinco posições",
    "Liberação progressiva",
    "Execução administrada pelo aplicativo SmallFlags",
  ];

  return (
    <section className="card p-6">
      <h2 className="text-xl">Referência operacional</h2>
      <ul className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
        {itens.map((t) => (
          <li key={t} className="flex items-start gap-2">
            <span aria-hidden className="mt-0.5 text-magenta">
              •
            </span>
            <span className="text-tinta/70">{t}</span>
          </li>
        ))}
      </ul>
      <p className="mt-4 rounded-xl border border-ciano/40 bg-ciano/5 px-4 py-3 text-sm text-tinta/70">
        O Site administra a exclusividade comercial. A jornada dos usuários e o
        ciclo operacional são administrados pelo aplicativo SmallFlags.
      </p>
    </section>
  );
}
