#!/usr/bin/env bash
# ============================================================================
# Concorrência REAL de segmento: sessões psql independentes, em paralelo,
# disputando o MESMO segmento em posições DIFERENTES da mesma exclusividade.
# Banco descartável (nunca remoto). Rode com PGPORT=5433 para o PG17.
#
#   C1  escalonado + COMMIT    A reserva e segura a transação; B chega depois,
#                              ESPERA na trava e é recusada quando A confirma
#   C2  escalonado + ROLLBACK  A desiste; B, que esperava, é aceita
#   C3  simultâneo (barreira)  10 rodadas, as duas no mesmo instante:
#                              exatamente uma aceita, a outra recusada
#   C4  reserva expirada       não bloqueia: outra posição reserva o segmento
#   C5  pedido (índice único)  dois INSERTs concorrentes do mesmo segmento,
#                              SEM a trava consultiva: o índice
#                              ceo_segmento_por_exclusividade_idx barra o
#                              segundo (unique_violation); com ROLLBACK do
#                              primeiro, o segundo entra
#   Em todos: nenhuma espera indefinida (lock_timeout 15 s), nenhum deadlock
#   (pg_stat_database.deadlocks inalterado) e estado final consistente.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
eval "$(sed -n '/^psql_db()/p;/^q()/p' scripts/db-test/upgrade-positions-segments-check.sh)"
BASE=bdflow_conc
TMPD=$(mktemp -d); chmod 755 "$TMPD"; trap 'rm -rf "$TMPD"' EXIT
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }

echo "== versão: $(q postgres 'show server_version') =="
BDFLOW_LOCAL_DB=$BASE bash scripts/db-test/reset-local.sh > "$TMPD/reset.log" 2>&1
# Fixtures da suíte 270 (exclusividade em formação em Viana, 8 empresas com
# Acordo Mestre, 5 segmentos aprovados pelo admin) — só a parte de setup.
sed -n '/^-- Fixtures/,/^-- 1\. Catálogo de posições/p' supabase/tests/270_commercial_positions_segments.sql \
  | sed '$d' > "$TMPD/fixtures.sql"
psql_db $BASE < "$TMPD/fixtures.sql" > /dev/null
# Só para C5: pedidos manuais sem os gatilhos de instrumento (D9 bloqueia o
# instrumento de segmento). Banco descartável.
psql_db $BASE <<'SQL' > /dev/null
alter table public.commercial_exclusivity_orders disable trigger ceo_exigir_instrumento;
alter table public.commercial_exclusivity_orders disable trigger ceo_emitir_instrumento;
select tests.preparar_contexto_contratual_v14_qa('270');
SQL

cat > "$TMPD/reserva.sql" <<'SQL'
\set ON_ERROR_STOP 1
set lock_timeout = '15s';
begin;
select tests.impersonate('authenticated', :'uid');
select pg_sleep_until(:'inicio'::timestamptz);
select extract(epoch from clock_timestamp()) as t0 \gset
select r ->> 'ok' as ok, coalesce(r ->> 'reason', '-') as motivo
  from (select public.create_commercial_checkout_intent(:'comp'::uuid, :'pos', 'direct_benefits', :'seg'::uuid) as r) x \gset
select round((extract(epoch from clock_timestamp()) - :t0)::numeric, 2) as espera \gset
\echo RESULTADO ok=:ok motivo=:motivo espera=:espera
select pg_sleep(:segurar);
:fim;
\echo FIM
SQL
chmod 644 "$TMPD/reserva.sql"

clonar() { echo "drop database if exists $1 with (force); create database $1 template $BASE;" | psql_db postgres; }
id() { q "$1" "$2"; }
deadlocks() { q postgres "select coalesce(sum(deadlocks),0) from pg_stat_database"; }
sessao() { # db nome uid comp pos seg inicio segurar fim
  su postgres -c "psql -X -q -d $1 -v uid=$3 -v comp=$4 -v pos=$5 -v seg=$6 -v inicio='$7' -v segurar=$8 -v fim=$9 -f $TMPD/reserva.sql" > "$TMPD/$2.out" 2>&1 &
}
campo() { grep -o "$2=[^ ]*" "$TMPD/$1.out" | head -1 | cut -d= -f2; }
vivas() { q "$1" "select count(*) from public.commercial_checkout_intents where segment_code_snapshot='$2' and status in ('draft','awaiting_contract') and reserved_until > now()"; }
DL0=$(deadlocks)

prep() { # db -> exporta U2 C2 U3 C3 SEG
  U2=$(id $1 "select m.auth_user_id from site_company_members m join site_partner_companies c on c.id=m.company_id where c.cnpj='27010002000118' and m.role='partner_owner'")
  C2=$(id $1 "select id from site_partner_companies where cnpj='27010002000118'")
  U3=$(id $1 "select m.auth_user_id from site_company_members m join site_partner_companies c on c.id=m.company_id where c.cnpj='27010003000162' and m.role='partner_owner'")
  C3=$(id $1 "select id from site_partner_companies where cnpj='27010003000162'")
  SEG=$(id $1 "select id from commercial_segments where code='pet_shop'")
}
em() { q postgres "select (clock_timestamp() + interval '$1 milliseconds')::text"; }

echo "C1 escalonado: A segura a transacao e confirma; B chega depois"
clonar c1; prep c1
T=$(em 1500); TB=$(q postgres "select ('$T'::timestamptz + interval '700 milliseconds')::text")
sessao c1 A "$U2" "$C2" others "$SEG" "$T" 3 commit
sessao c1 B "$U3" "$C3" pharmacy "$SEG" "$TB" 0 commit
sleep 3.2
ESPERANDO=$(q c1 "select count(*) from pg_locks where locktype='advisory' and not granted")
wait
echo "    A: ok=$(campo A ok) | B: ok=$(campo B ok) motivo=$(campo B motivo) espera=$(campo B espera)s | B esperando na trava durante A: $ESPERANDO"
[ "$(campo A ok)" = "true" ] && [ "$(campo B motivo)" = "segment_already_in_exclusivity" ] && passa "A aceita, B recusada" || falha "C1 resultado"
[ "$ESPERANDO" = "1" ] && passa "B bloqueou na trava consultiva (concorrencia efetiva)" || falha "C1 sem espera observada"
awk "BEGIN{exit !($(campo B espera) >= 1.5)}" && passa "B so decidiu depois do commit de A" || falha "C1 espera curta"
[ "$(vivas c1 pet_shop)" = "1" ] && passa "uma unica reserva viva do segmento" || falha "C1 duplicada"
grep -q FIM "$TMPD/A.out" && grep -q FIM "$TMPD/B.out" && passa "as duas sessoes terminaram (sem espera indefinida)" || falha "C1 sessao nao terminou"

echo "C2 escalonado: A desiste (rollback); B esperava"
clonar c2; prep c2
T=$(em 1500); TB=$(q postgres "select ('$T'::timestamptz + interval '700 milliseconds')::text")
sessao c2 A "$U2" "$C2" others "$SEG" "$T" 3 rollback
sessao c2 B "$U3" "$C3" pharmacy "$SEG" "$TB" 0 commit
wait
echo "    A: ok=$(campo A ok) (rollback) | B: ok=$(campo B ok) espera=$(campo B espera)s"
[ "$(campo A ok)" = "true" ] && [ "$(campo B ok)" = "true" ] && passa "B aceita depois do rollback de A" || falha "C2 resultado"
[ "$(vivas c2 pet_shop)" = "1" ] && [ "$(q c2 "select count(*) from commercial_checkout_intents where company_id='$C2'")" = "0" ] \
  && passa "so a reserva de B existe; nada de A sobrou" || falha "C2 estado"

echo "C3 simultaneo: 10 rodadas com barreira de horario"
GANHA=0; INCONS=0
for i in $(seq 1 10); do
  clonar c3; prep c3
  T=$(em 1200)
  sessao c3 A "$U2" "$C2" others "$SEG" "$T" 1 commit
  sessao c3 B "$U3" "$C3" pharmacy "$SEG" "$T" 1 commit
  wait
  R="$(campo A ok)/$(campo B ok)"
  if { [ "$R" = "true/false" ] || [ "$R" = "false/true" ]; } && [ "$(vivas c3 pet_shop)" = "1" ]; then GANHA=$((GANHA+1)); else INCONS=$((INCONS+1)); echo "    rodada $i: $R"; fi
done
echo "    rodadas com exatamente um vencedor: $GANHA/10"
[ "$GANHA" = "10" ] && passa "exatamente uma aceita em todas as rodadas" || falha "C3 $INCONS rodada(s) inconsistente(s)"

echo "C4 reserva expirada nao bloqueia"
clonar c4; prep c4
T=$(em 300)
sessao c4 A "$U2" "$C2" others "$SEG" "$T" 0 commit; wait
q c4 "update commercial_checkout_intents set reserved_until = now() - interval '1 second' where company_id='$C2'" >/dev/null
q c4 "update commercial_opportunities set reserved_until = now() - interval '1 second' where reserved_until is not null" >/dev/null
T=$(em 300)
sessao c4 B "$U3" "$C3" pharmacy "$SEG" "$T" 0 commit; wait
echo "    A: ok=$(campo A ok) depois expirada | B: ok=$(campo B ok) motivo=$(campo B motivo)"
[ "$(campo A ok)" = "true" ] && [ "$(campo B ok)" = "true" ] && [ "$(vivas c4 pet_shop)" = "1" ] \
  && passa "segmento liberado pela expiracao; uma reserva viva" || falha "C4"

echo "C5 pedido: indice unico sob INSERT concorrente (sem trava consultiva)"
for FIM_X in commit rollback; do
  clonar c5; prep c5
  ADM=$(id c5 "select user_id from site_admins limit 1")
  OPO=$(id c5 "select o.id from commercial_opportunities o join commercial_exclusivities e on e.id=o.exclusivity_id where e.is_current and o.niche_code='others'")
  C8=$(id c5 "select id from site_partner_companies where cnpj='27010008000195'")
  # Pedido manual REAL (RPC do admin): Outros com Pet shop. Serve de modelo.
  psql_db c5 > /dev/null <<SQL
begin;
select tests.impersonate('authenticated', '$ADM');
select public.admin_register_manual_commercial_order('$OPO'::uuid, '$C8'::uuid, 'v1', now() - interval '1 day',
  'Titular 270-8', (now() + interval '30 days')::date, 'direct_benefits', 'doc://conc', p_segment_id => '$SEG'::uuid);
commit;
SQL
  MODELO=$(id c5 "select id from commercial_exclusivity_orders where segment_id is not null")
  PAP=$(id c5 "select id from commercial_segments where code='papelaria'")
  T=$(em 1500); TY=$(q postgres "select ('$T'::timestamptz + interval '600 milliseconds')::text")
  for S in X Y; do
    POS=$([ $S = X ] && echo footwear || echo pharmacy); CNPJ=$([ $S = X ] && echo 27010006000104 || echo 27010005000151)
    INI=$([ $S = X ] && echo "$T" || echo "$TY"); SEG_=$([ $S = X ] && echo 3 || echo 0); FIM_=$([ $S = X ] && echo $FIM_X || echo commit)
    cat > "$TMPD/ins_$S.sql" <<SQL
set lock_timeout = '15s';
begin;
select pg_sleep_until('$INI'::timestamptz);
-- copia do pedido-modelo em OUTRA posicao e OUTRA empresa, com o MESMO
-- segmento Papelaria nas duas sessoes; INSERT direto, sem a RPC e sem a
-- trava consultiva: so o indice unico decide.
insert into public.commercial_exclusivity_orders
select * from jsonb_populate_record(null::public.commercial_exclusivity_orders,
  (select to_jsonb(o) || jsonb_build_object(
      'id', gen_random_uuid(), 'niche_code', '$POS', 'document_reference', 'doc://conc-$S',
      'segment_id', '$PAP', 'segment_code_snapshot', 'papelaria',
      'segment_name_snapshot', 'Papelaria', 'segment_classification_snapshot', 'papelaria',
      'opportunity_id', (select x.id from public.commercial_opportunities x
                          where x.exclusivity_id = o.exclusivity_id and x.niche_code = '$POS'),
      'company_id', (select c.id from public.site_partner_companies c where c.cnpj = '$CNPJ'),
      -- fatos materiais da OUTRA empresa: os gatilhos existentes os rederivam
      'nfse_taker_cnpj', null, 'execution_unit_id', null, 'legal_acceptance_id', null,
      'master_agreement_id', (select a.id from public.commercial_master_agreements a
                               join public.site_partner_companies c on c.id = a.company_id
                              where c.cnpj = '$CNPJ' order by a.created_at desc limit 1))
     from public.commercial_exclusivity_orders o where o.id = '$MODELO'));
\echo INSERIU
select pg_sleep($SEG_);
$FIM_;
\echo FIM
SQL
    chmod 644 "$TMPD/ins_$S.sql"
    su postgres -c "psql -X -q -d c5 -f $TMPD/ins_$S.sql" > "$TMPD/$S.out" 2>&1 &
  done
  sleep 2.6
  ESPERA_IDX=$(q c5 "select count(*) from pg_locks where locktype='transactionid' and not granted")
  wait
  NPAP=$(q c5 "select count(*) from commercial_exclusivity_orders where segment_code_snapshot='papelaria'")
  echo "    X($FIM_X): $(grep -c INSERIU $TMPD/X.out) insert | Y: $(grep -o 'duplicate key[^"]*"[a-z_]*"' $TMPD/Y.out | head -1)$(grep -c INSERIU $TMPD/Y.out) | Y esperando X: $ESPERA_IDX | Papelaria=$NPAP"
  if [ "$FIM_X" = commit ]; then
    grep -q 'ceo_segmento_por_exclusividade_idx' "$TMPD/Y.out" && [ "$NPAP" = "1" ] && [ "$ESPERA_IDX" = "1" ] \
      && passa "com commit de X: Y esperou e levou unique_violation; um pedido" || falha "C5 commit: $(cat $TMPD/Y.out)"
  else
    ! grep -q 'ERROR' "$TMPD/Y.out" && [ "$NPAP" = "1" ] && [ "$ESPERA_IDX" = "1" ] \
      && passa "com rollback de X: Y esperou e entrou; um pedido" || falha "C5 rollback: $(cat $TMPD/Y.out)"
  fi
done

DL1=$(deadlocks)
[ "$DL0" = "$DL1" ] && passa "nenhum deadlock em todo o ensaio (pg_stat_database.deadlocks $DL0 -> $DL1)" || falha "deadlocks $DL0 -> $DL1"
for d in c1 c2 c3 c4 c5 $BASE; do echo "drop database if exists $d with (force);" | psql_db postgres; done
echo "CONCURRENCY_CHECK: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
