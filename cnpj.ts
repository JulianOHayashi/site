/** Validação real de CNPJ — confere os dígitos verificadores, não só o formato. */
export function validarCNPJ(input: string): boolean {
  const cnpj = input.replace(/\D/g, "");
  if (cnpj.length !== 14) return false;
  if (/^(\d)\1{13}$/.test(cnpj)) return false; // todos os dígitos iguais

  const calcDigito = (base: string, pesos: number[]): number => {
    const soma = base
      .split("")
      .reduce((acc, d, i) => acc + parseInt(d, 10) * pesos[i], 0);
    const resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  };

  const pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  const pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

  const d1 = calcDigito(cnpj.slice(0, 12), pesos1);
  const d2 = calcDigito(cnpj.slice(0, 13), pesos2);

  return d1 === parseInt(cnpj[12], 10) && d2 === parseInt(cnpj[13], 10);
}

/** Aplica a máscara 00.000.000/0000-00 enquanto o usuário digita. */
export function formatarCNPJ(input: string): string {
  const d = input.replace(/\D/g, "").slice(0, 14);
  return d
    .replace(/^(\d{2})(\d)/, "$1.$2")
    .replace(/^(\d{2})\.(\d{3})(\d)/, "$1.$2.$3")
    .replace(/\.(\d{3})(\d)/, ".$1/$2")
    .replace(/(\d{4})(\d)/, "$1-$2");
}
