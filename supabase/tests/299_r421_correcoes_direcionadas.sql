-- ===========================================================================
-- 299 — R4.2.1: correções direcionadas da auditoria independente da R4.2
-- (migration 20261116180000).
--   P1-1 produção AUTORIZADA não é prontidão: renovação recusada sem os fatos
--        de cobrança e de produção (bloqueio seguro); pendente bloqueia;
--   P1-2 alteração presa à campanha alvo (base + 1), uma por campanha, pedido
--        base mais recente, campanha adjudicada, duas campanhas depois,
--        pedido alvo cancelado;
--   P1-3 adulterações nas guardas NOVAS (gatilhos, funções, índices, CHECK,
--        permissões, RLS, coluna gerada, Storage) detectadas;
--   P1-4 custo comprovado: documento privado ATESTADO pelo servidor, itens
--        (quantidade x unitário), preço não linear, divergências recusadas.
-- Cabeçalho (fixtures) igual ao da 298. Ativação, preços de DINHEIRO,
-- aprovações, procedimento de QA e a prontidão "simulada" são FIXTURES
-- [QA FICTICIO], numa transação revertida.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();
select tests.fechar_portao_autoatendimento_qa();

select tests.check('estado de partida: nenhuma solicitacao de alteracao de arte; manifesto R4.2 gravado e o vigente integro',
    not exists (select 1 from public.commercial_artwork_change_requests)
    and exists (select 1 from public.commercial_guard_manifests where manifest_label = 'R4.2')
    and public.commercial_guard_integrity_failures() = array[]::text[]);
select tests.check('ninguem alem do dono escreve nas tabelas de alteracao de arte (so RPC)',
    not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.commercial_artwork_change_requests',
                                 'public.commercial_artwork_change_versions',
                                 'public.commercial_artwork_change_quotes',
                                 'public.commercial_artwork_change_events']) t,
                    unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p
       where has_table_privilege(r, t, p)));

begin;
select tests.encerrar_contexto_contratual_v14_qa();

-- Executa um SQL como usuário autenticado e volta ao dono.
create or replace function pg_temp.como(p_uid uuid, p_sql text) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform tests.impersonate('authenticated', p_uid);
  execute p_sql into v;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

select r.id as reg from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset
select tests.mk_user('admin298') as adm \gset
insert into public.site_admins (user_id) values ((:'adm')::uuid) on conflict do nothing;
select tests.mk_user('titular298.1') as u1 \gset
select tests.mk_user('gerente298.1') as m1 \gset
select tests.mk_user('titular298.2') as u2 \gset

create or replace function pg_temp.empresa(p_cnpj text, p_n int, p_uid uuid) returns uuid language plpgsql as $f$
declare v_app uuid; v_comp uuid;
begin
  insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
  values (p_cnpj, 'Empresa 298-' || p_n, 'e298' || p_n || '@teste.local', 'Viana', 'ES') returning id into v_app;
  insert into public.partner_application_representatives
    (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
  values (v_app, 'Titular 298-' || p_n, '52998224725', 'rep298' || p_n || '@teste.local',
          'Socio administrador', 'approved', true, now() - interval '2 days');
  insert into public.site_partner_companies
    (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
  values (v_app, p_cnpj, 'Empresa 298-' || p_n, 'Loja 298-' || p_n, 'e298' || p_n || '@teste.local',
          'Viana', 'ES', 'active') returning id into v_comp;
  insert into public.site_company_members (company_id, auth_user_id, role, full_name, cpf, source, status)
  values (v_comp, p_uid, 'partner_owner', 'Titular 298-' || p_n, '52998224725', 'application_promotion', 'active');
  insert into public.site_partner_units (company_id, name, city, uf, status)
  values (v_comp, 'Unidade 298-' || p_n, 'Viana', 'ES', 'active');
  return v_comp;
end $f$;
select pg_temp.empresa('29800001000100', 1, :'u1') as c1 \gset
select pg_temp.empresa('29800002000147', 2, :'u2') as c2 \gset
insert into public.site_company_members (company_id, auth_user_id, role, full_name, cpf, source, status)
values (:'c1', :'m1', 'partner_manager', 'Gerente 298-1', '52998224725', 'manager_invite', 'active');

select tests.impersonate('authenticated', :'adm');
select tests.assinar_mestre_qa((:'c1')::uuid, 'AM-298-1');
select tests.assinar_mestre_qa((:'c2')::uuid, 'AM-298-2');
reset role; select set_config('request.jwt.claims', '', true);

create temp table exc298 (k int primary key, id uuid);
select set_config('tests.reg298', :'reg', true);
do $$
declare v_k int; v_id uuid;
begin
  for v_k in 0..3 loop
    insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
    values (current_setting('tests.reg298')::uuid, 2980 + v_k, 'forming', false) returning id into v_id;
    insert into exc298 values (v_k, v_id);
  end loop;
end $$;
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select x.id, n.code, n.contracted_quantity, 'available'
  from exc298 x cross join public.commercial_niches n where n.is_active;
create or replace function pg_temp.tornar_corrente(p_k int) returns void language sql as $f$
  update public.commercial_exclusivities set is_current = false
   where region_id = (select region_id from public.commercial_exclusivities
                       where id = (select id from exc298 where k = p_k)) and is_current;
  update public.commercial_exclusivities set is_current = true where id = (select id from exc298 where k = p_k);
$f$;
-- Pedido administrativo direto: números e fatos de produção vêm dos gatilhos.
create or replace function pg_temp.pedido(p_k int, p_comp uuid, p_niche text, p_fid boolean,
                                          p_mode text default 'direct_benefits') returns uuid
language plpgsql as $f$
declare v_id uuid; v_excl uuid := (select id from exc298 where k = p_k);
begin
  insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id, niche_code, nominal_quantity,
     fidelized, status, expected_operation_start, registered_by, pricing_rule_version, benefit_settlement_mode,
     economic_value_cents, contractual_pool_cents, bdflow_due_cents)
  values (v_excl,
          (select id from public.commercial_opportunities where exclusivity_id = v_excl and niche_code = p_niche),
          p_comp, (select id from public.commercial_master_agreements where company_id = p_comp and status = 'signed'),
          (select region_id from public.commercial_exclusivities where id = v_excl),
          p_niche, (select contracted_quantity from public.commercial_niches where code = p_niche),
          p_fid, 'draft', (now() + interval '30 days')::date,
          (select user_id from public.site_admins limit 1), 4, p_mode, 1, 1, 0)
  returning id into v_id;
  return v_id;
end $f$;
create or replace function pg_temp.conjunto(p_order uuid) returns uuid language sql as $f$
  insert into public.commercial_flag_sets (origin_order_id, company_id, fidelity_identity, pieces_count,
     produced_at, supplier_name, unit_cost_cents, recorded_by)
  values (p_order, gen_random_uuid(), 'qualquer_coisa', 1, now() - interval '60 days',
          '[QA FICTICIO] Fornecedor', 3500, (select user_id from public.site_admins limit 1))
  returning id;
$f$;
create or replace function pg_temp.inspecao(p_set uuid, p_dias int, p_unfit int default 0, p_cats text[] default '{}')
returns uuid language sql as $f$
  insert into public.commercial_flag_set_inspections (flag_set_id, inspected_at, inspector_name, evidence_hash,
     pieces_inspected, pieces_fit, pieces_unfit, unfit_categories, recorded_by)
  values (p_set, now() - make_interval(days => p_dias), '[QA FICTICIO] Conferente',
          encode(sha256(convert_to('[QA] inspecao 298 ' || p_set || p_dias || p_unfit, 'UTF8')), 'hex'),
          84, 84 - p_unfit, p_unfit, p_cats, (select user_id from public.site_admins limit 1))
  returning id;
$f$;
create or replace function pg_temp.objeto(p_path text, p_owner uuid) returns void language sql as $f$
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('partner-customization-images', p_path, p_owner,
          jsonb_build_object('size', 204800, 'mimetype', 'image/png'));
$f$;
-- R4.2.1: orçamento pelo caminho corrigido. Documento no bucket privado,
-- registrado pelo administrador, ATESTADO pelo servidor (aqui o dono do
-- banco no papel do backend com service_role, com o SHA-256 "calculado"
-- igual ao declarado) e orçamento de item único (pecas x unitario = total).
create or replace function pg_temp.orcar(p_req uuid, p_rv int, p_ref text, p_sha text, p_scope text,
                                         p_pecas int, p_unit bigint, p_total bigint, p_cap bigint)
returns jsonb language plpgsql as $f$
declare v_adm uuid := (select user_id from public.site_admins limit 1); v jsonb; v_doc uuid; v_path text;
begin
  v := pg_temp.como(v_adm, format('select public.admin_artwork_change_supplier_document_path(%L)', p_req));
  if (v->>'ok')::boolean is not true then return v; end if;
  v_path := v->>'storage_path';
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('supplier-quote-documents', v_path, v_adm, jsonb_build_object('size', 51200, 'mimetype', 'application/pdf'));
  v := pg_temp.como(v_adm, format('select public.admin_artwork_change_register_supplier_document(%L, %L, %L)',
                                  p_req, v_path, p_sha));
  if (v->>'ok')::boolean is not true then return v; end if;
  v_doc := (v->>'document_id')::uuid;
  perform public.service_artwork_change_attest_supplier_document(v_doc,
    (select id from storage.objects where bucket_id = 'supplier-quote-documents' and name = v_path), p_sha, 51200);
  return pg_temp.como(v_adm, format($s$select public.admin_artwork_change_register_quote(%L, %s, %L, 'Fornecedor 298',
      %L, %L, jsonb_build_array(jsonb_build_object('kind', 'flag_pieces', 'description', 'bandeiras com a nova arte',
      'document_locator', 'p.1', 'quantity', %s, 'unit_cost_cents', %s, 'line_total_cents', %s)), %s)$s$,
      p_req, p_rv, v_doc, p_ref, p_scope, p_pecas, p_unit, p_total, p_cap));
end $f$;
create or replace function pg_temp.aceitar(p_uid uuid, p_req uuid, p_rv int, p_quote uuid, p_total bigint)
returns jsonb language sql as $f$
  select pg_temp.como(p_uid, format('select public.artwork_change_accept_quote(%L, %s, %L, %s, %L)',
    p_req, p_rv, p_quote, p_total,
    (select supplier_document_sha256 from public.commercial_artwork_change_quotes where id = p_quote)));
$f$;
-- Prontidão SIMULADA (fixture): só dentro de savepoint revertido.
create or replace function pg_temp.simular_prontidao() returns void language plpgsql as $f$
begin
  execute $x$create or replace function public.commercial_artwork_change_readiness(p_request_id uuid)
    returns jsonb language sql stable security definer set search_path to 'pg_catalog' as $b$
      select pg_catalog.jsonb_build_object('ready', true, 'simulated', '[QA FICTICIO]')
       where exists (select 1 from public.commercial_artwork_change_requests
                      where id = p_request_id and status = 'production_authorized')
      union all
      select pg_catalog.jsonb_build_object('ready', false)
       where not exists (select 1 from public.commercial_artwork_change_requests
                          where id = p_request_id and status = 'production_authorized') $b$$x$;
end $f$;
-- Fixture de ativação (preço de DINHEIRO = valores do Cenário A, marcado
-- [QA FICTICIO]; aprovação e procedimento de QA fictícios). Só nesta transação.
select tests.preparar_ativacao_sf_v15_qa('298', 'A');
select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 298');

-- Pedido de origem (campanha atual) da empresa 1, com conjunto produzido.
select pg_temp.pedido(0, :'c1', 'womens_clothing', false) as origem \gset
select pg_temp.conjunto(:'origem') as conj \gset
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code, established_by_order_id)
values ('29800001000100', 'ES', 'viana', 'womens_clothing', :'origem');
-- Pedido da empresa 2 (para o teste de outra empresa).
select pg_temp.pedido(0, :'c2', 'pharmacy', false) as origem2 \gset

-- Pedido da empresa 1 é a origem (campanha k=0) com conjunto produzido;
-- inspeção APROVANDO as 84 peças: sem alteração de arte, a renovação
-- fidelizada por reutilização seria aceita.
select pg_temp.inspecao(:'conj', 5) as insp1 \gset

-- Fluxo completo até produção autorizada para a próxima campanha (k=1).
create or replace function pg_temp.ate_autorizada(p_uid uuid, p_order uuid, p_sha text) returns uuid
language plpgsql as $f$
declare v jsonb; v_req uuid; v_q jsonb; v_adm uuid := (select user_id from public.site_admins limit 1);
begin
  v := pg_temp.como(p_uid, format('select public.artwork_change_request_create(%L)', p_order));
  if (v->>'ok')::boolean is not true then raise exception 'create: %', v; end if;
  v_req := (v->>'request_id')::uuid;
  v := pg_temp.como(p_uid, format('select public.artwork_change_image_path(%L)', v_req));
  perform pg_temp.objeto(v->>'storage_path', p_uid);
  perform pg_temp.como(p_uid, format('select public.artwork_change_register_version(%L, 1, %L, %L)',
                                     v_req, v->>'storage_path', p_sha));
  perform pg_temp.como(p_uid, format('select public.artwork_change_submit(%L, 2)', v_req));
  perform pg_temp.como(v_adm, format('select public.admin_artwork_change_start_review(%L, 3)', v_req));
  v_q := pg_temp.orcar(v_req, 4, 'ORC-299-A', p_sha, '84 bandeiras com a nova arte', 84, 3500, 294000, 300000);
  perform pg_temp.aceitar(p_uid, v_req, 5, (v_q->>'quote_id')::uuid, 294000);
  v := pg_temp.como(v_adm, format('select public.admin_artwork_change_authorize_production(%L, 6)', v_req));
  if v->>'status' <> 'production_authorized' then raise exception 'autorizar: %', v; end if;
  return v_req;
end $f$;

-- ===========================================================================
-- P1-2. Campanha alvo
-- ===========================================================================
select pg_temp.como(:'u1', format('select public.artwork_change_request_create(%L)', :'origem')) as cr \gset
select (:'cr')::jsonb->>'request_id' as req \gset
select tests.check('P1-2: campanha alvo derivada pelo servidor: exclusividade base k=0, alvo = sequencia base + 1 na mesma regiao',
    (select r.base_exclusivity_id = (select id from exc298 where k = 0)
            and r.target_region_id = (:'reg')::uuid and r.target_sequence_number = 2981
       from public.commercial_artwork_change_requests r where r.id = (:'req')::uuid)
    and ((:'cr')::jsonb->>'target_sequence_number') = '2981');
select tests.check_raises('P1-2: campanha alvo imutavel (nem o dono muda)',
  format($s$update public.commercial_artwork_change_requests set row_version = row_version + 1,
            target_sequence_number = 2982 where id = %L$s$, :'req'), 'alteracao_arte_imutavel');

-- P1-1: solicitação PENDENTE para a campanha bloqueia a renovação nela, sem
-- cair para as bandeiras antigas (que estariam aptas).
select pg_temp.tornar_corrente(1);
savepoint pendente;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'direct_benefits')$s$,
                                  :'c1')) as rp \gset
select tests.check('P1-1: alteracao pendente para a campanha: reserva recusada (nao cai para as bandeiras antigas aptas)',
    ((:'rp')::jsonb->>'ok') = 'false' and ((:'rp')::jsonb->>'reason') = 'artwork_change_pending_for_campaign'
    and (public.commercial_flag_reuse_resolution((:'c1')::uuid, 'womens_clothing')->>'ok') = 'true');
rollback to savepoint pendente;
savepoint cancelada;
select pg_temp.como(:'u1', format($s$select public.artwork_change_cancel(%L, 1, 'desisti da troca')$s$, :'req'));
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'direct_benefits')$s$,
                                  :'c1')) as rc \gset
select tests.check('P1-1: depois de cancelada a alteracao, a renovacao volta a reutilizacao verificada',
    ((:'rc')::jsonb->>'ok') = 'true'
    and (select flag_reuse_set_id = (:'conj')::uuid and artwork_change_request_id is null
           from public.commercial_checkout_intents where id = ((:'rc')::jsonb->>'intent_id')::uuid));
rollback to savepoint cancelada;
select pg_temp.tornar_corrente(0);
-- Cancela o rascunho e faz o fluxo completo.
select pg_temp.como(:'u1', format($s$select public.artwork_change_cancel(%L, 1, 'refaz o fluxo')$s$, :'req'));
select pg_temp.ate_autorizada(:'u1', :'origem', repeat('a', 64)) as req \gset

-- P1-1: produção AUTORIZADA não é prontidão.
select tests.check('P1-1: prontidao = falsa com os tres fatos ausentes (cobranca, execucao, conjunto novo)',
    (select (x->>'ready') = 'false'
            and x->'missing' = '["billing_authorization_fact_not_available", "production_execution_fact_not_available", "new_flag_set_fact_not_available"]'::jsonb
       from (select public.commercial_artwork_change_readiness((:'req')::uuid) x) y));
select pg_temp.tornar_corrente(1);
savepoint nao_pronta;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'cash')$s$,
                                  :'c1')) as rn \gset
select tests.check('P1-1: em DINHEIRO tambem: autorizada sem cobranca/fabricacao nao renova (nada reservado)',
    ((:'rn')::jsonb->>'ok') = 'false' and ((:'rn')::jsonb->>'reason') = 'artwork_change_not_ready'
    and (select status from public.commercial_opportunities
          where exclusivity_id = (select id from exc298 where k = 1) and niche_code = 'womens_clothing') = 'available');
select tests.check_raises('P1-1: intencao direta pelo dono do banco tambem recusada (gatilho)',
  format($s$insert into public.commercial_checkout_intents (company_id, niche_code, status, pricing_rule_version,
      fidelized, benefit_settlement_mode, currency, nominal_quantity, economic_value_cents, opportunity_id, exclusivity_id,
      region_id, created_by)
    select %L, 'womens_clothing', 'reserved', 4, true, 'direct_benefits', 'BRL', 12, 1, o.id, o.exclusivity_id, %L, %L
      from public.commercial_opportunities o
     where o.exclusivity_id = (select id from exc298 where k = 1) and o.niche_code = 'womens_clothing'$s$,
    :'c1', :'reg', :'u1'), 'artwork_change_not_ready');
rollback to savepoint nao_pronta;
select pg_temp.tornar_corrente(0);

-- P1-2: duas campanhas depois, com prontidão SIMULADA ([QA FICTICIO]).
savepoint duas_depois;
select pg_temp.simular_prontidao();
select pg_temp.pedido(2, :'c1', 'womens_clothing', true) as k2 \gset
select tests.check('P1-2: duas campanhas depois a alteracao NAO vale (reutilizacao verificada no lugar; alteracao intacta)',
    (select artwork_change_request_id is null and flag_reuse_set_id = (:'conj')::uuid
       from public.commercial_exclusivity_orders where id = (:'k2')::uuid)
    and (public.commercial_artwork_change_renewal_state((:'c1')::uuid, 'womens_clothing',
           (select id from exc298 where k = 1))->>'state') = 'ready');
rollback to savepoint duas_depois;

savepoint campanha_certa;
select pg_temp.simular_prontidao();
select pg_temp.pedido(1, :'c1', 'womens_clothing', true) as k1 \gset
select tests.check('P1-2: na campanha alvo (k=1) a alteracao pronta substitui a reutilizacao',
    (select artwork_change_request_id = (:'req')::uuid and flag_reuse_set_id is null
       from public.commercial_exclusivity_orders where id = (:'k1')::uuid));
update public.commercial_exclusivity_orders set status = 'cancelled' where id = (:'k1')::uuid;
select pg_temp.pedido(2, :'c1', 'womens_clothing', true) as k2b \gset
select tests.check('P1-2: pedido da campanha alvo cancelado: a alteracao NAO migra para a campanha seguinte (pendencia P2)',
    (select artwork_change_request_id is null and flag_reuse_set_id = (:'conj')::uuid
       from public.commercial_exclusivity_orders where id = (:'k2b')::uuid));
rollback to savepoint campanha_certa;

-- P1-2: pedido base que não é o mais recente; campanha alvo adjudicada.
savepoint base_antiga;
select pg_temp.pedido(1, :'c2', 'pharmacy', false);
select tests.check('P1-2: pedido base que nao e o mais recente da identidade e recusado (a proxima campanha ja passou)',
    (pg_temp.como(:'u2', format('select public.artwork_change_request_create(%L)', :'origem2'))->>'reason')
      = 'base_order_not_latest');
rollback to savepoint base_antiga;
savepoint adjudicada2;
select pg_temp.pedido(2, :'c1', 'mens_clothing', false) as base_ph \gset
select pg_temp.pedido(3, :'c2', 'mens_clothing', false);
select tests.check('P1-2: campanha alvo ja adjudicada a outra empresa no nicho: solicitacao recusada',
    (pg_temp.como(:'u1', format('select public.artwork_change_request_create(%L)', :'base_ph'))->>'reason')
      = 'target_campaign_unavailable');
rollback to savepoint adjudicada2;

-- ===========================================================================
-- P1-4. Custo comprovado
-- ===========================================================================
select pg_temp.como(:'u2', format('select public.artwork_change_request_create(%L)', :'origem2')) as cr2 \gset
select (:'cr2')::jsonb->>'request_id' as req2 \gset
select pg_temp.como(:'u2', format('select public.artwork_change_image_path(%L)', :'req2')) as p2 \gset
select pg_temp.objeto((:'p2')::jsonb->>'storage_path', :'u2');
select pg_temp.como(:'u2', format('select public.artwork_change_register_version(%L, 1, %L, %L)',
                                  :'req2', (:'p2')::jsonb->>'storage_path', repeat('b', 64)));
select pg_temp.como(:'u2', format('select public.artwork_change_submit(%L, 2)', :'req2'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_start_review(%L, 3)', :'req2'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_supplier_document_path(%L)', :'req2')) as dp \gset
select (:'dp')::jsonb->>'storage_path' as dpath \gset
select tests.check('P1-4: documento so por caminho do servidor; objeto inexistente e recusado',
    (pg_temp.como(:'adm', format('select public.admin_artwork_change_register_supplier_document(%L, %L, %L)',
       :'req2', 'outro/' || :'dpath', repeat('1', 64)))->>'reason') = 'invalid_path'
    and (pg_temp.como(:'adm', format('select public.admin_artwork_change_register_supplier_document(%L, %L, %L)',
       :'req2', :'dpath', repeat('1', 64)))->>'reason') = 'storage_object_not_found'
    and (pg_temp.como(:'u2', format('select public.admin_artwork_change_supplier_document_path(%L)', :'req2'))->>'reason')
        = 'not_authorized');
insert into storage.objects (bucket_id, name, owner, metadata)
values ('supplier-quote-documents', :'dpath', :'adm', jsonb_build_object('size', 40960, 'mimetype', 'application/pdf'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_register_supplier_document(%L, %L, %L)',
                                   :'req2', :'dpath', repeat('1', 64))) as dr \gset
select (:'dr')::jsonb->>'document_id' as doc1 \gset
select tests.check('P1-4: documento registrado com metadados do Storage e atestado PENDENTE',
    ((:'dr')::jsonb->>'attestation') = 'pending'
    and (select byte_size = 40960 and mime_type = 'application/pdf' and attested_sha256 is null
           from public.commercial_artwork_change_supplier_documents where id = (:'doc1')::uuid));
create or replace function pg_temp.itens(p_q int, p_u bigint, p_t bigint) returns text language sql as $f$
  select format($j$jsonb_build_array(jsonb_build_object('kind', 'flag_pieces', 'description', 'bandeiras arte nova',
           'document_locator', 'p.1 l.3', 'quantity', %s, 'unit_cost_cents', %s, 'line_total_cents', %s))$j$, p_q, p_u, p_t);
$f$;
select tests.check('P1-4: orcamento com documento ainda NAO atestado e recusado (declarado nao basta)',
    (pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, %L, 'Fornecedor 299',
       'ORC-299-1', '40 bandeiras arte nova', %s, 150000)$s$, :'req2', :'doc1', pg_temp.itens(40, 3500, 140000)))->>'reason')
      = 'supplier_document_not_attested');
select tests.check_raises('P1-4: atestado so pelo servidor (service_role): administrador autenticado nao executa',
  format($s$select pg_temp.como(%L, format('select public.service_artwork_change_attest_supplier_document(%%L, %%L, %%L, 40960)',
     %L, (select id from storage.objects where name = %L), repeat('1', 64)))$s$, :'adm', :'doc1', :'dpath'),
  'permission denied');
select public.service_artwork_change_attest_supplier_document((:'doc1')::uuid,
  (select id from storage.objects where bucket_id = 'supplier-quote-documents' and name = :'dpath'), repeat('2', 64), 40960) as at1 \gset
select tests.check('P1-4: bytes com SHA-256 diferente do declarado: divergencia REGISTRADA e orcamento recusado',
    ((:'at1')::jsonb->>'reason') = 'supplier_document_sha256_mismatch'
    and (select attested_sha256 = repeat('2', 64) and declared_sha256 = repeat('1', 64)
           from public.commercial_artwork_change_supplier_documents where id = (:'doc1')::uuid)
    and (pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, %L, 'Fornecedor 299',
       'ORC-299-1', '40 bandeiras arte nova', %s, 150000)$s$, :'req2', :'doc1', pg_temp.itens(40, 3500, 140000)))->>'reason')
      = 'supplier_document_sha256_mismatch');
select tests.check_raises('P1-4: atestado e unico e imutavel',
  format($s$update public.commercial_artwork_change_supplier_documents set attested_sha256 = repeat('1', 64) where id = %L$s$, :'doc1'),
  'alteracao_arte_imutavel');
select tests.check('P1-4: segundo atestado recusado (ja atestado)',
    (public.service_artwork_change_attest_supplier_document((:'doc1')::uuid,
       (select id from storage.objects where name = :'dpath'), repeat('1', 64), 40960)->>'reason') = 'already_attested');
-- Documento correto (novo objeto), atestado igual ao declarado.
select pg_temp.como(:'adm', format('select public.admin_artwork_change_supplier_document_path(%L)', :'req2')) as dp2 \gset
select (:'dp2')::jsonb->>'storage_path' as dpath2 \gset
insert into storage.objects (bucket_id, name, owner, metadata)
values ('supplier-quote-documents', :'dpath2', :'adm', jsonb_build_object('size', 40960, 'mimetype', 'application/pdf'));
select (pg_temp.como(:'adm', format('select public.admin_artwork_change_register_supplier_document(%L, %L, %L)',
        :'req2', :'dpath2', repeat('3', 64)))->>'document_id') as doc2 \gset
select tests.check('P1-4: atestado do servidor com o objeto trocado (id/tamanho) e recusado',
    (public.service_artwork_change_attest_supplier_document((:'doc2')::uuid, gen_random_uuid(), repeat('3', 64), 40960)->>'reason')
      = 'storage_object_changed'
    and (public.service_artwork_change_attest_supplier_document((:'doc2')::uuid,
          (select id from storage.objects where name = :'dpath2'), repeat('3', 64), 40961)->>'reason') = 'storage_object_changed');
select public.service_artwork_change_attest_supplier_document((:'doc2')::uuid,
  (select id from storage.objects where name = :'dpath2'), repeat('3', 64), 40960) as at2 \gset
select tests.check('P1-4: atestado igual ao declarado', ((:'at2')::jsonb->>'ok') = 'true');
select tests.check('P1-4: documento de OUTRA solicitacao nao serve',
    (pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, %L, 'Fornecedor 299',
       'ORC-299-1', '40 bandeiras arte nova', %s, 150000)$s$, :'req2', gen_random_uuid(), pg_temp.itens(40, 3500, 140000)))->>'reason')
      = 'supplier_document_not_found');
select tests.check('P1-4: item com total diferente de quantidade x unitario e recusado',
    (pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, %L, 'Fornecedor 299',
       'ORC-299-1', '40 bandeiras arte nova', %s, 150000)$s$, :'req2', :'doc2', pg_temp.itens(40, 3500, 141000)))->>'reason')
      = 'quote_item_total_mismatch');
select tests.check('P1-4: rubrica fora da fabricacao das pecas (ex.: setup/matriz) exige decisao propria: recusada',
    (pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, %L, 'Fornecedor 299',
       'ORC-299-1', '40 bandeiras arte nova',
       jsonb_build_array(jsonb_build_object('kind', 'setup', 'description', 'matriz', 'document_locator', 'p.1',
                         'quantity', 1, 'unit_cost_cents', 5000, 'line_total_cents', 5000)), 150000)$s$, :'req2', :'doc2'))->>'reason')
      = 'quote_item_kind_not_allowed');
-- Preço não linear: dois itens explícitos (50 x 35,00 + 34 x 30,00).
select pg_temp.como(:'adm', format($s$select public.admin_artwork_change_register_quote(%L, 4, %L, 'Fornecedor 299',
       'ORC-299-2', '84 bandeiras arte nova, faixas de preco',
       jsonb_build_array(
         jsonb_build_object('kind', 'flag_pieces', 'description', 'faixa 1 a 50', 'document_locator', 'p.1 l.3',
                            'quantity', 50, 'unit_cost_cents', 3500, 'line_total_cents', 175000),
         jsonb_build_object('kind', 'flag_pieces', 'description', 'faixa 51 a 84', 'document_locator', 'p.1 l.4',
                            'quantity', 34, 'unit_cost_cents', 3000, 'line_total_cents', 102000)), 280000)$s$,
       :'req2', :'doc2')) as qn \gset
select (:'qn')::jsonb->>'quote_id' as qn_id \gset
set constraints all immediate;
set constraints all deferred;
select tests.check('P1-4: preco NAO linear em itens explicitos: 84 pecas, total 2.770,00 = soma dos itens, sem unitario unico, valor ao parceiro = total',
    ((:'qn')::jsonb->>'ok') = 'true'
    and (select pieces_count = 84 and supplier_total_cents = 277000 and supplier_unit_cost_cents is null
                and partner_charge_cents = 277000 and supplier_document_sha256 = repeat('3', 64)
                and supplier_document_id = (:'doc2')::uuid
           from public.commercial_artwork_change_quotes where id = (:'qn_id')::uuid));
savepoint item_extra;
insert into public.commercial_artwork_change_quote_items (quote_id, line_no, kind, description, document_locator,
  quantity, unit_cost_cents, line_total_cents)
values ((:'qn_id')::uuid, 3, 'flag_pieces', 'item acrescentado depois', 'p.9', 1, 100, 100);
select tests.check_raises('P1-4: item acrescentado depois do orcamento quebra a conciliacao (recusado no fim da transacao)',
  'set constraints all immediate', 'orcamento_pecas_divergentes');
rollback to savepoint item_extra;
savepoint direto;
select tests.check_raises('P1-4: orcamento gravado direto com unitario x pecas <> total viola o CHECK',
  format($s$insert into public.commercial_artwork_change_quotes (request_id, quote_no, artwork_version_id, supplier_name,
      supplier_document_reference, supplier_document_sha256, supplier_document_id, scope, pieces_count,
      supplier_unit_cost_cents, supplier_total_cents, cap_cents, registered_by, status)
    select %L, 90, id, 'Fornecedor X', 'ORC-XYZ', repeat('3', 64), %L, 'escopo x', 40, 3500, 150000, 200000, %L, 'superseded'
      from public.commercial_artwork_change_versions where request_id = %L$s$, :'req2', :'doc2', :'adm', :'req2'),
  'cacq_valores');
insert into public.commercial_artwork_change_quotes (request_id, quote_no, artwork_version_id, supplier_name,
  supplier_document_reference, supplier_document_sha256, supplier_document_id, scope, pieces_count,
  supplier_unit_cost_cents, supplier_total_cents, cap_cents, registered_by, status)
select (:'req2')::uuid, 91, id, 'Fornecedor X', 'ORC-XYZ', repeat('3', 64), (:'doc2')::uuid, 'escopo x', 40, null, 150000, 200000, (:'adm')::uuid, 'superseded'
  from public.commercial_artwork_change_versions where request_id = (:'req2')::uuid;
select tests.check_raises('P1-4: orcamento gravado direto sem itens e recusado no fim da transacao',
  'set constraints all immediate', 'orcamento_sem_itens');
rollback to savepoint direto;
savepoint total_divergente;
insert into public.commercial_artwork_change_quotes (request_id, quote_no, artwork_version_id, supplier_name,
  supplier_document_reference, supplier_document_sha256, supplier_document_id, scope, pieces_count,
  supplier_unit_cost_cents, supplier_total_cents, cap_cents, registered_by, status)
select (:'req2')::uuid, 92, id, 'Fornecedor X', 'ORC-XYZ', repeat('3', 64), (:'doc2')::uuid, 'escopo x', 40, null, 150000, 200000, (:'adm')::uuid, 'superseded'
  from public.commercial_artwork_change_versions where request_id = (:'req2')::uuid;
insert into public.commercial_artwork_change_quote_items (quote_id, line_no, kind, description, document_locator,
  quantity, unit_cost_cents, line_total_cents)
select id, 1, 'flag_pieces', 'pecas', 'p.1', 40, 3500, 140000 from public.commercial_artwork_change_quotes where quote_no = 92;
select tests.check_raises('P1-4: total do orcamento diferente da soma dos itens (margem escondida) e recusado',
  'set constraints all immediate', 'orcamento_total_divergente');
rollback to savepoint total_divergente;
savepoint doc_divergente;
insert into public.commercial_artwork_change_quotes (request_id, quote_no, artwork_version_id, supplier_name,
  supplier_document_reference, supplier_document_sha256, supplier_document_id, scope, pieces_count,
  supplier_unit_cost_cents, supplier_total_cents, cap_cents, registered_by, status)
select (:'req2')::uuid, 93, id, 'Fornecedor X', 'ORC-XYZ', repeat('1', 64), (:'doc1')::uuid, 'escopo x', 40, 3500, 140000, 200000, (:'adm')::uuid, 'superseded'
  from public.commercial_artwork_change_versions where request_id = (:'req2')::uuid;
insert into public.commercial_artwork_change_quote_items (quote_id, line_no, kind, description, document_locator,
  quantity, unit_cost_cents, line_total_cents)
select id, 1, 'flag_pieces', 'pecas', 'p.1', 40, 3500, 140000 from public.commercial_artwork_change_quotes where quote_no = 93;
select tests.check_raises('P1-4: orcamento gravado direto com documento de atestado divergente e recusado',
  'set constraints all immediate', 'orcamento_documento_nao_atestado');
rollback to savepoint doc_divergente;

select tests.check('P1-4: leitura do owner traz itens, documento atestado e prontidao',
    (select (q->'supplier_document'->>'attested') = 'true' and (q->'supplier_document'->>'sha256') = repeat('3', 64)
            and jsonb_array_length(q->'items') = 2 and (q->'items'->1->>'line_total_cents') = '102000'
       from (select pg_temp.como(:'u2', format('select public.artwork_change_requests_for_order(%L)', :'origem2'))
                     ->'requests'->0->'quote' q) x));
select tests.check('P1-4: aceite com SHA-256 de documento diferente do orcado e recusado',
    (pg_temp.como(:'u2', format('select public.artwork_change_accept_quote(%L, 5, %L, 277000, %L)',
       :'req2', :'qn_id', repeat('1', 64)))->>'reason') = 'supplier_document_mismatch');
savepoint objeto_trocado;
delete from storage.objects where bucket_id = 'supplier-quote-documents' and name = :'dpath2';
insert into storage.objects (bucket_id, name, owner, metadata)
values ('supplier-quote-documents', :'dpath2', :'adm', jsonb_build_object('size', 40960, 'mimetype', 'application/pdf'));
select tests.check('P1-4: objeto do Storage trocado depois do atestado: aceite recusado',
    (pg_temp.aceitar(:'u2', :'req2', 5, (:'qn_id')::uuid, 277000)->>'reason') = 'supplier_document_not_valid');
rollback to savepoint objeto_trocado;
select pg_temp.aceitar(:'u2', :'req2', 5, (:'qn_id')::uuid, 277000) as ac2 \gset
select tests.check('P1-4: owner aceita o valor exato e o SHA-256 do documento atestado',
    ((:'ac2')::jsonb->>'status') = 'accepted'
    and exists (select 1 from public.commercial_artwork_change_events where request_id = (:'req2')::uuid
                   and event = 'quote_accepted' and detail->>'supplier_document_sha256' = repeat('3', 64)));
select tests.check('P1-4: Storage: owner le so os documentos das proprias solicitacoes; ninguem sobrescreve',
    (select count(*) = 2 from (select pg_temp.como(:'u2', $q$select to_jsonb(array_agg(name)) from storage.objects
                                  where bucket_id = 'supplier-quote-documents'$q$) a) x, jsonb_array_elements_text(x.a) n)
    and (pg_temp.como(:'u1', $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'supplier-quote-documents'
                                 and name like '$q$ || :'req2' || $q$/%'$q$))::text = '0'
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname like 'cacd_%' and cmd in ('UPDATE', 'DELETE', 'ALL')));

-- ===========================================================================
-- P1-3. Cobertura: adulterações nas guardas NOVAS são detectadas
-- ===========================================================================
select tests.check('P1-3: catalogo v2 vigente cobre as 6 tabelas novas, 14 gatilhos delas e o Storage',
    (select (select count(*) from jsonb_array_elements(c->'tables') x
              where x->>'table' like 'public.commercial_artwork_change_%') = 6
            and (select count(*) from jsonb_object_keys(c->'triggers') k
                  where k like 'public.commercial_artwork_change_%') = 14
            and c->'functions' ? 'public.commercial_artwork_change_readiness(uuid)'
            and c->'functions' ? 'public.commercial_artwork_change_renewal_state(uuid,text,uuid)'
            and c->'storage'->'buckets' ? 'supplier-quote-documents'
       from (select catalog c from public.commercial_guard_manifests order by id desc limit 1) m));
create or replace function pg_temp.adultera(p_sql text, p_esperado text) returns boolean language plpgsql as $f$
declare v text[];
begin
  begin
    execute p_sql;
    v := public.commercial_guard_integrity_failures();
    raise exception 'desfaz' using detail = array_to_string(v, ' ; ');
  exception when raise_exception then
    get stacked diagnostics p_sql = pg_exception_detail;
  end;
  return p_sql like '%' || p_esperado || '%';
end $f$;
select tests.check('P1-3: gatilho da maquina de estados desabilitado: DETECTADO',
    pg_temp.adultera('alter table public.commercial_artwork_change_requests disable trigger cacr_protect',
                     'guard_trigger_state_not_approved:public.commercial_artwork_change_requests.cacr_protect'));
select tests.check('P1-3: gatilho em ENABLE REPLICA: DETECTADO',
    pg_temp.adultera('alter table public.commercial_artwork_change_quotes enable replica trigger cacq_append_only',
                     'guard_trigger_state_not_approved:public.commercial_artwork_change_quotes.cacq_append_only'));
select tests.check('P1-3: funcao de prontidao trocada (sempre pronta): DETECTADO',
    pg_temp.adultera($x$create or replace function public.commercial_artwork_change_readiness(p_request_id uuid)
      returns jsonb language sql stable security definer set search_path to 'pg_catalog'
      as $b$ select '{"ready": true}'::jsonb $b$$x$,
      'guard_function_divergent:public.commercial_artwork_change_readiness(uuid)'));
select tests.check('P1-3: funcao do gatilho de conciliacao trocada: DETECTADO',
    pg_temp.adultera($x$create or replace function public.commercial_artwork_change_quote_reconcile() returns trigger
      language plpgsql set search_path to 'pg_catalog' as $b$ begin return null; end $b$$x$,
      'guard_function_divergent:public.commercial_artwork_change_quote_reconcile()'));
select tests.check('P1-3: indice de uso unico/campanha removido: DETECTADO',
    pg_temp.adultera('drop index public.cacr_uma_por_campanha_idx',
                     'guard_table_divergent:public.commercial_artwork_change_requests:indexes'));
select tests.check('P1-3: CHECK da conciliacao do item removido: DETECTADO',
    pg_temp.adultera('alter table public.commercial_artwork_change_quote_items drop constraint cacqi_valores',
                     'guard_table_divergent:public.commercial_artwork_change_quote_items:constraints'));
select tests.check('P1-3: escrita concedida a authenticated: DETECTADO',
    pg_temp.adultera('grant insert on public.commercial_artwork_change_quotes to authenticated',
                     'guard_table_divergent:public.commercial_artwork_change_quotes:acl'));
select tests.check('P1-3: RLS desligada: DETECTADO',
    pg_temp.adultera('alter table public.commercial_artwork_change_supplier_documents disable row level security',
                     'guard_table_divergent:public.commercial_artwork_change_supplier_documents:rls'));
select tests.check('P1-3: coluna gerada substituida por coluna comum (margem possivel): DETECTADO',
    pg_temp.adultera('alter table public.commercial_artwork_change_quotes alter column partner_charge_cents drop expression',
                     'guard_table_divergent:public.commercial_artwork_change_quotes:columns_sha256'));
select tests.check('P1-3: atestado liberado para authenticated: DETECTADO',
    pg_temp.adultera('grant execute on function public.service_artwork_change_attest_supplier_document(uuid, uuid, text, bigint) to authenticated',
                     'guard_function_divergent:public.service_artwork_change_attest_supplier_document(uuid,uuid,text,bigint)'));
select tests.check('P1-3: bucket do documento tornado publico: DETECTADO',
    pg_temp.adultera($x$update storage.buckets set public = true where id = 'supplier-quote-documents'$x$,
                     'guard_storage_divergent:buckets'));
select tests.check('P1-3: politica de UPDATE no Storage acrescentada: DETECTADO',
    pg_temp.adultera($x$create policy cacd_x on storage.objects for update to authenticated
                       using (bucket_id = 'supplier-quote-documents')$x$, 'guard_storage_divergent:policies'));
savepoint pre_ativacao;
alter table public.commercial_artwork_change_requests disable trigger cacr_protect;
select tests.check('P1-3: adulteracao das guardas novas tambem aparece na pre-verificacao de ativacao',
    exists (select 1 from jsonb_array_elements_text(public.commercial_pricing_activation_preflight(4)->'failures') f
             where f like '%cacr_protect%'));
rollback to savepoint pre_ativacao;
select tests.check('P1-3: depois das contraprovas (revertidas) as guardas estao integras',
    public.commercial_guard_integrity_failures() = array[]::text[]);
rollback;

select tests.check('apos a suite: nada vazou (sem solicitacao/documento, v4 preparada, sem ativacao, sem preco de dinheiro)',
    not exists (select 1 from public.commercial_artwork_change_requests)
    and not exists (select 1 from public.commercial_artwork_change_supplier_documents)
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and not exists (select 1 from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'));

select tests.finish('299_r421_correcoes_direcionadas');
