#!/usr/bin/env bash
# ============================================================================
# AUDITORIA DE MUTAÇÃO (R14)
#
# Um teste que passa não prova nada sozinho: ele pode estar passando porque
# não observa o invariante que diz observar. Este script quebra, uma de cada
# vez, invariantes de segurança reais do código e EXIGE que a suíte
# correspondente falhe. Se a suíte continuar verde com o invariante quebrado,
# a suíte é o defeito — e este script reprova.
#
# Regras:
#   - Só roda com a árvore limpa (a restauração é feita por `git checkout`).
#   - Toda mutação é revertida, inclusive em caso de erro ou interrupção.
#   - Nenhum segredo é lido, gravado ou impresso.
#
# Uso:  bash scripts/audit/mutation-audit.sh [--sql]
#       --sql inclui as mutações de schema (exigem reset do banco auxiliar).
# ============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

INCLUIR_SQL=0
[ "${1:-}" = "--sql" ] && INCLUIR_SQL=1

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "MUTATION_AUDIT=ABORT (arvore suja: a restauracao depende de git checkout)"
  exit 1
fi

ARQUIVOS_TOCADOS=()
PLANTADOS=()

restaurar() {
  for f in "${ARQUIVOS_TOCADOS[@]:-}"; do
    [ -n "$f" ] && git checkout -- "$f" 2>/dev/null
  done
  for f in "${PLANTADOS[@]:-}"; do
    [ -n "$f" ] && rm -f "$f"
  done
  ARQUIVOS_TOCADOS=()
  PLANTADOS=()
}
trap restaurar EXIT INT TERM

total=0
sobreviventes=0

# aplica_sed <arquivo> <expressao-sed>
aplica_sed() {
  ARQUIVOS_TOCADOS+=("$1")
  perl -0pi -e "$2" "$1"
}

# verifica <nome> <comando-que-deve-FALHAR>
inconclusivos=0

verifica() {
  local nome="$1"; shift
  total=$((total+1))
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    sobreviventes=$((sobreviventes+1))
    echo "  MUTANTE SOBREVIVEU  $nome  <-- a suite NAO observa o invariante"
    printf '%s\n' "$out" | tail -5 | sed 's/^/      /'
  elif [ "$rc" -eq 2 ]; then
    inconclusivos=$((inconclusivos+1))
    echo "  INCONCLUSIVO        $nome  <-- a suite alvo nem chegou a rodar"
    printf '%s\n' "$out" | tail -3 | sed 's/^/      /'
  else
    echo "  MORTO               $nome"
  fi
  restaurar
}

vitest() { npx vitest run "$@" >/dev/null 2>&1; }

# sql_suite <arquivo-da-suite-alvo>
#
# As suites SQL sao encadeadas: varias dependem de fixtures criadas pelas
# anteriores (o admin de teste, por exemplo, nasce na suite 000). Rodar uma
# suite isolada faria qualquer mutante parecer "morto" apenas porque a suite
# nao consegue nem comecar — um falso positivo que invalidaria a auditoria.
# Por isso o encadeamento REAL e reproduzido ate a suite alvo, e o veredito
# olha SOMENTE a saida da suite alvo.
sql_suite() {
  local alvo="$1" f out rc nfail
  bash scripts/db-test/reset-local.sh >/dev/null 2>&1 || return 1
  for f in supabase/tests/*.sql; do
    out="$(su postgres -c "psql -v ON_ERROR_STOP=1 -q -d ${BDFLOW_LOCAL_DB:-bdflow_recon_local} -f -" < "$f" 2>&1)"
    rc=$?
    nfail="$(printf '%s\n' "$out" | grep -cE '^\s*FAIL  ')"
    if [ "$f" = "$alvo" ]; then
      [ "$rc" -eq 0 ] && [ "$nfail" -eq 0 ]
      return $?
    fi
    if [ "$rc" -ne 0 ]; then
      # Uma suite anterior tambem pode observar o mutante. Isso e desejavel e
      # NAO deve impedir o alvo de rodar: tests.finish() so levanta no FIM do
      # arquivo, entao todo o DDL/DML da suite ja foi aplicado e o estado do
      # banco esta integro. Segue-se o encadeamento.
      if printf '%s\n' "$out" | grep -q 'FALHOU:'; then
        echo "      (a suite $f tambem observou o mutante; encadeamento segue)" >&2
      else
        # Erro duro no meio do arquivo: o estado ficou incompleto e o alvo
        # nao teria um teste justo. Codigo 2 = INCONCLUSIVO, nunca morte.
        echo "      (erro duro em $f, antes da suite alvo)" >&2
        return 2
      fi
    fi
  done
  return 1
}

echo "== auditoria de mutacao =="

# ---------------------------------------------------------------------------
# 1. PortalGuard fail-closed: o `default` do switch precisa negar.
# ---------------------------------------------------------------------------
aplica_sed src/components/PortalGuard.tsx \
  's/    default:\n      return "erro";/    default:\n      return "liberado";/'
verifica "PortalGuard: default do switch libera" \
  vitest src/__tests__/portalGuardFailClosed.spec.tsx

# ---------------------------------------------------------------------------
# 2. Contexto durável só pode ELEVAR: falha do RPC não pode autorizar.
# ---------------------------------------------------------------------------
aplica_sed src/services/partnerApplicationService.ts \
  's/if \(duravel\.tipo === "ok" && duravel\.vinculos\.length > 0\) \{/if (duravel.tipo !== "ok" || duravel.vinculos.length >= 0) {/'
verifica "obterContextoConta: falha do vinculo duravel autoriza" \
  vitest src/__tests__/m2ContextoParceiro.spec.tsx

# ---------------------------------------------------------------------------
# 3. safeInternalDestination: sem a checagem de origem o `?next=` escapa.
# ---------------------------------------------------------------------------
aplica_sed src/lib/safeInternalDestination.ts \
  's/if \(url\.origin !== DUMMY_ORIGIN\) return null;/if (false) return null;/'
verifica "safeInternalDestination: checagem de origem removida" \
  vitest src/lib/__tests__/safeInternalDestination.spec.ts

# ---------------------------------------------------------------------------
# 4. Scanner de legado: precisa acusar uma consulta plantada em codigo vivo.
# ---------------------------------------------------------------------------
PLANTADOS+=("src/__mutante_plantado__.ts")
cat > src/__mutante_plantado__.ts <<'PLANT'
import { supabase } from "./lib/supabaseClient";
export const q = () => supabase!.from("site_partner_members").select("*");
PLANT
verifica "check:legacy: consulta a tabela inexistente plantada" \
  npm run --silent check:legacy

# ---------------------------------------------------------------------------
# 5. Ponte com o App: o transporte bloqueado nao pode virar no-op silencioso.
# ---------------------------------------------------------------------------
aplica_sed src/server/provisioning/bridgeAdapter.ts \
  's/    throw new ProvisioningBlockedError\(/    return { status: "sent" } as unknown as ProvisioningOutcome; void new ProvisioningBlockedError(/'
verifica "bridgeAdapter: transporte bloqueado deixa de falhar" \
  vitest src/__tests__/m2PonteProvisionamento.spec.ts

if [ "$INCLUIR_SQL" -eq 1 ]; then
  # -------------------------------------------------------------------------
  # 6. Invariante economico: economic = pool + due, garantido por CHECK.
  # -------------------------------------------------------------------------
  aplica_sed supabase/migrations/20260822124000_m2_contracts.sql \
    's/CHECK \(economic_value_cents = contractual_pool_cents \+ bdflow_due_cents\)/CHECK (economic_value_cents > 0)/'
  verifica "contratos: CHECK economic = pool + due enfraquecido" \
    sql_suite supabase/tests/140_m2_contracts.sql

  # -------------------------------------------------------------------------
  # 7. Menor privilegio: sem o REVOKE, anon volta a poder truncar orders.
  #    Prova que a suite 900 observa o privilegio de verdade, e nao o catalogo
  #    de um banco que ja nasceria correto.
  # -------------------------------------------------------------------------
  aplica_sed supabase/migrations/20260822130000_r14_revoke_rls_exempt_privileges.sql \
    "s/REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLE public\.\%I FROM anon, authenticated/REVOKE TRIGGER ON TABLE public.%I FROM anon, authenticated/"
  verifica "menor privilegio: REVOKE de TRUNCATE removido" \
    sql_suite supabase/tests/900_r14_auditoria_estrutural.sql

  # -------------------------------------------------------------------------
  # 8. R15 — vinculo geografico da fidelidade.
  #    Reintroduz EXATAMENTE o defeito original: em vez da cidade real da
  #    empresa, a primeira cidade ativa da regiao por ordem alfabetica.
  # -------------------------------------------------------------------------
  aplica_sed supabase/migrations/20260822140000_r15_fidelity_city_binding.sql \
    's/  v_key := public\.commercial_city_key\(v_company\.city\);/  v_key := (SELECT c.city_key FROM public.commercial_region_cities c WHERE c.region_id = p_region_id AND c.is_active ORDER BY c.city_name LIMIT 1);/'
  verifica "R15: cidade da fidelidade volta a ser a primeira da regiao" \
    sql_suite supabase/tests/910_r15_fidelity_city_binding.sql

  # -------------------------------------------------------------------------
  # 9. R15 — invalidacao da fidelidade pelo pedido fundador cancelado.
  # -------------------------------------------------------------------------
  aplica_sed supabase/migrations/20260822140000_r15_fidelity_city_binding.sql \
    "s/       AND NOT EXISTS \(\n             SELECT 1 FROM public\.commercial_exclusivity_orders o\n              WHERE o\.id = f\.established_by_order_id\n                AND o\.status = 'cancelled'\)\);/       );/"
  verifica "R15: guarda do fundador cancelado removida" \
    sql_suite supabase/tests/910_r15_fidelity_city_binding.sql

  # -------------------------------------------------------------------------
  # 10. Confirmacao manual: so o valor devido a BDFlow pode ser aceito.
  # -------------------------------------------------------------------------
  aplica_sed supabase/migrations/20260822126000_m2_manual_sale.sql \
    's/p_amount_cents <> v_ord\.bdflow_due_cents/p_amount_cents < 0/'
  verifica "venda manual: aceita valor diferente do devido a BDFlow" \
    sql_suite supabase/tests/160_m2_manual_sale.sql
fi

echo
if [ "$sobreviventes" -gt 0 ] || [ "$inconclusivos" -gt 0 ]; then
  echo "MUTATION_AUDIT=FAIL ($sobreviventes sobreviveram, $inconclusivos inconclusivos, de $total)"
  exit 1
fi
echo "MUTATION_AUDIT=PASS ($total/$total mutantes mortos)"
