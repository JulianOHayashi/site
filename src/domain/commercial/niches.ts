import type { CommercialNiche, CommercialNicheCode } from "./types";

/**
 * Fonte canônica dos nichos NO FRONTEND — apenas para apresentação:
 * nomes, ordem visual, descrições curtas e ícones.
 *
 * NÃO é autoridade sobre quantidade contratual, preço, disponibilidade,
 * status ou formação concluída. A quantidade REAL exibida vem sempre da
 * resposta server-side (get_current_commercial_formation).
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

const POR_CODIGO: Record<CommercialNicheCode, CommercialNiche> = NICHES.reduce(
  (acc, n) => {
    acc[n.code] = n;
    return acc;
  },
  {} as Record<CommercialNicheCode, CommercialNiche>
);

export function nicheByCode(code: CommercialNicheCode): CommercialNiche {
  return POR_CODIGO[code];
}

/**
 * Type guard canônico do código interno de nicho.
 *
 * Aceita `unknown` (respostas server-side chegam sem tipo) e confirma, por
 * pertencimento explícito, se o valor é um dos seis códigos canônicos. É a
 * única fonte de verdade para "isto é um CommercialNicheCode?"; nada de
 * casting (`x as CommercialNicheCode`) fora daqui.
 */
export function isCommercialNicheCode(
  value: unknown
): value is CommercialNicheCode {
  return typeof value === "string" && value in POR_CODIGO;
}

/** Alias histórico mantido para compatibilidade de importações. */
export const isNicheCode = isCommercialNicheCode;

/**
 * Mapeamento EXPLÍCITO e tipado entre o código interno canônico (underscore)
 * e o slug público (hífen). É a fonte canônica das URLs — nunca derivamos o
 * slug com um replaceAll("_", "-") solto.
 */
export const NICHE_SLUG_BY_CODE: Record<CommercialNicheCode, string> = {
  supermarket: "supermarket",
  pharmacy: "pharmacy",
  womens_clothing: "womens-clothing",
  mens_clothing: "mens-clothing",
  womens_footwear: "womens-footwear",
  mens_footwear: "mens-footwear",
} as const;

/** Mapeamento inverso: slug público (hífen) → código interno canônico. */
export const NICHE_CODE_BY_SLUG: Record<string, CommercialNicheCode> =
  Object.entries(NICHE_SLUG_BY_CODE).reduce((acc, [code, slug]) => {
    acc[slug] = code as CommercialNicheCode;
    return acc;
  }, {} as Record<string, CommercialNicheCode>);

/** Código interno → slug público canônico (com hífen). */
export function slugByCode(code: CommercialNicheCode): string {
  return NICHE_SLUG_BY_CODE[code];
}

/**
 * Slug público canônico → código interno. Aceita SOMENTE o slug canônico
 * (com hífen). Retorna null para qualquer valor desconhecido — sem casting,
 * sem inferência por substituição de caracteres.
 */
export function nicheCodeFromSlug(slug: string): CommercialNicheCode | null {
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
