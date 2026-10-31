import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, screen, waitFor, within } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderPortal, SESSAO_FALSA } from "./helpers/portalRender";

/* ------------------------------------------------------------------------- *
 * Cliente Supabase falso. Registra a ORDEM das chamadas (rpc/storage/tabela)
 * para provar o fluxo path → upload → register, e expõe `remove` só para
 * provar que ninguém o chama.
 * ------------------------------------------------------------------------- */
const ordem: string[] = [];
const rpc = vi.fn();
const upload = vi.fn();
const createSignedUrl = vi.fn();
const getPublicUrl = vi.fn();
const remove = vi.fn();
const filtros: Array<[string, unknown]> = [];
let linhaAtual: Record<string, unknown> | null = null;
let erroTabela: unknown = null;

vi.mock("../lib/supabase", () => ({
  supabase: {
    rpc: (nome: string, args: unknown) => {
      ordem.push(`rpc:${nome}`);
      return rpc(nome, args);
    },
    storage: {
      from: (bucket: string) => ({
        upload: (path: string, file: File, opts: unknown) => {
          ordem.push("storage:upload");
          return upload(bucket, path, file, opts);
        },
        createSignedUrl: (path: string, exp: number) => {
          ordem.push("storage:signed");
          return createSignedUrl(bucket, path, exp);
        },
        getPublicUrl: (...a: unknown[]) => getPublicUrl(...a),
        remove: (...a: unknown[]) => remove(...a),
      }),
    },
    from: (tabela: string) => {
      ordem.push(`from:${tabela}`);
      const q = {
        select: () => q,
        eq: (c: string, v: unknown) => {
          filtros.push([c, v]);
          return q;
        },
        maybeSingle: async () => ({ data: linhaAtual, error: erroTabela }),
        delete: () => {
          throw new Error("DELETE não deveria ser chamado");
        },
      };
      return q;
    },
  },
}));

const obterVinculosParceiro = vi.fn();
vi.mock("../hooks/usePortalSiteAuth", () => ({ usePortalSiteAuth: () => SESSAO_FALSA() }));
vi.mock("../services/partnerApplicationService", async (orig) => ({
  ...(await orig<typeof import("../services/partnerApplicationService")>()),
  obterVinculosParceiro: (...a: unknown[]) => obterVinculosParceiro(...a),
}));
vi.mock("../components/Header", () => ({ default: () => null }));

import {
  TAMANHO_MAXIMO,
  enviarImagemPersonalizacao,
  listarPedidosDaEmpresa,
  mensagemDeMotivo,
  obterImagemAtual,
  validarArquivo,
} from "../services/customizationImageService";
import PortalPedidos from "../pages/portal/PortalPedidos";
import PortalPedidoPersonalizacao from "../pages/portal/PortalPedidoPersonalizacao";
import { PortalTopo } from "../pages/portal/portalUi";

const COMPANY = "11111111-1111-4111-8111-111111111111";
const ORDER = "33333333-3333-4333-8333-333333333333";
const OUTRO_ORDER = "44444444-4444-4444-8444-444444444444";
const BUCKET = "partner-customization-images";
const PATH_1 = `${ORDER}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`;
const PATH_2 = `${ORDER}/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`;
const URL_ASSINADA = "https://exemplo.supabase.co/storage/v1/object/sign/x?token=t";

function arquivo(nome: string, tipo: string, tamanho = 2048): File {
  const f = new File([new Uint8Array(Math.min(tamanho, 4))], nome, { type: tipo });
  Object.defineProperty(f, "size", { value: tamanho });
  return f;
}

function vinculo(role: "partner_owner" | "partner_manager") {
  return {
    tipo: "ok",
    vinculos: [
      {
        company_id: COMPANY,
        trade_name: "Farmácia QA",
        company_status: "active",
        member_id: "m1",
        role,
        member_status: "active",
      },
    ],
  };
}

let temImagemNoResumo = false;
let caminhos: string[] = [];

function resumo() {
  return {
    data: {
      ok: true,
      commercial: [
        {
          order_id: ORDER,
          niche_code: "pharmacy",
          payment_status: "paid",
          has_customization_image: temImagemNoResumo,
        },
      ],
    },
    error: null,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  ordem.length = 0;
  filtros.length = 0;
  linhaAtual = null;
  erroTabela = null;
  temImagemNoResumo = false;
  caminhos = [PATH_1, PATH_2];
  obterVinculosParceiro.mockResolvedValue(vinculo("partner_owner"));
  rpc.mockImplementation(async (nome: string) => {
    if (nome === "get_my_company_commercial_summary") return resumo();
    if (nome === "request_customization_image_path") {
      return { data: { ok: true, bucket: BUCKET, storage_path: caminhos.shift() }, error: null };
    }
    if (nome === "register_customization_image") {
      return { data: { ok: true, image_id: "img-1", mime_type: "image/png", byte_size: 2048 }, error: null };
    }
    return { data: null, error: { message: "rpc inesperada" } };
  });
  upload.mockResolvedValue({ data: { path: PATH_1 }, error: null });
  createSignedUrl.mockResolvedValue({ data: { signedUrl: URL_ASSINADA }, error: null });
  // jsdom não implementa URLs de objeto.
  (URL as unknown as { createObjectURL: unknown }).createObjectURL = vi.fn(() => "blob:preview-1");
  (URL as unknown as { revokeObjectURL: unknown }).revokeObjectURL = vi.fn();
});

afterEach(() => cleanup());

/* ============================ validação local ============================ */

describe("validarArquivo", () => {
  it.each([
    ["foto.jpg", "image/jpeg"],
    ["arte.png", "image/png"],
    ["arte.webp", "image/webp"],
  ])("aceita %s", (nome, tipo) => {
    expect(validarArquivo(arquivo(nome, tipo))).toEqual({ ok: true });
  });

  it("aceita exatamente 10 MiB", () => {
    expect(validarArquivo(arquivo("a.png", "image/png", TAMANHO_MAXIMO))).toEqual({ ok: true });
  });

  it.each([
    ["contrato.pdf", "application/pdf"],
    ["logo.svg", "image/svg+xml"],
    ["sem-tipo", ""],
    ["anim.gif", "image/gif"],
  ])("rejeita %s", (nome, tipo) => {
    expect(validarArquivo(arquivo(nome, tipo))).toEqual({ ok: false, erro: "tipo" });
  });

  it("rejeita acima de 10 MiB", () => {
    expect(validarArquivo(arquivo("a.png", "image/png", TAMANHO_MAXIMO + 1))).toEqual({
      ok: false,
      erro: "tamanho",
    });
  });

  it("rejeita arquivo vazio", () => {
    expect(validarArquivo(arquivo("a.png", "image/png", 0))).toEqual({ ok: false, erro: "vazio" });
  });
});

/* ================================ envio ================================== */

describe("enviarImagemPersonalizacao", () => {
  it("pede o path ao servidor ANTES do Storage e registra só depois do upload", async () => {
    const f = arquivo("arte.png", "image/png");
    const r = await enviarImagemPersonalizacao(ORDER, f);
    expect(r).toEqual({ tipo: "ok", imageId: "img-1" });
    expect(ordem).toEqual([
      "rpc:request_customization_image_path",
      "storage:upload",
      "rpc:register_customization_image",
    ]);
    expect(rpc).toHaveBeenCalledWith("request_customization_image_path", { p_order_id: ORDER });
  });

  it("faz upload exatamente no bucket/path do servidor, com upsert:false e contentType do arquivo", async () => {
    const f = arquivo("foto.webp", "image/webp");
    await enviarImagemPersonalizacao(ORDER, f);
    expect(upload).toHaveBeenCalledTimes(1);
    expect(upload).toHaveBeenCalledWith(BUCKET, PATH_1, f, { upsert: false, contentType: "image/webp" });
    expect(rpc).toHaveBeenCalledWith("register_customization_image", {
      p_order_id: ORDER,
      p_storage_path: PATH_1,
      p_mime_type: "image/webp",
      p_byte_size: 2048,
    });
  });

  it("arquivo inválido não toca servidor nem Storage", async () => {
    for (const f of [
      arquivo("a.pdf", "application/pdf"),
      arquivo("a.svg", "image/svg+xml"),
      arquivo("a.png", "image/png", 0),
      arquivo("a.png", "image/png", TAMANHO_MAXIMO + 1),
    ]) {
      const r = await enviarImagemPersonalizacao(ORDER, f);
      expect(r.tipo).toBe("erro");
    }
    expect(ordem).toEqual([]);
  });

  it("falha no upload NÃO chama register", async () => {
    upload.mockResolvedValue({ data: null, error: { message: "network" } });
    const r = await enviarImagemPersonalizacao(ORDER, arquivo("a.png", "image/png"));
    expect(r).toEqual({ tipo: "erro", motivo: "upload_failed" });
    expect(rpc).not.toHaveBeenCalledWith("register_customization_image", expect.anything());
  });

  it("recusa do servidor ao pedir path NÃO faz upload", async () => {
    rpc.mockImplementation(async () => ({ data: { ok: false, reason: "not_authorized" }, error: null }));
    const r = await enviarImagemPersonalizacao(ORDER, arquivo("a.png", "image/png"));
    expect(r).toEqual({ tipo: "erro", motivo: "not_authorized" });
    expect(upload).not.toHaveBeenCalled();
  });

  it.each([
    ["recusa", { data: { ok: false, reason: "storage_object_not_found" }, error: null }, "storage_object_not_found"],
    ["erro de rede", { data: null, error: { message: "relation x does not exist" } }, "unexpected"],
  ])("falha no register (%s) NÃO apaga o objeto enviado", async (_n, resposta, motivo) => {
    rpc.mockImplementation(async (nome: string) =>
      nome === "request_customization_image_path"
        ? { data: { ok: true, bucket: BUCKET, storage_path: PATH_1 }, error: null }
        : resposta
    );
    const r = await enviarImagemPersonalizacao(ORDER, arquivo("a.png", "image/png"));
    expect(r).toEqual({ tipo: "erro", motivo });
    expect(remove).not.toHaveBeenCalled();
  });

  it("substituição usa um path NOVO do servidor e nunca sobrescreve o anterior", async () => {
    await enviarImagemPersonalizacao(ORDER, arquivo("v1.png", "image/png"));
    await enviarImagemPersonalizacao(ORDER, arquivo("v2.jpg", "image/jpeg"));
    expect(upload.mock.calls.map((c) => c[1])).toEqual([PATH_1, PATH_2]);
    for (const c of upload.mock.calls) expect(c[3]).toMatchObject({ upsert: false });
    const registros = rpc.mock.calls.filter((c) => c[0] === "register_customization_image");
    expect(registros.map((c) => (c[1] as { p_storage_path: string }).p_storage_path)).toEqual([PATH_1, PATH_2]);
    expect(remove).not.toHaveBeenCalled();
  });
});

/* ============================ imagem atual =============================== */

describe("obterImagemAtual", () => {
  it("lê só a versão corrente e ativa do pedido e exibe por signed URL", async () => {
    linhaAtual = {
      storage_bucket: BUCKET,
      storage_path: PATH_1,
      mime_type: "image/png",
      byte_size: 2048,
      registered_at: "2026-10-31T12:00:00Z",
    };
    const r = await obterImagemAtual(ORDER);
    expect(r).toMatchObject({ tipo: "ok", imagem: { url: URL_ASSINADA } });
    expect(filtros).toEqual([
      ["order_id", ORDER],
      ["is_current", true],
      ["status", "active"],
    ]);
    expect(createSignedUrl).toHaveBeenCalledWith(BUCKET, PATH_1, 300);
    expect(getPublicUrl).not.toHaveBeenCalled();
  });

  it("sem linha corrente → nenhuma, sem pedir URL", async () => {
    expect(await obterImagemAtual(ORDER)).toEqual({ tipo: "nenhuma" });
    expect(createSignedUrl).not.toHaveBeenCalled();
  });
});

/* ======================== pedidos e mensagens ============================ */

describe("listarPedidosDaEmpresa e mensagens", () => {
  it("bloco comercial null (manager) → sem_acesso", async () => {
    rpc.mockResolvedValue({ data: { ok: true, commercial: null }, error: null });
    expect(await listarPedidosDaEmpresa(COMPANY)).toEqual({ tipo: "sem_acesso" });
  });

  it("todo motivo conhecido tem mensagem própria; desconhecido vira mensagem genérica", () => {
    const motivos = [
      "not_authenticated",
      "not_found",
      "not_authorized",
      "order_cancelled",
      "invalid_path",
      "storage_object_not_found",
      "storage_object_not_owned",
      "invalid_metadata",
      "invalid_mime",
      "invalid_size",
      "upload_failed",
    ];
    const genérica = mensagemDeMotivo("unexpected");
    for (const m of motivos) {
      const t = mensagemDeMotivo(m);
      expect(t).not.toBe(genérica);
      expect(t).not.toMatch(/[a-z]+_[a-z]+|partner-customization|\//);
    }
    expect(mensagemDeMotivo("ERROR: duplicate key value violates")).toBe(genérica);
  });
});

/* ================================ telas ================================== */

function renderPersonalizacao(orderId = ORDER) {
  return renderPortal(
    <Routes>
      <Route path="/portal/pedidos/:orderId/personalizacao" element={<PortalPedidoPersonalizacao />} />
    </Routes>,
    { rotas: [`/portal/pedidos/${orderId}/personalizacao`] }
  );
}

function escolherArquivo(f: File) {
  fireEvent.change(screen.getByLabelText(/Escolher (nova )?imagem/), { target: { files: [f] } });
}

describe("tela de personalização", () => {
  it("owner sem imagem: estado pendente, preview local e envio até 'Imagem registrada'", async () => {
    renderPersonalizacao();
    expect(await screen.findByText("Imagem pendente")).toBeTruthy();
    expect(
      screen.getByText(/Envie a arte ou imagem que será usada como referência na personalização\./)
    ).toBeTruthy();
    const input = screen.getByLabelText("Escolher imagem") as HTMLInputElement;
    expect(input.type).toBe("file");
    expect(input.accept).toBe("image/jpeg,image/png,image/webp");
    const botao = screen.getByRole("button", { name: "Enviar imagem" }) as HTMLButtonElement;
    expect(botao.disabled).toBe(true);

    escolherArquivo(arquivo("arte-loja.png", "image/png", 1536 * 1024));
    const preview = screen.getByAltText("Pré-visualização da imagem escolhida") as HTMLImageElement;
    expect(preview.src).toBe("blob:preview-1");
    expect(screen.getByText("arte-loja.png")).toBeTruthy();
    expect(screen.getByText(/1,5 MB/)).toBeTruthy();

    // Depois do registro, a leitura volta com a imagem corrente.
    let liberar!: () => void;
    upload.mockImplementation(
      () => new Promise((ok) => (liberar = () => ok({ data: { path: PATH_1 }, error: null })))
    );
    fireEvent.click(botao);
    expect(await screen.findByRole("button", { name: "Enviando..." })).toBeTruthy();
    linhaAtual = {
      storage_bucket: BUCKET,
      storage_path: PATH_1,
      mime_type: "image/png",
      byte_size: 1536 * 1024,
      registered_at: "2026-10-31T12:00:00Z",
    };
    liberar();

    expect(await screen.findByText("Imagem enviada e registrada para este pedido.")).toBeTruthy();
    expect(await screen.findByText("Imagem registrada")).toBeTruthy();
    const atual = screen.getByAltText("Imagem atual para personalização") as HTMLImageElement;
    expect(atual.src).toBe(URL_ASSINADA);
    expect(screen.getByRole("button", { name: "Substituir imagem" })).toBeTruthy();
    expect(screen.getByText(/versões anteriores\s+ficam guardadas no histórico/)).toBeTruthy();
    expect(remove).not.toHaveBeenCalled();
  });

  it("owner com imagem: vê a atual por signed URL e o botão de substituir", async () => {
    temImagemNoResumo = true;
    linhaAtual = {
      storage_bucket: BUCKET,
      storage_path: PATH_1,
      mime_type: "image/jpeg",
      byte_size: 4096,
      registered_at: "2026-10-30T10:00:00Z",
    };
    renderPersonalizacao();
    const img = (await screen.findByAltText("Imagem atual para personalização")) as HTMLImageElement;
    expect(img.src).toBe(URL_ASSINADA);
    expect(screen.getByText("Imagem registrada")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Substituir imagem" })).toBeTruthy();
    // Nenhum path privado na tela.
    expect(document.body.textContent).not.toContain(PATH_1);
  });

  it("PDF escolhido na tela: mensagem clara e nada é enviado", async () => {
    renderPersonalizacao();
    await screen.findByText("Imagem pendente");
    escolherArquivo(arquivo("contrato.pdf", "application/pdf"));
    expect(screen.getByRole("alert").textContent).toMatch(/JPG, PNG ou WebP/);
    expect((screen.getByRole("button", { name: "Enviar imagem" }) as HTMLButtonElement).disabled).toBe(true);
    expect(rpc).not.toHaveBeenCalledWith("request_customization_image_path", expect.anything());
  });

  it("falha no registro mostra mensagem segura, sem texto cru do banco", async () => {
    rpc.mockImplementation(async (nome: string) => {
      if (nome === "get_my_company_commercial_summary") return resumo();
      if (nome === "request_customization_image_path")
        return { data: { ok: true, bucket: BUCKET, storage_path: PATH_1 }, error: null };
      return { data: null, error: { message: "permission denied for table commercial_orders" } };
    });
    renderPersonalizacao();
    await screen.findByText("Imagem pendente");
    escolherArquivo(arquivo("a.png", "image/png"));
    fireEvent.click(screen.getByRole("button", { name: "Enviar imagem" }));
    const alerta = await screen.findByRole("alert");
    expect(alerta.textContent).toBe(mensagemDeMotivo("unexpected"));
    expect(document.body.textContent).not.toMatch(/permission denied|commercial_orders/);
    expect(remove).not.toHaveBeenCalled();
  });

  it("pedido fora da empresa ativa: não oferece envio", async () => {
    renderPersonalizacao(OUTRO_ORDER);
    expect(await screen.findByText("Pedido não encontrado")).toBeTruthy();
    expect(screen.queryByLabelText(/Escolher/)).toBeNull();
    expect(rpc).not.toHaveBeenCalledWith("request_customization_image_path", expect.anything());
  });

  it("manager: nenhuma funcionalidade comercial nem botão de upload", async () => {
    obterVinculosParceiro.mockResolvedValue(vinculo("partner_manager"));
    renderPersonalizacao();
    expect(await screen.findByText("Área do responsável pela empresa")).toBeTruthy();
    expect(screen.queryByLabelText(/Escolher/)).toBeNull();
    expect(screen.queryByRole("button", { name: /Enviar imagem|Substituir imagem/ })).toBeNull();
    expect(rpc).not.toHaveBeenCalled();
    expect(upload).not.toHaveBeenCalled();
  });
});

describe("lista de pedidos e navegação", () => {
  it("owner vê o pedido com selo e link para a imagem", async () => {
    renderPortal(<PortalPedidos />);
    const item = await screen.findByRole("listitem");
    expect(within(item).getByText("Imagem pendente")).toBeTruthy();
    const link = within(item).getByRole("link", { name: "Imagem para personalização" });
    expect(link.getAttribute("href")).toBe(`/portal/pedidos/${ORDER}/personalizacao`);
  });

  it("aba 'Pedidos' só para o owner", async () => {
    const r = renderPortal(<PortalTopo titulo="T" />);
    expect(await screen.findByRole("link", { name: "Pedidos" })).toBeTruthy();
    r.unmount();

    obterVinculosParceiro.mockResolvedValue(vinculo("partner_manager"));
    renderPortal(<PortalTopo titulo="T" />);
    await screen.findByRole("link", { name: "Validar QR" });
    expect(screen.queryByRole("link", { name: "Pedidos" })).toBeNull();
  });

  it("manager na lista: sem pedidos e sem consulta comercial", async () => {
    obterVinculosParceiro.mockResolvedValue(vinculo("partner_manager"));
    renderPortal(<PortalPedidos />);
    expect(await screen.findByText("Área do responsável pela empresa")).toBeTruthy();
    expect(rpc).not.toHaveBeenCalled();
  });
});
