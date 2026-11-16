#!/usr/bin/env bash
# ============================================================================
# R4.2 / decisão A — ensaio do roteiro REAL de ops do Cenário A
# (supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql) e da recusa do B, em
# banco descartável local; tudo em transações revertidas.
#   uso: r42-cenario-a.sh   (PGHOST=/tmp PGPORT=5433 para o PG17 local)
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."
RAIZ=$(pwd)
DB=r42_cenario_a_${PGPORT:-5432}
BDFLOW_LOCAL_DB=$DB bash scripts/db-test/reset-local.sh > /tmp/r42_cenario_a_reset_${PGPORT:-5432}.log 2>&1 || { echo "reset falhou"; exit 2; }
OK=0; RUIM=0
passa() { echo "  PASS $1"; OK=$((OK+1)); }
falha() { echo "  FAIL $1"; RUIM=$((RUIM+1)); }
psql_tx() { su postgres -c "psql -X -At -d $DB -f -" 2>&1; }
echo "== cenario A real | $(su postgres -c "psql -X -At -d postgres -c 'show server_version'") | $(git rev-parse --short HEAD) =="

HIST="select md5(string_agg(t::text, '|' order by t::text)) from (
        select to_jsonb(s) t from public.commercial_pricing_schedule s where pricing_rule_version <= 3
        union all select to_jsonb(r) - 'updated_at' from public.commercial_pricing_rules r where version <= 3
        union all select to_jsonb(c) from public.commercial_settlement_terms c where pricing_rule_version <= 3) x"
ANTES=$(su postgres -c "psql -X -At -d $DB" <<< "$HIST")

S1=$(psql_tx <<SQL
begin;
\\i $RAIZ/supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql
rollback;
SQL
)
echo "$S1" | grep -q 'cenario_a_sem_decisao' && passa "sem decisao explicita na transacao: recusado" || falha "T1: $S1"

S2=$(psql_tx <<SQL
begin;
set local smallflags.decisao_dinheiro_sf_v15 = 'CENARIO-A-APROVADO';
set local smallflags.decisao_referencia = 'DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115';
\\o /dev/null
\\i $RAIZ/supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql
\\o
select 'T|' || t.commercial_category || '|' || t.fidelized || '|' || t.economic_value_cents || '|' || d.economic_value_cents
       || '|' || t.qa_in_kind_cents || '|' || t.qa_cash_cents || '|' || t.cash_adjustment_cents
       || '|' || t.total_monetary_funding_required_cents || '|' || (t.smallflags_main_fee_cents = d.smallflags_main_fee_cents)
       || '|' || d.qa_in_kind_cents || '|' || d.total_monetary_funding_required_cents
  from public.commercial_settlement_terms t
  join public.commercial_settlement_terms d on d.pricing_rule_version = 4 and d.commercial_category = t.commercial_category
   and d.fidelized = t.fidelized and d.benefit_settlement_mode = 'direct_benefits'
 where t.pricing_rule_version = 4 and t.benefit_settlement_mode = 'cash'
 order by 1;
select 'REF|' || decision_reference from public.commercial_settlement_terms
 where pricing_rule_version = 4 and benefit_settlement_mode = 'cash' limit 1;
select 'V4|' || status from public.commercial_pricing_rules where version = 4;
select 'PRE|' || (public.commercial_pricing_activation_preflight(4)->>'ok') || '|'
       || (public.commercial_pricing_activation_preflight(4)->'failures' ? 'qa_operational_procedure_missing:SF-v1.5');
\\o /dev/null
\\i $RAIZ/supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql
\\o
rollback;
SQL
)
echo "$S2" | grep -E '^(T|REF|V4|PRE)\|' | sed 's/^/    /'
ESPERADO="T|common|false|2287816|2293900|0|0|0|2287816|true|6084|1095100
T|common|true|1612716|1618800|0|0|0|1612716|true|6084|420000
T|supermarket|false|3281732|3293900|0|0|0|3281732|true|12168|896300
T|supermarket|true|2805432|2817600|0|0|0|2805432|true|12168|420000"
[ "$(echo "$S2" | grep -E '^T\|' | sort)" = "$ESPERADO" ] \
  && passa "4 condicoes: DINHEIRO 32.817,32 / 28.054,32 / 22.878,16 / 16.127,16; direto 32.939,00 / 28.176,00 / 22.939,00 / 16.188,00" \
  || falha "valores das 4 condicoes"
passa_se() { if eval "$1"; then passa "$2"; else falha "$2"; fi; }
passa_se 'echo "$S2" | grep -q "^REF|Cenario A: DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115$"' "referencia da decisao gravada nos termos"
passa_se 'echo "$S2" | grep -q "^V4|prepared$" && echo "$S2" | grep -q "^PRE|false|true$"' \
  "gravar o preco NAO ativa: v4 preparada; pre-verificacao reprova pela trava da QA"
passa_se 'echo "$S2" | grep -q "cenario_a_ja_definido"' "segunda execucao recusada (preco ja definido)"

S3=$(psql_tx <<SQL
begin;
update public.commercial_pricing_schedule set smallflags_main_fee_cents = smallflags_main_fee_cents + 1,
       economic_value_cents = economic_value_cents + 1,
       smallflags_total_remuneration_cents = smallflags_total_remuneration_cents + 1
 where pricing_rule_version = 4 and commercial_category = 'common' and not fidelized;
set local smallflags.decisao_dinheiro_sf_v15 = 'CENARIO-A-APROVADO';
set local smallflags.decisao_referencia = 'DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115';
\\i $RAIZ/supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql
rollback;
SQL
)
if echo "$S3" | grep -q 'cenario_a_valores_divergentes'; then passa "agenda produzindo valor diferente do aprovado: roteiro aborta"
else falha "T3: $S3"; fi

S4=$(psql_tx <<SQL
begin;
set local smallflags.decisao_dinheiro_sf_v15 = 'CENARIO-B-APROVADO';
set local smallflags.decisao_referencia = 'tentativa de usar o cenario B';
set local smallflags.cenario_b_fundamento = 'tentativa de usar o cenario B';
\\i $RAIZ/supabase/ops/20261113_sf_v15_dinheiro_cenario_b.sql
select 'CASH|' || count(*) from public.commercial_settlement_terms where benefit_settlement_mode = 'cash';
rollback;
SQL
)
passa_se 'echo "$S4" | grep -q "cenario_b_rejeitado"' "Cenario B recusado mesmo com decisao B declarada"

DEPOIS=$(su postgres -c "psql -X -At -d $DB" <<< "$HIST")
[ -n "$ANTES" ] && [ "$ANTES" = "$DEPOIS" ] && passa "precos historicos (v1..v3) intactos ($ANTES)" || falha "historico mudou"
[ "$(su postgres -c "psql -X -At -d $DB -c \"select count(*) from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'\"")" = "0" ] \
  && passa "depois dos ensaios: nenhum preco de DINHEIRO gravado (tudo revertido)" || falha "vazou preco"

echo "R42_CENARIO_A: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
