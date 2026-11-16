-- ===========================================================================
-- 300 — R4.3: habilitação SOMENTE DINHEIRO (Cenário A) e a primeira
-- contratação de anunciante NOVO de ponta a ponta (migration 20261116210000).
--   A arquitetura: fato por versão, CHECKs, imutabilidade, pré-verificação
--     por modalidade (QA exigida só com benefício direto habilitado);
--   B ativação SOMENTE DINHEIRO com fixtures [QA FICTICIO] (minutas e
--     aprovações fictícias, SEM procedimento de QA), publicação;
--   C cadeia real das RPCs do Site: reserva em DINHEIRO -> termos -> pedido
--     -> instrumento -> Pix -> confirmação do provedor -> arte das bandeiras;
--     benefício direto recusado em reserva e pedido.
-- Tudo numa transação revertida; nada fica gravado.
-- ===========================================================================
\set ON_ERROR_STOP on
\set ON_ERROR_STOP on
select tests.reset_results();
select tests.fechar_portao_autoatendimento_qa();

select tests.check('estado de partida: guardas integras (manifesto vigente)',
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
select tests.mk_user('admin300') as adm \gset
insert into public.site_admins (user_id) values ((:'adm')::uuid) on conflict do nothing;
select tests.mk_user('titular300.1') as u1 \gset
select tests.mk_user('gerente300.1') as m1 \gset
select tests.mk_user('titular300.2') as u2 \gset

create or replace function pg_temp.empresa(p_cnpj text, p_n int, p_uid uuid) returns uuid language plpgsql as $f$
declare v_app uuid; v_comp uuid;
begin
  insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
  values (p_cnpj, 'Empresa 300-' || p_n, 'e300' || p_n || '@teste.local', 'Viana', 'ES') returning id into v_app;
  insert into public.partner_application_representatives
    (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
  values (v_app, 'Titular 298-' || p_n, '52998224725', 'rep298' || p_n || '@teste.local',
          'Socio administrador', 'approved', true, now() - interval '2 days');
  insert into public.site_partner_companies
    (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
  values (v_app, p_cnpj, 'Empresa 300-' || p_n, 'Loja 298-' || p_n, 'e300' || p_n || '@teste.local',
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
values (:'c1', :'m1', 'partner_manager', 'Gerente 300-1', '52998224725', 'manager_invite', 'active');

select tests.impersonate('authenticated', :'adm');
select tests.assinar_mestre_qa((:'c1')::uuid, 'AM-300-1');
select tests.assinar_mestre_qa((:'c2')::uuid, 'AM-300-2');
reset role; select set_config('request.jwt.claims', '', true);

create temp table exc300 (k int primary key, id uuid);
select set_config('tests.reg300', :'reg', true);
do $$
declare v_k int; v_id uuid;
begin
  for v_k in 0..3 loop
    insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
    values (current_setting('tests.reg300')::uuid, 2980 + v_k, 'forming', false) returning id into v_id;
    insert into exc300 values (v_k, v_id);
  end loop;
end $$;
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select x.id, n.code, n.contracted_quantity, 'available'
  from exc300 x cross join public.commercial_niches n where n.is_active;
create or replace function pg_temp.tornar_corrente(p_k int) returns void language sql as $f$
  update public.commercial_exclusivities set is_current = false
   where region_id = (select region_id from public.commercial_exclusivities
                       where id = (select id from exc300 where k = p_k)) and is_current;
  update public.commercial_exclusivities set is_current = true where id = (select id from exc300 where k = p_k);
$f$;
-- Pedido administrativo direto: números e fatos de produção vêm dos gatilhos.
create or replace function pg_temp.pedido(p_k int, p_comp uuid, p_niche text, p_fid boolean,
                                          p_mode text default 'direct_benefits') returns uuid
language plpgsql as $f$
declare v_id uuid; v_excl uuid := (select id from exc300 where k = p_k);
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

-- ===========================================================================
-- A. Arquitetura da habilitação por modalidade (sem ativar)
-- ===========================================================================
select tests.check('A: sem habilitacao, v4 exige as DUAS modalidades e a QA (comportamento anterior preservado)',
    (select enabled_settlement_modes is null from public.commercial_pricing_rules where version = 4)
    and public.commercial_enabled_settlement_modes(4) = array['direct_benefits', 'cash']
    and public.commercial_enabled_settlement_modes(3) is null
    and public.commercial_pricing_activation_preflight(4)->'failures' ? 'qa_operational_procedure_missing:SF-v1.5');
select tests.check_raises('A: modalidade desconhecida recusada (CHECK)',
  $s$update public.commercial_pricing_rules set enabled_settlement_modes = array['pix'] where version = 4$s$,
  'cpr_modalidades_habilitadas');
select tests.check_raises('A: modalidade repetida recusada (CHECK)',
  $s$update public.commercial_pricing_rules set enabled_settlement_modes = array['cash', 'cash'] where version = 4$s$,
  'cpr_modalidades_habilitadas');
select tests.check_raises('A: versao historica (< 4) nao recebe modalidade (congelada)',
  $s$update public.commercial_pricing_rules set enabled_settlement_modes = array['cash'] where version = 2$s$,
  'pricing_rule_imutavel');
select tests.check_raises('A: ninguem alem do dono altera a regra',
  $s$select tests.impersonate('authenticated', gen_random_uuid());
     update public.commercial_pricing_rules set enabled_settlement_modes = array['cash'] where version = 4$s$,
  'permission denied');
reset role; select set_config('request.jwt.claims', '', true);

savepoint so_habilitar;
update public.commercial_pricing_rules set enabled_settlement_modes = array['cash'] where version = 4;
select public.commercial_pricing_activation_preflight(4) as pre_cash \gset
select tests.check('A: somente DINHEIRO habilitado: a QA deixa de ser exigida PARA ATIVAR, os termos e a minuta do DINHEIRO passam a ser',
    not ((:'pre_cash')::jsonb->'failures' ? 'qa_operational_procedure_missing:SF-v1.5')
    and ((:'pre_cash')::jsonb->'failures' ? 'settlement_terms_missing:common/novo/cash')
    and not ((:'pre_cash')::jsonb->'failures' ? 'settlement_terms_missing:common/novo/direct_benefits')
    and ((:'pre_cash')::jsonb->'failures' ? 'instrument_template_missing:novo')
    and ((:'pre_cash')::jsonb->'failures' ? 'activation_approval_missing')
    and (:'pre_cash')::jsonb->'enabled_settlement_modes' = '["cash"]'::jsonb);
rollback to savepoint so_habilitar;


-- ===========================================================================
-- B. Ativação SOMENTE DINHEIRO com fixtures [QA FICTICIO]
-- ===========================================================================
select tests.preparar_ativacao_sf_v15_somente_dinheiro_qa('300') as prep \gset
select tests.check('B: preparada sem procedimento de QA e sem minuta do beneficio direto: pre-verificacao OK',
    (public.commercial_pricing_activation_preflight(4)->>'ok') = 'true'
    and not exists (select 1 from public.commercial_qa_operational_procedures)
    and not exists (select 1 from public.commercial_instrument_template_approvals
                     where 'direct_benefits' = any (settlement_modes)));
select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] aprovacao de lancamento 300') as at \gset
select tests.check('B: v4 ativada SOMENTE DINHEIRO (fixture), v3 superada',
    ((:'at')::jsonb->>'ok') = 'true'
    and (select status = 'active' and enabled_settlement_modes = array['cash']
           from public.commercial_pricing_rules where version = 4)
    and (select status from public.commercial_pricing_rules where version = 3) = 'superseded');
select tests.check_raises('B: depois da ativacao a habilitacao e imutavel (reabrir beneficio direto = nova versao)',
  $s$update public.commercial_pricing_rules set enabled_settlement_modes = array['direct_benefits', 'cash'] where version = 4$s$,
  'pricing_rule_imutavel');

-- Publicação.
select (select x from jsonb_array_elements(public.get_public_niche_pricing()->'niches') x
         where x->>'niche_code' = 'supermarket') as pub_sm \gset
select tests.check('B: publico informa somente DINHEIRO habilitado, com o Cenario A (supermercado novo 32.817,32)',
    ((:'pub_sm')::jsonb->'founding'->'enabled_settlement_modes') = '["cash"]'::jsonb
    and ((:'pub_sm')::jsonb->'founding'->'settlement_modes'->'cash'->>'economic_value_cents') = '3281732'
    and ((:'pub_sm')::jsonb->'fidelized'->'settlement_modes'->'cash'->>'economic_value_cents') = '2805432');

-- ===========================================================================
-- C. Primeira contratação real de anunciante NOVO, em DINHEIRO (cadeia
--    completa pelas RPCs do Site: reserva -> contrato -> pedido -> instrumento
--    -> Pix -> confirmação -> especificação das bandeiras)
-- ===========================================================================
select pg_temp.tornar_corrente(0);
select tests.impersonate('authenticated', :'adm');
select public.admin_publish_legal_document('commercial_order_terms', 'v1-teste-300', 'Termos do pedido comercial',
  '[QA FICTICIO] CONTEUDO DE TESTE (nao juridico)', 'hash-teste-300') as pubt \gset
reset role; select set_config('request.jwt.claims', '', true);

select tests.check('C: beneficio direto RECUSADO na reserva (nada reservado)',
    (pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'supermarket', 'direct_benefits')$s$, :'c1'))->>'reason')
      = 'settlement_mode_not_enabled'
    and not exists (select 1 from public.commercial_checkout_intents where company_id = (:'c1')::uuid));
select tests.check_raises('C: beneficio direto RECUSADO tambem no pedido (venda manual / gravacao direta)',
  format($s$select pg_temp.pedido(0, %L, 'pharmacy', false, 'direct_benefits')$s$, :'c2'), 'settlement_mode_not_enabled');

select pg_temp.como(:'u1', format($s$select public.create_commercial_checkout_intent(%L, 'supermarket', 'cash')$s$, :'c1')) as ri \gset
select (:'ri')::jsonb->>'intent_id' as intent \gset
select tests.check('C: reserva em DINHEIRO do anunciante novo: valor do Cenario A, 84 bandeiras novas, sem QA',
    ((:'ri')::jsonb->>'ok') = 'true'
    and (select not fidelized and benefit_settlement_mode = 'cash' and economic_value_cents = 3281732
                and total_monetary_funding_required_cents = 3281732 and coalesce(smallflags_qa_cents, 0) = 0
                and flag_production_new_units = 84 and pricing_rule_version = 4
           from public.commercial_checkout_intents where id = (:'intent')::uuid));
select pg_temp.como(:'u1', format('select public.advance_checkout_intent_to_contract(%L)', :'intent')) as adv \gset
select pg_temp.como(:'u1', format('select public.accept_commercial_order_terms(%L)', :'intent')) as ace \gset
select pg_temp.como(:'u1', format('select public.finalize_commercial_order_from_intent(%L)', :'intent')) as fin \gset
select (:'fin')::jsonb->>'order_id' as pedido \gset
select tests.check('C: contrato: avancar, aceitar os termos publicados e finalizar o pedido',
    ((:'adv')::jsonb->>'ok') = 'true' and ((:'ace')::jsonb->>'ok') = 'true' and ((:'fin')::jsonb->>'ok') = 'true');
select tests.check('C: pedido copia a intencao centavo a centavo (DINHEIRO, Cenario A, exigivel = valor)',
    (select o.benefit_settlement_mode = 'cash' and o.economic_value_cents = 3281732
            and o.total_monetary_funding_required_cents = 3281732 and o.flag_production_new_units = 84
            and not o.fidelized and o.pricing_rule_version = 4
       from public.commercial_exclusivity_orders o where o.id = (:'pedido')::uuid));
select pg_temp.como(:'u1', format('select public.get_order_instrument(%L)', :'pedido')) as inst \gset
select tests.check('C: instrumento emitido com a minuta aprovada para DINHEIRO e a modalidade no snapshot',
    ((:'inst')::jsonb->>'ok') = 'true'
    and coalesce((:'inst')::jsonb#>>'{instrument,snapshot,benefit_settlement_mode}',
                 (:'inst')::jsonb#>>'{snapshot,benefit_settlement_mode}',
                 (select instrument_snapshot#>>'{snapshot,benefit_settlement_mode}'
                    from public.commercial_exclusivity_orders where id = (:'pedido')::uuid)) = 'cash');
select pg_temp.como(:'u1', format('select public.open_commercial_payment_attempt(%L)', :'pedido')) as pg \gset
select (:'pg')::jsonb->>'payment_id' as pay \gset
select tests.check('C: primeira contratacao paga por Pix, no valor exigivel do snapshot',
    ((:'pg')::jsonb->>'ok') = 'true' and ((:'pg')::jsonb->>'payment_method') = 'pix'
    and ((:'pg')::jsonb->>'amount_cents') = '3281732');
select tests.impersonate('service_role', null);
select public.prov_record_payment_identifiers((:'pay')::uuid, 'or_300', 'ch_300', null, 'ref-300') as ids \gset
select public.prov_confirm_commercial_payment((:'pay')::uuid, 'paid', 3281732, 'pix', 'ref-300') as conf \gset
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('C: confirmacao do provedor paga o pedido (valor e metodo conferidos)',
    ((:'conf')::jsonb->>'ok') = 'true'
    and (select payment_status = 'confirmed' and payment_amount_cents = 3281732
           from public.commercial_exclusivity_orders where id = (:'pedido')::uuid));
select tests.check('C: o pagamento NAO cria fidelidade antes da regra do servidor; QA continua sem procedimento',
    not exists (select 1 from public.commercial_qa_operational_procedures)
    and (public.commercial_order_settlement_check((:'pedido')::uuid)->>'ok') is distinct from 'false');
select pg_temp.como(:'u1', format('select public.request_customization_image_path(%L)', :'pedido')) as img \gset
select tests.check('C: especificacao das bandeiras: o titular recebe o caminho para enviar a arte do pedido pago',
    ((:'img')::jsonb->>'ok') = 'true' and ((:'img')::jsonb->>'storage_path') like '%' || :'pedido' || '%');

-- Mantidos bloqueados (não implementados agora): renovação com nova arte,
-- danos, campanhas perdidas.
select tests.check('C: alteracao de arte segue sem prontidao (renovacao com nova arte bloqueada)',
    (public.commercial_artwork_change_readiness(gen_random_uuid())->>'ready') = 'false');

rollback;

select tests.check('apos a suite: nada vazou (v4 preparada e sem habilitacao, v3 ativa, sem ativacao/procedimento)',
    (select status = 'prepared' and enabled_settlement_modes is null from public.commercial_pricing_rules where version = 4)
    and (select status from public.commercial_pricing_rules where version = 3) = 'active'
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and not exists (select 1 from public.commercial_qa_operational_procedures)
    and not exists (select 1 from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'));

select tests.finish('300_r43_somente_dinheiro_primeira_contratacao');
