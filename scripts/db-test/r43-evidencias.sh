#!/usr/bin/env bash
# ============================================================================
# R4.3 — evidências locais em PG16 e PG17 (bancos descartáveis; nada remoto).
#   uso: r43-evidencias.sh <saida>
# Suítes completas (as 15 falhas históricas continuam as mesmas), suíte 300
# (somente DINHEIRO e primeira contratação de ponta a ponta), Cenário A,
# ensaio dos roteiros de ops (Cenário A + somente DINHEIRO, revertido),
# upgrade/rollback R4.2.1 -> R4.3 e verificador somente leitura.
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
declare -A ALVO=( [pg16]="" [pg17]="PGHOST=/tmp PGPORT=5433" )
: > "$OUT/resumo.txt"
for pg in pg16 pg17; do
  ENVV=${ALVO[$pg]}
  V=$(env $ENVV su postgres -c "psql -X -At -d postgres -c 'show server_version'")
  echo "== $pg ($V)" | tee -a "$OUT/resumo.txt"
  env $ENVV BDFLOW_LOCAL_DB=ev43_$pg bash scripts/db-test/run-sql-tests.sh > "$OUT/$pg-suites.log" 2>&1
  awk '/^== supabase\/tests\// {s=$2} /^-- (OK|FALHOU): / {print s, $0}' "$OUT/$pg-suites.log" \
    | sed -E 's#supabase/tests/##' > "$OUT/$pg-suites-resumo.txt"
  echo "  suites com falha: $(grep -c 'FALHOU' "$OUT/$pg-suites-resumo.txt")" | tee -a "$OUT/resumo.txt"
  grep -E '^(29[0-9]|300)_' "$OUT/$pg-suites-resumo.txt" | sed 's/^/  /' | tee -a "$OUT/resumo.txt"
  env $ENVV su postgres -c "psql -X -At -d ev43_$pg -f -" < supabase/ops/20261116_verificar_r43_somente_leitura.sql > "$OUT/$pg-verificador.log" 2>&1
  echo "  verificador: $(grep -cE '\|true$' "$OUT/$pg-verificador.log") true / $(grep -cE '\|false$' "$OUT/$pg-verificador.log") false; $(grep -E '^estado\|' "$OUT/$pg-verificador.log")" | tee -a "$OUT/resumo.txt"
  { echo "begin;"
    echo "set local smallflags.decisao_dinheiro_sf_v15 = 'CENARIO-A-APROVADO';"
    echo "set local smallflags.decisao_referencia = 'DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115';"
    echo "\\i supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql"
    echo "set local smallflags.habilitar_somente_dinheiro = 'SOMENTE-DINHEIRO-AUTORIZADO';"
    echo "set local smallflags.habilitacao_referencia = 'ensaio local revertido R4.3';"
    echo "\\i supabase/ops/20261116_sf_v15_habilitar_somente_dinheiro.sql"
    echo "rollback;"
    echo "select 'depois_do_rollback|' || coalesce(array_to_string(enabled_settlement_modes, '+'), 'padrao') || '|' || status from public.commercial_pricing_rules where version = 4;"
  } | env $ENVV su postgres -c "psql -X -At -v ON_ERROR_STOP=1 -d ev43_$pg -f -" > "$OUT/$pg-ops-ensaio.log" 2>&1
  echo "  ensaio ops (revertido): $(grep -E '^4\|prepared\|' "$OUT/$pg-ops-ensaio.log" | cut -c1-200) | $(grep depois_do_rollback "$OUT/$pg-ops-ensaio.log")" | tee -a "$OUT/resumo.txt"
  env $ENVV bash scripts/db-test/r42-cenario-a.sh > "$OUT/$pg-cenario-a.log" 2>&1
  echo "  $(grep -E 'R42_CENARIO_A:' "$OUT/$pg-cenario-a.log")" | tee -a "$OUT/resumo.txt"
  env $ENVV bash scripts/db-test/r43-upgrade-check.sh > "$OUT/$pg-upgrade.log" 2>&1
  echo "  $(grep -E 'R43_UPGRADE:' "$OUT/$pg-upgrade.log")" | tee -a "$OUT/resumo.txt"
done
git rev-parse HEAD > "$OUT/commit.txt"
(cd "$OUT" && sha256sum *.log *.txt > SHA256SUMS)
