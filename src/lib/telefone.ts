/** Telefone brasileiro: máscara visual + validação auxiliar (DDD + 10/11 dígitos). */

export function formatarTelefone(valor: string): string {
  const d = (valor ?? "").replace(/\D/g, "").slice(0, 11);
  if (d.length <= 10)
    return d
      .replace(/(\d{2})(\d)/, "($1) $2")
      .replace(/(\d{4})(\d{1,4})$/, "$1-$2");
  return d
    .replace(/(\d{2})(\d)/, "($1) $2")
    .replace(/(\d{5})(\d{1,4})$/, "$1-$2");
}

export function validarTelefoneBr(valor: string): boolean {
  const d = (valor ?? "").replace(/\D/g, "");
  if (d.length !== 10 && d.length !== 11) return false;
  const ddd = parseInt(d.slice(0, 2), 10);
  if (ddd < 11 || ddd > 99) return false;
  if (d.length === 11 && d[2] !== "9") return false; // celular começa com 9
  return true;
}
