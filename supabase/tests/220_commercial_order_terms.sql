-- ===========================================================================
-- 220 — TERMOS DO PEDIDO, ACEITE ELETRÔNICO E FINALIZAÇÃO
--
-- Prova a ponte reserva -> contrato -> awaiting_payment_provider. Nenhum
-- provedor de pagamento existe, e nenhum teste aqui finge que exista.
--
-- O aceite provado é ELETRÔNICO AUTENTICADO. Não é ICP-Brasil, não é
-- assinatura qualificada, não é certificado digital — e nada aqui afirma
-- que seja.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
-- Admin proprio: a suite tem de rodar isolada, sem depender de outra antes.
select tests.mk_user('admin220@teste.local') as uid_admin \gset
insert into public.site_admins (user_id) values ((:'uid_admin')::uuid)
on conflict do nothing;

select r.id as reg220 from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg220')::uuid, 220, 'forming', false)
returning id as excl220 \gset

insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl220')::uuid, 'mens_clothing', 12, 'available')
returning id as opp220 \gset

update public.commercial_exclusivities set is_current = false
 where region_id = (:'reg220')::uuid and is_current;
update public.commercial_exclusivities set is_current = true
 where id = (:'excl220')::uuid;

select tests.mk_user('titular220@teste.local')  as uid_t \gset
select tests.mk_user('gerente220@teste.local')  as uid_g \gset
select tests.mk_user('outro220@teste.local')    as uid_o \gset

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('22010001000150','Empresa 220','e220@teste.local','Viana','ES')
returning id as app220 \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app220')::uuid,'22010001000150','Empresa 220','e220@teste.local',
        'Viana','ES','active')
returning id as comp220 \gset

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('22020002000185','Empresa Outra 220','o220@teste.local','Viana','ES')
returning id as app_o220 \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app_o220')::uuid,'22020002000185','Empresa Outra 220','o220@teste.local',
        'Viana','ES','active')
returning id as comp_o220 \gset

insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'comp220')::uuid,  (:'uid_t')::uuid, 'partner_owner',
        'Titular Canonico 220', 'application_promotion', 'active'),
       ((:'comp220')::uuid,  (:'uid_g')::uuid, 'partner_manager',
        'Gerente 220', 'manager_invite', 'active'),
       ((:'comp_o220')::uuid,(:'uid_o')::uuid, 'partner_owner',
        'Titular Outro 220', 'application_promotion', 'active');

-- ---------------------------------------------------------------------------
-- 1. PUBLICAÇÃO — somente admin
-- ---------------------------------------------------------------------------
-- m1_exigir_admin LEVANTA excecao; nao devolve json. Por isso check_raises.
begin;
select tests.impersonate('authenticated', :'uid_t');
select tests.check_raises('titular NAO publica termos juridicos',
  $sql$select public.admin_publish_legal_document(
    'commercial_order_terms','v1-teste','Termos',
    'CONTEUDO DE TESTE (nao juridico)','hash-teste-1')$sql$,
  'not_authorized');
commit;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao executa a publicacao',
  $sql$select public.admin_publish_legal_document('commercial_order_terms','v9','T','C','H')$sql$,
  'permission denied');
commit;

begin;
select tests.impersonate('authenticated', :'uid_admin');
-- Evidência obrigatória: sem hash, sem conteúdo, sem versão -> recusa.
select public.admin_publish_legal_document(
  'commercial_order_terms','v1-teste','Termos','CONTEUDO','') as r_sem_hash \gset
select tests.check('publicacao exige content_hash',
    ((:'r_sem_hash')::jsonb ->> 'reason') = 'content_hash_required');
select public.admin_publish_legal_document(
  'commercial_order_terms','','Termos','CONTEUDO','h') as r_sem_ver \gset
select tests.check('publicacao exige versao',
    ((:'r_sem_ver')::jsonb ->> 'reason') = 'version_required');
select public.admin_publish_legal_document(
  'commercial_order_terms','v1-teste','Termos','','h') as r_sem_cont \gset
select tests.check('publicacao exige conteudo ou URL',
    ((:'r_sem_cont')::jsonb ->> 'reason') = 'content_required');
select public.admin_publish_legal_document(
  'tipo_inventado','v1','T','C','h') as r_tipo \gset
select tests.check('tipo fora da allowlist e recusado',
    ((:'r_tipo')::jsonb ->> 'reason') = 'doc_type_not_allowed');
commit;

-- Antes de existir documento, o aceite falha fechado.
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.create_commercial_checkout_intent(
  (:'comp220')::uuid, 'mens_clothing', 'direct_benefits') as r_int \gset
commit;
select tests.check('reserva criada para a formacao 220',
    ((:'r_int')::jsonb ->> 'ok') = 'true');
select ((:'r_int')::jsonb ->> 'intent_id') as intent220 \gset

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.advance_checkout_intent_to_contract((:'intent220')::uuid) as r_adv0 \gset
select public.accept_commercial_order_terms((:'intent220')::uuid) as r_sem_doc \gset
select tests.check('sem termos publicados, o aceite falha fechado',
    ((:'r_sem_doc')::jsonb ->> 'reason') = 'terms_not_published');
commit;

-- Agora o admin publica de verdade.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_publish_legal_document(
  'commercial_order_terms','v1-teste','Termos do pedido comercial',
  'CONTEUDO DE TESTE (nao juridico)','hash-teste-v1') as r_pub \gset
select tests.check('admin publica commercial_order_terms',
    ((:'r_pub')::jsonb ->> 'ok') = 'true'
    and ((:'r_pub')::jsonb ->> 'version') = 'v1-teste'
    and ((:'r_pub')::jsonb ->> 'content_hash') = 'hash-teste-v1');
-- Republicar a MESMA versao com o mesmo hash e idempotente.
select public.admin_publish_legal_document(
  'commercial_order_terms','v1-teste','Termos do pedido comercial',
  'CONTEUDO DE TESTE (nao juridico)','hash-teste-v1') as r_pub2 \gset
select tests.check('republicar versao identica e idempotente',
    ((:'r_pub2')::jsonb ->> 'already') = 'true');
-- Mesma versao com conteudo DIFERENTE reescreveria texto ja aceitavel.
select public.admin_publish_legal_document(
  'commercial_order_terms','v1-teste','Termos','OUTRO CONTEUDO','hash-diferente') as r_pub3 \gset
select tests.check('mesma versao com hash diferente e recusada',
    ((:'r_pub3')::jsonb ->> 'reason') = 'version_already_exists');
commit;

select tests.check('documento publicado carrega evidencia completa',
    (select status='published' and content_hash='hash-teste-v1'
        and published_at is not null and published_by is not null
        and effective_from is not null
       from public.legal_documents
      where doc_type='commercial_order_terms' and version='v1-teste'));

-- ---------------------------------------------------------------------------
-- 2. ACEITE — somente titular ativo
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_g');
select public.accept_commercial_order_terms((:'intent220')::uuid) as r_ace_ger \gset
select tests.check('GERENTE nao aceita o contrato comercial',
    ((:'r_ace_ger')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_o');
select public.accept_commercial_order_terms((:'intent220')::uuid) as r_ace_out \gset
select tests.check('titular de OUTRA empresa nao aceita',
    ((:'r_ace_out')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao executa o aceite',
  format($sql$select public.accept_commercial_order_terms(%L)$sql$, :'intent220'),
  'permission denied');
commit;

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.accept_commercial_order_terms((:'intent220')::uuid) as r_ace \gset
commit;
select tests.check('titular ativo aceita os termos vigentes',
    ((:'r_ace')::jsonb ->> 'ok') = 'true'
    and ((:'r_ace')::jsonb ->> 'version') = 'v1-teste'
    and ((:'r_ace')::jsonb ->> 'content_hash') = 'hash-teste-v1');

select ((:'r_ace')::jsonb ->> 'acceptance_id') as ace220 \gset

-- O aceite e amarrado por CHAVE ESTRANGEIRA, nao por JSON solto.
select tests.check('aceite amarrado exatamente a intencao, ao titular e ao documento',
    (select a.subject_type = 'commercial_checkout_intent'
        and a.subject_id = (:'intent220')::uuid
        and a.commercial_checkout_intent_id = (:'intent220')::uuid
        and a.context = 'commercial_contract'
        and a.linked_auth_user_id = (:'uid_t')::uuid
        and a.revoked_at is null
       from public.legal_acceptances a where a.id = :'ace220'));
select tests.check('o documento aceito e do tipo commercial_order_terms',
    (select d.doc_type = 'commercial_order_terms' and d.status = 'published'
       from public.legal_acceptances a join public.legal_documents d
         on d.id = a.legal_document_id
      where a.id = :'ace220'));
select tests.check('o instante do aceite e do BANCO, nao do cliente',
    (select a.accepted_at <= now() and a.accepted_at > now() - interval '5 minutes'
       from public.legal_acceptances a where a.id = :'ace220'));

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.accept_commercial_order_terms((:'intent220')::uuid) as r_ace2 \gset
commit;
select tests.check('aceite repetido do mesmo documento e idempotente',
    ((:'r_ace2')::jsonb ->> 'already') = 'true'
    and ((:'r_ace2')::jsonb ->> 'acceptance_id') = :'ace220');

-- ---------------------------------------------------------------------------
-- 3. FINALIZAÇÃO — acordo mestre obrigatório
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'intent220')::uuid) as r_sem_acordo \gset
select tests.check('sem acordo mestre vigente o pedido NAO nasce',
    ((:'r_sem_acordo')::jsonb ->> 'reason') = 'master_agreement_missing');
commit;

-- O acordo mestre e registrado por ADMIN, como o MVP definiu.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_master_agreement(
  (:'comp220')::uuid, 'AM-v1-teste', now() - interval '1 day',
  'Titular Canonico 220', 'doc://acordo-220') as r_am \gset
select tests.check('admin registra o acordo mestre externo',
    ((:'r_am')::jsonb ->> 'ok') = 'true');
commit;

begin;
select tests.impersonate('authenticated', :'uid_g');
select public.finalize_commercial_order_from_intent((:'intent220')::uuid) as r_fin_ger \gset
select tests.check('GERENTE nao finaliza o pedido',
    ((:'r_fin_ger')::jsonb ->> 'reason') = 'not_company_owner');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'intent220')::uuid) as r_fin \gset
commit;

select tests.check('titular finaliza e o pedido nasce',
    ((:'r_fin')::jsonb ->> 'ok') = 'true'
    and ((:'r_fin')::jsonb ->> 'already') = 'false');
select ((:'r_fin')::jsonb ->> 'order_id') as ord220 \gset

select tests.check('intencao chega a awaiting_payment_provider',
    (select status = 'awaiting_payment_provider'
       from public.commercial_checkout_intents where id = :'intent220'));
select tests.check('oportunidade chega a payment_pending, sem reserva pendurada',
    (select status = 'payment_pending' and reserved_until is null
       from public.commercial_opportunities where id = :'opp220'));

-- O pedido COPIA o instantaneo reservado, centavo a centavo.
select tests.check('pedido copia exatamente o instantaneo monetario da intencao',
    (select o.economic_value_cents = i.economic_value_cents
        and o.contractual_pool_cents = i.user_pool_cents
        and o.bdflow_due_cents = i.bdflow_ops_investment_cents
        and o.cash_user_pool_funding_cents = i.cash_user_pool_funding_cents
        and o.total_monetary_funding_required_cents = i.total_monetary_funding_required_cents
        and o.nominal_quantity = i.nominal_quantity
        and o.pricing_rule_version = i.pricing_rule_version
        and o.fidelized = i.fidelized
        and o.benefit_settlement_mode = i.benefit_settlement_mode
       from public.commercial_exclusivity_orders o, public.commercial_checkout_intents i
      where o.id = :'ord220' and i.id = :'intent220'));
select tests.check('valores V2 exatos no pedido',
    (select economic_value_cents = 1999900 and contractual_pool_cents = 1335459
        and bdflow_due_cents = 664441 and pool_bps is null
       from public.commercial_exclusivity_orders where id = :'ord220'));
select tests.check('economico = pool + devido no pedido gravado',
    (select economic_value_cents = contractual_pool_cents + bdflow_due_cents
       from public.commercial_exclusivity_orders where id = :'ord220'));

-- Evidência: FK ao aceite, e campos legados DERIVADOS de registro canônico.
select tests.check('pedido amarrado ao aceite e a intencao por chave estrangeira',
    (select o.legal_acceptance_id = (:'ace220')::uuid
        and o.checkout_intent_id = (:'intent220')::uuid
       from public.commercial_exclusivity_orders o where o.id = :'ord220'));
select tests.check('campos de assinatura derivam de registros canonicos',
    (select o.signed_at = a.accepted_at
        and o.document_hash = d.content_hash
        and o.order_version = d.version
        and o.document_reference = 'bdflow:legal_acceptance/' || a.id::text
        and o.signatory_name = 'Titular Canonico 220'
       from public.commercial_exclusivity_orders o
       join public.legal_acceptances a on a.id = o.legal_acceptance_id
       join public.legal_documents d on d.id = a.legal_document_id
      where o.id = :'ord220'));
select tests.check('pedido amarrado ao acordo mestre vigente da empresa',
    (select o.master_agreement_id = m.id and m.status = 'signed'
       from public.commercial_exclusivity_orders o
       join public.commercial_master_agreements m on m.id = o.master_agreement_id
      where o.id = :'ord220'));

-- Idempotência e duplicidade.
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'intent220')::uuid) as r_fin2 \gset
commit;
select tests.check('finalizacao repetida e idempotente, sem pedido novo',
    ((:'r_fin2')::jsonb ->> 'already') = 'true'
    and ((:'r_fin2')::jsonb ->> 'order_id') = :'ord220');
select tests.check('existe UM unico pedido para esta intencao',
    (select count(*) from public.commercial_exclusivity_orders
      where checkout_intent_id = :'intent220') = 1);

-- ---------------------------------------------------------------------------
-- 4. Reserva expirada e aceite revogado
-- ---------------------------------------------------------------------------
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl220')::uuid, 'womens_clothing', 12, 'available')
returning id as opp_exp \gset

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.create_commercial_checkout_intent(
  (:'comp220')::uuid, 'womens_clothing', 'direct_benefits') as r_i2 \gset
commit;
select ((:'r_i2')::jsonb ->> 'intent_id') as intent_exp \gset

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.advance_checkout_intent_to_contract((:'intent_exp')::uuid) as r_adv \gset
select tests.check('titular avanca para awaiting_contract',
    ((:'r_adv')::jsonb ->> 'ok') = 'true'
    and ((:'r_adv')::jsonb ->> 'status') = 'awaiting_contract');
select public.accept_commercial_order_terms((:'intent_exp')::uuid) as r_ace_exp \gset
commit;

-- Envelhece a reserva pelo banco. O servidor continua sendo a autoridade.
update public.commercial_checkout_intents
   set reserved_until = now() - interval '1 minute' where id = :'intent_exp';
update public.commercial_opportunities
   set reserved_until = now() - interval '1 minute' where id = :'opp_exp';

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'intent_exp')::uuid) as r_exp \gset
select tests.check('reserva EXPIRADA nao vira pedido',
    ((:'r_exp')::jsonb ->> 'reason') = 'reservation_expired');
select public.accept_commercial_order_terms((:'intent_exp')::uuid) as r_ace_exp2 \gset
select tests.check('aceite tambem falha fechado com reserva expirada',
    ((:'r_ace_exp2')::jsonb ->> 'reason') = 'reservation_expired');
rollback;

select tests.check('nenhum pedido nasceu da intencao expirada',
    (select count(*) from public.commercial_exclusivity_orders
      where checkout_intent_id = :'intent_exp') = 0);

-- Aceite revogado não sustenta finalização.
update public.commercial_checkout_intents
   set reserved_until = now() + interval '20 minutes' where id = :'intent_exp';
update public.commercial_opportunities
   set reserved_until = now() + interval '20 minutes' where id = :'opp_exp';
update public.legal_acceptances
   set revoked_at = now(), revocation_reason = 'teste de revogacao'
 where id = ((:'r_ace_exp')::jsonb ->> 'acceptance_id')::uuid;

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'intent_exp')::uuid) as r_rev \gset
select tests.check('aceite REVOGADO nao sustenta o pedido',
    ((:'r_rev')::jsonb ->> 'reason') = 'terms_not_accepted');
rollback;

-- ---------------------------------------------------------------------------
-- 5. O navegador não escreve nada disto
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_t');
select tests.check_raises('titular nao insere aceite diretamente',
  format($sql$insert into public.legal_acceptances
    (subject_type, subject_id, linked_auth_user_id, commercial_checkout_intent_id,
     legal_document_id, context)
   select 'commercial_checkout_intent', %L, %L, %L, id, 'commercial_contract'
     from public.legal_documents where doc_type='commercial_order_terms' limit 1$sql$,
    :'intent220', :'uid_t', :'intent220'),
  'permission denied');
select tests.check_raises('titular nao altera valores do pedido',
  format($sql$update public.commercial_exclusivity_orders
            set economic_value_cents = 1 where id = %L$sql$, :'ord220'),
  'permission denied');
select tests.check_raises('titular nao publica documento juridico direto',
  $sql$insert into public.legal_documents (doc_type, version, title, status)
       values ('commercial_order_terms','v-falsa','Falso','published')$sql$,
  'permission denied');
rollback;

-- As RPCs nao aceitam documento, versao, hash, instante nem valor.
select tests.check('aceite e finalizacao recebem APENAS o id da intencao',
    (select pg_get_function_identity_arguments(p.oid)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.proname='accept_commercial_order_terms')
      = 'p_intent_id uuid'
    and (select pg_get_function_identity_arguments(p.oid)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.proname='finalize_commercial_order_from_intent')
      = 'p_intent_id uuid');

-- Snapshot imutavel do pedido continua protegido pelo gatilho historico.
select tests.check_raises('snapshot do pedido finalizado e imutavel',
  format($sql$update public.commercial_exclusivity_orders
            set contractual_pool_cents = 1 where id = %L$sql$, :'ord220'),
  'pedido_imutavel');

select tests.finish('220_commercial_order_terms');
