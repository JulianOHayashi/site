/**
 * Consulta pública e read-only da disponibilidade do fluxo de pagamento.
 *
 * Fail-closed: erro de rede, resposta inválida ou qualquer status inesperado
 * significa indisponível. O navegador nunca recebe detalhe de credencial.
 */

export type DisponibilidadePagamento =
  | { tipo: "disponivel" }
  | { tipo: "indisponivel" };

export async function obterDisponibilidadePagamento(): Promise<DisponibilidadePagamento> {
  let resposta: Response;
  try {
    resposta = await fetch("/api/payments/availability", {
      method: "GET",
      headers: { Accept: "application/json" },
    });
  } catch {
    return { tipo: "indisponivel" };
  }

  if (!resposta.ok) return { tipo: "indisponivel" };

  try {
    const corpo = (await resposta.json()) as Record<string, unknown>;
    return corpo?.ok === true && corpo.payment_available === true
      ? { tipo: "disponivel" }
      : { tipo: "indisponivel" };
  } catch {
    return { tipo: "indisponivel" };
  }
}
