-- ============================================================================
-- SUITE 200 — Outbox de e-mail sobre a semântica canônica do M1 (R13)
-- Prova que o convite do R4 atravessa o outbox canônico sem vazar segredo.
-- ============================================================================

select tests.reset_results();

select user_id as uid_admin from public.site_admins limit 1 \gset
select o.company_id as comp1 from public.commercial_exclusivity_orders o
 where o.exclusivity_id = (select id from public.commercial_exclusivities where sequence_number=2)
   and o.niche_code='supermarket' \gset
select auth_user_id as uid_owner1 from public.site_company_members
 where company_id = :'comp1' and role='partner_owner' \gset
select id as unit1 from public.site_partner_units where company_id = :'comp1' limit 1 \gset
select tests.mk_user('gestor_outbox') as uid_g \gset

-- ---------------------------------------------------------------------------
-- A máquina de estados canônica NÃO foi redesenhada
-- ---------------------------------------------------------------------------
select tests.check('svc_* canonicas do M1 continuam sendo as unicas de e-mail',
    to_regprocedure('public.svc_mark_notification_sent(uuid,text,text)') is not null
    and to_regprocedure('public.svc_mark_notification_failed(uuid,text,text)') is not null
    and to_regprocedure('public.svc_reschedule_notification(uuid,interval)') is not null);
select tests.check('nenhuma funcao nova duplica as transicoes de notificacao',
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname ~ '^(mark_notification|notification_mark)'
        and p.proname not like 'svc\_%') = 0);
select tests.check('trigger de protecao do outbox segue ativo',
    (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
      where c.relname='notification_events' and not t.tgisinternal
        and t.tgname = 'trg_notification_events_protect') = 1);

-- ---------------------------------------------------------------------------
-- Convite de manager pelo outbox canônico
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.owner_create_manager_invite(
    (:'comp1')::uuid, 'gestor_outbox@teste.local', 'Gestor Outbox',
    (:'unit1')::uuid) as inv \gset
select tests.check('convite criado', ((:'inv')::jsonb ->> 'ok') = 'true');
commit;

select ((:'inv')::jsonb ->> 'invite_id') as invite1 \gset
select id as evt1, status as st1 from public.notification_events
 where template_data->>'invite_id' = :'invite1' \gset

select tests.check('evento nasce pending no outbox canonico',
    :'st1' = 'pending');
select tests.check('payload do outbox NAO carrega segredo',
    (select template_data::text !~* '(token|secret|senha|password)'
       from public.notification_events where id = :'evt1'));
select tests.check('nenhum token existe antes do despacho',
    (select count(*) from public.site_manager_invite_tokens
      where invite_id = :'invite1') = 0);

-- Só o worker cunha.
begin;
select tests.impersonate('authenticated', :'uid_owner1');
select tests.check_raises('owner nao cunha no despacho',
  format($sql$select public.svc_mint_manager_invite_token(%L)$sql$, :'evt1'),
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select public.svc_mint_manager_invite_token((:'evt1')::uuid) as mint \gset
select tests.check('worker cunha o segredo no despacho',
    ((:'mint')::jsonb ->> 'ok') = 'true'
    and length((:'mint')::jsonb ->> 'token') = 64);
select public.svc_mark_notification_sent(
    (:'evt1')::uuid, 'fake-local', 'msg-1') as sent \gset
select tests.check('marcar enviado usa a transicao canonica',
    ((:'sent')::jsonb ->> 'ok') = 'true');
commit;

select ((:'mint')::jsonb ->> 'token') as tok \gset

select tests.check('apos o despacho persiste SOMENTE o hash',
    (select token_hash = public.m1_token_hash(:'tok')
       from public.site_manager_invite_tokens where invite_id = :'invite1'));
select tests.check('o token cru NAO aparece no outbox',
    (select count(*) from public.notification_events
      where template_data::text like '%' || :'tok' || '%') = 0);
select tests.check('o token cru NAO aparece na auditoria',
    (select count(*) from public.audit_logs
      where coalesce(new_state::text,'') || coalesce(previous_state::text,'')
            like '%' || :'tok' || '%') = 0);
select tests.check('evento fica sent com tentativa contada',
    (select status='sent' and attempt_count=1 and sent_at is not null
       from public.notification_events where id = :'evt1'));

-- O convite despachado continua utilizável pelo destinatário.
begin;
select tests.impersonate('authenticated', :'uid_g');
select public.accept_manager_invite(:'tok') as acc \gset
select tests.check('destinatario aceita o convite despachado',
    ((:'acc')::jsonb ->> 'ok') = 'true');
commit;

-- ---------------------------------------------------------------------------
-- Falha e reagendamento pelas transições canônicas
-- ---------------------------------------------------------------------------
insert into public.notification_events
    (channel, recipient_address, template_key, template_data, status, idempotency_key)
values ('email','falha@teste.local','partner_application_decided',
        '{"application_id":"x"}'::jsonb,'pending','teste-falha-r13')
returning id as evt2 \gset

begin;
select tests.impersonate('service_role', null);
-- o worker precisa marcar 'sending' antes de falhar (transição da baseline)
update public.notification_events set status='sending', attempt_count=1
 where id = :'evt2';
select public.svc_mark_notification_failed(
    (:'evt2')::uuid, 'smtp_timeout', 'tempo esgotado') as fail \gset
select tests.check('falha registrada pela transicao canonica',
    ((:'fail')::jsonb ->> 'ok') = 'true');
select public.svc_reschedule_notification((:'evt2')::uuid, interval '10 minutes') as resch \gset
select tests.check('reagendamento pela transicao canonica',
    ((:'resch')::jsonb ->> 'ok') = 'true');
commit;

select tests.check('reagendado preserva marcos de falha',
    (select status='scheduled' and first_failed_at is not null
        and last_failed_at is not null and error_code='smtp_timeout'
        and scheduled_for > now()
       from public.notification_events where id = :'evt2'));
select tests.check('mensagem de erro nao carrega segredo',
    (select coalesce(error_message,'') !~* '(token|secret|password)'
       from public.notification_events where id = :'evt2'));

select tests.finish('200_m2_email_outbox');
