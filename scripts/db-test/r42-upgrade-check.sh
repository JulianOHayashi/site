#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL da migration 20261116120000 (R4.2: alteração de arte e
# fidelidade independente da reutilização) e do seu rollback, em bancos
# descartáveis. PGHOST=/tmp PGPORT=5433 para o PG17.
#
#   P1  base = R4.1 (worktree do commit-base) -> aplica (transação única)
#   P2  só mudam as 6 funções previstas e os 2 CHECKs de bandeiras, com mesma
#       segurança e ACL; histórico (SF-v1.4, preço público, cálculo v1..v3,
#       pedidos, intenções, documentos, modelos) IDÊNTICO; manifesto vigente
#       = R4.2 publicado, R4.1 preservado; nada criado
#   P3  rollback devolve o catálogo IDÊNTICO ao da R4.1
#   P4  rollback recusado com solicitação existente
#   P5  base com guarda adulterada: a migration NÃO aplica e nada muda
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
NOVA=supabase/migrations/20261116120000_commercial_artwork_change_fidelity_r42.sql
RB=supabase/rollback/20261116120000_commercial_artwork_change_fidelity_r42_rollback.sql
MANIF_SHA=$(cut -d' ' -f1 docs/release/R42_MANIFESTO_GUARDAS.json.sha256)
R41_SHA=$(cut -d' ' -f1 docs/release/R41_MANIFESTO_GUARDAS.json.sha256)
BASE_REF=${BASE_REF:-HEAD~1}
DB=r42_upgrade
psql_db() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -d $1 -f -"; }
psql_1tx() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -1 -d $1 -f -"; }
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
  UNION ALL SELECT 'commercial_exclusivity_orders', md5(coalesce(string_agg((to_jsonb(x) - 'flag_production_new_units' - 'flag_unit_reference_cents' - 'flag_production_charge_cents' - 'flag_reuse_set_id' - 'flag_reuse_inspection_id' - 'artwork_change_request_id')::text, ',' ORDER BY x.id), '')) FROM public.commercial_exclusivity_orders x
  UNION ALL SELECT 'commercial_checkout_intents', md5(coalesce(string_agg((to_jsonb(x) - 'flag_production_new_units' - 'flag_unit_reference_cents' - 'flag_production_charge_cents' - 'flag_reuse_set_id' - 'flag_reuse_inspection_id' - 'artwork_change_request_id')::text, ',' ORDER BY x.id), '')) FROM public.commercial_checkout_intents x
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
echo "P1 aplica a migration sobre a R4.1 (transacao unica)"
if psql_1tx $DB < "$NOVA" > "$TMPD/apply.log" 2>&1; then passa "migration aplicou"; else falha "migration: $(tail -3 $TMPD/apply.log)"; fi
cat_ $DB > "$TMPD/depois.txt"

echo "P2 historico intacto, so mudou o previsto, manifesto conferido"
FN='cci_validar_producao_bandeiras ceo_validar_producao_bandeiras commercial_flag_facts_imutaveis create_commercial_checkout_intent request_customization_image_path register_customization_image'
FUNCS='cci_validar_producao_bandeiras\(\)|ceo_validar_producao_bandeiras\(\)|commercial_flag_facts_imutaveis\(\)|create_commercial_checkout_intent\(uuid,text,text,uuid\)|request_customization_image_path\(uuid\)|register_customization_image\(uuid,text,text,bigint,text\)'
SUMIRAM=$(LC_ALL=C comm -23 "$TMPD/antes.txt" "$TMPD/depois.txt")
OUTRAS=$(echo "$SUMIRAM" | grep -v '^$' | grep -Ev "^F\|public\.($FUNCS)\|" | grep -Ev "^K\|public\.commercial_(checkout_intents|exclusivity_orders)\|c(ci|eo)_bandeiras_coerente\|" || true)
[ -z "$OUTRAS" ] && passa "entre os objetos existentes so mudaram as 6 funcoes previstas e os 2 CHECKs de bandeiras" || falha "mudaram: $OUTRAS"
[ "$(echo "$SUMIRAM" | grep -Ec "^F\|public\.($FUNCS)\|")" = "6" ] && passa "as 6 funcoes foram estendidas" || falha "funcoes: $(echo "$SUMIRAM" | grep -c '^F|')"
for f in $FN; do
  A=$(grep "^F|public.$f(" "$TMPD/antes.txt" | cut -d'|' -f4-); D=$(grep "^F|public.$f(" "$TMPD/depois.txt" | cut -d'|' -f4-)
  [ "$A" = "$D" ] && passa "$f: SECURITY/volatilidade/search_path/ACL preservados" || falha "$f: $A -> $D"
done
for d in 'D|commercial_pricing_schedule(<=3)|' 'D|commercial_pricing_rules(<=3)|' 'D|preco_publico|' 'D|calculo_v1_v2_v3|' 'D|commercial_exclusivity_orders|' 'D|commercial_checkout_intents|' 'D|legal_documents|' 'D|commercial_instrument_templates|' 'D|commercial_contract_activity_catalog|' 'D|commercial_fidelity_records|'; do
  grep -qF "$d" "$TMPD/antes.txt" && [ "$(grep -F "$d" "$TMPD/antes.txt")" = "$(grep -F "$d" "$TMPD/depois.txt")" ] \
    && passa "identico: ${d#D|}" || falha "divergiu: $d"
done
OBT=$(q $DB "select encode(sha256(convert_to(public.commercial_guard_catalog()::text, 'UTF8')), 'hex')")
[ "$OBT" = "$MANIF_SHA" ] && passa "catalogo vivo das guardas = manifesto publicado (SHA-256 $OBT)" || falha "catalogo $OBT != manifesto $MANIF_SHA"
[ "$(q $DB "select string_agg(manifest_label || '=' || catalog_sha256, ',' order by id) from public.commercial_guard_manifests")" = "R4.1=$R41_SHA,R4.2=$MANIF_SHA" ] \
  && passa "manifestos no banco: R4.1 preservado, R4.2 vigente (ambos publicados)" || falha "manifestos no banco"
[ "$(q $DB "select coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0)")" = "0" ] \
  && passa "nenhuma divergencia de guarda" || falha "divergencias: $(q $DB "select public.commercial_guard_integrity_failures()")"
VERIF=$(su postgres -c "psql -X -At -d $DB -f -" < supabase/ops/20261116_verificar_r42_somente_leitura.sql | grep -E '\|(true|false)$')
[ "$(echo "$VERIF" | grep -c '|false$')" = "0" ] && [ "$(echo "$VERIF" | grep -c '|true$')" = "10" ] \
  && passa "verificacao somente-leitura R4.2: 10/10 true" || falha "verificacao: $VERIF"
[ "$(q $DB "select count(*) from public.commercial_pricing_activation_approvals") $(q $DB "select count(*) from public.commercial_qa_operational_procedures") $(q $DB "select count(*) from public.commercial_pricing_activation_log") $(q $DB "select count(*) from public.commercial_artwork_change_requests") $(q $DB "select count(*) from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'")" = "0 0 0 0 0" ] \
  && passa "nenhuma aprovacao, procedimento de QA, ativacao, solicitacao ou preco de dinheiro criados" || falha "dados criados"
[ "$(q $DB "select status from public.commercial_pricing_rules where version = 3")" = "active" ] && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "prepared" ] \
  && passa "SF-v1.4 vigente; SF-v1.5 so preparada" || falha "estado das regras"

echo "P3 rollback devolve o catalogo identico ao da R4.1"
if psql_db $DB < "$RB" > "$TMPD/rb.log" 2>&1; then passa "rollback aplicou"; else falha "rollback: $(tail -3 $TMPD/rb.log)"; fi
cat_ $DB > "$TMPD/volta.txt"
if diff -q "$TMPD/antes.txt" "$TMPD/volta.txt" >/dev/null; then passa "catalogo e dados identicos a R4.1 ($(wc -l < $TMPD/antes.txt) linhas)"
else falha "diferencas: $(diff $TMPD/antes.txt $TMPD/volta.txt | head -5)"; fi

echo "P4 rollback recusado com solicitacao existente"
psql_1tx $DB < "$NOVA" > /dev/null
psql_db $DB > /dev/null <<'SQL'
-- Solicitação gravada sem as FKs (replica), só para exercitar a guarda do rollback.
set session_replication_role = replica;
insert into public.commercial_artwork_change_requests
  (company_id, base_order_id, fidelity_identity, target_campaign, requested_by)
values (gen_random_uuid(), gen_random_uuid(), 'pharmacy', 'next_campaign', gen_random_uuid());
reset session_replication_role;
SQL
set +e; SAIDA=$(psql_db $DB < "$RB" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ] && echo "$SAIDA" | grep -q rollback_r42_recusado \
   && [ "$(q $DB "select count(*) from public.commercial_guard_manifests")" = "2" ] \
   && [ "$(q $DB "select count(*) from public.commercial_artwork_change_requests")" = "1" ]; then
  passa "rollback recusado e nada desfeito"; else falha "P4 rc=$RC"; fi
echo "drop database $DB with (force);" | psql_db postgres

echo "P5 base com guarda adulterada: a migration nao aplica"
for adult in "alter table public.commercial_exclusivity_orders enable replica trigger ceo_pagamento_confere_snapshot" \
             "create function public.zz_inerte() returns trigger language plpgsql as \$f\$ begin return new; end \$f\$; create or replace trigger ceo_pagamento_confere_snapshot before insert or update on public.commercial_exclusivity_orders for each row execute function public.zz_inerte()"; do
  (cd "$WT" && BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > "$TMPD/reset5.log" 2>&1)
  echo "$adult;" | psql_db $DB
  cat_ $DB > "$TMPD/antes5.txt"
  set +e; SAIDA=$(psql_1tx $DB < "$NOVA" 2>&1); RC=$?; set -e
  cat_ $DB > "$TMPD/depois5.txt"
  if [ $RC -ne 0 ] && echo "$SAIDA" | grep -q manifesto_guardas_divergente && diff -q "$TMPD/antes5.txt" "$TMPD/depois5.txt" >/dev/null; then
    passa "recusada (manifesto_guardas_divergente), nada aplicado: ${adult:0:70}..."
  else falha "P5 rc=$RC: ${adult:0:70}"; fi
  echo "drop database $DB with (force);" | psql_db postgres
done

echo "R42_UPGRADE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
