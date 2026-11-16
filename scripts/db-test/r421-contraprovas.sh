#!/usr/bin/env bash
# ============================================================================
# R4.2.1 — CONTRAPROVAS da auditoria independente: o MESMO ataque sobre a
# R4.2 (demonstra a lacuna) e sobre a R4.2.1 (lacuna fechada).
# Banco descartável local (nunca remoto); transações revertidas.
#
#   uso: r421-contraprovas.sh <checkout-R4.2> [checkout-R4.2.1]
#        (PGHOST=/tmp PGPORT=5433 para o PG17 local)
#
#   X1 produção só AUTORIZADA (sem cobrança/fabricação) habilita renovação?
#   X2 alteração "próxima campanha" vale duas campanhas depois?
#   X3 adulteração das guardas NOVAS (gatilho, função, índice, coluna gerada)
#      é detectada pela integridade e pelo verificador somente leitura?
#   X4 orçamento com total <> peças x unitário e documento inexistente passa?
# ============================================================================
set -uo pipefail
R42=$(cd "${1:?checkout R4.2}" && pwd); R421=$(cd "${2:-$(dirname "$0")/../..}" && pwd)
AQUI=$R421/scripts/db-test/r421-contraprovas
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }
roda() { # roda <checkout> <corpo> <verificador> <db>
  local d=$1 T=$1/supabase/tests/298_r42_alteracao_arte_fidelidade.sql
  (cd "$d" && BDFLOW_LOCAL_DB=$4 bash scripts/db-test/reset-local.sh > /tmp/$4_reset.log 2>&1) || { echo "reset falhou ($4)"; exit 2; }
  local I F; I=$(grep -n '^\\set ON_ERROR_STOP on' "$T" | cut -d: -f1)
  F=$(grep -n "^select pg_temp.pedido(0, :'c2', 'pharmacy', false) as origem2" "$T" | cut -d: -f1)
  { sed -n "${I},${F}p" "$T"; echo "\\o"; cat "$2"; echo "rollback;"; } \
    | su postgres -c "psql -X -At -v ON_ERROR_STOP=1 -v verificador=$3 -d $4 -f -" 2>&1 | grep -E '^X[0-9]\||\|(true|false)$'
}
SUF=${PGPORT:-5432}
echo "== contraprovas R4.2.1 | $(su postgres -c "psql -X -At -d postgres -c 'show server_version'") | R4.2 $(git -C "$R42" rev-parse --short HEAD) x R4.2.1 $(git -C "$R421" rev-parse --short HEAD) =="
A=$(roda "$R42" "$AQUI/corpo-r42.sql" "$R42/supabase/ops/20261116_verificar_r42_somente_leitura.sql" r421_cp_r42_$SUF)
echo "$A" | sed 's/^/    R4.2:   /' | cut -c1-260
B=$(roda "$R421" "$AQUI/corpo-r421.sql" "$R421/supabase/ops/20261116_verificar_r421_somente_leitura.sql" r421_cp_r421_$SUF)
echo "$B" | sed 's/^/    R4.2.1: /' | cut -c1-260
FALSOS() { printf '%s\n' "$1" | grep -E '\|(true|false)$' | grep -v '^X' | grep -c '|false$'; }

grep -q 'X1|renovacao_fidelizada_apoiada_so_na_autorizacao|{"ok": true' <<< "$A" \
  && passa "X1 R4.2: lacuna DEMONSTRADA (renovacao fidelizada sem cobranca/fabricacao)" || falha "X1 R4.2 nao reproduziu"
grep -q 'X1|renovacao_fidelizada_apoiada_so_na_autorizacao|{"ok": false, "detail": .*"reason": "artwork_change_not_ready"' <<< "$B" \
  && passa "X1 R4.2.1: renovacao recusada (artwork_change_not_ready)" || falha "X1 R4.2.1"
grep -qE 'X2\|duas_campanhas_depois\|[0-9a-f-]{36}' <<< "$A" \
  && passa "X2 R4.2: lacuna DEMONSTRADA (alteracao aplicada duas campanhas depois)" || falha "X2 R4.2 nao reproduziu"
grep -q 'X2|duas_campanhas_depois|sem_alteracao' <<< "$B" \
  && passa "X2 R4.2.1: alteracao nao vale fora da campanha alvo" || falha "X2 R4.2.1"
grep -q 'X3|falhas_de_integridade||fim' <<< "$A" && [ "$(FALSOS "$A")" = 0 ] \
  && passa "X3 R4.2: lacuna DEMONSTRADA (adulteracao das guardas novas invisivel a integridade e ao verificador)" || falha "X3 R4.2 nao reproduziu"
grep -q 'X3|falhas_de_integridade|.*guard_trigger_state_not_approved:public.commercial_artwork_change_requests.cacr_protect.*guard_function_divergent:public.commercial_artwork_change_readiness' <<< "$B" \
  && grep -q 'guard_table_divergent:public.commercial_artwork_change_quotes:columns_sha256' <<< "$B" \
  && grep -q 'guard_table_divergent:public.commercial_artwork_change_requests:indexes' <<< "$B" \
  && [ "$(FALSOS "$B")" -ge 2 ] \
  && passa "X3 R4.2.1: gatilho, funcao, indice e coluna gerada DETECTADOS (integridade e verificador)" || falha "X3 R4.2.1"
grep -q 'X4|orcamento_declarado_com_total_divergente_e_documento_inexistente|{"ok": true' <<< "$A" \
  && passa "X4 R4.2: lacuna DEMONSTRADA (total <> pecas x unitario e documento inexistente aceitos)" || falha "X4 R4.2 nao reproduziu"
grep -q 'X4|rpc_declarada_removida|true' <<< "$B" && grep -q 'X4|orcamento_com_total_divergente|.*quote_item_total_mismatch' <<< "$B" \
  && passa "X4 R4.2.1: orcamento declarado removido; total divergente recusado" || falha "X4 R4.2.1"
for d in r421_cp_r42_$SUF r421_cp_r421_$SUF; do echo "drop database if exists $d with (force);" | su postgres -c "psql -X -q -d postgres -f -" > /dev/null 2>&1; done
echo "R421_CONTRAPROVAS: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
