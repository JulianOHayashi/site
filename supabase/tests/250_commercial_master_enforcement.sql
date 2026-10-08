-- ===========================================================================
-- 250 — P0-1: IMPOSIÇÃO SERVER-SIDE DO ACORDO MESTRE NA CRIAÇÃO DE PEDIDO
--
-- A suíte 220 já prova o caso "não existe Acordo Mestre". Esta prova o caso
-- que faltava e que o P0-1 fechou: o Mestre EXISTE mas já NÃO está vigente.
-- Antes do P0-1 a leitura do Mestre não travava a linha, e uma revogação
-- concorrente podia escapar entre a guarda e o INSERT.
--
-- LIMITE HONESTO DESTA SUÍTE — LEIA ANTES DE CONFIAR NELA
-- Esta suíte NÃO prova o P0-1. Foi verificado por execução: ela passa
-- 11 PASS / 0 FAIL com a migration 20261007140000 aplicada E sem ela. A razão é
-- que o `FOR UPDATE` do P0-1 só se manifesta com DUAS transações concorrentes, e
-- o harness roda uma única sessão psql — numa sessão só, a guarda antiga
-- (`status = 'signed'` sem lock) recusa um Mestre revogado exatamente como a
-- nova.
--
-- O que esta suíte realmente garante, e que a 220 não cobria: a semântica
-- fail-closed de Mestre REVOGADO (superseded / terminated), nos dois caminhos de
-- escrita, mais as invariantes estruturais em volta. É cobertura de regressão
-- legítima e vale por si — mas não é a prova da corrida.
--
-- A prova da corrida é `scripts/db-test/p01-master-race.sh`, que abre duas
-- sessões de verdade, exercita as duas ordens possíveis e falha se o lock não
-- estiver no lugar. Rode-o separadamente; nenhuma asserção aqui o substitui.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- Fixture jurídica/contratual FICTÍCIA: permite que esta suíte exercite
-- seu próprio domínio sem promover a minuta real v1.4.
select tests.preparar_contexto_contratual_v14_qa('250');

-- ---------------------------------------------------------------------------
-- Fixtures próprias: a suíte roda isolada.
-- ---------------------------------------------------------------------------
select tests.mk_user('admin250@teste.local') as uid_admin \gset
insert into public.site_admins (user_id) values ((:'uid_admin')::uuid)
on conflict do nothing;

select tests.mk_user('titular250@teste.local') as uid_t \gset

select r.id as reg250 from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

insert into public.commercial_exclusivities
  (region_id, sequence_number, status, is_current)
values ((:'reg250')::uuid, 250, 'forming', false)
returning id as excl250 \gset

insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl250')::uuid, 'mens_clothing', 12, 'available')
returning id as opp250 \gset
insert into public.commercial_opportunities
  (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl250')::uuid, 'womens_clothing', 12, 'available')
returning id as opp250b \gset

update public.commercial_exclusivities set is_current = false
 where region_id = (:'reg250')::uuid and is_current;
update public.commercial_exclusivities set is_current = true
 where id = (:'excl250')::uuid;

insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('25010001000148','Empresa 250','e250@teste.local','Viana','ES')
returning id as app250 \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app250')::uuid,'25010001000148','Empresa 250','e250@teste.local',
        'Viana','ES','active')
returning id as comp250 \gset

insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'comp250')::uuid, (:'uid_t')::uuid, 'partner_owner',
        'Titular Canonico 250', 'application_promotion', 'active');

-- Segunda empresa, exclusiva do caminho MANUAL. Sem ela a venda manual seria
-- recusada antes da guarda do Mestre, por company_already_in_exclusivity — a
-- empresa 250 já ocupa um nicho desta mesma exclusividade.
insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
values ('25020002000173','Empresa 250 Manual','m250@teste.local','Viana','ES')
returning id as app250b \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, contact_email, city, uf, status)
values ((:'app250b')::uuid,'25020002000173','Empresa 250 Manual','m250@teste.local',
        'Viana','ES','active')
returning id as comp250b \gset

-- Representantes canônicos exigidos pela emissão do instrumento de QA.
insert into public.partner_application_representatives
  (application_id, full_name, cpf, email, role_title, authority_status,
   is_current, decided_at)
values ((:'app250')::uuid, 'Titular Canonico 250', '52998224725',
        'titular250@teste.local', 'Socio administrador', 'approved', true,
        now() - interval '2 days'),
       ((:'app250b')::uuid, 'Titular Manual 250', '11144477735',
        'titular250b@teste.local', 'Socio administrador', 'approved', true,
        now() - interval '2 days');

select tests.mk_user('titular250b@teste.local') as uid_tb \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, source, status)
values ((:'comp250b')::uuid, (:'uid_tb')::uuid, 'partner_owner',
        'Titular Manual 250', 'application_promotion', 'active');

-- P0-2: o aceite juridico exige unidade de execucao validada.
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp250')::uuid,  'Unidade 250',  'Viana', 'ES', 'active'),
       ((:'comp250b')::uuid, 'Unidade 250B', 'Viana', 'ES', 'active');

-- Acordo Mestre vigente, pelo caminho canônico.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.assinar_mestre_qa((:'comp250')::uuid, 'AM-250') as r_am \gset
select tests.check('fixture: acordo mestre vigente registrado',
    ((:'r_am')::jsonb ->> 'ok') = 'true');
select tests.assinar_mestre_qa((:'comp250b')::uuid, 'AM-250B') as r_amb \gset
select tests.check('fixture: acordo mestre vigente da empresa manual',
    ((:'r_amb')::jsonb ->> 'ok') = 'true');
commit;

select id as ma250 from public.commercial_master_agreements
 where company_id = (:'comp250')::uuid and status = 'signed' \gset
select id as ma250b from public.commercial_master_agreements
 where company_id = (:'comp250b')::uuid and status = 'signed' \gset

-- ---------------------------------------------------------------------------
-- 1. ESTRUTURA — no máximo UM Mestre vigente por empresa
--    É o que torna o FOR UPDATE do P0-1 inequívoco: a linha travada é a única
--    candidata, sem depender de ordenação.
-- ---------------------------------------------------------------------------
select tests.check('existe indice unico parcial de Mestre vigente por empresa',
    (select count(*) from pg_indexes
      where tablename = 'commercial_master_agreements'
        and indexdef ilike '%UNIQUE%'
        and indexdef ilike '%(company_id)%'
        and indexdef ilike '%status = ''signed''%') = 1);
select tests.check_raises('segundo Mestre vigente na mesma empresa e impossivel',
  format($sql$insert into public.commercial_master_agreements
    (company_id, agreement_version, document_reference, status, signed_at,
     signatory_name, registered_by)
   values (%L,'AM-250-DUPLICADO','doc://dup','signed', now() - interval '1 day',
           'Titular Canonico 250', %L)$sql$, :'comp250', :'uid_admin'),
  'cma_vigente_idx');

-- ---------------------------------------------------------------------------
-- 2. CAMINHO DO TITULAR — Mestre revogado NÃO origina pedido
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.create_commercial_checkout_intent(
  (:'comp250')::uuid, 'mens_clothing', 'direct_benefits') as r_int \gset
commit;
select tests.check('fixture: reserva criada',
    ((:'r_int')::jsonb ->> 'ok') = 'true');
select ((:'r_int')::jsonb ->> 'intent_id') as int250 \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.publicar_mestre_qa('TP-250') as ld250 \gset
commit;

begin;
select tests.impersonate('authenticated', :'uid_t');
select public.advance_checkout_intent_to_contract((:'int250')::uuid);
select public.accept_commercial_order_terms((:'int250')::uuid) as r_ace \gset
select tests.check('fixture: termos aceitos pelo titular',
    ((:'r_ace')::jsonb ->> 'ok') = 'true');
commit;

-- SUPERSEDED: o Mestre existe, tem a mesma empresa, mas deixou de reger.
begin;
update public.commercial_master_agreements
   set status = 'superseded', superseded_at = now()
 where id = (:'ma250')::uuid;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'int250')::uuid) as r_sup \gset
select tests.check('TITULAR: Mestre SUPERSEDED nao origina pedido',
    ((:'r_sup')::jsonb ->> 'ok') = 'false'
    and ((:'r_sup')::jsonb ->> 'reason') = 'master_agreement_missing');
reset role;
select tests.check('TITULAR: nenhum pedido nasceu da tentativa com Mestre revogado',
    (select count(*) from public.commercial_exclusivity_orders
      where checkout_intent_id = (:'int250')::uuid) = 0);
rollback;

-- TERMINATED: mesma exigência, outro estado terminal.
begin;
update public.commercial_master_agreements
   set status = 'terminated'
 where id = (:'ma250')::uuid;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'int250')::uuid) as r_ter \gset
select tests.check('TITULAR: Mestre TERMINATED nao origina pedido',
    ((:'r_ter')::jsonb ->> 'ok') = 'false'
    and ((:'r_ter')::jsonb ->> 'reason') = 'master_agreement_missing');
rollback;

-- Com o Mestre de volta ao estado vigente, o mesmo pedido nasce — prova de que
-- a recusa acima vinha do ESTADO do Mestre e não de outra condição qualquer.
begin;
select tests.impersonate('authenticated', :'uid_t');
select public.finalize_commercial_order_from_intent((:'int250')::uuid) as r_ok \gset
commit;
select tests.check('TITULAR: com Mestre vigente o pedido nasce',
    ((:'r_ok')::jsonb ->> 'ok') = 'true'
    and ((:'r_ok')::jsonb ->> 'already') = 'false');
select ((:'r_ok')::jsonb ->> 'order_id') as ord250 \gset
select tests.check('TITULAR: pedido amarrado ao Mestre VIGENTE da empresa',
    (select master_agreement_id = (:'ma250')::uuid
       from public.commercial_exclusivity_orders where id = (:'ord250')::uuid));

-- ---------------------------------------------------------------------------
-- 3. CAMINHO MANUAL — a mesma exigência, sem exceção para o admin
-- ---------------------------------------------------------------------------
begin;
update public.commercial_master_agreements
   set status = 'superseded', superseded_at = now()
 where id = (:'ma250b')::uuid;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp250b')::uuid, (:'comp250b')::uuid, 'v1', now() - interval '1 day',
  'Titular Manual 250', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-250') as r_man \gset
select tests.check('MANUAL: Mestre SUPERSEDED nao origina pedido nem para admin',
    ((:'r_man')::jsonb ->> 'ok') = 'false'
    and ((:'r_man')::jsonb ->> 'reason') = 'master_agreement_missing');
reset role;
select tests.check('MANUAL: a oportunidade continua disponivel, sem reserva pendurada',
    (select status = 'available' from public.commercial_opportunities
      where id = (:'opp250b')::uuid));
rollback;

-- Com o Mestre da empresa manual vigente, a mesma venda manual passa: prova de
-- que a recusa acima vinha do ESTADO do Mestre, não de outra condição.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp250b')::uuid, (:'comp250b')::uuid, 'v1', now() - interval '1 day',
  'Titular Manual 250', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-250') as r_man_ok \gset
select tests.check('MANUAL: com Mestre vigente a venda manual passa',
    ((:'r_man_ok')::jsonb ->> 'ok') = 'true');
reset role;
select tests.check('MANUAL: pedido amarrado ao Mestre vigente da propria empresa',
    (select master_agreement_id = (:'ma250b')::uuid
       from public.commercial_exclusivity_orders
      where id = ((:'r_man_ok')::jsonb ->> 'order_id')::uuid));
rollback;

-- ---------------------------------------------------------------------------
-- 4. INVARIANTE GLOBAL — nenhum pedido no banco aponta para Mestre não vigente
--    no momento em que nasceu. Vale sobre TODAS as suítes anteriores, não só
--    sobre as fixtures desta.
-- ---------------------------------------------------------------------------
select tests.check('nenhum pedido ativo aponta para Mestre inexistente',
    (select count(*) from public.commercial_exclusivity_orders o
      where not exists (select 1 from public.commercial_master_agreements a
                         where a.id = o.master_agreement_id)) = 0);
select tests.check('todo pedido ativo aponta para Mestre da PROPRIA empresa',
    (select count(*) from public.commercial_exclusivity_orders o
       join public.commercial_master_agreements a on a.id = o.master_agreement_id
      where a.company_id <> o.company_id) = 0);

-- ---------------------------------------------------------------------------
-- 5. RESOLVEDOR ÚNICO — os sete requisitos de elegibilidade
-- ---------------------------------------------------------------------------
select tests.check('resolvedor: Mestre canonicamente vinculado e elegivel',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'ok') = 'true');
select tests.check('resolvedor: devolve o Mestre e o documento canonico vinculado',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid)
       ->> 'master_agreement_id')::uuid = (:'ma250')::uuid
    and (public.m2_master_agreement_eligibility((:'comp250')::uuid)
       ->> 'legal_document_id') is not null);
select tests.check('resolvedor: empresa sem Mestre algum falha fechada',
    (public.m2_master_agreement_eligibility(gen_random_uuid()) ->> 'reason')
      = 'master_agreement_missing');
select tests.check('resolvedor: nao e executavel por anon nem authenticated',
    not has_function_privilege('anon',
      'public.m2_master_agreement_eligibility(uuid,boolean)', 'EXECUTE')
    and not has_function_privilege('authenticated',
      'public.m2_master_agreement_eligibility(uuid,boolean)', 'EXECUTE'));

-- LINHA HISTÓRICA SEM VÍNCULO CANÔNICO — preservada, legível, mas NÃO autoriza
-- contratação nova. É o caso da empresa legada anterior ao C2.
begin;
update public.commercial_master_agreements
   set legal_document_id = null
 where id = (:'ma250')::uuid;
select tests.check('resolvedor: Mestre historico sem vinculo canonico NAO autoriza',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'ok') = 'false'
    and (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'reason')
        = 'master_agreement_requires_canonical_relink');
select tests.check('resolvedor: a recusa traz instrucao de remediacao, nao beco sem saida',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'remediation')
      like '%admin_register_master_agreement%');
select tests.check('resolvedor: a linha historica segue INTACTA e legivel',
    (select count(*) from public.commercial_master_agreements
      where id = (:'ma250')::uuid and status = 'signed'
        and legal_document_id is null) = 1);

-- PORTÃO 1: sem Mestre elegível não se reserva inventário escasso.
select tests.impersonate('authenticated', :'uid_t');
select public.create_commercial_checkout_intent(
  (:'comp250')::uuid, 'womens_footwear', 'direct_benefits') as r_res \gset
select tests.check('PORTAO 1: vinculo ausente impede reservar inventario escasso',
    ((:'r_res')::jsonb ->> 'ok') = 'false'
    and ((:'r_res')::jsonb ->> 'reason') = 'master_agreement_requires_canonical_relink');
reset role;
rollback;

-- VERSÃO E HASH EXATOS, conferidos na LEITURA.
--
-- POR QUE A TRIGGER É DESLIGADA AQUI, e por que isso é legítimo:
-- `cma_coerencia_legal` impõe versão e hash na ESCRITA do Mestre, e foi
-- verificado em runtime que ela TORNA IMPOSSÍVEL construir a divergência por
-- DML normal — a tentativa falha com "agreement_version diverge da versao
-- publicada". Mas essa trigger nasceu no C2. Uma linha gravada ANTES dela pode
-- perfeitamente ter versão ou hash divergentes, e é exatamente essa população
-- que os requisitos 4 e 5 do resolvedor existem para recusar.
--
-- Sem desligar a trigger, esses dois requisitos ficariam escritos e NÃO
-- provados. Desligá-la dentro de uma transação revertida é a única forma de
-- montar a forma pré-C2 num banco que já tem o C2. Nada aqui enfraquece a
-- trigger: ela é religada no mesmo bloco e o ROLLBACK descarta a linha.
begin;
alter table public.commercial_master_agreements disable trigger cma_coerencia_legal;
alter table public.commercial_master_agreements disable trigger trg_cma_protect;
update public.commercial_master_agreements
   set agreement_version = 'AM-250-DIVERGENTE'
 where id = (:'ma250')::uuid;
alter table public.commercial_master_agreements enable trigger trg_cma_protect;
alter table public.commercial_master_agreements enable trigger cma_coerencia_legal;
select tests.check('resolvedor: versao divergente do documento falha fechada',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'reason')
      = 'master_agreement_version_mismatch');
rollback;

begin;
alter table public.commercial_master_agreements disable trigger cma_coerencia_legal;
alter table public.commercial_master_agreements disable trigger trg_cma_protect;
update public.commercial_master_agreements
   set document_hash = 'hash-que-nao-e-o-publicado'
 where id = (:'ma250')::uuid;
alter table public.commercial_master_agreements enable trigger trg_cma_protect;
alter table public.commercial_master_agreements enable trigger cma_coerencia_legal;
select tests.check('resolvedor: hash divergente do publicado falha fechada',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'reason')
      = 'master_agreement_hash_mismatch');
rollback;

-- A trigger continua ligada depois dos blocos acima.
select tests.check('as travas do Mestre seguem ATIVAS apos os cenarios legados',
    (select count(*) from pg_trigger
      where tgrelid = 'public.commercial_master_agreements'::regclass
        and tgname in ('cma_coerencia_legal','trg_cma_protect')
        and tgenabled = 'D') = 0);

-- RASCUNHO nunca rege contrato assinado. legal_documents_protect proíbe
-- published -> draft, então a forma só é construível com a trigger desligada —
-- e é, de novo, uma forma que só poderia vir de dado anterior às travas.
begin;
alter table public.legal_documents disable trigger trg_legal_documents_protect;
update public.legal_documents set status = 'draft'
 where id = (select legal_document_id from public.commercial_master_agreements
              where id = (:'ma250')::uuid);
alter table public.legal_documents enable trigger trg_legal_documents_protect;
select tests.check('resolvedor: documento em rascunho NAO rege contratacao',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'reason')
      = 'master_agreement_document_state_invalid');
rollback;

-- ARQUIVADO É permitido: é o estado de uma versão substituída, e a empresa que
-- assinou aquela versão continua regida por ela.
begin;
-- A trava de vigencia tambem e desligada: varias versoes de QA de
-- master_agreement coexistem no banco de teste, e definir effective_to aqui
-- colide com elas. O que se prova neste bloco e o RESOLVEDOR, nao a vigencia.
alter table public.legal_documents disable trigger trg_legal_documents_protect;
alter table public.legal_documents disable trigger trg_legal_documents_overlap;
update public.legal_documents
   set status = 'archived', effective_to = now() + interval '1 day'
 where id = (select legal_document_id from public.commercial_master_agreements
              where id = (:'ma250')::uuid);
alter table public.legal_documents enable trigger trg_legal_documents_overlap;
alter table public.legal_documents enable trigger trg_legal_documents_protect;
select tests.check('resolvedor: documento ARQUIVADO continua regendo (versao substituida)',
    (public.m2_master_agreement_eligibility((:'comp250')::uuid) ->> 'ok') = 'true'
    and (public.m2_master_agreement_eligibility((:'comp250')::uuid)
           ->> 'document_status') = 'archived');
rollback;

-- ---------------------------------------------------------------------------
-- 6. O Mestre não pode ser apagado para contornar a exigência
-- ---------------------------------------------------------------------------
select tests.check_raises('Mestre nao pode ser excluido',
  format($sql$delete from public.commercial_master_agreements where id = %L$sql$,
         :'ma250'),
  'acordo_imutavel');

select tests.encerrar_contexto_contratual_v14_qa();

select tests.finish('250_commercial_master_enforcement');
