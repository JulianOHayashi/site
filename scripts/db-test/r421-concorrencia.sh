#!/usr/bin/env bash
# ============================================================================
# R4.2.1 / P1-2 — CONCORRÊNCIA entre a solicitação de alteração de arte e a
# renovação da MESMA empresa e identidade (trava por empresa+identidade).
# Banco descartável local (nunca remoto). Fixtures [QA FICTICIO] commitadas
# só nesse banco.
#
#   uso: r421-concorrencia.sh <checkout> <rotulo>   (PGHOST=/tmp PGPORT=5433 p/ PG17)
#
#   C1 solicitação (B, sem commit) x renovação fidelizada (A):
#      A espera B e é recusada (artwork_change_pending_for_campaign).
#   C2 renovação (B, sem commit) x solicitação (A):
#      A espera B e é recusada (base_order_not_latest).
#   C3 duas solicitações para a mesma campanha: a segunda espera e é recusada.
# Sobre a R4.2 (controle) a C1 mostra a corrida: A não espera e renova com as
# bandeiras antigas enquanto a nova arte é pedida para a mesma campanha.
# ============================================================================
set -uo pipefail
DIR=$(cd "${1:?checkout}" && pwd); ROT=${2:?rotulo}
BASE=conc421_${ROT}_base
psql_db() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
q() { su postgres -c "psql -X -At -d $1 -c \"$2\""; }
agora() { date +%s.%N; }
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }
echo "== $ROT | $(q postgres 'show server_version') | checkout $(git -C "$DIR" rev-parse --short HEAD) =="
(cd "$DIR" && BDFLOW_LOCAL_DB=$BASE bash scripts/db-test/reset-local.sh > /tmp/conc421_reset_$ROT.log 2>&1) || { echo "reset falhou"; exit 2; }

# Fixtures: o cabeçalho da suíte 298 do checkout, COMMITADO neste banco.
T=$DIR/supabase/tests/298_r42_alteracao_arte_fidelidade.sql
I=$(grep -n '^\\set ON_ERROR_STOP on' "$T" | cut -d: -f1)
F=$(grep -n "^select pg_temp.pedido(0, :'c2', 'pharmacy', false) as origem2" "$T" | cut -d: -f1)
{ sed -n "${I},${F}p" "$T"
  cat <<'SQL'
select pg_temp.inspecao(:'conj', 5);
create schema conc421;
create table conc421.estado (k text primary key, v text);
insert into conc421.estado values ('u1', :'u1'), ('c1', :'c1'), ('origem', :'origem'),
  ('excl1', (select id::text from exc298 where k = 1));
select pg_temp.tornar_corrente(1);
commit;
SQL
} | psql_db $BASE > /tmp/conc421_setup_$ROT.log 2>&1 || { echo "setup falhou: $(tail -3 /tmp/conc421_setup_$ROT.log)"; exit 2; }
E() { q $BASE "select v from conc421.estado where k = '$1'"; }
U1=$(E u1); C1=$(E c1); ORIG=$(E origem); EX1=$(E excl1)
copia() { echo "drop database if exists $1 with (force); create database $1 template $BASE;" | psql_db postgres > /dev/null; }

SOLICITA="select tests.impersonate('authenticated', '$U1'); select public.artwork_change_request_create('$ORIG');"
RENOVA="insert into public.commercial_exclusivity_orders (exclusivity_id, opportunity_id, company_id, master_agreement_id,
  region_id, niche_code, nominal_quantity, fidelized, status, expected_operation_start, registered_by, pricing_rule_version,
  benefit_settlement_mode, economic_value_cents, contractual_pool_cents, bdflow_due_cents)
select e.id, o.id, '$C1', (select id from public.commercial_master_agreements where company_id = '$C1' and status = 'signed'),
  e.region_id, 'womens_clothing', 12, true, 'draft', (now() + interval '30 days')::date,
  (select user_id from public.site_admins limit 1), 4, 'direct_benefits', 1, 1, 0
  from public.commercial_exclusivities e join public.commercial_opportunities o on o.exclusivity_id = e.id
 where e.id = '$EX1' and o.niche_code = 'womens_clothing';"

corrida() { # corrida <db> <sql_B> <sql_A>: B segura a transação 3 s; A roda 1 s depois
  ( printf 'begin;\n%s\nselect pg_sleep(3);\ncommit;\n' "$2" | su postgres -c "psql -X -q -At -v ON_ERROR_STOP=1 -d $1 -f -" > /tmp/conc421_B.log 2>&1 ) &
  local pb=$!; sleep 1
  local t0; t0=$(agora)
  printf 'begin;\n%s\ncommit;\n' "$3" | su postgres -c "psql -X -q -At -v ON_ERROR_STOP=1 -d $1 -f -" > /tmp/conc421_A.log 2>&1; local rc=$?
  local t1; t1=$(agora); wait $pb
  echo "$rc $(echo "$t1 - $t0" | bc)"
}
espera() { awk -v s="$1" 'BEGIN { exit !(s >= 1.5) }'; }

DB=conc421_${ROT}_c1; copia $DB
read RC TT <<< "$(corrida $DB "$SOLICITA" "$RENOVA")"
A=$(tr '\n' ' ' < /tmp/conc421_A.log | cut -c1-200)
VIVOS=$(q $DB "select count(*) from public.commercial_exclusivity_orders where exclusivity_id = '$EX1' and company_id = '$C1'")
echo "  [C1] solicitacao x renovacao: A rc=$RC esperou ${TT}s; pedidos na campanha alvo=$VIVOS; A: $A"
if [ "$RC" -ne 0 ] && grep -q 'artwork_change_pending_for_campaign' /tmp/conc421_A.log && espera "$TT" && [ "$VIVOS" = 0 ]; then
  passa "C1 renovacao esperou a solicitacao e foi recusada (nao renovou com as bandeiras antigas)"
else
  falha "C1 renovacao NAO serializada com a solicitacao (rc=$RC, ${TT}s, pedidos=$VIVOS)"
fi

DB=conc421_${ROT}_c2; copia $DB
read RC TT <<< "$(corrida $DB "$RENOVA" "$SOLICITA")"
A=$(tr '\n' ' ' < /tmp/conc421_A.log | cut -c1-200)
SOL=$(q $DB "select count(*) from public.commercial_artwork_change_requests")
echo "  [C2] renovacao x solicitacao: A rc=$RC esperou ${TT}s; solicitacoes=$SOL; A: $A"
if grep -q 'base_order_not_latest' /tmp/conc421_A.log && espera "$TT" && [ "$SOL" = 0 ]; then
  passa "C2 solicitacao esperou a renovacao e foi recusada (a proxima campanha ja foi contratada)"
else
  falha "C2 solicitacao NAO serializada com a renovacao (rc=$RC, ${TT}s, solicitacoes=$SOL)"
fi

DB=conc421_${ROT}_c3; copia $DB
read RC TT <<< "$(corrida $DB "$SOLICITA" "$SOLICITA")"
A=$(tr '\n' ' ' < /tmp/conc421_A.log | cut -c1-200)
SOL=$(q $DB "select count(*) from public.commercial_artwork_change_requests")
echo "  [C3] duas solicitacoes: A esperou ${TT}s; solicitacoes=$SOL; A: $A"
if grep -q 'artwork_change_already_open' /tmp/conc421_A.log && espera "$TT" && [ "$SOL" = 1 ]; then
  passa "C3 segunda solicitacao para a mesma campanha esperou e foi recusada"
else
  falha "C3 duas solicitacoes concorrentes (${TT}s, solicitacoes=$SOL)"
fi

for d in c1 c2 c3; do echo "drop database if exists conc421_${ROT}_$d with (force);" | psql_db postgres > /dev/null; done
echo "R421_CONCORRENCIA: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
