-- ============================================================================
-- SUITE 180 — Outbox de provisionamento (R11, camada 1 de 5)
-- Roda sobre a exclusividade AUTORIZADA pela suíte 170.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select id as excl2 from public.commercial_exclusivities where sequence_number = 2 \gset
select o.company_id as comp1 from public.commercial_exclusivity_orders o
 where o.exclusivity_id = :'excl2' and o.niche_code='supermarket' \gset
select auth_user_id as uid_owner1 from public.site_company_members
 where company_id = :'comp1' and role='partner_owner' \gset

-- ---------------------------------------------------------------------------
-- Domínio SEPARADO do outbox de e-mail
-- ---------------------------------------------------------------------------
select tests.check('provisionamento tem tabela propria, nao notification_events',
    to_regclass('public.app_provisioning_messages') is not null);
select tests.check('operacoes de servico proprias (prov_*), nao svc_* de e-mail',
    to_regprocedure('public.prov_claim_provisioning_message(uuid)') is not null
    and to_regprocedure('public.prov_record_provisioning_result(uuid,boolean,uuid,text,text)') is not null);
select tests.check('nenhuma funcao svc_* de e-mail foi alterada para provisionar',
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname like 'svc\_%'
        and p.prosrc ilike '%provisioning%') = 0);

-- ---------------------------------------------------------------------------
-- Autorização
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check_raises('nao-admin nao enfileira provisionamento',
  format($sql$select public.admin_enqueue_app_provisioning(%L,'local')$sql$, :'excl2'),
  'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_owner1');
select tests.check_raises('parceiro nao enfileira provisionamento',
  format($sql$select public.admin_enqueue_app_provisioning(%L,'local')$sql$, :'excl2'),
  'not_authorized');
select tests.check_raises('parceiro nao monta o payload da ponte',
  format($sql$select public.build_app_provisioning_payload(%L,'local')$sql$, :'excl2'),
  'permission denied');
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises('anon nao le mensagens de provisionamento',
  'select count(*) from public.app_provisioning_messages', 'permission denied');
select tests.check_raises('anon nao escreve vinculo comercial<->operacional',
  $sql$insert into public.commercial_operational_bindings
    (exclusivity_id, operational_cycle_id, environment, provisioning_message_id)
    values (gen_random_uuid(), gen_random_uuid(), 'local', gen_random_uuid())$sql$,
  'permission denied');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_enqueue_app_provisioning((:'excl2')::uuid,'producao') as env_bad \gset
select tests.check('ambiente invalido e recusado',
    ((:'env_bad')::jsonb ->> 'reason') = 'invalid_environment');
rollback;

-- Exclusividade sem autorização operacional não provisiona.
insert into public.commercial_exclusivities
    (id, region_id, sequence_number, status, is_current)
values (gen_random_uuid(),
        (select id from public.commercial_regions where uf='ES' limit 1),
        3, 'forming', false)
returning id as excl3 \gset

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_enqueue_app_provisioning((:'excl3')::uuid,'local') as nao_aut \gset
select tests.check('exclusividade nao autorizada nao provisiona',
    ((:'nao_aut')::jsonb ->> 'reason') = 'operation_not_authorized');
rollback;

-- ---------------------------------------------------------------------------
-- Enfileiramento e conteúdo do snapshot
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_enqueue_app_provisioning((:'excl2')::uuid,'local') as enq1 \gset
select tests.check('admin enfileira apos o gate',
    ((:'enq1')::jsonb ->> 'ok') = 'true'
    and ((:'enq1')::jsonb ->> 'status') = 'pending');
select public.admin_enqueue_app_provisioning((:'excl2')::uuid,'local') as enq2 \gset
select tests.check('enfileiramento repetido e idempotente',
    ((:'enq2')::jsonb ->> 'already') = 'true'
    and ((:'enq2')::jsonb ->> 'message_id') = ((:'enq1')::jsonb ->> 'message_id'));
commit;

select ((:'enq1')::jsonb ->> 'message_id') as msg1 \gset
select payload as pay1 from public.app_provisioning_messages where id = :'msg1' \gset

select tests.check('payload traz os seis parceiros',
    jsonb_array_length((:'pay1')::jsonb -> 'partners') = 6);
select tests.check('payload carimba versoes de schema e politicas',
    (:'pay1')::jsonb ->> 'schema_version' = 'bdflow.commercial_provisioning.v1'
    and ((:'pay1')::jsonb ->> 'participant_target')::int = 84
    and ((:'pay1')::jsonb ->> 'distribution_policy_version')::int = 1
    and ((:'pay1')::jsonb ->> 'schedule_policy_version')::int = 1);
select tests.check('payload usa UUID de ponte para rede, filial e validador',
    (select count(*) from jsonb_array_elements((:'pay1')::jsonb -> 'partners') p
      where (p ->> 'partner_network_bridge_id') is not null
        and jsonb_array_length(p -> 'branches') >= 1
        and jsonb_array_length(p -> 'validators') >= 1) = 6);
select tests.check('payload envia o POOL contratual, nunca valor individual',
    (select sum((p ->> 'contractual_pool_cents')::bigint)
       from jsonb_array_elements((:'pay1')::jsonb -> 'partners') p) = 9231600
    and (:'pay1')::jsonb::text not like '%assigned_amount%');

-- NÃO VAZA PII nem financeiro interno.
select tests.check('payload NAO contem CNPJ de nenhum parceiro',
    (select count(*) from public.site_partner_companies c
      where (:'pay1')::jsonb::text like '%' || c.cnpj || '%') = 0);
select tests.check('payload NAO contem razao social nem nome fantasia',
    (select count(*) from public.site_partner_companies c
      where (:'pay1')::jsonb::text like '%' || c.legal_name || '%'
         or ((:'pay1')::jsonb::text like '%' || c.trade_name || '%'
             and c.trade_name is not null)) = 0);
select tests.check('payload NAO contem CPF nem e-mail de pessoas',
    (select count(*) from public.site_company_members m
      where (m.cpf is not null and (:'pay1')::jsonb::text like '%' || m.cpf || '%')
         or (m.email is not null and (:'pay1')::jsonb::text like '%' || m.email || '%')) = 0);
select tests.check('payload NAO contem financeiro interno da BDFlow',
    (:'pay1')::jsonb::text not like '%bdflow_due%'
    and (:'pay1')::jsonb::text not like '%payment%'
    and (:'pay1')::jsonb::text not like '%economic_value%'
    and (:'pay1')::jsonb::text not like '%document_reference%');
select tests.check('nenhum segredo/chave e persistido na fila',
    (select count(*) from public.app_provisioning_messages
      where payload::text ~* '(private_key|secret|token|password|service_role)') = 0);

-- Imutabilidade
select tests.check_raises('payload da mensagem e imutavel',
  format($sql$update public.app_provisioning_messages
           set payload = '{}'::jsonb where id = %L$sql$, :'msg1'),
  'provisionamento_imutavel');
select tests.check_raises('mensagem nao pode ser excluida',
  format($sql$delete from public.app_provisioning_messages where id = %L$sql$, :'msg1'),
  'provisionamento_imutavel');

-- ---------------------------------------------------------------------------
-- Worker: só service_role; lease e tentativas próprias
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.check_raises('admin autenticado nao reivindica mensagem',
  format($sql$select public.prov_claim_provisioning_message(%L)$sql$, :'msg1'),
  'permission denied');
select tests.check_raises('admin autenticado nao registra resultado do App',
  format($sql$select public.prov_record_provisioning_result(%L, true, gen_random_uuid())$sql$, :'msg1'),
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select public.prov_claim_provisioning_message((:'msg1')::uuid) as claim1 \gset
select tests.check('worker reivindica e recebe payload + JTI',
    ((:'claim1')::jsonb ->> 'ok') = 'true'
    and ((:'claim1')::jsonb ->> 'correlation_id') is not null
    and ((:'claim1')::jsonb -> 'payload') is not null);
select public.prov_claim_provisioning_message((:'msg1')::uuid) as claim2 \gset
select tests.check('lease impede reivindicacao concorrente',
    ((:'claim2')::jsonb ->> 'reason') = 'lease_held');
commit;

-- Fora do papel de worker: service_role NÃO lê a tabela direto (por desenho),
-- então a conferência do JTI é feita aqui.
select tests.check('a correlacao devolvida e o JTI antirreplay da mensagem',
    ((:'claim1')::jsonb ->> 'correlation_id')
      = (select correlation_id::text from public.app_provisioning_messages
          where id = :'msg1'));
select tests.check('worker NAO tem leitura direta da fila (so pelas RPCs)',
    has_table_privilege('service_role','public.app_provisioning_messages','SELECT') = false);

-- ---------------------------------------------------------------------------
-- Aceite do App: vínculo durável, único e idempotente
-- ---------------------------------------------------------------------------
select gen_random_uuid() as cycle1 \gset

begin;
select tests.impersonate('service_role', null);
select public.prov_record_provisioning_result((:'msg1')::uuid, true) as sem_ciclo \gset
select tests.check('aceite sem ciclo operacional e recusado',
    ((:'sem_ciclo')::jsonb ->> 'reason') = 'operational_cycle_required');
select public.prov_record_provisioning_result(
    (:'msg1')::uuid, true, (:'cycle1')::uuid) as res1 \gset
select tests.check('aceite cria o vinculo comercial<->operacional',
    ((:'res1')::jsonb ->> 'status') = 'accepted'
    and ((:'res1')::jsonb ->> 'binding_id') is not null);
select public.prov_record_provisioning_result(
    (:'msg1')::uuid, true, (:'cycle1')::uuid) as res2 \gset
select tests.check('registro repetido do aceite e idempotente',
    ((:'res2')::jsonb ->> 'already') = 'true'
    and ((:'res2')::jsonb ->> 'binding_id') = ((:'res1')::jsonb ->> 'binding_id'));
commit;

select tests.check('existe exatamente UM vinculo para a exclusividade',
    (select count(*) from public.commercial_operational_bindings
      where exclusivity_id = :'excl2') = 1);
select tests.check_raises('vinculo e imutavel',
  format($sql$update public.commercial_operational_bindings
           set operational_cycle_id = gen_random_uuid() where exclusivity_id = %L$sql$, :'excl2'),
  'vinculo_imutavel');
select tests.check_raises('vinculo nao pode ser excluido',
  format($sql$delete from public.commercial_operational_bindings where exclusivity_id = %L$sql$, :'excl2'),
  'vinculo_imutavel');
select tests.check_raises('aceite registrado nao troca de ciclo',
  format($sql$update public.app_provisioning_messages
           set operational_cycle_id = gen_random_uuid() where id = %L$sql$, :'msg1'),
  'provisionamento_imutavel');

-- Um ciclo operacional não serve a duas formações.
update public.commercial_exclusivities
   set status='operation_authorized', operation_authorized_at=now(), formed_at=now()
 where id = :'excl3';
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_enqueue_app_provisioning((:'excl3')::uuid,'local') as enq3 \gset
commit;
select ((:'enq3')::jsonb ->> 'message_id') as msg3 \gset

begin;
select tests.impersonate('service_role', null);
select public.prov_record_provisioning_result(
    (:'msg3')::uuid, true, (:'cycle1')::uuid) as res_dup \gset
select tests.check('ciclo operacional ja vinculado e recusado',
    ((:'res_dup')::jsonb ->> 'reason') = 'operational_cycle_already_bound');
commit;

-- Recusa soberana do App
begin;
select tests.impersonate('service_role', null);
select public.prov_record_provisioning_result(
    (:'msg3')::uuid, false, null, 'PARTNER_NETWORK_UNKNOWN', 'rede desconhecida') as res_rej \gset
select tests.check('recusa do App e registrada com codigo',
    ((:'res_rej')::jsonb ->> 'status') = 'rejected');
commit;

select tests.check('recusa NAO cria vinculo',
    (select count(*) from public.commercial_operational_bindings
      where exclusivity_id = :'excl3') = 0);

-- ---------------------------------------------------------------------------
-- Camadas 2 a 5 continuam pendentes: nada aqui assina nem faz HTTP
-- ---------------------------------------------------------------------------
select tests.check('o banco NAO assina nem faz HTTP (camadas 2-3 fora daqui)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname like 'prov\_%'
        and p.prosrc ~* '(ed25519|sign|http|curl|net\.)') = 0);

select tests.finish('180_m2_provisioning_outbox');
