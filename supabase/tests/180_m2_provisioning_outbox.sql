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
    (:'pay1')::jsonb ->> 'schema_version' = 'bdflow.commercial_provisioning.v2'
    and ((:'pay1')::jsonb ->> 'participant_target')::int = 84
    and ((:'pay1')::jsonb ->> 'distribution_policy_version')::int = 2
    -- Cronograma NAO muda nesta etapa: continua a matriz 7x7 versao 1.
    and ((:'pay1')::jsonb ->> 'schedule_policy_version')::int = 1);
select tests.check('coluna schema_version da fila concorda com o payload',
    (select m.schema_version from public.app_provisioning_messages m
      where m.id = :'msg1') = ((:'pay1')::jsonb ->> 'schema_version'));
-- V2: cada parceiro carrega a PROPRIA escolha contratual e a politica 2.
select tests.check('cada parceiro carrega modo de liquidacao e politica 2',
    (select count(*) from jsonb_array_elements((:'pay1')::jsonb -> 'partners') p
      where (p ->> 'benefit_settlement_mode') in ('direct_benefits','cash')
        and (p ->> 'benefit_distribution_policy_version')::int = 2) = 6);
select tests.check('payload reflete a formacao MISTA, nao um modo unico',
    (select count(*) from jsonb_array_elements((:'pay1')::jsonb -> 'partners') p
      where (p ->> 'benefit_settlement_mode') = 'direct_benefits') = 5
    and (select count(*) from jsonb_array_elements((:'pay1')::jsonb -> 'partners') p
      where (p ->> 'benefit_settlement_mode') = 'cash') = 1);
-- O modo de cada parceiro vem do snapshot do pedido, nao de um padrao.
select tests.check('modo de cada parceiro confere com o snapshot imutavel',
    (select count(*) from jsonb_array_elements((:'pay1')::jsonb -> 'partners') p
       join public.commercial_exclusivity_orders o
         on o.id = (p ->> 'site_order_reference')::uuid
      where p ->> 'benefit_settlement_mode' is distinct from o.benefit_settlement_mode
         or (p ->> 'contractual_pool_cents')::bigint
              is distinct from o.contractual_pool_cents) = 0);
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
-- A V2 acrescentou campos ao pedido; NENHUM deles de contabilidade entrou no
-- payload. O App recebe pool + modo, nao o financiamento devido a BDFlow.
select tests.check('payload NAO contem o financiamento V2 do lado Site',
    (:'pay1')::jsonb::text not like '%cash_user_pool_funding%'
    and (:'pay1')::jsonb::text not like '%total_monetary_funding%'
    and (:'pay1')::jsonb::text not like '%fidelized%'
    and (:'pay1')::jsonb::text not like '%pool_bps%'
    and (:'pay1')::jsonb::text not like '%cnpj%'
    and (:'pay1')::jsonb::text not like '%cpf%'
    and (:'pay1')::jsonb::text not like '%email%');
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

-- ---------------------------------------------------------------------------
-- TRANSICAO DE VERSAO: mensagem V1 pendente nao vira despacho V2 por acidente
--
-- O payload e o schema_version da linha sao IMUTAVEIS. Reconstruir a mensagem
-- no lugar exigiria enfraquecer m2_provisioning_protect(), o que nao se faz.
-- A saida e recusa na reivindicacao com transicao de estado que o ciclo de
-- vida ja previa, liberando o indice parcial para um reenfileiramento V2.
-- ---------------------------------------------------------------------------
insert into public.app_provisioning_messages
    (environment, exclusivity_id, schema_version, payload, payload_hash, created_by)
values ('staging', (:'excl2')::uuid, 'bdflow.commercial_provisioning.v1',
        jsonb_build_object(
          'ok', true,
          'schema_version', 'bdflow.commercial_provisioning.v1',
          'environment', 'staging',
          'commercial_exclusivity_id', (:'excl2')::uuid,
          'participant_target', 84,
          'distribution_policy_version', 1,
          'schedule_policy_version', 1,
          'partners', '[]'::jsonb),
        repeat('a', 64), (:'uid_admin')::uuid)
returning id as msg_v1 \gset

begin;
select tests.impersonate('service_role', null);
select public.prov_claim_provisioning_message((:'msg_v1')::uuid) as claim_v1 \gset
select tests.check('mensagem V1 pendente NAO e despachada como se fosse V2',
    ((:'claim_v1')::jsonb ->> 'ok') = 'false'
    and ((:'claim_v1')::jsonb ->> 'reason') = 'stale_schema_version'
    and ((:'claim_v1')::jsonb ->> 'found_schema_version')
        = 'bdflow.commercial_provisioning.v1');
-- Idempotente: reivindicar de novo devolve exatamente o mesmo veredito.
select public.prov_claim_provisioning_message((:'msg_v1')::uuid) as claim_v1b \gset
select tests.check('recusa por versao obsoleta e idempotente',
    ((:'claim_v1b')::jsonb ->> 'reason') = 'stale_schema_version');
commit;

select tests.check('mensagem V1 fica failed com motivo explicito, sem mutar payload',
    (select status = 'failed' and last_error = 'stale_schema_version'
        and payload ->> 'schema_version' = 'bdflow.commercial_provisioning.v1'
       from public.app_provisioning_messages where id = :'msg_v1'));

-- Liberado o indice parcial de unicidade, o reenfileiramento produz V2.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_enqueue_app_provisioning((:'excl2')::uuid,'staging') as enq_v2 \gset
select tests.check('reenfileiramento apos recusa produz mensagem nova',
    ((:'enq_v2')::jsonb ->> 'ok') = 'true'
    and ((:'enq_v2')::jsonb ->> 'already') = 'false'
    and ((:'enq_v2')::jsonb ->> 'message_id') <> (:'msg_v1'));
commit;

select ((:'enq_v2')::jsonb ->> 'message_id') as msg_v2 \gset
select tests.check('a mensagem reenfileirada e V2 no payload e na coluna',
    (select schema_version = 'bdflow.commercial_provisioning.v2'
        and payload ->> 'schema_version' = 'bdflow.commercial_provisioning.v2'
        and (payload ->> 'distribution_policy_version')::int = 2
       from public.app_provisioning_messages where id = :'msg_v2'));
select tests.check('idempotencia por exclusividade preservada: uma viva por ambiente',
    (select count(*) from public.app_provisioning_messages
      where exclusivity_id = :'excl2' and environment = 'staging'
        and status in ('pending','dispatching','accepted')) = 1);
-- Mensagem finalizada NAO e reavaliada pela porta de versao.
begin;
select tests.impersonate('service_role', null);
select public.prov_claim_provisioning_message((:'msg1')::uuid) as claim_ok \gset
select tests.check('mensagem ja aceita permanece aceita, sem reavaliar versao',
    ((:'claim_ok')::jsonb ->> 'already') = 'true'
    and ((:'claim_ok')::jsonb ->> 'status') = 'accepted');
commit;

-- Formacao sem semantica V2 nao vira asserção comercial: falha fechada.
select tests.check('payload falha fechado se algum pedido nao declarar V2',
    ((select public.build_app_provisioning_payload((:'excl3')::uuid,'local'))
       ->> 'reason') is not distinct from
    (case when (select count(*) from public.commercial_exclusivity_orders
                 where exclusivity_id = :'excl3' and status='signed'
                   and (benefit_settlement_mode is null
                        or benefit_distribution_policy_version is distinct from 2)) > 0
          then 'incompatible_distribution_policy' else null end));

select tests.finish('180_m2_provisioning_outbox');
