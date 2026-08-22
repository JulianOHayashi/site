#!/usr/bin/env bash
# ============================================================================
# Executa todas as suítes SQL em supabase/tests/*.sql contra o banco local
# descartável (harness nativo). Cada arquivo termina com tests.finish(...),
# que levanta erro se qualquer caso falhou; ON_ERROR_STOP propaga a falha.
# ============================================================================
set -uo pipefail

DB_NAME="${BDFLOW_LOCAL_DB:-bdflow_recon_local}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# As suítes pressupõem banco recém-criado (fixtures determinísticas).
if [ "${BDFLOW_SKIP_RESET:-0}" != "1" ]; then
  bash scripts/db-test/reset-local.sh
fi

total=0
failed=0
for f in supabase/tests/*.sql; do
  [ -e "$f" ] || continue
  total=$((total+1))
  echo "== $f =="
  out="$(su postgres -c "psql -v ON_ERROR_STOP=1 -q -d $DB_NAME -f -" < "$f" 2>&1)"
  rc=$?
  echo "$out"
  # Cenários com ROLLBACK descartam as linhas de tests.results; a contagem
  # autoritativa é feita sobre a SAÍDA (linhas FAIL impressas pelos checks).
  nfail="$(printf '%s\n' "$out" | grep -cE '^\s*FAIL  ')"
  if [ "$rc" -ne 0 ] || [ "$nfail" -gt 0 ]; then
    echo "-- FALHOU: $f (exit=$rc, FAIL=$nfail)"
    failed=$((failed+1))
  else
    echo "-- OK: $f"
  fi
done

echo
if [ "$failed" -gt 0 ]; then
  echo "SQL_TESTS_AUXILIAR=FAIL ($failed/$total suites falharam)"
  exit 1
fi
echo "SQL_TESTS_AUXILIAR=PASS ($total suites) [PG16 TESTE_AUXILIAR_NAO_GATE]"
