#!/usr/bin/env bash
# ============================================================================
# R4.2.1 — evidências locais em PG16 e PG17 (bancos descartáveis; nada remoto).
#   uso: r421-evidencias.sh <saida> <checkout-R4.2>
# Suítes completas na R4.2.1 e na R4.2 (comparação suíte a suíte: as 15
# falhas históricas aparecem nas duas), Cenário A real, upgrade/rollback,
# contraprovas R4.2 x R4.2.1, concorrência (R4.2.1 = gate; R4.2 = controle),
# limite administrativo, concorrência das bandeiras e verificador somente
# leitura com o ESTADO (nada ativado).
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mkdir -p "$1" && cd "$1" && pwd); R42DIR=$(cd "${2:?checkout R4.2}" && pwd)
printf 'servidor\tetapa\tsuite\tlinhas_pass\tlinhas_fail\trodape_pass\trodape_fail\tconsistente\n' > "$OUT/resumo.tsv"
linha_suite() { # pg etapa suite bloco
  local lp lf rod rp rf st c
  lp=$(printf '%s\n' "$4" | grep -oE '(^|\| )\s*PASS  ' | wc -l)
  lf=$(printf '%s\n' "$4" | grep -oE '(^|\| )\s*FAIL  ' | wc -l)
  rod=$(printf '%s\n' "$4" | grep -oE "SUITE [^ ]+( FALHOU)?: [0-9]+ PASS / [0-9]+ FAIL" | tail -1)
  rp=$(echo "$rod" | grep -oE '[0-9]+ PASS' | grep -oE '[0-9]+'); rf=$(echo "$rod" | grep -oE '[0-9]+ FAIL' | grep -oE '[0-9]+')
  st=$(printf '%s\n' "$4" | grep -oE '^-- (OK|FALHOU)' | tail -1 | cut -c4-)
  if [ -z "$rod" ]; then c="sem_rodape(${st:-sem_status})"; elif [ "$lp" = "$rp" ] && [ "$lf" = "$rf" ]; then c="sim"; else c="NAO"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$lp" "$lf" "${rp:--}" "${rf:--}" "$c" >> "$OUT/resumo.tsv"
}
linha_resumo() { # pg etapa alvo log padrao
  local l; l=$(grep -oE "$5: [0-9]+ PASS / [0-9]+ FAIL" "$4" | tail -1)
  printf '%s\t%s\t%s\t%s\t%s\t-\t-\t%s\n' "$1" "$2" "$3" "$(echo "$l" | grep -oE '[0-9]+ PASS' | cut -d' ' -f1)" \
    "$(echo "$l" | grep -oE '[0-9]+ FAIL' | cut -d' ' -f1)" "${l:-ERRO}" >> "$OUT/resumo.tsv"
}
declare -A ALVO=( [pg16]="" [pg17]="PGHOST=/tmp PGPORT=5433" )
for pg in pg16 pg17; do
  ENVV=${ALVO[$pg]}
  echo "== $pg ($(env $ENVV su postgres -c "psql -X -At -d postgres -c 'show server_version'"))"
  env $ENVV BDFLOW_LOCAL_DB=ev421_$pg bash scripts/db-test/run-sql-tests.sh > "$OUT/$pg-r421-suites.log" 2>&1
  (cd "$R42DIR" && env $ENVV BDFLOW_LOCAL_DB=ev421_r42base_$pg bash scripts/db-test/run-sql-tests.sh) > "$OUT/$pg-r42-suites.log" 2>&1
  for etapa in suites_r421 suites_r42; do
    LOG="$OUT/$pg-r421-suites.log"; [ $etapa = suites_r42 ] && LOG="$OUT/$pg-r42-suites.log"
    for s in $(grep -oE '^== supabase/tests/[^ ]+\.sql ==$' "$LOG" | sed -E 's#^== supabase/tests/(.+)\.sql ==$#\1#'); do
      blk=$(awk -v s="$s" '$0 == "== supabase/tests/" s ".sql ==" {on=1; next} on && /^-- (OK|FALHOU): / {print; on=0} on' "$LOG")
      linha_suite "$pg" "$etapa" "$s" "$blk"
    done
  done
  env $ENVV su postgres -c "psql -X -At -d ev421_$pg -f -" < supabase/ops/20261116_verificar_r421_somente_leitura.sql > "$OUT/$pg-r421-verificador.log" 2>&1
  linha_resumo "$pg" verificador_somente_leitura r421 <(printf 'VERIF: %s PASS / %s FAIL\n' \
    "$(grep -cE '\|true$' "$OUT/$pg-r421-verificador.log")" "$(grep -cE '\|false$' "$OUT/$pg-r421-verificador.log")") VERIF
  printf '%s\testado_nada_ativado\tr421\t-\t-\t-\t-\t%s\n' "$pg" "$(grep -E '^estado\|' "$OUT/$pg-r421-verificador.log")" >> "$OUT/resumo.tsv"
  env $ENVV bash scripts/db-test/r42-cenario-a.sh > "$OUT/$pg-r421-cenario-a.log" 2>&1
  linha_resumo "$pg" cenario_a_real r421 "$OUT/$pg-r421-cenario-a.log" R42_CENARIO_A
  env $ENVV bash scripts/db-test/r421-upgrade-check.sh > "$OUT/$pg-r421-upgrade.log" 2>&1
  linha_resumo "$pg" upgrade_rollback r421 "$OUT/$pg-r421-upgrade.log" R421_UPGRADE
  env $ENVV bash scripts/db-test/r421-contraprovas.sh "$R42DIR" . > "$OUT/$pg-r421-contraprovas.log" 2>&1
  linha_resumo "$pg" contraprovas_auditoria r42xr421 "$OUT/$pg-r421-contraprovas.log" R421_CONTRAPROVAS
  env $ENVV bash scripts/db-test/r421-concorrencia.sh . "r421$pg" > "$OUT/$pg-r421-concorrencia-arte.log" 2>&1
  linha_resumo "$pg" concorrencia_arte r421 "$OUT/$pg-r421-concorrencia-arte.log" R421_CONCORRENCIA
  env $ENVV bash scripts/db-test/r421-concorrencia.sh "$R42DIR" "r42$pg" > "$OUT/$pg-r42-concorrencia-arte-controle.log" 2>&1
  linha_resumo "$pg" concorrencia_arte_CONTROLE r42 "$OUT/$pg-r42-concorrencia-arte-controle.log" R421_CONCORRENCIA
  env $ENVV bash scripts/db-test/r41-limite-confianca.sh > "$OUT/$pg-r421-limite.log" 2>&1
  linha_resumo "$pg" limite_administrativo r421 "$OUT/$pg-r421-limite.log" R41_LIMITE_ADMINISTRATIVO
  env $ENVV bash scripts/db-test/r4-concorrencia-bandeiras.sh . "r421$pg" > "$OUT/$pg-r421-concorrencia-bandeiras.log" 2>&1
  linha_resumo "$pg" concorrencia_bandeiras r421 "$OUT/$pg-r421-concorrencia-bandeiras.log" "R4_CONCORRENCIA\[[^]]*\]"
done
git rev-parse HEAD > "$OUT/commit.txt"
(cd "$OUT" && sha256sum *.log resumo.tsv commit.txt > SHA256SUMS)
awk -F"\t" "{printf \"%-6s %-27s %-44s %5s %5s %5s %5s %s\\n\", \$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8}" "$OUT/resumo.tsv"
