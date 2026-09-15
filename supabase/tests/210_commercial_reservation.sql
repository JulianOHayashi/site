-- ===========================================================================
-- 210 — RESERVA COMERCIAL DE 30 MINUTOS e portão de titular
--
-- A suíte existe porque um defeito real atravessou toda a bateria anterior:
-- `create_commercial_checkout_intent` conferia `role = 'owner'`, literal
-- insatisfazível sob o CHECK que só admite `partner_owner`/`partner_manager`.
-- A RPC sempre reprovava, e ninguém percebeu — a única asserção sobre ela era
-- NEGATIVA (anon não executa). Por isso o primeiro teste aqui é POSITIVO: um
-- titular ativo de verdade contratando. Negativas sozinhas não provam que um
-- portão abre para quem deve.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- Fixtures: duas empresas ativas na MESMA região, cada uma com seu titular,
-- mais um gerente e um titular alheio.
-- ---------------------------------------------------------------------------
select r.id as reg210 from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'serra' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg210')::uuid, 210, 'forming', false)
returning id as excl210 \gset

insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl210')::uuid, 'pharmacy', 12, 'available')
returning id as opp210 \gset

-- Uma exclusividade corrente por região é garantido por índice único parcial.
-- Tiramos a corrente anterior desta região antes de promover a nossa.
update public.commercial_exclusivities set is_current = false
 where region_id = (:'reg210')::uuid and is_current;
update public.commercial_exclusivities set is_current = true
 where id = (:'excl210')::uuid;

select tests.mk_user('titular210.a@teste.local') as uid_a \gset
select tests.mk_user('titular210.b@teste.local') as uid_b \gset
select tests.mk_user('gerente210@teste.local')   as uid_g \gset
select tests.mk_user('alheio210@teste.local')    as uid_x \gset

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('21010001000197','Empresa A 210','a210@teste.local','Serra','ES')
returning id as app_a \gset
insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('21020002000112','Empresa B 210','b210@teste.local','Serra','ES')
returning id as app_b \gset

insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app_a')::uuid,'21010001000197','Empresa A 210','a210@teste.local',
        'Serra','ES','active')
returning id as comp_a \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app_b')::uuid,'21020002000112','Empresa B 210','b210@teste.local',
        'Serra','ES','active')
returning id as comp_b \gset

-- Terceira empresa so para o titular SUSPENSO: o indice scm_um_owner_vivo_idx
-- admite um unico owner vivo (active|suspended) por empresa.
insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('21030003000148','Empresa C 210','c210@teste.local','Serra','ES')
returning id as app_c \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app_c')::uuid,'21030003000148','Empresa C 210','c210@teste.local',
        'Serra','ES','active')
returning id as comp_c \gset

insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'comp_a')::uuid, (:'uid_a')::uuid, 'partner_owner',
        'Titular A 210', 'application_promotion', 'active'),
       ((:'comp_a')::uuid, (:'uid_g')::uuid, 'partner_manager',
        'Gerente 210', 'manager_invite', 'active'),
       ((:'comp_b')::uuid, (:'uid_b')::uuid, 'partner_owner',
        'Titular B 210', 'application_promotion', 'active'),
       -- Titular SUSPENSO: papel certo, vinculo inativo. Tem de ser recusado.
       ((:'comp_c')::uuid, (:'uid_x')::uuid, 'partner_owner',
        'Titular Suspenso 210', 'application_promotion', 'suspended');

-- ---------------------------------------------------------------------------
-- 1. O TESTE QUE FALTAVA: titular ativo consegue reservar.
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_a');
select public.create_commercial_checkout_intent(
  (:'comp_a')::uuid, 'pharmacy', 'direct_benefits') as r_ok \gset
commit;

select tests.check('titular ativo (partner_owner) CONSEGUE criar a intencao',
    ((:'r_ok')::jsonb ->> 'ok') = 'true'
    and ((:'r_ok')::jsonb ->> 'already') = 'false'
    and ((:'r_ok')::jsonb ->> 'status') = 'draft');
select tests.check('a intencao fica ligada a oportunidade resolvida no servidor',
    ((:'r_ok')::jsonb ->> 'opportunity_id') = :'opp210'
    and ((:'r_ok')::jsonb ->> 'exclusivity_id') = :'excl210'
    and ((:'r_ok')::jsonb ->> 'region_id') = :'reg210');
select tests.check('a oportunidade passou a reservada',
    (select status = 'reserved' and reserved_until is not null
       from public.commercial_opportunities where id = :'opp210'));

-- 30 minutos EXATOS, derivados de now() do banco.
select tests.check('expiracao = tempo do servidor + 30 minutos',
    ((:'r_ok')::jsonb ->> 'reservation_minutes')::int = 30
    and (select o.reserved_until = i.reserved_until
           from public.commercial_opportunities o, public.commercial_checkout_intents i
          where o.id = :'opp210' and i.id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid)
    and (select abs(extract(epoch from
           (i.reserved_until - (i.created_at + interval '30 minutes')))) < 1
           from public.commercial_checkout_intents i
          where i.id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid));

-- Instantâneo econômico: do servidor, e coerente com a Comercial V2.
select tests.check('valores monetarios vem do calculo V2 do servidor',
    ((:'r_ok')::jsonb ->> 'economic_value_cents')::bigint = 1999900
    and ((:'r_ok')::jsonb ->> 'user_pool_cents')::bigint = 1335459
    and ((:'r_ok')::jsonb ->> 'bdflow_ops_investment_cents')::bigint = 664441
    and ((:'r_ok')::jsonb ->> 'nominal_quantity')::int = 12
    and ((:'r_ok')::jsonb ->> 'fidelized') = 'false'
    and ((:'r_ok')::jsonb ->> 'payment_method') = 'pix');
select tests.check('economico = pool + BDFlow na linha gravada',
    (select economic_value_cents = user_pool_cents + bdflow_ops_investment_cents
       from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid));

-- Nicho INTEIRO: a quantidade e a da oportunidade, nao um parametro.
select tests.check('nicho inteiro: quantidade da intencao = da oportunidade',
    (select i.nominal_quantity = o.contracted_quantity
       from public.commercial_checkout_intents i, public.commercial_opportunities o
      where i.id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid and o.id = :'opp210'));

-- ---------------------------------------------------------------------------
-- 2. O titular LE a propria intencao (a politica RLS tambem estava quebrada).
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_a');
select tests.check('titular enxerga a propria intencao via RLS',
    (select count(*) from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid) = 1);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_b');
select tests.check('titular de OUTRA empresa nao enxerga a intencao alheia',
    (select count(*) from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid) = 0);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_g');
select tests.check('gerente nao enxerga a intencao comercial',
    (select count(*) from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid) = 0);
rollback;

-- ---------------------------------------------------------------------------
-- 3. Quem NAO pode reservar continua nao podendo.
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_g');
select public.create_commercial_checkout_intent(
  (:'comp_a')::uuid, 'pharmacy', 'direct_benefits') as r_ger \gset
select tests.check('GERENTE e recusado: nao decide contratacao comercial',
    ((:'r_ger')::jsonb ->> 'ok') = 'false'
    and ((:'r_ger')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_b');
select public.create_commercial_checkout_intent(
  (:'comp_a')::uuid, 'pharmacy', 'direct_benefits') as r_alheio \gset
select tests.check('titular de OUTRA empresa e recusado na empresa alheia',
    ((:'r_alheio')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_x');
select public.create_commercial_checkout_intent(
  (:'comp_c')::uuid, 'pharmacy', 'direct_benefits') as r_inativo \gset
select tests.check('titular SUSPENSO e recusado',
    ((:'r_inativo')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

-- Precisa rodar COMO anon: fora de impersonation o teste roda como superusuario
-- e a checagem passaria por nao encontrar erro nenhum — falso verde.
begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao executa a RPC de checkout',
  format($sql$select public.create_commercial_checkout_intent(%L,'pharmacy','direct_benefits')$sql$,
         :'comp_a'),
  'permission denied');
commit;

-- ---------------------------------------------------------------------------
-- 4. Reserva viva nao pode ser roubada.
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_b');
select public.create_commercial_checkout_intent(
  (:'comp_b')::uuid, 'pharmacy', 'direct_benefits') as r_roubo \gset
select tests.check('segunda empresa NAO toma reserva viva de terceiro',
    ((:'r_roubo')::jsonb ->> 'ok') = 'false'
    and ((:'r_roubo')::jsonb ->> 'reason') = 'opportunity_reserved');
rollback;

select tests.check('nenhuma intencao foi criada para a segunda empresa',
    (select count(*) from public.commercial_checkout_intents
      where company_id = :'comp_b') = 0);

-- ---------------------------------------------------------------------------
-- 5. Retentativa do MESMO titular e idempotente e NAO estica o prazo.
-- ---------------------------------------------------------------------------
select (select reserved_until::text from public.commercial_checkout_intents
         where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid) as ate_antes \gset

begin;
select tests.impersonate('authenticated', :'uid_a');
select public.create_commercial_checkout_intent(
  (:'comp_a')::uuid, 'pharmacy', 'direct_benefits') as r_retry \gset
commit;

select tests.check('retentativa devolve a MESMA intencao, marcada already',
    ((:'r_retry')::jsonb ->> 'ok') = 'true'
    and ((:'r_retry')::jsonb ->> 'already') = 'true'
    and ((:'r_retry')::jsonb ->> 'intent_id') = ((:'r_ok')::jsonb ->> 'intent_id'));
-- Renovar a cada F5 deixaria qualquer titular segurar a oportunidade eternamente.
select tests.check('retentativa NAO estica o prazo da reserva',
    (select reserved_until::text from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid) = :'ate_antes');
select tests.check('nenhuma intencao duplicada foi criada',
    (select count(*) from public.commercial_checkout_intents
      where opportunity_id = :'opp210' and status = 'draft') = 1);

-- ---------------------------------------------------------------------------
-- 6. Reserva VENCIDA nao bloqueia para sempre.
-- Envelhecemos a reserva pelo banco (o teste e superusuario aqui); o servidor
-- continua sendo a autoridade de tempo dentro da RPC.
-- ---------------------------------------------------------------------------
update public.commercial_opportunities
   set reserved_until = now() - interval '1 minute' where id = :'opp210';
update public.commercial_checkout_intents
   set reserved_until = now() - interval '1 minute'
 where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid;

begin;
select tests.impersonate('authenticated', :'uid_b');
select public.create_commercial_checkout_intent(
  (:'comp_b')::uuid, 'pharmacy', 'direct_benefits') as r_reclaim \gset
commit;

select tests.check('reserva VENCIDA e recuperada por outra empresa',
    ((:'r_reclaim')::jsonb ->> 'ok') = 'true'
    and ((:'r_reclaim')::jsonb ->> 'already') = 'false'
    and ((:'r_reclaim')::jsonb ->> 'intent_id') <> ((:'r_ok')::jsonb ->> 'intent_id'));
select tests.check('a intencao vencida foi cancelada, nao reescrita',
    (select status = 'cancelled' from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid));
select tests.check('segue existindo UMA unica reserva viva na oportunidade',
    (select count(*) from public.commercial_checkout_intents
      where opportunity_id = :'opp210' and status = 'draft'
        and reserved_until > now()) = 1);
select tests.check('o instantaneo economico da intencao cancelada NAO mudou',
    (select economic_value_cents = 1999900 and user_pool_cents = 1335459
       from public.commercial_checkout_intents
      where id = ((:'r_ok')::jsonb ->> 'intent_id')::uuid));

-- ---------------------------------------------------------------------------
-- 7. O navegador nao escreve nada: a tabela nao aceita DML de papel de API.
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_a');
select tests.check_raises('titular nao INSERE intencao diretamente',
  format($sql$insert into public.commercial_checkout_intents
    (company_id, niche_code, status, pricing_rule_version,
     benefit_distribution_policy_version, fidelized, payment_method,
     benefit_settlement_mode, currency, nominal_quantity,
     economic_value_cents, user_pool_cents, bdflow_ops_investment_cents,
     cash_user_pool_funding_cents, total_monetary_funding_required_cents,
     created_by)
   values (%L,'pharmacy','draft',2,2,true,'credit_card','direct_benefits',
           'BRL',12,1,1,0,0,0,%L)$sql$, :'comp_a', :'uid_a'),
  'permission denied');
select tests.check_raises('titular nao ALTERA valores nem expiracao da intencao',
  format($sql$update public.commercial_checkout_intents
            set economic_value_cents = 1, reserved_until = now() + interval '30 days'
          where company_id = %L$sql$, :'comp_a'),
  'permission denied');
select tests.check_raises('titular nao mexe na oportunidade',
  format($sql$update public.commercial_opportunities
            set status = 'available', reserved_until = null where id = %L$sql$, :'opp210'),
  'permission denied');
rollback;

-- A assinatura da RPC nao aceita preco, fidelidade, metodo, quantidade,
-- oportunidade nem expiracao: nao ha por onde o navegador enviar.
select tests.check('a RPC aceita exatamente tres argumentos, todos nao-monetarios',
    (select pg_get_function_identity_arguments(p.oid)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'create_commercial_checkout_intent')
    = 'p_company_id uuid, p_niche_code text, p_benefit_settlement_mode text');

-- ---------------------------------------------------------------------------
-- 8. Segurança estrutural da funcao alterada.
-- ---------------------------------------------------------------------------
select tests.check('RPC segue SECURITY DEFINER com search_path fixo',
    (select p.prosecdef
        and coalesce(array_to_string(p.proconfig,','),'') = 'search_path=pg_catalog'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'create_commercial_checkout_intent'));
select tests.check('anon e service_role nao executam a RPC de checkout',
    not has_function_privilege('anon',
      'public.create_commercial_checkout_intent(uuid,text,text)','EXECUTE')
    and not has_function_privilege('service_role',
      'public.create_commercial_checkout_intent(uuid,text,text)','EXECUTE'));
select tests.check('a RPC usa o helper canonico de titular, sem literal novo',
    (select prosrc like '%m2_is_company_owner%' and prosrc not like '%role = ''owner''%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'create_commercial_checkout_intent'));
select tests.check('a RPC serializa a oportunidade com FOR UPDATE',
    (select prosrc like '%FOR UPDATE%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'create_commercial_checkout_intent'));
select tests.check('a expiracao e derivada de now() do banco, nao de parametro',
    (select prosrc like '%now() + interval ''30 minutes''%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'create_commercial_checkout_intent'));

select tests.finish('210_commercial_reservation');
