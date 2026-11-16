#!/usr/bin/env bash
# SUPERADO pela R4.1 (20261113200000): vale para o checkout da R4. Com a R4.1
# use scripts/db-test/r41-limite-confianca.sh.
# ============================================================================
# R4 / item 1 — LIMITE DE CONFIANÇA do dono do banco, demonstrado e detectado.
# Banco descartável local (nunca remoto); tudo em transações revertidas.
#
#   uso: r4-limite-confianca.sh   (PGHOST=/tmp PGPORT=5433 para o PG17 local)
#
#   L0 ativação autorizada + recibo externo          -> verificação toda true
#   L1 replica: UPDATE direto, sem registro           -> detectado (sem registro)
#   L2 replica: UPDATE + registro forjado com a
#      impressão digital correta                      -> banco NÃO detecta;
#                                                        só o recibo externo
#   L3 ativação autorizada, depois DISABLE TRIGGER    -> detectado
#   L4 ativação autorizada, depois DDL numa guarda    -> detectado
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
DB=r4_limite_${PGPORT:-5432}
VERIF=supabase/ops/20261113_verificar_r4_somente_leitura.sql
BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > /tmp/r4_limite_reset_${PGPORT:-5432}.log 2>&1 || { echo "reset falhou"; exit 2; }
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }
roda() { # roda <rotulo> <sql-antes-da-verificacao>  -> imprime "item|valor" e recibos
  { echo "begin;"; echo "\\o /dev/null"; echo "select tests.preparar_ativacao_sf_v15_qa('LIM', 'A');"; echo "\\o";
    echo "$2"; echo "\\i $VERIF"; echo "rollback;"; } \
  | su postgres -c "psql -X -At -v ON_ERROR_STOP=1 -d $DB -f -" 2>&1
}
echo "== limite de confianca | $(su postgres -c "psql -X -At -d postgres -c 'show server_version'") | $(git rev-parse --short HEAD) =="
FALSOS() { printf '%s\n' "$1" | grep -E '\|(true|false)$' | grep -c '|false$'; }
ITEM() { printf '%s\n' "$1" | grep -F "$2" | grep -oE '(true|false)$'; }
RECIBOS() { printf '%s\n' "$1" | grep -E '^4\|' ; }

ATIVA="select public.admin_activate_pricing_rule(4, '[QA FICTICIO] ativacao autorizada') \\gset r_"
R0=$(roda L0 "$ATIVA"); echo "$R0" | sed 's/^/    L0: /'
REC0=$(RECIBOS "$R0")
[ "$(FALSOS "$R0")" = 0 ] && [ -n "$REC0" ] && passa "L0 ativacao autorizada: verificacao toda true e recibo emitido" || falha "L0"

R1=$(roda L1 "set local session_replication_role = replica;
update public.commercial_pricing_rules set status = 'superseded' where version = 3;
update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4;
reset session_replication_role;
select 'L1 status v4: ' || status from public.commercial_pricing_rules where version = 4;")
echo "$R1" | sed 's/^/    L1: /'
printf '%s\n' "$R1" | grep -q 'L1 status v4: active' && [ "$(ITEM "$R1" 'exatamente um registro')" = false ] \
  && passa "L1 replica sem registro: ativou (limite real) e a verificacao DETECTA (versao sem registro)" || falha "L1"

R2=$(roda L2 "set local session_replication_role = replica;
insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint, actor, txid, created_at)
values (4, 'forjado em replica', public.commercial_pricing_activation_preflight(4), public.commercial_activation_guard_fingerprint(), session_user, txid_current(), now());
update public.commercial_pricing_rules set status = 'superseded' where version = 3;
update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4;
reset session_replication_role;")
echo "$R2" | sed 's/^/    L2: /'
REC2=$(RECIBOS "$R2")
if [ "$(FALSOS "$R2")" = 0 ] && [ -n "$REC2" ]; then
  passa "L2 LIMITE: forja completa em replica passa em TODAS as verificacoes internas (o banco nao se protege do dono)"
else falha "L2: esperado o limite (verificacao toda true), obtido outro resultado"; fi
# Recibo externo: só o L0 foi registrado fora do banco. O registro do L2 não consta.
grep -qxF "$REC2" <<< "$REC0" && falha "L2: registro forjado coincide com o recibo externo" \
  || passa "L2 o confronto com o recibo externo (guardado na ativacao autorizada) DETECTA o registro forjado"

R3=$(roda L3 "$ATIVA
alter table public.commercial_exclusivity_orders disable trigger ceo_pagamento_confere_snapshot;")
echo "$R3" | sed 's/^/    L3: /'
[ "$(ITEM "$R3" 'nenhum gatilho de guarda desligado')" = false ] && [ "$(ITEM "$R3" 'ATUAL das guardas')" = false ] \
  && passa "L3 gatilho desligado depois da ativacao: DETECTADO" || falha "L3"

R4=$(roda L4 "$ATIVA
create or replace function public.ceo_pagamento_confere_snapshot() returns trigger language plpgsql as \$f\$ begin return new; end \$f\$;")
echo "$R4" | sed 's/^/    L4: /'
[ "$(ITEM "$R4" 'ATUAL das guardas')" = false ] && passa "L4 guarda substituida por DDL depois da ativacao: DETECTADO" || falha "L4"

echo "R4_LIMITE_CONFIANCA: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
