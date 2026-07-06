interface Props {
  estoque: number;
}

/** Badge de disponibilidade: verde (> 15), amarela pulsando (1–15), escura (0). */
export default function EstoqueBadge({ estoque }: Props) {
  if (estoque === 0) {
    return (
      <span className="inline-flex items-center gap-1.5 rounded-full bg-tinta px-3 py-1 text-xs font-semibold text-white">
        Esgotado
      </span>
    );
  }
  if (estoque <= 15) {
    return (
      <span className="inline-flex items-center gap-1.5 rounded-full bg-amarelo px-3 py-1 text-xs font-semibold text-tinta">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-tinta" />
        Últimas {estoque} unidades
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-[#E8F7EE] px-3 py-1 text-xs font-semibold text-[#0B7A3E]">
      <span className="h-1.5 w-1.5 rounded-full bg-[#0B7A3E]" />
      {estoque} disponíveis
    </span>
  );
}
