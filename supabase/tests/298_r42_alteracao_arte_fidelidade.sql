-- ===========================================================================
-- 298 — R4.2: fidelidade independente da reutilização das bandeiras e
-- solicitação de alteração de frase/arte (migration 20261116120000).
--   B. trocar a frase/arte não tira a fidelidade; produção nova em rubrica
--      separada; reutilização parcial (peças danificadas) segue bloqueada;
--   C. custo comprovado do fornecedor, sem margem; teto; aceite do owner;
--      orçamento revisado exige novo aceite;
--   D. próxima campanha por padrão; campanha atual só com exceção do
--      administrador; manager sem permissão; dupla solicitação; cancelamento;
--      concorrência por versão; imagem travada depois da produção.
-- R4.2.1 (20261116180000): adaptada à API corrigida, sem perder cobertura:
--   * orçamento por documento do fornecedor ATESTADO + itens (pg_temp.orcar)
--     e aceite com o SHA-256 do documento (pg_temp.aceitar);
--   * a renovação com alteração de arte agora é RECUSADA enquanto não houver
--     prontidão (P1-1); o caminho "pronta" é exercitado com a prontidão
--     SIMULADA dentro de um savepoint revertido ([QA FICTICIO]).
--   Mudanças de expectativa: docs/release/R421_MATRIZ_CORRECOES_20261116.md.
-- Preços do DINHEIRO, aprovações e procedimento de QA aqui são FIXTURES
-- [QA FICTICIO] (a ativação da SF-v1.5 é só para exercitar as regras), tudo
-- numa transação revertida. O Cenário A REAL é ensaiado em
-- scripts/db-test/r42-cenario-a.sh, contra o roteiro de ops.
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

select tests.check('pedido de origem: novo, 84 pecas produzidas, conjunto do pedido; empresa fidelizada pelas regras do servidor',
    (select not fidelized and flag_production_new_units = 84 and artwork_change_request_id is null
       from public.commercial_exclusivity_orders where id = (:'origem')::uuid)
    and public.is_fidelized_context('29800001000100', 'ES', 'viana', 'womens_clothing', null));

-- ---------------------------------------------------------------------------
-- D. Imagem do pedido travada depois da produção
-- ---------------------------------------------------------------------------
select tests.check('com o conjunto produzido, o caminho de troca direta da imagem e recusado (troca so por solicitacao)',
    (pg_temp.como(:'u1', format('select public.request_customization_image_path(%L)', :'origem'))->>'reason')
      = 'artwork_locked_use_change_request');
select pg_temp.objeto(:'origem' || '/troca-direta-298', :'u1');
select tests.check('com o conjunto produzido, o registro direto de nova imagem e recusado',
    (pg_temp.como(:'u1', format('select public.register_customization_image(%L, %L)',
                                :'origem', :'origem' || '/troca-direta-298'))->>'reason')
      = 'artwork_locked_use_change_request'
    and not exists (select 1 from public.commercial_order_customization_images where order_id = (:'origem')::uuid));

-- ---------------------------------------------------------------------------
-- C/D. Solicitação: papéis, dupla solicitação, versão, orçamento, aceite
-- ---------------------------------------------------------------------------
select tests.check('manager NAO abre solicitacao (o owner solicita e aceita)',
    (pg_temp.como(:'m1', format('select public.artwork_change_request_create(%L)', :'origem'))->>'reason')
      = 'not_authorized');
select tests.check('owner de OUTRA empresa nao abre solicitacao neste pedido',
    (pg_temp.como(:'u2', format('select public.artwork_change_request_create(%L)', :'origem'))->>'reason')
      = 'not_authorized');
select pg_temp.como(:'u1', format($s$select public.artwork_change_request_create(%L, 'next_campaign',
         'Nova frase da campanha 298', '[QA FICTICIO] troca de frase')$s$, :'origem')) as cr \gset
select (:'cr')::jsonb->>'request_id' as req \gset
select tests.check('owner abre rascunho para a PROXIMA campanha; identidade derivada do pedido',
    ((:'cr')::jsonb->>'ok') = 'true'
    and (select status = 'draft' and target_campaign = 'next_campaign' and fidelity_identity = 'womens_clothing'
                and company_id = (:'c1')::uuid and requested_by = (:'u1')::uuid
           from public.commercial_artwork_change_requests where id = (:'req')::uuid));
select tests.check('dupla solicitacao para a mesma empresa e identidade e recusada',
    (pg_temp.como(:'u1', format('select public.artwork_change_request_create(%L)', :'origem'))->>'reason')
      = 'artwork_change_already_open');
select tests.check('envio sem arte e recusado',
    (pg_temp.como(:'u1', format('select public.artwork_change_submit(%L, 1)', :'req'))->>'reason')
      = 'artwork_version_required');
select pg_temp.como(:'u1', format('select public.artwork_change_image_path(%L)', :'req')) as p1 \gset
select tests.check('caminho da arte derivado no servidor, preso ao pedido e a solicitacao; manager nao recebe caminho',
    ((:'p1')::jsonb->>'storage_path') like :'origem' || '/alteracao-arte/' || :'req' || '/%'
    and (pg_temp.como(:'m1', format('select public.artwork_change_image_path(%L)', :'req'))->>'reason') = 'not_authorized');
select ((:'p1')::jsonb->>'storage_path') as path1 \gset
select tests.check('arte sem objeto no Storage e recusada',
    (pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 1, %L, %L)',
                                :'req', :'path1', repeat('a', 64)))->>'reason') = 'storage_object_not_found');
select pg_temp.objeto(:'path1', :'u1');
select tests.check('caminho de outro pedido e recusado',
    (pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 1, %L, %L)',
                                :'req', :'origem2' || '/x', repeat('a', 64)))->>'reason') = 'invalid_path');
select pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 1, %L, %L, %L)',
                                  :'req', :'path1', repeat('a', 64), 'Nova frase da campanha 298')) as v1 \gset
select tests.check('arte versao 1 registrada (MIME e tamanho do Storage, SHA-256 informado)',
    ((:'v1')::jsonb->>'ok') = 'true' and ((:'v1')::jsonb->>'version_no') = '1'
    and (select mime_type = 'image/png' and byte_size = 204800 and sha256 = repeat('a', 64)
           from public.commercial_artwork_change_versions where request_id = (:'req')::uuid));
select tests.check('concorrencia: transicao com row_version desatualizada e recusada (stale_request)',
    (pg_temp.como(:'u1', format('select public.artwork_change_submit(%L, 1)', :'req'))->>'reason') = 'stale_request');
select tests.check('owner envia com a row_version corrente',
    (pg_temp.como(:'u1', format('select public.artwork_change_submit(%L, 2)', :'req'))->>'status') = 'submitted');
select tests.check('owner nao executa passo de administrador',
    (pg_temp.como(:'u1', format('select public.admin_artwork_change_start_review(%L, 3)', :'req'))->>'reason')
      = 'not_authorized');
select tests.check('administrador inicia a analise',
    (pg_temp.como(:'adm', format('select public.admin_artwork_change_start_review(%L, 3)', :'req'))->>'status')
      = 'under_review');
select tests.check('sem orcamento nao ha aceite',
    (pg_temp.aceitar(:'u1', :'req', 4, (gen_random_uuid())::uuid, 1)->>'reason')
      = 'invalid_status');
select tests.check('orcamento sem documento do fornecedor (SHA-256) e recusado',
    (pg_temp.orcar(:'req', 4, 'ORC-298-1', 'sem-hash', '40 bandeiras com a nova arte', 40, 3500, 140000, 150000)->>'reason')
      = 'invalid_sha256');
select tests.check('orcamento com teto abaixo do total e recusado',
    (pg_temp.orcar(:'req', 4, 'ORC-298-1', repeat('d', 64), '40 bandeiras com a nova arte', 40, 3500, 140000, 139999)->>'reason')
      = 'invalid_quote_values');
select pg_temp.orcar(:'req', 4, 'ORC-298-1', repeat('d', 64), '40 bandeiras com a nova arte, sem frete', 40, 3500, 140000, 150000) as q1 \gset
select (:'q1')::jsonb->>'quote_id' as quote1 \gset
select tests.check('orcamento: valor ao parceiro = custo comprovado do fornecedor (sem margem); 40 pecas, nao 84 automaticas',
    ((:'q1')::jsonb->>'status') = 'quoted'
    and (select partner_charge_cents = supplier_total_cents and supplier_total_cents = 140000 and pieces_count = 40
       from public.commercial_artwork_change_quotes where id = (:'quote1')::uuid));
select tests.check('frete, criacao de arte, instalacao, tributos e servicos ficam expressamente NAO incluidos',
    (select excluded_items @> array['frete','criacao_de_arte','instalacao','tributos','servicos']
       from public.commercial_artwork_change_quotes where id = (:'quote1')::uuid));
select tests.check_raises('margem impossivel: valor ao parceiro nao e informado, e gerado do custo do fornecedor',
  format($s$insert into public.commercial_artwork_change_quotes (request_id, quote_no, artwork_version_id, supplier_name,
      supplier_document_reference, supplier_document_sha256, scope, pieces_count, supplier_unit_cost_cents,
      supplier_total_cents, partner_charge_cents, cap_cents, registered_by)
    select %L, 99, id, 'F', 'ORC-X', repeat('e', 64), 'escopo x', 1, 1, 100, 130, 200, %L
      from public.commercial_artwork_change_versions where request_id = %L$s$, :'req', :'adm', :'req'),
  'partner_charge_cents');
select tests.check('manager nao aceita custo',
    (pg_temp.aceitar(:'m1', :'req', 5, (:'quote1')::uuid, 140000)->>'reason')
      = 'not_authorized');
select tests.check('aceite com valor diferente do orcado e recusado',
    (pg_temp.aceitar(:'u1', :'req', 5, (:'quote1')::uuid, 150000)->>'reason')
      = 'accepted_total_mismatch');
select tests.check('owner aceita o valor exato do orcamento',
    (pg_temp.aceitar(:'u1', :'req', 5, (:'quote1')::uuid, 140000)->>'status')
      = 'accepted');
select pg_temp.orcar(:'req', 6, 'ORC-298-2', repeat('f', 64), '40 bandeiras com a nova arte, revisado', 40, 4000, 160000, 170000) as q2 \gset
select (:'q2')::jsonb->>'quote_id' as quote2 \gset
select tests.check('aumento posterior: orcamento revisado DERRUBA o aceite e exige nova aprovacao',
    (select status = 'quoted' and accepted_quote_id is null and accepted_total_cents is null
       from public.commercial_artwork_change_requests where id = (:'req')::uuid)
    and (select status from public.commercial_artwork_change_quotes where id = (:'quote1')::uuid) = 'superseded'
    and exists (select 1 from public.commercial_artwork_change_events
                 where request_id = (:'req')::uuid and event = 'quote_revised_acceptance_cleared'));
select pg_temp.como(:'u1', format('select public.artwork_change_image_path(%L)', :'req')) as p2 \gset
select pg_temp.objeto((:'p2')::jsonb->>'storage_path', :'u1');
select pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 7, %L, %L)',
                                  :'req', (:'p2')::jsonb->>'storage_path', repeat('b', 64))) as v2 \gset
select tests.check('nova arte depois do orcamento derruba o orcamento e volta para analise',
    ((:'v2')::jsonb->>'status') = 'under_review'
    and (select status from public.commercial_artwork_change_quotes where id = (:'quote2')::uuid) = 'superseded');
select pg_temp.orcar(:'req', 8, 'ORC-298-3', repeat('c', 64), '40 bandeiras com a arte versao 2', 40, 4000, 160000, 170000) as q3 \gset
select tests.check('orcamento novo fica preso a arte vigente (versao 2)',
    (select v.version_no = 2 from public.commercial_artwork_change_quotes q
       join public.commercial_artwork_change_versions v on v.id = q.artwork_version_id
      where q.id = ((:'q3')::jsonb->>'quote_id')::uuid));
select tests.check('aceite do orcamento vigente',
    (pg_temp.aceitar(:'u1', :'req', 9, ((:'q3')::jsonb->>'quote_id')::uuid, 160000)->>'status') = 'accepted');
select pg_temp.como(:'adm', format('select public.admin_artwork_change_authorize_production(%L, 10)', :'req')) as ap \gset
select tests.check('producao autorizada (proxima campanha); cobranca e despacho externos indisponiveis',
    ((:'ap')::jsonb->>'status') = 'production_authorized'
    and ((:'ap')::jsonb->>'billing') = 'not_available' and ((:'ap')::jsonb->>'production_dispatch') = 'not_available');
select tests.check('depois da producao autorizada, nem cancelamento nem nova arte',
    (pg_temp.como(:'u1', format($s$select public.artwork_change_cancel(%L, 11, 'desisti')$s$, :'req'))->>'reason') = 'invalid_status'
    and (pg_temp.como(:'u1', format('select public.artwork_change_image_path(%L)', :'req'))->>'reason') = 'invalid_status');
select tests.check('manager le a solicitacao, mas nao decide',
    (select (r->>'viewer_role') = 'partner_member' and (r->>'can_request') = 'false'
            and jsonb_array_length(r->'requests') = 1
       from (select pg_temp.como(:'m1', format('select public.artwork_change_requests_for_order(%L)', :'origem')) r) x)
    and (pg_temp.como(:'u2', format('select public.artwork_change_requests_for_order(%L)', :'origem'))->>'reason')
        = 'not_authorized');

-- ---------------------------------------------------------------------------
-- B. Fidelidade != reutilização na renovação (próxima campanha)
-- ---------------------------------------------------------------------------
select pg_temp.tornar_corrente(1);
-- R4.2.1 (P1-1): autorização de produção não é prontidão. Sem os fatos de
-- cobrança e de produção, a renovação é recusada (sem cair para as
-- bandeiras antigas) em todos os caminhos.
savepoint prontidao_real;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'direct_benefits')$s$,
                                  :'c1')) as r0 \gset
select tests.check('R4.2.1: producao apenas AUTORIZADA nao habilita renovacao fidelizada (reserva recusada, nada reservado)',
    ((:'r0')::jsonb->>'ok') = 'false' and ((:'r0')::jsonb->>'reason') = 'artwork_change_not_ready'
    and not exists (select 1 from public.commercial_checkout_intents where company_id = (:'c1')::uuid));
select tests.check_raises('R4.2.1: venda manual fidelizada tambem recusada sem prontidao',
  format($s$select pg_temp.pedido(1, %L, 'womens_clothing', true)$s$, :'c1'), 'artwork_change_not_ready');
rollback to savepoint prontidao_real;
-- Daqui até o fim da seção: prontidão SIMULADA ([QA FICTICIO]), revertida.
savepoint prontidao_simulada;
select pg_temp.simular_prontidao();
savepoint sem_inspecao;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'direct_benefits')$s$,
                                  :'c1')) as r1 \gset
select tests.check('fidelidade mantida ao trocar a frase: renovacao FIDELIZADA, sem reutilizacao, com a alteracao autorizada',
    ((:'r1')::jsonb->>'ok') = 'true'
    and (select fidelized and flag_production_new_units = 0 and flag_production_charge_cents = 0
                and flag_reuse_set_id is null and flag_reuse_inspection_id is null
                and artwork_change_request_id = (:'req')::uuid
           from public.commercial_checkout_intents where id = ((:'r1')::jsonb->>'intent_id')::uuid));
select tests.check('preco-base, participantes e QA fidelizados inalterados; a producao da nova arte nao entra no preco',
    (select i.economic_value_cents = t.economic_value_cents and i.mei_consideration_cents = t.mei_consideration_cents
            and i.qa_in_kind_cents = t.qa_in_kind_cents and i.economic_value_cents = 1618800
       from public.commercial_checkout_intents i
       join public.commercial_settlement_terms t on t.pricing_rule_version = 4 and t.commercial_category = 'common'
        and t.fidelized and t.benefit_settlement_mode = 'direct_benefits'
      where i.id = ((:'r1')::jsonb->>'intent_id')::uuid));
rollback to savepoint sem_inspecao;

savepoint em_dinheiro;
select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'womens_clothing', 'cash')$s$,
                                  :'c1')) as r1c \gset
select tests.check('mesma renovacao em DINHEIRO: valores do Cenario A (16.127,16), sem QA nenhuma, alteracao de arte vinculada',
    ((:'r1c')::jsonb->>'ok') = 'true'
    and (select economic_value_cents = 1612716 and qa_in_kind_cents = 0 and qa_cash_cents = 0
                and total_monetary_funding_required_cents = 1612716 and fidelized
                and artwork_change_request_id = (:'req')::uuid
           from public.commercial_checkout_intents where id = ((:'r1c')::jsonb->>'intent_id')::uuid));
rollback to savepoint em_dinheiro;

savepoint reuso_parcial_sem_alteracao;
-- Empresa 2: pedido de origem, conjunto, fidelidade e inspeção com 10 peças
-- danificadas, SEM alteração de arte.
select pg_temp.conjunto(:'origem2') as conj2 \gset
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code, established_by_order_id)
values ('29800002000147', 'ES', 'viana', 'pharmacy', :'origem2');
select pg_temp.inspecao(:'conj2', 5, 10, array['damaged']) as insp2 \gset
select pg_temp.como(:'u2', format($s$select public.create_commercial_checkout_intent(%L, 'pharmacy', 'direct_benefits')$s$,
                                  :'c2')) as r2 \gset
select tests.check('reutilizacao parcial (10 pecas danificadas) sem alteracao de arte: bloqueio seguro, sem preco nem cobranca',
    ((:'r2')::jsonb->>'ok') = 'false' and ((:'r2')::jsonb->>'reason') = 'flag_replacement_policy_pending'
    and not exists (select 1 from public.commercial_checkout_intents where company_id = (:'c2')::uuid));
rollback to savepoint reuso_parcial_sem_alteracao;

savepoint uso_unico;
select pg_temp.pedido(1, :'c1', 'womens_clothing', true) as ren1 \gset
select tests.check('venda manual fidelizada usa a MESMA autoridade: alteracao autorizada no lugar da reutilizacao',
    (select fidelized and artwork_change_request_id = (:'req')::uuid and flag_reuse_set_id is null
            and economic_value_cents = 1618800
       from public.commercial_exclusivity_orders where id = (:'ren1')::uuid));
select tests.check_raises('a alteracao serve a UMA renovacao: a segunda volta a exigir reutilizacao verificada',
  format($s$select pg_temp.pedido(2, %L, 'womens_clothing', true)$s$, :'c1'), 'flag_reuse_not_verified');
select tests.check_raises('integridade do snapshot: o vinculo com a alteracao de arte e imutavel',
  format($s$update public.commercial_exclusivity_orders set artwork_change_request_id = null where id = %L$s$, :'ren1'),
  'pedido_imutavel');
select tests.check('pedido renovado com nova arte: imagem travada (troca so por nova solicitacao)',
    (pg_temp.como(:'u1', format('select public.request_customization_image_path(%L)', :'ren1'))->>'reason')
      = 'artwork_locked_use_change_request');
rollback to savepoint uso_unico;
rollback to savepoint prontidao_simulada;

select tests.check('o banco recusa pedido fidelizado com alteracao de arte e reutilizacao ao mesmo tempo (CHECK)',
    (select pg_get_constraintdef(oid) like '%artwork_change_request_id IS NULL%'
       from pg_constraint where conname = 'ceo_bandeiras_coerente'));

-- ---------------------------------------------------------------------------
-- D. Campanha ATUAL: só com exceção do administrador
-- ---------------------------------------------------------------------------
select pg_temp.como(:'u1', format($s$select public.artwork_change_request_create(%L, 'current_campaign', 'Frase urgente 298')$s$,
                                  :'origem')) as cr2 \gset
select (:'cr2')::jsonb->>'request_id' as req2 \gset
select pg_temp.como(:'u1', format('select public.artwork_change_image_path(%L)', :'req2')) as p3 \gset
select pg_temp.objeto((:'p3')::jsonb->>'storage_path', :'u1');
select pg_temp.como(:'u1', format('select public.artwork_change_register_version(%L, 1, %L, %L)',
                                  :'req2', (:'p3')::jsonb->>'storage_path', repeat('9', 64)));
select pg_temp.como(:'u1', format('select public.artwork_change_submit(%L, 2)', :'req2'));
select pg_temp.como(:'adm', format('select public.admin_artwork_change_start_review(%L, 3)', :'req2'));
select pg_temp.orcar(:'req2', 4, 'ORC-298-9', repeat('8', 64), '12 bandeiras, reimpressao urgente', 12, 3500, 42000, 45000) as q9 \gset
select pg_temp.aceitar(:'u1', :'req2', 5, ((:'q9')::jsonb->>'quote_id')::uuid, 42000);
select tests.check('campanha atual SEM excecao: producao nao e autorizada',
    (pg_temp.como(:'adm', format('select public.admin_artwork_change_authorize_production(%L, 6)', :'req2'))->>'reason')
      = 'current_campaign_exception_required');
select tests.check('owner e manager nao aprovam a excecao',
    (pg_temp.como(:'u1', format($s$select public.admin_artwork_change_approve_exception(%L, 6, 'motivo do owner aqui', 'viavel segundo o owner')$s$, :'req2'))->>'reason') = 'not_authorized'
    and (pg_temp.como(:'m1', format($s$select public.admin_artwork_change_approve_exception(%L, 6, 'motivo do manager aqui', 'viavel segundo o manager')$s$, :'req2'))->>'reason') = 'not_authorized');
select tests.check('excecao exige motivo e avaliacao de viabilidade',
    (pg_temp.como(:'adm', format($s$select public.admin_artwork_change_approve_exception(%L, 6, 'curto', 'curto')$s$, :'req2'))->>'reason')
      = 'exception_reason_and_feasibility_required');
select pg_temp.como(:'adm', format($s$select public.admin_artwork_change_approve_exception(%L, 6,
        '[QA FICTICIO] erro na frase impressa', '[QA FICTICIO] fornecedor entrega em 5 dias')$s$, :'req2')) as ex \gset
select pg_temp.como(:'adm', format('select public.admin_artwork_change_authorize_production(%L, 7)', :'req2')) as ap2 \gset
select tests.check('administrador registra a excecao (motivo, viabilidade, autor, data) e autoriza a producao',
    ((:'ex')::jsonb->>'ok') = 'true' and ((:'ap2')::jsonb->>'status') = 'production_authorized'
    and (select exception_approved_by = (:'adm')::uuid and exception_approved_at is not null
                and length(exception_feasibility) >= 10
           from public.commercial_artwork_change_requests where id = (:'req2')::uuid));
select tests.check('alteracao da campanha ATUAL nao serve para a renovacao (so next_campaign substitui a reutilizacao)',
    (public.commercial_artwork_change_renewal_state((:'c1')::uuid, 'womens_clothing',
       (select id from exc298 where k = 1))->>'request_id')::uuid = (:'req')::uuid);
select tests.check('a arte antiga continua valida: o pedido de origem nao foi reescrito',
    (select artwork_change_request_id is null and flag_production_new_units = 84
       from public.commercial_exclusivity_orders where id = (:'origem')::uuid));

-- ---------------------------------------------------------------------------
-- Cancelamento e proteção da máquina de estados
-- ---------------------------------------------------------------------------
select tests.check('R4.2.1: segunda solicitacao para a MESMA campanha alvo (ja autorizada) e recusada',
    (pg_temp.como(:'u1', format('select public.artwork_change_request_create(%L)', :'origem'))->>'reason')
      = 'artwork_change_already_exists_for_campaign');
select pg_temp.como(:'u2', format('select public.artwork_change_request_create(%L)', :'origem2')) as cr3 \gset
select (:'cr3')::jsonb->>'request_id' as req3 \gset
select tests.check('cancelamento exige motivo',
    (pg_temp.como(:'u2', format($s$select public.artwork_change_cancel(%L, 1, '')$s$, :'req3'))->>'reason') = 'reason_required');
select pg_temp.como(:'u2', format($s$select public.artwork_change_cancel(%L, 1, 'mudei de ideia')$s$, :'req3')) as cc \gset
select pg_temp.como(:'u2', format('select public.artwork_change_request_create(%L)', :'origem2')) as cr4 \gset
select tests.check('owner cancela o rascunho; depois disso pode abrir outro',
    ((:'cc')::jsonb->>'status') = 'cancelled' and ((:'cr4')::jsonb->>'ok') = 'true');
select tests.check_raises('maquina de estados vale ate para o dono: rascunho nao pula para producao autorizada',
  format($s$update public.commercial_artwork_change_requests set status = 'production_authorized', row_version = row_version + 1,
            accepted_quote_id = gen_random_uuid(), accepted_total_cents = 1, accepted_by = %L, accepted_at = now(),
            production_authorized_by = %L, production_authorized_at = now()
          where id = (select id from public.commercial_artwork_change_requests where status = 'draft' limit 1)$s$, :'adm', :'adm'),
  'alteracao_arte_transicao_invalida');
select tests.check_raises('solicitacao nao e apagada',
  format($s$delete from public.commercial_artwork_change_requests where id = %L$s$, :'req3'), 'alteracao_arte_imutavel');
select tests.check_raises('versao de arte e append-only',
  format($s$update public.commercial_artwork_change_versions set sha256 = repeat('0', 64) where request_id = %L$s$, :'req'),
  'alteracao_arte_imutavel');
select tests.check_raises('excecao registrada nao e reescrita',
  format($s$update public.commercial_artwork_change_requests set row_version = row_version + 1,
            exception_reason = 'outro motivo qualquer' where id = %L$s$, :'req2'),
  'alteracao_arte_final');
select tests.check('trilha completa da solicitacao (eventos com papel e autor)',
    (select count(*) >= 10
            and bool_and(actor_role in ('partner_owner', 'site_admin')
                         or (actor_role = 'system' and event = 'supplier_document_attested'))
       from public.commercial_artwork_change_events where request_id = (:'req')::uuid));
select tests.check('nada disso tocou a trava da QA nem o manifesto vigente',
    public.commercial_guard_integrity_failures() = array[]::text[]);
rollback;

select tests.check('apos a suite: nada vazou (sem solicitacao, v4 preparada, sem ativacao, sem preco de dinheiro)',
    not exists (select 1 from public.commercial_artwork_change_requests)
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and not exists (select 1 from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'));

select tests.finish('298_r42_alteracao_arte_fidelidade');
