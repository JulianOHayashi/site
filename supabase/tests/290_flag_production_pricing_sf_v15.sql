-- ===========================================================================
-- 290 — SF-v1.5: precificação com produção de bandeiras e reutilização por
-- fidelização. Migration 20261112120000.
--
-- Prova no BANCO:
--   * SF-v1.4 vigente e intacta; SF-v1.5 só preparada, não consultável;
--   * agenda e regras protegidas (nem o service_role nem o dono reescrevem
--     centavos publicados);
--   * não fidelizado: 84 bandeiras (não 24/12), R$ 35,00 × 84 = R$ 2.940,00,
--     somado UMA vez, sem tocar MEI, QA ou participação;
--   * fidelizado: só com conjunto do mesmo anunciante inspecionado e
--     reutilizável; cada reutilização consome uma inspeção; reposição sem
--     política aprovada não reserva nem gera preço;
--   * cenários mistos 504 / 0 / 84 / 252 somando os PEDIDOS efetivos;
--   * modalidades direct_benefits e cash separadas;
--   * fatos de produção imutáveis no pedido, copiados da reserva e levados ao
--     instrumento V2.
--
-- Tudo roda numa transação REVERTIDA: a ativação da v4 e as fixtures não
-- vazam para as demais suítes. As linhas PASS/FAIL impressas são a evidência.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- 0. Estado de partida (fora da transação: confirmado e registrado)
-- ---------------------------------------------------------------------------
select tests.check('SF-v1.4 (versao 3) e a regra vigente; SF-v1.5 (versao 4) so preparada',
    (select status from public.commercial_pricing_rules where version = 3) = 'active'
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared');
select tests.check('agenda SF-v1.4 historica intacta, centavo a centavo',
    (select string_agg(format('%s/%s/%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
            economic_value_cents, mei_consideration_cents, smallflags_qa_cents,
            smallflags_main_fee_cents, smallflags_total_remuneration_cents,
            ordinary_participation_value_cents), ';' order by commercial_category, fidelized)
       from public.commercial_pricing_schedule where pricing_rule_version = 3)
    = 'common/false/1999900/1192716/6084/801100/807184/14199;'
      'common/true/1618800/1192716/6084/420000/426084/14199;'
      'supermarket/false/2999900/2385432/12168/602300/614468/14199;'
      'supermarket/true/2817600/2385432/12168/420000/432168/14199');
select tests.check('SF-v1.4 nao ganhou fatos de bandeira (nada inventado para ela)',
    not exists (select 1 from public.commercial_pricing_schedule
                 where pricing_rule_version = 3
                   and (new_flag_units is not null or flag_unit_reference_cents is not null
                        or flag_production_charge_cents is not null)));
select tests.check('preco vigente continua SF-v1.4 e sem chaves de bandeira',
    (select (p->>'economic_value_cents')::bigint = 2999900
            and p->>'contract_economics_version' = 'SF-v1.4'
            and not (p ? 'new_flag_units') and not (p ? 'flag_production_charge_cents')
       from (select public.calculate_niche_contract_pricing('supermarket', false) p) x));
select tests.check('versao preparada nao e consultavel nem por versao explicita',
    (public.calculate_niche_contract_pricing('supermarket', false, 4) ->> 'reason')
      = 'pricing_rule_not_published'
    and (public.calculate_niche_contract_pricing('pharmacy', true, 4) ->> 'reason')
      = 'pricing_rule_not_published');

-- ---------------------------------------------------------------------------
-- 1. Agenda SF-v1.5 (preparada)
-- ---------------------------------------------------------------------------
select tests.check('SF-v1.5 nao fidelizado: supermercado 32.939,00 e comum 22.939,00',
    (select economic_value_cents from public.commercial_pricing_schedule
      where pricing_rule_version = 4 and commercial_category = 'supermarket' and not fidelized) = 3293900
    and (select economic_value_cents from public.commercial_pricing_schedule
      where pricing_rule_version = 4 and commercial_category = 'common' and not fidelized) = 2293900);
select tests.check('SF-v1.5 fidelizado com reutilizacao: supermercado 28.176,00 e comum 16.188,00',
    (select economic_value_cents from public.commercial_pricing_schedule
      where pricing_rule_version = 4 and commercial_category = 'supermarket' and fidelized) = 2817600
    and (select economic_value_cents from public.commercial_pricing_schedule
      where pricing_rule_version = 4 and commercial_category = 'common' and fidelized) = 1618800);
select tests.check('R$ 35,00 x 84 = R$ 2.940,00 (adicional do nao fidelizado)',
    (select bool_and(flag_unit_reference_cents = 3500 and new_flag_units = 84
                     and flag_production_charge_cents = 294000
                     and flag_unit_reference_cents * 84 = 294000)
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and not fidelized));
select tests.check('R$ 35,00 x 504 = R$ 17.640,00 (seis anunciantes novos)',
    (select max(flag_unit_reference_cents) * 504 = 1764000
            and max(new_flag_units) * 6 = 504
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and not fidelized));
select tests.check('84 bandeiras NAO e contracted_quantity: 84 para supermercado (24) e para as de 12',
    (select new_flag_units from public.commercial_pricing_schedule
      where pricing_rule_version = 4 and commercial_category = 'supermarket' and not fidelized) = 84
    and (select contracted_quantity from public.commercial_niches where code = 'supermarket') = 24
    and (select new_flag_units from public.commercial_pricing_schedule
      where pricing_rule_version = 4 and commercial_category = 'common' and not fidelized) = 84
    and (select bool_and(contracted_quantity = 12) from public.commercial_niches
          where is_active and code <> 'supermarket'));
select tests.check('fidelizado SF-v1.5: zero pecas novas e adicional zero',
    (select bool_and(new_flag_units = 0 and flag_production_charge_cents = 0)
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and fidelized));
select tests.check('adicional entra UMA vez: SF-v1.5 - SF-v1.4 = 294.000 no nao fidelizado',
    (select bool_and(n.economic_value_cents - o.economic_value_cents = n.flag_production_charge_cents
                     and n.smallflags_main_fee_cents - n.flag_production_charge_cents
                         = o.smallflags_main_fee_cents)
       from public.commercial_pricing_schedule n
       join public.commercial_pricing_schedule o
         on o.pricing_rule_version = 3 and o.commercial_category = n.commercial_category
        and o.fidelized = n.fidelized
      where n.pricing_rule_version = 4 and not n.fidelized));
select tests.check('fidelizado SF-v1.5 = fidelizado SF-v1.4 em todos os componentes',
    (select bool_and(n.economic_value_cents = o.economic_value_cents
                     and n.smallflags_main_fee_cents = o.smallflags_main_fee_cents
                     and n.smallflags_total_remuneration_cents = o.smallflags_total_remuneration_cents)
       from public.commercial_pricing_schedule n
       join public.commercial_pricing_schedule o
         on o.pricing_rule_version = 3 and o.commercial_category = n.commercial_category
        and o.fidelized = n.fidelized
      where n.pricing_rule_version = 4 and n.fidelized));
select tests.check('MEI, QA e participacao (R$ 141,99) identicos a SF-v1.4: nada financia bandeira',
    (select bool_and(n.mei_consideration_cents = o.mei_consideration_cents
                     and n.smallflags_qa_cents = o.smallflags_qa_cents
                     and n.ordinary_participation_value_cents = 14199
                     and o.ordinary_participation_value_cents = 14199)
       from public.commercial_pricing_schedule n
       join public.commercial_pricing_schedule o
         on o.pricing_rule_version = 3 and o.commercial_category = n.commercial_category
        and o.fidelized = n.fidelized
      where n.pricing_rule_version = 4));
select tests.check('588 participacoes x R$ 141,99 = R$ 83.490,12 = MEI da formacao (168 + 5 x 84)',
    168 + 5 * 84 = 588 and 588 * 14199 = 8349012
    and (select sum(mei_consideration_cents) filter (where commercial_category = 'supermarket')
              + 5 * sum(mei_consideration_cents) filter (where commercial_category = 'common')
           from public.commercial_pricing_schedule where pricing_rule_version = 4 and not fidelized) = 8349012
    and (select mei_consideration_cents from public.commercial_pricing_schedule
          where pricing_rule_version = 4 and commercial_category = 'supermarket' and not fidelized) = 168 * 14199
    and (select mei_consideration_cents from public.commercial_pricing_schedule
          where pricing_rule_version = 4 and commercial_category = 'common' and not fidelized) = 84 * 14199);
select tests.check('QA nao duplicada: 12.168 + 5 x 6.084 = 42.588 (R$ 425,88), igual nas duas condicoes',
    (select sum(smallflags_qa_cents) filter (where commercial_category = 'supermarket')
          + 5 * sum(smallflags_qa_cents) filter (where commercial_category = 'common')
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and not fidelized) = 42588
    and (select sum(smallflags_qa_cents) filter (where commercial_category = 'supermarket')
          + 5 * sum(smallflags_qa_cents) filter (where commercial_category = 'common')
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and fidelized) = 42588);
select tests.check('formacao nao fidelizada 147.634,00; remuneracao bruta 64.143,88; apos 504 bandeiras 46.503,88; sem QA 46.078,00',
    (select sum(economic_value_cents) filter (where commercial_category = 'supermarket')
          + 5 * sum(economic_value_cents) filter (where commercial_category = 'common') = 14763400
        and sum(smallflags_total_remuneration_cents) filter (where commercial_category = 'supermarket')
          + 5 * sum(smallflags_total_remuneration_cents) filter (where commercial_category = 'common') = 6414388
        and 6414388 - 504 * 3500 = 4650388 and 4650388 - 42588 = 4607800
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and not fidelized));
select tests.check('formacao fidelizada com reutilizacao 109.116,00; remuneracao 25.625,88; sem QA 25.200,00',
    (select sum(economic_value_cents) filter (where commercial_category = 'supermarket')
          + 5 * sum(economic_value_cents) filter (where commercial_category = 'common') = 10911600
        and sum(smallflags_total_remuneration_cents) filter (where commercial_category = 'supermarket')
          + 5 * sum(smallflags_total_remuneration_cents) filter (where commercial_category = 'common') = 2562588
        and 2562588 - 42588 = 2520000
       from public.commercial_pricing_schedule where pricing_rule_version = 4 and fidelized));
select tests.check('percentuais informativos (MEI / economico): 72,42 / 52,00 / 56,55 e 84,66 / 73,68 / 76,52',
    round(2385432 * 100.0 / 3293900, 2) = 72.42 and round(1192716 * 100.0 / 2293900, 2) = 52.00
    and round(8349012 * 100.0 / 14763400, 2) = 56.55
    and round(2385432 * 100.0 / 2817600, 2) = 84.66 and round(1192716 * 100.0 / 1618800, 2) = 73.68
    and round(8349012 * 100.0 / 10911600, 2) = 76.52);

-- ---------------------------------------------------------------------------
-- 2. Privilégios e proteção da autoridade
-- ---------------------------------------------------------------------------
select tests.check('service_role so LE agenda e inventario; ninguem mais escreve',
    has_table_privilege('service_role', 'public.commercial_pricing_schedule', 'SELECT')
    and has_table_privilege('service_role', 'public.commercial_flag_sets', 'SELECT')
    and has_table_privilege('service_role', 'public.commercial_flag_set_inspections', 'SELECT')
    and not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.commercial_pricing_schedule','public.commercial_pricing_rules',
                                 'public.commercial_flag_sets','public.commercial_flag_set_inspections']) t,
                    unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p
       where has_table_privilege(r, t, p)));
select tests.check('anon e authenticated nao leem inventario de bandeiras',
    not has_table_privilege('anon', 'public.commercial_flag_sets', 'SELECT')
    and not has_table_privilege('authenticated', 'public.commercial_flag_sets', 'SELECT')
    and not has_table_privilege('anon', 'public.commercial_flag_set_inspections', 'SELECT')
    and not has_table_privilege('authenticated', 'public.commercial_flag_set_inspections', 'SELECT'));
select tests.check('resolvedor de reutilizacao e gatilhos nao sao executaveis por anon/authenticated/service_role',
    not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.commercial_flag_reuse_resolution(uuid,text)',
                                 'public.cci_validar_producao_bandeiras()',
                                 'public.ceo_validar_producao_bandeiras()',
                                 'public.commercial_pricing_schedule_protect()',
                                 'public.commercial_pricing_rules_protect()']) f
       where has_function_privilege(r, f, 'EXECUTE')));
select tests.check('resumo de producao da formacao: so service_role',
    has_function_privilege('service_role', 'public.commercial_exclusivity_flag_production(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.commercial_exclusivity_flag_production(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.commercial_exclusivity_flag_production(uuid)', 'EXECUTE'));

select tests.check_raises('SF-v1.4: centavos nao mudam (nem para o dono)',
  $sql$update public.commercial_pricing_schedule set economic_value_cents = 1 where pricing_rule_version = 3$sql$,
  'pricing_schedule_imutavel');
select tests.check_raises('SF-v1.4: notas tambem nao mudam',
  $sql$update public.commercial_pricing_schedule set notes = 'x' where pricing_rule_version = 3$sql$,
  'pricing_schedule_imutavel');
select tests.check_raises('SF-v1.4: linha nao e apagada',
  $sql$delete from public.commercial_pricing_schedule where pricing_rule_version = 3$sql$,
  'pricing_schedule_imutavel');
select tests.check_raises('SF-v1.4: linha nova nao entra em versao publicada',
  $sql$insert into public.commercial_pricing_schedule (pricing_rule_version, contract_economics_version,
        commercial_category, fidelized, economic_value_cents, mei_consideration_cents,
        smallflags_qa_cents, smallflags_main_fee_cents, smallflags_total_remuneration_cents)
       values (2, 'X', 'common', true, 3, 1, 1, 1, 2)$sql$,
  'pricing_schedule_imutavel');
select tests.check_raises('agenda nao e truncada',
  $sql$truncate public.commercial_pricing_schedule$sql$, 'pricing_rule_imutavel');
select tests.check_raises('regra publicada: valores nao mudam',
  $sql$update public.commercial_pricing_rules set block_price_cents = 1 where version = 3$sql$,
  'pricing_rule_imutavel');
select tests.check_raises('regra ativa nao volta a preparada',
  $sql$update public.commercial_pricing_rules set status = 'prepared' where version = 3$sql$,
  'pricing_rule_imutavel');
select tests.check_raises('regra superada nao volta a ativa',
  $sql$update public.commercial_pricing_rules set status = 'active' where version = 2$sql$,
  'pricing_rule_imutavel');
select tests.check_raises('regra nova nao nasce ativa',
  $sql$insert into public.commercial_pricing_rules (version, status, block_units, block_price_cents,
        extra_unit_price_cents, fidelized_unit_price_cents, pool_precision_model)
       values (98, 'active', 12, 1, 1, 1, 'explicit_schedule')$sql$,
  'pricing_rule_imutavel');
select tests.check_raises('regra publicada nao e apagada',
  $sql$delete from public.commercial_pricing_rules where version = 1$sql$, 'pricing_rule_imutavel');
select tests.check_raises('regras nao sao truncadas',
  $sql$truncate public.commercial_pricing_rules cascade$sql$, 'pricing_rule_imutavel');
select tests.check_raises('agenda com bandeira incoerente e recusada (adicional <> pecas x unitario)',
  $sql$update public.commercial_pricing_schedule set flag_production_charge_cents = 293999
        where pricing_rule_version = 4 and commercial_category = 'common' and not fidelized$sql$,
  'cps_bandeiras_coerente');
select tests.check_raises('agenda fidelizada nao pode exigir pecas novas',
  $sql$update public.commercial_pricing_schedule set new_flag_units = 84, flag_production_charge_cents = 294000,
        smallflags_main_fee_cents = 714000, smallflags_total_remuneration_cents = 720084,
        economic_value_cents = 1912800
        where pricing_rule_version = 4 and commercial_category = 'common' and fidelized$sql$,
  'cps_bandeiras_coerente');

begin;
with u as (
  update public.commercial_pricing_schedule set notes = notes || ' (revisada)'
   where pricing_rule_version = 4 and commercial_category = 'common' and fidelized
  returning 1)
select tests.check('versao PREPARADA ainda e editavel (correcao antes da ativacao)',
    (select count(*) = 1 from u));
rollback;

-- ===========================================================================
-- TRANSAÇÃO DOS CENÁRIOS (revertida no fim)
-- ===========================================================================
begin;
select tests.encerrar_contexto_contratual_v14_qa();

select r.id as reg from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

select tests.mk_user('admin290') as uid_adm \gset
insert into public.site_admins (user_id) values ((:'uid_adm')::uuid) on conflict do nothing;

-- Doze empresas em Viana, cada uma com titular.
create temp table emp290 (n int primary key, cnpj text, comp uuid, uid uuid) on commit drop;
do $$
declare
  v_cnpjs text[] := array['29000001000118','29000002000162','29000003000107','29000004000151',
                          '29000005000104','29000006000140','29000007000195','29000008000130',
                          '29000009000184','29000010000109','29000011000153','29000012000106'];
  v_i int; v_app uuid; v_comp uuid; v_uid uuid;
begin
  for v_i in 1..12 loop
    v_uid := tests.mk_user('titular290.' || v_i);
    insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
    values (v_cnpjs[v_i], 'Empresa 290-' || v_i, 'e290' || v_i || '@teste.local', 'Viana', 'ES')
    returning id into v_app;
    insert into public.partner_application_representatives
      (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
    values (v_app, 'Titular 290-' || v_i, '52998224725', 'rep290' || v_i || '@teste.local',
            'Socio administrador', 'approved', true, now() - interval '2 days');
    insert into public.site_partner_companies
      (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
    values (v_app, v_cnpjs[v_i], 'Empresa 290-' || v_i, 'Loja 290-' || v_i,
            'e290' || v_i || '@teste.local', 'Viana', 'ES', 'active')
    returning id into v_comp;
    insert into public.site_company_members
      (company_id, auth_user_id, role, full_name, cpf, source, status)
    values (v_comp, v_uid, 'partner_owner', 'Titular 290-' || v_i, '52998224725',
            'application_promotion', 'active');
    insert into public.site_partner_units (company_id, name, city, uf, status)
    values (v_comp, 'Unidade 290-' || v_i, 'Viana', 'ES', 'active');
    insert into emp290 values (v_i, v_cnpjs[v_i], v_comp, v_uid);
  end loop;
end $$;

-- As tabelas temporárias da suíte são lidas também sob o papel impersonado.
grant select on emp290 to authenticated;
select tests.impersonate('authenticated', :'uid_adm');
select tests.assinar_mestre_qa(e.comp, 'AM-290-' || e.n) from emp290 e;
select (public.admin_create_commercial_segment('pet_shop_290','Pet shop 290','pet_shop_290')->>'segment_id') as seg \gset
reset role;
select set_config('request.jwt.claims', '', true);

-- Exclusividades E0 (reservas), E1..E4 (cenários) e E5 (instrumento), cada
-- uma com as seis posições.
create temp table exc290 (k int primary key, id uuid) on commit drop;
select set_config('tests.reg290', :'reg', true);
do $$
declare v_k int; v_id uuid;
begin
  for v_k in 0..5 loop
    insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
    values (current_setting('tests.reg290')::uuid, 2900 + v_k, 'forming', false)
    returning id into v_id;
    insert into exc290 values (v_k, v_id);
  end loop;
end $$;
grant select on exc290 to authenticated;
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select x.id, n.code, n.contracted_quantity, 'available'
  from exc290 x cross join public.commercial_niches n where n.is_active;

create or replace function pg_temp.tornar_corrente(p_k int) returns void language sql as $f$
  update public.commercial_exclusivities set is_current = false
   where region_id = (select region_id from public.commercial_exclusivities
                       where id = (select id from exc290 where k = p_k)) and is_current;
  update public.commercial_exclusivities set is_current = true
   where id = (select id from exc290 where k = p_k);
$f$;

-- Pedido direto (caminho administrativo): os números vêm dos gatilhos.
create or replace function pg_temp.pedido(p_k int, p_n int, p_niche text, p_fid boolean,
                                          p_mode text default 'direct_benefits')
returns uuid language plpgsql as $f$
declare v_id uuid; v_excl uuid := (select id from exc290 where k = p_k);
        v_comp uuid := (select comp from emp290 where n = p_n);
        v_seg public.commercial_segments%rowtype;
begin
  if p_niche = 'others' then
    select * into v_seg from public.commercial_segments where code = 'pet_shop_290';
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
-- 3. Antes da ativação: nada nasce sob a versão preparada
-- ---------------------------------------------------------------------------
select tests.check_raises('pedido sob versao PREPARADA e recusado',
  $sql$select pg_temp.pedido(1, 1, 'supermarket', false)$sql$, 'pricing_rule_not_published');

-- ---------------------------------------------------------------------------
-- 4. Ativação (como faria o ato autorizado), DENTRO da transação revertida
-- ---------------------------------------------------------------------------
-- R3: só pela função autorizada, com os pré-requisitos A1–A6 atendidos. Aqui
-- eles são FIXTURES: minutas QA com o modelo de liquidação R3, atividades QA
-- SF-v1.5 e preço FICTÍCIO do dinheiro no Cenário B (preço mantido, com
-- componente fundamentado, nunca QA). Depois da ativação as minutas e
-- atividades QA são arquivadas: as seções seguintes provam o caminho sem elas.
select tests.preparar_ativacao_sf_v15_qa('290', 'B');
select tests.check('ativacao autorizada (R3) aceita com os pre-requisitos de teste',
    (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao da suite 290') ->> 'ok') = 'true');
select tests.encerrar_contexto_contratual_v14_qa();
select tests.check('ativacao: v4 ativa, v3 superada e ainda legivel por versao explicita',
    (public.calculate_niche_contract_pricing('supermarket', false) ->> 'economic_value_cents')::bigint = 3293900
    and (public.calculate_niche_contract_pricing('supermarket', false, 3) ->> 'economic_value_cents')::bigint = 2999900);
select tests.check('preco publico SF-v1.5: chaves de bandeira com 84 pecas e 294.000; fidelizado com reuso exigido',
    (select bool_and((n->'founding'->>'new_flag_units')::int = 84
                     and (n->'founding'->>'flag_production_charge_cents')::bigint = 294000
                     and (n->'founding'->>'flag_reuse_required')::boolean = false
                     and (n->'fidelized'->>'new_flag_units')::int = 0
                     and (n->'fidelized'->>'flag_production_charge_cents')::bigint = 0
                     and (n->'fidelized'->>'flag_reuse_required')::boolean = true
                     and n->'founding'->>'contract_economics_version' = 'SF-v1.5')
       from jsonb_array_elements(public.get_public_niche_pricing()->'niches') n));
select tests.check('formacao publica SF-v1.5 = 147.634,00; MEI 83.490,12 preservado',
    (public.get_public_formation_economics()->>'economic_value_cents')::bigint = 14763400
    and (public.get_public_formation_economics()->>'mei_consideration_cents')::bigint = 8349012
    and (public.get_public_formation_economics()->>'participant_target')::int = 84);

-- ---------------------------------------------------------------------------
-- 5. Reserva (checkout) pelo RPC: preço exibido = preço cobrado
-- ---------------------------------------------------------------------------
savepoint reservas;
select pg_temp.tornar_corrente(0);
select tests.impersonate('authenticated', (select uid::text from emp290 where n = 1)::uuid);
select public.create_commercial_checkout_intent((select comp from emp290 where n = 1),
         'supermarket', 'direct_benefits') as r1 \gset
select tests.impersonate('authenticated', (select uid::text from emp290 where n = 2)::uuid);
select public.create_commercial_checkout_intent((select comp from emp290 where n = 2),
         'pharmacy', 'cash') as r2 \gset
reset role;
select set_config('request.jwt.claims', '', true);
select tests.check('reserva nao fidelizada (supermercado): 32.939,00 com 84 bandeiras e 2.940,00 de fabricacao',
    ((:'r1')::jsonb->>'ok') = 'true'
    and ((:'r1')::jsonb->>'economic_value_cents')::bigint = 3293900
    and ((:'r1')::jsonb->>'new_flag_units')::int = 84
    and ((:'r1')::jsonb->>'flag_production_charge_cents')::bigint = 294000
    and ((:'r1')::jsonb->>'flag_reuse')::boolean = false
    and ((:'r1')::jsonb->>'contract_economics_version') = 'SF-v1.5');
select tests.check('beneficio direto (R3): dinheiro devido = parcela principal com fabricacao UMA vez (602.300 + 294.000); QA em produtos',
    ((:'r1')::jsonb->>'total_monetary_funding_required_cents')::bigint = 896300
    and 896300 = 602300 + 294000
    and ((:'r1')::jsonb->>'qa_in_kind_cents')::bigint = 12168
    and ((:'r1')::jsonb->>'qa_cash_cents')::bigint = 0
    and ((:'r1')::jsonb->>'cash_user_pool_funding_cents')::bigint = 0);
select tests.check('dinheiro (farmacia, cenario B de teste): cobra o economico 22.939,00; MEI em dinheiro; sem QA',
    ((:'r2')::jsonb->>'ok') = 'true'
    and ((:'r2')::jsonb->>'total_monetary_funding_required_cents')::bigint = 2293900
    and (select mei_cash_funding_cents = 1192716 and smallflags_qa_cents = 0
                and qa_in_kind_cents = 0 and qa_cash_cents = 0 and cash_adjustment_cents = 6084
                and smallflags_main_fee_cents = 1095100 and flag_production_charge_cents = 294000
           from public.commercial_checkout_intents where id = ((:'r2')::jsonb->>'intent_id')::uuid));
select tests.check('intencao guarda os fatos de producao exatamente uma vez',
    (select flag_production_new_units = 84 and flag_unit_reference_cents = 3500
            and economic_value_cents = mei_consideration_cents + smallflags_qa_cents + smallflags_main_fee_cents
            and flag_reuse_set_id is null
       from public.commercial_checkout_intents where id = ((:'r1')::jsonb->>'intent_id')::uuid));
select tests.check_raises('intencao: fatos de producao sao imutaveis',
  format($sql$update public.commercial_checkout_intents set flag_production_new_units = 24 where id = %L$sql$,
         (:'r1')::jsonb->>'intent_id'),
  'pedido_imutavel');

-- Pedido copiado da intenção: o snapshot preserva o que foi reservado.
select pg_temp.pedido(1, 3, 'womens_clothing', false) as o_tmp \gset
select tests.check('pedido v4 direto (nao fidelizado) tambem recebe 84 pecas e o preco SF-v1.5',
    (select flag_production_new_units = 84 and economic_value_cents = 2293900
       from public.commercial_exclusivity_orders where id = (:'o_tmp')::uuid));
rollback to savepoint reservas;

-- ---------------------------------------------------------------------------
-- 6. E1: seis anunciantes novos -> 504 bandeiras
-- ---------------------------------------------------------------------------
select pg_temp.pedido(1, 1, 'supermarket', false) as e1_1 \gset
select pg_temp.pedido(1, 2, 'pharmacy', false) as e1_2 \gset
select pg_temp.pedido(1, 3, 'womens_clothing', false) as e1_3 \gset
select pg_temp.pedido(1, 4, 'mens_clothing', false, 'cash') as e1_4 \gset
select pg_temp.pedido(1, 5, 'footwear', false) as e1_5 \gset
select pg_temp.pedido(1, 6, 'others', false, 'cash') as e1_6 \gset
select public.commercial_exclusivity_flag_production((select id from exc290 where k = 1)) as s1 \gset
select tests.check('E1 seis novos: 504 bandeiras e 17.640,00 de fabricacao nominal',
    ((:'s1')::jsonb->>'new_flag_units')::int = 504
    and ((:'s1')::jsonb->>'flag_production_charge_cents')::bigint = 1764000
    and ((:'s1')::jsonb->>'orders_new_production')::int = 6);
-- R3: QA so em produtos e so no beneficio direto (4 dos 6 pedidos de E1);
-- remuneracao monetaria = parcela principal. Economico mantido pelo cenario B.
select tests.check('E1 soma dos PEDIDOS: 147.634,00; MEI 83.490,12; QA em produtos 304,20; remuneracao monetaria 63.718,00',
    ((:'s1')::jsonb->>'economic_value_cents')::bigint = 14763400
    and ((:'s1')::jsonb->>'mei_consideration_cents')::bigint = 8349012
    and ((:'s1')::jsonb->>'smallflags_qa_cents')::bigint = 12168 + 3 * 6084
    and ((:'s1')::jsonb->>'smallflags_total_remuneration_cents')::bigint = 896300 + 5 * 1095100);
select tests.check('as 84 unidades comerciais nao viram 84 bandeiras no total',
    (select sum(nominal_quantity) = 84 and sum(flag_production_new_units) = 504
       from public.commercial_exclusivity_orders
      where exclusivity_id = (select id from exc290 where k = 1)));
select tests.check('liquidacao separada: cash -> MEI em dinheiro de terceiros; direto -> zero, QA sempre fora',
    (select bool_and(case benefit_settlement_mode
                       when 'cash' then mei_cash_funding_cents = mei_consideration_cents
                                        and total_monetary_funding_required_cents = economic_value_cents
                       else mei_cash_funding_cents = 0
                            and total_monetary_funding_required_cents = smallflags_total_remuneration_cents end)
       from public.commercial_exclusivity_orders
      where exclusivity_id = (select id from exc290 where k = 1)));
select tests.check_raises('pedido: fatos de producao imutaveis',
  format($sql$update public.commercial_exclusivity_orders set flag_production_new_units = 24 where id = %L$sql$, :'e1_1'),
  'pedido_imutavel');
select tests.check_raises('pedido: preco congelado nao muda (snapshot v1.4+)',
  format($sql$update public.commercial_exclusivity_orders set smallflags_main_fee_cents = 602300 where id = %L$sql$, :'e1_1'),
  'pedido_imutavel');

-- Fidelidade estabelecida pelos pedidos de E1 (identidade derivada).
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code, established_by_order_id)
select e.cnpj, 'ES', 'viana', o.niche_code, o.id
  from public.commercial_exclusivity_orders o join emp290 e on e.comp = o.company_id
 where o.exclusivity_id = (select id from exc290 where k = 1);
select tests.check('fidelidade de Outros segue o segmento (segment:pet_shop_290)',
    exists (select 1 from public.commercial_fidelity_records
             where cnpj = '29000006000140' and fidelity_identity = 'segment:pet_shop_290'));

-- ---------------------------------------------------------------------------
-- 7. Inventário: conjunto nasce do pedido que exigiu produção
-- ---------------------------------------------------------------------------
select pg_temp.conjunto(:'e1_1', 60) as set1 \gset
select tests.check('conjunto: empresa, identidade e 84 pecas derivadas do pedido (nao do registrador)',
    (select company_id = (select comp from emp290 where n = 1)
            and fidelity_identity = 'supermarket' and pieces_count = 84
            and production_cost_cents = 294000 and status = 'active'
       from public.commercial_flag_sets where id = (:'set1')::uuid));
select tests.check_raises('um conjunto por pedido de origem',
  format($sql$select pg_temp.conjunto(%L, 59)$sql$, :'e1_1'), 'duplicate key');
select tests.check_raises('conjunto: dados registrados nao mudam',
  format($sql$update public.commercial_flag_sets set unit_cost_cents = 1 where id = %L$sql$, :'set1'),
  'flag_set_imutavel');
select tests.check_raises('conjunto: nao e apagado',
  format($sql$delete from public.commercial_flag_sets where id = %L$sql$, :'set1'), 'flag_set_imutavel');
select tests.check_raises('conjunto: nao e truncado',
  $sql$truncate public.commercial_flag_sets cascade$sql$, 'flag_inventory_imutavel');
select tests.check_raises('conjunto: produzido no futuro e recusado',
  format($sql$select pg_temp.conjunto(%L, -1)$sql$, :'e1_2'), 'produced_at no futuro');
select pg_temp.conjunto(:'e1_2', 60) as set2 \gset
select pg_temp.conjunto(:'e1_3', 60) as set3 \gset
select pg_temp.conjunto(:'e1_4', 60) as set4 \gset
select pg_temp.conjunto(:'e1_5', 60) as set5 \gset
select pg_temp.conjunto(:'e1_6', 60) as set6 \gset
select tests.check('conjunto de Outros carrega a identidade do segmento',
    (select fidelity_identity = 'segment:pet_shop_290' from public.commercial_flag_sets
      where id = (:'set6')::uuid));

select tests.check_raises('inspecao parcial (menos que as 84 pecas) e recusada',
  format($sql$insert into public.commercial_flag_set_inspections (flag_set_id, inspected_at, inspector_name,
        evidence_hash, pieces_inspected, pieces_fit, pieces_unfit, recorded_by)
        values (%L, now() - interval '1 day', 'Conferente QA', repeat('a', 64), 80, 80, 0, gen_random_uuid())$sql$, :'set1'),
  'inspecionar todas as 84');
select tests.check_raises('inspecao com pecas inadequadas exige categoria',
  format($sql$insert into public.commercial_flag_set_inspections (flag_set_id, inspected_at, inspector_name,
        evidence_hash, pieces_inspected, pieces_fit, pieces_unfit, recorded_by)
        values (%L, now() - interval '1 day', 'Conferente QA', repeat('a', 64), 84, 82, 2, gen_random_uuid())$sql$, :'set1'),
  'cfi_categorias_coerentes');
select tests.check_raises('inspecao sem hash de evidencia e recusada',
  format($sql$insert into public.commercial_flag_set_inspections (flag_set_id, inspected_at, inspector_name,
        evidence_hash, pieces_inspected, pieces_fit, pieces_unfit, recorded_by)
        values (%L, now() - interval '1 day', 'Conferente QA', 'foto.jpg', 84, 84, 0, gen_random_uuid())$sql$, :'set1'),
  'cfi_evidencia');
select tests.check_raises('inspecao no futuro e recusada',
  format($sql$select pg_temp.inspecao(%L, -2)$sql$, :'set1'), 'fora do intervalo');

-- ---------------------------------------------------------------------------
-- 8. Reserva fidelizada: reutilização exige evidência; reposição não tem preço
-- ---------------------------------------------------------------------------
savepoint reservas_fid;
select pg_temp.tornar_corrente(0);
select tests.impersonate('authenticated', (select uid::text from emp290 where n = 1)::uuid);
select public.create_commercial_checkout_intent((select comp from emp290 where n = 1),
         'supermarket', 'direct_benefits') as f1 \gset
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('fidelizado SEM inspecao: nao reserva e nao recebe preco',
    ((:'f1')::jsonb->>'ok') = 'false'
    and ((:'f1')::jsonb->>'reason') = 'flag_reuse_not_verified'
    and ((:'f1')::jsonb->>'detail') = 'flag_inspection_missing'
    and not ((:'f1')::jsonb ? 'economic_value_cents')
    and (select status = 'available' from public.commercial_opportunities
          where exclusivity_id = (select id from exc290 where k = 0) and niche_code = 'supermarket'));

select pg_temp.inspecao(:'set1', 20, 3, array['damaged','lost']) as insp_ruim \gset
select tests.check('inspecao com 3 pecas inadequadas: resultado replacement_needed',
    (select conservation_result = 'replacement_needed' and pieces_fit = 81
       from public.commercial_flag_set_inspections where id = (:'insp_ruim')::uuid));
select tests.impersonate('authenticated', (select uid::text from emp290 where n = 1)::uuid);
select public.create_commercial_checkout_intent((select comp from emp290 where n = 1),
         'supermarket', 'direct_benefits') as f2 \gset
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('reposicao pendente de politica: sem reserva, sem preco, sem cobranca de 84 nem de 3 pecas',
    ((:'f2')::jsonb->>'ok') = 'false'
    and ((:'f2')::jsonb->>'reason') = 'flag_replacement_policy_pending'
    and not ((:'f2')::jsonb ?| array['economic_value_cents','flag_production_charge_cents',
                                     'total_monetary_funding_required_cents'])
    and not exists (select 1 from public.commercial_checkout_intents
                     where company_id = (select comp from emp290 where n = 1)));
select tests.check_raises('reposicao pendente: venda manual fidelizada tambem falha fechada',
  $sql$select pg_temp.pedido(2, 1, 'supermarket', true)$sql$, 'flag_replacement_policy_pending');
select tests.check_raises('inspecao registrada nao e reescrita para liberar a reserva',
  format($sql$update public.commercial_flag_set_inspections set pieces_unfit = 0, pieces_fit = 84,
        unfit_categories = '{}' where id = %L$sql$, :'insp_ruim'),
  'flag_inspection_imutavel');

select pg_temp.inspecao(:'set1', 10) as insp_boa \gset
select tests.impersonate('authenticated', (select uid::text from emp290 where n = 1)::uuid);
select public.create_commercial_checkout_intent((select comp from emp290 where n = 1),
         'supermarket', 'direct_benefits') as f3 \gset
reset role; select set_config('request.jwt.claims', '', true);
select tests.check('fidelizado com conjunto reutilizavel: 28.176,00, zero pecas, sem adicional',
    ((:'f3')::jsonb->>'ok') = 'true'
    and ((:'f3')::jsonb->>'fidelized')::boolean
    and ((:'f3')::jsonb->>'economic_value_cents')::bigint = 2817600
    and ((:'f3')::jsonb->>'new_flag_units')::int = 0
    and ((:'f3')::jsonb->>'flag_production_charge_cents')::bigint = 0
    and ((:'f3')::jsonb->>'flag_reuse')::boolean
    and ((:'f3')::jsonb->>'total_monetary_funding_required_cents')::bigint = 420000);
select tests.check('intencao fidelizada aponta o conjunto e a inspecao corretos',
    (select flag_reuse_set_id = (:'set1')::uuid and flag_reuse_inspection_id = (:'insp_boa')::uuid
       from public.commercial_checkout_intents where id = ((:'f3')::jsonb->>'intent_id')::uuid));

-- Pedido criado a partir da intenção copia os fatos da reserva.
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
  from public.commercial_checkout_intents i where i.id = ((:'f3')::jsonb->>'intent_id')::uuid
returning id as o_intent \gset
select tests.check('pedido da reserva preserva o preco e os fatos de producao resolvidos pelo servidor',
    (select o.economic_value_cents = i.economic_value_cents
            and o.total_monetary_funding_required_cents = i.total_monetary_funding_required_cents
            and o.flag_production_new_units = 0 and o.flag_reuse_inspection_id = i.flag_reuse_inspection_id
       from public.commercial_exclusivity_orders o
       join public.commercial_checkout_intents i on i.id = o.checkout_intent_id
      where o.id = (:'o_intent')::uuid));
select tests.check_raises('a mesma inspecao nao autoriza segunda reutilizacao',
  $sql$select pg_temp.pedido(2, 1, 'supermarket', true)$sql$, 'flag_inspection_already_used');
rollback to savepoint reservas_fid;

select tests.check_raises('fidelizado sem conjunto registrado: falha fechada (nao presume reuso)',
  $sql$select pg_temp.pedido(2, 11, 'pharmacy', true)$sql$, 'flag_set_not_registered');

-- ---------------------------------------------------------------------------
-- 9. E2: seis fidelizados com reutilização -> 0 bandeiras novas
-- ---------------------------------------------------------------------------
select pg_temp.inspecao(:'set1', 50), pg_temp.inspecao(:'set2', 50), pg_temp.inspecao(:'set3', 50),
       pg_temp.inspecao(:'set4', 50), pg_temp.inspecao(:'set5', 50), pg_temp.inspecao(:'set6', 50);
select pg_temp.pedido(2, 1, 'supermarket', true);
select pg_temp.pedido(2, 2, 'pharmacy', true);
select pg_temp.pedido(2, 3, 'womens_clothing', true);
select pg_temp.pedido(2, 4, 'mens_clothing', true, 'cash');
select pg_temp.pedido(2, 5, 'footwear', true);
select pg_temp.pedido(2, 6, 'others', true);
select public.commercial_exclusivity_flag_production((select id from exc290 where k = 2)) as s2 \gset
select tests.check('E2 seis fidelizados com reuso: 0 bandeiras e 0 de fabricacao',
    ((:'s2')::jsonb->>'new_flag_units')::int = 0
    and ((:'s2')::jsonb->>'flag_production_charge_cents')::bigint = 0
    and ((:'s2')::jsonb->>'orders_reusing_flags')::int = 6);
select tests.check('E2: 109.116,00; MEI 83.490,12; remuneracao monetaria 25.200,00 (R3: sem QA)',
    ((:'s2')::jsonb->>'economic_value_cents')::bigint = 10911600
    and ((:'s2')::jsonb->>'mei_consideration_cents')::bigint = 8349012
    and ((:'s2')::jsonb->>'smallflags_total_remuneration_cents')::bigint = 6 * 420000);
select tests.check('reutilizacao nao cobra de novo os 2.940,00',
    (select bool_and(flag_production_charge_cents = 0 and smallflags_main_fee_cents = 420000)
       from public.commercial_exclusivity_orders where exclusivity_id = (select id from exc290 where k = 2)));

-- ---------------------------------------------------------------------------
-- 10. E3: um novo + cinco fidelizados -> 84; E4: três novos + três -> 252
-- ---------------------------------------------------------------------------
select pg_temp.inspecao(:'set1', 40), pg_temp.inspecao(:'set3', 40), pg_temp.inspecao(:'set4', 40),
       pg_temp.inspecao(:'set5', 40), pg_temp.inspecao(:'set6', 40);
select pg_temp.pedido(3, 1, 'supermarket', true);
select pg_temp.pedido(3, 7, 'pharmacy', false);
select pg_temp.pedido(3, 3, 'womens_clothing', true);
select pg_temp.pedido(3, 4, 'mens_clothing', true);
select pg_temp.pedido(3, 5, 'footwear', true, 'cash');
select pg_temp.pedido(3, 6, 'others', true);
select public.commercial_exclusivity_flag_production((select id from exc290 where k = 3)) as s3 \gset
select tests.check('E3 um novo + cinco fidelizados: 84 bandeiras, 2.940,00 e 115.867,00',
    ((:'s3')::jsonb->>'new_flag_units')::int = 84
    and ((:'s3')::jsonb->>'flag_production_charge_cents')::bigint = 294000
    and ((:'s3')::jsonb->>'economic_value_cents')::bigint = 2817600 + 2293900 + 4 * 1618800
    and ((:'s3')::jsonb->>'orders_reusing_flags')::int = 5);

select tests.check_raises('E4: fidelizado com inspecao ja consumida em E2 falha fechado',
  $sql$select pg_temp.pedido(4, 2, 'pharmacy', true)$sql$, 'flag_inspection_already_used');
select pg_temp.inspecao(:'set4', 30), pg_temp.inspecao(:'set5', 30), pg_temp.inspecao(:'set6', 30);
select pg_temp.pedido(4, 8, 'supermarket', false);
select pg_temp.pedido(4, 9, 'pharmacy', false, 'cash');
select pg_temp.pedido(4, 10, 'womens_clothing', false);
select pg_temp.pedido(4, 4, 'mens_clothing', true);
select pg_temp.pedido(4, 5, 'footwear', true);
select pg_temp.pedido(4, 6, 'others', true, 'cash');
select public.commercial_exclusivity_flag_production((select id from exc290 where k = 4)) as s4 \gset
select tests.check('E4 tres novos + tres fidelizados: 252 bandeiras, 8.820,00 e 127.381,00',
    ((:'s4')::jsonb->>'new_flag_units')::int = 252
    and ((:'s4')::jsonb->>'flag_production_charge_cents')::bigint = 882000
    and ((:'s4')::jsonb->>'economic_value_cents')::bigint = 3293900 + 2 * 2293900 + 3 * 1618800
    and ((:'s4')::jsonb->>'mei_consideration_cents')::bigint = 8349012);
select tests.check('cada pedido mantem os proprios fatos: producao depende do anunciante, nao da posicao',
    (select bool_and((fidelized and flag_production_new_units = 0 and flag_reuse_set_id is not null)
                  or (not fidelized and flag_production_new_units = 84 and flag_reuse_set_id is null))
       from public.commercial_exclusivity_orders
      where exclusivity_id in (select id from exc290 where k between 1 and 4)));

with u as (
  update public.commercial_flag_sets set status = 'retired', retired_at = now(),
         retired_reason = '[QA] fim de vida' where id = (:'set2')::uuid returning 1)
select tests.check('aposentar conjunto: so status, data e motivo', (select count(*) = 1 from u));
select tests.check_raises('conjunto aposentado nao recebe inspecao',
  format($sql$select pg_temp.inspecao(%L, 1)$sql$, :'set2'), 'aposentado');

-- ---------------------------------------------------------------------------
-- 11. Instrumento: fatos de produção no bloco V2; templates reais não assináveis
-- ---------------------------------------------------------------------------
select tests.check('nenhum modelo real assinavel (so rascunhos); nenhum V2 registrado',
    not exists (select 1 from public.commercial_instrument_templates
                 where lifecycle_status = 'signable' and template_code not like '[QA FICTICIO]%')
    and not exists (select 1 from public.commercial_instrument_templates
                     where requires_advertising_spec and template_code not like '[QA FICTICIO]%'));

savepoint instrumento;
select tests.criar_modelo_instrumento_qa(false, '290') as tpl_qa \gset
-- R3 / A6: pedido SF-v1.5 so e individualizado por minuta que redige o modelo
-- de liquidacao R3.
update public.commercial_instrument_templates
   set settlement_model = 'in_kind_direct_benefits_only' where id = (:'tpl_qa')::uuid;
-- R4: e com aprovacao juridica (FICTICIA) do mesmo conteudo, para a SF-v1.5.
select tests.aprovar_minuta_r3_qa((:'tpl_qa')::uuid);
select tests.aprovar_atividade_qa('pharmacy') as ativ_qa \gset
select pg_temp.tornar_corrente(5);
select id as opp5 from public.commercial_opportunities
 where exclusivity_id = (select id from exc290 where k = 5) and niche_code = 'pharmacy' \gset
select comp as comp12 from emp290 where n = 12 \gset
-- O catálogo de atividades é versionado pela economia: redação aprovada só
-- para a SF-v1.4 NÃO serve a pedido SF-v1.5 (pré-requisito da ativação).
select tests.impersonate('authenticated', :'uid_adm');
select tests.check_raises('SF-v1.5 exige atividade aprovada no catalogo SF-v1.5 (a da SF-v1.4 nao serve)',
  format($sql$select public.admin_register_manual_commercial_order(%L::uuid, %L::uuid, 'v1',
         now() - interval '1 day', 'Titular 290-12', (now() + interval '30 days')::date,
         'direct_benefits', 'doc://pedido-290')$sql$, :'opp5', :'comp12'),
  'commercial_activity_description_unavailable');
reset role; select set_config('request.jwt.claims', '', true);
select tests.aprovar_atividade_qa('pharmacy', 'SF-v1.5') as ativ_qa15 \gset
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_register_manual_commercial_order(
  (:'opp5')::uuid, (:'comp12')::uuid, 'v1', now() - interval '1 day',
  'Titular 290-12', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-290') as r_man \gset
reset role; select set_config('request.jwt.claims', '', true);
select ((:'r_man')::jsonb ->> 'order_id') as ord_man \gset
select tests.check('venda manual SF-v1.5: 84 pecas e 22.939,00 pela mesma autoridade',
    ((:'r_man')::jsonb ->> 'ok') = 'true'
    and (select flag_production_new_units = 84 and economic_value_cents = 2293900
                and contract_economics_version = 'SF-v1.5'
           from public.commercial_exclusivity_orders where id = (:'ord_man')::uuid));
select tests.check('modelo v1.4 (sem exigencia de especificacao) nao recebe fatos de bandeira',
    (select not (instrument_snapshot ?| array['flag_production_new_units','flag_production_charge_cents'])
       from public.commercial_exclusivity_orders where id = (:'ord_man')::uuid));

update public.commercial_instrument_templates set lifecycle_status = 'archived' where id = (:'tpl_qa')::uuid;
insert into public.commercial_instrument_templates
  (template_code, template_version, template_date, source_hash, lifecycle_status,
   applies_to_fidelized, allows_outros_niche, required_snapshot_fields, notes,
   advertising_modality, requires_advertising_spec, settlement_model)
select '[QA FICTICIO] MODELO-V2-BANDEIRA-290', '0.0-qa-v2', current_date,
       encode(extensions.digest('[QA FICTICIO] instrumento v2 290', 'sha256'), 'hex'),
       'signable', false, false,
       t.required_snapshot_fields || array['advertising_modality','advertising_spec_id',
         'flag_production_new_units','flag_unit_reference_cents','flag_production_charge_cents'],
       'QA: modelo ficticio V2 com fatos de bandeira', 'vehicle_roof_visual_flag', true,
       'in_kind_direct_benefits_only'
  from public.commercial_instrument_templates t where t.id = (:'tpl_qa')::uuid
returning id as tpl_v2 \gset
select tests.aprovar_minuta_r3_qa((:'tpl_v2')::uuid);
insert into public.commercial_advertising_specs
  (spec_code, spec_version, modality, artwork_reference_width_mm, artwork_reference_height_mm, source_hash)
values ('[QA FICTICIO] ESPEC-290', '0.0-qa', 'vehicle_roof_visual_flag', 490, 305, repeat('e', 64))
returning id as spec290 \gset
update public.commercial_advertising_specs
   set lifecycle_status = 'approved', technical_responsible_name = '[QA FICTICIO] Responsavel',
       technical_responsible_registration = '[QA] REGISTRO-0290', technical_report_hash = repeat('f', 64),
       approved_by = (:'uid_adm')::uuid, approved_at = now()
 where id = (:'spec290')::uuid;
select public.commercial_build_instrument_snapshot((:'ord_man')::uuid, (:'tpl_v2')::uuid) as r_v2 \gset
select tests.check('instrumento V2 carrega 84 pecas, R$ 35,00 e 2.940,00 do PEDIDO, com proveniencia',
    ((:'r_v2')::jsonb->>'ok') = 'true'
    and ((:'r_v2')::jsonb->'snapshot'->>'flag_production_new_units')::int = 84
    and ((:'r_v2')::jsonb->'snapshot'->>'flag_unit_reference_cents')::bigint = 3500
    and ((:'r_v2')::jsonb->'snapshot'->>'flag_production_charge_cents')::bigint = 294000
    and ((:'r_v2')::jsonb->'snapshot'->>'economic_value_cents')::bigint = 2293900
    and ((:'r_v2')::jsonb->'snapshot'->'field_provenance'->>'flag_production_charge_cents')
        = 'contract_economics_authority'
    and not ((:'r_v2')::jsonb->'snapshot' ? 'flag_reuse_set_id'));
-- Pedido SF-v1.4 (sem fatos de produção) não é emitido por modelo que os exige.
insert into public.commercial_exclusivity_orders
  (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id,
   niche_code, nominal_quantity, fidelized, status, expected_operation_start,
   registered_by, pricing_rule_version, benefit_settlement_mode,
   economic_value_cents, contractual_pool_cents, bdflow_due_cents)
select x.id, o.id, e.comp,
       (select id from public.commercial_master_agreements where company_id = e.comp and status = 'signed'),
       (:'reg')::uuid, 'pharmacy', 12, false, 'draft', (now() + interval '30 days')::date,
       (:'uid_adm')::uuid, 3, 'direct_benefits', 1, 1, 0
  from exc290 x join public.commercial_opportunities o on o.exclusivity_id = x.id and o.niche_code = 'pharmacy'
  join emp290 e on e.n = 11
 where x.k = 0
returning id as ord_v14 \gset
select tests.check('pedido SF-v1.4 continua sem fatos de bandeira (nada presumido)',
    (select flag_production_new_units is null and flag_production_charge_cents is null
            and contract_economics_version = 'SF-v1.4' and economic_value_cents = 1999900
       from public.commercial_exclusivity_orders where id = (:'ord_v14')::uuid));
select public.commercial_build_instrument_snapshot((:'ord_v14')::uuid, (:'tpl_v2')::uuid) as r_v14 \gset
-- R3 / A6: antes mesmo de faltar fato de bandeira, a minuta R3 nao rege
-- pedido SF-v1.4 (QA monetaria): falha fechada pelo modelo de liquidacao.
select tests.check('minuta R3 nao individualiza pedido SF-v1.4 (modelo de liquidacao divergente)',
    ((:'r_v14')::jsonb->>'ok') = 'false'
    and ((:'r_v14')::jsonb->>'reason') = 'commercial_instrument_template_settlement_model_mismatch');
rollback to savepoint instrumento;

rollback;

-- ---------------------------------------------------------------------------
-- 12. Depois do rollback: nada vazou
-- ---------------------------------------------------------------------------
select tests.check('apos a suite: SF-v1.4 continua vigente, SF-v1.5 preparada, inventario vazio',
    (select status from public.commercial_pricing_rules where version = 3) = 'active'
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_flag_sets)
    and not exists (select 1 from public.commercial_flag_set_inspections)
    and not exists (select 1 from public.commercial_exclusivity_orders where pricing_rule_version = 4));

select tests.finish('290_flag_production_pricing_sf_v15');
