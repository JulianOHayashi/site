#!/usr/bin/env bash
# ============================================================================
# R4 / item 5 — CONCORRÊNCIA REAL (duas sessões) entre retirada ou inspeção
# reprovadora de um conjunto de bandeiras e a criação/confirmação do pedido
# que reutiliza esse conjunto. Bancos descartáveis; nunca remoto.
#
#   uso: r4-concorrencia-bandeiras.sh <diretorio-do-checkout> <rotulo>
#        PGHOST=/tmp PGPORT=5433 para o PG17 local
#
# Cenários (B = sessão que retira/inspeciona, A = sessão do pedido):
#   S1 B retira (sem efetivar) -> A cria o pedido -> B efetiva
#   S2 B registra inspeção reprovando (sem efetivar) -> A cria o pedido
#   S3 A cria o pedido (sem efetivar) -> B retira -> A efetiva  (ordem legítima)
#   S4 B retira (sem efetivar) -> A confirma o pagamento
#   S5 B registra inspeção reprovando (sem efetivar) -> A confirma o pagamento
# Esperado com a R4: em S1, S2, S4 e S5 A espera B e falha (flag_reuse_stale);
# em S3 B espera A, e a confirmação posterior é que recusa. Sem as travas
# (R3), A não espera e o pedido/pagamento nasce sobre estado já superado.
# ============================================================================
set -uo pipefail
DIR=$(cd "${1:?checkout}" && pwd); ROT=${2:?rotulo}
AQUI=$(cd "$(dirname "$0")" && pwd)
BASE=conc_${ROT}_base
psql_db() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
q() { su postgres -c "psql -X -At -d $1 -c \"$2\""; }
agora() { date +%s.%N; }
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }

echo "== $ROT | $(q postgres 'show server_version') | checkout $(git -C "$DIR" rev-parse --short HEAD 2>/dev/null) =="
(cd "$DIR" && BDFLOW_LOCAL_DB=$BASE bash scripts/db-test/reset-local.sh > /tmp/conc_reset_$ROT.log 2>&1) || { echo "reset falhou"; exit 2; }
# A preparação vem do próprio checkout (casa com o helpers.sql dele); sem
# ela (R3), usa a deste script.
SETUP="$DIR/scripts/db-test/r4-concorrencia-setup.sql"; [ -f "$SETUP" ] || SETUP="$AQUI/r4-concorrencia-setup.sql"
psql_db $BASE < "$SETUP" > /tmp/conc_setup_$ROT.log 2>&1 || { echo "setup falhou: $(tail -3 /tmp/conc_setup_$ROT.log)"; exit 2; }
[ "$(q $BASE "select v from conc.estado where k = 'reserva_ok'")" = "true" ] || { echo "reserva fidelizada nao criada"; exit 2; }

copia() { echo "drop database if exists $1 with (force); create database $1 template $BASE;" | psql_db postgres > /dev/null; }
SET=$(q $BASE "select v from conc.estado where k = 'conjunto'")
INT=$(q $BASE "select v from conc.estado where k = 'intencao'")
ADM=$(q $BASE "select v from conc.estado where k = 'admin'")
RETIRA="update public.commercial_flag_sets set status = 'retired', retired_at = now(), retired_reason = '[QA] concorrencia' where id = '$SET'"
REPROVA="select conc.inspecao('$SET', 0, 2, array['damaged'])"
PEDIDO="select conc.pedido_da_reserva('$INT')"
assinar() { q $1 "update public.commercial_exclusivity_orders set status = 'signed', signed_at = now(), signatory_name = 'Titular conc', order_version = 'v1', document_reference = 'doc://conc' where id = (select v::uuid from conc.estado where k = 'pedido')" > /dev/null; }
CONFIRMA="update public.commercial_exclusivity_orders set payment_status = 'confirmed', payment_confirmed_at = now(), payment_confirmed_by = '$ADM', payment_amount_cents = total_monetary_funding_required_cents, payment_confirmed_source = 'admin_manual' where id = (select v::uuid from conc.estado where k = 'pedido')"

# B segura a mudança por 3 s; A começa 1 s depois.
corrida() { # corrida <db> <sql_B> <sql_A> -> imprime "rcA segundosA" ; saída de A em /tmp
  local db=$1
  ( printf 'begin;\n%s;\nselect pg_sleep(3);\ncommit;\n' "$2" | su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $db -f -" > /tmp/conc_B.log 2>&1 ) &
  local pb=$!; sleep 1
  local t0; t0=$(agora)
  su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $db -c \"$3\"" > /tmp/conc_A.log 2>&1; local rc=$?
  local t1; t1=$(agora); wait $pb
  echo "$rc $(echo "$t1 - $t0" | bc)"
}
espera() { awk -v s="$1" 'BEGIN { exit !(s >= 1.5) }'; }

for cen in S1 S2 S4 S5; do
  DB=conc_${ROT}_$(echo $cen | tr A-Z a-z); copia $DB
  case $cen in
    S1) B="$RETIRA";  A="$PEDIDO";   O="retirada antes do pedido" ;;
    S2) B="$REPROVA"; A="$PEDIDO";   O="inspecao reprovando antes do pedido" ;;
    S4) q $DB "$PEDIDO" > /dev/null; assinar $DB; B="$RETIRA";  A="$CONFIRMA"; O="retirada durante a confirmacao" ;;
    S5) q $DB "$PEDIDO" > /dev/null; assinar $DB; B="$REPROVA"; A="$CONFIRMA"; O="inspecao reprovando durante a confirmacao" ;;
  esac
  read RC T <<< "$(corrida $DB "$B" "$A")"
  ERRO=$(grep -o 'flag_reuse_stale[^"]*' /tmp/conc_A.log | head -1)
  echo "  [$cen] $O: A rc=$RC, esperou ${T}s ${ERRO:+, erro: $ERRO}"
  if [ "$RC" -ne 0 ] && [ -n "$ERRO" ] && espera "$T"; then
    passa "$cen $O: A esperou B efetivar e foi recusada com o estado efetivo"
  else
    falha "$cen $O: A NAO esperou ou foi aceita sobre estado ja superado (rc=$RC, ${T}s)"
  fi
  echo "drop database $DB with (force);" | psql_db postgres > /dev/null
done

DB=conc_${ROT}_s3; copia $DB
( printf 'begin;\n%s;\nselect pg_sleep(3);\ncommit;\n' "$PEDIDO" | su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $DB -f -" > /tmp/conc_A3.log 2>&1 ) &
PA=$!; sleep 1; T0=$(agora)
su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $DB -c \"$RETIRA\"" > /tmp/conc_B3.log 2>&1; RCB=$?
T=$(echo "$(agora) - $T0" | bc); wait $PA; RCA=$?
echo "  [S3] pedido antes da retirada: A rc=$RCA, B rc=$RCB, B esperou ${T}s"
if [ $RCA -eq 0 ] && [ $RCB -eq 0 ] && espera "$T"; then
  passa "S3 pedido antes da retirada: B esperou o pedido efetivar (ordem serial A -> B)"
else falha "S3: B nao esperou (rc A=$RCA B=$RCB, ${T}s)"; fi
assinar $DB
if su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $DB -c \"$CONFIRMA\"" > /tmp/conc_C3.log 2>&1; then
  falha "S3: pagamento confirmado sobre conjunto ja retirado"
else grep -q flag_reuse_stale /tmp/conc_C3.log && passa "S3: confirmacao posterior recusada (conjunto retirado)" || falha "S3: erro inesperado"; fi
echo "drop database $DB with (force); drop database $BASE with (force);" | psql_db postgres > /dev/null

echo "R4_CONCORRENCIA[$ROT]: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
