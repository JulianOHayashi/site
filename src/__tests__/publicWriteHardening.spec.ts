import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("public write hardening", () => {
  it("frontend no longer calls the three public write RPCs directly", () => {
    const partner = readFileSync(
      resolve(__dirname, "../services/partnerApplicationService.ts"),
      "utf8"
    );
    const future = readFileSync(
      resolve(__dirname, "../services/commercialFutureInterestService.ts"),
      "utf8"
    );

    expect(partner).toContain("/api/public/partner-application/create");
    expect(partner).toContain("/api/public/partner-application/recovery");
    expect(partner).not.toContain('"create_partner_application"');
    expect(partner).not.toContain('"request_partner_application_recovery"');

    expect(future).toContain("/api/public/commercial/territorial-interest");
    expect(future).not.toContain('"register_territorial_waitlist_interest"');
  });

  it("server endpoints fail closed and rate-limit before invoking write RPCs", () => {
    const create = readFileSync(
      resolve(__dirname, "../../api/public/partner-application/create.ts"),
      "utf8"
    );
    const recovery = readFileSync(
      resolve(__dirname, "../../api/public/partner-application/recovery.ts"),
      "utf8"
    );
    const waitlist = readFileSync(
      resolve(__dirname, "../../api/public/commercial/territorial-interest.ts"),
      "utf8"
    );

    for (const source of [create, recovery, waitlist]) {
      const gate = source.indexOf("await enforceTwoLimits");
      const rpc = source.indexOf(".rpc(");
      expect(gate).toBeGreaterThan(-1);
      expect(rpc).toBeGreaterThan(gate);
      expect(source).toContain('reason: "rate_limited"');
      expect(source).toContain("site_backend_unavailable");
    }
  });

  it("database migrations remove browser execution from write RPCs", () => {
    const acl = readFileSync(
      resolve(__dirname, "../../supabase/migrations/20260925121600_public_write_rpc_acl.sql"),
      "utf8"
    );
    const restrict = readFileSync(
      resolve(__dirname, "../../supabase/migrations/20260925121800_public_write_restrict_acl.sql"),
      "utf8"
    );

    expect(acl).toContain("create_partner_application");
    expect(acl).toContain("request_partner_application_recovery");
    expect(acl).toContain("register_territorial_waitlist_interest");
    expect(acl).toContain("from anon, authenticated");

    expect(restrict).toContain("consume_public_write_rate_limit");
    expect(restrict).toContain("public.is_site_admin()");
  });

  it("rate-limit ledger has bounded cleanup and remains server-only", () => {
    const cleanup = readFileSync(
      resolve(__dirname, "../../supabase/migrations/20260925121900_public_write_rate_limit_cleanup.sql"),
      "utf8"
    );

    expect(cleanup).toContain("window_started_at < clock_timestamp() - interval '2 days'");
    expect(cleanup).toContain("public_write_rate_limits_window_started_at_idx");
    expect(cleanup).toContain("from public, anon, authenticated");
    expect(cleanup).toContain("to service_role");
  });

  it("territorial endpoint does not disclose prior membership or waitlist ids", () => {
    const source = readFileSync(
      resolve(__dirname, "../../api/public/commercial/territorial-interest.ts"),
      "utf8"
    );
    expect(source).toContain('json({ ok: true, already: false })');
    expect(source).not.toContain("waitlist_id");
  });
});
