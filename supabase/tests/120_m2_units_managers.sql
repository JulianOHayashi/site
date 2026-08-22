-- ============================================================================
-- SUITE 120 — Unidades e managers (R4). Continua sobre as suítes 100/110.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_titular from auth.users where email = 'titular_m2@teste.local' \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select m.id as owner1, m.company_id as company1
  from public.site_company_members m
 where m.role = 'partner_owner'
   and m.auth_user_id = (select id from auth.users where email='titular_m2@teste.local') \gset
-- Owner da SEGUNDA empresa (para provas de rede cruzada).
select m.company_id as company2
  from public.site_company_members m
 where m.role = 'partner_owner' and m.company_id <> :'company1' limit 1 \gset

-- Contas dos managers (o aceite exige e-mail casando com o convite).
select tests.mk_user('gestor1') as uid_g1 \gset
select tests.mk_user('gestor2') as uid_g2 \gset
select tests.mk_user('gestor3') as uid_g3 \gset

-- ---------------------------------------------------------------------------
-- Prontidão ANTES de unidade: fechada
-- ---------------------------------------------------------------------------
select tests.check('sem unidade ativa nao ha validador nem prontidao',
    (public.company_launch_readiness(:'company1') ->> 'active_unit') = 'false'
    and (public.company_launch_readiness(:'company1') ->> 'active_validator') = 'false');

-- ---------------------------------------------------------------------------
-- Unidades
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_intruso');
select public.owner_create_unit((:'company1')::uuid,'Matriz','Vitória','ES') as u_neg \gset
select tests.check('nao-owner nao cria unidade',
    ((:'u_neg')::jsonb ->> 'reason') = 'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_create_unit((:'company1')::uuid,'Matriz','Vitória','ES') as u1 \gset
select tests.check('owner cria unidade', ((:'u1')::jsonb ->> 'ok') = 'true');
select public.owner_create_unit((:'company1')::uuid,'  matriz ','Serra','ES') as u_dup \gset
select tests.check('nome de unidade duplicado e recusado',
    ((:'u_dup')::jsonb ->> 'reason') = 'duplicate_unit');
select public.owner_create_unit((:'company1')::uuid,'Filial Serra','Serra','ES') as u2 \gset
commit;
select ((:'u1')::jsonb ->> 'unit_id') as unit1 \gset
select ((:'u2')::jsonb ->> 'unit_id') as unit2 \gset

-- Owner ativo + unidade ativa já basta: manager NÃO é exigido pelo gate.
select tests.check('unidade ativa + owner ativo -> prontidao completa SEM manager',
    (public.company_launch_readiness(:'company1') ->> 'active_unit') = 'true'
    and (public.company_launch_readiness(:'company1') ->> 'active_validator') = 'true');

-- ---------------------------------------------------------------------------
-- Convite: o segredo NÃO nasce na criação
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_create_manager_invite(
    (:'company1')::uuid, 'gestor1@teste.local', 'Gestor Um', (:'unit1')::uuid) as inv1 \gset
select tests.check('owner cria convite', ((:'inv1')::jsonb ->> 'ok') = 'true');
select tests.check('criacao do convite NAO devolve segredo',
    ((:'inv1')::jsonb ->> 'token') is null);
commit;
select ((:'inv1')::jsonb ->> 'invite_id') as invite1 \gset

select tests.check('nenhum token existe antes do despacho',
    (select count(*) from public.site_manager_invite_tokens
      where invite_id = :'invite1') = 0);
select tests.check('outbox do convite nao carrega segredo',
    (select template_data::text !~* '(token|secret|senha)'
       from public.notification_events
      where correlation_entity_id is null
        and template_data->>'invite_id' = :'invite1'));

-- ---------------------------------------------------------------------------
-- Cunhagem no DESPACHO (padrão canônico espelhado)
-- ---------------------------------------------------------------------------
select id as evt1 from public.notification_events
 where template_key = 'manager_invite'
   and template_data->>'invite_id' = :'invite1' \gset

begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check_raises(
  'owner nao cunha token de convite',
  format($sql$select public.svc_mint_manager_invite_token(%L)$sql$, :'evt1'),
  'permission denied');
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises(
  'anon nao cunha token de convite',
  format($sql$select public.svc_mint_manager_invite_token(%L)$sql$, :'evt1'),
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt1')::uuid) as mint1 \gset
select tests.check('worker cunha o segredo no despacho',
    ((:'mint1')::jsonb ->> 'ok') = 'true'
    and length((:'mint1')::jsonb ->> 'token') = 64
    and ((:'mint1')::jsonb ->> 'purpose') = 'manager_invite');
select tests.check('TTL de 48h aplicado',
    ((:'mint1')::jsonb ->> 'expires_in_seconds')::bigint = 172800);
-- LEASE: segunda cunhagem imediata é recusada.
select public.svc_mint_manager_invite_token((:'evt1')::uuid) as mint_lease \gset
select tests.check('lease impede cunhagem concorrente',
    ((:'mint_lease')::jsonb ->> 'reason') = 'lease_held');
commit;

select ((:'mint1')::jsonb ->> 'token') as token1 \gset

select tests.check('somente o HASH e persistido',
    (select token_hash = public.m1_token_hash(:'token1')
       from public.site_manager_invite_tokens where invite_id = :'invite1'));
select tests.check('o segredo cru NAO aparece em nenhuma tabela do convite',
    (select count(*) from public.site_manager_invite_tokens
      where encode(token_hash,'hex') = :'token1') = 0
    and (select count(*) from public.notification_events
          where template_data::text like '%' || :'token1' || '%') = 0);
select tests.check('auditoria da cunhagem NAO contem segredo',
    (select count(*) from public.audit_logs
      where action = 'manager_invite.token_minted'
        and coalesce(new_state::text,'') like '%' || :'token1' || '%') = 0);

-- ---------------------------------------------------------------------------
-- Aceite: e-mail correto, uso único
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_g2');
select public.accept_manager_invite(:'token1') as acc_err \gset
select tests.check('conta com e-mail diferente NAO aceita o convite',
    ((:'acc_err')::jsonb ->> 'reason') = 'email_mismatch');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_g1');
select public.accept_manager_invite(:'token1') as acc1 \gset
select tests.check('manager convidado aceita', ((:'acc1')::jsonb ->> 'ok') = 'true');
commit;
select ((:'acc1')::jsonb ->> 'member_id') as mgr1 \gset

select tests.check('aceite vincula o manager a unidade do convite',
    (select count(*) from public.site_member_unit_bindings
      where member_id = :'mgr1' and unit_id = :'unit1' and status = 'active') = 1);

begin;
select tests.impersonate('authenticated', :'uid_g1');
select public.accept_manager_invite(:'token1') as acc_reuso \gset
select tests.check('token e de USO UNICO',
    ((:'acc_reuso')::jsonb ->> 'reason') = 'invalid_token');
rollback;

-- ---------------------------------------------------------------------------
-- Reenvio supersede; revogação e expiração invalidam
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_create_manager_invite(
    (:'company1')::uuid, 'gestor2@teste.local', 'Gestor Dois', (:'unit2')::uuid) as inv2a \gset
commit;
select id as evt2a from public.notification_events
 where template_data->>'invite_id' = ((:'inv2a')::jsonb ->> 'invite_id') \gset
begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt2a')::uuid) as m2a \gset
commit;
select ((:'m2a')::jsonb ->> 'token') as token2a \gset

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_create_manager_invite(
    (:'company1')::uuid, 'gestor2@teste.local', 'Gestor Dois', (:'unit2')::uuid) as inv2b \gset
commit;
select tests.check('reenvio supersede o convite anterior',
    (select status from public.site_manager_invites
      where id = ((:'inv2a')::jsonb ->> 'invite_id')::uuid) = 'superseded');

begin;
select tests.impersonate('authenticated', :'uid_g2');
select public.accept_manager_invite(:'token2a') as acc_sup \gset
select tests.check('token do convite supersedido morre',
    ((:'acc_sup')::jsonb ->> 'reason') = 'invalid_token');
rollback;

-- Expiração
select id as evt2b from public.notification_events
 where template_data->>'invite_id' = ((:'inv2b')::jsonb ->> 'invite_id') \gset
begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt2b')::uuid) as m2b \gset
commit;
-- Envelhece o token INTEIRO (49h atrás), preservando expires_at > created_at
-- como no domínio canônico: é assim que um convite realmente expira.
update public.site_manager_invite_tokens
   set created_at = now() - interval '49 hours',
       expires_at = now() - interval '1 hour'
 where invite_id = ((:'inv2b')::jsonb ->> 'invite_id')::uuid
   and consumed_at is null and invalidated_at is null;

begin;
select tests.impersonate('authenticated', :'uid_g2');
select public.accept_manager_invite(((:'m2b')::jsonb ->> 'token')) as acc_exp \gset
select tests.check('token de 48h expirado e recusado',
    ((:'acc_exp')::jsonb ->> 'reason') = 'expired');
commit;
select tests.check('convite expirado muda de estado',
    (select status from public.site_manager_invites
      where id = ((:'inv2b')::jsonb ->> 'invite_id')::uuid) = 'expired');

-- Revogação pelo owner
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_create_manager_invite(
    (:'company1')::uuid, 'gestor3@teste.local', 'Gestor Tres', (:'unit1')::uuid) as inv3 \gset
commit;
select id as evt3 from public.notification_events
 where template_data->>'invite_id' = ((:'inv3')::jsonb ->> 'invite_id') \gset
begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt3')::uuid) as m3 \gset
commit;
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_revoke_manager_invite(((:'inv3')::jsonb ->> 'invite_id')::uuid);
commit;
begin;
select tests.impersonate('authenticated', :'uid_g3');
select public.accept_manager_invite(((:'m3')::jsonb ->> 'token')) as acc_rev \gset
select tests.check('convite revogado nao aceita',
    ((:'acc_rev')::jsonb ->> 'reason') = 'invalid_token');
rollback;

-- Enquanto o lease do worker anterior está VIVO, a ordem canônica recusa por
-- lease_held antes de qualquer outra análise.
begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt3')::uuid) as m3_lease \gset
select tests.check('lease vivo tem precedencia sobre o estado do convite',
    ((:'m3_lease')::jsonb ->> 'reason') = 'lease_held');
commit;

-- O lease é preso ao relógio: o trigger canônico de updated_at impede
-- envelhecê-lo por UPDATE, o que é uma propriedade desejável. Para exercitar
-- a coerência propósito/estado usa-se o caminho realista — convite revogado
-- ANTES do primeiro despacho, com o evento ainda em 'pending' (sem lease).
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_create_manager_invite(
    (:'company1')::uuid, 'gestor3@teste.local', 'Gestor Tres', (:'unit1')::uuid) as inv4 \gset
select public.owner_revoke_manager_invite(((:'inv4')::jsonb ->> 'invite_id')::uuid);
commit;

select id as evt4 from public.notification_events
 where template_data->>'invite_id' = ((:'inv4')::jsonb ->> 'invite_id') \gset

begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt4')::uuid) as m4 \gset
select tests.check('convite revogado antes do despacho -> stale_for_state',
    ((:'m4')::jsonb ->> 'reason') = 'stale_for_state');
commit;

select tests.check('convite revogado NUNCA ganha token',
    (select count(*) from public.site_manager_invite_tokens
      where invite_id = ((:'inv4')::jsonb ->> 'invite_id')::uuid) = 0);
select tests.check('evento do convite morto e cancelado, nao reenviado',
    (select status from public.notification_events where id = :'evt4') = 'cancelled');

-- ---------------------------------------------------------------------------
-- Validador: owner em todas; manager só nas vinculadas
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.get_my_validator_context((:'company1')::uuid) as vo \gset
select tests.check('owner valida em TODAS as unidades ativas',
    ((:'vo')::jsonb ->> 'eligible') = 'true'
    and ((:'vo')::jsonb ->> 'role') = 'partner_owner'
    and jsonb_array_length((:'vo')::jsonb -> 'units') = 2);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_g1');
select public.get_my_validator_context((:'company1')::uuid) as vm \gset
select tests.check('manager valida SOMENTE na unidade vinculada',
    ((:'vm')::jsonb ->> 'eligible') = 'true'
    and ((:'vm')::jsonb ->> 'role') = 'partner_manager'
    and jsonb_array_length((:'vm')::jsonb -> 'units') = 1
    and ((:'vm')::jsonb -> 'units' -> 0 ->> 'unit_id') = :'unit1');
select tests.check('manager NAO le convites (e-mails de terceiros)',
    (select count(*) from public.site_manager_invites) = 0);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check('conta de fora nao e validador',
    (public.get_my_validator_context((:'company1')::uuid) ->> 'eligible') = 'false');
rollback;

-- Manager de OUTRA empresa não valida nesta rede.
begin;
select tests.impersonate('authenticated', :'uid_g1');
select tests.check('manager nao valida em rede de outro parceiro',
    (public.get_my_validator_context((:'company2')::uuid) ->> 'eligible') = 'false');
rollback;

-- ---------------------------------------------------------------------------
-- Suspensão / revogação com efeito IMEDIATO
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_g1');
select public.owner_set_manager_status((:'mgr1')::uuid,'suspend') as neg \gset
select tests.check('manager nao gere o proprio status',
    ((:'neg')::jsonb ->> 'reason') = 'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_set_manager_status((:'mgr1')::uuid,'suspend');
commit;
begin;
select tests.impersonate('authenticated', :'uid_g1');
select tests.check('manager SUSPENSO deixa de validar imediatamente',
    (public.get_my_validator_context((:'company1')::uuid) ->> 'eligible') = 'false');
select tests.check('manager suspenso perde o contexto de parceiro',
    (public.get_my_partner_context() ->> 'authorized') = 'false');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_set_manager_status((:'mgr1')::uuid,'reactivate');
commit;
begin;
select tests.impersonate('authenticated', :'uid_g1');
select tests.check('reativacao devolve a validacao',
    (public.get_my_validator_context((:'company1')::uuid) ->> 'eligible') = 'true');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_set_manager_status((:'mgr1')::uuid,'revoke') as rev_sem \gset
select tests.check('revogacao exige justificativa',
    ((:'rev_sem')::jsonb ->> 'reason') = 'reason_required');
select public.owner_set_manager_status((:'mgr1')::uuid,'revoke','desligamento') as rev \gset
select tests.check('revogacao executa', ((:'rev')::jsonb ->> 'ok') = 'true');
commit;

select tests.check('revogacao derruba os vinculos de unidade',
    (select count(*) from public.site_member_unit_bindings
      where member_id = :'mgr1' and status = 'active') = 0);
begin;
select tests.impersonate('authenticated', :'uid_g1');
select tests.check('manager REVOGADO nao valida',
    (public.get_my_validator_context((:'company1')::uuid) ->> 'eligible') = 'false');
rollback;

-- Unidade suspensa some do contexto (inclusive para o owner)
begin;
select tests.impersonate('authenticated', :'uid_titular');
select public.owner_set_unit_status((:'unit1')::uuid,'suspended','reforma');
select tests.check('unidade suspensa sai do contexto do owner',
    jsonb_array_length(public.get_my_validator_context((:'company1')::uuid) -> 'units') = 1);
select public.owner_set_unit_status((:'unit1')::uuid,'active');
commit;

-- ---------------------------------------------------------------------------
-- ACL e ausência de leitura de segredo
-- ---------------------------------------------------------------------------
select tests.check('tabela de tokens de convite NAO tem policy alguma',
    (select count(*) from pg_policies
      where schemaname='public' and tablename='site_manager_invite_tokens') = 0);
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check_raises(
  'nem o owner le a tabela de tokens',
  'select count(*) from public.site_manager_invite_tokens',
  'permission denied');
rollback;
select tests.check('m2_emitir_token_convite fora do alcance de toda role de API',
    has_function_privilege('anon','public.m2_emitir_token_convite(uuid,text,interval)','EXECUTE') = false
    and has_function_privilege('authenticated','public.m2_emitir_token_convite(uuid,text,interval)','EXECUTE') = false
    and has_function_privilege('service_role','public.m2_emitir_token_convite(uuid,text,interval)','EXECUTE') = false);

select tests.finish('120_m2_units_managers');
