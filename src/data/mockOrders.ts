import type { Order } from "../types";

export const mockOrders: Order[] = [
  {
    id: "PED-001",
    empresa: "Padaria Vitória LTDA",
    cnpj: "12.345.678/0001-90",
    estado: "ES",
    produto: "Modelo Horizonte",
    fraseCustomizada: "Pão quentinho!",
    imagemAprovada: false,
    status: "recebido",
    criadoEm: "2026-07-04",
  },
  {
    id: "PED-002",
    empresa: "Auto Peças Serra ME",
    cnpj: "98.765.432/0001-10",
    estado: "ES",
    produto: "Modelo Serra",
    fraseCustomizada: "Desde 1998",
    imagemAprovada: true,
    status: "em_producao",
    criadoEm: "2026-07-02",
  },
  {
    id: "PED-003",
    empresa: "Café Colatina SA",
    cnpj: "11.222.333/0001-44",
    estado: "ES",
    produto: "Modelo Litoral",
    fraseCustomizada: "Café de montanha",
    imagemAprovada: true,
    status: "enviado",
    criadoEm: "2026-06-28",
  },
];
