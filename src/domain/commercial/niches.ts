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

export function isNicheCode(value: string): value is CommercialNicheCode {
  return value in POR_CODIGO;
}

/**
 * Normaliza um slug de rota para o código canônico do nicho.
 *
 * O código canônico usa underscore (womens_clothing), mas as URLs podem
 * chegar com hífen (womens-clothing). Esta função aceita as duas formas e
 * devolve o código canônico, ou null se não corresponder a um nicho.
 * Não altera o domínio: o código de autoridade continua com underscore.
 */
export function nicheCodeFromRoute(slug: string): CommercialNicheCode | null {
  const canonico = slug.trim().toLowerCase().replace(/-/g, "_");
  return isNicheCode(canonico) ? canonico : null;
}
