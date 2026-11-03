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
