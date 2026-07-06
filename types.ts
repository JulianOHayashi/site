export interface Product {
  id: string;
  slug: string;
  nome: string;
  descricao: string;
  preco: number; // ⚠️ valores provisórios — A DEFINIR
  frase_fixa: string; // ⚠️ definida pelo dono — A DEFINIR
  cor_base: string;
  estoque: number;
  ativo: boolean;
}

export type OrderStatus = "recebido" | "em_producao" | "enviado";

export interface Order {
  id: string;
  empresa: string;
  cnpj: string;
  estado: string;
  produto: string;
  fraseCustomizada: string;
  imagemAprovada: boolean;
  status: OrderStatus;
  criadoEm: string;
}

/** Dados que fluem da personalização para o checkout */
export interface Customization {
  productSlug: string;
  imagemUrl: string | null;
  fraseCustomizada: string;
}
