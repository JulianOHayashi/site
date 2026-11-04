#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL do registro da versão 20261103120000 (63ª), em bancos
# descartáveis no estado de Production. Rode com PGPORT=5433 para o PG17.
#
#   R1  migration via psql -f   -> diagnóstico vazio -> registro -> 63 versões
#   R2  migration em consulta única (modo SQL Editor/execute_sql) -> idem
#   R3  registro com search_path de sessão diferente ('' e extensions) -> aceita
#   R4  repetição do registro -> aborta, continua 63
#   N1  histórico não reconciliado -> aborta, nada gravado
#   N2  corpo de função alterado -> aborta e nomeia a função (conteudo)
#   N3  atributo alterado (search_path) -> aborta (atributos)
#   N4  sobrecarga extra com o mesmo nome -> aborta (inesperada)
#   N5  índice da migration ausente -> aborta (objetos)
#   N6  migration que falhou (D2 bloqueado) -> aborta, nada gravado
#   N7  arquivo com CRLF -> a migration aborta (integridade do transporte)
#   N8  client_encoding LATIN1 -> a migration aborta (integridade do transporte)
#
# JAMAIS aponte este script para um banco remoto.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
NOVA=supabase/migrations/20261103120000_commercial_positions_segments.sql
REG=supabase/ops/20261103_register_positions_segments_version.sql
DIAG=supabase/ops/20261104_fingerprint_diagnostico.sql
RECON=supabase/ops/20261103_reconcile_migration_history.sql
HIST=scripts/db-test/fixtures-prod-migration-history-20261103.txt
eval "$(sed -n '/^BASE_SEED_REF=/p;/^psql_db()/p;/^q()/p' scripts/db-test/upgrade-positions-segments-check.sh)"
eval "$(sed -n '/^montar_estado_production()/,/^}/p' scripts/db-test/upgrade-positions-segments-check.sh)"
TMPD=$(mktemp -d); chmod 755 "$TMPD"; trap 'rm -rf "$TMPD"' EXIT
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }

historico() { # $1 db: tabela do CLI com as 62 linhas de Production, reconciliadas
  q "$1" "create schema if not exists supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, statements text[], name text, created_by text, idempotency_key text, rollback text[])" >/dev/null
  tr '|' '\n' < "$HIST" | sed 's/^ *//;s/ *$//' | grep . \
    | awk -F: '{printf "insert into supabase_migrations.schema_migrations(version,name) values (%c%s%c,%c%s%c);\n",39,$1,39,39,$2,39}' | psql_db "$1"
  psql_db "$1" < "$RECON" >/dev/null
}
clonar() { echo "drop database if exists $2 with (force); create database $2 template $1;" | psql_db postgres; }
registrar() { # $1 db [$2 PGOPTIONS] -> rc; saída em $TMPD/reg.out
  set +e; su postgres -c "PGOPTIONS='${2:-}' psql -X -v ON_ERROR_STOP=1 -q -d $1 -f -" < "$REG" > "$TMPD/reg.out" 2>&1; local rc=$?; set -e; return $rc
}
linhas() { q "$1" "select count(*)||'/'||count(*) filter (where version='20261103120000') from supabase_migrations.schema_migrations"; }
diag() { su postgres -c "psql -X -At -q -d $1 -f -" < "$DIAG"; }

echo "== versão: $(q postgres 'show server_version') =="
# Base 1: migration aplicada com psql -f
montar_estado_production reg_base_f >/dev/null 2>&1
psql_db reg_base_f < "$NOVA" >/dev/null
historico reg_base_f
# Base 2: migration aplicada em consulta única
montar_estado_production reg_base_q >/dev/null 2>&1
cp "$NOVA" "$TMPD/m.sql"; chmod 644 "$TMPD/m.sql"
su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d reg_base_q -c \"\$(cat $TMPD/m.sql)\"" >/dev/null
historico reg_base_q

echo "R1 psql -f"
D=$(diag reg_base_f); [ -z "$D" ] && passa "diagnostico vazio" || falha "diagnostico: $D"
clonar reg_base_f r1
if registrar r1 && [ "$(linhas r1)" = "63/1" ]; then passa "registrado: 63 versoes"; else falha "R1 $(cat $TMPD/reg.out)"; fi
echo "R4 repeticao"
if ! registrar r1 && [ "$(linhas r1)" = "63/1" ]; then passa "segunda execucao abortou, continua 63"; else falha "R4"; fi

echo "R2 consulta unica"
D=$(diag reg_base_q); [ -z "$D" ] && passa "diagnostico vazio" || falha "diagnostico: $D"
clonar reg_base_q r2
if registrar r2 && [ "$(linhas r2)" = "63/1" ]; then passa "registrado: 63 versoes"; else falha "R2 $(cat $TMPD/reg.out)"; fi

echo "R3 search_path de sessao"
for sp in "-c search_path=" "-c search_path=extensions" "-c search_path=public"; do
  clonar reg_base_f r3
  if registrar r3 "$sp" && [ "$(linhas r3)" = "63/1" ]; then passa "aceita com [$sp]"; else falha "R3 [$sp] $(cat $TMPD/reg.out)"; fi
done

echo "N1 historico nao reconciliado"
clonar reg_base_f n1
psql_db n1 < supabase/ops/20261103_reconcile_migration_history_revert.sql >/dev/null
if ! registrar n1 && grep -q "historico nao esta no estado reconciliado" "$TMPD/reg.out" && [ "$(linhas n1)" = "62/0" ]; then passa "abortou, 62 versoes"; else falha "N1"; fi

echo "N2 corpo alterado"
clonar reg_base_f n2
psql_db n2 <<'SQL' >/dev/null
create or replace function public.list_commercial_segments() returns jsonb
  language sql stable security definer set search_path to 'pg_catalog'
  as $x$ select '[]'::jsonb $x$;
SQL
if ! registrar n2 && grep -q "list_commercial_segments() => conteudo" "$TMPD/reg.out" && [ "$(linhas n2)" = "62/0" ]; then passa "abortou e nomeou a funcao (conteudo)"; else falha "N2 $(cat $TMPD/reg.out)"; fi
diag n2 | grep -q "list_commercial_segments() | conteudo\|list_commercial_segments()|conteudo" && passa "diagnostico aponta a mesma funcao" || falha "N2 diag: $(diag n2)"

echo "N3 atributo alterado"
clonar reg_base_f n3
q n3 "alter function public.commercial_resolve_position_segment(text,uuid,uuid,uuid,boolean) set search_path = public" >/dev/null
if ! registrar n3 && grep -q "commercial_resolve_position_segment(.*) => atributos" "$TMPD/reg.out" && [ "$(linhas n3)" = "62/0" ]; then passa "abortou (atributos)"; else falha "N3 $(cat $TMPD/reg.out)"; fi

echo "N4 sobrecarga extra"
clonar reg_base_f n4
q n4 "create function public.list_commercial_segments(p int) returns int language sql as 'select 1'" >/dev/null
if ! registrar n4 && grep -q "list_commercial_segments(integer) => inesperada" "$TMPD/reg.out" && [ "$(linhas n4)" = "62/0" ]; then passa "abortou (inesperada)"; else falha "N4 $(cat $TMPD/reg.out)"; fi

echo "N5 indice ausente"
clonar reg_base_f n5
q n5 "drop index public.ceo_segmento_por_exclusividade_idx" >/dev/null
if ! registrar n5 && grep -q "objetos da migration ausentes: indice:ceo_segmento_por_exclusividade_idx" "$TMPD/reg.out" && [ "$(linhas n5)" = "62/0" ]; then passa "abortou (objetos)"; else falha "N5 $(cat $TMPD/reg.out)"; fi

echo "N6 migration que falhou (D2 bloqueado)"
montar_estado_production n6 >/dev/null 2>&1
q n6 "update commercial_opportunities set status='reserved', reserved_until=now()+interval '10 minutes' where niche_code='mens_footwear'" >/dev/null
set +e; psql_db n6 < "$NOVA" >/dev/null 2>&1; RCM=$?; set -e
historico n6
if [ "$RCM" -ne 0 ] && ! registrar n6 && grep -q "ausente" "$TMPD/reg.out" && [ "$(linhas n6)" = "62/0" ]; then passa "migration abortou e o registro tambem, 62 versoes"; else falha "N6 rc=$RCM $(cat $TMPD/reg.out)"; fi

echo "N7 arquivo com CRLF"
montar_estado_production n7 >/dev/null 2>&1
sed 's/$/\r/' "$NOVA" > "$TMPD/crlf.sql"; chmod 644 "$TMPD/crlf.sql"
set +e; SAIDA=$(su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d n7 -f $TMPD/crlf.sql" 2>&1); RCM=$?; set -e
historico n7
if [ "$RCM" -ne 0 ] && echo "$SAIDA" | grep -q transporte_corrompido \
   && [ "$(q n7 "select count(*) from pg_class where relname='commercial_segments'")" = "0" ] \
   && ! registrar n7 && [ "$(linhas n7)" = "62/0" ]; then passa "migration abortou inteira; registro recusado"; else falha "N7 rc=$RCM"; fi

echo "N8 client_encoding LATIN1"
montar_estado_production n8 >/dev/null 2>&1
set +e; SAIDA=$(su postgres -c "PGCLIENTENCODING=LATIN1 psql -X -v ON_ERROR_STOP=1 -q -d n8 -f -" < "$NOVA" 2>&1); RCM=$?; set -e
historico n8
if [ "$RCM" -ne 0 ] && echo "$SAIDA" | grep -q transporte_corrompido \
   && [ "$(q n8 "select count(*) from pg_class where relname='commercial_segments'")" = "0" ] \
   && ! registrar n8 && [ "$(linhas n8)" = "62/0" ]; then passa "migration abortou inteira; registro recusado"; else falha "N8 rc=$RCM"; fi

for d in reg_base_f reg_base_q r1 r2 r3 n1 n2 n3 n4 n5 n6 n7 n8; do
  echo "drop database if exists $d with (force);" | psql_db postgres
done
echo "REGISTER_CHECK: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
