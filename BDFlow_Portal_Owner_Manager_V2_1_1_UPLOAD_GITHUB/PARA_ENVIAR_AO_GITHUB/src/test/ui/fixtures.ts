import type {
  PartnerCompany,
  PortalCapabilities,
  PortalContextState,
  PortalMembership,
  PortalRole,
  MemberStatus,
} from "../../domain/portal/types";
import { noCapabilities } from "../../domain/portal/capabilities";

export const empresaFake: PartnerCompany = {
  companyId: "c1",
  partnerDisplayName: "Loja Exemplo",
  status: "active",
  contractStatusLabel: null,
  paymentStatusLabel: null,
  nicheLabel: null,
  exclusivityStatusLabel: null,
  operationStatusLabel: null,
  notices: [],
};

export function membershipFake(
  role: PortalRole,
  status: MemberStatus = "active"
): PortalMembership {
  return { memberId: "m1", role, status, company: empresaFake };
}

export function capsFake(over: Partial<PortalCapabilities> = {}): PortalCapabilities {
  return { ...noCapabilities(), ...over };
}

export function readyState(
  role: PortalRole,
  over: Partial<PortalCapabilities> = {},
  status: MemberStatus = "active"
): PortalContextState {
  return {
    kind: "ready",
    membership: membershipFake(role, status),
    capabilities: capsFake(over),
    capabilitiesSource: "unavailable",
  };
}
