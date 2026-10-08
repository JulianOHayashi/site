#!/usr/bin/env bash
# ============================================================================
# P0-1 — PROVA DE CORRIDA DO ACORDO MESTRE, COM DUAS SESSÕES REAIS
#
# Por que este script existe separado das suítes: o harness SQL roda uma única
# sessão psql, e numa sessão só a guarda antiga (SELECT ... WHERE status =
# 'signed', sem lock) recusa um Mestre revogado exatamente como a nova. A suíte
# 250 passa com e sem a correção — verificado por execução. Portanto a suíte NÃO
# prova o P0-1. Este script prova.
#
# O defeito original: entre a guarda ler o Mestre como 'signed' e o INSERT do
# pedido, uma revogação concorrente podia commitar. O pedido nascia amarrado a um
# Acordo Mestre que, no instante do commit, já não regia nada. A única amarra
# entre pedido e Mestre é a FK, que garante EXISTÊNCIA e nunca STATUS.
#
# COMO A PROVA DISCRIMINA A CORREÇÃO
# O script NÃO escreve `FOR UPDATE` em lugar algum — se escrevesse, provaria a
# semântica do PostgreSQL e não o comportamento da função. Ele chama a RPC real
# `admin_register_manual_commercial_order` dentro de uma transação que fica
# ABERTA, e observa de fora:
#
#   1. `pg_locks` mostra a tupla do Acordo Mestre travada pela transação da RPC.
#   2. Uma revogação concorrente BLOQUEIA enquanto essa transação não commita.
#
# Sem a migration 20261007140000 a RPC não trava a linha, e as duas observações
# falham: nenhum lock de tupla aparece e a revogação commita de imediato. O
# INSERT do pedido pega FOR KEY SHARE na linha do Mestre por causa da FK, mas
# esse modo NÃO conflita com a mudança de `status`, que é coluna não-chave — por
# isso a FK sozinha não produz o bloqueio, e o bloqueio observado é do lock
# explícito da guarda.
#
# JAMAIS aponte este script para um banco remoto.
# ============================================================================
set -uo pipefail

DB_NAME="${BDFLOW_LOCAL_DB:-bdflow_recon_local}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORK="$(mktemp -d /var/tmp/p01-race.XXXXXX)"
chmod 755 "$WORK"
trap 'rm -rf "$WORK"' EXIT

q() { su postgres -c "psql -q -d $DB_NAME -At -c \"$1\""; }
qf() { su postgres -c "psql -q -d $DB_NAME -At -f $1"; }

# ---------------------------------------------------------------------------
# Fixture própria: empresa, Acordo Mestre vigente e oportunidade livre. Depende
# dos helpers tests.* , que o reset-local.sh instala.
# ---------------------------------------------------------------------------
cat > "$WORK/setup.sql" <<'SQL'
\set ON_ERROR_STOP on
select tests.mk_user('admin_p01race@teste.local') as uid_admin \gset
insert into public.site_admins (user_id) values ((:'uid_admin')::uuid)
on conflict do nothing;

select r.id as regr from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'regr')::uuid, 251, 'forming', false)
returning id as exclr \gset

insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'exclr')::uuid, 'mens_footwear', 12, 'available')
returning id as oppr \gset

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('25100001000139','Empresa P01 Race','p01race@teste.local','Viana','ES')
returning id as appr \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'appr')::uuid,'25100001000139','Empresa P01 Race',
        'p01race@teste.local','Viana','ES','active')
returning id as compr \gset

select tests.mk_user('titular_p01race@teste.local') as uid_t \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'compr')::uuid, (:'uid_t')::uuid, 'partner_owner',
        'Titular P01 Race', 'application_promotion', 'active');

-- assinar_mestre_qa chama admin_register_master_agreement, que exige admin real.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select (tests.assinar_mestre_qa((:'compr')::uuid, 'AM-P01-RACE') ->> 'ok');
commit;

select 'FIXTURE|'||:'uid_admin'||'|'||:'compr'||'|'||:'oppr';
SQL

echo "== preparando fixture =="
SETUP="$(qf "$WORK/setup.sql" 2>&1 | grep '^FIXTURE|' || true)"
if [ -z "$SETUP" ]; then
  echo "P01_RACE=FAIL (fixture nao pode ser preparada; rode apos reset-local.sh)"
  qf "$WORK/setup.sql" 2>&1 | tail -5
  exit 1
fi
UID_ADMIN="$(echo "$SETUP" | cut -d'|' -f2)"
COMP="$(echo "$SETUP" | cut -d'|' -f3)"
OPP="$(echo "$SETUP" | cut -d'|' -f4)"
MA="$(q "select id from public.commercial_master_agreements
          where company_id='$COMP' and status='signed';")"
if [ -z "$MA" ]; then
  echo "P01_RACE=FAIL (Acordo Mestre da fixture nao ficou vigente)"; exit 1
fi
echo "empresa=$COMP  mestre=$MA  oportunidade=$OPP"

falhas=0

# ---------------------------------------------------------------------------
# Sessão A: chama a RPC REAL e mantém a transação aberta por 6 s.
# Nenhum FOR UPDATE escrito aqui — o lock, se existir, é o da própria função.
# ---------------------------------------------------------------------------
cat > "$WORK/a.sql" <<SQL
begin isolation level read committed;
select set_config('request.jwt.claims',
  json_build_object('role','authenticated','sub','$UID_ADMIN')::text, true);
set local role authenticated;
select (public.admin_register_manual_commercial_order(
          '$OPP'::uuid, '$COMP'::uuid, 'v1', now() - interval '1 day',
          'Titular P01 Race', (now() + interval '30 days')::date,
          'direct_benefits', 'doc://p01-race') ->> 'ok') as rpc_ok;
reset role;
select pg_sleep(6);
rollback;
SQL
chmod 644 "$WORK"/*.sql

su postgres -c "psql -q -d $DB_NAME -At -f $WORK/a.sql" > "$WORK/a.log" 2>&1 &
A_PID=$!
sleep 2

# ---- Contexto (NÃO é prova): locks de tabela observados durante a RPC aberta.
# RowShareLock aparece com ou sem a correção, porque a FK do pedido já faz
# SELECT ... FOR KEY SHARE na linha do Mestre. Por isso este número é apenas
# informativo e não entra na contagem de falhas.
TRAVA_REL="$(q "select coalesce(string_agg(distinct l.mode, ','), 'nenhum')
                  from pg_locks l join pg_class c on c.oid = l.relation
                 where c.relname = 'commercial_master_agreements';")"
echo "CONTEXTO: modos de lock na tabela do Mestre durante a RPC aberta: $TRAVA_REL"
echo "          (informativo: a FK sozinha ja produz RowShareLock)"

# ---- PROVA: a revogação concorrente bloqueia até a RPC terminar?
# Este é o discriminador. O FOR KEY SHARE da FK NÃO conflita com a mudança de
# `status`, que é coluna não-chave (FOR NO KEY UPDATE). Só o FOR UPDATE
# explícito da guarda bloqueia. Sem a correção, este UPDATE commita em ~0 ms.
INICIO=$(date +%s%N)
q "update public.commercial_master_agreements
      set status='superseded', superseded_at=now()
    where id='$MA' and status='signed';" >/dev/null 2>&1
FIM=$(date +%s%N)
wait $A_PID
ESPERA_MS=$(( (FIM - INICIO) / 1000000 ))

RPC_OK="$(grep -c '^true$' "$WORK/a.log" || true)"
echo "PROVA: a revogacao concorrente esperou ${ESPERA_MS} ms pelo lock da RPC"
if [ "${RPC_OK:-0}" -lt 1 ]; then
  echo "  FAIL  a RPC nao criou o pedido; sem isso a medicao nao prova nada"
  sed -n '1,12p' "$WORK/a.log"
  falhas=$((falhas+1))
elif [ "$ESPERA_MS" -ge 2000 ]; then
  echo "  PASS  a RPC criou o pedido E manteve o Mestre travado ate o commit"
else
  echo "  FAIL  a revogacao commitou de imediato: a janela de corrida esta aberta"
  falhas=$((falhas+1))
fi

# A transação de A terminou em rollback: nenhum pedido ficou no banco.
q "update public.commercial_master_agreements
      set status='signed', superseded_at=null where id='$MA';" >/dev/null 2>&1

echo
if [ "$falhas" -gt 0 ]; then
  echo "P01_RACE=FAIL ($falhas falha(s))"
  exit 1
fi
echo "P01_RACE=PASS (prova de corrida) [PG16 TESTE_AUXILIAR_NAO_GATE]"
