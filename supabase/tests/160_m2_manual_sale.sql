-- ============================================================================
-- SUITE 160 — Venda manual e pagamento devido (R8)
-- Constrói a formação REAL de seis nichos numa exclusividade própria,
-- usada pelo gate do R9.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset

-- Exclusividade dedicada a esta suíte.
insert into public.commercial_exclusivities
    (id, region_id, sequence_number, status, is_current, planned_start_at)
values (gen_random_uuid(),
        (select id from public.commercial_regions where uf='ES' limit 1),
        2, 'forming', false, now() + interval '30 days')
returning id as excl2 \gset

insert into public.commercial_opportunities
    (exclusivity_id, niche_code, contracted_quantity, status)
select :'excl2', n.code, n.contracted_quantity, 'available'
  from public.commercial_niches n where n.is_active;

-- Seis empresas parceiras completas, pelo fluxo canônico do M1.
do $$
declare
  v_admin uuid;
  -- CNPJs válidos e INÉDITOS: reutilizar os das suítes anteriores criaria
  -- duas candidaturas com o mesmo CNPJ e tornaria a seleção ambígua.
  v_cnpjs text[] := array['70000000000177','70000137000121','70000274000166',
                          '70000411000162','70000548000117','70000685000151'];
  v_cpfs  text[] := array['52998224725','11144477735','12345678909',
                          '98765432100','15350946056','04303152013'];
  v_i int; v_uid uuid; v_app uuid; v_company uuid; v_email text; v_tok text;
begin
  select user_id into v_admin from public.site_admins limit 1;

  for v_i in 1..6 loop
    v_email := 'r8parceiro' || v_i || '@teste.local';
    v_uid := gen_random_uuid();
    insert into auth.users (id, email) values (v_uid, v_email);

    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform public.create_partner_application(jsonb_build_object(
      'cnpj', v_cnpjs[v_i],
      'legal_name', 'R8 Parceiro ' || v_i || ' LTDA',
      'trade_name', 'R8 Parceiro ' || v_i,
      'contact_email', v_email,
      'city', 'Vitória', 'uf', 'ES',
      'representative_full_name', 'Responsavel R8 ' || v_i,
      'representative_cpf', v_cpfs[v_i],
      'representative_email', 'rep' || v_i || '@teste.local',
      'acceptances', (select jsonb_agg(jsonb_build_object(
                          'legal_document_id', x ->> 'legal_document_id'))
                        from jsonb_array_elements(
                               public.get_partner_application_terms() -> 'documents') x)));

    select id into v_app from public.partner_applications
     where cnpj = v_cnpjs[v_i] order by created_at desc limit 1;
    if v_app is null then
      raise exception 'fixture R8: candidatura nao criada para %', v_cnpjs[v_i];
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

    -- Unidade ativa (pré-requisito do gate) criada pelo owner real.
    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_uid)::text, true);
    perform public.owner_create_unit(v_company,'Matriz','Vitória','ES');

    -- Acordo mestre assinado.
    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_admin)::text, true);
    perform public.admin_register_master_agreement(
        v_company,'v1', now() - interval '1 day',
        'Responsavel R8 ' || v_i, 'doc://acordo-r8-' || v_i);
  end loop;
  perform set_config('request.jwt.claims', null, true);
end $$;

select tests.check('seis empresas parceiras promovidas com unidade e acordo',
    (select count(*) from public.site_partner_companies c
      where exists (select 1 from public.site_partner_units u
                     where u.company_id = c.id and u.status='active')
        and exists (select 1 from public.commercial_master_agreements a
                     where a.company_id = c.id and a.status='signed')) >= 6);

-- ---------------------------------------------------------------------------
-- Autorização e validações da venda manual
-- ---------------------------------------------------------------------------
select id as opp_super from public.commercial_opportunities
 where exclusivity_id = :'excl2' and niche_code='supermarket' \gset
select c.id as comp1 from public.site_partner_companies c
 where c.cnpj = '70000000000177' \gset

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check_raises('nao-admin nao registra venda manual',
  format($sql$select public.admin_register_manual_commercial_order(
    %L,%L,'v1',now() - interval '1 day','Resp',(now()+interval '30 days')::date,'doc://x')$sql$,
    :'opp_super', :'comp1'),
  'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp_super')::uuid,(:'comp1')::uuid,'v1', now() + interval '1 day','Resp',
  (now()+interval '30 days')::date,'doc://x') as v_fut \gset
select tests.check('assinatura no futuro e recusada',
    ((:'v_fut')::jsonb ->> 'reason') = 'invalid_signature_date');
select public.admin_register_manual_commercial_order(
  (:'opp_super')::uuid,(:'comp1')::uuid,'v1', now() - interval '1 day','Resp',
  (now()+interval '30 days')::date) as v_sem_doc \gset
select tests.check('venda sem evidencia documental e recusada',
    ((:'v_sem_doc')::jsonb ->> 'reason') = 'document_evidence_required');

select public.admin_register_manual_commercial_order(
  (:'opp_super')::uuid,(:'comp1')::uuid,'v1', now() - interval '1 day',
  'Responsavel R8 1',(now()+interval '30 days')::date,'doc://pedido-super') as ord_s \gset
select tests.check('venda manual do supermercado registrada',
    ((:'ord_s')::jsonb ->> 'ok') = 'true');
-- PREÇO DO SERVIDOR: o chamador não enviou valor algum.
select tests.check('snapshot economico calculado no servidor (24 unidades)',
    ((:'ord_s')::jsonb ->> 'economic_value_cents')::bigint = 3558700
    and ((:'ord_s')::jsonb ->> 'contractual_pool_cents')::bigint = 2669025
    and ((:'ord_s')::jsonb ->> 'bdflow_due_cents')::bigint = 889675);
select tests.check('primeiro contrato do contexto e fundador',
    ((:'ord_s')::jsonb ->> 'fidelized') = 'false');

select public.admin_register_manual_commercial_order(
  (:'opp_super')::uuid,(:'comp1')::uuid,'v1', now() - interval '1 day',
  'Responsavel R8 1',(now()+interval '30 days')::date,'doc://pedido-super') as ord_s2 \gset
select tests.check('venda repetida da mesma oportunidade e idempotente',
    ((:'ord_s2')::jsonb ->> 'already') = 'true');
commit;

select ((:'ord_s')::jsonb ->> 'order_id') as order_super \gset

select tests.check('oportunidade vendida fica payment_pending',
    (select status from public.commercial_opportunities where id = :'opp_super')
      = 'payment_pending');
select tests.check('pedido nasce assinado e registra fidelidade futura',
    (select status='signed' from public.commercial_exclusivity_orders where id = :'order_super')
    and (select count(*) from public.commercial_fidelity_records
          where cnpj='70000000000177' and niche_code='supermarket') = 1);

-- Mesmo CNPJ não ocupa segundo nicho na mesma exclusividade.
select id as opp_pharm2 from public.commercial_opportunities
 where exclusivity_id = :'excl2' and niche_code='pharmacy' \gset
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp_pharm2')::uuid,(:'comp1')::uuid,'v1', now() - interval '1 day','Resp',
  (now()+interval '30 days')::date,'doc://y') as v_dup \gset
select tests.check('mesmo CNPJ nao ocupa segundo nicho na exclusividade',
    ((:'v_dup')::jsonb ->> 'reason') = 'company_already_in_exclusivity');
rollback;

-- Empresa sem acordo mestre não compra.
select tests.mk_user('sem_acordo') as uid_sa \gset
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp_pharm2')::uuid, gen_random_uuid(),'v1', now() - interval '1 day','Resp',
  (now()+interval '30 days')::date,'doc://z') as v_sememp \gset
select tests.check('empresa inexistente e recusada',
    ((:'v_sememp')::jsonb ->> 'reason') = 'company_invalid');
rollback;

-- ---------------------------------------------------------------------------
-- Pagamento: "pago" é o valor DEVIDO À BDFLOW
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_confirm_manual_bdflow_payment((:'order_super')::uuid, 999) as pg_err \gset
select tests.check('valor diferente do devido e recusado',
    ((:'pg_err')::jsonb ->> 'reason') = 'amount_differs_from_due'
    and ((:'pg_err')::jsonb ->> 'expected_cents')::bigint = 889675);
-- O valor ECONÔMICO integral NÃO é o que a BDFlow recebe.
select public.admin_confirm_manual_bdflow_payment((:'order_super')::uuid, 3558700) as pg_eco \gset
select tests.check('confirmar o valor economico integral e recusado',
    ((:'pg_eco')::jsonb ->> 'reason') = 'amount_differs_from_due');
-- Tampouco o pool contratual.
select public.admin_confirm_manual_bdflow_payment((:'order_super')::uuid, 2669025) as pg_pool \gset
select tests.check('confirmar o pool contratual e recusado (BDFlow nao custodia)',
    ((:'pg_pool')::jsonb ->> 'reason') = 'amount_differs_from_due');

select public.admin_confirm_manual_bdflow_payment(
    (:'order_super')::uuid, 889675, 'pix-r8-001') as pg_ok \gset
select tests.check('pagamento do valor devido confirmado',
    ((:'pg_ok')::jsonb ->> 'ok') = 'true');
select public.admin_confirm_manual_bdflow_payment((:'order_super')::uuid, 889675) as pg_idem \gset
select tests.check('confirmacao repetida e idempotente',
    ((:'pg_idem')::jsonb ->> 'already') = 'true');
commit;

select tests.check('oportunidade paga fica contracted',
    (select status from public.commercial_opportunities where id = :'opp_super') = 'contracted');
select tests.check_raises('confirmacao de pagamento e imutavel',
  format($sql$update public.commercial_exclusivity_orders
           set payment_amount_cents = 1 where id = %L$sql$, :'order_super'),
  'pedido_imutavel');

-- ---------------------------------------------------------------------------
-- Vende os cinco nichos restantes e completa a formação
-- ---------------------------------------------------------------------------
do $$
declare
  v_admin uuid; v_excl uuid; v_i int;
  v_niches text[] := array['pharmacy','womens_clothing','mens_clothing',
                           'womens_footwear','mens_footwear'];
  v_cnpjs  text[] := array['70000137000121','70000274000166','70000411000162',
                           '70000548000117','70000685000151'];
  v_opp uuid; v_comp uuid; v_ord jsonb;
begin
  select user_id into v_admin from public.site_admins limit 1;
  select id into v_excl from public.commercial_exclusivities where sequence_number = 2;
  perform set_config('request.jwt.claims',
      json_build_object('role','authenticated','sub',v_admin)::text, true);

  for v_i in 1..5 loop
    select id into v_opp from public.commercial_opportunities
     where exclusivity_id = v_excl and niche_code = v_niches[v_i];
    select id into v_comp from public.site_partner_companies where cnpj = v_cnpjs[v_i];
    v_ord := public.admin_register_manual_commercial_order(
        v_opp, v_comp, 'v1', now() - interval '1 day',
        'Responsavel R8', (now() + interval '30 days')::date,
        'doc://pedido-' || v_niches[v_i]);
    perform public.admin_confirm_manual_bdflow_payment(
        (v_ord->>'order_id')::uuid, (v_ord->>'bdflow_due_cents')::bigint, 'pix-lote');
  end loop;
  perform set_config('request.jwt.claims', null, true);
end $$;

select tests.check('seis pedidos ativos formam a exclusividade',
    (select count(*) from public.commercial_exclusivity_orders
      where exclusivity_id = :'excl2' and status = 'signed') = 6);
select tests.check('seis CNPJs distintos ocupam os seis nichos',
    (select count(distinct company_id) from public.commercial_exclusivity_orders
      where exclusivity_id = :'excl2' and status = 'signed') = 6);
select tests.check('soma economica da formacao = R$ 135.582,00',
    (select sum(economic_value_cents) from public.commercial_exclusivity_orders
      where exclusivity_id = :'excl2' and status='signed') = 13558200);
select tests.check('soma dos pools contratuais = R$ 96.686,75',
    (select sum(contractual_pool_cents) from public.commercial_exclusivity_orders
      where exclusivity_id = :'excl2' and status='signed') = 9668675);
select tests.check('soma do devido a BDFlow = R$ 38.895,25',
    (select sum(bdflow_due_cents) from public.commercial_exclusivity_orders
      where exclusivity_id = :'excl2' and status='signed') = 3889525);
select tests.check('todos os seis pagamentos confirmados',
    (select count(*) from public.commercial_exclusivity_orders
      where exclusivity_id = :'excl2' and payment_status='confirmed') = 6);
select tests.check('invariante economico = pool + devido em todos os pedidos',
    (select count(*) from public.commercial_exclusivity_orders
      where economic_value_cents <> contractual_pool_cents + bdflow_due_cents) = 0);

select tests.finish('160_m2_manual_sale');
