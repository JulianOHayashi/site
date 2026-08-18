/**
 * Validação local do formulário de cadastro de parceiro.
 *
 * Existe para retorno imediato ao usuário. NÃO é autoridade: o banco
 * revalida tudo (constraints + RPC). Espelha as regras server-side para
 * evitar divergência silenciosa.
 */

export function somenteDigitos(valor: string): string {
  return valor.replace(/\D/g, "");
}

/** Validação real de CNPJ, incluindo dígitos verificadores. */
export function cnpjValido(entrada: string): boolean {
  const c = somenteDigitos(entrada);
  if (c.length !== 14) return false;
  if (/^(\d)\1{13}$/.test(c)) return false;

  const calc = (tamanho: number): number => {
    let soma = 0;
    let peso = tamanho - 7;
    for (let i = 0; i < tamanho; i += 1) {
      soma += Number(c[i]) * peso;
      peso -= 1;
      if (peso < 2) peso = 9;
    }
    const resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  };

  return calc(12) === Number(c[12]) && calc(13) === Number(c[13]);
}

/** Validação real de CPF, incluindo dígitos verificadores. */
export function cpfValido(entrada: string): boolean {
  const c = somenteDigitos(entrada);
  if (c.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(c)) return false;

  const calc = (tamanho: number): number => {
    let soma = 0;
    for (let i = 0; i < tamanho; i += 1) soma += Number(c[i]) * (tamanho + 1 - i);
    const resto = (soma * 10) % 11;
    return resto === 10 ? 0 : resto;
  };

  return calc(9) === Number(c[9]) && calc(10) === Number(c[10]);
}

export function emailValido(valor: string): boolean {
  const v = valor.trim().toLowerCase();
  return v.length <= 320 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v);
}

export function telefoneValido(valor: string): boolean {
  if (valor.trim() === "") return true;
  const d = somenteDigitos(valor);
  return d.length >= 10 && d.length <= 13;
}

export function cepValido(valor: string): boolean {
  if (valor.trim() === "") return true;
  return somenteDigitos(valor).length === 8;
}

export type ErrosFormulario = Record<string, string>;

export type CamposFormulario = {
  cnpj: string;
  legal_name: string;
  trade_name: string;
  contact_email: string;
  contact_phone: string;
  postal_code: string;
  street: string;
  street_number: string;
  district: string;
  city: string;
  uf: string;
  representative_full_name: string;
  representative_cpf: string;
  representative_email: string;
  representative_phone: string;
};

export function validarFormulario(campos: CamposFormulario): ErrosFormulario {
  const erros: ErrosFormulario = {};

  if (!cnpjValido(campos.cnpj)) erros.cnpj = "Informe um CNPJ válido.";
  if (campos.legal_name.trim().length < 2) erros.legal_name = "Informe a razão social.";
  if (!emailValido(campos.contact_email)) erros.contact_email = "Informe um e-mail válido.";
  if (!telefoneValido(campos.contact_phone)) erros.contact_phone = "Telefone inválido.";
  if (!cepValido(campos.postal_code)) erros.postal_code = "CEP inválido.";
  if (campos.city.trim().length < 2) erros.city = "Informe a cidade.";
  if (campos.uf.trim().length !== 2) erros.uf = "Selecione a UF.";
  if (campos.representative_full_name.trim().length < 3)
    erros.representative_full_name = "Informe o nome completo do responsável.";
  if (!cpfValido(campos.representative_cpf))
    erros.representative_cpf = "Informe um CPF válido.";
  if (campos.representative_email.trim() !== "" && !emailValido(campos.representative_email))
    erros.representative_email = "E-mail do responsável inválido.";
  if (!telefoneValido(campos.representative_phone))
    erros.representative_phone = "Telefone do responsável inválido.";

  return erros;
}
