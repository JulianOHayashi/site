/**
 * Tipos de benefício OPERACIONAIS do App (sete) e sua origem COMERCIAL no
 * Site (seis nichos).
 *
 * Existe UM único parceiro de supermercado, UM nicho comercial de
 * supermercado, UM Pedido de Exclusividade e UM pool contratual de
 * supermercado. As duas etapas de supermercado são divisões OPERACIONAIS
 * dentro do App e apontam para a MESMA origem comercial.
 *
 * NUNCA criar supermarket_stage_1 / supermarket_stage_2 como nichos
 * comerciais do Site.
 *
 * Os códigos de nicho seguem a convenção real do repositório
 * (womens_clothing, mens_footwear, ...), não a grafia conceitual do
 * documento de decisão.
 */

export const COMMERCIAL_NICHES = [
  "supermarket",
  "pharmacy",
  "womens_clothing",
  "mens_clothing",
  "womens_footwear",
  "mens_footwear",
] as const;
export type CommercialNiche = (typeof COMMERCIAL_NICHES)[number];

export const BENEFIT_TYPES = [
  "supermarket_stage_1",
  "supermarket_stage_2",
  "pharmacy",
  "womens_clothing",
  "mens_clothing",
  "womens_footwear",
  "mens_footwear",
] as const;
export type BenefitType = (typeof BENEFIT_TYPES)[number];

/** Origem comercial de cada benefício operacional. */
export const COMMERCIAL_ORIGIN: Record<BenefitType, CommercialNiche> = {
  supermarket_stage_1: "supermarket",
  supermarket_stage_2: "supermarket",
  pharmacy: "pharmacy",
  womens_clothing: "womens_clothing",
  mens_clothing: "mens_clothing",
  womens_footwear: "womens_footwear",
  mens_footwear: "mens_footwear",
};

export const SUPERMARKET_STAGES: BenefitType[] = [
  "supermarket_stage_1",
  "supermarket_stage_2",
];

export function isSupermarketStage(b: BenefitType): boolean {
  return COMMERCIAL_ORIGIN[b] === "supermarket";
}

/** Capacidade nominal por etapa de calendário. */
export const NOMINAL_CAPACITY: Record<CommercialNiche, number> = {
  supermarket: 24,
  pharmacy: 12,
  womens_clothing: 12,
  mens_clothing: 12,
  womens_footwear: 12,
  mens_footwear: 12,
};
