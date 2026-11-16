#!/usr/bin/env bash
# ============================================================================
# R4 / item 6 — EVIDÊNCIAS VERIFICÁVEIS em PostgreSQL 16 e 17 (locais,
# descartáveis; nunca remoto). Para cada servidor:
#   * todas as suítes SQL a partir de banco recém-criado (run-sql-tests.sh);
#   * por suíte: linhas PASS e FAIL impressas, rodapé do tests.finish e a
#     conferência linhas == rodapé (contadores por sequência, imunes a ROLLBACK);
#   * ensaio de upgrade/rollback R3 e R4;
#   * ataque do registro de ativação forjado, na R4 e na R3 (contraprova);
#   * limite de confiança do dono (replica, DDL, gatilho desligado);
#   * concorrência real (duas sessões) na R4 e, como contraprova, na R3.
# Saída: <dir>/resumo.tsv, um log por etapa e SHA256SUMS.
#
#   uso: r4-evidencias.sh <dir-saida> <checkout-R3-049d1c2>
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mkdir -p "$1" && cd "$1" && pwd); R3DIR=$(cd "${2:?checkout R3}" && pwd)
printf 'servidor\tetapa\tsuite\tlinhas_pass\tlinhas_fail\trodape_pass\trodape_fail\tconsistente\n' > "$OUT/resumo.tsv"
# Conta PASS/FAIL por OCORRÊNCIA (um SELECT pode imprimir vários checks na
# mesma linha, separados por " | ") e compara com o rodapé do tests.finish.
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
declare -A ALVO=( [pg16]="" [pg17]="PGHOST=/tmp PGPORT=5433" )
for pg in pg16 pg17; do
  ENVV=${ALVO[$pg]}
  VER=$(env $ENVV su postgres -c "psql -X -At -d postgres -c 'show server_version'")
  echo "== $pg ($VER)"
  # Suítes da R4 e, como linha de base, as mesmas suítes no checkout da R3
  # (separa falhas pré-existentes de regressões).
  env $ENVV BDFLOW_LOCAL_DB=evid_$pg bash scripts/db-test/run-sql-tests.sh > "$OUT/$pg-suites.log" 2>&1
  (cd "$R3DIR" && env $ENVV BDFLOW_LOCAL_DB=evid_r3base_$pg bash scripts/db-test/run-sql-tests.sh) > "$OUT/$pg-r3-suites.log" 2>&1
  for etapa in suites suites_r3; do
    LOG="$OUT/$pg-suites.log"; [ $etapa = suites_r3 ] && LOG="$OUT/$pg-r3-suites.log"
    for s in $(grep -oE '^== supabase/tests/[^ ]+\.sql ==$' "$LOG" | sed -E 's#^== supabase/tests/(.+)\.sql ==$#\1#'); do
      blk=$(awk -v s="$s" '$0 == "== supabase/tests/" s ".sql ==" {on=1; next} on && /^-- (OK|FALHOU): / {print; on=0} on' "$LOG")
      linha_suite "$pg" "$etapa" "$s" "$blk"
    done
  done
  # Contraprova do rodapé antigo (item 6): a suíte 295 no checkout da R3,
  # com o helpers.sql da R3 (rodapé contado em tests.results, que perde o que
  # foi gravado dentro de transações revertidas).
  env $ENVV BDFLOW_LOCAL_DB=evid_r3_$pg bash "$R3DIR/scripts/db-test/reset-local.sh" > "$OUT/$pg-r3-295-rodape-antigo.log" 2>&1
  (cd "$R3DIR" && env $ENVV su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d evid_r3_$pg -f -" < supabase/tests/295_qa_modalidades_r3.sql) >> "$OUT/$pg-r3-295-rodape-antigo.log" 2>&1
  linha_suite "$pg" r3_rodape_antigo 295_qa_modalidades_r3 "$(cat "$OUT/$pg-r3-295-rodape-antigo.log")"
  for r in r3 r4; do
    D=$([ $r = r3 ] && echo "$R3DIR" || pwd)
    (cd "$D" && env $ENVV BASE_REF=$([ $r = r3 ] && echo a8f5e51 || echo 049d1c2) bash scripts/db-test/$r-upgrade-check.sh) > "$OUT/$pg-$r-upgrade.log" 2>&1
    l=$(grep -oE "${r^^}_UPGRADE: [0-9]+ PASS / [0-9]+ FAIL" "$OUT/$pg-$r-upgrade.log")
    printf '%s\tupgrade_rollback\t%s\t%s\t%s\t-\t-\t%s\n' "$pg" "$r" "$(echo "$l" | grep -oE '[0-9]+ PASS' | cut -d' ' -f1)" "$(echo "$l" | grep -oE '[0-9]+ FAIL' | cut -d' ' -f1)" "${l:-ERRO}" >> "$OUT/resumo.tsv"
  done
  # Item 1: o ataque pedido (registro direto, travas ligadas, pré-verificação
  # aprovada), mesmo roteiro na R4 e na R3, cada um em banco recém-criado.
  for r in r4 r3; do
    D=$([ $r = r3 ] && echo "$R3DIR" || pwd)
    (cd "$D" && env $ENVV BDFLOW_LOCAL_DB=evid_forja_${r}_$pg bash scripts/db-test/reset-local.sh) > "$OUT/$pg-$r-forja.log" 2>&1
    env $ENVV su postgres -c "psql -X -At -d evid_forja_${r}_$pg -f -" < scripts/db-test/r4-forja-registro-ativacao.sql >> "$OUT/$pg-$r-forja.log" 2>&1
    if grep -q 'activation_log_somente_pelo_procedimento' "$OUT/$pg-$r-forja.log"; then res="recusado(activation_log_somente_pelo_procedimento)"
    else res=$(grep -oE '^resultado\|.*' "$OUT/$pg-$r-forja.log" || echo ERRO); fi
    printf '%s\tforja_registro\t%s\t-\t-\t-\t-\t%s\n' "$pg" "$r" "$res" >> "$OUT/resumo.tsv"
  done
  # Item 1: limite de confiança do dono (replica, DDL, gatilho desligado).
  env $ENVV bash scripts/db-test/r4-limite-confianca.sh > "$OUT/$pg-r4-limite-confianca.log" 2>&1
  l=$(grep -oE "R4_LIMITE_CONFIANCA: [0-9]+ PASS / [0-9]+ FAIL" "$OUT/$pg-r4-limite-confianca.log")
  printf '%s\tlimite_confianca\tr4\t%s\t%s\t-\t-\t%s\n' "$pg" "$(echo "$l" | grep -oE '[0-9]+ PASS' | cut -d' ' -f1)" "$(echo "$l" | grep -oE '[0-9]+ FAIL' | cut -d' ' -f1)" "${l:-ERRO}" >> "$OUT/resumo.tsv"
  for r in r4 r3; do
    D=$([ $r = r3 ] && echo "$R3DIR" || pwd)
    env $ENVV bash scripts/db-test/r4-concorrencia-bandeiras.sh "$D" "${r}${pg}" > "$OUT/$pg-$r-concorrencia.log" 2>&1
    l=$(grep -oE "R4_CONCORRENCIA\[[^]]*\]: [0-9]+ PASS / [0-9]+ FAIL" "$OUT/$pg-$r-concorrencia.log")
    printf '%s\tconcorrencia\t%s\t%s\t%s\t-\t-\t%s\n' "$pg" "$r" "$(echo "$l" | grep -oE '[0-9]+ PASS' | cut -d' ' -f1)" "$(echo "$l" | grep -oE '[0-9]+ FAIL' | cut -d' ' -f1)" "${l:-ERRO}" >> "$OUT/resumo.tsv"
  done
done
git rev-parse HEAD > "$OUT/commit.txt"
(cd "$OUT" && sha256sum *.log resumo.tsv commit.txt > SHA256SUMS)
awk -F"\t" "{printf \"%-6s %-17s %-44s %5s %5s %5s %5s %s\\n\", \$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8}" "$OUT/resumo.tsv"
