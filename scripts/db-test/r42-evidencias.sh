#!/usr/bin/env bash
# ============================================================================
# R4.2 — EVIDÊNCIAS VERIFICÁVEIS em PostgreSQL 16 e 17 (locais,
# descartáveis; nunca remoto), sempre comparando com a R4.1 (f319c29):
#   * todas as suítes SQL, R4.1 e R4, a partir de banco recém-criado; por
#     suíte: PASS/FAIL impressos × rodapé do tests.finish;
#   * upgrade/rollback R4.1 sobre a R4 (r41-upgrade-check.sh) e o da R4;
#   * contraprova R4 × R4.1 (ENABLE REPLICA; mesma guarda executando outra
#     função): r41-contraprova-gatilhos.sql, roteiro idêntico;
#   * ataque do registro de ativação forjado (r4-forja-registro-ativacao.sql);
#   * limite administrativo do dono: R4.1 (r41-limite-confianca.sh) e R4;
#   * concorrência real (duas sessões) na R4.1 e na R4.
# Saída: <dir>/resumo.tsv, um log por etapa, commit.txt e SHA256SUMS.
#
#   uso: r42-evidencias.sh <dir-saida> <checkout-R4.1-f319c29>
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mkdir -p "$1" && cd "$1" && pwd); R41DIR=$(cd "${2:?checkout R4.1}" && pwd)
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
linha_resumo() { # pg etapa alvo log padrao
  local l; l=$(grep -oE "$5: [0-9]+ PASS / [0-9]+ FAIL" "$4" | tail -1)
  printf '%s\t%s\t%s\t%s\t%s\t-\t-\t%s\n' "$1" "$2" "$3" "$(echo "$l" | grep -oE '[0-9]+ PASS' | cut -d' ' -f1)" \
    "$(echo "$l" | grep -oE '[0-9]+ FAIL' | cut -d' ' -f1)" "${l:-ERRO}" >> "$OUT/resumo.tsv"
}
declare -A ALVO=( [pg16]="" [pg17]="PGHOST=/tmp PGPORT=5433" )
for pg in pg16 pg17; do
  ENVV=${ALVO[$pg]}
  VER=$(env $ENVV su postgres -c "psql -X -At -d postgres -c 'show server_version'")
  echo "== $pg ($VER)"
  env $ENVV BDFLOW_LOCAL_DB=ev42_$pg bash scripts/db-test/run-sql-tests.sh > "$OUT/$pg-r42-suites.log" 2>&1
  (cd "$R41DIR" && env $ENVV BDFLOW_LOCAL_DB=ev42_r41base_$pg bash scripts/db-test/run-sql-tests.sh) > "$OUT/$pg-r41-suites.log" 2>&1
  for etapa in suites_r42 suites_r41; do
    LOG="$OUT/$pg-r42-suites.log"; [ $etapa = suites_r41 ] && LOG="$OUT/$pg-r41-suites.log"
    for s in $(grep -oE '^== supabase/tests/[^ ]+\.sql ==$' "$LOG" | sed -E 's#^== supabase/tests/(.+)\.sql ==$#\1#'); do
      blk=$(awk -v s="$s" '$0 == "== supabase/tests/" s ".sql ==" {on=1; next} on && /^-- (OK|FALHOU): / {print; on=0} on' "$LOG")
      linha_suite "$pg" "$etapa" "$s" "$blk"
    done
  done

  # Decisão A: roteiro REAL do Cenário A (4 condições) e recusa do B.
  env $ENVV bash scripts/db-test/r42-cenario-a.sh > "$OUT/$pg-r42-cenario-a.log" 2>&1
  linha_resumo "$pg" cenario_a_real r42 "$OUT/$pg-r42-cenario-a.log" R42_CENARIO_A

  env $ENVV BASE_REF=f319c29 bash scripts/db-test/r42-upgrade-check.sh > "$OUT/$pg-r42-upgrade.log" 2>&1
  linha_resumo "$pg" upgrade_rollback r42 "$OUT/$pg-r42-upgrade.log" R42_UPGRADE
  (cd "$R41DIR" && env $ENVV BASE_REF=cd4064a bash scripts/db-test/r41-upgrade-check.sh) > "$OUT/$pg-r41-upgrade.log" 2>&1
  linha_resumo "$pg" upgrade_rollback r41 "$OUT/$pg-r41-upgrade.log" R41_UPGRADE

  # Guardas R4.1 preservadas sob a R4.2: contraprova (R, função trocada) e forja.
  for r in r41 r42; do
    D=$([ $r = r41 ] && echo "$R41DIR" || pwd)
    (cd "$D" && env $ENVV BDFLOW_LOCAL_DB=ev42_contra_${r}_$pg bash scripts/db-test/reset-local.sh) > "$OUT/$pg-$r-contraprova.log" 2>&1
    env $ENVV su postgres -c "psql -X -At -d ev42_contra_${r}_$pg -f -" < scripts/db-test/r41-contraprova-gatilhos.sql >> "$OUT/$pg-$r-contraprova.log" 2>&1
    for c in C0_linha_de_base_preflight C1_preflight C1_ativacao_ok C1_status_v4_depois C2_preflight C2_ativacao_ok C2_status_v4_depois; do
      v=$(grep -E "^$c\|" "$OUT/$pg-$r-contraprova.log" | cut -d'|' -f2-); [ -n "$v" ] || v=ERRO
      printf '%s\tcontraprova_gatilhos\t%s:%s\t-\t-\t-\t-\t%s\n' "$pg" "$r" "$c" "$v" >> "$OUT/resumo.tsv"
    done
  done
  env $ENVV BDFLOW_LOCAL_DB=ev42_forja_$pg bash scripts/db-test/reset-local.sh > "$OUT/$pg-r42-forja.log" 2>&1
  env $ENVV su postgres -c "psql -X -At -d ev42_forja_$pg -f -" < scripts/db-test/r4-forja-registro-ativacao.sql >> "$OUT/$pg-r42-forja.log" 2>&1
  if grep -q 'activation_log_somente_pelo_procedimento' "$OUT/$pg-r42-forja.log"; then res="recusado(activation_log_somente_pelo_procedimento)"
  else res=$(grep -oE '^resultado\|.*' "$OUT/$pg-r42-forja.log" || echo ERRO); fi
  printf '%s\tforja_registro\tr42\t-\t-\t-\t-\t%s\n' "$pg" "$res" >> "$OUT/resumo.tsv"

  env $ENVV bash scripts/db-test/r41-limite-confianca.sh > "$OUT/$pg-r42-limite.log" 2>&1
  linha_resumo "$pg" limite_administrativo r42 "$OUT/$pg-r42-limite.log" R41_LIMITE_ADMINISTRATIVO
  (cd "$R41DIR" && env $ENVV bash scripts/db-test/r41-limite-confianca.sh) > "$OUT/$pg-r41-limite.log" 2>&1
  linha_resumo "$pg" limite_administrativo r41 "$OUT/$pg-r41-limite.log" R41_LIMITE_ADMINISTRATIVO

  for r in r42 r41; do
    D=$([ $r = r41 ] && echo "$R41DIR" || pwd)
    env $ENVV bash scripts/db-test/r4-concorrencia-bandeiras.sh "$D" "${r}${pg}" > "$OUT/$pg-$r-concorrencia.log" 2>&1
    linha_resumo "$pg" concorrencia "$r" "$OUT/$pg-$r-concorrencia.log" "R4_CONCORRENCIA\[[^]]*\]"
  done
done
git rev-parse HEAD > "$OUT/commit.txt"
(cd "$OUT" && sha256sum *.log resumo.tsv commit.txt > SHA256SUMS)
awk -F"\t" "{printf \"%-6s %-21s %-44s %5s %5s %5s %5s %s\\n\", \$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8}" "$OUT/resumo.tsv"
