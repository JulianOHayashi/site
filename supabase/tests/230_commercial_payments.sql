-- ===========================================================================
-- 230 — PAGAMENTO COMERCIAL: estados, conciliação e concorrência
--
-- Nenhuma chamada a provedor acontece aqui. O que se prova é o que o banco
-- aceita e o que ele recusa — inclusive a recusa que importa mais: webhook
-- forjado não produz `paid`.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

select tests.mk_user('admin230@teste.local') as uid_admin \gset
insert into public.site_admins (user_id) values ((:'uid_admin')::uuid)
on conflict do nothing;

select r.id as reg230 from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'cariacica' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg230')::uuid, 230, 'forming', false)
returning id as excl230 \gset

insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl230')::uuid, 'womens_footwear', 12, 'available')
returning id as opp230 \gset

update public.commercial_exclusivities set is_current = false
 where region_id = (:'reg230')::uuid and is_current;
update public.commercial_exclusivities set is_current = true
 where id = (:'excl230')::uuid;

select tests.mk_user('titular230@teste.local') as uid_t \gset
select tests.mk_user('gerente230@teste.local') as uid_g \gset

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('23010001000112','Empresa 230','e230@teste.local','Cariacica','ES')
returning id as app230 \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app230')::uuid,'23010001000112','Empresa 230','e230@teste.local',
        'Cariacica','ES','active')
returning id as comp230 \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'comp230')::uuid,(:'uid_t')::uuid,'partner_owner',
        'Titular 230','application_promotion','active'),
       ((:'comp230')::uuid,(:'uid_g')::uuid,'partner_manager',
        'Gerente 230','manager_invite','active');

-- Um CNPJ contrata UM nicho por exclusividade (ceo_empresa_por_exclusividade_idx).
-- Cada cenario abaixo precisa, portanto, da propria empresa.
select tests.mk_user('titular230b@teste.local') as uid_tb \gset
select tests.mk_user('titular230c@teste.local') as uid_tc \gset
insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('23020002000148','Empresa 230B','b230@teste.local','Cariacica','ES')
returning id as app230b \gset
insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('23030003000173','Empresa 230C','c230@teste.local','Cariacica','ES')
returning id as app230c \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app230b')::uuid,'23020002000148','Empresa 230B','b230@teste.local','Cariacica','ES','active')
returning id as comp230b \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app230c')::uuid,'23030003000173','Empresa 230C','c230@teste.local','Cariacica','ES','active')
returning id as comp230c \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'comp230b')::uuid,(:'uid_tb')::uuid,'partner_owner',
        'Titular 230B','application_promotion','active'),
       ((:'comp230c')::uuid,(:'uid_tc')::uuid,'partner_owner',
        'Titular 230C','application_promotion','active');

-- Termos publicados e acordo mestre registrado: pré-requisitos do contrato.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_publish_legal_document(
  'commercial_order_terms','v230','Termos 230',
  'CONTEUDO DE TESTE (nao juridico)','hash-230') as r_pub \gset
select public.admin_register_master_agreement(
  (:'comp230')::uuid,'AM-230', now() - interval '1 day',
  'Titular 230','doc://acordo-230') as r_am \gset
select public.admin_register_master_agreement(
  (:'comp230b')::uuid,'AM-230B', now() - interval '1 day',
  'Titular 230B','doc://acordo-230b');
select public.admin_register_master_agreement(
  (:'comp230c')::uuid,'AM-230C', now() - interval '1 day',
  'Titular 230C','doc://acordo-230c');
commit;

-- Reserva -> contrato -> aceite -> pedido.
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.create_commercial_checkout_intent(
  (:'comp230')::uuid,'womens_footwear','direct_benefits') as r_i \gset
commit;
select ((:'r_i')::jsonb ->> 'intent_id') as int230 \gset

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.advance_checkout_intent_to_contract((:'int230')::uuid);
select public.accept_commercial_order_terms((:'int230')::uuid);
select public.finalize_commercial_order_from_intent((:'int230')::uuid) as r_fin \gset
commit;
select ((:'r_fin')::jsonb ->> 'order_id') as ord230 \gset
select tests.check('pedido criado e pronto para pagamento',
    ((:'r_fin')::jsonb ->> 'ok') = 'true');

-- ---------------------------------------------------------------------------
-- 1. Abertura da tentativa: só titular, só no estado certo
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_g');
select public.open_commercial_payment_attempt((:'ord230')::uuid) as r_ger \gset
select tests.check('GERENTE nao abre pagamento',
    ((:'r_ger')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao abre pagamento',
  format($sql$select public.open_commercial_payment_attempt(%L)$sql$, :'ord230'),
  'permission denied');
commit;

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.open_commercial_payment_attempt((:'ord230')::uuid) as r_op \gset
commit;
select tests.check('titular abre a tentativa de pagamento',
    ((:'r_op')::jsonb ->> 'ok') = 'true'
    and ((:'r_op')::jsonb ->> 'already') = 'false');
select ((:'r_op')::jsonb ->> 'payment_id') as pay230 \gset

-- Nao fidelizado -> PIX, valor do instantaneo, prazo da reserva.
select tests.check('nao fidelizado recebe PIX, sem parcelas',
    ((:'r_op')::jsonb ->> 'payment_method') = 'pix'
    and ((:'r_op')::jsonb -> 'installments') = 'null'::jsonb);
select tests.check('valor vem do instantaneo contratual do pedido',
    (select p.amount_cents = o.total_monetary_funding_required_cents
        and p.amount_cents = 664441
       from public.commercial_payments p, public.commercial_exclusivity_orders o
      where p.id = :'pay230' and o.id = :'ord230'));
select tests.check('prazo do pagamento = reserved_until da intencao, sem recalculo',
    (select p.expires_at = i.reserved_until
       from public.commercial_payments p, public.commercial_checkout_intents i
      where p.id = :'pay230' and i.id = :'int230'));

-- Idempotencia: a MESMA chave, sem recurso novo.
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.open_commercial_payment_attempt((:'ord230')::uuid) as r_op2 \gset
commit;
select tests.check('reabrir devolve a MESMA tentativa e a mesma chave',
    ((:'r_op2')::jsonb ->> 'already') = 'true'
    and ((:'r_op2')::jsonb ->> 'payment_id') = :'pay230'
    and ((:'r_op2')::jsonb ->> 'idempotency_key') = ((:'r_op')::jsonb ->> 'idempotency_key'));
select tests.check('existe UMA unica tentativa viva para o pedido',
    (select count(*) from public.commercial_payments
      where commercial_order_id = :'ord230'
        and status in ('created','pending','paid')) = 1);
select tests.check_raises('tentativa viva duplicada e impossivel',
  format($sql$insert into public.commercial_payments
    (commercial_order_id, checkout_intent_id, provider, payment_method,
     amount_cents, status, expires_at, idempotency_key)
   values (%L,%L,'pagarme','pix',664441,'created', now()+interval '10 minutes','outra-chave')$sql$,
   :'ord230', :'int230'),
  'cp_tentativa_viva_idx');

-- ---------------------------------------------------------------------------
-- 2. Conciliacao: webhook sozinho NAO paga
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_t');
select tests.check_raises('titular nao confirma pagamento',
  format($sql$select public.prov_confirm_commercial_payment(%L,'paid',664441,'pix',null)$sql$,
         :'pay230'),
  'permission denied');
select tests.check_raises('titular nao escreve na tabela de pagamentos',
  format($sql$update public.commercial_payments set status='paid' where id=%L$sql$, :'pay230'),
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
-- Valor divergente: o que o provedor diz nao bate com o instantaneo local.
select public.prov_confirm_commercial_payment(
  (:'pay230')::uuid,'paid',1,'pix',null) as r_valor \gset
select tests.check('valor divergente NAO paga',
    ((:'r_valor')::jsonb ->> 'reason') = 'amount_mismatch');
-- Metodo divergente.
select public.prov_confirm_commercial_payment(
  (:'pay230')::uuid,'paid',664441,'credit_card',null) as r_metodo \gset
select tests.check('metodo divergente NAO paga',
    ((:'r_metodo')::jsonb ->> 'reason') = 'method_mismatch');
-- Status que nao e pago.
select public.prov_confirm_commercial_payment(
  (:'pay230')::uuid,'pending',664441,'pix',null) as r_status \gset
select tests.check('status de provedor diferente de pago NAO paga',
    ((:'r_status')::jsonb ->> 'reason') = 'provider_status_not_paid');
commit;

select tests.check('nenhuma divergencia mudou o estado local',
    (select status = 'created' and paid_at is null
       from public.commercial_payments where id = :'pay230')
    and (select payment_status = 'pending'
       from public.commercial_exclusivity_orders where id = :'ord230')
    and (select status = 'payment_pending'
       from public.commercial_opportunities where id = :'opp230'));

-- Referencia divergente, depois de o provedor registrar a dele.
begin;
select tests.impersonate('service_role', null);
select public.prov_record_payment_identifiers(
  (:'pay230')::uuid,'or_230','ch_230',null,'bdflow-ref-230') as r_ids \gset
select tests.check('identificadores do provedor sao registrados',
    ((:'r_ids')::jsonb ->> 'ok') = 'true'
    and ((:'r_ids')::jsonb ->> 'status') = 'pending');
select public.prov_confirm_commercial_payment(
  (:'pay230')::uuid,'paid',664441,'pix','referencia-de-outro-pedido') as r_ref \gset
select tests.check('referencia divergente NAO paga',
    ((:'r_ref')::jsonb ->> 'reason') = 'reference_mismatch');
commit;

-- ---------------------------------------------------------------------------
-- 3. Conciliacao correta: o unico caminho para pago
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('service_role', null);
select public.prov_confirm_commercial_payment(
  (:'pay230')::uuid,'paid',664441,'pix','bdflow-ref-230') as r_pago \gset
commit;
select tests.check('conciliacao correta paga',
    ((:'r_pago')::jsonb ->> 'ok') = 'true'
    and ((:'r_pago')::jsonb ->> 'status') = 'paid');
select tests.check('oportunidade chega a CONTRACTED, sem reserva pendurada',
    (select status = 'contracted' and reserved_until is null
       from public.commercial_opportunities where id = :'opp230'));
select tests.check('pedido confirmado com origem PROVEDOR, sem ator humano falso',
    (select payment_status = 'confirmed'
        and payment_confirmed_source = 'payment_provider'
        and payment_confirmed_by is null
        and payment_confirmed_at is not null
        and payment_amount_cents = 664441
       from public.commercial_exclusivity_orders where id = :'ord230'));
select tests.check('intencao chega a paid',
    (select status = 'paid' from public.commercial_checkout_intents where id = :'int230'));
select tests.check('paid_at e tempo do BANCO',
    (select paid_at <= now() and paid_at > now() - interval '5 minutes'
       from public.commercial_payments where id = :'pay230'));

begin;
select tests.impersonate('service_role', null);
select public.prov_confirm_commercial_payment(
  (:'pay230')::uuid,'paid',664441,'pix','bdflow-ref-230') as r_pago2 \gset
select tests.check('confirmacao repetida e idempotente',
    ((:'r_pago2')::jsonb ->> 'already') = 'true');
commit;

select tests.check_raises('pagamento confirmado nao volta atras',
  format($sql$update public.commercial_payments set status='cancelled' where id=%L$sql$, :'pay230'),
  'pagamento_imutavel');
select tests.check_raises('valor e prazo do pagamento sao imutaveis',
  format($sql$update public.commercial_payments set amount_cents=1 where id=%L$sql$, :'pay230'),
  'pagamento_imutavel');

-- ---------------------------------------------------------------------------
-- 4. Pagamento TARDIO nao rouba oportunidade ja reatribuida
-- ---------------------------------------------------------------------------
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl230')::uuid, 'mens_footwear', 12, 'available')
returning id as opp_late \gset

begin;
select tests.impersonate('authenticated', :'uid_tb');
select public.create_commercial_checkout_intent(
  (:'comp230b')::uuid,'mens_footwear','direct_benefits') as r_il \gset
commit;
select ((:'r_il')::jsonb ->> 'intent_id') as int_late \gset

begin;
select tests.impersonate('authenticated', :'uid_tb');
select public.advance_checkout_intent_to_contract((:'int_late')::uuid);
select public.accept_commercial_order_terms((:'int_late')::uuid);
select public.finalize_commercial_order_from_intent((:'int_late')::uuid) as r_fl \gset
select public.open_commercial_payment_attempt(
  ((:'r_fl')::jsonb ->> 'order_id')::uuid) as r_pl \gset
commit;
select ((:'r_pl')::jsonb ->> 'payment_id') as pay_late \gset

-- A oportunidade e legitimamente devolvida ao mercado (prazo vencido).
update public.commercial_opportunities
   set status = 'available', reserved_until = null where id = :'opp_late';

begin;
select tests.impersonate('service_role', null);
select public.prov_confirm_commercial_payment(
  (:'pay_late')::uuid,'paid',664441,'pix',null) as r_tardio \gset
commit;

select tests.check('pagamento TARDIO nao contrata oportunidade reatribuida',
    ((:'r_tardio')::jsonb ->> 'ok') = 'false'
    and ((:'r_tardio')::jsonb ->> 'reason') = 'late_payment_unreconciled');
select tests.check('a oportunidade NAO foi contratada pelo pagamento tardio',
    (select status = 'available' from public.commercial_opportunities where id = :'opp_late'));
select tests.check('a tentativa fica em estado excepcional, com motivo registrado',
    (select status = 'late_unreconciled' and exception_reason is not null
       from public.commercial_payments where id = :'pay_late'));
select tests.check('o pagamento tardio NAO marcou o pedido como pago',
    (select payment_status = 'pending'
       from public.commercial_exclusivity_orders
      where id = ((:'r_fl')::jsonb ->> 'order_id')::uuid));

-- ---------------------------------------------------------------------------
-- 5. Expiracao sem pagamento
-- ---------------------------------------------------------------------------
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl230')::uuid, 'pharmacy', 12, 'available')
returning id as opp_exp \gset

begin;
select tests.impersonate('authenticated', :'uid_tc');
select public.create_commercial_checkout_intent(
  (:'comp230c')::uuid,'pharmacy','direct_benefits') as r_ie \gset
commit;
select ((:'r_ie')::jsonb ->> 'intent_id') as int_exp \gset

begin;
select tests.impersonate('authenticated', :'uid_tc');
select public.advance_checkout_intent_to_contract((:'int_exp')::uuid);
select public.accept_commercial_order_terms((:'int_exp')::uuid);
select public.finalize_commercial_order_from_intent((:'int_exp')::uuid) as r_fe \gset
select public.open_commercial_payment_attempt(
  ((:'r_fe')::jsonb ->> 'order_id')::uuid) as r_pe \gset
commit;
select ((:'r_pe')::jsonb ->> 'payment_id') as pay_exp \gset

begin;
select tests.impersonate('service_role', null);
select public.prov_expire_commercial_payment((:'pay_exp')::uuid) as r_cedo \gset
select tests.check('nao expira antes da hora',
    ((:'r_cedo')::jsonb ->> 'reason') = 'not_expired_yet');
commit;

-- Envelhecer o prazo exige desligar a protecao por um instante: `expires_at`
-- e IMUTAVEL de propria vontade, e isso e provado logo acima com
-- `pagamento_imutavel`. Aqui a manobra e de fixture, feita como superusuario,
-- porque nao ha como esperar trinta minutos dentro de um teste.
alter table public.commercial_payments disable trigger trg_cp_proteger;
update public.commercial_payments
   set expires_at = now() - interval '1 minute' where id = :'pay_exp';
alter table public.commercial_payments enable trigger trg_cp_proteger;

begin;
select tests.impersonate('service_role', null);
select public.prov_expire_commercial_payment((:'pay_exp')::uuid) as r_exp \gset
select tests.check('vencido sem pagamento: tentativa expira',
    ((:'r_exp')::jsonb ->> 'status') = 'expired');
commit;

select tests.check('oportunidade volta a ser reclamavel',
    (select status = 'available' and reserved_until is null
       from public.commercial_opportunities where id = :'opp_exp'));
select tests.check('historico contratual NAO foi apagado',
    (select count(*) from public.commercial_exclusivity_orders
      where id = ((:'r_fe')::jsonb ->> 'order_id')::uuid) = 1
    and (select count(*) from public.commercial_checkout_intents
      where id = :'int_exp') = 1);
select tests.check('nenhum centavo do instantaneo mudou na expiracao',
    (select economic_value_cents = 1999900 and contractual_pool_cents = 1335459
       from public.commercial_exclusivity_orders
      where id = ((:'r_fe')::jsonb ->> 'order_id')::uuid));

-- ---------------------------------------------------------------------------
-- 6. O que a tabela NAO guarda
-- ---------------------------------------------------------------------------
select tests.check('nao existe coluna de payload bruto, cartao ou segredo',
    (select count(*) from information_schema.columns
      where table_name = 'commercial_payments'
        and (column_name ~* 'raw|payload|card|cvv|secret|token|key'
             and column_name <> 'idempotency_key')) = 0);
-- O Postgres normaliza BETWEEN para >= e <=; a assercao olha a forma
-- normalizada, nao o texto que escrevemos.
select tests.check('parcelas so no cartao, e no maximo seis',
    (select pg_get_constraintdef(oid) like '%installments <= 6%'
        and pg_get_constraintdef(oid) like '%installments >= 1%'
        and pg_get_constraintdef(oid) like '%installments IS NULL%'
       from pg_constraint where conname = 'cp_parcelas_coerentes'));
select tests.check_raises('sete parcelas sao recusadas pelo banco',
  format($sql$insert into public.commercial_payments
    (commercial_order_id, checkout_intent_id, provider, payment_method,
     amount_cents, installments, status, expires_at, idempotency_key)
   values (%L,%L,'pagarme','credit_card',664441,7,'created',
           now()+interval '10 minutes','chave-sete-parcelas')$sql$,
   :'ord230', :'int230'),
  'cp_parcelas_coerentes');

select tests.finish('230_commercial_payments');
