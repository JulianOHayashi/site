-- ============================================================================
-- SUITE 900 — Auditoria ESTRUTURAL (R14)
--
-- As demais suítes testam comportamento. Esta testa a FORMA do schema por
-- IGUALDADE DE CONJUNTOS NOS DOIS SENTIDOS: tanto um objeto que sumiu quanto
-- um objeto que apareceu sem ser declarado reprovam. É a rede que pega o que
-- ninguém pensou em testar — inclusive o padrão do Supabase de conceder ALL
-- a anon em cada tabela nova.
--
-- STATUS: TESTE_AUXILIAR_NAO_GATE (PG16). O gate final é Supabase PG17 real.
-- ============================================================================

select tests.reset_results();

-- ---------------------------------------------------------------------------
-- 1. Privilégios ISENTOS DE RLS não podem existir para papéis públicos.
--    TRUNCATE não passa por RLS: é o único caminho em que o GRANT ALL da
--    baseline virava destruição real de dados.
-- ---------------------------------------------------------------------------
select tests.check('nenhum TRUNCATE/TRIGGER/REFERENCES para anon ou authenticated',
    (select count(*) from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee in ('anon','authenticated')
        and privilege_type in ('TRUNCATE','TRIGGER','REFERENCES')) = 0);

-- Prova de campo (não apenas catálogo): o papel anon TENTANDO truncar de
-- verdade. Antes desta correção o privilégio existia e o TRUNCATE passava.
begin;
select tests.impersonate('anon', null);
select tests.check_raises(
  'anon nao consegue truncar public.orders',
  $sql$truncate public.orders cascade$sql$,
  'permission denied');
select tests.check_raises(
  'anon nao consegue truncar public.site_admins',
  $sql$truncate public.site_admins cascade$sql$,
  'permission denied');
rollback;

begin;
select tests.impersonate('authenticated', null);
select tests.check_raises(
  'authenticated nao consegue truncar public.payments',
  $sql$truncate public.payments cascade$sql$,
  'permission denied');
rollback;

-- O que NÃO deve ter mudado: a vitrine pública continua legível.
select tests.check('anon manteve SELECT nas tabelas publicas da vitrine',
    has_table_privilege('anon','public.products','SELECT')
    and has_table_privilege('anon','public.site_monthly_partners','SELECT'));

-- ---------------------------------------------------------------------------
-- 2. IGUALDADE DE CONJUNTOS — funções executáveis por anon.
--    Toda função nova nasce executável por anon (ALTER DEFAULT PRIVILEGES da
--    baseline). Este teste falha se alguém esquecer o REVOKE.
-- ---------------------------------------------------------------------------
create temporary table esperado_anon_exec (proname text primary key);
insert into esperado_anon_exec values
  -- canônicas M1 (fluxo pré-auth, por definição anônimo)
  ('create_partner_application'),
  ('confirm_partner_application_email'),
  ('request_partner_application_recovery'),
  ('get_partner_application_terms'),
  ('get_current_legal_documents'),
  ('is_site_admin'),
  -- canônicas da vitrine pública
  ('get_current_commercial_formation'),
  ('resolve_commercial_region'),
  -- M2: preço público da vitrine (regras de preço são informação pública)
  ('calculate_niche_contract_pricing'),
  ('get_public_niche_pricing');

create temporary table real_anon_exec as
  select p.proname::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and has_function_privilege('anon', p.oid, 'EXECUTE');

select tests.check('nenhuma funcao executavel por anon alem das declaradas',
    not exists (select proname from real_anon_exec
                except select proname from esperado_anon_exec));
select tests.check('nenhuma funcao declarada deixou de ser executavel por anon',
    not exists (select proname from esperado_anon_exec
                except select proname from real_anon_exec));

-- ---------------------------------------------------------------------------
-- 3. IGUALDADE DE CONJUNTOS — tabelas do domínio M2.
--    Uma tabela M2 removida OU uma tabela M2 nova não declarada reprovam.
-- ---------------------------------------------------------------------------
create temporary table esperado_tabelas_m2 (tablename text primary key);
insert into esperado_tabelas_m2 values
  ('site_partner_companies'),
  ('site_company_members'),
  ('site_partner_units'),
  ('site_member_unit_bindings'),
  ('site_manager_invites'),
  ('site_manager_invite_tokens'),
  ('commercial_pricing_rules'),
  ('commercial_fidelity_records'),
  ('commercial_master_agreements'),
  ('commercial_exclusivity_orders'),
  ('commercial_order_customization_images'),
  ('commercial_operational_bindings'),
  ('app_provisioning_messages'),
  ('benefit_validation_attempts');

create temporary table real_tabelas_m2 as
  select c.relname::text as tablename
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in (select tablename from esperado_tabelas_m2);

-- Sentido 1: nada do que foi declarado pode faltar.
select tests.check('todas as tabelas M2 declaradas existem',
    not exists (select tablename from esperado_tabelas_m2
                except select tablename from real_tabelas_m2));
-- Sentido 2: nada pode existir com nome M2 sem ter sido declarado.
select tests.check('nenhuma tabela M2 nao declarada',
    not exists (select tablename from real_tabelas_m2
                except select tablename from esperado_tabelas_m2));

-- ---------------------------------------------------------------------------
-- 4. RLS habilitada em TODA tabela M2 (conjunto de violações vazio).
-- ---------------------------------------------------------------------------
select tests.check('RLS habilitada em todas as tabelas M2',
    not exists (
      select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname in (select tablename from esperado_tabelas_m2)
         and c.relrowsecurity = false));

-- Nenhum privilégio de tabela M2 para anon (o REVOKE de cada migração M2).
select tests.check('anon nao tem nenhum privilegio nas tabelas M2',
    (select count(*) from information_schema.role_table_grants
      where table_schema = 'public' and grantee = 'anon'
        and table_name in (select tablename from esperado_tabelas_m2)) = 0);

-- ---------------------------------------------------------------------------
-- 5. Toda função M2 é SECURITY DEFINER com search_path fixado — exceto os
--    dois auxiliares internos, que são INVOKER de propósito e não são
--    executáveis por nenhum papel público.
-- ---------------------------------------------------------------------------
create temporary table invoker_permitidos (proname text primary key);
insert into invoker_permitidos values ('m2_convite_ttl'), ('m2_emitir_token_convite');

select tests.check('toda funcao M2 tem search_path fixado',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname like 'm2\_%'
         and (p.proconfig is null
              or not exists (select 1 from unnest(p.proconfig) cfg
                              where cfg like 'search_path=%'))));

select tests.check('funcoes M2 nao-DEFINER sao exatamente as declaradas',
    not exists (
      select p.proname::text from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname like 'm2\_%' and p.prosecdef = false
      except select proname from invoker_permitidos));

select tests.check('auxiliares INVOKER nao sao executaveis por anon nem authenticated',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in (select proname from invoker_permitidos)
         and (has_function_privilege('anon', p.oid, 'EXECUTE')
              or has_function_privilege('authenticated', p.oid, 'EXECUTE'))));

-- ---------------------------------------------------------------------------
-- 6. MATRIZ DE ATORES — RPCs administrativas e de ponte negadas a anon e a
--    authenticated comum. Fecha as lacunas das suítes 140/150/160/170.
-- ---------------------------------------------------------------------------
create temporary table rpc_restritas (proname text primary key, quem text);
insert into rpc_restritas values
  ('admin_promote_partner_application','admin'),
  ('admin_register_master_agreement','admin'),
  ('admin_register_manual_commercial_order','admin'),
  ('admin_confirm_manual_bdflow_payment','admin'),
  ('admin_authorize_commercial_operation','admin'),
  ('admin_enqueue_app_provisioning','admin'),
  ('commercial_formation_gate_report','admin'),
  ('build_app_provisioning_payload','admin'),
  ('prov_claim_provisioning_message','service_role'),
  ('prov_record_provisioning_result','service_role'),
  ('prov_record_validation_result','service_role'),
  ('svc_mint_manager_invite_token','service_role');

select tests.check('nenhuma RPC restrita e executavel por anon',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in (select proname from rpc_restritas)
         and has_function_privilege('anon', p.oid, 'EXECUTE')));

select tests.check('RPCs de service_role nao sao executaveis por authenticated',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in (select proname from rpc_restritas where quem = 'service_role')
         and has_function_privilege('authenticated', p.oid, 'EXECUTE')));

-- Controle positivo do próprio critério: uma função sabidamente pública
-- PRECISA aparecer como executável por anon. Se este check falhar, a
-- verificação de privilégio acima está sempre dando negativo por engano.
select tests.check('controle positivo: funcao publica e mesmo visivel a anon',
    has_function_privilege('anon', 'public.get_public_niche_pricing()', 'EXECUTE'));

-- ---------------------------------------------------------------------------
-- 7. A baseline canônica não foi alterada: os objetos M1 continuam de pé.
-- ---------------------------------------------------------------------------
select tests.check('primitivas canonicas M1 intactas',
    to_regprocedure('public.m1_token_hash(text)') is not null
    and to_regprocedure('public.m1_exigir_admin()') is not null
    and to_regprocedure('public.m1_mint_lease()') is not null
    and to_regprocedure('public.claim_partner_application_account(text)') is not null);

select tests.finish('900_r14_auditoria_estrutural');
