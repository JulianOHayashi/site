/**
 * Testes do Portal separado por papel (owner/manager).
 *
 * Mesma infraestrutura do teste comercial existente: funções puras, sem
 * framework novo e sem alterar dependências. Rodar via esbuild + node.
 *
 * Além da lógica pura, há asserções ESTRUTURAIS sobre o código-fonte para
 * garantias que dependem de renderização (ex.: ausência do CTA de cadastro
 * empresarial), já que o repositório não possui runtime de testes de DOM.
 */

import {
  applyRoleAndStatusFloor,
  noCapabilities,
  parseCapabilities,
  resolveCapabilities,
  roleLabel,
} from "../domain/portal/capabilities";
import {
  canRoleOpenRoute,
  portalNavigation,
} from "../domain/portal/navigation";
import {
  buildBatchInput,
  canReplaceInvitation,
  canRevokeInvitation,
  expiresAtFromCreation,
  formatInvitationList,
  hoursRemaining,
  invitationStateLabel,
  invitationVisualState,
  labelPageCount,
  labelPositionsForPage,
  LABELS_PAGE_SIZE,
  validateBatchQuantity,
} from "../domain/portal/invitations";
import { filterValidatableUnits } from "../services/partnerUnitService";
import {
  DEFAULT_PORTAL_TARGET,
  isSafePortalNext,
  safePortalNext,
} from "../domain/portal/nextTarget";
import { loteCurto, resumirLotes } from "../domain/portal/batches";
import {
  createInvitationBatch,
  listManagers,
  reactivateManager,
  replaceInvitation,
  revokeInvitationBatch,
  revokeManagerMembership,
  suspendManager,
} from "../services/partnerTeamService";
import { startValidation } from "../services/partnerValidationService";
import {
  INVITATION_TTL_HOURS,
  isValidStateCode,
  type ManagerInvitation,
  type PartnerUnit,
  type PortalCapabilities,
} from "../domain/portal/types";

declare function require(m: string): any;

let pass = 0;
let fail = 0;
const results: string[] = [];

function check(name: string, cond: boolean) {
  if (cond) {
    pass++;
    results.push(`PASS  ${name}`);
  } else {
    fail++;
    results.push(`FAIL  ${name}`);
  }
}

const fs = require("fs");
function fonte(caminho: string): string {
  return fs.readFileSync(caminho, "utf8") as string;
}

/**
 * Código-fonte SEM comentários.
 *
 * As garantias de "não renderiza X" precisam ser avaliadas sobre o código
 * efetivo: uma menção em comentário de documentação (ex.: registrar que um
 * CTA foi removido) não representa interface exibida ao usuário.
 */
function fonteCodigo(caminho: string): string {
  return fonte(caminho)
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
}

const todasCapacidades = (): PortalCapabilities => ({
  canAccessPortal: true,
  canPrepareOperation: true,
  canManageUnits: true,
  canInviteManagers: true,
  canManageManagers: true,
  canValidateBenefits: true,
  canViewCompanyTransactions: true,
  canAccessFinancial: true,
});

// ===========================================================================
// 1. Capacidades — `status = active` sozinho não concede nada
// ===========================================================================

{
  // Backend indisponível (undefined) com owner ativo → tudo negado.
  const caps = resolveCapabilities(undefined, "partner_owner", "active");
  check(
    "status active sozinho NÃO concede canInviteManagers",
    caps.canInviteManagers === false
  );
  check(
    "status active sozinho NÃO concede canManageUnits",
    caps.canManageUnits === false
  );
  check(
    "status active sozinho NÃO concede canValidateBenefits",
    caps.canValidateBenefits === false
  );
  check(
    "status active sozinho NÃO concede canAccessFinancial",
    caps.canAccessFinancial === false
  );
}

{
  // Só `true` booleano é aceito — string/número/ausência não concedem.
  const caps = parseCapabilities({
    canManageUnits: "true",
    canInviteManagers: 1,
    canValidateBenefits: true,
    canAccessFinancial: null,
  });
  check("capacidade string 'true' é rejeitada", caps.canManageUnits === false);
  check("capacidade numérica 1 é rejeitada", caps.canInviteManagers === false);
  check("capacidade booleana true é aceita", caps.canValidateBenefits === true);
  check("capacidade null é rejeitada", caps.canAccessFinancial === false);
}

{
  const caps = parseCapabilities(null);
  check("payload nulo → nenhuma capacidade", caps.canAccessPortal === false);
  const vazio = noCapabilities();
  check(
    "noCapabilities nega tudo",
    Object.values(vazio).every((v) => v === false)
  );
}

// ===========================================================================
// 2. Trava de papel e status
// ===========================================================================

{
  // Manager jamais recebe poderes administrativos, mesmo se o backend errar.
  const caps = applyRoleAndStatusFloor(
    todasCapacidades(),
    "partner_manager",
    "active"
  );
  check("manager não recebe canManageUnits", caps.canManageUnits === false);
  check("manager não recebe canInviteManagers", caps.canInviteManagers === false);
  check("manager não recebe canManageManagers", caps.canManageManagers === false);
  check(
    "manager não recebe canViewCompanyTransactions",
    caps.canViewCompanyTransactions === false
  );
  check("manager não recebe canAccessFinancial", caps.canAccessFinancial === false);
  check(
    "manager MANTÉM canValidateBenefits quando concedida",
    caps.canValidateBenefits === true
  );
}

{
  // Membro suspenso não recebe ação operacional alguma.
  const suspenso = applyRoleAndStatusFloor(
    todasCapacidades(),
    "partner_manager",
    "suspended"
  );
  check(
    "membro suspenso não valida benefício",
    suspenso.canValidateBenefits === false
  );
  check(
    "membro suspenso mantém apenas acesso de leitura ao portal",
    suspenso.canAccessPortal === true
  );

  const emAnalise = applyRoleAndStatusFloor(
    todasCapacidades(),
    "partner_owner",
    "pending_admin_review"
  );
  check(
    "membro em análise não recebe ações operacionais",
    emAnalise.canValidateBenefits === false &&
      emAnalise.canInviteManagers === false
  );
}

{
  // Owner autorizado continua podendo validar mesmo havendo managers.
  const owner = applyRoleAndStatusFloor(
    todasCapacidades(),
    "partner_owner",
    "active"
  );
  check("owner autorizado pode validar benefício", owner.canValidateBenefits === true);
  check("owner autorizado mantém canManageUnits", owner.canManageUnits === true);
}

check("rótulo do papel owner", roleLabel("partner_owner") === "Responsável principal");
check("rótulo do papel manager", roleLabel("partner_manager") === "Gerente operacional");

// ===========================================================================
// 3. Navegação por papel
// ===========================================================================

{
  const navManager = portalNavigation("partner_manager", todasCapacidades());
  const rotas = navManager.map((i) => i.to);
  check("manager não vê Equipe", !rotas.includes("/portal/equipe"));
  check("manager não vê Unidades", !rotas.includes("/portal/unidades"));
  check(
    "manager não vê rótulo de Transações/Equipe/Convites",
    !navManager.some((i) =>
      ["Transações", "Equipe e convites", "Empresa e filiais"].includes(i.rotulo)
    )
  );
  check(
    "manager vê Meu acesso e Minhas validações",
    rotas.includes("/portal/meu-acesso") &&
      navManager.some((i) => i.rotulo === "Minhas validações")
  );

  const navOwner = portalNavigation("partner_owner", todasCapacidades());
  const rotasOwner = navOwner.map((i) => i.to);
  check(
    "owner vê Empresa e filiais, Equipe e Transações",
    rotasOwner.includes("/portal/unidades") &&
      rotasOwner.includes("/portal/equipe") &&
      rotasOwner.includes("/portal/solicitacoes")
  );
  check("owner não vê Meu acesso (manager-only)", !rotasOwner.includes("/portal/meu-acesso"));
}

{
  // Sem capacidade de validar, o item "Validar" não aparece para ninguém.
  const semValidar = { ...todasCapacidades(), canValidateBenefits: false };
  const navO = portalNavigation("partner_owner", semValidar);
  const navM = portalNavigation("partner_manager", semValidar);
  check(
    "item Validar oculto sem capacidade (owner)",
    !navO.some((i) => i.rotulo === "Validar")
  );
  check(
    "item Validar oculto sem capacidade (manager)",
    !navM.some((i) => i.rotulo === "Validar")
  );
}

// ===========================================================================
// 4. Rotas por papel
// ===========================================================================

check(
  "manager NÃO abre /portal/equipe",
  canRoleOpenRoute("partner_manager", "/portal/equipe") === false
);
check(
  "manager NÃO abre /portal/equipe/:id",
  canRoleOpenRoute("partner_manager", "/portal/equipe/abc-123") === false
);
check(
  "manager NÃO abre /portal/unidades",
  canRoleOpenRoute("partner_manager", "/portal/unidades") === false
);
check(
  "owner NÃO abre /portal/meu-acesso (manager-only)",
  canRoleOpenRoute("partner_owner", "/portal/meu-acesso") === false
);
check(
  "owner abre /portal/equipe",
  canRoleOpenRoute("partner_owner", "/portal/equipe") === true
);
check(
  "ambos abrem /portal/validar",
  canRoleOpenRoute("partner_owner", "/portal/validar") === true &&
    canRoleOpenRoute("partner_manager", "/portal/validar") === true
);

// ===========================================================================
// 5. Convites — 48 horas corridas
// ===========================================================================

const criado = "2026-08-01T10:00:00.000Z";
const expira = expiresAtFromCreation(criado)!;

check(
  "validade do convite = 48 horas corridas",
  Date.parse(expira) - Date.parse(criado) === INVITATION_TTL_HOURS * 3600_000
);

{
  const conv: ManagerInvitation = {
    invitationId: "i1",
    batchId: "batch-abc12345",
    label: "Turno da manhã",
    url: "https://exemplo/portal/convites/T1",
    createdAt: criado,
    expiresAt: expira,
    status: "not_used",
    usedAt: null,
    usedByMemberId: null,
    usedByName: null,
  };

  const logoAposCriar = new Date(Date.parse(criado) + 60_000);
  check(
    "convite não utilizado permanece 'not_used'",
    invitationVisualState(conv, logoAposCriar) === "not_used"
  );
  check(
    "convite não utilizado mostra validade em horas (48h)",
    invitationStateLabel(conv, logoAposCriar) ===
      "Não utilizado — expira em 47 horas"
  );
  check(
    "horas restantes coerentes com 48h",
    hoursRemaining(expira, logoAposCriar) === 47
  );

  // Abrir o link NÃO altera o estado: a função é pura e idempotente.
  const antes = invitationVisualState(conv, logoAposCriar);
  const depois = invitationVisualState(conv, logoAposCriar);
  check(
    "abrir/consultar o convite não muda o estado para utilizado",
    antes === "not_used" && depois === "not_used"
  );

  // Depois de 48h vira expirado, com o texto exigido.
  const depoisDoPrazo = new Date(Date.parse(expira) + 1000);
  check(
    "após 48h o convite fica expirado",
    invitationVisualState(conv, depoisDoPrazo) === "expired"
  );
  check(
    "texto exato do convite expirado",
    invitationStateLabel(conv, depoisDoPrazo) ===
      "Expirado — este convite não foi utilizado"
  );
  check(
    "convite expirado não pode ser revogado",
    canRevokeInvitation(conv, depoisDoPrazo) === false
  );
  check(
    "convite expirado pode receber substituto",
    canReplaceInvitation(conv, depoisDoPrazo) === true
  );
  check(
    "convite não utilizado pode ser revogado",
    canRevokeInvitation(conv, logoAposCriar) === true
  );

  // Utilizado nunca é sobrescrito por expiração (histórico preservado).
  const usado: ManagerInvitation = {
    ...conv,
    status: "used",
    usedAt: "2026-08-01T11:00:00.000Z",
  };
  check(
    "convite utilizado permanece 'utilizado' mesmo após o prazo",
    invitationVisualState(usado, depoisDoPrazo) === "used"
  );

  const revogado: ManagerInvitation = { ...conv, status: "revoked" };
  check(
    "convite revogado tem precedência",
    invitationVisualState(revogado, logoAposCriar) === "revoked" &&
      invitationStateLabel(revogado, logoAposCriar) === "Revogado"
  );

  check(
    "lista numerada para copiar todos os links",
    formatInvitationList([conv]) ===
      "1. (Turno da manhã) https://exemplo/portal/convites/T1"
  );
}

// ===========================================================================
// 6. Lote: apenas inteiro positivo, sem teto inventado
// ===========================================================================

check("lote rejeita zero", validateBatchQuantity(0).ok === false);
check("lote rejeita negativo", validateBatchQuantity(-3).ok === false);
check("lote rejeita fracionário", validateBatchQuantity(2.5).ok === false);
check("lote rejeita texto", validateBatchQuantity("abc").ok === false);
check("lote rejeita vazio", validateBatchQuantity("").ok === false);
check("lote aceita 1", validateBatchQuantity(1).ok === true);
check("lote aceita string numérica", validateBatchQuantity("7").ok === true);
check(
  "lote NÃO impõe limite máximo no frontend",
  validateBatchQuantity(5000).ok === true
);

// ===========================================================================
// 7. Unidades elegíveis para validação
// ===========================================================================

{
  const base: PartnerUnit = {
    unitId: "u",
    isHeadquarters: false,
    branchDisplayName: "Loja",
    branchLocationLabel: "Centro",
    branchCityName: "Vitória",
    branchStateCode: "ES",
    status: "active",
    benefitsAuthorized: true,
    activeManagersCount: 1,
  };
  const unidades: PartnerUnit[] = [
    base,
    { ...base, unitId: "u2", status: "suspended" },
    { ...base, unitId: "u3", benefitsAuthorized: false },
    { ...base, unitId: "u4", status: "archived", benefitsAuthorized: true },
    { ...base, unitId: "u5", benefitsAuthorized: null },
  ];
  const elegiveis = filterValidatableUnits(unidades).map((u) => u.unitId);
  check(
    "só filiais ativas E autorizadas ficam elegíveis",
    elegiveis.length === 1 && elegiveis[0] === "u"
  );
}

check("UF válida aceita", isValidStateCode("ES") === true);
check("UF minúscula rejeitada", isValidStateCode("es") === false);
check("UF inexistente rejeitada", isValidStateCode("XX") === false);
check("UF com 3 letras rejeitada", isValidStateCode("ESP") === false);

// ===========================================================================
// 7b. Proteção contra quantidade grande (CORREÇÃO 7)
// ===========================================================================

check("safe-integer: rejeita infinito", validateBatchQuantity(Infinity).ok === false);
check(
  "safe-integer: rejeita inteiro inseguro",
  validateBatchQuantity(Number.MAX_SAFE_INTEGER + 1).ok === false
);
check("safe-integer: aceita 1000000", validateBatchQuantity(1000000).ok === true);

check(
  "1000000 → páginas de 20 sem materializar array total",
  labelPageCount(1000000) === 50000
);
{
  const pag1 = labelPositionsForPage(1000000, 1);
  check(
    "página 1 tem no máximo 20 posições",
    pag1.length === LABELS_PAGE_SIZE && pag1[0] === 1 && pag1[19] === 20
  );
  const pag2 = labelPositionsForPage(1000000, 2);
  check("página 2 começa em 21", pag2[0] === 21 && pag2.length === 20);
  const ultimaCheia = labelPositionsForPage(45, 3);
  check(
    "última página parcial respeita o total",
    ultimaCheia.length === 5 && ultimaCheia[4] === 45
  );
  check("página além do total é vazia", labelPositionsForPage(45, 10).length === 0);
}

{
  // Rótulos ESPARSOS: só posições preenchidas viram payload.
  const esparso = new Map<number, string>([
    [3, "turno da noite"],
    [1, "  "], // vazio após trim → descartado
    [50000, "última vaga"],
  ]);
  const input = buildBatchInput(1000000, esparso);
  check("payload contém apenas rótulos preenchidos", input.labels.length === 2);
  check("payload preserva quantity", input.quantity === 1000000);
  check(
    "payload esparso ordenado por posição",
    input.labels[0].position === 3 && input.labels[1].position === 50000
  );
  check(
    "rótulo fora do intervalo é descartado",
    buildBatchInput(2, new Map([[5, "x"]])).labels.length === 0
  );
}

// ===========================================================================
// 7c. Resumo de lotes e batchId (CORREÇÃO 3)
// ===========================================================================

check("loteCurto encurta id longo", loteCurto("batch-abcdef-0001") === "batch-ab");
check("loteCurto trata null", loteCurto(null) === "—");

{
  const criadoL = "2026-08-01T10:00:00.000Z";
  const expL = expiresAtFromCreation(criadoL)!;
  const base = (over: Partial<ManagerInvitation>): ManagerInvitation => ({
    invitationId: "x",
    batchId: "batch-XYZ",
    label: null,
    url: null,
    createdAt: criadoL,
    expiresAt: expL,
    status: "not_used",
    usedAt: null,
    usedByMemberId: null,
    usedByName: null,
    ...over,
  });
  const agoraL = new Date(Date.parse(criadoL) + 60_000);
  const lote = resumirLotes(
    [
      base({ invitationId: "a", status: "not_used" }),
      base({ invitationId: "b", status: "used", usedAt: criadoL }),
      base({ invitationId: "c", status: "revoked" }),
      base({ invitationId: "d", batchId: "outro", status: "not_used" }),
    ],
    agoraL
  );
  const xyz = lote.find((l) => l.batchId === "batch-XYZ")!;
  check("resumo agrupa por batchId", lote.length === 2);
  check(
    "resumo conta disponíveis/utilizados/revogados",
    xyz.total === 3 && xyz.disponiveis === 1 && xyz.utilizados === 1 && xyz.revogados === 1
  );
}

// ===========================================================================
// 7d. Validação segura de `next` (CORREÇÃO 5.3)
// ===========================================================================

check("next válido: /portal", isSafePortalNext("/portal") === true);
check("next válido: /portal/dashboard", isSafePortalNext("/portal/dashboard") === true);
check("next válido: /portal/convites/ABC?y=2", isSafePortalNext("/portal/convites/ABC?y=2") === true);
check("next válido: /portal?x=1", isSafePortalNext("/portal?x=1") === true);

check("next inválido: /portal-malicioso", isSafePortalNext("/portal-malicioso") === false);
check("next inválido: /portal.example", isSafePortalNext("/portal.example") === false);
check("next inválido: prefixo lexical /portalX", isSafePortalNext("/portalabc") === false);
check("next inválido: externo https", isSafePortalNext("https://mal.example/portal") === false);
check("next inválido: protocol-relative //host", isSafePortalNext("//evil.com/portal") === false);
check("next inválido: esquema javascript:", isSafePortalNext("javascript:alert(1)") === false);
check("next inválido: barra invertida", isSafePortalNext("/portal\\x") === false);
check("next inválido: relativo sem barra", isSafePortalNext("portal/x") === false);
check("next inválido: vazio", isSafePortalNext("") === false);
check("next inválido: null", isSafePortalNext(null) === false);
check(
  "next inválido: controle (newline)",
  isSafePortalNext("/portal/x\nmal") === false
);

check(
  "safePortalNext: inválido cai em /portal/dashboard",
  safePortalNext("/portal-malicioso") === DEFAULT_PORTAL_TARGET
);
check(
  "safePortalNext: /portal.example cai em /portal/dashboard",
  safePortalNext("/portal.example") === "/portal/dashboard"
);
check(
  "safePortalNext: externo cai em /portal/dashboard",
  safePortalNext("https://evil.example") === "/portal/dashboard"
);
check(
  "safePortalNext: válido é preservado",
  safePortalNext("/portal/convites/ABC?y=2") === "/portal/convites/ABC?y=2"
);

// ===========================================================================
// 8. Backend ausente nunca produz sucesso
// ===========================================================================

const verificacoesAssincronas = (async () => {
  const r1 = await createInvitationBatch({ quantity: 1, labels: [{ position: 1, label: "a" }] });
  check(
    "createInvitationBatch sem backend → falha explícita",
    r1.ok === false && r1.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r2 = await startValidation({ unitId: "u", code: "X" });
  check(
    "startValidation sem backend → falha explícita",
    r2.ok === false && r2.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r3 = await suspendManager("m1");
  check(
    "suspendManager sem backend → falha explícita",
    r3.ok === false && r3.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r4 = await revokeManagerMembership({ memberId: "m1", reason: "desligamento", sensitiveActionProof: "" });
  check(
    "revokeManagerMembership sem backend → falha explícita",
    r4.ok === false && r4.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r5 = await listManagers();
  check(
    "listManagers sem backend → falha explícita",
    r5.ok === false && r5.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r6 = await reactivateManager("m1");
  check(
    "reactivateManager sem backend → falha explícita",
    r6.ok === false && r6.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r7 = await replaceInvitation("i1");
  check(
    "replaceInvitation sem backend → falha explícita",
    r7.ok === false && r7.error.code === "BACKEND_NOT_AVAILABLE"
  );

  const r8 = await revokeInvitationBatch("batch-1");
  check(
    "revokeInvitationBatch sem backend → falha explícita",
    r8.ok === false && r8.error.code === "BACKEND_NOT_AVAILABLE"
  );
})();

// ===========================================================================
// 9. Garantias estruturais no código-fonte
// ===========================================================================

{
  const dashboard = fonteCodigo("src/pages/portal/PortalDashboard.tsx");
  const ownerDash = fonteCodigo("src/components/portal/OwnerDashboard.tsx");
  const managerDash = fonteCodigo("src/components/portal/ManagerDashboard.tsx");

  const CTA = "Cadastre sua empresa parceira";
  check("dashboard não contém o CTA de cadastro empresarial", !dashboard.includes(CTA));
  check("owner com vínculo não recebe o CTA de cadastro", !ownerDash.includes(CTA));
  check("manager nunca recebe o CTA de cadastro", !managerDash.includes(CTA));

  check(
    "dashboard não reutiliza a RPC antiga de criação de owner",
    !dashboard.includes("create_my_partner_owner_registration") &&
      !ownerDash.includes("create_my_partner_owner_registration")
  );

  // Manager não tem superfície administrativa nem financeira.
  check(
    "ManagerDashboard não importa painel de equipe/convites",
    !managerDash.includes("EquipeConvitesPainel")
  );
  check(
    "ManagerDashboard não importa resumo de unidades",
    !managerDash.includes("UnidadesResumo")
  );
  check(
    "ManagerDashboard não linka rotas owner-only",
    !managerDash.includes("/portal/equipe") &&
      !managerDash.includes("/portal/unidades")
  );

  // Nenhuma consulta nova ao Supabase espalhada nas páginas do portal.
  for (const arquivo of [
    "src/pages/portal/PortalEquipe.tsx",
    "src/pages/portal/PortalUnidades.tsx",
    "src/pages/portal/PortalValidar.tsx",
    "src/pages/portal/PortalSolicitacoes.tsx",
    "src/pages/portal/PortalMeuAcesso.tsx",
    "src/pages/portal/PortalConvite.tsx",
  ]) {
    const src = fonteCodigo(arquivo);
    check(
      `${arquivo} não consulta Supabase diretamente`,
      !src.includes(".from(") && !src.includes(".rpc(")
    );
  }

  // Nenhuma página do portal toca o banco do App BDFlow.
  for (const arquivo of [
    "src/pages/portal/PortalValidar.tsx",
    "src/components/portal/OwnerDashboard.tsx",
    "src/components/portal/ManagerDashboard.tsx",
  ]) {
    check(
      `${arquivo} não usa o cliente do App BDFlow`,
      !fonteCodigo(arquivo).includes("appSupabase")
    );
  }

  // Convite: abrir não consome; nada é revelado antes da validação segura.
  const convite = fonteCodigo("src/pages/portal/PortalConvite.tsx");
  check(
    "página de convite NÃO chama aceite ao abrir",
    !convite.includes("acceptInvitation(")
  );
  check(
    "página de convite consulta apenas leitura protegida",
    convite.includes("getPublicInvitation(")
  );
  check(
    "página de convite preserva pathname + search em next",
    convite.includes("location.pathname + location.search")
  );

  // qt preservado através do login.
  const guard = fonte("src/components/PortalGuard.tsx");
  check(
    "PortalGuard preserva pathname + search no next",
    guard.includes("location.pathname + location.search")
  );
  const validar = fonte("src/pages/portal/PortalValidar.tsx");
  check(
    "/portal/validar lê e preserva o parâmetro qt",
    validar.includes('params.get("qt")')
  );
  check(
    "/portal/validar exige seleção de filial por validação",
    validar.includes("unitId") && validar.includes("Selecione a filial")
  );

  // Revogação: linguagem correta e histórico preservado.
  const revog = fonteCodigo("src/components/portal/ConfirmarRevogacao.tsx");
  check(
    "revogação não usa a expressão 'Excluir cadastro'",
    !revog.includes("Excluir cadastro")
  );
  check(
    "revogação informa preservação do histórico",
    revog.includes("preservado para auditoria")
  );
  check(
    "revogação informa necessidade de novo convite",
    revog.includes("novo convite")
  );

  // Formação comercial vigente intocada.
  const comercial = fonte("src/services/commercialResponse.ts");
  check(
    "formação comercial permanece 84 unidades",
    comercial.includes("EXPECTED_TOTAL_UNITS = 84")
  );
  check(
    "quantidades por nicho permanecem 24/12/12/12/12/12",
    comercial.includes("supermarket: 24") && comercial.includes("pharmacy: 12")
  );
}

// ===========================================================================
// Saída (após concluir as verificações assíncronas)
// ===========================================================================
verificacoesAssincronas.then(() => {
  console.log(results.join("\n"));
  console.log(`\nTOTAL: ${pass} PASS / ${fail} FAIL`);
  if (fail > 0) {
    throw new Error(`${fail} teste(s) falharam`);
  }
});
