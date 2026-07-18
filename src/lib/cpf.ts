/**
 * Validação REAL de CPF (dígitos verificadores) + máscara visual.
 * Auxiliar de frontend — a autoridade final é a função do banco.
 */

export function somenteDigitos(t: string): string {
  return (t ?? "").replace(/\D/g, "");
}

export function validarCPF(cpf: string): boolean {
  const d = somenteDigitos(cpf);
  if (d.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(d)) return false; // 111.111.111-11 etc.

  const calc = (fatia: number): number => {
    let soma = 0;
    for (let i = 0; i < fatia; i++) soma += parseInt(d[i], 10) * (fatia + 1 - i);
    const resto = (soma * 10) % 11;
    return resto === 10 ? 0 : resto;
  };

  return calc(9) === parseInt(d[9], 10) && calc(10) === parseInt(d[10], 10);
}

export function formatarCPF(valor: string): string {
  const d = somenteDigitos(valor).slice(0, 11);
  return d
    .replace(/(\d{3})(\d)/, "$1.$2")
    .replace(/(\d{3})\.(\d{3})(\d)/, "$1.$2.$3")
    .replace(/(\d{3})\.(\d{3})\.(\d{3})(\d)/, "$1.$2.$3-$4");
}
