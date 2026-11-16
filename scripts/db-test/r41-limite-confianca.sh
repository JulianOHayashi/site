#!/usr/bin/env bash
# ============================================================================
# R4.1 / item 3 — LIMITE ADMINISTRATIVO do dono do banco, demonstrado e
# detectado. Banco descartável local (nunca remoto); transações revertidas.
#
#   uso: r41-limite-confianca.sh   (PGHOST=/tmp PGPORT=5433 para o PG17 local)
#
#   L0 ativação autorizada (aprovação registrada)     -> verificação toda true
#   L1 replica: UPDATE direto, sem registro           -> detectado
#   L2 replica: registro + aprovação forjados, com
#      catálogo e SHA-256 corretos                    -> banco NÃO detecta;
#                                                        só o registro externo
#   L3 ativação autorizada, depois ENABLE REPLICA     -> detectado (estado R)
#   L4 ativação autorizada, depois troca da função
#      executada (mesmo nome e estado)                -> detectado (catálogo)
#   L5 DDL do dono anula a comparação e o registro    -> ativa; detectado
#   L6 L5 + restaura as funções depois do ato         -> banco NÃO detecta;
#                                                        só o registro externo
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=r41_limite_${PGPORT:-5432}
VERIF=$(pwd)/supabase/ops/20261116_verificar_r421_somente_leitura.sql
BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > /tmp/r41_limite_reset_${PGPORT:-5432}.log 2>&1 || { echo "reset falhou"; exit 2; }
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }
roda() { # roda <rotulo> <sql-antes-da-verificacao>
  { echo "begin;"; echo "\\o /dev/null"; echo "select tests.preparar_ativacao_sf_v15_qa('LIM', 'A');"; echo "\\o";
    echo "$2"; echo "\\i $VERIF"; echo "rollback;"; } \
  | su postgres -c "psql -X -At -v ON_ERROR_STOP=1 -d $DB -f -" 2>&1
}
echo "== limite administrativo R4.1 | $(su postgres -c "psql -X -At -d postgres -c 'show server_version'") | $(git rev-parse --short HEAD) =="
FALSOS() { printf '%s\n' "$1" | grep -E '\|(true|false)$' | grep -c '|false$'; }
ITEM() { printf '%s\n' "$1" | grep -F "$2" | grep -oE '(true|false)$'; }
RECIBO() { printf '%s\n' "$1" | grep -E '^recibo_ativacao\|' | cut -d'|' -f2-4; }
APROV() { printf '%s\n' "$1" | grep -E '^aprovacao_lancamento\|' | cut -d'|' -f3-4 | sort; }
ATIVA="select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao autorizada') \\gset r_"

R0=$(roda L0 "$ATIVA"); echo "$R0" | sed 's/^/    L0: /'
REC0=$(RECIBO "$R0"); APR0=$(APROV "$R0")
[ "$(FALSOS "$R0")" = 0 ] && [ -n "$REC0" ] && passa "L0 ativacao autorizada: verificacao toda true e recibo emitido" || falha "L0"

R1=$(roda L1 "set local session_replication_role = replica;
update public.commercial_pricing_rules set status = 'superseded' where version = 3;
update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4;
reset session_replication_role;
select 'L1 status v4: ' || status from public.commercial_pricing_rules where version = 4;")
echo "$R1" | sed 's/^/    L1: /'
printf '%s\n' "$R1" | grep -q 'L1 status v4: active' && [ "$(ITEM "$R1" 'exatamente um registro')" = false ] \
  && passa "L1 replica sem registro: ativou (limite real) e a verificacao DETECTA" || falha "L1"

R2=$(roda L2 "set local session_replication_role = replica;
insert into public.commercial_pricing_activation_approvals (id, pricing_rule_version, approval_reference, approval_document_sha256,
  approver_as_stated, approved_on_as_stated, registered_by_db_role, registered_at, registration_txid)
values ('00000000-0000-0000-0000-0000000000f2', 4, '[QA FICTICIO] aprovacao forjada em replica', repeat('f', 64),
  'Pessoa que nunca aprovou', current_date, session_user, now(), txid_current());
insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint,
  actor, txid, created_at, activation_approval_id, approval_document_sha256, guard_catalog_sha256, guard_manifest_id, executor_db_role)
select 4, '[QA FICTICIO] aprovacao forjada em replica', public.commercial_pricing_activation_preflight(4), m.catalog,
  session_user, txid_current(), now(), '00000000-0000-0000-0000-0000000000f2', repeat('f', 64), m.catalog_sha256, m.id, session_user
  from public.commercial_guard_manifests m order by m.id desc limit 1;
update public.commercial_pricing_rules set status = 'superseded' where version = 3;
update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4;
reset session_replication_role;")
echo "$R2" | sed 's/^/    L2: /'
[ "$(FALSOS "$R2")" = 0 ] && [ -n "$(RECIBO "$R2")" ] \
  && passa "L2 LIMITE: forja completa em replica passa em TODAS as verificacoes internas" \
  || falha "L2: esperado o limite (verificacao toda true)"
# Registro externo = o que foi aprovado e guardado fora do banco em L0.
APR2=$(APROV "$R2" | grep -vxF -f <(printf '%s\n' "$APR0") || true)
[ -n "$APR2" ] && ! grep -qxF "$(RECIBO "$R2")" <<< "$REC0" \
  && passa "L2 o confronto com o registro externo DETECTA a aprovacao e o recibo forjados ($APR2)" || falha "L2 externo"

R3=$(roda L3 "$ATIVA
alter table public.commercial_exclusivity_orders enable replica trigger ceo_pagamento_confere_snapshot;")
echo "$R3" | sed 's/^/    L3: /'
[ "$(ITEM "$R3" 'fora do estado O')" = false ] && [ "$(ITEM "$R3" 'um manifesto publicado')" = false ] \
  && passa "L3 ENABLE REPLICA depois da ativacao: DETECTADO" || falha "L3"

R4=$(roda L4 "$ATIVA
create function public.zz_inerte() returns trigger language plpgsql as \$f\$ begin return new; end \$f\$;
create or replace trigger ceo_pagamento_confere_snapshot before insert or update on public.commercial_exclusivity_orders
  for each row execute function public.zz_inerte();")
echo "$R4" | sed 's/^/    L4: /'
[ "$(ITEM "$R4" 'fora do estado O')" = true ] && [ "$(ITEM "$R4" 'um manifesto publicado')" = false ] \
  && passa "L4 funcao executada trocada (mesmo nome, estado O) depois da ativacao: DETECTADO" || falha "L4"

ANULA="create temp table orig_r41 on commit drop as
  select pg_get_functiondef(oid) d from pg_proc
   where oid in ('public.commercial_guard_integrity_failures()'::regprocedure,
                 'public.commercial_pricing_activation_log_guard()'::regprocedure);
create or replace function public.commercial_guard_integrity_failures() returns text[]
  language sql stable security definer set search_path to 'pg_catalog' as \$f\$ select array[]::text[] \$f\$;
create or replace function public.commercial_pricing_activation_log_guard() returns trigger
  language plpgsql set search_path to 'pg_catalog' as \$f\$
begin
  select m.catalog, m.catalog_sha256, m.id into new.guard_fingerprint, new.guard_catalog_sha256, new.guard_manifest_id
    from public.commercial_guard_manifests m order by m.id desc limit 1;
  select a.approval_document_sha256 into new.approval_document_sha256
    from public.commercial_pricing_activation_approvals a where a.id = new.activation_approval_id;
  new.actor := session_user; new.executor_db_role := session_user;
  new.txid := txid_current(); new.created_at := now();
  return new;
end \$f\$;
alter table public.commercial_exclusivity_orders disable trigger ceo_pagamento_confere_snapshot;
select 'L5 ativacao: ' || (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao com guardas anuladas')->>'ok');"

R5=$(roda L5 "$ANULA")
echo "$R5" | sed 's/^/    L5: /'
printf '%s\n' "$R5" | grep -q 'L5 ativacao: true' && [ "$(ITEM "$R5" 'um manifesto publicado')" = false ] \
  && [ "$(ITEM "$R5" 'fora do estado O')" = false ] \
  && passa "L5 DDL do dono anulando as guardas: ATIVOU (limite real) e a verificacao DETECTA" || falha "L5"

R6=$(roda L6 "$ANULA
select d from orig_r41 \\gexec
alter table public.commercial_exclusivity_orders enable trigger ceo_pagamento_confere_snapshot;")
echo "$R6" | sed 's/^/    L6: /'
printf '%s\n' "$R6" | grep -q 'L5 ativacao: true' && [ "$(FALSOS "$R6")" = 0 ] \
  && passa "L6 LIMITE: anular, ativar e restaurar as guardas passa em TODAS as verificacoes internas" || falha "L6"
APR6=$(APROV "$R6" | grep -vxF -f <(printf '%s\n' "$APR0") || true)
[ -n "$APR6" ] && ! grep -qxF "$(RECIBO "$R6")" <<< "$REC0" && passa "L6 o confronto com o registro externo DETECTA a aprovacao que nao consta dele ($APR6)" || falha "L6 externo"

echo "R41_LIMITE_ADMINISTRATIVO: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
