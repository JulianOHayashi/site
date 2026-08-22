-- ============================================================================
-- SUITE 110 — Contexto positivo de parceiro (R3)
-- Continua sobre o estado deixado pela suíte 100 (duas empresas promovidas).
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_titular from auth.users where email = 'titular_m2@teste.local' \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select m.id as member1, m.company_id as company1
  from public.site_company_members m where m.role = 'partner_owner'
   and m.auth_user_id = (select id from auth.users where email='titular_m2@teste.local') \gset

-- ---------------------------------------------------------------------------
-- Autorização positiva
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.get_my_partner_context() as ctx1 \gset
select tests.check('owner promovido -> authorized=true com vinculo',
    ((:'ctx1')::jsonb ->> 'authorized') = 'true'
    and jsonb_array_length((:'ctx1')::jsonb -> 'memberships') = 1
    and ((:'ctx1')::jsonb -> 'memberships' -> 0 ->> 'role') = 'partner_owner');
select tests.check('contexto NAO expoe CNPJ nem CPF',
    (:'ctx1')::jsonb::text not like '%11222333000181%'
    and (:'ctx1')::jsonb::text not like '%52998224725%');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select public.get_my_partner_context() as ctx2 \gset
select tests.check('conta sem vinculo -> authorized=false',
    ((:'ctx2')::jsonb ->> 'authorized') = 'false'
    and jsonb_array_length((:'ctx2')::jsonb -> 'memberships') = 0);
rollback;

-- ---------------------------------------------------------------------------
-- Estados que NÃO podem autorizar
-- ---------------------------------------------------------------------------
update public.site_company_members set status = 'suspended' where id = :'member1';
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('vinculo SUSPENSO nao autoriza',
    (public.get_my_partner_context() ->> 'authorized') = 'false');
rollback;
update public.site_company_members set status = 'active' where id = :'member1';

update public.site_partner_companies set status = 'suspended' where id = :'company1';
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('empresa SUSPENSA nao autoriza',
    (public.get_my_partner_context() ->> 'authorized') = 'false');
rollback;
update public.site_partner_companies set status = 'active' where id = :'company1';

update public.site_company_members
   set status = 'revoked', revoked_at = now(), revocation_reason = 'teste de revogacao'
 where id = :'member1';
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('vinculo REVOGADO nao autoriza (efeito imediato)',
    (public.get_my_partner_context() ->> 'authorized') = 'false');
rollback;
update public.site_company_members
   set status = 'active', revoked_at = null, revocation_reason = null
 where id = :'member1';

begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('reativacao restaura a autorizacao',
    (public.get_my_partner_context() ->> 'authorized') = 'true');
rollback;

-- ---------------------------------------------------------------------------
-- ACL da RPC de contexto
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('anon', null);
select tests.check_raises(
  'anon nao executa get_my_partner_context',
  'select public.get_my_partner_context()',
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select tests.check_raises(
  'service_role nao executa get_my_partner_context',
  'select public.get_my_partner_context()',
  'permission denied');
rollback;

select tests.check('get_my_partner_context nao e executavel por PUBLIC',
    has_function_privilege('public', 'public.get_my_partner_context()', 'EXECUTE') = false);
select tests.check('get_my_partner_context tem search_path fixo',
    (select coalesce(array_to_string(proconfig, ','), '') like '%search_path%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_my_partner_context'));

-- A promoção não muda a candidatura: o contexto durável é que decide.
select tests.check('candidatura do owner promovido segue provisional',
    (select account_kind = 'provisional' from public.partner_applications
      where account_user_id = (:'uid_titular')::uuid));

select tests.finish('110_m2_partner_context');
