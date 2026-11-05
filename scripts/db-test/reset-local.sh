#!/usr/bin/env bash
# ============================================================================
# Reset do banco LOCAL descartável (equivalente funcional de
# `supabase db reset --local` para ambientes onde as imagens Docker do
# Supabase não podem ser baixadas).
#
# - Recria o banco bdflow_site_local do zero.
# - Aplica: shim supabase -> migrations (ordem lexicográfica) -> seed.sql
#   -> helpers de teste.
# - A baseline NÃO é editada em disco; apenas a linha do supabase_vault
#   (extensão proprietária indisponível fora da imagem Supabase) é comentada
#   no stream enviado ao psql. Desvio documentado no relatório.
#
# STATUS: TESTE_AUXILIAR_NAO_GATE — o gate final exige Supabase PG17 real.
#
# JAMAIS aponte este script para um banco remoto.
# ============================================================================
set -euo pipefail

DB_NAME="${BDFLOW_LOCAL_DB:-bdflow_recon_local}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

psql_db() { # psql_db <db>  (lê SQL do stdin)
  su postgres -c "psql -v ON_ERROR_STOP=1 -q -d $1 -f -"
}

echo "== recriando banco $DB_NAME =="
echo "drop database if exists $DB_NAME with (force);" | psql_db postgres
echo "create database $DB_NAME;" | psql_db postgres

echo "== shim supabase =="
psql_db "$DB_NAME" < scripts/db-test/shim-supabase.sql

echo "== migrations =="
for f in supabase/migrations/*.sql; do
  echo "   -> $f"
  # A publicação jurídica de 27/10 exige um site_admin existente (em
  # Production ele existe). O banco local nasce sem nenhum, então o harness
  # cria um admin de fixture IMEDIATAMENTE antes dela. Só local.
  case "$f" in
    *20261027154258_onboarding_legal_publication_v1.sql)
      psql_db "$DB_NAME" <<'SQL'
insert into auth.users (id, email)
  values ('00000000-0000-4000-8000-00000000ad00', 'harness-admin@local.invalid')
  on conflict (id) do nothing;
insert into public.site_admins (user_id)
  select '00000000-0000-4000-8000-00000000ad00'
   where not exists (select 1 from public.site_admins);
SQL
      ;;
  esac
  # Filtro exclusivo do harness: comenta a extensão supabase_vault.
  sed 's/^CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";/-- [harness local] supabase_vault indisponivel fora da imagem Supabase/' "$f" \
    | psql_db "$DB_NAME"
done

echo "== seed =="
psql_db "$DB_NAME" < supabase/seed.sql

echo "== helpers de teste =="
psql_db "$DB_NAME" < scripts/db-test/helpers.sql

echo "DB_RESET_LOCAL_AUXILIAR=PASS ($DB_NAME) [PG16 TESTE_AUXILIAR_NAO_GATE]"
