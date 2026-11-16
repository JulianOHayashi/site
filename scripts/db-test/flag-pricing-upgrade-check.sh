#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL da migration 20261112120000 (SF-v1.5, produção de bandeiras) e
# do seu rollback, em bancos descartáveis. PGPORT=5433 para o PG17. Nunca remoto.
#
#   P1  base = main sem a migration (worktree do commit-base) -> aplica
#   P2  só mudam os objetos previstos: 4 funções estendidas, CHECK de status
#       das regras, ACL da agenda; SF-v1.4, preço público, cálculo histórico,
#       pedidos, intenções, documentos, templates, especificações e
#       fidelidade IDÊNTICOS; atributos e ACL das funções preservados
#   P3  rollback devolve o catálogo IDÊNTICO ao de antes
#   P4  rollback é recusado depois da ativação, e nada é desfeito
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
NOVA=supabase/migrations/20261112120000_commercial_flag_production_pricing_sf_v15.sql
RB=supabase/rollback/20261112120000_commercial_flag_production_pricing_sf_v15_rollback.sql
BASE_REF=${BASE_REF:-92f189ec967dccd2943ccfa0f606c678a7a793b9}
DB=sfv15_upgrade
psql_db() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
q() { su postgres -c "psql -X -At -d $1 -c \"$2\""; }
TMPD=$(mktemp -d); chmod 755 "$TMPD"
WT="$TMPD/base"
trap 'git -C "$RAIZ" worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$TMPD"' EXIT
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }

echo "== versão: $(q postgres 'show server_version') | base $BASE_REF =="
git worktree add -q "$WT" "$BASE_REF"
chmod -R a+rX "$WT"
[ ! -f "$WT/$NOVA" ] || { echo "a base ja contem a migration"; exit 1; }
(cd "$WT" && BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > "$TMPD/reset.log" 2>&1)

cat > "$TMPD/catalogo.sql" <<'SQL'
SET search_path = pg_catalog;
SELECT 'F|' || p.oid::regprocedure::text || '|' || md5(p.prosrc) || '|' || p.prosecdef::text || '|' || p.provolatile::text
       || '|' || coalesce(array_to_string(p.proconfig, ','), '')
       || '|' || coalesce((SELECT string_agg(a::text, ',' ORDER BY a::text) FROM unnest(p.proacl) a), '')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
UNION ALL
SELECT 'C|' || c.relname || '.' || a.attname || '|' || format_type(a.atttypid, a.atttypmod) || '|' || a.attnotnull::text
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
UNION ALL
SELECT 'K|' || conrelid::regclass::text || '|' || conname || '|' || pg_get_constraintdef(oid)
  FROM pg_constraint WHERE connamespace = 'public'::regnamespace
UNION ALL
SELECT 'I|' || indexrelid::regclass::text || '|' || pg_get_indexdef(indexrelid)
  FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid WHERE c.relnamespace = 'public'::regnamespace
UNION ALL
SELECT 'T|' || tgrelid::regclass::text || '|' || tgname || '|' || tgenabled::text
  FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text LIKE 'public.%'
UNION ALL
SELECT 'G|' || c.relname || '|' || coalesce((SELECT string_agg(a::text, ',' ORDER BY a::text) FROM unnest(c.relacl) a), '')
  FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
UNION ALL
SELECT 'D|' || t || '|' || h FROM (
  SELECT 'legal_documents' t, md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) h FROM public.legal_documents x
  UNION ALL SELECT 'legal_acceptances', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.legal_acceptances x
  UNION ALL SELECT 'commercial_master_agreements', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_master_agreements x
  UNION ALL SELECT 'commercial_exclusivity_orders', md5(coalesce(string_agg((to_jsonb(x) - 'flag_production_new_units' - 'flag_unit_reference_cents' - 'flag_production_charge_cents' - 'flag_reuse_set_id' - 'flag_reuse_inspection_id')::text, ',' ORDER BY x.id), '')) FROM public.commercial_exclusivity_orders x
  UNION ALL SELECT 'commercial_checkout_intents', md5(coalesce(string_agg((to_jsonb(x) - 'flag_production_new_units' - 'flag_unit_reference_cents' - 'flag_production_charge_cents' - 'flag_reuse_set_id' - 'flag_reuse_inspection_id')::text, ',' ORDER BY x.id), '')) FROM public.commercial_checkout_intents x
  UNION ALL SELECT 'commercial_pricing_schedule(<=3)', md5(coalesce(string_agg((to_jsonb(x) - 'new_flag_units' - 'flag_unit_reference_cents' - 'flag_production_charge_cents')::text, ',' ORDER BY (to_jsonb(x) - 'new_flag_units' - 'flag_unit_reference_cents' - 'flag_production_charge_cents')::text), '')) FROM public.commercial_pricing_schedule x WHERE x.pricing_rule_version <= 3
  UNION ALL SELECT 'commercial_pricing_rules(<=3)', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.version), '')) FROM public.commercial_pricing_rules x WHERE x.version <= 3
  UNION ALL SELECT 'preco_publico', md5(public.get_public_niche_pricing()::text || public.get_public_formation_economics()::text)
  UNION ALL SELECT 'calculo_v1_v2_v3', md5(string_agg(public.calculate_niche_contract_pricing(n.code, f, v)::text, ',' ORDER BY n.code, f, v)) FROM public.commercial_niches n, (VALUES (true), (false)) b(f), generate_series(1, 3) v WHERE n.is_active
  UNION ALL SELECT 'commercial_niches', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.code), '')) FROM public.commercial_niches x
  UNION ALL SELECT 'commercial_segments', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_segments x
  UNION ALL SELECT 'commercial_contract_activity_catalog', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_contract_activity_catalog x
  UNION ALL SELECT 'commercial_instrument_templates', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_instrument_templates x
  UNION ALL SELECT 'commercial_advertising_specs', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_advertising_specs x
  UNION ALL SELECT 'commercial_fidelity_records', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_fidelity_records x
) d
ORDER BY 1;
SQL
cat_() { su postgres -c "psql -X -At -q -d $1 -f $TMPD/catalogo.sql" | grep -v '^SET$' | LC_ALL=C sort; }

cat_ $DB > "$TMPD/antes.txt"
echo "P1 aplica a migration sobre a base"
if psql_db $DB < "$NOVA" > "$TMPD/apply.log" 2>&1; then passa "migration aplicou"; else falha "migration: $(tail -3 $TMPD/apply.log)"; fi
cat_ $DB > "$TMPD/depois.txt"

echo "P2 so mudou o previsto"
FUNCS='calculate_niche_contract_pricing\(text,boolean,integer\)|create_commercial_checkout_intent\(uuid,text,text,uuid\)|cci_resposta_intencao\((public\.)?commercial_checkout_intents,boolean\)|commercial_build_instrument_snapshot\(uuid,uuid\)'
ESPERADO_SUMIR="^F\|public\.($FUNCS)\||^K\|(public\.)?commercial_pricing_rules\|cpr_status_allowed\||^G\|commercial_pricing_schedule\|"
SUMIRAM=$(LC_ALL=C comm -23 "$TMPD/antes.txt" "$TMPD/depois.txt")
OUTRAS=$(echo "$SUMIRAM" | grep -v '^$' | grep -Ev "$ESPERADO_SUMIR" || true)
[ -z "$OUTRAS" ] && passa "entre os objetos existentes so mudaram as 4 funcoes, o CHECK de status e a ACL da agenda" || falha "mudaram: $OUTRAS"
[ "$(echo "$SUMIRAM" | grep -Ec "^F\|public\.($FUNCS)\|")" = "4" ] && passa "as 4 funcoes foram estendidas" || falha "funcoes estendidas: $(echo "$SUMIRAM" | grep -c '^F|')"
for f in calculate_niche_contract_pricing create_commercial_checkout_intent cci_resposta_intencao commercial_build_instrument_snapshot; do
  A=$(grep "^F|public.$f(" "$TMPD/antes.txt" | cut -d'|' -f4-); D=$(grep "^F|public.$f(" "$TMPD/depois.txt" | cut -d'|' -f4-)
  [ "$A" = "$D" ] && passa "$f: SECURITY/volatilidade/search_path/ACL preservados" || falha "$f: $A -> $D"
done
for d in 'D|commercial_pricing_schedule(<=3)|' 'D|commercial_pricing_rules(<=3)|' 'D|preco_publico|' 'D|calculo_v1_v2_v3|' 'D|commercial_exclusivity_orders|' 'D|commercial_checkout_intents|' 'D|legal_documents|' 'D|commercial_instrument_templates|' 'D|commercial_advertising_specs|' 'D|commercial_fidelity_records|'; do
  grep -qF "$d" "$TMPD/antes.txt" && [ "$(grep -F "$d" "$TMPD/antes.txt")" = "$(grep -F "$d" "$TMPD/depois.txt")" ] \
    && passa "identico: ${d#D|}" || falha "divergiu: $d"
done
NOVAS=$(LC_ALL=C comm -13 "$TMPD/antes.txt" "$TMPD/depois.txt" | grep -Ev "^F\|public\.($FUNCS)\|" || true)
FORA=$(echo "$NOVAS" | grep -v '^$' | grep -Ev 'flag|bandeiras|commercial_pricing_rules_protect|commercial_pricing_schedule_protect|commercial_pricing_protect_truncate|cpr_protect|cps_protect|cps_bandeiras|cpr_status_allowed|^G\|commercial_pricing_schedule\||ceo_inspecao_reuso|cfs_|cfi_' || true)
[ -z "$FORA" ] && passa "objetos novos restritos a precificacao com bandeiras e inventario" || falha "novos fora do escopo: $FORA"
grep -q '^G|commercial_pricing_schedule|.*service_role=r/postgres' "$TMPD/depois.txt" && passa "agenda: service_role so le" || falha "ACL da agenda"
[ "$(q $DB "select status from public.commercial_pricing_rules where version = 3")" = "active" ] && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "prepared" ] \
  && passa "SF-v1.4 vigente; SF-v1.5 so preparada" || falha "estado das regras"

echo "P3 rollback devolve o catalogo identico"
if psql_db $DB < "$RB" > "$TMPD/rb.log" 2>&1; then passa "rollback aplicou"; else falha "rollback: $(tail -3 $TMPD/rb.log)"; fi
cat_ $DB > "$TMPD/volta.txt"
if diff -q "$TMPD/antes.txt" "$TMPD/volta.txt" >/dev/null; then passa "catalogo e dados identicos ao estado anterior ($(wc -l < $TMPD/antes.txt) linhas)"
else falha "diferencas: $(diff $TMPD/antes.txt $TMPD/volta.txt | head -5)"; fi

echo "P4 rollback recusado depois da ativacao"
psql_db $DB < "$NOVA" > /dev/null
q $DB "update public.commercial_pricing_rules set status = 'superseded' where version = 3; update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4" >/dev/null
set +e; SAIDA=$(psql_db $DB < "$RB" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ] && echo "$SAIDA" | grep -q rollback_bloqueado \
   && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "active" ] \
   && [ "$(q $DB "select count(*) from public.commercial_pricing_schedule where pricing_rule_version = 4")" = "4" ]; then
  passa "rollback recusado e nada desfeito"; else falha "P4 rc=$RC"; fi

echo "drop database $DB with (force);" | psql_db postgres
echo "SF_V15_UPGRADE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
