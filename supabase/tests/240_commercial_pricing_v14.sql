-- ============================================================================
-- SUITE 240 — Autoridade econômica v1.4 (P0-3)
--
-- Comportamento REAL no PostgreSQL, não asserção sobre o texto da migration.
--
-- Fonte congelada: contratos v1.4, SHA-256
-- 03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73,
-- conferido contra o manifesto oficial.
-- ============================================================================

select tests.reset_results();

-- ---------------------------------------------------------------------------
-- 1. Os quatro casos congelados, centavo a centavo
-- ---------------------------------------------------------------------------
select tests.check('v1.4 supermercado nao fidelizado',
  (select (p->>'economic_value_cents')::bigint = 2999900
      and (p->>'mei_consideration_cents')::bigint = 2385432
      and (p->>'smallflags_qa_cents')::bigint = 12168
      and (p->>'smallflags_main_fee_cents')::bigint = 602300
      and (p->>'smallflags_total_remuneration_cents')::bigint = 614468
   from (select public.calculate_niche_contract_pricing('supermarket', false) as p) x));

select tests.check('v1.4 nicho comum nao fidelizado',
  (select (p->>'economic_value_cents')::bigint = 1999900
      and (p->>'mei_consideration_cents')::bigint = 1192716
      and (p->>'smallflags_qa_cents')::bigint = 6084
      and (p->>'smallflags_main_fee_cents')::bigint = 801100
      and (p->>'smallflags_total_remuneration_cents')::bigint = 807184
   from (select public.calculate_niche_contract_pricing('pharmacy', false) as p) x));

select tests.check('v1.4 supermercado fidelizado',
  (select (p->>'economic_value_cents')::bigint = 2817600
      and (p->>'mei_consideration_cents')::bigint = 2385432
      and (p->>'smallflags_qa_cents')::bigint = 12168
      and (p->>'smallflags_main_fee_cents')::bigint = 420000
      and (p->>'smallflags_total_remuneration_cents')::bigint = 432168
   from (select public.calculate_niche_contract_pricing('supermarket', true) as p) x));

select tests.check('v1.4 nicho comum fidelizado',
  (select (p->>'economic_value_cents')::bigint = 1618800
      and (p->>'mei_consideration_cents')::bigint = 1192716
      and (p->>'smallflags_qa_cents')::bigint = 6084
      and (p->>'smallflags_main_fee_cents')::bigint = 420000
      and (p->>'smallflags_total_remuneration_cents')::bigint = 426084
   from (select public.calculate_niche_contract_pricing('pharmacy', true) as p) x));

-- ---------------------------------------------------------------------------
-- 2. Invariantes nos doze pares nicho × fidelidade
-- ---------------------------------------------------------------------------
select tests.check('economico = MEI + QA + parcela principal, nos 12 casos',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'economic_value_cents')::bigint
          = (p->>'mei_consideration_cents')::bigint
          + (p->>'smallflags_qa_cents')::bigint
          + (p->>'smallflags_main_fee_cents')::bigint));

select tests.check('remuneracao SmallFlags = QA + parcela principal, nos 12 casos',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'smallflags_total_remuneration_cents')::bigint
          = (p->>'smallflags_qa_cents')::bigint + (p->>'smallflags_main_fee_cents')::bigint));

-- Compatibilidade do snapshot herdado.
select tests.check('economico = pool + bdflow_due continua valendo sob v1.4',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'economic_value_cents')::bigint
          = (p->>'contractual_pool_cents')::bigint + (p->>'bdflow_due_cents')::bigint
      and (p->>'contractual_pool_cents')::bigint
          = (p->>'mei_consideration_cents')::bigint + (p->>'smallflags_qa_cents')::bigint));

-- A QA NUNCA é contraprestação do MEI.
select tests.check('QA nunca e absorvida pela contraprestacao do MEI',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'smallflags_qa_cents')::bigint > 0
      and (p->>'mei_consideration_cents')::bigint
          <> (p->>'contractual_pool_cents')::bigint));

-- P0-A: a mesma autoridade publica a parcela entregavel e a cobrança das duas
-- modalidades. A UI não precisa (nem pode) reconstruir esses valores.
select tests.check('P0-A: beneficio entregavel = MEI nos 12 casos v1.4',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'direct_benefit_deliverable_cents')::bigint
          = (p->>'mei_consideration_cents')::bigint));

select tests.check('P0-A: cobranca em beneficio direto = remuneracao total SmallFlags',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'funding_direct_benefits_cents')::bigint
          = (p->>'smallflags_total_remuneration_cents')::bigint));

select tests.check('P0-A: cobranca em dinheiro = economico nos 12 casos v1.4',
  (select count(*) = 12 from public.commercial_niches n
     cross join (values(false),(true)) f(fid)
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, f.fid) as p) c
    where n.is_active
      and (p->>'funding_cash_cents')::bigint
          = (p->>'economic_value_cents')::bigint));

-- ---------------------------------------------------------------------------
-- 3. Os seis nichos canônicos e sua categoria de preço
-- ---------------------------------------------------------------------------
select tests.check('exatamente seis nichos canonicos ativos',
  (select count(*) from public.commercial_niches where is_active) = 6);

select tests.check('os seis codigos canonicos sao exatamente os esperados',
  (select array_agg(code order by code) from public.commercial_niches where is_active)
  = array['mens_clothing','mens_footwear','pharmacy','supermarket',
          'womens_clothing','womens_footwear']::text[]);

select tests.check('supermarket resolve para a matriz supermarket, 24 unidades',
  (select (p->>'niche_category') = 'supermarket'
      and (p->>'nominal_quantity')::int = 24
   from (select public.calculate_niche_contract_pricing('supermarket', false) as p) x));

select tests.check('os outros cinco resolvem para a matriz common, 12 unidades',
  (select count(*) = 5 from public.commercial_niches n
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, false) as p) c
    where n.is_active and n.code <> 'supermarket'
      and (p->>'niche_category') = 'common'
      and (p->>'nominal_quantity')::int = 12));

select tests.check('formacao soma 84 unidades em seis posicoes',
  (select sum(contracted_quantity) = 84 and count(*) = 6
     from public.commercial_niches where is_active));

-- Totais conferidos contra o memorando fiscal v0.6.
select tests.check('formacao nao fidelizada: MEIs 83.490,12 e QA 425,88',
  (select sum((p->>'mei_consideration_cents')::bigint) = 8349012
      and sum((p->>'smallflags_qa_cents')::bigint) = 42588
     from public.commercial_niches n
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, false) as p) c
    where n.is_active));

select tests.check('remuneracao SmallFlags: 46.503,88 nao fidelizada / 25.625,88 fidelizada',
  (select sum((p0->>'smallflags_total_remuneration_cents')::bigint) = 4650388
      and sum((p1->>'smallflags_total_remuneration_cents')::bigint) = 2562588
     from public.commercial_niches n
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, false) as p0) a
     cross join lateral (select public.calculate_niche_contract_pricing(n.code, true)  as p1) b
    where n.is_active));

-- ---------------------------------------------------------------------------
-- 4. Linhagem de versão: pricing_rule_version, não uma segunda coluna
-- ---------------------------------------------------------------------------
select tests.check('a versao tecnica e pricing_rule_version = 3',
  (select (p->>'pricing_rule_version')::int = 3
   from (select public.calculate_niche_contract_pricing('supermarket', false) as p) x));

select tests.check('o rotulo legal e contract_economics_version = SF-v1.4',
  (select (p->>'contract_economics_version') = 'SF-v1.4'
   from (select public.calculate_niche_contract_pricing('supermarket', false) as p) x));

select tests.check('NAO existe uma segunda coluna generica pricing_version',
  not exists (select 1 from information_schema.columns
               where table_schema='public' and column_name='pricing_version'));

select tests.check('a autoridade e indexada por pricing_rule_version',
  exists (select 1 from information_schema.columns
           where table_schema='public' and table_name='commercial_pricing_schedule'
             and column_name='pricing_rule_version'));

-- ---------------------------------------------------------------------------
-- 5. As oito combinações de liquidação, resolvidas pelo servidor
-- ---------------------------------------------------------------------------
-- Insere pedidos com a decomposição DELIBERADAMENTE em branco: o trigger de
-- autoridade preenche tudo. É assim que se prova que existe uma única fonte.
-- ---------------------------------------------------------------------------
do $fix240$
declare
  v_region uuid; v_excl uuid; v_comp uuid; v_app uuid;
  v_admin uuid; v_agree uuid;
begin
  select id into v_region from public.commercial_regions limit 1;
  if v_region is null then
    insert into public.commercial_regions (name, uf, status)
    values ('Regiao 240 QA', 'ES', 'active') returning id into v_region;
  end if;

  select id into v_excl from public.commercial_exclusivities
   where region_id = v_region and sequence_number = 9240;
  if v_excl is null then
    insert into public.commercial_exclusivities (region_id, sequence_number, status)
    values (v_region, 9240, 'forming') returning id into v_excl;
  end if;

  select id into v_comp from public.site_partner_companies where cnpj = '70000000900089';
  if v_comp is null then
    -- source_application_id tem FK: a candidatura precisa existir antes.
    insert into public.partner_applications
      (legal_name, cnpj, contact_email, city, uf)
    values ('Empresa 240 QA LTDA', '70000000900089', 'qa240@teste.local',
            'Vitoria', 'ES')
    returning id into v_app;

    insert into public.site_partner_companies
      (source_application_id, legal_name, trade_name, cnpj,
       contact_email, city, uf, status)
    values (v_app, 'Empresa 240 QA LTDA', 'Empresa 240 QA',
            '70000000900089', 'qa240@teste.local', 'Vitoria', 'ES', 'active')
    returning id into v_comp;
  end if;

  -- Acordo mestre e admin: o pedido exige ambos.
  select user_id into v_admin from public.site_admins order by created_at limit 1;
  if v_admin is null then
    insert into auth.users (id, email) values (gen_random_uuid(), 'admin240@teste.local')
    returning id into v_admin;
    insert into public.site_admins (user_id) values (v_admin);
  end if;
  perform set_config('request.jwt.claims',
      json_build_object('role','authenticated','sub',v_admin)::text, true);

  select id into v_agree from public.commercial_master_agreements
   where company_id = v_comp and status = 'signed';
  if v_agree is null then
    perform tests.assinar_mestre_qa(v_comp, 'AM-240', now() - interval '1 day',
                                    'Titular 240', 'doc://acordo-240');
    select id into v_agree from public.commercial_master_agreements
     where company_id = v_comp and status = 'signed';
  end if;
  perform set_config('request.jwt.claims', null, true);

  -- Uma oportunidade por nicho exercitado. opportunity_id e UNIQUE, mas cada
  -- caso roda em transacao propria com rollback, entao a reutilizacao e segura.
  insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity)
  select v_excl, n.code, n.contracted_quantity from public.commercial_niches n
   where n.is_active and n.code in ('supermarket','pharmacy')
     and not exists (select 1 from public.commercial_opportunities o
                      where o.exclusivity_id = v_excl and o.niche_code = n.code);

  perform set_config('tests.excl240', v_excl::text, false);
  perform set_config('tests.comp240', v_comp::text, false);
  perform set_config('tests.region240', v_region::text, false);
  perform set_config('tests.agree240', v_agree::text, false);
  perform set_config('tests.admin240', v_admin::text, false);
end
$fix240$;

-- Insere SEM decomposição e devolve o que o servidor resolveu.
create or replace function pg_temp.pedido_v14(
  p_niche text, p_fid boolean, p_mode text
) returns jsonb language plpgsql as $fn$
declare v_o public.commercial_exclusivity_orders%rowtype;
begin
  insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id,
     niche_code, nominal_quantity, fidelized, status, expected_operation_start,
     registered_by, pricing_rule_version, benefit_settlement_mode,
     economic_value_cents, contractual_pool_cents, bdflow_due_cents)
  values
    (current_setting('tests.excl240')::uuid,
     (select id from public.commercial_opportunities
       where exclusivity_id = current_setting('tests.excl240')::uuid
         and niche_code = p_niche),
     current_setting('tests.comp240')::uuid,
     current_setting('tests.agree240')::uuid,
     current_setting('tests.region240')::uuid,
     p_niche,
     (select contracted_quantity from public.commercial_niches where code = p_niche),
     p_fid, 'draft', (now() + interval '30 days')::date,
     current_setting('tests.admin240')::uuid, 3, p_mode,
     -- Valores propositalmente ERRADOS: o trigger os substitui pela autoridade.
     1, 1, 0)
  returning * into v_o;
  return jsonb_build_object(
    'economic', v_o.economic_value_cents,
    'mei', v_o.mei_consideration_cents,
    'qa', v_o.smallflags_qa_cents,
    'main', v_o.smallflags_main_fee_cents,
    'remun', v_o.smallflags_total_remuneration_cents,
    'mei_cash', v_o.mei_cash_funding_cents,
    'total_funding', v_o.total_monetary_funding_required_cents,
    'economics_version', v_o.contract_economics_version);
end $fn$;

-- P0-A: previsão pública e linha persistida são caminhos independentes. A
-- primeira vem de calculate_niche_contract_pricing; a segunda já passou pelos
-- triggers e CHECKs do pedido. Divergirem é regressão de autoridade.
begin;
select tests.check('P0-A: previsao direto supermercado coincide com pedido persistido',
  (select (p->>'funding_direct_benefits_cents')::bigint = (r->>'total_funding')::bigint
     from (select public.calculate_niche_contract_pricing('supermarket', false) p,
                  pg_temp.pedido_v14('supermarket', false, 'direct_benefits') r) x));
rollback;

begin;
select tests.check('P0-A: previsao dinheiro supermercado coincide com pedido persistido',
  (select (p->>'funding_cash_cents')::bigint = (r->>'total_funding')::bigint
     from (select public.calculate_niche_contract_pricing('supermarket', false) p,
                  pg_temp.pedido_v14('supermarket', false, 'cash') r) x));
rollback;

begin;
select tests.check('P0-A: previsao direto nicho comum coincide com pedido persistido',
  (select (p->>'funding_direct_benefits_cents')::bigint = (r->>'total_funding')::bigint
     from (select public.calculate_niche_contract_pricing('pharmacy', false) p,
                  pg_temp.pedido_v14('pharmacy', false, 'direct_benefits') r) x));
rollback;

begin;
select tests.check('P0-A: previsao dinheiro nicho comum coincide com pedido persistido',
  (select (p->>'funding_cash_cents')::bigint = (r->>'total_funding')::bigint
     from (select public.calculate_niche_contract_pricing('pharmacy', false) p,
                  pg_temp.pedido_v14('pharmacy', false, 'cash') r) x));
rollback;

-- BENEFÍCIO DIRETO: dinheiro à SmallFlags = remuneração total (QA inclusa).
begin;
select tests.check('direto, super nao fid: exige 614.468 em dinheiro, MEI zero',
  (select (r->>'total_funding')::bigint = 614468 and (r->>'mei_cash')::bigint = 0
      and (r->>'economic')::bigint = 2999900 and (r->>'economics_version') = 'SF-v1.4'
   from (select pg_temp.pedido_v14('supermarket', false, 'direct_benefits') as r) x));
rollback;

begin;
select tests.check('direto, comum nao fid: exige 807.184 em dinheiro, MEI zero',
  (select (r->>'total_funding')::bigint = 807184 and (r->>'mei_cash')::bigint = 0
   from (select pg_temp.pedido_v14('pharmacy', false, 'direct_benefits') as r) x));
rollback;

begin;
select tests.check('direto, super fid: exige 432.168 em dinheiro, MEI zero',
  (select (r->>'total_funding')::bigint = 432168 and (r->>'mei_cash')::bigint = 0
   from (select pg_temp.pedido_v14('supermarket', true, 'direct_benefits') as r) x));
rollback;

begin;
select tests.check('direto, comum fid: exige 426.084 em dinheiro, MEI zero',
  (select (r->>'total_funding')::bigint = 426084 and (r->>'mei_cash')::bigint = 0
   from (select pg_temp.pedido_v14('pharmacy', true, 'direct_benefits') as r) x));
rollback;

-- DINHEIRO: a parceira paga o econômico integral.
begin;
select tests.check('dinheiro, super nao fid: 2.999.900 integral, MEI 2.385.432',
  (select (r->>'total_funding')::bigint = 2999900
      and (r->>'mei_cash')::bigint = 2385432
   from (select pg_temp.pedido_v14('supermarket', false, 'cash') as r) x));
rollback;

begin;
select tests.check('dinheiro, comum nao fid: 1.999.900 integral, MEI 1.192.716',
  (select (r->>'total_funding')::bigint = 1999900
      and (r->>'mei_cash')::bigint = 1192716
   from (select pg_temp.pedido_v14('pharmacy', false, 'cash') as r) x));
rollback;

begin;
select tests.check('dinheiro, super fid: 2.817.600 integral',
  (select (r->>'total_funding')::bigint = 2817600
      and (r->>'mei_cash')::bigint = 2385432
   from (select pg_temp.pedido_v14('supermarket', true, 'cash') as r) x));
rollback;

begin;
select tests.check('dinheiro, comum fid: 1.618.800 integral',
  (select (r->>'total_funding')::bigint = 1618800
      and (r->>'mei_cash')::bigint = 1192716
   from (select pg_temp.pedido_v14('pharmacy', true, 'cash') as r) x));
rollback;

-- O ponto que o operador destacou: a QA nunca vira financiamento do MEI.
begin;
select tests.check('em dinheiro, o financiamento do MEI exclui a QA',
  (select (r->>'mei_cash')::bigint = (r->>'mei')::bigint
      and (r->>'mei_cash')::bigint
          <> (r->>'mei')::bigint + (r->>'qa')::bigint
   from (select pg_temp.pedido_v14('supermarket', false, 'cash') as r) x));
rollback;

begin;
select tests.check('em beneficio direto, o dinheiro exigido INCLUI a QA',
  (select (r->>'total_funding')::bigint
          = (r->>'main')::bigint + (r->>'qa')::bigint
      and (r->>'total_funding')::bigint > (r->>'main')::bigint
   from (select pg_temp.pedido_v14('supermarket', false, 'direct_benefits') as r) x));
rollback;

-- ---------------------------------------------------------------------------
-- 6. Caminhos negativos
-- ---------------------------------------------------------------------------
create or replace function pg_temp.tentar_incoerente(
  p_mode text, p_mei bigint, p_qa bigint, p_main bigint,
  p_mei_cash bigint, p_pool bigint, p_total bigint
) returns text language plpgsql as $fn$
declare v_msg text;
begin
  begin
    insert into public.commercial_exclusivity_orders
      (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id,
       niche_code, nominal_quantity, fidelized, status, expected_operation_start,
       registered_by, pricing_rule_version, contract_economics_version,
       benefit_settlement_mode,
       economic_value_cents, contractual_pool_cents, bdflow_due_cents,
       mei_consideration_cents, smallflags_qa_cents, smallflags_main_fee_cents,
       smallflags_total_remuneration_cents, mei_cash_funding_cents,
       cash_user_pool_funding_cents, total_monetary_funding_required_cents)
    values
      (current_setting('tests.excl240')::uuid,
       (select id from public.commercial_opportunities
         where exclusivity_id = current_setting('tests.excl240')::uuid
           and niche_code = 'supermarket'),
       current_setting('tests.comp240')::uuid,
       current_setting('tests.agree240')::uuid,
       current_setting('tests.region240')::uuid,
       'supermarket', 24, false, 'draft', (now() + interval '30 days')::date,
       current_setting('tests.admin240')::uuid, 3, 'SF-v1.4', p_mode,
       p_mei + p_qa + p_main, p_pool, p_main,
       p_mei, p_qa, p_main, p_qa + p_main, p_mei_cash, p_pool, p_total);
    return 'aceito';
  exception when check_violation then
    get stacked diagnostics v_msg = constraint_name;
    return 'recusado:' || coalesce(v_msg, '?');
  end;
end $fn$;

begin;
select tests.check('beneficio direto SEM a QA no dinheiro e recusado',
  pg_temp.tentar_incoerente('direct_benefits', 2385432, 12168, 602300, 0, 2397600, 602300)
  = 'recusado:ceo_financiamento_v14_coerente');
rollback;

begin;
select tests.check('dinheiro com a QA somada ao financiamento do MEI e recusado',
  pg_temp.tentar_incoerente('cash', 2385432, 12168, 602300, 2397600, 2397600, 2999900)
  = 'recusado:ceo_financiamento_v14_coerente');
rollback;

begin;
select tests.check('dinheiro com total menor que o economico e recusado',
  pg_temp.tentar_incoerente('cash', 2385432, 12168, 602300, 2385432, 2397600, 2397600)
  = 'recusado:ceo_financiamento_v14_coerente');
rollback;

-- ---------------------------------------------------------------------------
-- 7. Imutabilidade do snapshot econômico
-- ---------------------------------------------------------------------------
begin;
select pg_temp.pedido_v14('supermarket', false, 'cash');
select id as oid240 from public.commercial_exclusivity_orders
 where company_id = current_setting('tests.comp240')::uuid
 order by created_at desc limit 1 \gset

select tests.check_raises('snapshot v1.4 e imutavel apos criado',
  format($sql$update public.commercial_exclusivity_orders
                  set mei_consideration_cents = 1
                where id = %L$sql$, :'oid240'),
  'snapshot economico v1.4 e imutavel');

select tests.check_raises('rotulo legal tambem e imutavel',
  format($sql$update public.commercial_exclusivity_orders
                  set contract_economics_version = 'OUTRA'
                where id = %L$sql$, :'oid240'),
  'snapshot economico v1.4 e imutavel');
rollback;

-- ---------------------------------------------------------------------------
-- 8. V1 e V2 continuam reproduzíveis; nada é reprecificado
-- ---------------------------------------------------------------------------
select tests.check('V1 reproduz seus proprios valores (super nao fid)',
  (select (p->>'economic_value_cents')::bigint = 3558700
      and (p->>'contractual_pool_cents')::bigint = 2669025
      and (p->>'pool_precision_model') = 'basis_points'
   from (select public.calculate_niche_contract_pricing('supermarket', false, 1) as p) x));

select tests.check('V2 reproduz seus proprios valores (super nao fid)',
  (select (p->>'economic_value_cents')::bigint = 3558700
      and (p->>'contractual_pool_cents')::bigint = 2554305
      and (p->>'pool_precision_model') = 'exact_ratio'
   from (select public.calculate_niche_contract_pricing('supermarket', false, 2) as p) x));

select tests.check('V2 fidelizado reproduz 3.117.600, diferente da v1.4',
  (select (p->>'economic_value_cents')::bigint = 3117600
   from (select public.calculate_niche_contract_pricing('supermarket', true, 2) as p) x));

select tests.check('V1/V2 nao ganham campos v1.4',
  (select (p->'mei_consideration_cents') is null
      and (p->'contract_economics_version') is null
   from (select public.calculate_niche_contract_pricing('supermarket', false, 2) as p) x));

select tests.check('P0-A: V1/V2 preservam semantica historica de financiamento',
  (select (p->>'direct_benefit_deliverable_cents')::bigint
            = (p->>'contractual_pool_cents')::bigint
      and (p->>'funding_direct_benefits_cents')::bigint
            = (p->>'bdflow_due_cents')::bigint
      and (p->>'funding_cash_cents')::bigint
            = (p->>'economic_value_cents')::bigint
   from (select public.calculate_niche_contract_pricing('supermarket', false, 2) as p) x));

select tests.check('a versao ativa e a 3; 1 e 2 ficam superseded',
  (select count(*) = 1 from public.commercial_pricing_rules
     where status = 'active' and version = 3 and pool_precision_model = 'explicit_schedule')
  and (select count(*) = 2 from public.commercial_pricing_rules
         where status = 'superseded' and version in (1, 2)));

select tests.check('sem versao explicita, resolve pela autoridade ativa v1.4',
  (select (p->>'pricing_rule_version')::int = 3
      and (p->>'pool_precision_model') = 'explicit_schedule'
   from (select public.calculate_niche_contract_pricing('supermarket', false) as p) x));

-- Pedidos V1/V2 preexistentes: nem reprecificados nem invalidados.
select tests.check('pedidos historicos continuam sem campos v1.4',
  (select count(*) = 0 from public.commercial_exclusivity_orders
     where pricing_rule_version < 3 and contract_economics_version is not null));

select tests.check('o CHECK V2 passou a declarar sua faixa de versao',
  (select pg_get_constraintdef(oid) like '%pricing_rule_version%'
     from pg_constraint where conname = 'ceo_financiamento_v2_coerente'));

-- ---------------------------------------------------------------------------
-- 9. A autoridade não é legível nem gravável pelo navegador
-- ---------------------------------------------------------------------------
select tests.check('schedule nao e legivel por anon nem authenticated',
  not has_table_privilege('anon', 'public.commercial_pricing_schedule', 'SELECT')
  and not has_table_privilege('authenticated', 'public.commercial_pricing_schedule', 'SELECT'));

select tests.check('schedule nao e gravavel por authenticated',
  not has_table_privilege('authenticated', 'public.commercial_pricing_schedule', 'INSERT')
  and not has_table_privilege('authenticated', 'public.commercial_pricing_schedule', 'UPDATE'));

select tests.check('quatro linhas de preco na versao 3',
  (select count(*) = 4 from public.commercial_pricing_schedule where pricing_rule_version = 3));

-- ===========================================================================
-- SEMANTICA DO POOL — a parcela QA NAO e dinheiro do usuario/MEI
--
-- Sob a SF-v1.4 contractual_pool_cents = mei_consideration_cents +
-- smallflags_qa_cents, e a parcela QA pertence a SmallFlags. As superficies que
-- carregam SIGNIFICADO tem de expor a decomposicao, e o valor por participante
-- tem de derivar da contraprestacao dos MEIs — nao do pool inteiro.
-- ===========================================================================
select public.get_public_formation_economics() as vitrine \gset

select tests.check('vitrine: decomposicao da formacao fundadora completa',
    ((:'vitrine')::jsonb ->> 'mei_consideration_cents')::bigint = 8349012
    and ((:'vitrine')::jsonb ->> 'smallflags_qa_cents')::bigint = 42588
    and ((:'vitrine')::jsonb ->> 'user_pool_cents')::bigint = 8391600);
select tests.check('vitrine: as duas parcelas somam exatamente o pool',
    ((:'vitrine')::jsonb ->> 'mei_consideration_cents')::bigint
    + ((:'vitrine')::jsonb ->> 'smallflags_qa_cents')::bigint
    = ((:'vitrine')::jsonb ->> 'user_pool_cents')::bigint);
-- 8.349.012 / 84 = 99.393, exato. O valor derivado do pool seria 99.900 e
-- superdeclararia 507 centavos por participante.
select tests.check('vitrine: valor por MEI deriva da contraprestacao, nao do pool',
    ((:'vitrine')::jsonb ->> 'per_complete_mei_base_cents')::bigint = 99393
    and ((:'vitrine')::jsonb ->> 'mei_remainder_cents')::bigint = 0
    and ((:'vitrine')::jsonb ->> 'per_complete_mei_base_cents')::bigint
        <> ((:'vitrine')::jsonb ->> 'per_complete_user_base_cents')::bigint);
select tests.check('vitrine: campo de compatibilidade preservado sem mudanca',
    ((:'vitrine')::jsonb ->> 'per_complete_user_base_cents')::bigint = 99900
    and ((:'vitrine')::jsonb ->> 'pool_remainder_cents')::bigint = 0);
select tests.check('vitrine: carimba o rotulo legal da economia ativa',
    ((:'vitrine')::jsonb ->> 'contract_economics_version') = 'SF-v1.4'
    and ((:'vitrine')::jsonb ->> 'pricing_rule_version')::int = 3);

-- A autoridade por nicho tambem expoe a decomposicao, e ela fecha.
select tests.check('autoridade ativa: decomposicao coerente em todos os nichos',
    (select count(*) from public.commercial_niches n
      cross join (values (false),(true)) f(fid)
      cross join lateral public.calculate_niche_contract_pricing(n.code, f.fid) r
     where n.is_active
       and not (
         (r->>'mei_consideration_cents')::bigint + (r->>'smallflags_qa_cents')::bigint
           = (r->>'contractual_pool_cents')::bigint
         and (r->>'smallflags_total_remuneration_cents')::bigint
           = (r->>'smallflags_main_fee_cents')::bigint + (r->>'smallflags_qa_cents')::bigint
         and (r->>'bdflow_due_cents')::bigint = (r->>'smallflags_main_fee_cents')::bigint)) = 0);

-- HISTORICO: V1 e V2 nao tinham parcela QA. A decomposicao NAO e afirmada la —
-- fingir mei = pool e qa = 0 inventaria um fato que nao existia.
select tests.check('V1/V2 historicas nao afirmam decomposicao de pool',
    (public.calculate_niche_contract_pricing('supermarket', false, 1)
       ->> 'mei_consideration_cents') is null
    and (public.calculate_niche_contract_pricing('supermarket', false, 2)
       ->> 'smallflags_qa_cents') is null);

select tests.finish('240_commercial_pricing_v14');
