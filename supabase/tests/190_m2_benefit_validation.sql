-- ============================================================================
-- SUITE 190 — Validação de benefício, LADO SITE (R12)
-- Negativos que NÃO dependem do App: papel, unidade, vínculo, status e rede.
-- Token, replay, confirmação e uso são autoridade do App.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select o.company_id as comp1 from public.commercial_exclusivity_orders o
 where o.exclusivity_id = (select id from public.commercial_exclusivities where sequence_number=2)
   and o.niche_code='supermarket' \gset
select auth_user_id as uid_owner1 from public.site_company_members
 where company_id = :'comp1' and role='partner_owner' \gset
select id as mgr1, auth_user_id as uid_mgr1 from public.site_company_members
 where company_id = :'comp1' and role='partner_manager' and status='active' limit 1 \gset
select b.unit_id as unit1 from public.site_member_unit_bindings b
 where b.member_id = :'mgr1' and b.status='active' limit 1 \gset
-- Segunda unidade da mesma empresa, à qual o manager NÃO está vinculado.
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_create_unit((:'comp1')::uuid,'Filial Sem Vinculo','Serra','ES') as u2 \gset
commit;
select ((:'u2')::jsonb ->> 'unit_id') as unit2 \gset
-- Empresa e unidade de OUTRO parceiro.
select o.company_id as comp2 from public.commercial_exclusivity_orders o
 where o.exclusivity_id = (select id from public.commercial_exclusivities where sequence_number=2)
   and o.niche_code='pharmacy' \gset
select id as unit_p2 from public.site_partner_units where company_id = :'comp2' limit 1 \gset

-- ---------------------------------------------------------------------------
-- Caminho feliz: OWNER e MANAGER validam
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.prepare_benefit_validation(
    (:'comp1')::uuid, (:'unit1')::uuid, 'token-owner-teste') as v_own \gset
select tests.check('OWNER valida e o pedido segue para o App',
    ((:'v_own')::jsonb ->> 'allowed') = 'true'
    and ((:'v_own')::jsonb ->> 'validator_role') = 'partner_owner');
select tests.check('pacote usa UUIDs de ponte (rede, filial, validador)',
    ((:'v_own')::jsonb ->> 'partner_network_bridge_id') is not null
    and ((:'v_own')::jsonb ->> 'partner_branch_bridge_id') is not null
    and ((:'v_own')::jsonb ->> 'validator_bridge_id') is not null);
-- m1_token_hash é revogado de PUBLIC (endurecimento do M1): o hash esperado
-- é recomputado inline com as funções de pg_catalog.
select tests.check('o token CRU nao volta no pacote; apenas o hash',
    (:'v_own')::jsonb ->> 'token_hash'
      = encode(sha256(convert_to('token-owner-teste','UTF8')), 'hex')
    and (:'v_own')::jsonb::text not like '%token-owner-teste%');
select tests.check('o desfecho real e declarado como dependente do App',
    ((:'v_own')::jsonb ->> 'app_gateway') = 'BLOCKED_APP_REPOSITORY');
commit;

select tests.check('token cru NAO fica persistido em lugar nenhum',
    (select count(*) from public.benefit_validation_attempts
      where encode(token_hash,'hex') = 'token-owner-teste') = 0
    and (select count(*) from public.audit_logs
          where coalesce(new_state::text,'') like '%token-owner-teste%') = 0);

begin;
select tests.impersonate('authenticated', :'uid_mgr1');
select public.prepare_benefit_validation(
    (:'comp1')::uuid, (:'unit1')::uuid, 'token-manager-teste') as v_mgr \gset
select tests.check('MANAGER vinculado valida normalmente',
    ((:'v_mgr')::jsonb ->> 'allowed') = 'true'
    and ((:'v_mgr')::jsonb ->> 'validator_role') = 'partner_manager');
commit;

-- ---------------------------------------------------------------------------
-- NEGATIVOS locais (todos auditados, nenhum levanta exceção)
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_mgr1');
select public.prepare_benefit_validation(
    (:'comp1')::uuid, (:'unit2')::uuid, 'tk1') as n1 \gset
select tests.check('manager NAO valida em unidade sem vinculo',
    ((:'n1')::jsonb ->> 'allowed') = 'false'
    and ((:'n1')::jsonb ->> 'reason') = 'validation_denied');
commit;

select tests.check('negativa por unidade sem vinculo fica AUDITADA',
    (select count(*) from public.benefit_validation_attempts
      where result='denied_local' and rejection_code='MANAGER_NOT_BOUND_TO_UNIT') = 1);
select tests.check('o motivo preciso NAO vaza para o chamador',
    ((:'n1')::jsonb ->> 'reason') <> 'MANAGER_NOT_BOUND_TO_UNIT');

begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.prepare_benefit_validation(
    (:'comp1')::uuid, (:'unit_p2')::uuid, 'tk2') as n2 \gset
select tests.check('unidade de OUTRO parceiro nao serve a esta empresa',
    ((:'n2')::jsonb ->> 'allowed') = 'false');
commit;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select public.prepare_benefit_validation(
    (:'comp1')::uuid, (:'unit1')::uuid, 'tk3') as n3 \gset
select tests.check('conta sem vinculo nenhum nao valida',
    ((:'n3')::jsonb ->> 'allowed') = 'false');
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao executa a preparacao',
  format($sql$select public.prepare_benefit_validation(%L,%L,'tk4')$sql$, :'comp1', :'unit1'),
  'permission denied');
rollback;

-- Manager de outra rede
begin;
select tests.impersonate('authenticated', :'uid_mgr1');
select public.prepare_benefit_validation(
    (:'comp2')::uuid, (:'unit_p2')::uuid, 'tk5') as n5 \gset
select tests.check('validador nao atua na rede de outro parceiro',
    ((:'n5')::jsonb ->> 'allowed') = 'false');
rollback;

-- Manager suspenso e revogado
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_set_manager_status((:'mgr1')::uuid,'suspend');
commit;
begin;
select tests.impersonate('authenticated', :'uid_mgr1');
select public.prepare_benefit_validation((:'comp1')::uuid,(:'unit1')::uuid,'tk6') as n6 \gset
select tests.check('manager SUSPENSO nao valida',
    ((:'n6')::jsonb ->> 'allowed') = 'false');
rollback;
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_set_manager_status((:'mgr1')::uuid,'reactivate');
commit;

-- Unidade suspensa não valida nem para o owner
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_set_unit_status((:'unit1')::uuid,'suspended','reforma');
commit;
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.prepare_benefit_validation((:'comp1')::uuid,(:'unit1')::uuid,'tk7') as n7 \gset
select tests.check('unidade SUSPENSA nao valida nem para o owner',
    ((:'n7')::jsonb ->> 'allowed') = 'false');
commit;
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_set_unit_status((:'unit1')::uuid,'active');
commit;

begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_set_manager_status((:'mgr1')::uuid,'revoke','desligamento');
commit;
begin;
select tests.impersonate('authenticated', :'uid_mgr1');
select public.prepare_benefit_validation((:'comp1')::uuid,(:'unit1')::uuid,'tk8') as n8 \gset
select tests.check('manager REVOGADO nao valida',
    ((:'n8')::jsonb ->> 'allowed') = 'false');
rollback;

-- ---------------------------------------------------------------------------
-- Histórico imutável, sem PII, com leitura restrita
-- ---------------------------------------------------------------------------
select tests.check_raises('historico de validacao e imutavel',
  $sql$update public.benefit_validation_attempts set result='forwarded_to_app'$sql$,
  'validacao_imutavel');
select tests.check_raises('historico de validacao nao pode ser apagado',
  $sql$delete from public.benefit_validation_attempts$sql$,
  'validacao_imutavel');
select tests.check('historico NAO guarda PII do usuario do App',
    (select bool_and(to_jsonb(a)::text !~* '(cpf|email|full_name|phone)')
       from public.benefit_validation_attempts a));

begin;
select tests.impersonate('authenticated', :'uid_owner1');
select tests.check('owner ve o historico da propria rede',
    (select count(*) from public.benefit_validation_attempts) >= 3);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check('terceiro nao ve historico de validacao alheio',
    (select count(*) from public.benefit_validation_attempts) = 0);
rollback;

-- Desfecho do gateway: só backend
select id as att1 from public.benefit_validation_attempts
 where result='forwarded_to_app' limit 1 \gset
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select tests.check_raises('parceiro nao registra desfecho do gateway',
  format($sql$select public.prov_record_validation_result(%L)$sql$, :'att1'),
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select public.prov_record_validation_result((:'att1')::uuid, gen_random_uuid()) as des \gset
select tests.check('backend registra o desfecho como auditoria',
    ((:'des')::jsonb ->> 'recorded') = 'true');
commit;

select tests.check('desfecho do App vira log, nao UPDATE do historico',
    (select count(*) from public.audit_logs
      where action = 'benefit_validation.accepted_by_app') = 1);

select tests.finish('190_m2_benefit_validation');
