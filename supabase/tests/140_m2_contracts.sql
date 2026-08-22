-- ============================================================================
-- SUITE 140 — Instrumentos contratuais (R6). Continua sobre 100/110/120.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_titular from auth.users where email = 'titular_m2@teste.local' \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select m.company_id as company1 from public.site_company_members m
 where m.role='partner_owner'
   and m.auth_user_id=(select id from auth.users where email='titular_m2@teste.local') \gset
select auth_user_id as uid_mgr from public.site_company_members
 where company_id = :'company1' and role='partner_manager' limit 1 \gset

-- ---------------------------------------------------------------------------
-- Autorização e validação de entrada
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check_raises('nao-admin nao registra acordo mestre',
  format($sql$select public.admin_register_master_agreement(
    %L,'v1',now() - interval '1 day','Ana Representante','doc://a1')$sql$, :'company1'),
  'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_master_agreement(
    (:'company1')::uuid,'v1', now() + interval '1 day','Ana','doc://a1') as fut \gset
select tests.check('assinatura no futuro e recusada',
    ((:'fut')::jsonb ->> 'reason') = 'invalid_signature_date');
select public.admin_register_master_agreement(
    (:'company1')::uuid,'v1', now() - interval '1 day','Ana') as sem_ev \gset
select tests.check('acordo sem referencia nem hash e recusado',
    ((:'sem_ev')::jsonb ->> 'reason') = 'invalid_data');
select public.admin_register_master_agreement(
    (:'company1')::uuid,'v1', now() - interval '1 day','Ana Representante','doc://acordo-1') as ag1 \gset
select tests.check('acordo mestre registrado', ((:'ag1')::jsonb ->> 'ok') = 'true');
commit;

select ((:'ag1')::jsonb ->> 'agreement_id') as ag1id \gset
select signed_at as ag1_signed from public.commercial_master_agreements where id = :'ag1id' \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_master_agreement(
    (:'company1')::uuid,'v1', (:'ag1_signed')::timestamptz,'Ana Representante','doc://acordo-1') as ag1b \gset
select tests.check('mesma versao e assinatura -> idempotente',
    ((:'ag1b')::jsonb ->> 'already') = 'true'
    and ((:'ag1b')::jsonb ->> 'agreement_id') = :'ag1id');
-- Nova versão supersede preservando o histórico.
select public.admin_register_master_agreement(
    (:'company1')::uuid,'v2', now() - interval '1 hour','Ana Representante','doc://acordo-2') as ag2 \gset
select tests.check('nova versao cria acordo novo', ((:'ag2')::jsonb ->> 'already') = 'false');
commit;

select tests.check('apenas um acordo vigente por empresa',
    (select count(*) from public.commercial_master_agreements
      where company_id = :'company1' and status = 'signed') = 1);
select tests.check('acordo anterior fica superseded, sem apagar historico',
    (select status = 'superseded' and superseded_at is not null
       from public.commercial_master_agreements where id = :'ag1id')
    and (select count(*) from public.commercial_master_agreements
          where company_id = :'company1') = 2);
select tests.check('novo acordo aponta o que ele supersede',
    (select supersedes_agreement_id = (:'ag1id')::uuid
       from public.commercial_master_agreements
      where id = ((:'ag2')::jsonb ->> 'agreement_id')::uuid));

-- Imutabilidade do acordo
select tests.check_raises('evidencia do acordo e imutavel',
  format($sql$update public.commercial_master_agreements
           set document_hash = 'x' where id = %L$sql$, :'ag1id'),
  'acordo_imutavel');
select tests.check_raises('acordo nao pode ser excluido',
  format($sql$delete from public.commercial_master_agreements where id = %L$sql$, :'ag1id'),
  'acordo_imutavel');

-- ---------------------------------------------------------------------------
-- Pedido de Exclusividade: modelo técnico e invariantes
-- ---------------------------------------------------------------------------
insert into public.commercial_exclusivities
    (id, region_id, sequence_number, status, is_current, planned_start_at)
values (gen_random_uuid(),
        (select id from public.commercial_regions where uf='ES' limit 1),
        1, 'forming', true, now() + interval '30 days')
returning id as excl1 \gset

insert into public.commercial_opportunities
    (exclusivity_id, niche_code, contracted_quantity, status)
select :'excl1', n.code, n.contracted_quantity, 'available'
  from public.commercial_niches n where n.is_active;

select tests.check('exclusividade com 6 oportunidades e 84 unidades',
    (select count(*) from public.commercial_opportunities where exclusivity_id = :'excl1') = 6
    and (select sum(contracted_quantity) from public.commercial_opportunities
          where exclusivity_id = :'excl1') = 84);

select id as opp_pharm from public.commercial_opportunities
 where exclusivity_id = :'excl1' and niche_code = 'pharmacy' \gset
select id as ag_vigente from public.commercial_master_agreements
 where company_id = :'company1' and status='signed' \gset

-- Insere um pedido em draft com snapshot vindo do cálculo autoritativo.
insert into public.commercial_exclusivity_orders
  (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
   region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
   economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
   expected_operation_start, registered_by)
select :'excl1', :'opp_pharm', :'company1', :'ag_vigente', 'pharmacy',
       (select region_id from public.commercial_exclusivities where id = :'excl1'),
       12,
       (pr->>'pricing_rule_version')::int, false, 'BRL',
       (pr->>'economic_value_cents')::bigint,
       (pr->>'pool_bps')::int,
       (pr->>'contractual_pool_cents')::bigint,
       (pr->>'bdflow_due_cents')::bigint,
       (now() + interval '30 days')::date, :'uid_admin'
  from (select public.calculate_niche_contract_pricing('pharmacy', false) as pr) t
returning id as ord1 \gset

select tests.check('pedido nasce em draft com pagamento pendente',
    (select status='draft' and payment_status='pending'
       from public.commercial_exclusivity_orders where id = :'ord1'));
select tests.check('snapshot economico do pedido confere com a tabela vigente',
    (select economic_value_cents=1999900 and contractual_pool_cents=1399930
        and bdflow_due_cents=599970
       from public.commercial_exclusivity_orders where id = :'ord1'));

-- Invariante econômica barrada no banco
select tests.check_raises('invariante economico = pool + devido e obrigatoria',
  format($sql$insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     expected_operation_start, registered_by)
    values (%L, (select id from public.commercial_opportunities
                  where exclusivity_id=%L and niche_code='mens_clothing'),
            %L, %L, 'mens_clothing',
            (select region_id from public.commercial_exclusivities where id=%L),
            12, 1, false, 'BRL', 1999900, 7000, 1399930, 1, current_date, %L)$sql$,
    :'excl1', :'excl1', :'company1', :'ag_vigente', :'excl1', :'uid_admin'),
  'ceo_invariante_economica');

-- Pagamento não existe sem assinatura
select tests.check_raises('pagamento confirmado exige pedido assinado',
  format($sql$update public.commercial_exclusivity_orders
           set payment_status='confirmed', payment_confirmed_at=now(),
               payment_confirmed_by=%L, payment_amount_cents=599970
         where id=%L$sql$, :'uid_admin', :'ord1'),
  'ceo_pagamento_exige_assinatura');

-- Assinado exige instrumento completo
select tests.check_raises('pedido assinado exige instrumento completo',
  format($sql$update public.commercial_exclusivity_orders
           set status='signed' where id=%L$sql$, :'ord1'),
  'ceo_assinatura_coerente');

-- Snapshot imutável e sem DELETE
select tests.check_raises('snapshot economico do pedido e imutavel',
  format($sql$update public.commercial_exclusivity_orders
           set economic_value_cents=1 where id=%L$sql$, :'ord1'),
  'pedido_imutavel');
select tests.check_raises('pedido nao pode ser excluido',
  format($sql$delete from public.commercial_exclusivity_orders where id=%L$sql$, :'ord1'),
  'pedido_imutavel');

-- Unicidade: um nicho por exclusividade; um CNPJ em um nicho
select tests.check_raises('mesmo CNPJ nao ocupa segundo nicho na exclusividade',
  format($sql$insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     expected_operation_start, registered_by)
    values (%L, (select id from public.commercial_opportunities
                  where exclusivity_id=%L and niche_code='womens_clothing'),
            %L, %L, 'womens_clothing',
            (select region_id from public.commercial_exclusivities where id=%L),
            12, 1, false, 'BRL', 1999900, 7000, 1399930, 599970, current_date, %L)$sql$,
    :'excl1', :'excl1', :'company1', :'ag_vigente', :'excl1', :'uid_admin'),
  'ceo_empresa_por_exclusividade_idx');

-- ---------------------------------------------------------------------------
-- RLS financeira: owner vê; MANAGER NÃO
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('owner ve o proprio acordo vigente e o proprio pedido',
    (select count(*) from public.commercial_master_agreements) = 2
    and (select count(*) from public.commercial_exclusivity_orders) = 1);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_mgr');
select tests.check('MANAGER nao ve acordo nem pedido (sem acesso financeiro)',
    (select count(*) from public.commercial_master_agreements) = 0
    and (select count(*) from public.commercial_exclusivity_orders) = 0);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check('terceiro nao ve contrato algum',
    (select count(*) from public.commercial_exclusivity_orders) = 0);
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao le pedidos',
  'select count(*) from public.commercial_exclusivity_orders', 'permission denied');
rollback;

-- Nenhum texto jurídico de produção foi introduzido.
select tests.check('nenhum texto juridico de producao nas tabelas de contrato',
    (select count(*) from information_schema.columns
      where table_schema='public'
        and table_name in ('commercial_master_agreements','commercial_exclusivity_orders')
        and column_name in ('content','clauses','legal_text','body')) = 0);

select tests.finish('140_m2_contracts');
