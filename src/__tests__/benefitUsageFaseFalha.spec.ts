import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const getSession = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: (...a: unknown[]) => getSession(...a) } },
  supabaseConfigurado: true,
}));

import {
  enviarUsoDeBeneficio,
  enviarUsoDeBeneficioPorCodigo,
} from "../services/benefitUsageService";

/**
 * CLASSIFICAÇÃO DA FALHA POR CAMINHO DE EXECUÇÃO.
 *
 * `fase` decide se um QR já consumido pode voltar a ser usado, então precisa
 * refletir o código de verdade, não uma suposição. A regra é fail-closed:
 * só vale `pre_despacho` quando a função retorna ANTES do fetch; qualquer
 * desfecho a partir do envio é `indeterminado`, porque do navegador não se
 * prova que o servidor nada criou.
 *
 * Estes testes exercitam o serviço real com `fetch` simulado — não o
 * componente —, que é onde a classificação nasce.
 */
const QR = {
  publicLookupId: "11111111-2222-4333-8444-555555555555",
  rawSecret: "a".repeat(64),
  unitId: "u-1",
  physicalPhotoIdChecked: true as const,
};
const CODIGO = { displayCode: "ABCD7K2M", unitId: "u-1", physicalPhotoIdChecked: true as const };

const envios = [
  ["enviarUsoDeBeneficio (QR)", () => enviarUsoDeBeneficio(QR)],
  ["enviarUsoDeBeneficioPorCodigo", () => enviarUsoDeBeneficioPorCodigo(CODIGO)],
] as const;

const resposta = (corpo: unknown, ok = true, status = 200) =>
  ({ ok, status, json: async () => corpo }) as unknown as Response;

beforeEach(() => {
  vi.clearAllMocks();
  getSession.mockResolvedValue({ data: { session: { access_token: "t" } } });
});
afterEach(() => vi.unstubAllGlobals());

describe("falhas PROVADAMENTE anteriores ao despacho", () => {
  for (const [nome, chamar] of envios) {
    it(`${nome}: sem sessão retorna pre_despacho e não chama fetch`, async () => {
      const f = vi.fn();
      vi.stubGlobal("fetch", f);
      getSession.mockResolvedValue({ data: { session: null } });

      const r = await chamar();
      expect(r).toEqual({ tipo: "erro", codigo: "not_authenticated", fase: "pre_despacho" });
      // A prova de que nada foi despachado: fetch nunca foi chamado.
      expect(f).not.toHaveBeenCalled();
    });

    it(`${nome}: sem conferência de documento retorna pre_despacho e não chama fetch`, async () => {
      const f = vi.fn();
      vi.stubGlobal("fetch", f);
      const r = nome.startsWith("enviarUsoDeBeneficioPorCodigo")
        ? await enviarUsoDeBeneficioPorCodigo({
            ...CODIGO,
            physicalPhotoIdChecked: false as never,
          })
        : await enviarUsoDeBeneficio({ ...QR, physicalPhotoIdChecked: false as never });
      expect(r).toEqual({
        tipo: "erro",
        codigo: "photo_id_check_required",
        fase: "pre_despacho",
      });
      expect(f).not.toHaveBeenCalled();
    });
  }
});

describe("falhas INDETERMINADAS — o POST pode ter sido processado", () => {
  for (const [nome, chamar] of envios) {
    it(`${nome}: fetch rejeitado é indeterminado, não pre_despacho`, async () => {
      // Um fetch rejeitado NÃO prova que a requisição não chegou: a conexão
      // pode ter caído depois de o servidor receber e processar o POST.
      vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
      const r = await chamar();
      expect(r).toEqual({ tipo: "erro", codigo: "network_error", fase: "indeterminado" });
    });

    it(`${nome}: corpo ilegível é indeterminado`, async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => {
          throw new SyntaxError("Unexpected token");
        },
      } as unknown as Response));
      const r = await chamar();
      expect(r).toEqual({ tipo: "erro", codigo: "unexpected_error", fase: "indeterminado" });
    });

    it(`${nome}: 500 do servidor é indeterminado`, async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
        resposta({ ok: false, code: "internal_error" }, false, 500)
      ));
      const r = await chamar();
      expect(r).toEqual({ tipo: "erro", codigo: "internal_error", fase: "indeterminado" });
    });

    it(`${nome}: recusa de negócio devolvida pelo servidor é indeterminada`, async () => {
      // O servidor respondeu, mas daqui não se prova que nada foi criado no
      // App antes da recusa. Fail-closed.
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
        resposta({ ok: false, code: "request_denied" }, true, 200)
      ));
      const r = await chamar();
      expect(r).toEqual({ tipo: "erro", codigo: "request_denied", fase: "indeterminado" });
    });

    it(`${nome}: 200 sem code reconhecível é indeterminado`, async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(resposta({ ok: false })));
      const r = await chamar();
      expect(r).toEqual({ tipo: "erro", codigo: "unexpected_error", fase: "indeterminado" });
    });
  }

  it("nenhum caminho pós-fetch pode ser classificado como pre_despacho", async () => {
    const cenarios = [
      vi.fn().mockRejectedValue(new TypeError("boom")),
      vi.fn().mockResolvedValue({ ok: true, json: async () => { throw new Error("x"); } } as unknown as Response),
      vi.fn().mockResolvedValue(resposta({ ok: false, code: "qualquer" }, false, 503)),
    ];
    for (const f of cenarios) {
      vi.stubGlobal("fetch", f);
      const r = await enviarUsoDeBeneficio(QR);
      expect(r.tipo).toBe("erro");
      if (r.tipo === "erro") expect(r.fase).not.toBe("pre_despacho");
    }
  });
});

describe("o segredo do QR só viaja no corpo da requisição autorizada", () => {
  it("vai no corpo do POST, nunca na URL", async () => {
    const f = vi.fn().mockResolvedValue(
      resposta({ ok: true, request_correlation_id: "corr-1", app_status: "awaiting_user_confirmation" })
    );
    vi.stubGlobal("fetch", f);
    await enviarUsoDeBeneficio(QR);

    const [url, init] = f.mock.calls[0] as [string, RequestInit];
    expect(url).not.toContain(QR.rawSecret);
    expect(init.method).toBe("POST");
    expect(String(init.body)).toContain(QR.rawSecret);
    expect(JSON.stringify(init.headers)).not.toContain(QR.rawSecret);
  });
});
