#!/usr/bin/env bash
# Ensaio LOCAL da reconciliação do histórico de migrations (supabase/ops).
# Monta uma cópia da tabela supabase_migrations.schema_migrations com as 62
# linhas (version:name) lidas de Production em 2026-11-03 e verifica ida,
# idempotência (segunda execução aborta), reversão e nenhuma alteração em
# statements. JAMAIS aponte para um banco remoto.
set -euo pipefail
cd "$(dirname "$0")/../.."
DB=bdflow_reconcile
psql_db() { su postgres -c "psql -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
q() { su postgres -c "psql -d $1 -Atc \"$2\""; }
PROD_ROWS="$1"   # arquivo com version:name separados por ' | '
echo "drop database if exists $DB with (force); create database $DB;" | psql_db postgres
{
  echo "create schema supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, statements text[], name text, created_by text, idempotency_key text, rollback text[]);"
  tr '|' '\n' < "$PROD_ROWS" | sed 's/^ *//;s/ *$//' | grep . | awk -F: '{printf "insert into supabase_migrations.schema_migrations(version,name,statements) values (%c%s%c,%c%s%c,array[%cstmt-%s%c]);\n",39,$1,39,39,$2,39,39,$2,39}'
} | psql_db $DB
H="select md5(string_agg(version||':'||name, ',' order by version||':'||name)) from supabase_migrations.schema_migrations"
ST="select md5(string_agg(name||':'||array_to_string(statements,'#'), ',' order by name)) from supabase_migrations.schema_migrations"
H0=$(q $DB "$H"); S0=$(q $DB "$ST")
psql_db $DB < supabase/ops/20261103_reconcile_migration_history.sql >/dev/null
H1=$(q $DB "$H"); S1=$(q $DB "$ST")
set +e; psql_db $DB < supabase/ops/20261103_reconcile_migration_history.sql >/dev/null 2>&1; RC2=$?; set -e
H2=$(q $DB "$H")
psql_db $DB < supabase/ops/20261103_reconcile_migration_history_revert.sql >/dev/null
H3=$(q $DB "$H"); S3=$(q $DB "$ST")
echo "inicial=$H0 reconciliado=$H1 segunda_rc=$RC2 revertido=$H3"
[ "$H0" = "f13ee66fee74cc39a82cb2a69c99e205" ] && [ "$H1" = "c9924f1092689753d1bdfb59670aa8c4" ] \
  && [ "$RC2" -ne 0 ] && [ "$H2" = "$H1" ] && [ "$H3" = "$H0" ] && [ "$S0" = "$S1" ] && [ "$S0" = "$S3" ] \
  || { echo "RECONCILE=FAIL"; exit 1; }
echo "RECONCILE=PASS"
echo "drop database $DB with (force);" | psql_db postgres
