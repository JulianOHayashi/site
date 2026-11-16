-- Contraprovas sobre a R4.2 (89363db): demonstra as lacunas da auditoria.
-- Fixtures do cabeçalho da 298 da R4.2; transação revertida.
select pg_temp.inspecao(:'conj', 5);
select (pg_temp.como(:'u1', format('select public.artwork_change_request_create(%L)', :'origem'))->>'request_id') as req \gset
select pg_temp.como(:'u1', format('select public.artwork_change_image_path(%L)', :'req')) as p \gset
select pg_temp.objeto((:'p')::jsonb->>'storage_path', :'u1');
select pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 1, %L, %L)', :'req', (:'p')::jsonb->>'storage_path', repeat('a', 64)));
select pg_temp.como(:'u1', format('select public.artwork_change_submit(%L, 2)', :'req'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_start_review(%L, 3)', :'req'));
-- X4: total 1.500,00 com 40 x 35,00 (= 1.400,00) e SHA-256 de documento que não existe.
select pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, 'Fornecedor X',
  'ORC-X4-1', %L, '40 bandeiras', 40, 3500, 150000, 160000)$s$, :'req', repeat('d', 64))) as q \gset
\echo X4|orcamento_declarado_com_total_divergente_e_documento_inexistente|:q
select pg_temp.como(:'u1', format('select public.artwork_change_accept_quote(%L, 5, %L, 150000)', :'req', (:'q')::jsonb->>'quote_id'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_authorize_production(%L, 6)', :'req')) as ap \gset
\echo X1|producao_autorizada|:ap
select pg_temp.tornar_corrente(1);
savepoint x1;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'direct_benefits')$s$, :'c1')) as r1 \gset
\echo X1|renovacao_fidelizada_apoiada_so_na_autorizacao|:r1
rollback to savepoint x1;
savepoint x2;
select pg_temp.pedido(2, :'c1', 'womens_clothing', true) as k2 \gset
select 'X2|duas_campanhas_depois|' || coalesce(artwork_change_request_id::text, 'sem_alteracao')
  from public.commercial_exclusivity_orders where id = :'k2';
rollback to savepoint x2;
savepoint x3;
alter table public.commercial_artwork_change_requests disable trigger cacr_protect;
create or replace function public.commercial_artwork_change_for_renewal(p_company_id uuid, p_fidelity_identity text)
  returns uuid language sql stable security definer set search_path to 'pg_catalog' as $b$ select null::uuid $b$;
drop index public.cacr_uma_aberta_idx;
alter table public.commercial_artwork_change_quotes alter column partner_charge_cents drop expression;
select 'X3|falhas_de_integridade|' || coalesce(array_to_string(public.commercial_guard_integrity_failures(), ';'), '') || '|fim';
\i :verificador
rollback to savepoint x3;
