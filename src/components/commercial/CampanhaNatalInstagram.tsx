/**
 * Atendimento de Natal: o Instagram é apenas o canal de contato e envio dos
 * contratos. A assinatura é posterior e ocorre por documento físico ou
 * eletrônico. Nenhuma ação de reserva, pagamento ou assinatura é iniciada aqui.
 */
export default function CampanhaNatalInstagram() {
  return (
    <section
      className="card mt-6 overflow-hidden"
      aria-labelledby="campanha-natal-titulo"
      data-testid="campanha-natal-instagram"
    >
      <div aria-hidden="true" className="h-1 bg-marca" />
      <div className="p-6">
        <p className="text-xs font-semibold uppercase tracking-wide text-magenta">
          Campanha de Natal · SmallFlags
        </p>
        <h2 id="campanha-natal-titulo" className="mt-2 text-xl font-bold">
          Solicite seu contrato de Natal pelo Instagram
        </h2>
        <p className="mt-3 text-sm leading-6 text-tinta/75">
          Para a campanha de Natal, o atendimento comercial e o envio dos
          contratos são realizados diretamente por nossa equipe no Instagram{" "}
          <strong>@smallflags</strong>.
        </p>
        <p className="mt-2 text-sm leading-6 text-tinta/75">
          Após o atendimento, você poderá analisar o contrato e assiná-lo
          posteriormente por documento físico ou eletrônico.
        </p>
        <a
          href="https://www.instagram.com/smallflags/"
          target="_blank"
          rel="noopener noreferrer"
          className="btn-primary mt-5 inline-flex w-full flex-wrap items-center justify-center gap-2 text-center sm:w-auto"
        >
          Solicitar contrato pelo Instagram
          <span className="font-normal opacity-90">@smallflags</span>
        </a>
        <p className="mt-3 text-xs leading-5 text-tinta/60">
          O contato pelo Instagram não constitui reserva, contratação ou
          assinatura. As condições comerciais e a formalização do contrato
          dependem de confirmação pela SmallFlags.
        </p>
      </div>
    </section>
  );
}
