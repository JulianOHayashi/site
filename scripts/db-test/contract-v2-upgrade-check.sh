#!/usr/bin/env bash
# ============================================================================
# Ensaio LOCAL da migration 20261110120000 (contratos V2) e do seu rollback,
# em bancos descartáveis. Rode com PGPORT=5433 para o PG17. Nunca remoto.
#
#   U1  base = main sem a migration (worktree do commit-base) -> aplica
#   U2  NADA além do construtor do snapshot muda: demais funções (corpo,
#       atributos, ACL), preços, regras, documentos, aceites, pedidos
#   U3  rollback devolve o catálogo IDÊNTICO ao de antes (funções, ACL,
#       colunas, constraints, índices, gatilhos, dados)
#   U4  rollback é recusado depois que a infraestrutura V2 é usada
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
NOVA=supabase/migrations/20261110120000_contract_v2_vehicle_visual_advertising.sql
RB=supabase/rollback/20261110120000_contract_v2_vehicle_visual_advertising_rollback.sql
BASE_REF=${BASE_REF:-97b74ef77cfe4b81eb332b11c47ff72083fd75aa}
DB=cv2_upgrade
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
[ ! -f "$WT/$NOVA" ] || { echo "a base ja contem a migration"; exit 1; }
(cd "$WT" && BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > "$TMPD/reset.log" 2>&1)

# Catálogo e dados comparáveis. ACL comparada como conjunto.
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
  UNION ALL SELECT 'commercial_exclusivity_orders', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_exclusivity_orders x
  UNION ALL SELECT 'commercial_checkout_intents', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_checkout_intents x
  UNION ALL SELECT 'commercial_pricing_schedule', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY to_jsonb(x)::text), '')) FROM public.commercial_pricing_schedule x
  UNION ALL SELECT 'commercial_niches', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.code), '')) FROM public.commercial_niches x
  UNION ALL SELECT 'commercial_segments', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_segments x
  UNION ALL SELECT 'commercial_contract_activity_catalog', md5(coalesce(string_agg(to_jsonb(x)::text, ',' ORDER BY x.id), '')) FROM public.commercial_contract_activity_catalog x
  UNION ALL SELECT 'templates(v1)', md5(coalesce(string_agg((to_jsonb(x) - 'advertising_modality' - 'requires_advertising_spec')::text, ',' ORDER BY x.id), '')) FROM public.commercial_instrument_templates x
) d
ORDER BY 1;
SQL
chmod 644 "$TMPD/catalogo.sql"
cat_() { su postgres -c "psql -X -At -q -d $1 -f $TMPD/catalogo.sql" | grep -v '^SET$' | LC_ALL=C sort; }

cat_ $DB > "$TMPD/antes.txt"
echo "U1 aplica a migration sobre a base"
if psql_db $DB < "$NOVA" > "$TMPD/apply.log" 2>&1; then passa "migration aplicou"; else falha "migration: $(tail -3 $TMPD/apply.log)"; fi
cat_ $DB > "$TMPD/depois.txt"

echo "U2 nada fora do escopo mudou"
# Linhas que existiam antes e sumiram/mudaram:
SUMIRAM=$(LC_ALL=C comm -23 "$TMPD/antes.txt" "$TMPD/depois.txt")
ESPERADO_SUMIR='^F\|public\.commercial_build_instrument_snapshot\(uuid,uuid\)\|'
OUTRAS=$(echo "$SUMIRAM" | grep -v '^$' | grep -Ev "$ESPERADO_SUMIR" || true)
[ -z "$OUTRAS" ] && passa "so o construtor do snapshot mudou entre os objetos existentes" || falha "mudaram: $OUTRAS"
echo "$SUMIRAM" | grep -Eq "$ESPERADO_SUMIR" && passa "construtor do snapshot foi estendido" || falha "construtor nao mudou"
NOVAS=$(LC_ALL=C comm -13 "$TMPD/antes.txt" "$TMPD/depois.txt" | grep -v '^F|public.commercial_build_instrument_snapshot\|^F|commercial_build_instrument_snapshot' || true)
FORA=$(echo "$NOVAS" | grep -v '^$' | grep -Ev 'commercial_advertising_specs|cas_|commercial_order_effective_activity|commercial_instrument_templates\.(advertising_modality|requires_advertising_spec)|cit_modalidade_valida|cit_especificacao_exige_modalidade' || true)
[ -z "$FORA" ] && passa "objetos novos restritos a especificacao, modalidade e atividade efetiva" || falha "novos fora do escopo: $FORA"
grep -q '^F|public.commercial_build_instrument_snapshot(uuid,uuid)|[0-9a-f]*|true|s|search_path=pg_catalog|' "$TMPD/depois.txt" \
  && passa "construtor mantem SECURITY DEFINER, STABLE e search_path" || falha "atributos do construtor"
ACL_A=$(grep '^F|public.commercial_build_instrument_snapshot' "$TMPD/antes.txt" | awk -F'|' '{print $NF}')
ACL_D=$(grep '^F|public.commercial_build_instrument_snapshot' "$TMPD/depois.txt" | awk -F'|' '{print $NF}')
[ "$ACL_A" = "$ACL_D" ] && passa "ACL do construtor preservada ($ACL_D)" || falha "ACL $ACL_A -> $ACL_D"

echo "U3 rollback devolve o catalogo identico"
if psql_db $DB < "$RB" > "$TMPD/rb.log" 2>&1; then passa "rollback aplicou"; else falha "rollback: $(tail -3 $TMPD/rb.log)"; fi
cat_ $DB > "$TMPD/volta.txt"
if diff -q "$TMPD/antes.txt" "$TMPD/volta.txt" >/dev/null; then passa "catalogo e dados identicos ao estado anterior ($(wc -l < $TMPD/antes.txt) linhas)"
else falha "diferencas: $(diff $TMPD/antes.txt $TMPD/volta.txt | head -5)"; fi

echo "U4 rollback recusado depois de uso"
psql_db $DB < "$NOVA" > /dev/null
q $DB "insert into public.commercial_advertising_specs (spec_code, spec_version, modality, artwork_reference_width_mm, artwork_reference_height_mm, source_hash) values ('[QA] X','0','vehicle_roof_visual_flag',490,305,repeat('e',64))" >/dev/null
set +e; SAIDA=$(psql_db $DB < "$RB" 2>&1); RC=$?; set -e
if [ $RC -ne 0 ] && echo "$SAIDA" | grep -q rollback_bloqueado \
   && [ "$(q $DB "select count(*) from public.commercial_advertising_specs")" = "1" ]; then
  passa "rollback recusado e nada desfeito"; else falha "U4 rc=$RC"; fi

echo "drop database $DB with (force);" | psql_db postgres
echo "CONTRACT_V2_UPGRADE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
