import type { Product } from "../types";

// ⚠️ PLACEHOLDER — nomes, descrições, preços e frases fixas A DEFINIR pelo dono.
export const mockProducts: Product[] = [
  {
    id: "1",
    slug: "horizonte",
    nome: "Modelo Horizonte",
    descricao:
      "Camisa em tamanho único com área de estampa horizontal de 49×30cm. Base branca, ideal para logotipos amplos e artes panorâmicas.",
    preco: 89.9,
    frase_fixa: "Feito no Espírito Santo",
    cor_base: "#FFFFFF",
    estoque: 100,
    ativo: true,
  },
  {
    id: "2",
    slug: "litoral",
    nome: "Modelo Litoral",
    descricao:
      "Camisa em tamanho único com área de estampa horizontal de 49×30cm. Base azul-clara, tecido leve.",
    preco: 94.9,
    frase_fixa: "Feito no Espírito Santo",
    cor_base: "#EAF6FB",
    estoque: 12,
    ativo: true,
  },
  {
    id: "3",
    slug: "serra",
    nome: "Modelo Serra",
    descricao:
      "Camisa em tamanho único com área de estampa horizontal de 49×30cm. Base escura para artes de alto contraste.",
    preco: 99.9,
    frase_fixa: "Feito no Espírito Santo",
    cor_base: "#17121F",
    estoque: 0,
    ativo: true,
  },
];
