-- ============================================================================
-- SUITE 100 — Promoção durável M2 sobre o domínio canônico do M1 (R2)
--
-- O fixture percorre o fluxo REAL do M1 (pré-auth -> e-mail -> conta
-- provisória -> análises separadas -> decisão), nunca inserindo direto.
-- STATUS: TESTE_AUXILIAR_NAO_GATE (PG16).
-- ============================================================================

select tests.reset_results();

select tests.mk_user('admin_m2') as uid_admin \gset
select tests.mk_user('titular_m2') as uid_titular \gset
select tests.mk_user('intruso_m2') as uid_intruso \gset
insert into public.site_admins (user_id) values (:'uid_admin');

-- Documentos jurídicos vigentes exigidos pelo fluxo canônico.
insert into public.legal_documents
    (doc_type, version, title, content, content_hash, status,
     effective_from, published_at, published_by)
select t, 'v1-teste', 'Doc ' || t, 'CONTEUDO DE TESTE (nao juridico) ' || t,
       encode(extensions.digest('teste-' || t, 'sha256'), 'hex'),
       'published', now() - interval '1 hour', now() - interval '1 hour', :'uid_admin'
  from unnest(array['truthfulness_declaration','document_analysis_authorization',
                    'privacy_notice','provisional_account_terms']) as t;

-- ---------------------------------------------------------------------------
-- Fluxo canônico: solicitação PRÉ-AUTH (sem sessão)
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('anon', null);
select public.create_partner_application(jsonb_build_object(
    'cnpj', '11222333000181',
    'legal_name', 'Parceiro Canonico LTDA',
    'trade_name', 'Parceiro Canonico',
    'contact_email', 'titular_m2@teste.local',
    'contact_phone', '2799999000',
    'city', 'Vitória', 'uf', 'ES',
    'representative_full_name', 'Ana Representante',
    'representative_cpf', '52998224725',
    'representative_email', 'ana@parceiro.local',
    'acceptances', (select jsonb_agg(jsonb_build_object(
                        'legal_document_id', x ->> 'legal_document_id'))
                      from jsonb_array_elements(
                             public.get_partner_application_terms() -> 'documents') x)
)) as criada \gset
select tests.check('solicitacao canonica criada SEM conta Auth',
    ((:'criada')::jsonb ->> 'ok') = 'true'
    and ((:'criada')::jsonb ->> 'status') = 'pending_email_verification');
commit;

select ((:'criada')::jsonb ->> 'application_id') as app1 \gset

-- Promoção antes de tudo: recusada por estado.
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_promote_partner_application((:'app1')::uuid) as p0 \gset
select tests.check('candidatura nao aprovada NAO promove',
    ((:'p0')::jsonb ->> 'ok') = 'false'
    and ((:'p0')::jsonb ->> 'reason') = 'not_approved');
rollback;

-- ---------------------------------------------------------------------------
-- Confirma e-mail e vincula conta provisória pelo caminho canônico
-- ---------------------------------------------------------------------------
do $$
declare v_tok text; v_app uuid;
begin
  select id into v_app from public.partner_applications
   where cnpj = '11222333000181';
  v_tok := public.m1_emitir_token(v_app, 'email_verification',
                                  'titular_m2@teste.local', interval '24 hours');
  perform set_config('bdflow.tok_email', v_tok, false);
end $$;

begin;
select tests.impersonate('anon', null);
select public.confirm_partner_application_email(
    current_setting('bdflow.tok_email')) as conf \gset
select tests.check('e-mail confirmado pelo caminho canonico',
    ((:'conf')::jsonb ->> 'ok') = 'true');
commit;

do $$
declare v_tok text; v_app uuid;
begin
  select id into v_app from public.partner_applications
   where cnpj = '11222333000181';
  v_tok := public.m1_emitir_token(v_app, 'account_claim',
                                  'titular_m2@teste.local', interval '24 hours');
  perform set_config('bdflow.tok_claim', v_tok, false);
end $$;

begin;
select tests.impersonate('authenticated', :'uid_titular');
-- aceite EXPLÍCITO dos termos de conta provisória (semântica canônica)
select public.record_bound_legal_acceptance(
    x ->> 'doc_type', (x ->> 'legal_document_id')::uuid, '{}'::jsonb)
  from jsonb_array_elements(
         public.get_provisional_account_terms() -> 'documents') x;
select public.claim_partner_application_account(
    current_setting('bdflow.tok_claim')) as claim \gset
select tests.check('conta provisoria vinculada pelo caminho canonico',
    ((:'claim')::jsonb ->> 'ok') = 'true');
commit;

select tests.check('candidatura ficou provisional com account_user_id',
    (select account_kind = 'provisional' and account_user_id = (:'uid_titular')::uuid
       from public.partner_applications where id = :'app1'));

-- ---------------------------------------------------------------------------
-- Análises SEPARADAS: empresa e autoridade
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_review_partner_company((:'app1')::uuid, 'approved', null);
-- só empresa aprovada: decisão final ainda é recusada pelo M1
select public.admin_decide_partner_application((:'app1')::uuid, 'approved', null) as d1 \gset
select tests.check('decisao exige as DUAS analises (contrato M1 preservado)',
    ((:'d1')::jsonb ->> 'ok') = 'false'
    and ((:'d1')::jsonb ->> 'reason') = 'reviews_incomplete');
select public.admin_review_partner_authority((:'app1')::uuid, 'approved', null);
select public.admin_decide_partner_application((:'app1')::uuid, 'approved', null) as d2 \gset
select tests.check('com as duas analises aprovadas a decisao passa',
    ((:'d2')::jsonb ->> 'ok') = 'true');
commit;

-- Aprovação sozinha NÃO abre o Portal: ainda não há promoção.
select tests.check('aprovacao nao cria empresa duravel por si so',
    (select count(*) from public.site_partner_companies) = 0);

-- ---------------------------------------------------------------------------
-- Autorização da promoção
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check_raises(
  'nao-admin nao promove',
  format($sql$select public.admin_promote_partner_application(%L)$sql$, :'app1'),
  'not_authorized');
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises(
  'anon nao promove',
  format($sql$select public.admin_promote_partner_application(%L)$sql$, :'app1'),
  'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select tests.check_raises(
  'service_role nao promove (privilegio administrativo humano)',
  format($sql$select public.admin_promote_partner_application(%L)$sql$, :'app1'),
  'permission denied');
rollback;

-- ---------------------------------------------------------------------------
-- Promoção efetiva + idempotência
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_promote_partner_application((:'app1')::uuid) as p1 \gset
select tests.check('promocao cria empresa e owner duraveis',
    ((:'p1')::jsonb ->> 'ok') = 'true'
    and ((:'p1')::jsonb ->> 'already') = 'false'
    and ((:'p1')::jsonb ->> 'company_id') is not null
    and ((:'p1')::jsonb ->> 'owner_member_id') is not null);
select public.admin_promote_partner_application((:'app1')::uuid) as p2 \gset
select tests.check('promocao repetida e idempotente',
    ((:'p2')::jsonb ->> 'already') = 'true'
    and ((:'p2')::jsonb ->> 'company_id') = ((:'p1')::jsonb ->> 'company_id'));
commit;

select ((:'p1')::jsonb ->> 'company_id') as company1 \gset

select tests.check('exatamente uma empresa e um owner',
    (select count(*) from public.site_partner_companies) = 1
    and (select count(*) from public.site_company_members
          where role = 'partner_owner') = 1);
select tests.check('owner e a conta provisoria canonica',
    (select auth_user_id = (:'uid_titular')::uuid
       from public.site_company_members where role = 'partner_owner'));
select tests.check('owner herda o representante CORRENTE aprovado',
    (select m.full_name = 'Ana Representante' and m.cpf = '52998224725'
        and m.source = 'application_promotion'
        and m.source_representative_id is not null
       from public.site_company_members m where m.role = 'partner_owner'));
select tests.check('empresa aponta para a candidatura canonica de origem',
    (select source_application_id = (:'app1')::uuid
       from public.site_partner_companies));
select tests.check('identidades de ponte sao UUID e nao CNPJ/CPF',
    (select c.partner_network_bridge_id::text <> c.cnpj
       from public.site_partner_companies c)
    and (select m.validator_bridge_id::text <> coalesce(m.cpf,'')
           from public.site_company_members m where m.role = 'partner_owner'));

-- A promoção NÃO tocou a candidatura canônica nem criou aceites.
select tests.check('promocao NAO alterou partner_applications',
    (select status = 'approved' and account_kind = 'provisional'
       from public.partner_applications where id = :'app1'));
select tests.check('promocao NAO criou aceite juridico algum',
    (select count(*) from public.legal_acceptances
      where evidence::text like '%admin_promote%') = 0);
select tests.check('promocao foi auditada pelo helper canonico',
    (select count(*) from public.audit_logs
      where action = 'partner_application.promoted'
        and entity_id = :'app1') = 1);

-- ---------------------------------------------------------------------------
-- RLS do domínio durável
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_titular');
select tests.check('owner ve a propria empresa e o proprio vinculo',
    (select count(*) from public.site_partner_companies) = 1
    and (select count(*) from public.site_company_members) = 1);
select tests.check_raises(
  'owner nao escreve direto na empresa',
  $sql$update public.site_partner_companies set status = 'suspended'$sql$,
  'permission denied');
rollback;

begin;
select tests.impersonate('authenticated', :'uid_intruso');
select tests.check('terceiro nao ve empresa nem vinculo alheios',
    (select count(*) from public.site_partner_companies) = 0
    and (select count(*) from public.site_company_members) = 0);
rollback;

begin;
select tests.impersonate('anon', null);
select tests.check_raises(
  'anon nao le empresa duravel',
  'select count(*) from public.site_partner_companies',
  'permission denied');
rollback;

-- ---------------------------------------------------------------------------
-- CONCORRÊNCIA REAL: duas sessões promovem ao mesmo tempo (dblink)
-- ---------------------------------------------------------------------------
create extension if not exists dblink with schema extensions;

-- Segunda candidatura completa, pronta para promover.
do $$
declare
  v_app uuid; v_tok text; v_admin uuid; v_user uuid;
begin
  select user_id into v_admin from public.site_admins limit 1;
  select id into v_user from auth.users where email = 'titular2_m2@teste.local';
  if v_user is null then
    v_user := gen_random_uuid();
    insert into auth.users (id, email) values (v_user, 'titular2_m2@teste.local');
  end if;

  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform public.create_partner_application(jsonb_build_object(
      'cnpj', '19131243000197',
      'legal_name', 'Segundo Parceiro LTDA',
      'contact_email', 'titular2_m2@teste.local',
      'city', 'Serra', 'uf', 'ES',
      'representative_full_name', 'Beto Representante',
      'representative_cpf', '11144477735',
      'representative_email', 'beto@parceiro.local',
      'acceptances', (select jsonb_agg(jsonb_build_object(
                          'legal_document_id', x ->> 'legal_document_id'))
                        from jsonb_array_elements(
                               public.get_partner_application_terms() -> 'documents') x)));
  select id into v_app from public.partner_applications where cnpj = '19131243000197';

  v_tok := public.m1_emitir_token(v_app, 'email_verification', 'titular2_m2@teste.local', interval '24 hours');
  perform public.confirm_partner_application_email(v_tok);

  v_tok := public.m1_emitir_token(v_app, 'account_claim', 'titular2_m2@teste.local', interval '24 hours');
  perform set_config('request.jwt.claims',
      json_build_object('role','authenticated','sub',v_user)::text, true);
  perform public.record_bound_legal_acceptance(
      x ->> 'doc_type', (x ->> 'legal_document_id')::uuid, '{}'::jsonb)
     from jsonb_array_elements(
            public.get_provisional_account_terms() -> 'documents') x;
  perform public.claim_partner_application_account(v_tok);

  perform set_config('request.jwt.claims',
      json_build_object('role','authenticated','sub',v_admin)::text, true);
  perform public.admin_review_partner_company(v_app, 'approved', null);
  perform public.admin_review_partner_authority(v_app, 'approved', null);
  perform public.admin_decide_partner_application(v_app, 'approved', null);
  perform set_config('request.jwt.claims', null, true);
  perform set_config('bdflow.app2', v_app::text, false);
end $$;

select current_setting('bdflow.app2') as app2 \gset

select extensions.dblink_connect('sa', 'dbname=' || current_database()) as ca \gset
select extensions.dblink_connect('sb', 'dbname=' || current_database()) as cb \gset
select extensions.dblink_exec('sa', 'begin') as a1 \gset
select extensions.dblink_exec('sb', 'begin') as b1 \gset
select extensions.dblink_exec('sa', format(
    $q$set "request.jwt.claims" = '{"role":"authenticated","sub":"%s"}'$q$, :'uid_admin')) as a2 \gset
select extensions.dblink_exec('sb', format(
    $q$set "request.jwt.claims" = '{"role":"authenticated","sub":"%s"}'$q$, :'uid_admin')) as b2 \gset
select extensions.dblink_exec('sa', 'set role authenticated') as a3 \gset
select extensions.dblink_exec('sb', 'set role authenticated') as b3 \gset

-- A promove e SEGURA a trava.
select res from extensions.dblink('sa', format(
    $q$select public.admin_promote_partner_application('%s')::text$q$, :'app2'))
    as t(res text) \gset res_a_
-- B tenta ao mesmo tempo: bloqueia na trava de linha.
select extensions.dblink_send_query('sb', format(
    $q$select public.admin_promote_partner_application('%s')::text$q$, :'app2')) as env \gset
select pg_sleep(0.5);
select tests.check('sessao B bloqueia na trava enquanto A nao confirma',
    extensions.dblink_is_busy('sb') = 1);

select extensions.dblink_exec('sa', 'commit') as a4 \gset
select res from extensions.dblink_get_result('sb') as t(res text) \gset res_b_
select count(*) as drena from extensions.dblink_get_result('sb') as t(res text) \gset
select extensions.dblink_exec('sb', 'commit') as b4 \gset
select extensions.dblink_disconnect('sa') as da \gset
select extensions.dblink_disconnect('sb') as db \gset

select tests.check('primeira sessao promove de fato',
    (:'res_a_res')::jsonb ->> 'ok' = 'true'
    and (:'res_a_res')::jsonb ->> 'already' = 'false');
select tests.check('segunda sessao concorrente e idempotente',
    (:'res_b_res')::jsonb ->> 'ok' = 'true'
    and (:'res_b_res')::jsonb ->> 'already' = 'true'
    and (:'res_b_res')::jsonb ->> 'company_id'
        = (:'res_a_res')::jsonb ->> 'company_id');
select tests.check('promocao concorrente criou UMA empresa e UM owner',
    (select count(*) from public.site_partner_companies
      where source_application_id = (:'app2')::uuid) = 1
    and (select count(*) from public.site_company_members m
          join public.site_partner_companies c on c.id = m.company_id
         where c.source_application_id = (:'app2')::uuid
           and m.role = 'partner_owner') = 1);
select tests.check('auditoria de promocao registrada uma unica vez',
    (select count(*) from public.audit_logs
      where action = 'partner_application.promoted' and entity_id = :'app2') = 1);

select tests.finish('100_m2_durable_promotion');
