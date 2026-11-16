-- As mesmas contraprovas sobre a R4.2.1: cada lacuna fica fechada.
-- Fixtures do cabeçalho da 298 da R4.2.1; transação revertida.
select pg_temp.inspecao(:'conj', 5);
select (pg_temp.como(:'u1', format('select public.artwork_change_request_create(%L)', :'origem'))->>'request_id') as req \gset
select pg_temp.como(:'u1', format('select public.artwork_change_image_path(%L)', :'req')) as p \gset
select pg_temp.objeto((:'p')::jsonb->>'storage_path', :'u1');
select pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 1, %L, %L)', :'req', (:'p')::jsonb->>'storage_path', repeat('a', 64)));
select pg_temp.como(:'u1', format('select public.artwork_change_submit(%L, 2)', :'req'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_start_review(%L, 3)', :'req'));
-- X4: o orçamento declarado não existe mais; o itemizado recusa total divergente.
select 'X4|rpc_declarada_removida|' || (to_regprocedure('public.admin_artwork_change_register_quote(uuid,integer,text,text,text,text,integer,bigint,bigint,bigint)') is null)::text;
select pg_temp.orcar(:'req', 4, 'ORC-X4-1', repeat('d', 64), '40 bandeiras', 40, 3500, 150000, 160000) as q \gset
\echo X4|orcamento_com_total_divergente|:q
select pg_temp.orcar(:'req', 4, 'ORC-X4-2', repeat('e', 64), '40 bandeiras', 40, 3500, 140000, 160000) as q \gset
select pg_temp.aceitar(:'u1', :'req', 5, ((:'q')::jsonb->>'quote_id')::uuid, 140000);
select pg_temp.como(:'adm', format('select public.admin_artwork_change_authorize_production(%L, 6)', :'req')) as ap \gset
\echo X1|producao_autorizada|:ap
select pg_temp.tornar_corrente(1);
savepoint x1;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'direct_benefits')$s$, :'c1')) as r1 \gset
\echo X1|renovacao_fidelizada_apoiada_so_na_autorizacao|:r1
rollback to savepoint x1;
savepoint x2;
select pg_temp.simular_prontidao();
select pg_temp.pedido(2, :'c1', 'womens_clothing', true) as k2 \gset
select 'X2|duas_campanhas_depois|' || coalesce(artwork_change_request_id::text, 'sem_alteracao')
  from public.commercial_exclusivity_orders where id = :'k2';
rollback to savepoint x2;
set constraints all immediate;
savepoint x3;
alter table public.commercial_artwork_change_requests disable trigger cacr_protect;
create or replace function public.commercial_artwork_change_readiness(p_request_id uuid)
  returns jsonb language sql stable security definer set search_path to 'pg_catalog' as $b$ select '{"ready": true}'::jsonb $b$;
drop index public.cacr_uma_aberta_idx;
alter table public.commercial_artwork_change_quotes alter column partner_charge_cents drop expression;
select 'X3|falhas_de_integridade|' || coalesce(array_to_string(public.commercial_guard_integrity_failures(), ';'), '') || '|fim';
\i :verificador
rollback to savepoint x3;
