import type {
  CommercialNiche,
  CommercialNicheCode,
  FormationNicheCode,
  LegacyCommercialNicheCode,
} from "./types";

/**
 * Fonte canônica das POSIÇÕES comerciais NO FRONTEND — apenas para
 * apresentação: nomes, ordem visual, descrições curtas e ícones.
 *
 * NÃO é autoridade sobre quantidade contratual, preço, disponibilidade,
 * segmento, status ou formação concluída. A quantidade REAL exibida vem
 * sempre da resposta server-side (get_current_commercial_formation), e quem
 * aceita ou recusa um segmento é o servidor.
 *
 * Seis posições, 84 unidades (migration 20261103120000): Calçados é uma
 * posição única e Outros é a posição de segmento variável.
 */
export const NICHES: readonly CommercialNiche[] = [
  {
    code: "supermarket",
    displayName: "Supermercado",
    sortOrder: 1,
    shortDescription: "Rede de supermercados da região.",
    icon: "🛒",
  },
  {
    code: "pharmacy",
    displayName: "Farmácia",
    sortOrder: 2,
    shortDescription: "Farmácias e drogarias da região.",
    icon: "💊",
  },
  {
    code: "womens_clothing",
    displayName: "Roupas femininas",
    sortOrder: 3,
    shortDescription: "Moda feminina da região.",
    icon: "👗",
  },
  {
    code: "mens_clothing",
    displayName: "Roupas masculinas",
    sortOrder: 4,
    shortDescription: "Moda masculina da região.",
    icon: "👔",
  },
  {
    code: "footwear",
    displayName: "Calçados",
    sortOrder: 5,
    shortDescription: "Lojas de calçados da região.",
    icon: "👟",
  },
  {
    code: "others",
    displayName: "Outros",
    sortOrder: 6,
    shortDescription:
      "Outro segmento comercial autorizado pela SmallFlags, como papelaria, pet shop ou material de construção.",
    icon: "🏷️",
  },
] as const;

/**
 * Posições HISTÓRICAS. Só para exibir pedidos antigos e para a vitrine não
 * quebrar enquanto o backend ainda não recebeu a migration. Nunca entram na
 * lista de opções de compra.
 */
export const LEGACY_NICHES: readonly CommercialNiche[] = [
  {
    code: "womens_footwear",
    displayName: "Calçados femininos",
    sortOrder: 5,
    shortDescription: "Calçados femininos da região.",
    icon: "👠",
  },
  {
    code: "mens_footwear",
    displayName: "Calçados masculinos",
    sortOrder: 6,
    shortDescription: "Calçados masculinos da região.",
    icon: "👞",
  },
] as const;

const POR_CODIGO: Record<FormationNicheCode, CommercialNiche> = [
  ...NICHES,
  ...LEGACY_NICHES,
].reduce(
  (acc, n) => {
    acc[n.code] = n;
    return acc;
  },
  {} as Record<FormationNicheCode, CommercialNiche>
);

const ATIVOS = new Set<string>(NICHES.map((n) => n.code));
const LEGADOS = new Set<string>(LEGACY_NICHES.map((n) => n.code));

export function nicheByCode(code: FormationNicheCode): CommercialNiche {
  return POR_CODIGO[code];
}

/**
 * Type guard canônico do código de posição ATIVO.
 *
 * Aceita `unknown` (respostas server-side chegam sem tipo) e confirma, por
 * pertencimento explícito, se o valor é uma das seis posições atuais. Nada de
 * casting (`x as CommercialNicheCode`) fora daqui.
 */
export function isCommercialNicheCode(
  value: unknown
): value is CommercialNicheCode {
  return typeof value === "string" && ATIVOS.has(value);
}

/** Código histórico de calçados (F/M), anterior à unificação. */
export function isLegacyNicheCode(
  value: unknown
): value is LegacyCommercialNicheCode {
  return typeof value === "string" && LEGADOS.has(value);
}

/** Qualquer código de posição que a formação pode devolver. */
export function isFormationNicheCode(value: unknown): value is FormationNicheCode {
  return isCommercialNicheCode(value) || isLegacyNicheCode(value);
}

/** Alias histórico mantido para compatibilidade de importações. */
export const isNicheCode = isCommercialNicheCode;

/**
 * Posições que podem ser ocupadas por um segmento de Outros. Supermercado
 * NUNCA. Apresentação apenas: o servidor repete e decide a regra.
 */
export const SEGMENT_POSITION_CODES: readonly CommercialNicheCode[] = [
  "pharmacy",
  "womens_clothing",
  "mens_clothing",
  "footwear",
  "others",
] as const;

export function positionAcceptsSegment(code: FormationNicheCode): boolean {
  return (SEGMENT_POSITION_CODES as readonly string[]).includes(code);
}

export function positionRequiresSegment(code: FormationNicheCode): boolean {
  return code === "others";
}

/**
 * Mapeamento EXPLÍCITO e tipado entre o código interno canônico (underscore)
 * e o slug público (hífen). É a fonte canônica das URLs — nunca derivamos o
 * slug com um replaceAll("_", "-") solto.
 */
export const NICHE_SLUG_BY_CODE: Record<FormationNicheCode, string> = {
  supermarket: "supermarket",
  pharmacy: "pharmacy",
  womens_clothing: "womens-clothing",
  mens_clothing: "mens-clothing",
  footwear: "footwear",
  others: "others",
  // Históricos: o link antigo continua resolvendo (e a tela leva a Calçados
  // quando o servidor já não tiver a posição antiga).
  womens_footwear: "womens-footwear",
  mens_footwear: "mens-footwear",
} as const;

/** Mapeamento inverso: slug público (hífen) → código interno. */
export const NICHE_CODE_BY_SLUG: Record<string, FormationNicheCode> =
  Object.entries(NICHE_SLUG_BY_CODE).reduce((acc, [code, slug]) => {
    acc[slug] = code as FormationNicheCode;
    return acc;
  }, {} as Record<string, FormationNicheCode>);

/** Código interno → slug público canônico (com hífen). */
export function slugByCode(code: FormationNicheCode): string {
  return NICHE_SLUG_BY_CODE[code];
}

/**
 * Slug público canônico → código interno. Aceita SOMENTE o slug canônico
 * (com hífen). Retorna null para qualquer valor desconhecido — sem casting,
 * sem inferência por substituição de caracteres.
 */
export function nicheCodeFromSlug(slug: string): FormationNicheCode | null {
  const s = slug.trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(NICHE_CODE_BY_SLUG, s)
    ? NICHE_CODE_BY_SLUG[s]
    : null;
}

/**
 * URL legada com underscore → slug público canônico (hífen), para permitir
 * um redirecionamento interno único. Retorna o slug canônico apenas quando o
 * valor bruto, ao trocar "_" por "-", corresponde a um slug canônico E não é
 * já o próprio slug canônico (evita loop de redirecionamento). Caso contrário
 * retorna null e o chamador trata como código inválido.
 */
export function canonicalSlugFromLegacy(raw: string): string | null {
  const bruto = raw.trim().toLowerCase();
  if (nicheCodeFromSlug(bruto)) return null; // já é canônico → não redireciona
  const comHifen = bruto.replace(/_/g, "-");
  const code = nicheCodeFromSlug(comHifen);
  return code ? slugByCode(code) : null;
}
