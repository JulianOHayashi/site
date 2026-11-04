#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL da migration 20261103120000 sobre um banco no estado de
# Production (auditoria 14): catálogo antigo de seis nichos e a exclusividade
# Grande Vitória nº 1 em formação, com as seis oportunidades livres.
#
# Cenário A: aplica a migration e confere o remapeamento D2.
# Cenário B: uma oportunidade de calçados reservada → a migration tem de
#            ABORTAR inteira, sem alterar nada.
#
# JAMAIS aponte este script para um banco remoto.
# ============================================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
NOVA=supabase/migrations/20261103120000_commercial_positions_segments.sql
BASE_SEED_REF="${BASE_SEED_REF:-origin/main}"

psql_db() { su postgres -c "psql -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
q() { su postgres -c "psql -d $1 -Atc \"$2\""; }

montar_estado_production() { # $1 = db
  local db="$1"
  echo "drop database if exists $db with (force);" | psql_db postgres
  echo "create database $db;" | psql_db postgres
  psql_db "$db" < scripts/db-test/shim-supabase.sql >/dev/null 2>&1
  for f in supabase/migrations/*.sql; do
    [ "$f" = "$NOVA" ] && continue
    case "$f" in
      *20261027154258_onboarding_legal_publication_v1.sql)
        psql_db "$db" <<'SQL' >/dev/null
insert into auth.users (id, email) values ('00000000-0000-4000-8000-00000000ad00','harness-admin@local.invalid') on conflict do nothing;
insert into public.site_admins (user_id) select '00000000-0000-4000-8000-00000000ad00' where not exists (select 1 from public.site_admins);
SQL
        ;;
    esac
    sed 's/^CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";/-- harness/' "$f" \
      | psql_db "$db" >/dev/null 2>&1
  done
  # Seed ANTERIOR à migration (catálogo antigo), como está em Production.
  git show "$BASE_SEED_REF":supabase/seed.sql | psql_db "$db" >/dev/null
  psql_db "$db" <<'SQL' >/dev/null
insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
select id, 1, 'forming', true from public.commercial_regions where slug = 'grande-vitoria';
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select e.id, n.code, n.contracted_quantity, 'available'
  from public.commercial_exclusivities e, public.commercial_niches n
 where e.sequence_number = 1;
SQL
}

echo "== Cenario A: estado de Production -> migration =="
montar_estado_production bdflow_upgrade_a
echo "antes:  $(q bdflow_upgrade_a "select string_agg(niche_code||':'||status, ',' order by niche_code) from commercial_opportunities")"
psql_db bdflow_upgrade_a < "$NOVA" >/dev/null
echo "depois: $(q bdflow_upgrade_a "select string_agg(niche_code||':'||status, ',' order by niche_code) from commercial_opportunities")"
A_ATIVOS=$(q bdflow_upgrade_a "select count(*)||'/'||sum(contracted_quantity) from commercial_niches where is_active")
A_POS=$(q bdflow_upgrade_a "select count(*)||'/'||sum(contracted_quantity) from commercial_opportunities")
A_LEG=$(q bdflow_upgrade_a "select count(*) from commercial_opportunities where niche_code like '%_footwear'")
A_AUD=$(q bdflow_upgrade_a "select count(*) from audit_logs where action='commercial_opportunity.position_remapped'")
A_FORM=$(q bdflow_upgrade_a "select jsonb_array_length(get_current_commercial_formation('ES','Vitória')->'opportunities')")
echo "ativos=$A_ATIVOS posicoes=$A_POS legados_em_oportunidade=$A_LEG auditoria=$A_AUD formacao=$A_FORM"
[ "$A_ATIVOS" = "6/84" ] && [ "$A_POS" = "6/84" ] && [ "$A_LEG" = "0" ] && [ "$A_AUD" = "2" ] && [ "$A_FORM" = "6" ] \
  || { echo "UPGRADE_A=FAIL"; exit 1; }
echo "UPGRADE_A=PASS"

echo "== Cenario A2: registro da versao 20261103120000 no historico =="
REG=supabase/ops/20261103_register_positions_segments_version.sql
HIST=scripts/db-test/fixtures-prod-migration-history-20261103.txt
q bdflow_upgrade_a "create schema supabase_migrations; create table supabase_migrations.schema_migrations (version text primary key, statements text[], name text, created_by text, idempotency_key text, rollback text[])" >/dev/null
tr '|' '\n' < "$HIST" | sed 's/^ *//;s/ *$//' | grep . | awk -F: '{printf "insert into supabase_migrations.schema_migrations(version,name) values (%c%s%c,%c%s%c);\n",39,$1,39,39,$2,39}' | psql_db bdflow_upgrade_a
set +e; psql_db bdflow_upgrade_a < "$REG" >/dev/null 2>&1; RC_SEM=$?; set -e     # sem reconciliar: tem de abortar
psql_db bdflow_upgrade_a < supabase/ops/20261103_reconcile_migration_history.sql >/dev/null
# adulteração: uma função com search_path diferente muda a impressão digital
q bdflow_upgrade_a "alter function public.list_commercial_segments() set search_path = public" >/dev/null
set +e; SAIDA_ADULT=$(psql_db bdflow_upgrade_a < "$REG" 2>&1); RC_ADULT=$?; set -e
echo "$SAIDA_ADULT" | grep -o 'impressao digital[^(]*' | head -1
q bdflow_upgrade_a "alter function public.list_commercial_segments() set search_path = pg_catalog" >/dev/null
psql_db bdflow_upgrade_a < "$REG" >/dev/null
set +e; psql_db bdflow_upgrade_a < "$REG" >/dev/null 2>&1; RC_DUP=$?; set -e     # segunda vez: tem de abortar
A2=$(q bdflow_upgrade_a "select count(*)||'/'||count(*) filter (where version='20261103120000') from supabase_migrations.schema_migrations")
echo "sem_reconciliar_rc=$RC_SEM adulterada_rc=$RC_ADULT registrado=$A2 repeticao_rc=$RC_DUP"
[ "$RC_SEM" -ne 0 ] && [ "$RC_ADULT" -ne 0 ] && [ "$A2" = "63/1" ] && [ "$RC_DUP" -ne 0 ] || { echo "REGISTER_A2=FAIL"; exit 1; }
echo "REGISTER_A2=PASS"

echo "== Cenario B: oportunidade de calcados reservada -> migration aborta =="
montar_estado_production bdflow_upgrade_b
q bdflow_upgrade_b "update commercial_opportunities set status='reserved', reserved_until=now()+interval '10 minutes' where niche_code='mens_footwear'" >/dev/null
set +e
SAIDA=$(psql_db bdflow_upgrade_b < "$NOVA" 2>&1); RC=$?
set -e
echo "$SAIDA" | grep -o 'd2_bloqueado[^"]*' | head -1
B_NICHOS=$(q bdflow_upgrade_b "select string_agg(code||':'||is_active, ',' order by sort_order) from commercial_niches")
B_TAB=$(q bdflow_upgrade_b "select count(*) from pg_tables where tablename='commercial_segments'")
echo "rc=$RC nichos=$B_NICHOS tabela_segmentos=$B_TAB"
[ "$RC" -ne 0 ] && [ "$B_TAB" = "0" ] && echo "$B_NICHOS" | grep -q 'mens_footwear:t' \
  || { echo "UPGRADE_B=FAIL"; exit 1; }
echo "UPGRADE_B=PASS (abortou sem alterar nada)"

echo "drop database bdflow_upgrade_a with (force); drop database bdflow_upgrade_b with (force);" | psql_db postgres

echo "== Cenario C: migration -> rollback volta exatamente ao estado anterior =="
RB=supabase/rollback/20261103120000_commercial_positions_segments_rollback.sql
HASH_SQL="select md5(string_agg(f||':'||h, ',' order by f)) from (select p.oid::regprocedure::text f, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') x"
# A ACL é comparada como CONJUNTO (a ordem dos itens em proacl não é semântica).
ACL_SQL="select md5(string_agg(x, ',' order by x)) from (select p.oid::regprocedure::text||':'||coalesce((select string_agg(a::text, ',' order by a::text) from unnest(p.proacl) a),'') x from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') t"
SCHEMA_SQL="select md5(string_agg(x, ',' order by x)) from (select table_name||'.'||column_name||':'||data_type x from information_schema.columns where table_schema='public') t"
CONS_SQL="select md5(string_agg(x, ',' order by x)) from (select conrelid::regclass||'.'||conname||':'||pg_get_constraintdef(oid) x from pg_constraint where connamespace='public'::regnamespace) t"
IDX_SQL="select md5(string_agg(x, ',' order by x)) from (select indexname||':'||indexdef x from pg_indexes where schemaname='public') t"
TRG_SQL="select md5(string_agg(x, ',' order by x)) from (select tgrelid::regclass||'.'||tgname||':'||tgfoid::regproc x from pg_trigger where not tgisinternal) t"
DADOS_SQL="select (select string_agg(code||':'||sort_order||':'||is_active, ',' order by code) from commercial_niches)||' | '||(select string_agg(niche_code||':'||status, ',' order by niche_code) from commercial_opportunities)"
montar_estado_production bdflow_upgrade_c
ANTES="$(q bdflow_upgrade_c "$HASH_SQL")/$(q bdflow_upgrade_c "$ACL_SQL")/$(q bdflow_upgrade_c "$SCHEMA_SQL")/$(q bdflow_upgrade_c "$CONS_SQL")/$(q bdflow_upgrade_c "$IDX_SQL")/$(q bdflow_upgrade_c "$TRG_SQL")"
DADOS_ANTES="$(q bdflow_upgrade_c "$DADOS_SQL")"
psql_db bdflow_upgrade_c < "$NOVA" >/dev/null
psql_db bdflow_upgrade_c < "$RB" >/dev/null
DEPOIS="$(q bdflow_upgrade_c "$HASH_SQL")/$(q bdflow_upgrade_c "$ACL_SQL")/$(q bdflow_upgrade_c "$SCHEMA_SQL")/$(q bdflow_upgrade_c "$CONS_SQL")/$(q bdflow_upgrade_c "$IDX_SQL")/$(q bdflow_upgrade_c "$TRG_SQL")"
DADOS_DEPOIS="$(q bdflow_upgrade_c "$DADOS_SQL")"
echo "funcoes/acl/colunas/constraints/indices/gatilhos antes=$ANTES"
echo "funcoes/acl/colunas/constraints/indices/gatilhos depois=$DEPOIS"
echo "dados antes:  $DADOS_ANTES"
echo "dados depois: $DADOS_DEPOIS"
[ "$ANTES" = "$DEPOIS" ] && [ "$DADOS_ANTES" = "$DADOS_DEPOIS" ] || { echo "ROLLBACK_C=FAIL"; exit 1; }
echo "ROLLBACK_C=PASS"
echo "drop database bdflow_upgrade_c with (force);" | psql_db postgres

echo "== Cenario D: modelo novo ja em uso -> rollback recusa =="
montar_estado_production bdflow_upgrade_d
psql_db bdflow_upgrade_d < "$NOVA" >/dev/null
q bdflow_upgrade_d "update commercial_opportunities set status='reserved', reserved_until=now()+interval '10 minutes' where niche_code='others'" >/dev/null
set +e
SAIDA=$(psql_db bdflow_upgrade_d < "$RB" 2>&1); RC=$?
set -e
echo "$SAIDA" | grep -o 'rollback_bloqueado[^"]*' | head -1
D_SEG=$(q bdflow_upgrade_d "select count(*) from pg_tables where tablename='commercial_segments'")
[ "$RC" -ne 0 ] && [ "$D_SEG" = "1" ] || { echo "ROLLBACK_D=FAIL"; exit 1; }
echo "ROLLBACK_D=PASS (recusou sem alterar nada)"
echo "drop database bdflow_upgrade_d with (force);" | psql_db postgres

echo "== Cenario E: permissao de Production preservada (reserva fechada para authenticated) =="
montar_estado_production bdflow_upgrade_e
q bdflow_upgrade_e "revoke execute on function public.create_commercial_checkout_intent(uuid,text,text) from authenticated" >/dev/null
ACL_ANTES=$(q bdflow_upgrade_e "select has_function_privilege('authenticated','public.create_commercial_checkout_intent(uuid,text,text)','EXECUTE')||'/'||has_function_privilege('authenticated','public.join_my_commercial_future_queue(uuid,text)','EXECUTE')||'/'||has_function_privilege('service_role','public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer)','EXECUTE')")
psql_db bdflow_upgrade_e < "$NOVA" >/dev/null
ACL_DEPOIS=$(q bdflow_upgrade_e "select has_function_privilege('authenticated','public.create_commercial_checkout_intent(uuid,text,text,uuid)','EXECUTE')||'/'||has_function_privilege('authenticated','public.join_my_commercial_future_queue(uuid,text,uuid)','EXECUTE')||'/'||has_function_privilege('service_role','public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer,uuid)','EXECUTE')")
psql_db bdflow_upgrade_e < "$RB" >/dev/null
ACL_VOLTA=$(q bdflow_upgrade_e "select has_function_privilege('authenticated','public.create_commercial_checkout_intent(uuid,text,text)','EXECUTE')||'/'||has_function_privilege('authenticated','public.join_my_commercial_future_queue(uuid,text)','EXECUTE')||'/'||has_function_privilege('service_role','public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer)','EXECUTE')")
echo "reserva/fila/manual antes=$ACL_ANTES depois=$ACL_DEPOIS rollback=$ACL_VOLTA"
[ "$ACL_ANTES" = "false/true/true" ] && [ "$ACL_DEPOIS" = "$ACL_ANTES" ] && [ "$ACL_VOLTA" = "$ACL_ANTES" ] \
  || { echo "ACL_E=FAIL"; exit 1; }
echo "ACL_E=PASS"
echo "drop database bdflow_upgrade_e with (force);" | psql_db postgres
