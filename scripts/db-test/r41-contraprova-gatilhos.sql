-- ===========================================================================
-- R4.1 — contraprova R4 × R4.1, roteiro IDÊNTICO nos dois bancos:
--   C1. ENABLE REPLICA TRIGGER numa guarda (estado R);
--   C2. mesma guarda, mesmo nome e estado O, executando OUTRA função.
-- Para cada caso: estado do gatilho, pré-verificação e resultado da
-- ativação autorizada. Transações revertidas; banco descartável.
--   R4 (cd4064a): esperado preflight=true e ativacao=true nos dois casos;
--   R4.1:         esperado preflight=false e ativacao=false nos dois casos.
-- ===========================================================================
\set ON_ERROR_STOP on
select to_regprocedure('tests.ativar_sf_v15_qa(integer,text)') is not null as eh_r41 \gset
\o /dev/null
\if :eh_r41
create or replace function pg_temp.ativar(r text) returns jsonb language sql as $f$
  select tests.ativar_sf_v15_qa(4, r) $f$;
\else
create or replace function pg_temp.ativar(r text) returns jsonb language sql as $f$
  select public.admin_activate_pricing_rule(4, r) $f$;
\endif
\o

begin;
\o /dev/null
select tests.preparar_ativacao_sf_v15_qa('CONTRA', 'A');
\o
select 'C0_linha_de_base_preflight', (public.commercial_pricing_activation_preflight(4)->>'ok');

savepoint c1;
alter table public.commercial_exclusivity_orders enable replica trigger ceo_pagamento_confere_snapshot;
select 'C1_estado_do_gatilho', tgenabled::text from pg_trigger where tgname = 'ceo_pagamento_confere_snapshot';
select 'C1_preflight', (public.commercial_pricing_activation_preflight(4)->>'ok');
select 'C1_ativacao_ok', (pg_temp.ativar('[QA FICTICIO] contraprova C1 gatilho em R')->>'ok');
select 'C1_status_v4_depois', status from public.commercial_pricing_rules where version = 4;
rollback to savepoint c1;

savepoint c2;
create function public.zz_contraprova_inerte() returns trigger language plpgsql as $f$
begin
  return coalesce(new, old);
end $f$;
create or replace trigger ceo_pagamento_confere_snapshot before insert or update on public.commercial_exclusivity_orders
  for each row execute function public.zz_contraprova_inerte();
select 'C2_gatilho', tgname::text || ' estado ' || tgenabled::text || ' executa ' || tgfoid::regprocedure::text
  from pg_trigger where tgname = 'ceo_pagamento_confere_snapshot';
select 'C2_preflight', (public.commercial_pricing_activation_preflight(4)->>'ok');
select 'C2_ativacao_ok', (pg_temp.ativar('[QA FICTICIO] contraprova C2 funcao trocada')->>'ok');
select 'C2_status_v4_depois', status from public.commercial_pricing_rules where version = 4;
rollback to savepoint c2;
rollback;
