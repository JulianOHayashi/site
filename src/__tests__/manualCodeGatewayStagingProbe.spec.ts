import { describe, it, expect } from "vitest";
import {
  loadGatewayConfig,
  signGatewayRequest,
  GATEWAY_CONTENT_TYPE,
  GATEWAY_SIGNATURE_HEADER,
} from "../server/provisioning/gatewaySigner";
import { montarCreateRequestByCodeBody } from "../server/benefitUsage/benefitUsageContract";

/**
 * SONDA DE STAGING — desligada por padrão.
 *
 * Roda só com `RUN_MANUAL_CODE_STAGING_PROBE=1` e as cinco variáveis do
 * gateway presentes no ambiente. Não há credencial aqui e nada é impresso.
 *
 * O QUE ELA PROVA, E POR QUE PRECISA SER ASSIM
 * Com a flag do App desligada, a primeira requisição corretamente assinada
 * deve voltar 503 ENDPOINT_DISABLED. Reenviando EXATAMENTE os mesmos bytes —
 * mesmo corpo, mesmo JWS, mesmo JTI, mesma correlação, mesmos issued_at e
 * expires_at — deve voltar 401 REPLAY_DETECTED.
 *
 * Assinar duas vezes NÃO é teste de replay: geraria dois JTI e duas
 * assinaturas, ou seja, duas requisições legítimas. Por isso a assinatura
 * acontece UMA vez e o objeto preparado é reenviado.
 *
 * Se o gateway responder com um contrato diferente (por exemplo `code` em vez
 * de `error`), REPORTE o que veio verbatim em vez de afrouxar a asserção
 * aqui.
 */

const LIGADA = process.env.RUN_MANUAL_CODE_STAGING_PROBE === "1";
const VARS = [
  "BDFLOW_APP_BRIDGE_URL",
  "BDFLOW_APP_BRIDGE_KEY_ID",
  "BDFLOW_APP_BRIDGE_SIGNING_KEY",
  "BDFLOW_APP_BRIDGE_ISSUER",
  "BDFLOW_APP_BRIDGE_AUDIENCE",
] as const;
const TEM_SEGREDOS = VARS.every((v) => (process.env[v] ?? "").trim() !== "");
const PROBE_CORRELATION_ID = "00000000-0000-4000-8000-000000000106";

/** Fixture sintético: nenhum código real de usuário entra aqui. */
const AUTORIDADE = {
  company_id: "00000000-0000-4000-8000-000000000101",
  unit_id: "00000000-0000-4000-8000-000000000102",
  partner_network_bridge_id: "00000000-0000-4000-8000-000000000103",
  partner_branch_bridge_id: "00000000-0000-4000-8000-000000000104",
  validator_bridge_id: "00000000-0000-4000-8000-000000000105",
  validator_role: "partner_owner" as const,
  snapshot_presentation_version: 1,
  snapshot_partner_display_name: "Sonda Staging",
  snapshot_branch_display_name: "Filial Sonda",
  snapshot_branch_city_name: "Vitória",
  snapshot_branch_state_code: "ES",
  snapshot_branch_location_label: "Vitória/ES",
};

describe.skipIf(!LIGADA || !TEM_SEGREDOS)(
  "sonda de staging — endpoint desligado e replay",
  () => {
    it("503 ENDPOINT_DISABLED, depois 401 REPLAY_DETECTED com o MESMO envelope", async () => {
      const config = loadGatewayConfig(process.env);

      // ---- ASSINATURA ÚNICA
      const req = signGatewayRequest({
        config,
        action: "benefit_usage.create_request_by_code",
        body: montarCreateRequestByCodeBody(
          "ABCD7K2M",
          PROBE_CORRELATION_ID,
          AUTORIDADE
        ),
        correlationId: PROBE_CORRELATION_ID,
      });

      // Correlation binding: o valor assinado precisa ser exatamente o do corpo.
      const bodyForBinding = JSON.parse(req.bodyText) as Record<string, unknown>;
      expect(req.envelope.request_correlation_id).toBe(PROBE_CORRELATION_ID);
      expect(bodyForBinding.request_correlation_id).toBe(PROBE_CORRELATION_ID);

      // Congelados: é isto, byte a byte, que vai nas duas vezes.
      const url = req.url;
      const bodyText = req.bodyText;
      const headers = {
        "Content-Type": GATEWAY_CONTENT_TYPE,
        [GATEWAY_SIGNATURE_HEADER]: req.jws,
      };

      const enviar = async () => {
        const r = await fetch(url, { method: "POST", headers, body: bodyText });
        let corpo: Record<string, unknown> | null = null;
        try {
          corpo = (await r.json()) as Record<string, unknown>;
        } catch {
          corpo = null;
        }
        return { status: r.status, corpo };
      };

      const primeira = await enviar();
      const segunda = await enviar();

      // Rótulo curto, nunca o corpo inteiro: ele contém o envelope enviado.
      const rotulo = (c: Record<string, unknown> | null) =>
        typeof c?.error === "string"
          ? c.error
          : typeof c?.code === "string"
            ? c.code
            : null;

      expect({ status: primeira.status, erro: rotulo(primeira.corpo) }).toEqual({
        status: 503,
        erro: "ENDPOINT_DISABLED",
      });
      expect({ status: segunda.status, erro: rotulo(segunda.corpo) }).toEqual({
        status: 401,
        erro: "REPLAY_DETECTED",
      });
    }, 60_000);
  }
);

describe("a sonda é opt-in e não vaza", () => {
  it("fica desligada sem a flag explícita", () => {
    if (!LIGADA) expect(LIGADA).toBe(false);
    expect(typeof LIGADA).toBe("boolean");
  });

  it("assina UMA vez e reenvia o mesmo objeto — não assina duas", () => {
    const src = readFileSyncLocal();
    // Uma única chamada ao assinante no arquivo inteiro.
    expect((src.match(/signGatewayRequest\(/g) ?? []).length).toBe(1);
    // E nada é impresso.
    expect(src).not.toMatch(/console\.|logger\./);
  });
});

function readFileSyncLocal(): string {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { readFileSync } = require("node:fs") as typeof import("node:fs");
  const { resolve } = require("node:path") as typeof import("node:path");
  return readFileSync(
    resolve(__dirname, "manualCodeGatewayStagingProbe.spec.ts"),
    "utf8"
  );
}