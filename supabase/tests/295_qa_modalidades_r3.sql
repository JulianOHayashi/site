-- ===========================================================================
-- 295 — R3: QA EXCLUSIVAMENTE EM PRODUTOS NO BENEFÍCIO DIRETO; SEM QA NO
-- DINHEIRO; pagamento conferido pelo snapshot; ativação e checkout travados
-- no banco. Migration 20261113150000.
--
-- Os preços da modalidade DINHEIRO usados aqui são FIXTURES (Cenário A ou B),
-- criados só dentro de transações revertidas. Nenhum é decisão.
-- As linhas PASS/FAIL impressas são a evidência.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();
select tests.fechar_portao_autoatendimento_qa();

-- ---------------------------------------------------------------------------
-- 0. Estado de partida
-- ---------------------------------------------------------------------------
select tests.check('SF-v1.4 vigente sem politica R3; SF-v1.5 preparada com QA so em produtos no beneficio direto',
    (select status = 'active' and qa_policy is null from public.commercial_pricing_rules where version = 3)
    and (select status = 'prepared' and qa_policy = 'in_kind_direct_benefits_only'
           from public.commercial_pricing_rules where version = 4));
select tests.check('historico SF-v1.4: resposta publica identica byte a byte a de Production (md5 9fa02757...)',
    md5(public.get_public_niche_pricing()::text) = '9fa027579866dd2cde79388545ac2787');
select tests.check('historico SF-v1.4: CHECK v1.4 so re-escopado (versao 3), expressao de liquidacao intacta',
    (select pg_get_constraintdef(oid) like '%(pricing_rule_version >= 4) OR (pricing_rule_version < 3)%'
            and pg_get_constraintdef(oid) like '%(total_monetary_funding_required_cents = smallflags_total_remuneration_cents)%'
       from pg_constraint where conname = 'ceo_financiamento_v14_coerente'));
select tests.check('beneficio direto v4: supermercado e demais, novo e fidelizado, fecham em centavos com QA em produtos',
    (select string_agg(format('%s/%s/%s=%s+%s+%s/din=%s', commercial_category, fidelized::text,
            economic_value_cents, mei_in_kind_cents, smallflags_main_fee_cents, qa_in_kind_cents,
            total_monetary_funding_required_cents), ';' order by commercial_category, fidelized)
       from public.commercial_settlement_terms
      where pricing_rule_version = 4 and benefit_settlement_mode = 'direct_benefits')
    = 'common/false/2293900=1192716+1095100+6084/din=1095100;'
      'common/true/1618800=1192716+420000+6084/din=420000;'
      'supermarket/false/3293900=2385432+896300+12168/din=896300;'
      'supermarket/true/2817600=2385432+420000+12168/din=420000');
select tests.check('beneficio direto: QA monetaria zero e QA fora do dinheiro devido',
    (select bool_and(qa_cash_cents = 0 and total_monetary_funding_required_cents = smallflags_main_fee_cents
                     and total_monetary_funding_required_cents + qa_in_kind_cents + mei_in_kind_cents = economic_value_cents)
       from public.commercial_settlement_terms where benefit_settlement_mode = 'direct_benefits'));
select tests.check('DINHEIRO da versao 4 nao existe: preco pendente de decisao (A ou B)',
    not exists (select 1 from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'));
select tests.check('A4: sem preco do dinheiro, minutas R3 e catalogo SF-v1.5 a versao 4 NAO ativa',
    (select (p->>'ok')::boolean = false
            and p->'failures' ?& array['settlement_terms_missing:supermarket/novo/cash',
                                       'settlement_terms_missing:common/fidelizado/cash',
                                       'instrument_template_missing:novo',
                                       'instrument_template_missing:fidelizado']
       from (select public.commercial_pricing_activation_preflight(4) p) x));
select tests.check('autoatendimento travado no banco abaixo da versao 4',
    (select min_pricing_rule_version = 4 from public.commercial_checkout_gate));
select tests.check('ninguem alem do dono ativa versao, le a pre-verificacao ou escreve termos/portao/registro',
    not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.admin_activate_pricing_rule(integer,text)',
                                 'public.commercial_pricing_activation_preflight(integer)',
                                 'public.commercial_settlement_terms_for(integer,text,boolean,text)',
                                 'public.commercial_order_settlement_check(uuid)',
                                 'public.cci_liquidar_modalidade_v15()',
                                 'public.ceo_liquidar_modalidade_v15()']) f
       where has_function_privilege(r, f, 'EXECUTE'))
    and not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.commercial_settlement_terms','public.commercial_checkout_gate',
                                 'public.commercial_pricing_activation_log']) t,
                    unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p
       where has_table_privilege(r, t, p)));

-- ---------------------------------------------------------------------------
-- 1. Termos: QA so em produtos, so no beneficio direto
-- ---------------------------------------------------------------------------
begin;
create or replace function pg_temp.termo_dinheiro(p_cat text, p_fid boolean, p_econ bigint,
  p_qa_in_kind bigint, p_qa_cash bigint, p_adj bigint, p_basis text, p_main_extra bigint default 0)
returns void language sql as $f$
  insert into public.commercial_settlement_terms
    (pricing_rule_version, contract_economics_version, commercial_category, fidelized,
     benefit_settlement_mode, economic_value_cents, mei_consideration_cents, mei_in_kind_cents,
     mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents, qa_cash_cents,
     cash_adjustment_cents, cash_adjustment_basis, total_monetary_funding_required_cents,
     ordinary_participation_value_cents, decision_reference)
  select 4, s.contract_economics_version, p_cat, p_fid, 'cash', p_econ, s.mei_consideration_cents, 0,
         s.mei_consideration_cents, s.smallflags_main_fee_cents + p_main_extra, p_qa_in_kind, p_qa_cash,
         p_adj, p_basis, p_econ, s.ordinary_participation_value_cents, '[QA FICTICIO] teste 295'
    from public.commercial_pricing_schedule s
   where s.pricing_rule_version = 4 and s.commercial_category = p_cat and s.fidelized = p_fid;
$f$;
select tests.check_raises('DINHEIRO com QA monetaria diferente de zero e rejeitado',
  $sql$select pg_temp.termo_dinheiro('supermarket', false, 2385432 + 896300, 0, 12168, 0, null)$sql$,
  'cst_sem_qa_em_dinheiro');
select tests.check_raises('QA em dinheiro e rejeitada em qualquer modalidade (CHECK proprio)',
  $sql$update public.commercial_settlement_terms set qa_cash_cents = 12168
        where pricing_rule_version = 4 and commercial_category = 'supermarket' and not fidelized
          and benefit_settlement_mode = 'direct_benefits'$sql$,
  'cst_sem_qa_em_dinheiro');
select tests.check_raises('DINHEIRO com QA em produtos diferente de zero e rejeitado',
  $sql$select pg_temp.termo_dinheiro('supermarket', false, 2385432 + 896300 + 12168, 12168, 0, 0, null)$sql$,
  'cst_dinheiro');
select tests.check_raises('beneficio direto com QA cobrada em dinheiro e rejeitado na versao 4',
  $sql$update public.commercial_settlement_terms set total_monetary_funding_required_cents = 896300 + 12168
        where pricing_rule_version = 4 and commercial_category = 'supermarket' and not fidelized
          and benefit_settlement_mode = 'direct_benefits'$sql$,
  'cst_beneficio_direto');
select tests.check_raises('beneficio direto nao aceita componente de ajuste',
  $sql$update public.commercial_settlement_terms set cash_adjustment_cents = 100,
        cash_adjustment_basis = 'qualquer fundamento com mais de vinte letras'
        where pricing_rule_version = 4 and commercial_category = 'common' and fidelized
          and benefit_settlement_mode = 'direct_benefits'$sql$,
  'cst_beneficio_direto');
select tests.check_raises('QA nao vira remuneracao por inferencia: principal do dinheiro e o da agenda',
  $sql$select pg_temp.termo_dinheiro('supermarket', false, 2385432 + 896300 + 12168, 0, 0, 0, null, 12168)$sql$,
  'settlement_terms_divergem_da_agenda');
select tests.check_raises('componente do Cenario B exige fundamento (nao e QA renomeada)',
  $sql$select pg_temp.termo_dinheiro('supermarket', false, 3293900, 0, 0, 12168, null)$sql$,
  'cst_ajuste_fundamentado');
select tests.check_raises('beneficio direto: QA em produtos e a da agenda',
  $sql$update public.commercial_settlement_terms set qa_in_kind_cents = 1, economic_value_cents = 2385432 + 896300 + 1
        where pricing_rule_version = 4 and commercial_category = 'supermarket' and not fidelized
          and benefit_settlement_mode = 'direct_benefits'$sql$,
  'settlement_terms_divergem_da_agenda');
select tests.check_raises('termos nao sao escritos para a SF-v1.4 publicada (historico preservado)',
  $sql$insert into public.commercial_settlement_terms (pricing_rule_version, contract_economics_version,
        commercial_category, fidelized, benefit_settlement_mode, economic_value_cents, mei_consideration_cents,
        mei_in_kind_cents, mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents,
        total_monetary_funding_required_cents, ordinary_participation_value_cents, decision_reference)
        values (3, 'SF-v1.4', 'common', false, 'cash', 1999900, 1192716, 0, 1192716, 807184, 0, 1999900, 14199,
                'tentativa de reescrever historico')$sql$,
  'settlement_terms_imutaveis');
savepoint sem_politica;
update public.commercial_pricing_rules set qa_policy = null where version = 4;
select tests.check_raises('sem politica de QA na versao, nenhum termo e aceito',
  $sql$select pg_temp.termo_dinheiro('common', true, 1192716 + 420000, 0, 0, 0, null)$sql$,
  'settlement_terms_sem_politica');
select tests.check('sem politica de QA a pre-verificacao aponta a falta',
    public.commercial_pricing_activation_preflight(4)->'failures' ? 'qa_policy_missing');
rollback to savepoint sem_politica;
rollback;

-- ---------------------------------------------------------------------------
-- 2. Os dois cenarios do DINHEIRO (fixtures): valores e diferenca
-- ---------------------------------------------------------------------------
begin;
select tests.preparar_ativacao_sf_v15_qa('295A', 'A');
select tests.check('Cenario A: dinheiro sem QA = participantes + principal (32.817,32 / 28.054,32 / 22.878,16 / 16.127,16)',
    (select string_agg(format('%s/%s/%s', commercial_category, fidelized::text, economic_value_cents), ';'
                       order by commercial_category, fidelized)
       from public.commercial_settlement_terms where pricing_rule_version = 4 and benefit_settlement_mode = 'cash')
    = 'common/false/2287816;common/true/1612716;supermarket/false/3281732;supermarket/true/2805432');
select tests.check('Cenario A: QA zero nas duas formas, ajuste zero, dinheiro devido = economico, MEI em dinheiro',
    (select bool_and(qa_in_kind_cents = 0 and qa_cash_cents = 0 and cash_adjustment_cents = 0
                     and total_monetary_funding_required_cents = economic_value_cents
                     and mei_cash_cents = mei_consideration_cents and mei_in_kind_cents = 0)
       from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'));
select tests.check('Cenario A: diferenca para o beneficio direto = exatamente a QA (121,68 / 60,84), principal igual',
    (select bool_and(d.economic_value_cents - c.economic_value_cents = d.qa_in_kind_cents
                     and d.smallflags_main_fee_cents = c.smallflags_main_fee_cents)
       from public.commercial_settlement_terms d
       join public.commercial_settlement_terms c
         on c.pricing_rule_version = d.pricing_rule_version and c.commercial_category = d.commercial_category
        and c.fidelized = d.fidelized and c.benefit_settlement_mode = 'cash'
      where d.benefit_settlement_mode = 'direct_benefits'));
select tests.check('com termos, minutas R3 e catalogo SF-v1.5 a pre-verificacao passa',
    (public.commercial_pricing_activation_preflight(4)->>'ok')::boolean);
rollback;
begin;
select tests.preparar_ativacao_sf_v15_qa('295B', 'B');
select tests.check('Cenario B: preco publicado mantido, com componente fundamentado (nao QA)',
    (select bool_and(c.economic_value_cents = d.economic_value_cents
                     and c.cash_adjustment_cents = d.qa_in_kind_cents
                     and c.cash_adjustment_basis is not null
                     and c.qa_in_kind_cents = 0 and c.qa_cash_cents = 0
                     and c.smallflags_main_fee_cents = d.smallflags_main_fee_cents)
       from public.commercial_settlement_terms d
       join public.commercial_settlement_terms c
         on c.pricing_rule_version = d.pricing_rule_version and c.commercial_category = d.commercial_category
        and c.fidelized = d.fidelized and c.benefit_settlement_mode = 'cash'
      where d.benefit_settlement_mode = 'direct_benefits'));
rollback;
begin;
select tests.encerrar_contexto_contratual_v14_qa();

select r.id as reg from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

select tests.mk_user('admin295') as uid_adm \gset
insert into public.site_admins (user_id) values ((:'uid_adm')::uuid) on conflict do nothing;

-- Doze empresas em Viana, cada uma com titular.
create temp table emp295 (n int primary key, cnpj text, comp uuid, uid uuid) on commit drop;
do $$
declare
  v_cnpjs text[] := array['29000001000118','29000002000162','29000003000107','29000004000151',
                          '29000005000104','29000006000140','29000007000195','29000008000130',
                          '29000009000184','29000010000109','29000011000153','29000012000106'];
  v_i int; v_app uuid; v_comp uuid; v_uid uuid;
begin
  for v_i in 1..12 loop
    v_uid := tests.mk_user('titular295.' || v_i);
    insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
    values (v_cnpjs[v_i], 'Empresa 295-' || v_i, 'e295' || v_i || '@teste.local', 'Viana', 'ES')
    returning id into v_app;
    insert into public.partner_application_representatives
      (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
    values (v_app, 'Titular 295-' || v_i, '52998224725', 'rep295' || v_i || '@teste.local',
            'Socio administrador', 'approved', true, now() - interval '2 days');
    insert into public.site_partner_companies
      (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
    values (v_app, v_cnpjs[v_i], 'Empresa 295-' || v_i, 'Loja 295-' || v_i,
            'e295' || v_i || '@teste.local', 'Viana', 'ES', 'active')
    returning id into v_comp;
    insert into public.site_company_members
      (company_id, auth_user_id, role, full_name, cpf, source, status)
    values (v_comp, v_uid, 'partner_owner', 'Titular 295-' || v_i, '52998224725',
            'application_promotion', 'active');
    insert into public.site_partner_units (company_id, name, city, uf, status)
    values (v_comp, 'Unidade 295-' || v_i, 'Viana', 'ES', 'active');
    insert into emp295 values (v_i, v_cnpjs[v_i], v_comp, v_uid);
  end loop;
end $$;

-- As tabelas temporárias da suíte são lidas também sob o papel impersonado.
grant select on emp295 to authenticated;
select tests.impersonate('authenticated', :'uid_adm');
select tests.assinar_mestre_qa(e.comp, 'AM-295-' || e.n) from emp295 e;
select (public.admin_create_commercial_segment('pet_shop_295','Pet shop 295','pet_shop_295')->>'segment_id') as seg \gset
reset role;
select set_config('request.jwt.claims', '', true);

-- Exclusividades E0 (reservas), E1..E4 (cenários) e E5 (instrumento), cada
-- uma com as seis posições.
create temp table exc295 (k int primary key, id uuid) on commit drop;
select set_config('tests.reg295', :'reg', true);
do $$
declare v_k int; v_id uuid;
begin
  for v_k in 0..5 loop
    insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
    values (current_setting('tests.reg295')::uuid, 2950 + v_k, 'forming', false)
    returning id into v_id;
    insert into exc295 values (v_k, v_id);
  end loop;
end $$;
grant select on exc295 to authenticated;
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select x.id, n.code, n.contracted_quantity, 'available'
  from exc295 x cross join public.commercial_niches n where n.is_active;

create or replace function pg_temp.tornar_corrente(p_k int) returns void language sql as $f$
  update public.commercial_exclusivities set is_current = false
   where region_id = (select region_id from public.commercial_exclusivities
                       where id = (select id from exc295 where k = p_k)) and is_current;
  update public.commercial_exclusivities set is_current = true
   where id = (select id from exc295 where k = p_k);
$f$;

-- Pedido direto (caminho administrativo): os números vêm dos gatilhos.
create or replace function pg_temp.pedido(p_k int, p_n int, p_niche text, p_fid boolean,
                                          p_mode text default 'direct_benefits')
returns uuid language plpgsql as $f$
declare v_id uuid; v_excl uuid := (select id from exc295 where k = p_k);
        v_comp uuid := (select comp from emp295 where n = p_n);
        v_seg public.commercial_segments%rowtype;
begin
  if p_niche = 'others' then
    select * into v_seg from public.commercial_segments where code = 'pet_shop_295';
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

create or replace function pg_temp.conjunto(p_order uuid, p_dias int) returns uuid language sql as $f$
  insert into public.commercial_flag_sets
    (origin_order_id, company_id, fidelity_identity, pieces_count, produced_at,
     supplier_name, unit_cost_cents, recorded_by)
  values (p_order, gen_random_uuid(), 'qualquer_coisa', 1, now() - make_interval(days => p_dias),
          '[QA FICTICIO] Fornecedor', 3500, (select user_id from public.site_admins limit 1))
  returning id;
$f$;

create or replace function pg_temp.inspecao(p_set uuid, p_dias int, p_unfit int default 0,
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


-- ---------------------------------------------------------------------------
-- 3. Antes da ativação: nenhuma chamada direta contorna a trava
-- ---------------------------------------------------------------------------
select pg_temp.tornar_corrente(0);
select tests.impersonate('authenticated', (select uid::text from emp295 where n = 1)::uuid);
select tests.check_raises('RPC direta sob a SF-v1.4: reserva recusada pelo banco (portao), nao so pelo navegador',
  format($sql$select public.create_commercial_checkout_intent(%L::uuid, 'pharmacy', 'cash')$sql$,
         (select comp from emp295 where n = 1)),
  'checkout_bloqueado');
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('nada ficou reservado pela tentativa',
    not exists (select 1 from public.commercial_checkout_intents
                 where company_id = (select comp from emp295 where n = 1))
    and (select status = 'available' from public.commercial_opportunities
          where exclusivity_id = (select id from exc295 where k = 0) and niche_code = 'pharmacy'));
select tests.check_raises('pedido sob versao PREPARADA e recusado (caminho administrativo)',
  $sql$select pg_temp.pedido(1, 1, 'supermarket', false)$sql$, 'pricing_rule_not_published');

-- ---------------------------------------------------------------------------
-- 4. Ativação: só pelo procedimento autorizado, com pré-condições no banco
-- ---------------------------------------------------------------------------
select md5(public.calculate_niche_contract_pricing('supermarket', false, 3)::text) as md5_v3_sup,
       md5(public.calculate_niche_contract_pricing('pharmacy', true, 3)::text) as md5_v3_fid \gset
select tests.check_raises('A3: UPDATE direto nao ativa a versao 4',
  $sql$update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4$sql$,
  'ativacao_nao_autorizada');
select tests.check_raises('A3: UPDATE direto nao supera a versao vigente',
  $sql$update public.commercial_pricing_rules set status = 'superseded' where version = 3$sql$,
  'superacao_nao_autorizada');
select tests.check('A2/A4: ativacao autorizada sem pre-requisitos e recusada, com todas as pendencias',
    (select (r->>'ok')::boolean = false and r->>'reason' = 'activation_preconditions_pending'
            and jsonb_array_length(r->'failures') >= 7
       from (select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 295') r) x)
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared');
select tests.check('ativacao exige referencia de autorizacao',
    (public.admin_activate_pricing_rule(4, 'curta')->>'reason') = 'authorization_reference_required');

select tests.preparar_ativacao_sf_v15_qa('295', 'A');
savepoint forja;
alter table public.commercial_exclusivity_orders disable trigger ceo_pagamento_confere_snapshot;
-- R4: o registro forjado nem chega a ser gravado (so o procedimento grava);
-- com uma trava desligada, o proprio procedimento recusa.
select tests.check_raises('A3/A5: registro forjado e recusado ja na gravacao',
  $sql$insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight)
       values (4, '[QA FICTICIO] registro forjado', '{}'::jsonb)$sql$,
  'activation_log_somente_pelo_procedimento');
select tests.check('A3/A5: com a trava de pagamento DESLIGADA, o procedimento autorizado recusa a ativacao',
    -- R4.1: chave nova, com o estado encontrado e o aprovado no manifesto.
    (select r->'failures' ? 'guard_trigger_state_not_approved:public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot:D(aprovado O)'
       from (select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] trava desligada') r) x));
rollback to savepoint forja;

select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao autorizada da suite 295') as ativ \gset
select tests.check('ativacao autorizada: v4 vigente, v3 superada, ato registrado com ator e transacao',
    ((:'ativ')::jsonb->>'ok') = 'true'
    and ((:'ativ')::jsonb->>'superseded_version')::int = 3
    and (select status from public.commercial_pricing_rules where version = 4) = 'active'
    and (select status from public.commercial_pricing_rules where version = 3) = 'superseded'
    and (select count(*) = 1 and bool_and(actor is not null and txid = txid_current()
                                           and (preflight->>'ok')::boolean)
           from public.commercial_pricing_activation_log where pricing_rule_version = 4));
select tests.check('historico SF-v1.4 inalterado depois da ativacao (calculo por versao, md5)',
    md5(public.calculate_niche_contract_pricing('supermarket', false, 3)::text) = :'md5_v3_sup'
    and md5(public.calculate_niche_contract_pricing('pharmacy', true, 3)::text) = :'md5_v3_fid');
select tests.check_raises('termos ficam imutaveis depois da ativacao',
  $sql$update public.commercial_settlement_terms set notes = 'x' where pricing_rule_version = 4$sql$,
  'settlement_terms_imutaveis');
select tests.check_raises('politica de QA fica imutavel depois da ativacao',
  $sql$update public.commercial_pricing_rules set qa_policy = null where version = 4$sql$,
  'pricing_rule_imutavel');
select tests.check_raises('registro de ativacao nao e apagado',
  $sql$delete from public.commercial_pricing_activation_log$sql$, 'activation_log_imutavel');

-- Preço público por modalidade
select public.calculate_niche_contract_pricing('supermarket', false) as p_sup \gset
select tests.check('preco publico v4: blocos por modalidade, QA so no beneficio direto e em produtos',
    ((:'p_sup')::jsonb->>'qa_policy') = 'in_kind_direct_benefits_only'
    and ((:'p_sup')::jsonb->'settlement_modes'->'direct_benefits'->>'qa_in_kind_cents')::bigint = 12168
    and ((:'p_sup')::jsonb->'settlement_modes'->'direct_benefits'->>'qa_cash_cents')::bigint = 0
    and ((:'p_sup')::jsonb->'settlement_modes'->'direct_benefits'->>'total_monetary_funding_required_cents')::bigint = 896300
    and ((:'p_sup')::jsonb->'settlement_modes'->'cash'->>'qa_in_kind_cents')::bigint = 0
    and ((:'p_sup')::jsonb->'settlement_modes'->'cash'->>'qa_cash_cents')::bigint = 0
    and ((:'p_sup')::jsonb->'settlement_modes'->'cash'->>'economic_value_cents')::bigint = 3281732
    and ((:'p_sup')::jsonb->>'funding_direct_benefits_cents')::bigint = 896300
    and ((:'p_sup')::jsonb->>'smallflags_total_remuneration_cents')::bigint = 896300);

-- ---------------------------------------------------------------------------
-- 5. Reserva pelo RPC: a modalidade decide a composição
-- ---------------------------------------------------------------------------
select tests.impersonate('authenticated', (select uid::text from emp295 where n = 1)::uuid);
select public.create_commercial_checkout_intent((select comp from emp295 where n = 1),
         'supermarket', 'direct_benefits') as r_d \gset
select tests.impersonate('authenticated', (select uid::text from emp295 where n = 2)::uuid);
select public.create_commercial_checkout_intent((select comp from emp295 where n = 2),
         'pharmacy', 'cash') as r_c \gset
reset role; select set_config('request.jwt.claims', '', true);
select ((:'r_d')::jsonb->>'intent_id') as i_d, ((:'r_c')::jsonb->>'intent_id') as i_c \gset
select tests.check('beneficio direto: participantes em beneficios (23.854,32), QA 121,68 em produtos, dinheiro so a principal',
    ((:'r_d')::jsonb->>'ok') = 'true'
    and ((:'r_d')::jsonb->>'economic_value_cents')::bigint = 3293900
    and ((:'r_d')::jsonb->>'mei_in_kind_cents')::bigint = 2385432
    and ((:'r_d')::jsonb->>'mei_cash_funding_cents')::bigint = 0
    and ((:'r_d')::jsonb->>'qa_in_kind_cents')::bigint = 12168
    and ((:'r_d')::jsonb->>'qa_cash_cents')::bigint = 0
    and ((:'r_d')::jsonb->>'total_monetary_funding_required_cents')::bigint = 896300);
select tests.check('dinheiro: contraprestacao dos participantes em dinheiro (11.927,16), sem QA, cobra o valor da modalidade',
    ((:'r_c')::jsonb->>'ok') = 'true'
    and ((:'r_c')::jsonb->>'economic_value_cents')::bigint = 2287816
    and ((:'r_c')::jsonb->>'mei_cash_funding_cents')::bigint = 1192716
    and ((:'r_c')::jsonb->>'qa_in_kind_cents')::bigint = 0
    and ((:'r_c')::jsonb->>'qa_cash_cents')::bigint = 0
    and ((:'r_c')::jsonb->>'smallflags_qa_cents')::bigint = 0
    and ((:'r_c')::jsonb->>'total_monetary_funding_required_cents')::bigint = 2287816);
select tests.check('nenhum centavo atribuido duas vezes: economico = participantes + principal + QA em produtos + ajuste = pool + devido',
    (select bool_and(economic_value_cents = mei_consideration_cents + smallflags_main_fee_cents
                                           + qa_in_kind_cents + cash_adjustment_cents
                     and economic_value_cents = user_pool_cents + bdflow_ops_investment_cents
                     and mei_in_kind_cents + mei_cash_funding_cents = mei_consideration_cents)
       from public.commercial_checkout_intents where id in ((:'i_d')::uuid, (:'i_c')::uuid)));

-- Troca de modalidade: recalcula e congela; nada mais muda os valores.
update public.commercial_checkout_intents set benefit_settlement_mode = 'cash' where id = (:'i_d')::uuid;
select tests.check('troca de modalidade na reserva recalcula pelos termos do dinheiro (sem QA)',
    (select economic_value_cents = 3281732 and total_monetary_funding_required_cents = 3281732
            and qa_in_kind_cents = 0 and mei_cash_funding_cents = 2385432 and mei_in_kind_cents = 0
            and settlement_terms_id = (select id from public.commercial_settlement_terms
                                        where pricing_rule_version = 4 and commercial_category = 'supermarket'
                                          and not fidelized and benefit_settlement_mode = 'cash')
       from public.commercial_checkout_intents where id = (:'i_d')::uuid));
update public.commercial_checkout_intents set benefit_settlement_mode = 'direct_benefits' where id = (:'i_d')::uuid;
select tests.check('voltar ao beneficio direto restaura a QA em produtos e o dinheiro da principal',
    (select economic_value_cents = 3293900 and total_monetary_funding_required_cents = 896300
            and qa_in_kind_cents = 12168
       from public.commercial_checkout_intents where id = (:'i_d')::uuid));
select tests.check_raises('reserva: valor nao muda sem troca de modalidade',
  format($sql$update public.commercial_checkout_intents set total_monetary_funding_required_cents = 1 where id = %L$sql$, :'i_d'),
  'liquidacao_congelada');
select tests.check_raises('reserva: QA monetaria nao e enxertada',
  format($sql$update public.commercial_checkout_intents set qa_cash_cents = 12168 where id = %L$sql$, :'i_d'),
  'liquidacao_congelada');
savepoint fora_do_rascunho;
update public.commercial_checkout_intents set status = 'awaiting_contract' where id = (:'i_c')::uuid;
select tests.check_raises('fora do rascunho a modalidade nao muda',
  format($sql$update public.commercial_checkout_intents set benefit_settlement_mode = 'direct_benefits' where id = %L$sql$, :'i_c'),
  'commercial_checkout_intent_snapshot_immutable');
rollback to savepoint fora_do_rascunho;

-- CHECK como última barreira (gatilho de autoridade desligado de propósito).
savepoint sem_gatilho_intencao;
alter table public.commercial_checkout_intents disable trigger cci_liquidar_modalidade_v15;
select tests.check_raises('CHECK da intencao: beneficio direto com QA em dinheiro e recusado mesmo sem o gatilho',
  format($sql$update public.commercial_checkout_intents
           set total_monetary_funding_required_cents = 896300 + 12168,
               smallflags_total_remuneration_cents = 896300 + 12168
         where id = %L$sql$, :'i_d'),
  'cci_liquidacao_modalidade_v15');
rollback to savepoint sem_gatilho_intencao;

-- ---------------------------------------------------------------------------
-- 6. Pedido: cópia exata da reserva; QA só com modalidade compatível
-- ---------------------------------------------------------------------------
create or replace function pg_temp.pedido_da_reserva(p_intent uuid, p_mode text default null,
                                                     p_econ bigint default null)
returns uuid language plpgsql as $f$
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
         i.pricing_rule_version, coalesce(p_mode, i.benefit_settlement_mode),
         coalesce(p_econ, i.economic_value_cents), i.user_pool_cents, i.bdflow_ops_investment_cents,
         i.contract_economics_version, i.mei_consideration_cents, i.smallflags_qa_cents,
         i.smallflags_main_fee_cents, i.smallflags_total_remuneration_cents,
         i.mei_cash_funding_cents, i.cash_user_pool_funding_cents,
         i.total_monetary_funding_required_cents, i.id
    from public.commercial_checkout_intents i where i.id = p_intent
  returning id into v_id;
  return v_id;
end $f$;

select tests.check_raises('pedido nao troca a modalidade congelada na reserva',
  format($sql$select pg_temp.pedido_da_reserva(%L, 'direct_benefits')$sql$, :'i_c'),
  'liquidacao_divergente_da_intencao');
select tests.check_raises('pedido nao altera o valor congelado na reserva',
  format($sql$select pg_temp.pedido_da_reserva(%L, null, 3293900)$sql$, :'i_c'),
  'liquidacao_divergente_da_intencao');
select pg_temp.pedido_da_reserva((:'i_c')::uuid) as o_c \gset
select tests.check('pedido do dinheiro copia a reserva: mesmos termos, mesmo total, sem QA',
    (select o.settlement_terms_id = i.settlement_terms_id
            and o.total_monetary_funding_required_cents = 2287816
            and o.qa_in_kind_cents = 0 and o.qa_cash_cents = 0
            and o.mei_cash_funding_cents = 1192716
            and (public.commercial_order_settlement_check(o.id)->>'ok')::boolean
       from public.commercial_exclusivity_orders o
       join public.commercial_checkout_intents i on i.id = o.checkout_intent_id
      where o.id = (:'o_c')::uuid));
select tests.check_raises('pedido v4 sem modalidade e recusado (QA exige modalidade compativel)',
  $sql$select pg_temp.pedido(1, 3, 'womens_clothing', false, null)$sql$, 'liquidacao_sem_modalidade');
select tests.check_raises('pedido: QA em produtos congelada nao muda',
  format($sql$update public.commercial_exclusivity_orders set qa_in_kind_cents = 6084 where id = %L$sql$, :'o_c'),
  'pedido_imutavel');
select tests.check_raises('pedido: modalidade congelada nao muda',
  format($sql$update public.commercial_exclusivity_orders set benefit_settlement_mode = 'direct_benefits' where id = %L$sql$, :'o_c'),
  'pedido_imutavel');

savepoint sem_gatilho_pedido;
alter table public.commercial_exclusivity_orders disable trigger ceo_liquidar_modalidade_v15;
select tests.check_raises('CHECK do pedido: dinheiro com QA em produtos e recusado mesmo sem o gatilho',
  format($sql$insert into public.commercial_exclusivity_orders
     (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id, niche_code,
      nominal_quantity, fidelized, status, expected_operation_start, registered_by,
      pricing_rule_version, benefit_settlement_mode, economic_value_cents, contractual_pool_cents,
      bdflow_due_cents, contract_economics_version, mei_consideration_cents, smallflags_qa_cents,
      smallflags_main_fee_cents, smallflags_total_remuneration_cents, mei_cash_funding_cents,
      cash_user_pool_funding_cents, total_monetary_funding_required_cents,
      settlement_terms_id, qa_policy, mei_in_kind_cents, qa_in_kind_cents, qa_cash_cents, cash_adjustment_cents)
   select x.id, o.id, e.comp, (select id from public.commercial_master_agreements where company_id = e.comp and status = 'signed'),
          %L::uuid, 'footwear', 12, false, 'draft', (now() + interval '30 days')::date, %L::uuid,
          4, 'cash', 2293900, 1198800, 1095100, 'SF-v1.5', 1192716, 6084, 1095100, 1095100, 1192716,
          1198800, 2293900, t.id, 'in_kind_direct_benefits_only', 0, 6084, 0, 0
     from exc295 x join public.commercial_opportunities o on o.exclusivity_id = x.id and o.niche_code = 'footwear'
     join emp295 e on e.n = 5
     join public.commercial_settlement_terms t on t.pricing_rule_version = 4 and t.commercial_category = 'common'
          and not t.fidelized and t.benefit_settlement_mode = 'cash'
    where x.k = 1$sql$, :'reg', :'uid_adm'),
  'ceo_liquidacao_modalidade_v15');
rollback to savepoint sem_gatilho_pedido;

select tests.check_raises('pedido SF-v1.4 nao aceita campos de QA da R3',
  format($sql$insert into public.commercial_exclusivity_orders
     (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id, niche_code,
      nominal_quantity, fidelized, status, expected_operation_start, registered_by,
      pricing_rule_version, benefit_settlement_mode, economic_value_cents, contractual_pool_cents,
      bdflow_due_cents, qa_in_kind_cents)
   select x.id, o.id, e.comp, (select id from public.commercial_master_agreements where company_id = e.comp and status = 'signed'),
          %L::uuid, 'pharmacy', 12, false, 'draft', (now() + interval '30 days')::date, %L::uuid,
          3, 'direct_benefits', 1, 1, 0, 6084
     from exc295 x join public.commercial_opportunities o on o.exclusivity_id = x.id and o.niche_code = 'pharmacy'
     join emp295 e on e.n = 11
    where x.k = 1$sql$, :'reg', :'uid_adm'),
  'ceo_liquidacao_v15_so_versao_4');

-- ---------------------------------------------------------------------------
-- 7. Instrumento (A6) e pagamento (A5): um único valor exigível
-- ---------------------------------------------------------------------------
select pg_temp.tornar_corrente(5);
select id as opp_pha from public.commercial_opportunities
 where exclusivity_id = (select id from exc295 where k = 5) and niche_code = 'pharmacy' \gset
select id as opp_wom from public.commercial_opportunities
 where exclusivity_id = (select id from exc295 where k = 5) and niche_code = 'womens_clothing' \gset
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_register_manual_commercial_order(
  (:'opp_pha')::uuid, (select comp from emp295 where n = 12), 'v1', now() - interval '1 day',
  'Titular 295-12', (now() + interval '30 days')::date, 'cash', 'doc://pedido-295-dinheiro') as m_cash \gset
select public.admin_register_manual_commercial_order(
  (:'opp_wom')::uuid, (select comp from emp295 where n = 11), 'v1', now() - interval '1 day',
  'Titular 295-11', (now() + interval '30 days')::date, 'direct_benefits', 'doc://pedido-295-direto') as m_dir \gset
reset role; select set_config('request.jwt.claims', '', true);
select ((:'m_cash')::jsonb->>'order_id') as om_cash, ((:'m_dir')::jsonb->>'order_id') as om_dir \gset
select tests.check('venda manual v4 assinada com instrumento R3: dinheiro sem QA, direto com QA em produtos',
    ((:'m_cash')::jsonb->>'ok') = 'true' and ((:'m_dir')::jsonb->>'ok') = 'true'
    and (select instrument_snapshot->>'qa_policy' = 'in_kind_direct_benefits_only'
                and (instrument_snapshot->>'qa_in_kind_cents')::bigint = 0
                and (instrument_snapshot->>'qa_cash_cents')::bigint = 0
                and (instrument_snapshot->>'total_monetary_funding_required_cents')::bigint = 2287816
                and instrument_snapshot->'field_provenance'->>'qa_in_kind_cents' = 'contract_economics_authority'
           from public.commercial_exclusivity_orders where id = (:'om_cash')::uuid)
    and (select (instrument_snapshot->>'qa_in_kind_cents')::bigint = 6084
                and (instrument_snapshot->>'mei_in_kind_cents')::bigint = 1192716
                and (instrument_snapshot->>'total_monetary_funding_required_cents')::bigint = 1095100
           from public.commercial_exclusivity_orders where id = (:'om_dir')::uuid));

savepoint minuta_historica;
update public.commercial_instrument_templates set settlement_model = null
 where template_code like '[QA FICTICIO] MODELO-INSTRUMENTO-295-R3%' and not applies_to_fidelized;
select tests.check('A6: minuta sem o modelo de liquidacao R3 nao individualiza pedido v4',
    (public.commercial_build_instrument_snapshot((:'om_cash')::uuid,
       (select id from public.commercial_instrument_templates
         where template_code like '[QA FICTICIO] MODELO-INSTRUMENTO-295-R3%' and not applies_to_fidelized))
     ->>'reason') = 'commercial_instrument_template_settlement_model_mismatch');
rollback to savepoint minuta_historica;

select tests.impersonate('authenticated', :'uid_adm');
select public.admin_confirm_manual_bdflow_payment((:'om_cash')::uuid, 1095100, 'ref-295-a', 'so a remuneracao') as pg_rem \gset
select public.admin_confirm_manual_bdflow_payment((:'om_cash')::uuid, 2287816 - 1, 'ref-295-b', 'um centavo a menos') as pg_menos \gset
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('A5: confirmacao manual so com a remuneracao da SmallFlags e rejeitada no dinheiro',
    ((:'pg_rem')::jsonb->>'ok') = 'false'
    and ((:'pg_rem')::jsonb->>'reason') = 'amount_differs_from_due'
    and ((:'pg_rem')::jsonb->>'expected_cents')::bigint = 2287816
    and (select payment_status = 'pending' from public.commercial_exclusivity_orders where id = (:'om_cash')::uuid));
select tests.check('confirmacao manual com valor insuficiente (1 centavo) e rejeitada',
    ((:'pg_menos')::jsonb->>'ok') = 'false');
select tests.check_raises('nenhum caminho marca pago abaixo do snapshot (UPDATE direto do pedido)',
  format($sql$update public.commercial_exclusivity_orders set payment_status = 'confirmed',
         payment_confirmed_at = now(), payment_confirmed_by = %L, payment_amount_cents = 1095100,
         payment_confirmed_source = 'admin_manual' where id = %L$sql$, :'uid_adm', :'om_cash'),
  'pagamento_divergente_do_snapshot');
select tests.check_raises('tentativa no provedor nasce com o valor do snapshot, nunca com a remuneracao',
  format($sql$insert into public.commercial_payments (commercial_order_id, checkout_intent_id, provider,
         payment_method, amount_cents, expires_at, idempotency_key)
         values (%L, %L, 'pagarme', 'pix', 1095100, now() + interval '30 minutes', 'idem-295-errado')$sql$,
         :'om_cash', :'i_c'),
  'pagamento_divergente_do_snapshot');
with p as (
  insert into public.commercial_payments (commercial_order_id, checkout_intent_id, provider,
         payment_method, amount_cents, expires_at, idempotency_key)
  values ((:'om_cash')::uuid, (:'i_c')::uuid, 'pagarme', 'pix', 2287816, now() + interval '30 minutes',
          'idem-295-certo') returning amount_cents)
select tests.check('provedor e caminho administrativo exigem o MESMO valor (2.287.816 = esperado da confirmacao manual)',
    (select amount_cents = ((:'pg_rem')::jsonb->>'expected_cents')::bigint from p));
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_confirm_manual_bdflow_payment((:'om_cash')::uuid, 2287816, 'ref-295-c', 'valor do snapshot') as pg_ok \gset
select public.admin_confirm_manual_bdflow_payment((:'om_dir')::uuid, 1095100, 'ref-295-d', 'principal; QA em produtos') as pg_dir \gset
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('confirmacao com o total do snapshot: dinheiro 22.878,16; direto 10.951,00 (QA nao cobrada)',
    ((:'pg_ok')::jsonb->>'ok') = 'true' and ((:'pg_dir')::jsonb->>'ok') = 'true'
    and (select payment_amount_cents = total_monetary_funding_required_cents
           from public.commercial_exclusivity_orders where id = (:'om_cash')::uuid)
    and (select payment_amount_cents = 1095100 and qa_in_kind_cents = 6084
           from public.commercial_exclusivity_orders where id = (:'om_dir')::uuid));

-- ---------------------------------------------------------------------------
-- 8. Reutilização de bandeiras revalidada no pedido e na confirmação (A1)
-- ---------------------------------------------------------------------------
select pg_temp.pedido(1, 3, 'womens_clothing', false) as o_origem \gset
select pg_temp.conjunto(:'o_origem', 60) as set3 \gset
select pg_temp.inspecao(:'set3', 10) as insp_ok \gset
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code, established_by_order_id)
select e.cnpj, 'ES', 'viana', 'womens_clothing', (:'o_origem')::uuid from emp295 e where e.n = 3;
select pg_temp.tornar_corrente(2);
select tests.impersonate('authenticated', (select uid::text from emp295 where n = 3)::uuid);
select public.create_commercial_checkout_intent((select comp from emp295 where n = 3),
         'womens_clothing', 'direct_benefits') as r_f \gset
reset role; select set_config('request.jwt.claims', '', true);
select ((:'r_f')::jsonb->>'intent_id') as i_f \gset
select tests.check('reserva fidelizada com inspecao aprovada: 16.188,00, QA 60,84 em produtos, dinheiro 4.200,00',
    ((:'r_f')::jsonb->>'ok') = 'true' and ((:'r_f')::jsonb->>'fidelized')::boolean
    and ((:'r_f')::jsonb->>'economic_value_cents')::bigint = 1618800
    and ((:'r_f')::jsonb->>'qa_in_kind_cents')::bigint = 6084
    and ((:'r_f')::jsonb->>'total_monetary_funding_required_cents')::bigint = 420000);

savepoint inspecao_nova;
select pg_temp.inspecao(:'set3', 5, 2, array['damaged']);
select tests.check_raises('A1: inspecao mais nova reprovando pecas torna a da reserva obsoleta: pedido recusado',
  format($sql$select pg_temp.pedido_da_reserva(%L)$sql$, :'i_f'), 'flag_reuse_stale');
rollback to savepoint inspecao_nova;

savepoint conjunto_retirado;
update public.commercial_flag_sets set status = 'retired', retired_at = now(),
       retired_reason = '[QA] retirado entre a reserva e o pedido' where id = (:'set3')::uuid;
select tests.check_raises('A1: conjunto retirado depois da reserva: pedido recusado',
  format($sql$select pg_temp.pedido_da_reserva(%L)$sql$, :'i_f'), 'flag_reuse_stale');
rollback to savepoint conjunto_retirado;

select pg_temp.pedido_da_reserva((:'i_f')::uuid) as o_f \gset
update public.commercial_exclusivity_orders
   set status = 'signed', signed_at = now(), signatory_name = 'Titular 295-3',
       order_version = 'v1', document_reference = 'doc://pedido-295-fidelizado'
 where id = (:'o_f')::uuid;
update public.commercial_flag_sets set status = 'retired', retired_at = now(),
       retired_reason = '[QA] retirado entre o pedido e o pagamento' where id = (:'set3')::uuid;
select tests.check_raises('A1: conjunto retirado antes da confirmacao: pagamento nao e confirmado',
  format($sql$update public.commercial_exclusivity_orders set payment_status = 'confirmed',
         payment_confirmed_at = now(), payment_confirmed_by = %L, payment_amount_cents = 420000,
         payment_confirmed_source = 'admin_manual' where id = %L$sql$, :'uid_adm', :'o_f'),
  'flag_reuse_stale');

rollback;

-- ---------------------------------------------------------------------------
-- 9. Depois do rollback: nada vazou
-- ---------------------------------------------------------------------------
select tests.check('apos a suite: v3 vigente, v4 preparada, sem preco de dinheiro, sem ativacao, portao em 4',
    (select status from public.commercial_pricing_rules where version = 3) = 'active'
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_settlement_terms where benefit_settlement_mode = 'cash')
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and (select min_pricing_rule_version from public.commercial_checkout_gate) = 4
    and not exists (select 1 from public.commercial_exclusivity_orders where pricing_rule_version = 4));

select tests.finish('295_qa_modalidades_r3');
