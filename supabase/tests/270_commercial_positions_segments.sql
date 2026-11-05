-- ===========================================================================
-- 270 — POSIÇÕES COMERCIAIS, CALÇADOS UNIFICADO E SEGMENTO OUTROS
-- Migration 20261103120000 · decisões D1–D9 da auditoria 14.
--
-- Prova no BANCO (não no navegador):
--   * seis posições ativas / 84 unidades; Calçados é uma única posição;
--     calçados F/M permanecem como históricos inativos;
--   * Supermercado nunca recebe segmento; Outros sempre exige um;
--   * Outros pode ocupar cada uma das quatro posições elegíveis, ao mesmo
--     tempo, com segmentos distintos; o mesmo segmento não ocupa duas posições;
--   * nenhuma posição é vendida duas vezes;
--   * solicitação de segmento não listado: só owner, não reserva, não aprova;
--     aprovação só por admin, auditada;
--   * fidelidade de segmento segue a classificação, não a posição;
--   * preço vigente preservado; provisionamento e instrumento falham fechados.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
select r.id as reg270 from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg270')::uuid, 270, 'forming', false)
returning id as excl270 \gset

-- Seis oportunidades = seis posições ATIVAS, como o script de fundação faz.
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
select (:'excl270')::uuid, n.code, n.contracted_quantity, 'available'
  from public.commercial_niches n where n.is_active;

update public.commercial_exclusivities set is_current = false
 where region_id = (:'reg270')::uuid and is_current;
update public.commercial_exclusivities set is_current = true
 where id = (:'excl270')::uuid;

select tests.mk_user('admin270@teste.local')   as uid_adm \gset
insert into public.site_admins (user_id) values ((:'uid_adm')::uuid) on conflict do nothing;
select tests.mk_user('gerente270@teste.local') as uid_ger \gset

-- Oito empresas ativas em Viana, cada uma com seu titular (owner).
do $$
declare
  v_cnpjs text[] := array['27010001000173','27010002000118','27010003000162',
                          '27010004000107','27010005000151','27010006000104',
                          '27010007000140','27010008000195'];
  v_i int; v_app uuid; v_comp uuid; v_uid uuid;
begin
  for v_i in 1..8 loop
    v_uid := tests.mk_user('titular270.' || v_i || '@teste.local');
    insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
    values (v_cnpjs[v_i], 'Empresa 270-' || v_i, 'e270' || v_i || '@teste.local', 'Viana', 'ES')
    returning id into v_app;
    insert into public.site_partner_companies
      (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
    values (v_app, v_cnpjs[v_i], 'Empresa 270-' || v_i, 'Loja 270-' || v_i,
            'e270' || v_i || '@teste.local', 'Viana', 'ES', 'active')
    returning id into v_comp;
    insert into public.site_company_members
      (company_id, auth_user_id, role, full_name, source, status)
    values (v_comp, v_uid, 'partner_owner', 'Titular 270-' || v_i,
            'application_promotion', 'active');
  end loop;
end $$;

select c.id as c1 from public.site_partner_companies c where cnpj = '27010001000173' \gset
select c.id as c2 from public.site_partner_companies c where cnpj = '27010002000118' \gset
select c.id as c3 from public.site_partner_companies c where cnpj = '27010003000162' \gset
select c.id as c4 from public.site_partner_companies c where cnpj = '27010004000107' \gset
select c.id as c5 from public.site_partner_companies c where cnpj = '27010005000151' \gset
select c.id as c6 from public.site_partner_companies c where cnpj = '27010006000104' \gset
select c.id as c7 from public.site_partner_companies c where cnpj = '27010007000140' \gset
select c.id as c8 from public.site_partner_companies c where cnpj = '27010008000195' \gset
select m.auth_user_id as u1 from public.site_company_members m where company_id = :'c1' \gset
select m.auth_user_id as u2 from public.site_company_members m where company_id = :'c2' \gset
select m.auth_user_id as u3 from public.site_company_members m where company_id = :'c3' \gset
select m.auth_user_id as u4 from public.site_company_members m where company_id = :'c4' \gset
select m.auth_user_id as u5 from public.site_company_members m where company_id = :'c5' \gset
select m.auth_user_id as u6 from public.site_company_members m where company_id = :'c6' \gset
select m.auth_user_id as u7 from public.site_company_members m where company_id = :'c7' \gset
select m.auth_user_id as u8 from public.site_company_members m where company_id = :'c8' \gset

-- Gerente (não owner) na empresa 7.
insert into public.site_company_members (company_id, auth_user_id, role, full_name, source, status)
values ((:'c7')::uuid, (:'uid_ger')::uuid, 'partner_manager', 'Gerente 270', 'manager_invite', 'active');

-- Acordo Mestre elegível para todas (pré-requisito da reserva, P0-1).
begin;
select tests.impersonate('authenticated', :'uid_adm');
select tests.assinar_mestre_qa(c.id, 'AM-270-' || right(c.cnpj, 6))
  from public.site_partner_companies c where c.cnpj like '2701%';
commit;

-- Catálogo de segmentos criado PELO ADMIN, pela RPC.
begin;
select tests.impersonate('authenticated', :'uid_adm');
select (public.admin_create_commercial_segment('pet_shop','Pet shop','pet_shop')->>'segment_id') as s_pet \gset
select (public.admin_create_commercial_segment('papelaria','Papelaria','papelaria')->>'segment_id') as s_pap \gset
select (public.admin_create_commercial_segment('material_construcao','Material de construção','material_construcao')->>'segment_id') as s_mat \gset
select (public.admin_create_commercial_segment('artigos_esportivos','Artigos esportivos','artigos_esportivos')->>'segment_id') as s_esp \gset
select (public.admin_create_commercial_segment('cosmeticos','Cosméticos','cosmeticos')->>'segment_id') as s_cos \gset
commit;

-- ---------------------------------------------------------------------------
-- 1. Catálogo de posições
-- ---------------------------------------------------------------------------
select tests.check('seis posicoes ativas somando 84 unidades',
    (select count(*) = 6 and sum(contracted_quantity) = 84
       from public.commercial_niches where is_active));
select tests.check('Supermercado ativo com 24 unidades, ordem 1',
    exists (select 1 from public.commercial_niches
             where code = 'supermarket' and is_active
               and contracted_quantity = 24 and sort_order = 1));
select tests.check('Calcados e uma unica posicao ativa (footwear), 12 unidades',
    (select count(*) from public.commercial_niches
      where is_active and code like '%footwear%') = 1
    and exists (select 1 from public.commercial_niches
                 where code = 'footwear' and is_active and contracted_quantity = 12));
select tests.check('Outros e posicao ativa de 12 unidades, ordem 6',
    exists (select 1 from public.commercial_niches
             where code = 'others' and is_active and contracted_quantity = 12
               and sort_order = 6));
select tests.check('calcados F/M permanecem como historicos inativos',
    (select count(*) from public.commercial_niches
      where code in ('womens_footwear','mens_footwear') and not is_active) = 2);
select tests.check_raises('codigo legado nao pode ser reativado',
    $sql$update public.commercial_niches set is_active = true where code = 'womens_footwear'$sql$,
    'commercial_niches_legado_inativo');

-- ---------------------------------------------------------------------------
-- 2. Formação pública
-- ---------------------------------------------------------------------------
select public.get_current_commercial_formation('ES','Viana') as f270 \gset
select tests.check('formacao publica: seis posicoes, 84 unidades',
    jsonb_array_length((:'f270')::jsonb -> 'opportunities') = 6
    and (select sum((o->>'contracted_quantity')::int)
           from jsonb_array_elements((:'f270')::jsonb -> 'opportunities') o) = 84);
select tests.check('formacao publica: supermercado nao aceita segmento; outros exige',
    (select (o->>'accepts_segment')::boolean = false
       from jsonb_array_elements((:'f270')::jsonb -> 'opportunities') o
      where o->>'niche_code' = 'supermarket')
    and (select (o->>'requires_segment')::boolean and (o->>'accepts_segment')::boolean
           from jsonb_array_elements((:'f270')::jsonb -> 'opportunities') o
          where o->>'niche_code' = 'others'));
select tests.check('formacao publica: as quatro posicoes elegiveis aceitam segmento',
    (select count(*) from jsonb_array_elements((:'f270')::jsonb -> 'opportunities') o
      where (o->>'accepts_segment')::boolean
        and o->>'niche_code' in ('pharmacy','womens_clothing','mens_clothing','footwear')) = 4);

-- ---------------------------------------------------------------------------
-- 3. Preço vigente preservado (D3)
-- ---------------------------------------------------------------------------
select tests.check('Calcados e Outros custam exatamente o mesmo que Farmacia (fundador e fidelizado)',
    (select bool_and(
        (public.calculate_niche_contract_pricing(c, f)->>'economic_value_cents')
        = (public.calculate_niche_contract_pricing('pharmacy', f)->>'economic_value_cents')
        and public.calculate_niche_contract_pricing(c, f)->>'niche_category' = 'common')
       from unnest(array['footwear','others']) c, unnest(array[false,true]) f));
select tests.check('Supermercado continua na matriz supermarket',
    public.calculate_niche_contract_pricing('supermarket', false)->>'niche_category' = 'supermarket');
select tests.check('codigo legado nao recebe preco novo (falha fechado)',
    public.calculate_niche_contract_pricing('womens_footwear', false)->>'reason' = 'invalid_niche');

-- ---------------------------------------------------------------------------
-- 4. Supermercado nunca é substituído
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'u1');
select public.create_commercial_checkout_intent(
  (:'c1')::uuid, 'supermarket', 'direct_benefits', (:'s_pet')::uuid) as r_sup \gset
commit;
select tests.check('Supermercado com segmento e recusado no servidor',
    (:'r_sup')::jsonb ->> 'reason' = 'supermarket_not_substitutable');
select tests.check('a recusa nao reservou nada',
    (select status = 'available' from public.commercial_opportunities
      where exclusivity_id = :'excl270' and niche_code = 'supermarket')
    and not exists (select 1 from public.commercial_checkout_intents where company_id = :'c1'));
select tests.check('restricao estrutural: supermercado sem segmento em pedido e intencao',
    (select count(*) from pg_constraint
      where conname in ('ceo_supermercado_sem_segmento','cci_supermercado_sem_segmento',
                        'cpo_supermercado_sem_segmento','csw_supermercado_sem_segmento')) = 4);

-- ---------------------------------------------------------------------------
-- 5. Outros exige segmento aprovado
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'u2');
select public.create_commercial_checkout_intent(
  (:'c2')::uuid, 'others', 'direct_benefits') as r_sem \gset
select public.create_commercial_checkout_intent(
  (:'c2')::uuid, 'others', 'direct_benefits', gen_random_uuid()) as r_inex \gset
commit;
select tests.check('Outros sem segmento e recusado', (:'r_sem')::jsonb ->> 'reason' = 'segment_required');
select tests.check('Outros com segmento inexistente e recusado',
    (:'r_inex')::jsonb ->> 'reason' = 'segment_not_approved');

begin;
select tests.impersonate('authenticated', :'u2');
select public.create_commercial_checkout_intent(
  (:'c2')::uuid, 'others', 'direct_benefits', (:'s_pet')::uuid) as r_out \gset
commit;
select tests.check('Outros com segmento aprovado reserva, com 12 unidades',
    (:'r_out')::jsonb ->> 'ok' = 'true'
    and ((:'r_out')::jsonb ->> 'nominal_quantity')::int = 12
    and (:'r_out')::jsonb ->> 'segment_name' = 'Pet shop');
select tests.check('a intencao guarda o snapshot do segmento',
    (select segment_id = (:'s_pet')::uuid and segment_code_snapshot = 'pet_shop'
            and segment_classification_snapshot = 'pet_shop'
       from public.commercial_checkout_intents
      where id = ((:'r_out')::jsonb ->> 'intent_id')::uuid));

-- ---------------------------------------------------------------------------
-- 6. Mesmo segmento não ocupa duas posições na mesma exclusividade
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'u3');
select public.create_commercial_checkout_intent(
  (:'c3')::uuid, 'pharmacy', 'direct_benefits', (:'s_pet')::uuid) as r_dup \gset
commit;
select tests.check('segmento ja reservado em outra posicao e recusado',
    (:'r_dup')::jsonb ->> 'reason' = 'segment_already_in_exclusivity');
select tests.check('a farmacia continuou disponivel',
    (select status = 'available' from public.commercial_opportunities
      where exclusivity_id = :'excl270' and niche_code = 'pharmacy'));

-- ---------------------------------------------------------------------------
-- 7. Outros substitui CADA uma das quatro posições elegíveis, ao mesmo tempo
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'u3');
select public.create_commercial_checkout_intent((:'c3')::uuid, 'pharmacy', 'direct_benefits', (:'s_pap')::uuid) as r_p \gset
select tests.impersonate('authenticated', :'u4');
select public.create_commercial_checkout_intent((:'c4')::uuid, 'womens_clothing', 'direct_benefits', (:'s_mat')::uuid) as r_wc \gset
select tests.impersonate('authenticated', :'u5');
select public.create_commercial_checkout_intent((:'c5')::uuid, 'mens_clothing', 'direct_benefits', (:'s_esp')::uuid) as r_mc \gset
select tests.impersonate('authenticated', :'u6');
select public.create_commercial_checkout_intent((:'c6')::uuid, 'footwear', 'direct_benefits', (:'s_cos')::uuid) as r_fw \gset
commit;
select tests.check('Farmacia substituida por Papelaria', (:'r_p')::jsonb ->> 'segment_name' = 'Papelaria');
select tests.check('Roupas femininas substituida por Material de construcao',
    (:'r_wc')::jsonb ->> 'segment_name' = 'Material de construção');
select tests.check('Roupas masculinas substituida por Artigos esportivos',
    (:'r_mc')::jsonb ->> 'segment_name' = 'Artigos esportivos');
select tests.check('Calcados substituida por Cosmeticos', (:'r_fw')::jsonb ->> 'segment_name' = 'Cosméticos');
select tests.check('cinco segmentos distintos ocupam cinco posicoes distintas',
    (select count(distinct segment_classification_snapshot) = 5
            and count(distinct opportunity_id) = 5
       from public.commercial_checkout_intents
      where exclusivity_id = :'excl270' and segment_id is not null));
select tests.check('substituicao mantem 12 unidades e nao cria posicao nova',
    (select count(*) = 6 and sum(contracted_quantity) = 84
       from public.commercial_opportunities where exclusivity_id = :'excl270')
    and (select bool_and(nominal_quantity = 12) from public.commercial_checkout_intents
          where exclusivity_id = :'excl270' and segment_id is not null));

-- Vitrine pública com CINCO reservas vivas de segmento: nenhuma identidade
-- comercial é divulgada (só a venda confirmada divulga; ver seção 13).
select public.get_current_commercial_formation('ES','Viana') as f_res \gset
select tests.check('vitrine publica nao divulga segmento de reserva nao paga',
    (select count(*) from jsonb_array_elements((:'f_res')::jsonb -> 'opportunities') o
      where o ? 'segment' and jsonb_typeof(o->'segment') = 'null') = 6
    and (select count(*) from public.commercial_checkout_intents
          where exclusivity_id = :'excl270' and segment_id is not null
            and status in ('draft','awaiting_contract') and reserved_until > now()) = 5);

-- ---------------------------------------------------------------------------
-- 8. Nenhuma posição vendida duas vezes
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'u8');
select public.create_commercial_checkout_intent((:'c8')::uuid, 'pharmacy', 'direct_benefits') as r_twice \gset
commit;
select tests.check('posicao substituida nao pode ser vendida como o nicho original',
    (:'r_twice')::jsonb ->> 'reason' = 'opportunity_reserved');
select tests.check('indices de unicidade: posicao e segmento por exclusividade',
    exists (select 1 from pg_indexes where indexname = 'ceo_nicho_por_exclusividade_idx')
    and exists (select 1 from pg_indexes where indexname = 'ceo_segmento_por_exclusividade_idx')
    and exists (select 1 from pg_indexes where indexname = 'cci_reserva_viva_por_oportunidade_idx'));

-- ---------------------------------------------------------------------------
-- 9. Permissões: manager e empresa alheia
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_ger');
select public.create_commercial_checkout_intent((:'c7')::uuid, 'supermarket', 'direct_benefits') as r_ger \gset
select public.request_commercial_segment((:'c7')::uuid, 'Otica') as r_ger_req \gset
commit;
select tests.check('manager nao reserva', (:'r_ger')::jsonb ->> 'reason' = 'not_company_owner');
select tests.check('manager nao solicita segmento', (:'r_ger_req')::jsonb ->> 'reason' = 'not_company_owner');
begin;
select tests.impersonate('authenticated', :'u1');
select public.request_commercial_segment((:'c7')::uuid, 'Otica') as r_alheio \gset
select public.get_my_commercial_segment_requests((:'c7')::uuid) as r_alheio_list \gset
commit;
select tests.check('owner de outra empresa nao solicita por ela',
    (:'r_alheio')::jsonb ->> 'reason' = 'not_company_owner');
select tests.check('owner de outra empresa nao le as solicitacoes dela',
    (:'r_alheio_list')::jsonb ->> 'reason' = 'not_company_owner');
select tests.check('anon nao executa solicitacao nem decisao',
    not has_function_privilege('anon', 'public.request_commercial_segment(uuid,text,text,text)', 'EXECUTE')
    and not has_function_privilege('anon',
      'public.admin_decide_commercial_segment_request(uuid,text,uuid,text,text,text,text,text,text)', 'EXECUTE'));
select tests.check('tabelas de segmento sem acesso direto do navegador',
    not has_table_privilege('authenticated', 'public.commercial_segments', 'SELECT')
    and not has_table_privilege('authenticated', 'public.commercial_segment_requests', 'INSERT')
    and not has_table_privilege('anon', 'public.commercial_segment_requests', 'SELECT'));

-- ---------------------------------------------------------------------------
-- 10. Solicitação pendente: não reserva, não aprova; decisão só do admin
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'u7');
select public.request_commercial_segment((:'c7')::uuid, '  Ótica  ', 'Vendemos oculos', 'others') as r_req \gset
select public.request_commercial_segment((:'c7')::uuid, 'otica') as r_req2 \gset
select public.request_commercial_segment((:'c7')::uuid, 'Pet Shop') as r_req_listado \gset
commit;
select tests.check('owner solicita segmento nao listado: fica pendente',
    (:'r_req')::jsonb ->> 'ok' = 'true' and (:'r_req')::jsonb ->> 'status' = 'pending');
select tests.check('mesmo nome normalizado nao duplica a solicitacao',
    (:'r_req2')::jsonb ->> 'already' = 'true'
    and (:'r_req2')::jsonb ->> 'request_id' = (:'r_req')::jsonb ->> 'request_id');
select tests.check('nome de segmento ja aprovado aponta para o existente',
    (:'r_req_listado')::jsonb ->> 'reason' = 'segment_already_listed');
select tests.check('solicitacao pendente nao cria reserva, pedido nem segmento',
    not exists (select 1 from public.commercial_checkout_intents where company_id = :'c7')
    and not exists (select 1 from public.commercial_exclusivity_orders where company_id = :'c7')
    and not exists (select 1 from public.commercial_segments where classification_key like 'otica%'));
select tests.check('catalogo publico nao mostra segmento pendente',
    not exists (select 1 from jsonb_array_elements(public.list_commercial_segments()->'segments') s
                 where s->>'name' ilike '%tica%'));

select ((:'r_req')::jsonb ->> 'request_id') as req7 \gset
begin;
select tests.impersonate('authenticated', :'u7');
select tests.check_raises('owner nao aprova a propria solicitacao',
    format($sql$select public.admin_decide_commercial_segment_request(%L::uuid, 'approve',
             null, 'otica', 'Ótica', 'otica')$sql$, :'req7'),
    'not_authorized');
commit;
select tests.check('a solicitacao continua pendente', (select status = 'pending'
    from public.commercial_segment_requests where id = :'req7'));

begin;
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_decide_commercial_segment_request((:'req7')::uuid, 'approve',
  null, 'otica', 'Ótica', 'otica') as r_aprov \gset
commit;
select tests.check('admin aprova criando o segmento',
    (:'r_aprov')::jsonb ->> 'status' = 'approved'
    and exists (select 1 from public.commercial_segments where code = 'otica' and status = 'approved'));
select tests.check('aprovacao auditada sem criar reserva',
    exists (select 1 from public.audit_logs
             where action = 'commercial_segment_request.approved' and entity_id = :'req7')
    and not exists (select 1 from public.commercial_checkout_intents where company_id = :'c7'));
select tests.check_raises('solicitacao decidida e imutavel',
    format($sql$update public.commercial_segment_requests set status = 'pending' where id = %L$sql$, :'req7'),
    'commercial_segment_request_immutable');

-- ---------------------------------------------------------------------------
-- 11. Classificação administrativa e sobreposição a nicho canônico (D5)
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_create_commercial_segment('pet_shop_2','Petshop','pet_shop') as r_sin \gset
select public.admin_create_commercial_segment('farmacia_manipulacao','Farmácia de manipulação',
  'farmacia_manipulacao', null, 'pharmacy', null) as r_sobre_sem \gset
select public.admin_create_commercial_segment('farmacia_manipulacao','Farmácia de manipulação',
  'farmacia_manipulacao', null, 'pharmacy',
  'Somente manipulacao magistral; vedada venda de medicamentos industrializados.') as r_sobre_com \gset
select public.admin_create_commercial_segment('pharmacy_x','Farmácia','pharmacy') as r_canon \gset
commit;
select tests.check('sinonimo com a mesma classificacao nao vira segmento novo',
    (:'r_sin')::jsonb ->> 'reason' = 'classification_already_approved');
select tests.check('sobreposicao a nicho canonico sem delimitacao e recusada',
    (:'r_sobre_sem')::jsonb ->> 'reason' = 'invalid_segment_definition');
select tests.check('sobreposicao com politica expressa de delimitacao e aceita',
    (:'r_sobre_com')::jsonb ->> 'ok' = 'true');
select tests.check('classificacao igual a nicho canonico e recusada',
    (:'r_canon')::jsonb ->> 'reason' = 'invalid_segment_definition');

-- ---------------------------------------------------------------------------
-- 12. Snapshot imutável e arquivamento não retroativo
-- ---------------------------------------------------------------------------
select tests.check_raises('snapshot do segmento na intencao e imutavel',
    format($sql$update public.commercial_checkout_intents set segment_name_snapshot = 'X'
               where id = %L$sql$, (:'r_out')::jsonb ->> 'intent_id'),
    'commercial_segment_snapshot_immutable');
begin;
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_archive_commercial_segment((:'s_pet')::uuid) as r_arq \gset
commit;
select tests.check('arquivar o segmento nao altera a reserva existente',
    (select segment_name_snapshot = 'Pet shop' and segment_id = (:'s_pet')::uuid
       from public.commercial_checkout_intents
      where id = ((:'r_out')::jsonb ->> 'intent_id')::uuid));
begin;
select tests.impersonate('authenticated', :'u8');
select public.join_my_commercial_future_queue((:'c8')::uuid, 'others', (:'s_pet')::uuid) as r_arq_novo \gset
commit;
select tests.check('segmento arquivado nao entra em venda nova',
    (:'r_arq_novo')::jsonb ->> 'reason' = 'segment_not_approved');
select tests.check_raises('segmento nao pode ser renomeado',
    format($sql$update public.commercial_segments set display_name = 'Pet' where id = %L$sql$, :'s_pap'),
    'commercial_segment_immutable');
select tests.check_raises('segmento nao pode ser excluido',
    format($sql$delete from public.commercial_segments where id = %L$sql$, :'s_pap'),
    'commercial_segment_immutable');

-- ---------------------------------------------------------------------------
-- 13. Fidelidade segue a identidade comercial, não a posição (D4)
-- ---------------------------------------------------------------------------
select tests.check('unicidade antiga por posicao foi substituida pela identidade',
    not exists (select 1 from pg_constraint where conname = 'cfr_unico')
    and exists (select 1 from pg_indexes where indexname = 'cfr_identidade_unica'));
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code)
values ('27010008000195', 'ES', public.commercial_city_key('Viana'), 'pharmacy');
select tests.check('registro sem pedido de segmento tem identidade = posicao',
    (select fidelity_identity = 'pharmacy' from public.commercial_fidelity_records
      where cnpj = '27010008000195'));
select tests.check('fidelidade de Farmacia NAO vale para segmento na posicao Farmacia',
    public.is_fidelized_context('27010008000195','ES','Viana','pharmacy')
    and not public.is_fidelized_context('27010008000195','ES','Viana','pharmacy', (:'s_pap')::uuid));

-- Pedido real de segmento falha no instrumento (D9). Para provar a derivação
-- da identidade, os DOIS gatilhos de instrumento são desligados somente
-- dentro desta transação, que é descartada (rollback).
begin;
insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
values ((:'reg270')::uuid, 2701, 'forming', false) returning id as excl2701 \gset
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl2701')::uuid, 'supermarket', 24, 'available'),
       ((:'excl2701')::uuid, 'others', 12, 'available'),
       ((:'excl2701')::uuid, 'footwear', 12, 'available');
select id as o2701s from public.commercial_opportunities where exclusivity_id = :'excl2701' and niche_code = 'supermarket' \gset
select id as o2701o from public.commercial_opportunities where exclusivity_id = :'excl2701' and niche_code = 'others' \gset
select id as o2701f from public.commercial_opportunities where exclusivity_id = :'excl2701' and niche_code = 'footwear' \gset
alter table public.commercial_exclusivity_orders disable trigger ceo_exigir_instrumento;
alter table public.commercial_exclusivity_orders disable trigger ceo_emitir_instrumento;
select tests.preparar_contexto_contratual_v14_qa('270');
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_register_manual_commercial_order(
  (:'o2701s')::uuid,
  (:'c1')::uuid, 'v1', now() - interval '1 day', 'Titular 270-1',
  (now() + interval '30 days')::date, 'direct_benefits', 'doc://270-sup') as r_man_sup \gset
select public.admin_register_manual_commercial_order(
  (:'o2701o')::uuid,
  (:'c8')::uuid, 'v1', now() - interval '1 day', 'Titular 270-8',
  (now() + interval '30 days')::date, 'direct_benefits', 'doc://270-out',
  p_segment_id => (:'s_pap')::uuid) as r_man_seg \gset
-- O segmento já está num PEDIDO desta exclusividade: outra posição não o recebe.
select public.admin_register_manual_commercial_order(
  (:'o2701f')::uuid,
  (:'c6')::uuid, 'v1', now() - interval '1 day', 'Titular 270-6',
  (now() + interval '30 days')::date, 'direct_benefits', 'doc://270-fw-dup',
  p_segment_id => (:'s_pap')::uuid) as r_man_dup \gset
select public.admin_register_manual_commercial_order(
  (:'o2701f')::uuid,
  (:'c6')::uuid, 'v1', now() - interval '1 day', 'Titular 270-6',
  (now() + interval '30 days')::date, 'direct_benefits', 'doc://270-fw') as r_man_fw \gset
reset role;
select tests.check('segmento ja contratado em pedido nao ocupa outra posicao',
    (:'r_man_dup')::jsonb ->> 'reason' = 'segment_already_in_exclusivity');
select tests.check('Calcados unificado (sem segmento) e vendavel',
    (:'r_man_fw')::jsonb ->> 'ok' = 'true');
select tests.check('provisionamento ao App recusa formacao com posicoes novas (D8)',
    public.build_app_provisioning_payload((:'excl2701')::uuid, 'local')->>'reason'
      = 'app_contract_v3_required');
select tests.check('venda manual sem segmento continua funcionando',
    (:'r_man_sup')::jsonb ->> 'ok' = 'true');
select tests.check('venda manual de Outros grava o snapshot do segmento',
    (:'r_man_seg')::jsonb ->> 'ok' = 'true'
    and (select segment_code_snapshot = 'papelaria' and niche_code = 'others'
           from public.commercial_exclusivity_orders
          where id = ((:'r_man_seg')::jsonb ->> 'order_id')::uuid));
select tests.check('fidelidade do pedido de posicao: identidade = supermarket',
    exists (select 1 from public.commercial_fidelity_records
             where cnpj = '27010001000173' and fidelity_identity = 'supermarket'));
select tests.check('fidelidade do pedido de segmento: identidade = segment:papelaria',
    exists (select 1 from public.commercial_fidelity_records
             where cnpj = '27010008000195' and fidelity_identity = 'segment:papelaria'));
select tests.check('fidelidade de segmento vale em qualquer posicao elegivel, nunca como nicho',
    public.is_fidelized_context('27010008000195','ES','Viana','pharmacy', (:'s_pap')::uuid)
    and public.is_fidelized_context('27010008000195','ES','Viana','footwear', (:'s_pap')::uuid)
    and not public.is_fidelized_context('27010008000195','ES','Viana','others', (:'s_mat')::uuid));
-- Vitrine pública: pedido ASSINADO com pagamento PENDENTE ainda não divulga
-- o segmento; depois da confirmação do pagamento, divulga só código e nome.
update public.commercial_exclusivities set is_current = false where id = :'excl270';
update public.commercial_exclusivities set is_current = true where id = :'excl2701';
select public.get_current_commercial_formation('ES','Viana') as f_pend \gset
select tests.check('vitrine: pedido assinado com pagamento pendente nao divulga o segmento',
    (select o->'segment' = 'null'::jsonb and o->>'status' <> 'contracted'
       from jsonb_array_elements((:'f_pend')::jsonb -> 'opportunities') o
      where o->>'niche_code' = 'others'));
select ((:'r_man_seg')::jsonb ->> 'order_id') as ord_seg \gset
select case when pricing_rule_version >= 3 then smallflags_total_remuneration_cents
            else bdflow_due_cents end as due_seg
  from public.commercial_exclusivity_orders where id = :'ord_seg' \gset
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_confirm_manual_bdflow_payment((:'ord_seg')::uuid, (:'due_seg')::bigint,
  'ref-270-seg', 'teste 270: confirmacao de pagamento') as r_conf \gset
reset role;
select public.get_current_commercial_formation('ES','Viana') as f_conf \gset
select tests.check('pagamento do pedido de segmento confirmado',
    (:'r_conf')::jsonb ->> 'ok' = 'true');
select tests.check('vitrine: venda confirmada divulga somente codigo e nome do segmento',
    (select o->'segment' = '{"code": "papelaria", "name": "Papelaria"}'::jsonb
            and o->>'status' = 'contracted'
       from jsonb_array_elements((:'f_conf')::jsonb -> 'opportunities') o
      where o->>'niche_code' = 'others'));
select tests.check('vitrine: nenhum dado empresarial ou financeiro do pedido',
    position('27010008000195' in (:'f_conf')::text) = 0
    and position((:'c8')::text in (:'f_conf')::text) = 0
    and position(:'ord_seg' in (:'f_conf')::text) = 0
    and position('Titular 270-8' in (:'f_conf')::text) = 0);
select tests.check_raises('identidade de fidelidade e imutavel',
    $sql$update public.commercial_fidelity_records set fidelity_identity = 'pharmacy'
         where cnpj = '27010008000195' and fidelity_identity = 'segment:papelaria'$sql$,
    'commercial_fidelity_identity_immutable');
rollback;

-- ---------------------------------------------------------------------------
-- 14. Com os gatilhos de instrumento LIGADOS, pedido de segmento não nasce
--     (D9), e o provisionamento ao App falha fechado (D8)
-- ---------------------------------------------------------------------------
begin;
insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
values ((:'reg270')::uuid, 2702, 'forming', false) returning id as excl2702 \gset
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl2702')::uuid, 'others', 12, 'available');
select id as o2702o from public.commercial_opportunities where exclusivity_id = :'excl2702' and niche_code = 'others' \gset
select tests.preparar_contexto_contratual_v14_qa('270b');
select tests.impersonate('authenticated', :'uid_adm');
select tests.check_raises('venda manual de segmento nao vira pedido assinado (D9)',
    format($sql$select public.admin_register_manual_commercial_order(
      %L::uuid,
      %L::uuid, 'v1', now() - interval '1 day', 'Titular 270-8',
      (now() + interval '30 days')::date, 'direct_benefits', 'doc://270',
      p_segment_id => %L::uuid)$sql$, :'o2702o', :'c8', :'s_pap'),
    'commercial_instrument_segment_activity_unavailable');
reset role;
rollback;

select tests.check('instrumento recusa segmento ate a revisao juridica',
    (select prosrc like '%commercial_instrument_segment_activity_unavailable%'
       from pg_proc where proname = 'commercial_build_instrument_snapshot'));
select tests.check('provisionamento exige contrato v3 para posicoes novas',
    (select prosrc like '%app_contract_v3_required%'
       from pg_proc where proname = 'build_app_provisioning_payload'));

-- ---------------------------------------------------------------------------
-- 15. Pré-compra e fila preservam o segmento (D7)
-- ---------------------------------------------------------------------------
select id as s_otica from public.commercial_segments where code = 'otica' \gset
begin;
select tests.impersonate('authenticated', :'u7');
select public.join_my_commercial_future_queue((:'c7')::uuid, 'others') as r_q_sem \gset
select public.join_my_commercial_future_queue((:'c7')::uuid, 'pharmacy', (:'s_otica')::uuid) as r_q \gset
commit;
select tests.check('fila de Outros sem segmento e recusada',
    (:'r_q_sem')::jsonb ->> 'reason' = 'segment_required');
select tests.check('pre-compra registrada com o segmento escolhido',
    (:'r_q')::jsonb ->> 'mode' = 'preorder'
    and exists (select 1 from public.commercial_preorders
                 where company_id = :'c7' and niche_code = 'pharmacy'
                   and segment_code_snapshot = 'otica'));
select tests.check('pre-compra nao cria reserva nem pedido',
    not exists (select 1 from public.commercial_checkout_intents where company_id = :'c7')
    and not exists (select 1 from public.commercial_exclusivity_orders where company_id = :'c7'));

select tests.finish('270_commercial_positions_segments');
