#!/usr/bin/env bash
# ============================================================================
# R4.2.1 — ENSAIO DE UPGRADE E ROLLBACK (banco descartável local, nunca remoto)
#
#   uso: r421-upgrade-check.sh   (BASE_REF=<commit R4.2>, padrão 89363db;
#                                 PGHOST=/tmp PGPORT=5433 para o PG17 local)
#
#   U0 rollback e reaplicação da migration recusados fora do estado certo
#   U1 base R4.2 -> migration R4.2.1 numa transação: autoverificação,
#      manifestos R4.1/R4.2/R4.2.1, verificador somente leitura todo true
#   U2 estrutura do banco atualizado = estrutura de um banco novo na R4.2.1
#   U3 rollback -> estrutura IDÊNTICA à da R4.2; manifesto vigente R4.2;
#      verificador da R4.2 todo true
#   U4 reaplicação depois do rollback = mesma estrutura de U1
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
NOVA=supabase/migrations/20261116180000_commercial_artwork_change_integrity_r421.sql
RB=supabase/rollback/20261116180000_commercial_artwork_change_integrity_r421_rollback.sql
BASE_REF=${BASE_REF:-89363db}
SUF=${PGPORT:-5432}
psql_1tx() { su postgres -c "psql -X -v ON_ERROR_STOP=1 -q -1 -d $1 -f -"; }
q() { su postgres -c "psql -X -At -d $1 -c \"$2\""; }
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }
TMPD=$(mktemp -d); chmod 755 "$TMPD"; WT="$TMPD/base"
trap 'git -C "$RAIZ" worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$TMPD"' EXIT
git worktree add --detach "$WT" "$BASE_REF" > /dev/null 2>&1 || { echo "worktree falhou"; exit 2; }

# Estrutura: funções, gatilhos, restrições, índices, colunas, políticas
# (inclusive Storage), buckets e manifestos. Sem OIDs nem datas.
ESTR="select md5(string_agg(x, E'\n' order by x)) from (
  select 'f ' || pg_get_functiondef(p.oid) x from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
  union all select 'a ' || p.oid::regprocedure::text || coalesce(p.proacl::text, '') from pg_proc p where p.pronamespace = 'public'::regnamespace
  union all select 't ' || pg_get_triggerdef(t.oid) || t.tgenabled::text from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where c.relnamespace = 'public'::regnamespace and not t.tgisinternal
  union all select 'k ' || conrelid::regclass::text || ' ' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint
     where connamespace = 'public'::regnamespace
  union all select 'i ' || indexdef from pg_indexes where schemaname = 'public'
  union all select 'c ' || table_name || '.' || column_name || ' ' || data_type || ' ' || is_nullable || ' '
     || coalesce(column_default, '') || coalesce(generation_expression, '') from information_schema.columns where table_schema = 'public'
  union all select 'r ' || c.relname || coalesce(c.relacl::text, '') || c.relrowsecurity::text from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
  union all select 'p ' || schemaname || '.' || tablename || ' ' || policyname || ' ' || cmd || ' ' || coalesce(qual, '') || coalesce(with_check, '')
     from pg_policies where schemaname in ('public', 'storage')
  union all select 'b ' || id || public::text || coalesce(file_size_limit::text, '') || coalesce(allowed_mime_types::text, '') from storage.buckets
  union all select 'm ' || manifest_label || catalog_sha256 from public.commercial_guard_manifests) s"
VERIF_TRUE() { su postgres -c "psql -X -At -d $1 -f $2" 2>&1 | grep -E '\|(true|false)$' | grep -vc '|true$'; }

echo "== upgrade/rollback R4.2.1 | $(q postgres 'show server_version') | base $(git -C "$WT" rev-parse --short HEAD) =="
(cd "$WT" && BDFLOW_LOCAL_DB=r421_up_$SUF bash scripts/db-test/reset-local.sh > /tmp/r421_up_base_$SUF.log 2>&1) || { echo "reset base falhou"; exit 2; }
(BDFLOW_LOCAL_DB=r421_novo_$SUF bash scripts/db-test/reset-local.sh > /tmp/r421_up_novo_$SUF.log 2>&1) || { echo "reset novo falhou"; exit 2; }
E42=$(q r421_up_$SUF "$ESTR"); ENOVO=$(q r421_novo_$SUF "$ESTR")
[[ "$E42" =~ ^[0-9a-f]{32}$ && "$ENOVO" =~ ^[0-9a-f]{32}$ ]] || { echo "impressao da estrutura falhou"; exit 2; }

psql_1tx r421_up_$SUF < "$RB" > /tmp/r421_u0.log 2>&1
grep -q 'rollback_r421_recusado' /tmp/r421_u0.log && [ "$(q r421_up_$SUF "$ESTR")" = "$E42" ] \
  && passa "U0 rollback recusado sobre a R4.2 (nada muda)" || falha "U0 rollback sobre a R4.2"
psql_1tx r421_novo_$SUF < "$NOVA" > /tmp/r421_u0b.log 2>&1
grep -q 'r421_pre' /tmp/r421_u0b.log && [ "$(q r421_novo_$SUF "$ESTR")" = "$ENOVO" ] \
  && passa "U0 migration recusada sobre banco ja na R4.2.1 (nada muda)" || falha "U0 reaplicacao direta"

if psql_1tx r421_up_$SUF < "$NOVA" > /tmp/r421_u1.log 2>&1; then
  MAN=$(q r421_up_$SUF "select string_agg(manifest_label, ',' order by id) from public.commercial_guard_manifests")
  INT=$(q r421_up_$SUF "select coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0)")
  NF=$(VERIF_TRUE r421_up_$SUF supabase/ops/20261116_verificar_r421_somente_leitura.sql)
  [ "$MAN" = "R4.1,R4.2,R4.2.1" ] && [ "$INT" = 0 ] && [ "$NF" = 0 ] \
    && passa "U1 upgrade R4.2 -> R4.2.1 (autoverificacao, manifestos $MAN, verificador todo true)" || falha "U1 ($MAN, integ=$INT, falsos=$NF)"
else falha "U1 migration falhou: $(tail -2 /tmp/r421_u1.log)"; fi
EUP=$(q r421_up_$SUF "$ESTR")
[ "$EUP" = "$ENOVO" ] && passa "U2 estrutura atualizada = banco novo na R4.2.1 ($EUP)" || falha "U2 estrutura ($EUP x $ENOVO)"

if psql_1tx r421_up_$SUF < "$RB" > /tmp/r421_u3.log 2>&1; then
  ERB=$(q r421_up_$SUF "$ESTR")
  NF=$(VERIF_TRUE r421_up_$SUF "$WT/supabase/ops/20261116_verificar_r42_somente_leitura.sql")
  [ "$ERB" = "$E42" ] && [ "$NF" = 0 ] \
    && passa "U3 rollback: estrutura identica a R4.2 ($ERB) e verificador da R4.2 todo true" || falha "U3 ($ERB x $E42, falsos=$NF)"
else falha "U3 rollback falhou: $(tail -2 /tmp/r421_u3.log)"; fi

if psql_1tx r421_up_$SUF < "$NOVA" > /tmp/r421_u4.log 2>&1 && [ "$(q r421_up_$SUF "$ESTR")" = "$EUP" ]; then
  passa "U4 reaplicacao depois do rollback = mesma estrutura do upgrade"
else falha "U4 reaplicacao: $(tail -2 /tmp/r421_u4.log)"; fi

for d in r421_up_$SUF r421_novo_$SUF; do q postgres "drop database if exists $d with (force)" > /dev/null 2>&1; done
echo "R421_UPGRADE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
