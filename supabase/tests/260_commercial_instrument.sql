-- ===========================================================================
-- 260 — P0-2: INSTRUMENTO COMERCIAL (infraestrutura, sem ativar a minuta)
--
-- A minuta v1.4 real NÃO é assinável e esta suíte não a promove. A fonte
-- congelada diz "NÃO ASSINAR AINDA", e tratar esse rascunho como aprovado só
-- para fazer teste passar seria desobedecer exatamente o documento sob teste.
-- O caminho completo é exercitado com um modelo INEQUIVOCAMENTE FICTÍCIO de QA.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- 1. A MINUTA REAL ESTÁ REGISTRADA E NÃO É ASSINÁVEL
-- ---------------------------------------------------------------------------
select tests.check('minuta v1.4 real registrada para rastreabilidade',
    (select count(*) = 1 from public.commercial_instrument_templates
      where template_code = 'SF-MINUTA-PRESENCIAL-v1.4'
        and template_version = '1.4'
        and template_date = date '2026-10-05'
        and source_hash = '03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73'));
select tests.check('minuta v1.4 esta em DRAFT, nunca assinavel por omissao',
    (select lifecycle_status = 'draft' from public.commercial_instrument_templates
      where template_code = 'SF-MINUTA-PRESENCIAL-v1.4'));
select tests.check('minuta v1.4 e da PRIMEIRA COMPRA, condicao nao fidelizada',
    (select applies_to_fidelized = false from public.commercial_instrument_templates
      where template_code = 'SF-MINUTA-PRESENCIAL-v1.4'));

-- O caminho de produção falha fechado nas duas condições de fidelidade.
select tests.check('producao falha fechada: nenhum modelo assinavel (nao fidelizado)',
    (public.commercial_signable_instrument_template(false) ->> 'reason')
      = 'commercial_instrument_template_unavailable');
select tests.check('producao falha fechada: nenhum modelo assinavel (fidelizado)',
    (public.commercial_signable_instrument_template(true) ->> 'reason')
      = 'commercial_instrument_template_unavailable');

-- OUTROS fica DORMENTE: declarado no modelo e desligado.
select tests.check('OUTROS nao esta habilitado em modelo algum',
    (select count(*) from public.commercial_instrument_templates
      where allows_outros_niche) = 0);
select tests.check('OUTROS nao e nicho canonico de produto/preco',
    (select count(*) from public.commercial_niches
      where code in ('outros','OUTROS','other')) = 0
    and (public.calculate_niche_contract_pricing('outros', false) ->> 'reason')
        = 'invalid_niche');

-- ---------------------------------------------------------------------------
-- 2. SERIAL GLOBAL — unicidade, monotonicidade, sem reuso, expansao
-- ---------------------------------------------------------------------------
select tests.check('codigo do instrumento comeca em quatro digitos',
    public.commercial_next_instrument_code() ~ '^SF-[0-9]{4}$');

-- Monotonicidade e unicidade numa rajada.
select tests.check('alocacao em rajada e unica e monotonica',
    (with lote as (
       select public.commercial_next_instrument_code() as c,
              row_number() over () as i
         from generate_series(1, 25))
     select count(distinct c) = 25
            and min(substring(c from 4)::bigint) + 24
                = max(substring(c from 4)::bigint)
       from lote));

-- Expansao acima de 9999. lpad() TRUNCA entrada mais longa que o alvo, e usar
-- lpad direto fazia SF-10000 colidir com SF-1000 — defeito pego em runtime.
select tests.check('serial expande naturalmente acima de 9999, sem truncar',
    (select bool_and(ok) from (
       select setval('public.commercial_instrument_serial', 9998) is not null as ok
       union all select public.commercial_next_instrument_code() = 'SF-9999'
       union all select public.commercial_next_instrument_code() = 'SF-10000'
       union all select public.commercial_next_instrument_code() = 'SF-10001'
     ) t));

-- Nenhum reuso de numero: transacao revertida deixa LACUNA, e lacuna nao e
-- requisito legal — mas numero comprometido jamais volta.
select public.commercial_next_instrument_code() as antes_rollback \gset
begin;
select public.commercial_next_instrument_code() as dentro \gset
rollback;
select public.commercial_next_instrument_code() as depois_rollback \gset
select tests.check('numero consumido em transacao revertida NAO e reutilizado',
    substring((:'depois_rollback') from 4)::bigint
      > substring((:'dentro') from 4)::bigint
    and (:'depois_rollback') <> (:'dentro')
    and (:'dentro') <> (:'antes_rollback'));

-- ---------------------------------------------------------------------------
-- 3. Fixtures de pedido para exercitar o snapshot
-- ---------------------------------------------------------------------------
select tests.mk_user('admin260@teste.local') as uid_admin \gset
insert into public.site_admins (user_id) values ((:'uid_admin')::uuid)
on conflict do nothing;
select tests.mk_user('titular260@teste.local') as uid_t \gset

select r.id as reg260 from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg260')::uuid, 260, 'forming', false)
returning id as excl260 \gset
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl260')::uuid, 'mens_clothing', 12, 'available')
returning id as opp260 \gset

insert into public.partner_applications (cnpj, legal_name, trade_name, contact_email, city, uf)
values ('26010001000100','Empresa 260 LTDA','Marca 260','e260@teste.local','Viana','ES')
returning id as app260 \gset
-- O representante com autoridade vem do registro canonico da candidatura.
-- par_decisao_coerente exige decided_at quando a autoridade foi aprovada.
insert into public.partner_application_representatives
  (application_id, full_name, cpf, email, role_title, authority_status,
   is_current, decided_at)
values ((:'app260')::uuid, 'Representante Canonico 260', '52998224725',
        'rep260@teste.local', 'Socio administrador', 'approved', true,
        now() - interval '2 days');
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
values ((:'app260')::uuid,'26010001000100','Empresa 260 LTDA','Marca 260',
        'e260@teste.local','Viana','ES','active')
returning id as comp260 \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, cpf, source, status)
values ((:'comp260')::uuid, (:'uid_t')::uuid, 'partner_owner',
        'Representante Canonico 260', '52998224725', 'application_promotion', 'active');

-- Uma unidade ativa: com exatamente UMA, o servidor pre-seleciona por
-- conveniencia, e o fato canonico persistido continua sendo o ID dela.
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp260')::uuid, 'Unidade 260 Centro', 'Viana', 'ES', 'active')
returning id as unid260 \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.assinar_mestre_qa((:'comp260')::uuid, 'AM-260');
commit;

-- P0-C: sem modelo assinável, a própria RPC autoritativa falha ANTES da escrita.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp260')::uuid, (:'comp260')::uuid, 'v1', now() - interval '1 day',
  'Representante Canonico 260', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-260') as r_sem_modelo \gset
commit;
select tests.check('P0-C: sem modelo assinavel a RPC retorna erro de dominio',
    ((:'r_sem_modelo')::jsonb ->> 'ok') = 'false'
    and ((:'r_sem_modelo')::jsonb ->> 'reason')
      = 'commercial_instrument_template_unavailable');
select tests.check('P0-C: sem modelo assinavel nenhum pedido v1.4 e criado',
    (select count(*) = 0 from public.commercial_exclusivity_orders
      where opportunity_id = (:'opp260')::uuid));

-- ---------------------------------------------------------------------------
-- 4. MODELO EM RASCUNHO NÃO INDIVIDUALIZA INSTRUMENTO
-- ---------------------------------------------------------------------------
select id as tpl_v14 from public.commercial_instrument_templates
 where template_code = 'SF-MINUTA-PRESENCIAL-v1.4' \gset

-- O lifecycle e validado antes do pedido: ate um UUID inexistente deve ser
-- recusado por o modelo real continuar DRAFT.
select tests.check('construtor recusa modelo em DRAFT',
    (public.commercial_build_instrument_snapshot(
       gen_random_uuid(), (:'tpl_v14')::uuid)
     ->> 'reason') = 'commercial_instrument_template_not_signable');

-- ---------------------------------------------------------------------------
-- 4-bis. O CONSTRUTOR NÃO ACEITA FATO DE CHAMADOR
-- ---------------------------------------------------------------------------
select tests.check('existe APENAS a versao de dois argumentos do construtor',
    (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'commercial_build_instrument_snapshot')
    and (select p.pronargs = 2
                and p.proargtypes[0] = 'uuid'::regtype::oid
                and p.proargtypes[1] = 'uuid'::regtype::oid
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = 'commercial_build_instrument_snapshot'));
select tests.check_raises('chamar o construtor com JSON de fatos NAO existe mais',
  format($sql$select public.commercial_build_instrument_snapshot(%L::uuid, %L::uuid,
           '{"activity_description":"injetado","nfse_taker_cnpj":"11111111111111"}'::jsonb)$sql$,
         gen_random_uuid(), :'tpl_v14'),
  'does not exist');

-- ---------------------------------------------------------------------------
-- 5. MODELO FICTÍCIO DE QA, ASSINÁVEL — o caminho completo
-- ---------------------------------------------------------------------------
select tests.criar_modelo_instrumento_qa(false, '260') as tpl_qa \gset
select tests.check('fixture de QA e inequivocamente ficticia, e NAO e a minuta real',
    (select template_code like '[QA FICTICIO]%'
        and source_hash <> '03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73'
       from public.commercial_instrument_templates where id = (:'tpl_qa')::uuid));
select tests.check('modelo de QA e resolvido como assinavel para nao fidelizado',
    (public.commercial_signable_instrument_template(false) ->> 'ok') = 'true'
    and (public.commercial_signable_instrument_template(false) ->> 'template_id')::uuid
        = (:'tpl_qa')::uuid);

-- 5a. ATIVIDADE CONTRATADA — modelo signable sozinho NAO basta. A emissão
-- automática tem de abortar o pedido inteiro se faltar qualquer fato material.
select tests.check('NAO existe atividade aprovada de producao para nicho algum',
    (select count(*) from public.commercial_contract_activity_catalog
      where status = 'approved' and activity_code not like 'QA-%') = 0);
begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.check_raises('modelo signable sem atividade aprovada aborta o pedido inteiro',
  format($sql$select public.admin_register_manual_commercial_order(
    %L::uuid, %L::uuid, 'v1', now() - interval '1 day',
    'Representante Canonico 260', (now() + interval '30 days')::date,
    'direct_benefits', 'doc://pedido-260-sem-atividade')$sql$,
    :'opp260', :'comp260'),
  'commercial_activity_description_unavailable');
commit;
select tests.check('falha do snapshot reverte o INSERT do pedido',
    (select count(*) = 0 from public.commercial_exclusivity_orders
      where opportunity_id = (:'opp260')::uuid));
select tests.check('o nome de exibicao do nicho NAO e usado como atividade contratada',
    (select count(*) = 0 from public.commercial_contract_activity_catalog c
       join public.commercial_niches n on n.code = c.niche_code
      where c.activity_description = n.display_name));

-- 5b. Com atividade FICTÍCIA aprovada, a MESMA RPC cria pedido + instrumento
-- na mesma transação. A minuta real continua draft.
select tests.aprovar_atividade_qa('mens_clothing') as ativ_qa \gset
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp260')::uuid, (:'comp260')::uuid, 'v1', now() - interval '1 day',
  'Representante Canonico 260', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-260') as r_ord \gset
commit;
select tests.check('fixture: pedido 260 criado somente apos modelo+atividade QA',
    ((:'r_ord')::jsonb ->> 'ok') = 'true');
select ((:'r_ord')::jsonb ->> 'order_id') as ord260 \gset
select tests.check('com UMA unica unidade ativa o servidor pre-seleciona, e persiste o ID',
    (select execution_unit_id = (:'unid260')::uuid
       from public.commercial_exclusivity_orders where id = (:'ord260')::uuid));
select tests.check('P0-C: pedido v1.4 nasce COM instrumento emitido pelo servidor',
    (select instrument_code ~ '^SF-[0-9]{4,}$'
        and instrument_template_id = (:'tpl_qa')::uuid
        and instrument_template_version = '0.0-qa'
        and instrument_snapshot is not null
        and instrument_snapshot_hash ~ '^[0-9a-f]{64}$'
       from public.commercial_exclusivity_orders where id = (:'ord260')::uuid));
select tests.check('a minuta real v1.4 continua DRAFT depois da emissao QA',
    (select lifecycle_status = 'draft' from public.commercial_instrument_templates
      where id = (:'tpl_v14')::uuid));

-- Reconstrução diagnóstica do MESMO snapshot, para provar proveniência e hash.
select public.commercial_build_instrument_snapshot(
  (:'ord260')::uuid, (:'tpl_qa')::uuid) as r_snap \gset
select tests.check('snapshot persistido coincide com a autoridade server-side',
    ((:'r_snap')::jsonb ->> 'ok') = 'true'
    and (select instrument_snapshot = (:'r_snap')::jsonb -> 'snapshot'
            and instrument_snapshot_hash = (:'r_snap')::jsonb ->> 'snapshot_hash'
           from public.commercial_exclusivity_orders where id = (:'ord260')::uuid));

-- `representative_role_title` é fato material, não dado decorativo. A mesma
-- ordem e o mesmo modelo passam com o cargo canônico e falham quando SÓ esse
-- fato é removido do registro autoritativo.
begin;
update public.partner_application_representatives
   set role_title = null
 where application_id = (:'app260')::uuid and is_current;
select public.commercial_build_instrument_snapshot(
  (:'ord260')::uuid, (:'tpl_qa')::uuid) as r_sem_cargo \gset
select tests.check('cargo do representante ausente falha fechado e nomeia o campo',
    ((:'r_sem_cargo')::jsonb ->> 'reason') = 'instrument_snapshot_material_fact_missing'
    and ((:'r_sem_cargo')::jsonb -> 'missing_fields') ? 'representative_role_title');
rollback;
select tests.check('cargo restaurado torna o mesmo snapshot novamente construivel',
    (public.commercial_build_instrument_snapshot(
       (:'ord260')::uuid, (:'tpl_qa')::uuid) ->> 'ok') = 'true');

-- 5c-pre. O VALOR DA PARTICIPAÇÃO vem da autoridade de economia, não do caller.
select tests.check('participacao de R$ 141,99 vem da autoridade de economia',
    ((:'r_snap')::jsonb -> 'snapshot' ->> 'participation_value_cents')::bigint = 14199
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance'
           ->> 'participation_value_cents') = 'contract_economics_authority');
select tests.check('o valor da participacao esta na agenda da v1.4, nao espalhado',
    (select count(*) = 4 from public.commercial_pricing_schedule
      where pricing_rule_version = 3 and contract_economics_version = 'SF-v1.4'
        and ordinary_participation_value_cents = 14199));
-- A fidelizacao NAO reduz o valor da participacao (clausula 6.7).
select tests.check('fidelizacao nao altera o valor da participacao',
    (select count(distinct ordinary_participation_value_cents) = 1
       from public.commercial_pricing_schedule where pricing_rule_version = 3));
-- 7 participacoes x 141,99 = 993,93 = contraprestacao por MEI completo.
select tests.check('sete participacoes fecham a contraprestacao por MEI',
    7 * 14199 = (public.get_public_formation_economics()
                   ->> 'per_complete_mei_base_cents')::bigint);

-- 5c-nfse. TOMADOR DE NFS-e é o CNPJ da contratante, persistido.
select tests.check('tomador de NFS-e persistido e igual ao CNPJ da contratante',
    (select o.nfse_taker_cnpj = c.cnpj
       from public.commercial_exclusivity_orders o
       join public.site_partner_companies c on c.id = o.company_id
      where o.id = (:'ord260')::uuid));
select tests.check('tomador de NFS-e vem do registro canonico da empresa',
    ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'nfse_taker_cnpj')
      = 'site_company'
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'nfse_taker_cnpj')
      = (select cnpj from public.site_partner_companies where id = (:'comp260')::uuid));
select tests.check_raises('tomador ALTERNATIVO falha fechado na intencao',
  format($sql$insert into public.commercial_checkout_intents
    (company_id, niche_code, status, pricing_rule_version, fidelized,
     benefit_settlement_mode, currency, nominal_quantity, economic_value_cents,
     user_pool_cents, bdflow_ops_investment_cents, created_by, nfse_taker_cnpj)
   values (%L,'mens_clothing','draft',3,false,'direct_benefits','BRL',12,
           1999900,1198800,801100,%L,'11222333000181')$sql$,
         :'comp260', :'uid_t'),
  'alternate_nfse_taker_not_supported');

-- 5c-unidade. UNIDADE DE EXECUÇÃO: da própria empresa, ativa, persistida.
select tests.check('snapshot carrega a unidade de execucao canonica',
    ((:'r_snap')::jsonb -> 'snapshot' ->> 'execution_unit_id') is not null
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'execution_unit_name') is not null
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'execution_unit_city') is not null
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'execution_unit_uf') is not null
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'execution_unit_company_id')::uuid
        = (:'comp260')::uuid
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'execution_unit_id')
        = 'site_unit');
select tests.check('a unidade do snapshot pertence a contratante e esta ativa',
    (select u.company_id = (:'comp260')::uuid and u.status = 'active'
       from public.site_partner_units u
      where u.id = ((:'r_snap')::jsonb -> 'snapshot' ->> 'execution_unit_id')::uuid));

-- Fixture dedicada a ESCOLHA da unidade: empresa propria, DUAS unidades ativas
-- (para que o servidor nao pre-selecione) e intencao em outra exclusividade.
insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg260')::uuid, 262, 'forming', false)
returning id as excl262 \gset
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl262')::uuid, 'pharmacy', 12, 'available');
update public.commercial_exclusivities set is_current = false
 where region_id = (:'reg260')::uuid and is_current;
update public.commercial_exclusivities set is_current = true
 where id = (:'excl262')::uuid;

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('26030003000161','Empresa Unidades 260','unid260@teste.local','Viana','ES')
returning id as app_u \gset
insert into public.partner_application_representatives
  (application_id, full_name, cpf, email, role_title, authority_status,
   is_current, decided_at)
values ((:'app_u')::uuid, 'Representante Unidades 260', '11144477735',
        'repu260@teste.local', 'Socio administrador', 'approved', true,
        now() - interval '2 days');
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
values ((:'app_u')::uuid,'26030003000161','Empresa Unidades 260','Marca U',
        'unid260@teste.local','Viana','ES','active')
returning id as comp_u \gset
select tests.mk_user('titular_u260@teste.local') as uid_tu \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, cpf, source, status)
values ((:'comp_u')::uuid, (:'uid_tu')::uuid, 'partner_owner',
        'Representante Unidades 260', '11144477735', 'application_promotion', 'active');
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp_u')::uuid, 'Unidade U-1', 'Viana', 'ES', 'active')
returning id as unid_u1 \gset
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp_u')::uuid, 'Unidade U-2', 'Viana', 'ES', 'active');

begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.assinar_mestre_qa((:'comp_u')::uuid, 'AM-260U');
commit;

begin;
select tests.impersonate('authenticated', :'uid_tu');
select public.create_commercial_checkout_intent(
  (:'comp_u')::uuid, 'pharmacy', 'direct_benefits') as r_iu \gset
commit;
select tests.check('fixture: intencao criada para a empresa de duas unidades',
    ((:'r_iu')::jsonb ->> 'ok') = 'true');
select ((:'r_iu')::jsonb ->> 'intent_id') as int262 \gset

-- Com DUAS unidades ativas o servidor NAO escolhe: a decisao e do titular.
select tests.check('com duas unidades ativas o servidor NAO pre-seleciona',
    (select execution_unit_id is null from public.commercial_checkout_intents
      where id = (:'int262')::uuid));

begin;
select tests.impersonate('authenticated', :'uid_tu');
select public.set_checkout_intent_execution_unit(
  (:'int262')::uuid, (:'unid_u1')::uuid) as r_sel \gset
select tests.check('titular escolhe a unidade e o servidor valida e persiste',
    ((:'r_sel')::jsonb ->> 'ok') = 'true'
    and ((:'r_sel')::jsonb ->> 'execution_unit_id')::uuid = (:'unid_u1')::uuid);
commit;
select tests.check('a escolha ficou PERSISTIDA na intencao',
    (select execution_unit_id = (:'unid_u1')::uuid
       from public.commercial_checkout_intents where id = (:'int262')::uuid));

-- Unidade de OUTRA empresa e recusada pelo servidor.
insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('26020002000136','Empresa Alheia 260','alheia260@teste.local','Viana','ES')
returning id as app_alheia \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app_alheia')::uuid,'26020002000136','Empresa Alheia 260',
        'alheia260@teste.local','Viana','ES','active')
returning id as comp_alheia \gset
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp_alheia')::uuid, 'Unidade Alheia', 'Viana', 'ES', 'active')
returning id as unid_alheia \gset

begin;
select tests.impersonate('authenticated', :'uid_tu');
select public.set_checkout_intent_execution_unit(
  (:'int262')::uuid, (:'unid_alheia')::uuid) as r_alheia \gset
select tests.check('unidade de OUTRA empresa e recusada',
    ((:'r_alheia')::jsonb ->> 'reason') = 'execution_unit_not_owned_by_company');
rollback;

-- Unidade inativa e recusada.
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp_u')::uuid, 'Unidade Suspensa 260', 'Viana', 'ES', 'suspended')
returning id as unid_inativa \gset
begin;
select tests.impersonate('authenticated', :'uid_tu');
select public.set_checkout_intent_execution_unit(
  (:'int262')::uuid, (:'unid_inativa')::uuid) as r_inativa \gset
select tests.check('unidade SUSPENSA e recusada',
    ((:'r_inativa')::jsonb ->> 'reason') = 'execution_unit_not_active');
rollback;

-- Sem unidade de execucao, o construtor falha fechado.
begin;
update public.commercial_exclusivity_orders
   set execution_unit_id = null where id = (:'ord260')::uuid;
select tests.check('sem unidade de execucao o construtor falha fechado',
    (public.commercial_build_instrument_snapshot(
       (:'ord260')::uuid, (:'tpl_qa')::uuid) ->> 'reason')
      = 'execution_unit_not_selected');
rollback;

-- 5c. A economia do snapshot é exatamente a da SF-v1.4 para nicho comum.
select tests.check('economia do snapshot confere com a SF-v1.4 (nicho comum)',
    ((:'r_snap')::jsonb -> 'snapshot' ->> 'economic_value_cents')::bigint = 1999900
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'mei_consideration_cents')::bigint = 1192716
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'smallflags_qa_cents')::bigint = 6084
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'smallflags_main_fee_cents')::bigint = 801100
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'smallflags_total_remuneration_cents')::bigint = 807184);
select tests.check('economia do snapshot fecha a invariante do pool',
    ((:'r_snap')::jsonb -> 'snapshot' ->> 'mei_consideration_cents')::bigint
    + ((:'r_snap')::jsonb -> 'snapshot' ->> 'smallflags_qa_cents')::bigint
    + ((:'r_snap')::jsonb -> 'snapshot' ->> 'smallflags_main_fee_cents')::bigint
    = ((:'r_snap')::jsonb -> 'snapshot' ->> 'economic_value_cents')::bigint);
select tests.check('snapshot registra o valor de R$ 141,99 por participacao',
    ((:'r_snap')::jsonb -> 'snapshot' ->> 'participation_value_cents')::bigint = 14199);

-- 5d. Proveniência explícita: o que NÃO é canônico fica marcado como tal.
-- PROVENIÊNCIA POR REGISTRO CANÔNICO. Nenhum fato material é mais
-- `caller_supplied`: a entrada arbitrária de chamador deixou de existir.
select tests.check('nenhum fato material e mais caller_supplied',
    (select count(*) = 0
       from jsonb_each_text((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance') p
      where p.value = 'caller_supplied'));
select tests.check('proveniencia nomeia o REGISTRO canonico de cada fato',
    (select count(*) = 0
       from jsonb_each_text((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance') p
      where p.value not in ('site_company','site_unit','site_representative',
                            'contract_economics_authority',
                            'commercial_activity_authority','master_agreement',
                            'legal_acceptance','commercial_order')));
select tests.check('cada familia de fato aponta para a autoridade certa',
    ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'company_cnpj')
      = 'site_company'
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'representative_cpf')
      = 'site_representative'
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'execution_unit_name')
      = 'site_unit'
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'activity_description')
      = 'commercial_activity_authority'
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'master_document_hash')
      = 'master_agreement'
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'acceptance_at')
      = 'legal_acceptance'
    and ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ->> 'order_id')
      = 'commercial_order');
-- TODO fato material exigido pelo modelo tem proveniencia declarada.
select tests.check('todo fato exigido pelo modelo tem proveniencia declarada',
    (select count(*) = 0 from (
       select unnest(required_snapshot_fields) as campo
         from public.commercial_instrument_templates where id = (:'tpl_qa')::uuid) t
      where not ((:'r_snap')::jsonb -> 'snapshot' -> 'field_provenance' ? t.campo)));

-- 5e. Hash do instrumento NUNCA é o hash do modelo.
select tests.check('hash do snapshot NAO e o hash do modelo',
    ((:'r_snap')::jsonb ->> 'snapshot_hash')
      <> ((:'r_snap')::jsonb ->> 'template_source_hash')
    and ((:'r_snap')::jsonb -> 'snapshot' ->> 'instrument_template_source_hash')
      = ((:'r_snap')::jsonb ->> 'template_source_hash'));

-- 5f. Determinismo: mesmos fatos, mesmo hash.
select public.commercial_build_instrument_snapshot(
  (:'ord260')::uuid, (:'tpl_qa')::uuid) as r_snap2 \gset
select tests.check('serializacao canonica e determinista: mesmos fatos, mesmo hash',
    ((:'r_snap')::jsonb ->> 'snapshot_hash')
      = ((:'r_snap2')::jsonb ->> 'snapshot_hash'));

-- 5g. Mudar UM fato material muda o hash. O fato e alterado no REGISTRO
-- CANONICO, nao por JSON: e assim que ele pode mudar de verdade.
begin;
update public.site_partner_units
   set name = 'Unidade 260 RENOMEADA'
 where id = (select execution_unit_id from public.commercial_exclusivity_orders
              where id = (:'ord260')::uuid);
select public.commercial_build_instrument_snapshot(
  (:'ord260')::uuid, (:'tpl_qa')::uuid) as r_snap3 \gset
select tests.check('mudar um fato material canonico muda o hash do snapshot',
    ((:'r_snap3')::jsonb ->> 'snapshot_hash')
      <> ((:'r_snap')::jsonb ->> 'snapshot_hash')
    and ((:'r_snap3')::jsonb -> 'snapshot' ->> 'execution_unit_name')
      = 'Unidade 260 RENOMEADA');
rollback;

-- ---------------------------------------------------------------------------
-- 6. FIDELIDADE — a minuta de primeira compra não rege pedido fidelizado
-- ---------------------------------------------------------------------------
select tests.check('modelo nao fidelizado NAO rege pedido fidelizado',
    (select count(*) = 0 from public.commercial_instrument_templates
      where id = (:'tpl_qa')::uuid and applies_to_fidelized));
-- Pedido fidelizado não encontra modelo assinável algum, porque o único
-- assinável é o do fundador.
select tests.check('nao existe modelo assinavel para condicao FIDELIZADA',
    (public.commercial_signable_instrument_template(true) ->> 'reason')
      = 'commercial_instrument_template_unavailable');

-- ---------------------------------------------------------------------------
-- 7. ATOMICIDADE — pedido v1.4 e instrumento nascem juntos
-- ---------------------------------------------------------------------------
select tests.check('trigger emissor AFTER INSERT existe e esta habilitada',
    (select count(*) = 1 from pg_trigger
      where tgrelid = 'public.commercial_exclusivity_orders'::regclass
        and tgname = 'ceo_emitir_instrumento' and tgenabled <> 'D'));
select tests.check('CHECK de tudo-ou-nada existe',
    (select count(*) from pg_constraint
      where conname = 'ceo_instrumento_completo_ou_ausente') = 1);

-- Segunda exclusividade: a mesma empresa pode contratar outro ciclo comercial.
insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg260')::uuid, 261, 'forming', false)
returning id as excl261 \gset
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl261')::uuid, 'mens_clothing', 12, 'available')
returning id as opp261 \gset

-- 7a. Mesmo DML direto não pode furar o gate quando nenhum modelo está
-- assinável. O archive é revertido pela transação de teste.
begin;
update public.commercial_instrument_templates
   set lifecycle_status = 'archived' where id = (:'tpl_qa')::uuid;
select tests.check('fixture confirma ausencia temporaria de modelo assinavel',
    (public.commercial_signable_instrument_template(false) ->> 'reason')
      = 'commercial_instrument_template_unavailable');
select tests.check_raises('DML direto v1.4 sem modelo signable falha fechado',
  format($sql$
    insert into public.commercial_exclusivity_orders
      (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
       region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
       economic_value_cents, contractual_pool_cents, bdflow_due_cents,
       benefit_settlement_mode, cash_user_pool_funding_cents,
       total_monetary_funding_required_cents, benefit_distribution_policy_version,
       order_version, document_reference, signed_at, signatory_name, status,
       expected_operation_start, exclusivity_period_days, registered_by)
    select %L, %L, o.company_id, o.master_agreement_id, 'mens_clothing',
           o.region_id, 12, 3, false, 'BRL',
           1999900, 1198800, 801100, 'direct_benefits', 0, 807184, 2,
           'v1', 'doc://sem-modelo', now() - interval '1 day', o.signatory_name,
           'signed', current_date + 30, 28, o.registered_by
      from public.commercial_exclusivity_orders o where o.id = %L$sql$,
    :'excl261', :'opp261', :'ord260'),
  'commercial_instrument_template_unavailable');
rollback;

-- 7b. O caller tampouco pode pré-preencher código/snapshot. A individualização
-- é responsabilidade exclusiva do emissor server-side.
select tests.check_raises('caller nao pode pre-preencher instrumento v1.4',
  format($sql$
    insert into public.commercial_exclusivity_orders
      (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
       region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
       economic_value_cents, contractual_pool_cents, bdflow_due_cents,
       benefit_settlement_mode, cash_user_pool_funding_cents,
       total_monetary_funding_required_cents, benefit_distribution_policy_version,
       order_version, document_reference, signed_at, signatory_name, status,
       expected_operation_start, exclusivity_period_days, registered_by,
       instrument_code)
    select %L, %L, o.company_id, o.master_agreement_id, 'mens_clothing',
           o.region_id, 12, 3, false, 'BRL',
           1999900, 1198800, 801100, 'direct_benefits', 0, 807184, 2,
           'v1', 'doc://preenchido-pelo-caller', now() - interval '1 day', o.signatory_name,
           'signed', current_date + 30, 28, o.registered_by, 'SF-9000'
      from public.commercial_exclusivity_orders o where o.id = %L$sql$,
    :'excl261', :'opp261', :'ord260'),
  'instrumento_prepreenchido_nao_permitido');

-- 7c. O INSERT normal vem sem campos instrumentais e a trigger os emite na
-- MESMA transação. Se o AFTER INSERT falhar, o INSERT inteiro é revertido.
insert into public.commercial_exclusivity_orders
  (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
   region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
   economic_value_cents, contractual_pool_cents, bdflow_due_cents,
   benefit_settlement_mode, cash_user_pool_funding_cents,
   total_monetary_funding_required_cents, benefit_distribution_policy_version,
   order_version, document_reference, signed_at, signatory_name, status,
   expected_operation_start, exclusivity_period_days, registered_by)
select (:'excl261')::uuid, (:'opp261')::uuid, o.company_id, o.master_agreement_id,
       'mens_clothing', o.region_id, 12, 3, false, 'BRL',
       1999900, 1198800, 801100, 'direct_benefits', 0, 807184, 2,
       'v1', 'doc://auto-emissao', now() - interval '1 day', o.signatory_name,
       'signed', current_date + 30, 28, o.registered_by
  from public.commercial_exclusivity_orders o where o.id = (:'ord260')::uuid
returning id as ord261 \gset

select tests.check('pedido v1.4 e instrumento nascem atomicamente',
    (select instrument_code ~ '^SF-[0-9]{4,}$'
        and instrument_snapshot_hash ~ '^[0-9a-f]{64}$'
        and instrument_template_id = (:'tpl_qa')::uuid
        and instrument_template_date is not null
        and instrument_snapshot is not null
       from public.commercial_exclusivity_orders where id = (:'ord261')::uuid));
select tests.check('hash do instrumento difere do hash do modelo na linha gravada',
    (select instrument_snapshot_hash <> instrument_template_hash
       from public.commercial_exclusivity_orders where id = (:'ord261')::uuid));

-- ---------------------------------------------------------------------------
-- 8. IMUTABILIDADE depois da emissão
-- ---------------------------------------------------------------------------
select tests.check_raises('snapshot emitido e IMUTAVEL',
  format($sql$update public.commercial_exclusivity_orders
           set instrument_snapshot = '{"adulterado":true}'::jsonb where id = %L$sql$,
         :'ord261'),
  'instrumento assinado e imutavel');
select tests.check_raises('codigo do instrumento emitido e IMUTAVEL',
  format($sql$update public.commercial_exclusivity_orders
           set instrument_code = 'SF-9999' where id = %L$sql$, :'ord261'),
  'instrumento assinado e imutavel');
select tests.check('get_order_instrument encontra snapshot emitido',
    (select instrument_snapshot is not null
       from public.commercial_exclusivity_orders where id = (:'ord261')::uuid));

-- Funções de trigger não são RPCs. Mesmo service_role não precisa executá-las
-- diretamente: a tabela dispara as rotinas sob o owner da função.
select tests.check('funcoes estruturais de instrumento nao sao RPCs executaveis por clientes',
    not has_function_privilege('anon', 'public.ceo_instrumento_imutavel()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.ceo_instrumento_imutavel()', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.ceo_instrumento_imutavel()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.ceo_exigir_instrumento_quando_assinavel()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.ceo_exigir_instrumento_quando_assinavel()', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.ceo_exigir_instrumento_quando_assinavel()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.ceo_emitir_instrumento()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.ceo_emitir_instrumento()', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.ceo_emitir_instrumento()', 'EXECUTE'));

-- ---------------------------------------------------------------------------
-- 9. LIMPEZA — a fixture assinável NÃO pode vazar para as suítes seguintes
--
-- As suítes compartilham o mesmo banco, em sequência. Deixar o modelo de QA
-- `signable` faria toda suíte posterior exigir instrumento nos pedidos dela,
-- que é exatamente o que aconteceu na primeira execução desta suíte: a 910
-- passou a falhar. O modelo é arquivado aqui; a linha continua no banco, para
-- auditoria, apenas sem reger assinatura.
-- ---------------------------------------------------------------------------
update public.commercial_instrument_templates
   set lifecycle_status = 'archived' where id = (:'tpl_qa')::uuid;
-- A atividade de QA tambem e arquivada: aprovacao de QA viva faria as suites
-- seguintes acharem que existe redacao legal aprovada de producao.
select tests.arquivar_atividades_qa();

select tests.check('nenhuma atividade de QA segue aprovada apos a suite',
    (select count(*) from public.commercial_contract_activity_catalog
      where activity_code like 'QA-%' and status = 'approved') = 0);
select tests.check('producao volta a falhar fechada por falta de atividade aprovada',
    (public.commercial_approved_contract_activity('mens_clothing') ->> 'reason')
      = 'commercial_activity_description_unavailable');
select tests.check('fixture de QA arquivada: nao vaza obrigatoriedade adiante',
    (public.commercial_signable_instrument_template(false) ->> 'reason')
      = 'commercial_instrument_template_unavailable'
    and (public.commercial_signable_instrument_template(true) ->> 'reason')
      = 'commercial_instrument_template_unavailable');
select tests.check('a minuta v1.4 real continua em draft, intocada',
    (select lifecycle_status = 'draft' from public.commercial_instrument_templates
      where template_code = 'SF-MINUTA-PRESENCIAL-v1.4'));

select tests.finish('260_commercial_instrument');
