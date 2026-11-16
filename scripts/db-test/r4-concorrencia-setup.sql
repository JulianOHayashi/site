-- Fixtures EFETIVADAS (banco descartável) para o ensaio de concorrência.
\set ON_ERROR_STOP on
begin;
create schema conc;
grant usage on schema conc to authenticated;
select tests.encerrar_contexto_contratual_v14_qa();

select r.id as reg from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

select tests.mk_user('admin296') as uid_adm \gset
insert into public.site_admins (user_id) values ((:'uid_adm')::uuid) on conflict do nothing;

-- Doze empresas em Viana, cada uma com titular.
create table conc.emp296 (n int primary key, cnpj text, comp uuid, uid uuid);
do $$
declare
  v_cnpjs text[] := array['29000001000118','29000002000162','29000003000107','29000004000151',
                          '29000005000104','29000006000140','29000007000195','29000008000130',
                          '29000009000184','29000010000109','29000011000153','29000012000106'];
  v_i int; v_app uuid; v_comp uuid; v_uid uuid;
begin
  for v_i in 1..12 loop
    v_uid := tests.mk_user('titular296.' || v_i);
    insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
    values (v_cnpjs[v_i], 'Empresa 296-' || v_i, 'e296' || v_i || '@teste.local', 'Viana', 'ES')
    returning id into v_app;
    insert into public.partner_application_representatives
      (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
    values (v_app, 'Titular 296-' || v_i, '52998224725', 'rep296' || v_i || '@teste.local',
            'Socio administrador', 'approved', true, now() - interval '2 days');
    insert into public.site_partner_companies
      (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
    values (v_app, v_cnpjs[v_i], 'Empresa 296-' || v_i, 'Loja 296-' || v_i,
            'e296' || v_i || '@teste.local', 'Viana', 'ES', 'active')
    returning id into v_comp;
    insert into public.site_company_members
      (company_id, auth_user_id, role, full_name, cpf, source, status)
    values (v_comp, v_uid, 'partner_owner', 'Titular 296-' || v_i, '52998224725',
            'application_promotion', 'active');
    insert into public.site_partner_units (company_id, name, city, uf, status)
    values (v_comp, 'Unidade 296-' || v_i, 'Viana', 'ES', 'active');
    insert into conc.emp296 values (v_i, v_cnpjs[v_i], v_comp, v_uid);
  end loop;
end $$;

-- As tabelas temporárias da suíte são lidas também sob o papel impersonado.
grant select on conc.emp296 to authenticated;
select tests.impersonate('authenticated', :'uid_adm');
select tests.assinar_mestre_qa(e.comp, 'AM-296-' || e.n) from conc.emp296 e;
select (public.admin_create_commercial_segment('pet_shop_296','Pet shop 296','pet_shop_296')->>'segment_id') as seg \gset
reset role;
select set_config('request.jwt.claims', '', true);

-- Exclusividades E0 (reservas), E1..E4 (cenários) e E5 (instrumento), cada
-- uma com as seis posições.
create table conc.exc296 (k int primary key, id uuid);
select set_config('tests.reg296', :'reg', true);
do $$
declare v_k int; v_id uuid;
begin
  for v_k in 0..5 loop
    insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
    values (current_setting('tests.reg296')::uuid, 2960 + v_k, 'forming', false)
    returning id into v_id;
    insert into conc.exc296 values (v_k, v_id);
  end loop;
end $$;
grant select on conc.exc296 to authenticated;
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select x.id, n.code, n.contracted_quantity, 'available'
  from conc.exc296 x cross join public.commercial_niches n where n.is_active;

create or replace function conc.tornar_corrente(p_k int) returns void language sql as $f$
  update public.commercial_exclusivities set is_current = false
   where region_id = (select region_id from public.commercial_exclusivities
                       where id = (select id from conc.exc296 where k = p_k)) and is_current;
  update public.commercial_exclusivities set is_current = true
   where id = (select id from conc.exc296 where k = p_k);
$f$;

-- Pedido direto (caminho administrativo): os números vêm dos gatilhos.
create or replace function conc.pedido(p_k int, p_n int, p_niche text, p_fid boolean,
                                          p_mode text default 'direct_benefits')
returns uuid language plpgsql as $f$
declare v_id uuid; v_excl uuid := (select id from conc.exc296 where k = p_k);
        v_comp uuid := (select comp from conc.emp296 where n = p_n);
        v_seg public.commercial_segments%rowtype;
begin
  if p_niche = 'others' then
    select * into v_seg from public.commercial_segments where code = 'pet_shop_296';
  end if;
  insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id,
     niche_code, nominal_quantity, fidelized, status, expected_operation_start,
     registered_by, pricing_rule_version, benefit_settlement_mode,
     economic_value_cents, contractual_pool_cents, bdflow_due_cents,
     segment_id, segment_code_snapshot, segment_name_snapshot, segment_classification_snapshot)
  values
    (v_excl,
     (select id from public.commercial_opportunities where exclusivity_id = v_excl and niche_code = p_niche),
     v_comp,
     (select id from public.commercial_master_agreements where company_id = v_comp and status = 'signed'),
     (select region_id from public.commercial_exclusivities where id = v_excl),
     p_niche, (select contracted_quantity from public.commercial_niches where code = p_niche),
     p_fid, 'draft', (now() + interval '30 days')::date,
     (select user_id from public.site_admins limit 1), 4, p_mode,
     -- valores propositalmente errados: a autoridade os substitui
     1, 1, 0,
     v_seg.id, v_seg.code, v_seg.display_name, v_seg.classification_key)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function conc.conjunto(p_order uuid, p_dias int) returns uuid language sql as $f$
  insert into public.commercial_flag_sets
    (origin_order_id, company_id, fidelity_identity, pieces_count, produced_at,
     supplier_name, unit_cost_cents, recorded_by)
  values (p_order, gen_random_uuid(), 'qualquer_coisa', 1, now() - make_interval(days => p_dias),
          '[QA FICTICIO] Fornecedor', 3500, (select user_id from public.site_admins limit 1))
  returning id;
$f$;

create or replace function conc.inspecao(p_set uuid, p_dias int, p_unfit int default 0,
                                            p_cats text[] default '{}')
returns uuid language sql as $f$
  insert into public.commercial_flag_set_inspections
    (flag_set_id, inspected_at, inspector_name, evidence_hash, pieces_inspected,
     pieces_fit, pieces_unfit, unfit_categories, recorded_by)
  values (p_set, now() - make_interval(days => p_dias), '[QA FICTICIO] Conferente',
          encode(extensions.digest('[QA] inspecao ' || p_set || p_dias, 'sha256'), 'hex'),
          84, 84 - p_unfit, p_unfit, p_cats, (select user_id from public.site_admins limit 1))
  returning id;
$f$;


select tests.preparar_ativacao_sf_v15_qa('CONC', 'A');
select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ensaio de concorrencia');
create table conc.estado (k text primary key, v text);
select conc.pedido(1, 3, 'womens_clothing', false) as origem \gset
select conc.conjunto(:'origem', 60) as conjunto \gset
select conc.inspecao(:'conjunto', 10) as inspecao \gset
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code, established_by_order_id)
select e.cnpj, 'ES', 'viana', 'womens_clothing', (:'origem')::uuid from conc.emp296 e where e.n = 3;
select conc.tornar_corrente(2);
select tests.impersonate('authenticated', (select uid from conc.emp296 where n = 3));
select public.create_commercial_checkout_intent((select comp from conc.emp296 where n = 3),
         'womens_clothing', 'direct_benefits') as r \gset
reset role; select set_config('request.jwt.claims', '', false);
insert into conc.estado values ('conjunto', :'conjunto'), ('intencao', (:'r')::jsonb->>'intent_id'),
  ('admin', :'uid_adm'), ('reserva_ok', (:'r')::jsonb->>'ok');
create or replace function conc.pedido_da_reserva(p_intent uuid) returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id,
     niche_code, nominal_quantity, fidelized, status, expected_operation_start,
     registered_by, pricing_rule_version, benefit_settlement_mode,
     economic_value_cents, contractual_pool_cents, bdflow_due_cents,
     contract_economics_version, mei_consideration_cents, smallflags_qa_cents,
     smallflags_main_fee_cents, smallflags_total_remuneration_cents,
     mei_cash_funding_cents, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, checkout_intent_id)
  select i.exclusivity_id, i.opportunity_id, i.company_id,
         (select id from public.commercial_master_agreements where company_id = i.company_id and status = 'signed'),
         i.region_id, i.niche_code, i.nominal_quantity, i.fidelized, 'draft',
         (now() + interval '30 days')::date, (select user_id from public.site_admins limit 1),
         i.pricing_rule_version, i.benefit_settlement_mode,
         i.economic_value_cents, i.user_pool_cents, i.bdflow_ops_investment_cents,
         i.contract_economics_version, i.mei_consideration_cents, i.smallflags_qa_cents,
         i.smallflags_main_fee_cents, i.smallflags_total_remuneration_cents,
         i.mei_cash_funding_cents, i.cash_user_pool_funding_cents,
         i.total_monetary_funding_required_cents, i.id
    from public.commercial_checkout_intents i where i.id = p_intent
  returning id into v_id;
  insert into conc.estado values ('pedido', v_id) on conflict (k) do update set v = excluded.v;
  return v_id;
end $f$;
commit;
