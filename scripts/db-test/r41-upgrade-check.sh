#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL da migration 20261113200000 (R4.1: manifesto das guardas,
# aprovação de lançamento, pré-requisito da QA) e do seu rollback, em bancos
# descartáveis. PGHOST=/tmp PGPORT=5433 para o PG17.
#
#   P1  base = R4 (worktree do commit-base) -> aplica (transação única)
#   P2  só mudam as 5 funções previstas, com mesma segurança e ACL; histórico
#       (SF-v1.4, preço público, cálculo v1..v3, pedidos, intenções,
#       documentos, modelos, catálogo) IDÊNTICO; catálogo das guardas =
#       manifesto publicado (SHA-256); nada aprovado nem ativado
#   P3  rollback devolve o catálogo IDÊNTICO ao da R4
#   P4  rollback recusado depois de aprovação/ativação
#   P5  base com guarda adulterada (gatilho em REPLICA; função executada
#       trocada): a migration NÃO aplica e nada muda
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
NOVA=supabase/migrations/20261113200000_commercial_guard_integrity_r41.sql
RB=supabase/rollback/20261113200000_commercial_guard_integrity_r41_rollback.sql
MANIF_SHA=$(cut -d' ' -f1 docs/release/R41_MANIFESTO_GUARDAS.json.sha256)
BASE_REF=${BASE_REF:-HEAD~1}
DB=r41_upgrade
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
echo "P1 aplica a migration sobre a R4 (transacao unica)"
if psql_1tx $DB < "$NOVA" > "$TMPD/apply.log" 2>&1; then passa "migration aplicou"; else falha "migration: $(tail -3 $TMPD/apply.log)"; fi
cat_ $DB > "$TMPD/depois.txt"

echo "P2 historico intacto, so mudou o previsto, manifesto conferido"
FN='commercial_activation_guard_fingerprint commercial_pricing_activation_log_guard admin_activate_pricing_rule commercial_pricing_activation_preflight commercial_build_instrument_snapshot'
FUNCS='commercial_activation_guard_fingerprint\(\)|commercial_pricing_activation_log_guard\(\)|admin_activate_pricing_rule\(integer,text\)|commercial_pricing_activation_preflight\(integer\)|commercial_build_instrument_snapshot\(uuid,uuid\)'
SUMIRAM=$(LC_ALL=C comm -23 "$TMPD/antes.txt" "$TMPD/depois.txt")
OUTRAS=$(echo "$SUMIRAM" | grep -v '^$' | grep -Ev "^F\|public\.($FUNCS)\|" || true)
[ -z "$OUTRAS" ] && passa "entre os objetos existentes so mudaram as 5 funcoes previstas" || falha "mudaram: $OUTRAS"
[ "$(echo "$SUMIRAM" | grep -Ec "^F\|public\.($FUNCS)\|")" = "5" ] && passa "as 5 funcoes foram estendidas" || falha "funcoes: $(echo "$SUMIRAM" | grep -c '^F|')"
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
[ "$(q $DB "select count(*) || '|' || max(catalog_sha256) from public.commercial_guard_manifests")" = "1|$MANIF_SHA" ] \
  && passa "manifesto aprovado gravado no banco = publicado" || falha "manifesto no banco"
[ "$(q $DB "select coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0)")" = "0" ] \
  && passa "nenhuma divergencia de guarda" || falha "divergencias: $(q $DB "select public.commercial_guard_integrity_failures()")"
VERIF=$(su postgres -c "psql -X -At -d $DB -f -" < supabase/ops/20261113_verificar_r41_somente_leitura.sql | grep -E '\|(true|false)$')
[ "$(echo "$VERIF" | grep -c '|false$')" = "0" ] && [ "$(echo "$VERIF" | grep -c '|true$')" = "8" ] \
  && passa "verificacao somente-leitura R4.1: 8/8 true" || falha "verificacao: $VERIF"
[ "$(q $DB "select count(*) from public.commercial_pricing_activation_approvals") $(q $DB "select count(*) from public.commercial_qa_operational_procedures") $(q $DB "select count(*) from public.commercial_pricing_activation_log")" = "0 0 0" ] \
  && passa "nenhuma aprovacao, procedimento de QA ou ativacao criados" || falha "dados criados"
[ "$(q $DB "select status from public.commercial_pricing_rules where version = 3")" = "active" ] && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "prepared" ] \
  && passa "SF-v1.4 vigente; SF-v1.5 so preparada" || falha "estado das regras"

echo "P3 rollback devolve o catalogo identico ao da R4"
if psql_db $DB < "$RB" > "$TMPD/rb.log" 2>&1; then passa "rollback aplicou"; else falha "rollback: $(tail -3 $TMPD/rb.log)"; fi
cat_ $DB > "$TMPD/volta.txt"
if diff -q "$TMPD/antes.txt" "$TMPD/volta.txt" >/dev/null; then passa "catalogo e dados identicos a R4 ($(wc -l < $TMPD/antes.txt) linhas)"
else falha "diferencas: $(diff $TMPD/antes.txt $TMPD/volta.txt | head -5)"; fi

echo "P4 rollback recusado depois de aprovacao e ativacao"
psql_1tx $DB < "$NOVA" > /dev/null
su postgres -c "psql -X -q -d $DB -f -" < scripts/db-test/helpers.sql > /dev/null 2>&1
psql_db $DB > /dev/null <<'SQL'
select tests.preparar_ativacao_sf_v15_qa('UPG', 'A');
select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ensaio de rollback R4.1');
SQL
set +e; SAIDA=$(psql_db $DB < "$RB" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ] && echo "$SAIDA" | grep -q rollback_r41_recusado \
   && [ "$(q $DB "select status from public.commercial_pricing_rules where version = 4")" = "active" ] \
   && [ "$(q $DB "select count(*) from public.commercial_guard_manifests")" = "1" ]; then
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

echo "P6 base com o texto das guardas fora do padrao do repositorio (como em Production: CRLF, sem comentarios): a migration reafirma e o manifesto confere"
(cd "$WT" && BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > "$TMPD/reset6.log" 2>&1)
psql_db $DB <<'SQL'
DO $deriva$
DECLARE f text; d text;
BEGIN
  FOREACH f IN ARRAY ARRAY['fase2a_touch_updated_at', 'ceo_emitir_instrumento', 'ceo_instrumento_imutavel',
                           'ceo_snapshot_v14_imutavel', 'cci_preencher_fatos_materiais',
                           'ceo_preencher_fatos_materiais', 'ceo_exigir_instrumento_quando_assinavel'] LOOP
    d := pg_catalog.pg_get_functiondef(('public.' || f || '()')::regprocedure);
    d := pg_catalog.regexp_replace(d, '\n[ \t]*--[^\n]*', '', 'g');
    d := pg_catalog.replace(d, E'\n', E'\r\n');
    EXECUTE d;
  END LOOP;
END $deriva$;
SQL
DIF=$(q $DB "select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('fase2a_touch_updated_at','ceo_emitir_instrumento','ceo_instrumento_imutavel','ceo_snapshot_v14_imutavel','cci_preencher_fatos_materiais','ceo_preencher_fatos_materiais','ceo_exigir_instrumento_quando_assinavel') and position(E'\r' in prosrc) > 0")
[ "$DIF" = "7" ] && passa "base com 7 funcoes em texto divergente (CRLF, sem comentarios)" || falha "P6 preparo: $DIF"
if psql_1tx $DB < "$NOVA" > "$TMPD/apply6.log" 2>&1 \
   && [ "$(q $DB "select encode(sha256(convert_to(public.commercial_guard_catalog()::text, 'UTF8')), 'hex')")" = "$MANIF_SHA" ]; then
  passa "migration aplicou e o catalogo vivo = manifesto publicado"
else falha "P6: $(tail -3 $TMPD/apply6.log)"; fi
echo "drop database $DB with (force);" | psql_db postgres

echo "R41_UPGRADE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
