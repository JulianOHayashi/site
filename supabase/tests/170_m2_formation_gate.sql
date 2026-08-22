-- ============================================================================
-- SUITE 170 — Gate de formação (R9), com CONCORRÊNCIA REAL via dblink.
-- Roda sobre a formação de seis nichos construída pela suíte 160.
-- ============================================================================

select tests.reset_results();
create extension if not exists dblink with schema extensions;

select user_id as uid_admin from public.site_admins limit 1 \gset
select id as uid_intruso from auth.users where email = 'intruso_m2@teste.local' \gset
select id as excl2 from public.commercial_exclusivities where sequence_number = 2 \gset
select o.company_id as comp1 from public.commercial_exclusivity_orders o
 where o.exclusivity_id = :'excl2' and o.niche_code='supermarket' \gset
select auth_user_id as uid_owner1 from public.site_company_members
 where company_id = :'comp1' and role='partner_owner' \gset

-- ---------------------------------------------------------------------------
-- SEM imagem de personalização o gate NEGA (requisito de lançamento R7)
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.commercial_formation_gate_report((:'excl2')::uuid) as rep0 \gset
select tests.check('seis nichos, quantidades e pagamentos ja conferem',
    ((:'rep0')::jsonb -> 'checks' ->> 'six_niches_contracted') = 'true'
    and ((:'rep0')::jsonb -> 'checks' ->> 'nominal_quantities_ok') = 'true'
    and ((:'rep0')::jsonb -> 'checks' ->> 'one_niche_per_cnpj') = 'true'
    and ((:'rep0')::jsonb -> 'checks' ->> 'bdflow_payments_confirmed') = 'true');
select tests.check('gate NEGA por falta de imagem de personalizacao',
    ((:'rep0')::jsonb ->> 'eligible') = 'false'
    and ((:'rep0')::jsonb -> 'checks' ->> 'customization_image_present') = 'false');
select public.admin_authorize_commercial_operation((:'excl2')::uuid) as aut0 \gset
select tests.check('autorizacao recusada com o gate incompleto',
    ((:'aut0')::jsonb ->> 'reason') = 'gate_not_satisfied'
    and ((:'aut0')::jsonb ->> 'failed_checks') like '%customization_image_present%');
commit;

select tests.check('exclusividade permanece nao autorizada',
    (select operation_authorized_at is null
       from public.commercial_exclusivities where id = :'excl2'));

-- ---------------------------------------------------------------------------
-- Registra a imagem em cada um dos seis pedidos (fluxo real do R7)
-- ---------------------------------------------------------------------------
do $$
declare
  v_o record; v_path text; v_owner uuid;
begin
  for v_o in
    select o.id, o.company_id from public.commercial_exclusivity_orders o
     where o.exclusivity_id = (select id from public.commercial_exclusivities
                                where sequence_number = 2)
       and o.status = 'signed'
  loop
    select m.auth_user_id into v_owner from public.site_company_members m
     where m.company_id = v_o.company_id and m.role='partner_owner' and m.status='active';

    perform set_config('request.jwt.claims',
        json_build_object('role','authenticated','sub',v_owner)::text, true);
    v_path := (public.request_customization_image_path(v_o.id) ->> 'storage_path');

    -- o objeto no Storage é o que o navegador teria enviado
    insert into storage.objects (bucket_id, name, owner, metadata)
    values ('partner-customization-images', v_path, v_owner,
            jsonb_build_object('size', 102400, 'mimetype', 'image/png'));

    perform public.register_customization_image(v_o.id, v_path);
  end loop;
  perform set_config('request.jwt.claims', null, true);
end $$;

select tests.check('os seis pedidos passam a ter imagem corrente',
    (select count(*) from public.commercial_exclusivity_orders o
      where o.exclusivity_id = :'excl2' and o.status='signed'
        and public.order_has_customization_image(o.id)) = 6);

-- ---------------------------------------------------------------------------
-- Autorização do relatório
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_intruso');
select public.commercial_formation_gate_report((:'excl2')::uuid) as rep_neg \gset
select tests.check('usuario sem vinculo nao le o relatorio do gate',
    ((:'rep_neg')::jsonb ->> 'reason') = 'not_authorized');
select tests.check_raises('usuario sem vinculo nao autoriza operacao',
  format($sql$select public.admin_authorize_commercial_operation(%L)$sql$, :'excl2'),
  'not_authorized');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_owner1');
select tests.check('parceiro contratante le o relatorio',
    (public.commercial_formation_gate_report((:'excl2')::uuid) ->> 'ok') = 'true');
select tests.check_raises('parceiro NAO autoriza a operacao (privilegio BDFlow)',
  format($sql$select public.admin_authorize_commercial_operation(%L)$sql$, :'excl2'),
  'not_authorized');
rollback;

-- ---------------------------------------------------------------------------
-- Pré-requisito de validador: sem unidade ativa o gate volta a negar
-- ---------------------------------------------------------------------------
select id as unit_alvo from public.site_partner_units
 where company_id = :'comp1' limit 1 \gset
update public.site_partner_units set status='suspended' where id = :'unit_alvo';

begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.commercial_formation_gate_report((:'excl2')::uuid) as rep1 \gset
select tests.check('parceiro sem unidade ativa reprova o gate',
    ((:'rep1')::jsonb ->> 'eligible') = 'false'
    and ((:'rep1')::jsonb -> 'checks' ->> 'active_unit_per_partner') = 'false'
    and ((:'rep1')::jsonb -> 'checks' ->> 'active_validator_per_partner') = 'false');
commit;

update public.site_partner_units set status='active' where id = :'unit_alvo';

-- ---------------------------------------------------------------------------
-- Gate completo
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.commercial_formation_gate_report((:'excl2')::uuid) as rep2 \gset
select tests.check('gate completo fica elegivel',
    ((:'rep2')::jsonb ->> 'eligible') = 'true');
select tests.check('as treze verificacoes passam',
    (select count(*) from jsonb_each((:'rep2')::jsonb -> 'checks') e
      where e.value = 'true'::jsonb) = 13);
commit;

-- ---------------------------------------------------------------------------
-- CONCORRÊNCIA REAL: duas sessões autorizam ao mesmo tempo
-- ---------------------------------------------------------------------------
select extensions.dblink_connect('ga', 'dbname=' || current_database()) as ca \gset
select extensions.dblink_connect('gb', 'dbname=' || current_database()) as cb \gset
select extensions.dblink_exec('ga','begin') as a1 \gset
select extensions.dblink_exec('gb','begin') as b1 \gset
select extensions.dblink_exec('ga', format(
  $q$set "request.jwt.claims" = '{"role":"authenticated","sub":"%s"}'$q$, :'uid_admin')) as a2 \gset
select extensions.dblink_exec('gb', format(
  $q$set "request.jwt.claims" = '{"role":"authenticated","sub":"%s"}'$q$, :'uid_admin')) as b2 \gset
select extensions.dblink_exec('ga','set role authenticated') as a3 \gset
select extensions.dblink_exec('gb','set role authenticated') as b3 \gset

select res from extensions.dblink('ga', format(
  $q$select public.admin_authorize_commercial_operation('%s')::text$q$, :'excl2'))
  as t(res text) \gset res_a_
select extensions.dblink_send_query('gb', format(
  $q$select public.admin_authorize_commercial_operation('%s')::text$q$, :'excl2')) as env \gset
select pg_sleep(0.5);
select tests.check('sessao B bloqueia na trava enquanto A nao confirma',
    extensions.dblink_is_busy('gb') = 1);

select extensions.dblink_exec('ga','commit') as a4 \gset
select res from extensions.dblink_get_result('gb') as t(res text) \gset res_b_
select count(*) as drena from extensions.dblink_get_result('gb') as t(res text) \gset
select extensions.dblink_exec('gb','commit') as b4 \gset
select extensions.dblink_disconnect('ga') as da \gset
select extensions.dblink_disconnect('gb') as db \gset

select tests.check('primeira sessao autoriza de fato',
    (:'res_a_res')::jsonb ->> 'ok' = 'true'
    and (:'res_a_res')::jsonb ->> 'already' = 'false');
select tests.check('segunda sessao concorrente e idempotente',
    (:'res_b_res')::jsonb ->> 'already' = 'true');
select tests.check('autorizada exatamente uma vez',
    (select count(*) from public.audit_logs
      where action = 'commercial_exclusivity.operation_authorized'
        and entity_id = :'excl2') = 1);
select tests.check('estado final operation_authorized com carimbos',
    (select status='operation_authorized' and operation_authorized_at is not null
        and formed_at is not null
       from public.commercial_exclusivities where id = :'excl2'));

-- Nova autorização após o fato continua idempotente.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_authorize_commercial_operation((:'excl2')::uuid) as aut_rep \gset
select tests.check('autorizacao repetida e idempotente',
    ((:'aut_rep')::jsonb ->> 'already') = 'true');
select tests.check('gate ja autorizado reprova not_already_authorized',
    (public.commercial_formation_gate_report((:'excl2')::uuid)
       -> 'checks' ->> 'not_already_authorized') = 'false');
rollback;

-- ---------------------------------------------------------------------------
-- Resumo comercial: owner vê valores, manager não
-- ---------------------------------------------------------------------------
-- Convida e aceita um manager para provar a RLS financeira do resumo.
-- (O manager da suíte 120 foi revogado ao final dela.)
select tests.mk_user('gestor_gate') as uid_mgr \gset
do $$
declare v_owner uuid; v_comp uuid; v_inv jsonb; v_evt uuid; v_tok text; v_mgr uuid;
begin
  select o.company_id into v_comp from public.commercial_exclusivity_orders o
   where o.exclusivity_id = (select id from public.commercial_exclusivities
                              where sequence_number = 2)
     and o.niche_code = 'supermarket';
  select m.auth_user_id into v_owner from public.site_company_members m
   where m.company_id = v_comp and m.role='partner_owner';
  select id into v_mgr from auth.users where email = 'gestor_gate@teste.local';

  perform set_config('request.jwt.claims',
      json_build_object('role','authenticated','sub',v_owner)::text, true);
  v_inv := public.owner_create_manager_invite(
      v_comp, 'gestor_gate@teste.local', 'Gestor do Gate',
      (select id from public.site_partner_units where company_id = v_comp limit 1));

  select id into v_evt from public.notification_events
   where template_data->>'invite_id' = (v_inv->>'invite_id');

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
  v_tok := (public.svc_mint_manager_invite_token(v_evt) ->> 'token');
  reset role;

  perform set_config('request.jwt.claims',
      json_build_object('role','authenticated','sub',v_mgr)::text, true);
  perform public.accept_manager_invite(v_tok);
  perform set_config('request.jwt.claims', null, true);
  perform set_config('bdflow.comp_com_mgr', v_comp::text, false);
end $$;

select current_setting('bdflow.comp_com_mgr') as comp_com_mgr \gset

begin;
select tests.impersonate('authenticated', :'uid_owner1');
select public.get_my_company_commercial_summary((:'comp1')::uuid) as sum1 \gset
select tests.check('owner ve resumo com valores e estado da imagem',
    jsonb_array_length((:'sum1')::jsonb -> 'commercial') = 1
    and ((:'sum1')::jsonb -> 'commercial' -> 0 ->> 'bdflow_due_cents')::bigint = 889675
    and ((:'sum1')::jsonb -> 'commercial' -> 0 ->> 'has_customization_image') = 'true');
select tests.check('resumo traz unidades e prontidao',
    jsonb_array_length((:'sum1')::jsonb -> 'units') >= 1
    and ((:'sum1')::jsonb -> 'readiness' ->> 'active_validator') = 'true');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_mgr');
select public.get_my_company_commercial_summary((:'comp_com_mgr')::uuid) as sum2 \gset
select tests.check('MANAGER ve empresa e unidades mas NAO ve financeiro',
    ((:'sum2')::jsonb -> 'commercial') = 'null'::jsonb
    and jsonb_array_length((:'sum2')::jsonb -> 'units') >= 1);
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select public.get_my_company_commercial_summary((:'comp1')::uuid) as sum3 \gset
select tests.check('terceiro nao le resumo comercial',
    ((:'sum3')::jsonb ->> 'reason') = 'not_authorized');
rollback;

select tests.finish('170_m2_formation_gate');
