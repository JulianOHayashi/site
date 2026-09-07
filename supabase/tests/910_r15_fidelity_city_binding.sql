-- ============================================================================
-- SUITE 910 — R15: vínculo geográfico da fidelidade e ciclo de vida do fundador
--
-- O defeito corrigido pelo R15 passava por TODAS as suítes anteriores porque
-- nenhuma delas olhava a city_key gravada. Esta suíte olha.
--
-- STATUS: TESTE_AUXILIAR_NAO_GATE (PG16). O gate final é Supabase PG17 real.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset

-- ---------------------------------------------------------------------------
-- Fixture: exclusividade própria + empresas em CIDADES DIFERENTES da mesma
-- região comercial, além de uma fora da região e uma sem cidade.
-- ---------------------------------------------------------------------------
insert into public.commercial_exclusivities
    (id, region_id, sequence_number, status, is_current, planned_start_at)
values (gen_random_uuid(),
        (select id from public.commercial_regions where uf='ES' limit 1),
        15, 'forming', false, now() + interval '60 days')
returning id as excl15 \gset

insert into public.commercial_opportunities
    (exclusivity_id, niche_code, contracted_quantity, status)
select :'excl15', n.code, n.contracted_quantity, 'available'
  from public.commercial_niches n where n.is_active;

-- Segunda exclusividade: prova que a fidelidade vale para pedidos FUTUROS.
insert into public.commercial_exclusivities
    (id, region_id, sequence_number, status, is_current, planned_start_at)
values (gen_random_uuid(),
        (select id from public.commercial_regions where uf='ES' limit 1),
        16, 'forming', false, now() + interval '90 days')
returning id as excl16 \gset

insert into public.commercial_opportunities
    (exclusivity_id, niche_code, contracted_quantity, status)
select :'excl16', n.code, n.contracted_quantity, 'available'
  from public.commercial_niches n where n.is_active;

do $$
declare
  v_admin uuid;
  -- CNPJs válidos e inéditos (dígito verificador real).
  v_cnpjs  text[] := array['71000000000130','71000137000194','71000274000129',
                           '71000411000125','71000548000180'];
  -- Cidades AUTORITATIVAS distintas. 'VITÓRIA' em caixa alta e com acento
  -- exercita a normalização; 'Guarapari' é ES válido mas FORA da região.
  v_cities text[] := array['Vitória','Serra','Guarapari','Vitória','VITÓRIA'];
  v_cpfs   text[] := array['52998224725','11144477735','12345678909',
                           '98765432100','15350946056'];
  v_i int; v_uid uuid; v_app uuid; v_company uuid; v_email text; v_tok text;
begin
  select user_id into v_admin from public.site_admins limit 1;

  for v_i in 1..5 loop
    v_email := 'r15parceiro' || v_i || '@teste.local';
    v_uid := gen_random_uuid();
    insert into auth.users (id, email) values (v_uid, v_email);

    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform public.create_partner_application(jsonb_build_object(
      'cnpj', v_cnpjs[v_i],
      'legal_name', 'R15 Parceiro ' || v_i || ' LTDA',
      'trade_name', 'R15 Parceiro ' || v_i,
      'contact_email', v_email,
      'city', v_cities[v_i], 'uf', 'ES',
      'representative_full_name', 'Responsavel R15 ' || v_i,
      'representative_cpf', v_cpfs[v_i],
      'representative_email', 'repr15' || v_i || '@teste.local',
      'acceptances', (select jsonb_agg(jsonb_build_object(
                          'legal_document_id', x ->> 'legal_document_id'))
                        from jsonb_array_elements(
                               public.get_partner_application_terms() -> 'documents') x)));

    select id into v_app from public.partner_applications
     where cnpj = v_cnpjs[v_i] order by created_at desc limit 1;
    if v_app is null then
      raise exception 'fixture R15: candidatura nao criada para %', v_cnpjs[v_i];
    end if;

    v_tok := public.m1_emitir_token(v_app,'email_verification',v_email,interval '24 hours');
    perform public.confirm_partner_application_email(v_tok);
    v_tok := public.m1_emitir_token(v_app,'account_claim',v_email,interval '24 hours');

    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_uid)::text, true);
    perform public.record_bound_legal_acceptance(
        x ->> 'doc_type', (x ->> 'legal_document_id')::uuid, '{}'::jsonb)
      from jsonb_array_elements(public.get_provisional_account_terms() -> 'documents') x;
    perform public.claim_partner_application_account(v_tok);

    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_admin)::text, true);
    perform public.admin_review_partner_company(v_app,'approved',null);
    perform public.admin_review_partner_authority(v_app,'approved',null);
    perform public.admin_decide_partner_application(v_app,'approved',null);
    v_company := (public.admin_promote_partner_application(v_app) ->> 'company_id')::uuid;

    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_uid)::text, true);
    perform public.owner_create_unit(v_company,'Matriz',v_cities[v_i],'ES');

    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_admin)::text, true);
    perform public.admin_register_master_agreement(
        v_company,'v1', now() - interval '1 day',
        'Responsavel R15 ' || v_i, 'doc://acordo-r15-' || v_i);
  end loop;
  perform set_config('request.jwt.claims', null, true);
end $$;

select c.id as comp_vit  from public.site_partner_companies c where c.cnpj='71000000000130' \gset
select c.id as comp_ser  from public.site_partner_companies c where c.cnpj='71000137000194' \gset
select c.id as comp_gua  from public.site_partner_companies c where c.cnpj='71000274000129' \gset
select c.id as comp_fmt  from public.site_partner_companies c where c.cnpj='71000411000125' \gset
select c.id as comp_up   from public.site_partner_companies c where c.cnpj='71000548000180' \gset
select r.id as reg_es    from public.commercial_regions r where r.uf='ES' limit 1 \gset

select tests.check('fixture: cidades autoritativas distintas foram preservadas',
    (select city from public.site_partner_companies where id=:'comp_vit') = 'Vitória'
    and (select city from public.site_partner_companies where id=:'comp_ser') = 'Serra'
    and (select city from public.site_partner_companies where id=:'comp_gua') = 'Guarapari');

-- ---------------------------------------------------------------------------
-- CONTROLE POSITIVO DO CRITÉRIO: a região TEM mais de uma cidade ativa e a
-- primeira por city_name NÃO é Vitória. Sem isso, os casos A e B poderiam
-- passar por coincidência.
-- ---------------------------------------------------------------------------
select tests.check('regiao tem varias cidades ativas e a primeira nao e Vitoria',
    (select count(*) from public.commercial_region_cities
      where region_id=:'reg_es' and is_active) > 1
    and (select city_key from public.commercial_region_cities
          where region_id=:'reg_es' and is_active
          order by city_name limit 1) <> 'vitoria');

-- ---------------------------------------------------------------------------
-- CASO A — empresa em Vitória: a fidelidade nasce em Vitória
-- ---------------------------------------------------------------------------
select id as opp15_super from public.commercial_opportunities
 where exclusivity_id=:'excl15' and niche_code='supermarket' \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp15_super')::uuid,(:'comp_vit')::uuid,'v1', now() - interval '1 day',
  'Responsavel R15 1',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-super') as ord_a \gset
commit;

select tests.check('CASO A: venda registrada',
    ((:'ord_a')::jsonb ->> 'ok') = 'true');
-- O retorno da RPC sob a V2 nao expoe mais 'city_key' (ver relatorio CP2.2,
-- achado F-01). A prova de vinculo passa a sair da evidencia PERSISTIDA, que
-- e mais forte que o campo de retorno: e ela que governa fidelidade futura.
select tests.check('CASO A: chave de cidade gravada e a cidade REAL da empresa',
    (select f.city_key from public.commercial_fidelity_records f
      where f.established_by_order_id = ((:'ord_a')::jsonb ->> 'order_id')::uuid)
    = 'vitoria');
select tests.check('CASO A: fidelidade gravada em vitoria, jamais na primeira da regiao',
    (select count(*) from public.commercial_fidelity_records
      where cnpj='71000000000130' and niche_code='supermarket'
        and city_key='vitoria') = 1
    and (select count(*) from public.commercial_fidelity_records
          where cnpj='71000000000130'
            and city_key in ('cariacica','serra','viana','vila-velha')) = 0);
select tests.check('CASO A: leitura do dominio reconhece a cidade real',
    public.is_fidelized_context('71000000000130','ES','Vitória','supermarket') = true);
select tests.check('CASO A: fidelidade NAO vaza para outra cidade da regiao',
    public.is_fidelized_context('71000000000130','ES','Cariacica','supermarket') = false
    and public.is_fidelized_context('71000000000130','ES','Serra','supermarket') = false);

-- ---------------------------------------------------------------------------
-- CASO B — segunda empresa, MESMA região, cidade diferente
-- ---------------------------------------------------------------------------
select id as opp15_pharm from public.commercial_opportunities
 where exclusivity_id=:'excl15' and niche_code='pharmacy' \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp15_pharm')::uuid,(:'comp_ser')::uuid,'v1', now() - interval '1 day',
  'Responsavel R15 2',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-pharm') as ord_b \gset
commit;

select tests.check('CASO B: empresa de Serra fideliza em serra',
    (select f.city_key from public.commercial_fidelity_records f
      where f.established_by_order_id = ((:'ord_b')::jsonb ->> 'order_id')::uuid)
    = 'serra'
    and (select count(*) from public.commercial_fidelity_records
          where cnpj='71000137000194' and city_key='serra') = 1);
select tests.check('CASO B: a regiao NAO colapsa as duas empresas na mesma cidade',
    (select city_key from public.commercial_fidelity_records
      where cnpj='71000000000130' and niche_code='supermarket')
    <> (select city_key from public.commercial_fidelity_records
         where cnpj='71000137000194' and niche_code='pharmacy'));

-- ---------------------------------------------------------------------------
-- CASO C — cidade fora da região comercial: FALHA FECHADA
-- ---------------------------------------------------------------------------
select id as opp15_wc from public.commercial_opportunities
 where exclusivity_id=:'excl15' and niche_code='womens_clothing' \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp15_wc')::uuid,(:'comp_gua')::uuid,'v1', now() - interval '1 day',
  'Responsavel R15 3',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-gua') as ord_c \gset
select tests.check('CASO C: cidade fora da regiao e recusada',
    ((:'ord_c')::jsonb ->> 'ok') = 'false'
    and ((:'ord_c')::jsonb ->> 'reason') = 'city_not_in_region');
select tests.check('CASO C: nenhuma fidelidade criada sob cidade arbitraria',
    (select count(*) from public.commercial_fidelity_records
      where cnpj='71000274000129') = 0);
select tests.check('CASO C: nenhum pedido criado',
    (select count(*) from public.commercial_exclusivity_orders
      where company_id=:'comp_gua') = 0);
rollback;

-- ---------------------------------------------------------------------------
-- CASO D — cidade ausente/irresolvível: FALHA FECHADA
-- ---------------------------------------------------------------------------
begin;
update public.site_partner_companies set city = '   ' where id = :'comp_gua';
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp15_wc')::uuid,(:'comp_gua')::uuid,'v1', now() - interval '1 day',
  'Responsavel R15 3',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-vazio') as ord_d \gset
select tests.check('CASO D: cidade em branco e recusada como ausente',
    ((:'ord_d')::jsonb ->> 'reason') = 'company_city_missing');
select tests.check('CASO D: nenhuma fidelidade criada',
    (select count(*) from public.commercial_fidelity_records
      where cnpj='71000274000129') = 0);
rollback;

begin;
update public.site_partner_companies
   set city = 'Cidade Que Nao Existe' where id = :'comp_gua';
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp15_wc')::uuid,(:'comp_gua')::uuid,'v1', now() - interval '1 day',
  'Responsavel R15 3',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-inex') as ord_d2 \gset
select tests.check('CASO D: cidade inexistente na regiao e recusada',
    ((:'ord_d2')::jsonb ->> 'reason') = 'city_not_in_region');
rollback;

-- ---------------------------------------------------------------------------
-- CASO E — normalização: acento e caixa não mudam a chave
-- ---------------------------------------------------------------------------
select tests.check('CASO E: VITÓRIA em caixa alta resolve para vitoria',
    (public.m2_resolve_company_fidelity_city(:'comp_up', :'reg_es') ->> 'city_key')
      = 'vitoria');

begin;
update public.site_partner_companies set city = 'vitoria' where id = :'comp_up';
select tests.check('CASO E: vitoria sem acento resolve para a mesma chave',
    (public.m2_resolve_company_fidelity_city(:'comp_up', :'reg_es') ->> 'city_key')
      = 'vitoria');
update public.site_partner_companies set city = '  Vila   Velha  ' where id = :'comp_up';
select tests.check('CASO E: espacos extras normalizam para vila-velha',
    (public.m2_resolve_company_fidelity_city(:'comp_up', :'reg_es') ->> 'city_key')
      = 'vila-velha');
rollback;

-- ---------------------------------------------------------------------------
-- CASO F — ambiguidade de cidade
--
-- A guarda 'city_ambiguous' do resolvedor é DEFESA EM PROFUNDIDADE: a
-- baseline canônica já impede a duplicidade por índice único (uf, city_key).
-- Testar o ramo exigiria violar essa restrição, então o que se prova aqui é
-- a restrição que o torna inalcançável — e não um cenário fabricado.
-- ---------------------------------------------------------------------------
select tests.check('CASO F: chave de cidade e unica por UF na baseline canonica',
    (select count(*) from pg_constraint
      where conrelid = 'public.commercial_region_cities'::regclass
        and contype = 'u'
        and pg_get_constraintdef(oid) = 'UNIQUE (uf, city_key)') = 1);

select tests.check_raises(
  'CASO F: duplicar (uf, city_key) e recusado pelo banco',
  format($sql$insert into public.commercial_region_cities
              (region_id, uf, city_name, city_key, is_active)
              values (%L,'ES','Vitoria Duplicada','vitoria', true)$sql$, :'reg_es'),
  'commercial_region_cities_key_unique_per_uf');

-- ---------------------------------------------------------------------------
-- Escrita e leitura usam a MESMA chave (não podem divergir de novo)
-- ---------------------------------------------------------------------------
select tests.check('escrita e leitura concordam na chave de cidade',
    (select city_key from public.commercial_fidelity_records
      where cnpj='71000000000130' and niche_code='supermarket')
    = (public.m2_resolve_company_fidelity_city(:'comp_vit', :'reg_es') ->> 'city_key'));

-- CNPJ é gravado normalizado (a leitura usa somente_digitos).
select id as opp15_mc from public.commercial_opportunities
 where exclusivity_id=:'excl15' and niche_code='mens_clothing' \gset
begin;
update public.site_partner_companies
   set cnpj = '71.000.411/0001-25' where id = :'comp_fmt';
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp15_mc')::uuid,(:'comp_fmt')::uuid,'v1', now() - interval '1 day',
  'Responsavel R15 4',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-fmt') as ord_f \gset
select tests.check('CNPJ formatado na empresa grava fidelidade em digitos',
    ((:'ord_f')::jsonb ->> 'ok') = 'true'
    and (select count(*) from public.commercial_fidelity_records
          where cnpj='71000411000125' and niche_code='mens_clothing') = 1);
select tests.check('CNPJ formatado continua legivel pela funcao de leitura',
    public.is_fidelized_context('71.000.411/0001-25','ES','Vitória','mens_clothing') = true);
rollback;

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DO FUNDADOR
-- ---------------------------------------------------------------------------
select ((:'ord_a')::jsonb ->> 'order_id') as order_a \gset

select tests.check('CICLO: o pedido fundador NAO recebe preco fidelizado',
    ((:'ord_a')::jsonb ->> 'fidelized') = 'false'
    and ((:'ord_a')::jsonb ->> 'economic_value_cents')::bigint = 3558700);
select tests.check('CICLO: pedido nasce signed e oportunidade fica payment_pending',
    (select status from public.commercial_exclusivity_orders where id=:'order_a') = 'signed'
    and (select payment_status from public.commercial_exclusivity_orders where id=:'order_a') = 'pending'
    and (select status from public.commercial_opportunities where id=:'opp15_super') = 'payment_pending');
select tests.check('CICLO: a fidelidade ja existe no estado signed (ponto de ativacao vigente)',
    (select count(*) from public.commercial_fidelity_records
      where established_by_order_id = (:'order_a')::uuid) = 1);

-- Pedido FUTURO, outra exclusividade, mesmo CNPJ + cidade + nicho: fidelizado.
select id as opp16_super from public.commercial_opportunities
 where exclusivity_id=:'excl16' and niche_code='supermarket' \gset
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp16_super')::uuid,(:'comp_vit')::uuid,'v2', now() - interval '1 day',
  'Responsavel R15 1',(now()+interval '30 days')::date,
  'direct_benefits','doc://r15-super-2') as ord_next \gset
select tests.check('CICLO: pedido futuro do mesmo contexto sai FIDELIZADO',
    ((:'ord_next')::jsonb ->> 'fidelized') = 'true'
    and ((:'ord_next')::jsonb ->> 'economic_value_cents')::bigint = 3117600);
rollback;

-- Confirmação do pagamento não altera a chave de fidelidade.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_confirm_manual_bdflow_payment(
  (:'order_a')::uuid,
  (select bdflow_due_cents from public.commercial_exclusivity_orders where id=:'order_a')
) as pay_a \gset
-- commercial_opportunities nao e legivel pelo papel authenticated comum; a
-- verificacao de estado sai da impersonacao, sem afastar o efeito da RPC.
reset role;
select tests.check('CICLO: pagamento confirmado leva a oportunidade a contracted',
    ((:'pay_a')::jsonb ->> 'ok') = 'true'
    and (select status from public.commercial_opportunities where id=:'opp15_super') = 'contracted');
select tests.check('CICLO: confirmacao de pagamento nao muda a chave de fidelidade',
    (select city_key from public.commercial_fidelity_records
      where established_by_order_id = (:'order_a')::uuid) = 'vitoria');
rollback;

-- ---------------------------------------------------------------------------
-- INVARIANTE: fidelidade não sobrevive ao pedido fundador cancelado
-- ---------------------------------------------------------------------------
begin;
select tests.check('INVARIANTE: antes do cancelamento a fidelidade vale',
    public.is_fidelized_context('71000000000130','ES','Vitória','supermarket') = true);
update public.commercial_exclusivity_orders
   set status = 'cancelled' where id = (:'order_a')::uuid;
select tests.check('INVARIANTE: fundador cancelado deixa de sustentar fidelidade',
    public.is_fidelized_context('71000000000130','ES','Vitória','supermarket') = false);
select tests.check('INVARIANTE: pedido futuro volta a preco NAO fidelizado',
    (public.calculate_niche_contract_pricing('supermarket',
       public.is_fidelized_context('71000000000130','ES','Vitória','supermarket'))
       ->> 'economic_value_cents')::bigint = 3558700);
rollback;

-- O registro de fidelidade aponta para um pedido real (integridade referencial).
select tests.check_raises(
  'fidelidade nao aceita pedido fundador inexistente',
  $sql$insert into public.commercial_fidelity_records
        (cnpj, uf, city_key, niche_code, established_by_order_id)
       values ('71000000000130','ES','viana','pharmacy',
               '00000000-0000-0000-0000-000000000000')$sql$,
  'cfr_pedido_fundador_fk');

-- ---------------------------------------------------------------------------
-- Segurança: o resolvedor é interno, não é superfície pública
-- ---------------------------------------------------------------------------
select tests.check('resolvedor de cidade nao e executavel por anon nem authenticated',
    has_function_privilege('anon','public.m2_resolve_company_fidelity_city(uuid,uuid)','EXECUTE') = false
    and has_function_privilege('authenticated','public.m2_resolve_company_fidelity_city(uuid,uuid)','EXECUTE') = false
    and has_function_privilege('service_role','public.m2_resolve_company_fidelity_city(uuid,uuid)','EXECUTE') = false);

select tests.finish('910_r15_fidelity_city_binding');
