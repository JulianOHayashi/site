#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL da migration 20261113150000 (R3: QA só em produtos no benefício
# direto, sem QA no dinheiro) e do seu rollback, em bancos descartáveis.
# PGHOST=/tmp PGPORT=5433 para o PG17 local. Nunca remoto.
#
#   P1  base = SF-v1.5 preparada SEM a R3 (worktree do commit-base) -> aplica
#   P2  histórico intacto: SF-v1.4, preço público, cálculo v1..v3, pedidos,
#       intenções, documentos, modelos, catálogo e fidelidade IDÊNTICOS;
#       atributos e ACL das funções estendidas preservados
#   P3  rollback devolve o catálogo IDÊNTICO ao de antes
#   P4  rollback é recusado depois de uma ativação, e nada é desfeito
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
NOVA=supabase/migrations/20261113150000_commercial_qa_in_kind_settlement_modes_r3.sql
RB=supabase/rollback/20261113150000_commercial_qa_in_kind_settlement_modes_r3_rollback.sql
BASE_REF=${BASE_REF:-HEAD~1}
DB=r3_upgrade
psql_db() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
q() { su postgres -c "psql -X -At -d $1 -c \"$2\""; }
TMPD=$(mktemp -d); chmod 755 "$TMPD"
WT="$TMPD/base"
trap 'git -C "$RAIZ" worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$TMPD"' EXIT
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }

echo "== versão: $(q postgres 'show server_version') | base $BASE_REF =="
git worktree add -q --detach "$WT" "$BASE_REF"
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

echo "P2 historico intacto e so mudou o previsto"
FUNCS='calculate_niche_contract_pricing\(text,boolean,integer\)|cci_resposta_intencao\((public\.)?commercial_checkout_intents,boolean\)|commercial_build_instrument_snapshot\(uuid,uuid\)|commercial_pricing_rules_protect\(\)|cci_aplicar_autoridade_v14\(\)|ceo_aplicar_autoridade_v14\(\)|admin_confirm_manual_bdflow_payment\(uuid,bigint,text,text\)'
SUMIRAM=$(LC_ALL=C comm -23 "$TMPD/antes.txt" "$TMPD/depois.txt")
ESPERADO="^F\|public\.($FUNCS)\||^K\|(public\.)?commercial_(exclusivity_orders|checkout_intents)\|c(eo|ci)_financiamento_v14_coerente\||^D\|(commercial_exclusivity_orders|commercial_checkout_intents|commercial_pricing_rules\(<=3\)|commercial_instrument_templates)\|"
OUTRAS=$(echo "$SUMIRAM" | grep -v '^$' | grep -Ev "$ESPERADO" || true)
[ -z "$OUTRAS" ] && passa "so mudaram as 7 funcoes estendidas e os 2 CHECKs v1.4 re-escopados" || falha "mudaram: $OUTRAS"
[ "$(echo "$SUMIRAM" | grep -Ec "^F\|public\.($FUNCS)\|")" = "7" ] && passa "as 7 funcoes foram estendidas" || falha "funcoes: $(echo "$SUMIRAM" | grep -c '^F|')"
for f in calculate_niche_contract_pricing cci_resposta_intencao commercial_build_instrument_snapshot commercial_pricing_rules_protect cci_aplicar_autoridade_v14 ceo_aplicar_autoridade_v14 admin_confirm_manual_bdflow_payment; do
  A=$(grep "^F|public.$f(" "$TMPD/antes.txt" | cut -d'|' -f4-); D=$(grep "^F|public.$f(" "$TMPD/depois.txt" | cut -d'|' -f4-)
  [ "$A" = "$D" ] && passa "$f: SECURITY/volatilidade/search_path/ACL preservados" || falha "$f: $A -> $D"
done
for d in 'D|commercial_pricing_schedule(<=3)|' 'D|preco_publico|' 'D|calculo_v1_v2_v3|' 'D|legal_documents|' 'D|commercial_advertising_specs|' 'D|commercial_fidelity_records|' 'D|commercial_contract_activity_catalog|'; do
  grep -qF "$d" "$TMPD/antes.txt" && [ "$(grep -F "$d" "$TMPD/antes.txt")" = "$(grep -F "$d" "$TMPD/depois.txt")" ] \
    && passa "identico: ${d#D|}" || falha "divergiu: $d"
done
# Linhas históricas: só ganham colunas novas NULL (nenhum valor reescrito).
for t in commercial_exclusivity_orders commercial_checkout_intents; do
  [ "$(q $DB "select count(*) from public.$t where settlement_terms_id is not null or qa_policy is not null or qa_in_kind_cents is not null or qa_cash_cents is not null or mei_in_kind_cents is not null or cash_adjustment_cents is not null")" = "0" ] \
    && passa "$t: linhas historicas sem valor R3 (colunas novas NULL)" || falha "$t: linha historica recebeu valor R3"
done
[ "$(q $DB "select count(*) from public.commercial_pricing_rules where version <= 3 and qa_policy is not null")" = "0" ] \
  && passa "regras <= 3 sem politica R3 (interpretacao historica preservada)" || falha "regra historica recebeu politica"
[ "$(q $DB "select count(*) from public.commercial_instrument_templates where settlement_model is not null")" = "0" ] \
  && passa "nenhum modelo de instrumento alterado" || falha "modelo alterado"
[ "$(q $DB "select status from public.commercial_pricing_rules where version = 3")" = "active" ] && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "prepared" ] \
  && passa "SF-v1.4 vigente; SF-v1.5 so preparada" || falha "estado das regras"

echo "P3 rollback devolve o catalogo identico"
if psql_db $DB < "$RB" > "$TMPD/rb.log" 2>&1; then passa "rollback aplicou"; else falha "rollback: $(tail -3 $TMPD/rb.log)"; fi
cat_ $DB > "$TMPD/volta.txt"
if diff -q "$TMPD/antes.txt" "$TMPD/volta.txt" >/dev/null; then passa "catalogo e dados identicos ao estado anterior ($(wc -l < $TMPD/antes.txt) linhas)"
else falha "diferencas: $(diff $TMPD/antes.txt $TMPD/volta.txt | head -5)"; fi

echo "P4 rollback recusado depois de ativacao"
psql_db $DB < "$NOVA" > /dev/null
su postgres -c "psql -X -q -d $DB -f -" < scripts/db-test/helpers.sql > /dev/null 2>&1
psql_db $DB > /dev/null <<'SQL'
select tests.preparar_ativacao_sf_v15_qa('UPG', 'A');
select public.admin_activate_pricing_rule(4, '[QA FICTICIO] ensaio de rollback');
SQL
set +e; SAIDA=$(psql_db $DB < "$RB" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ] && echo "$SAIDA" | grep -q rollback_bloqueado \
   && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "active" ] \
   && [ "$(q $DB "select count(*) from public.commercial_settlement_terms")" = "8" ]; then
  passa "rollback recusado e nada desfeito"; else falha "P4 rc=$RC"; fi

echo "drop database $DB with (force);" | psql_db postgres
echo "R3_UPGRADE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
