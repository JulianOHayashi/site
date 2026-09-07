-- ============================================================================
-- SUITE 000 — Invariantes CANÔNICAS do M1 (rede de proteção)
--
-- Esta suíte não testa nada novo: ela congela o que o M1 já garante, para que
-- qualquer bloco de reconciliação que as quebre seja detectado.
--
-- STATUS: TESTE_AUXILIAR_NAO_GATE (PG16). O gate final é Supabase PG17 real.
-- ============================================================================

select tests.reset_results();

-- ---------------------------------------------------------------------------
-- 1. Domínio canônico de candidatura existe e NÃO foi recriado
-- ---------------------------------------------------------------------------
select tests.check('partner_applications canônica existe',
    to_regclass('public.partner_applications') is not null);
select tests.check('tabelas satélites canônicas existem',
    to_regclass('public.partner_application_representatives') is not null
    and to_regclass('public.partner_application_documents') is not null
    and to_regclass('public.partner_application_tokens') is not null
    and to_regclass('public.partner_application_corrections') is not null);

-- Colunas do fluxo PRÉ-AUTH: a candidatura nasce sem conta.
select tests.check('candidatura é pré-auth (account_kind/account_user_id)',
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'partner_applications'
        and column_name in ('account_kind','account_user_id','account_linked_at',
                            'email_verified_at')) = 4);
select tests.check('análises separadas de empresa e autoridade',
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'partner_applications'
        and column_name in ('company_review_status','authority_review_status')) = 2);
select tests.check('estados canônicos incluem changes_requested e withdrawn',
    (select pg_get_constraintdef(oid) from pg_constraint
      where conname = 'partner_applications_status_allowed')
      like '%changes_requested%withdrawn%');

-- ---------------------------------------------------------------------------
-- 2. Validação de dígito verificador (NÃO pode regredir para regex)
-- ---------------------------------------------------------------------------
select tests.check('m1_cnpj_valido e m1_cpf_valido existem',
    to_regprocedure('public.m1_cnpj_valido(text)') is not null
    and to_regprocedure('public.m1_cpf_valido(text)') is not null);
select tests.check('CNPJ com dígito verificador incorreto é rejeitado',
    public.m1_cnpj_valido('11222333000199') = false
    and public.m1_cnpj_valido('11222333000181') = true);
select tests.check('CPF com dígito verificador incorreto é rejeitado',
    public.m1_cpf_valido('52998224700') = false
    and public.m1_cpf_valido('52998224725') = true);
select tests.check('CHECK de CNPJ usa o validador, não regex de formato',
    (select count(*) from pg_constraint
      where conname like '%cnpj%'
        and pg_get_constraintdef(oid) like '%m1_cnpj_valido%') >= 1);

-- Prova de campo: insert direto com dígito inválido falha.
select tests.check_raises(
  'insert com CNPJ invalido falha no banco',
  $sql$insert into public.partner_applications
      (cnpj, legal_name, contact_email, city, uf)
      values ('11222333000199','X LTDA','x@y.z','Vitória','ES')$sql$,
  'cnpj');

-- ---------------------------------------------------------------------------
-- 3. Segredo de token nunca persistido em claro
-- ---------------------------------------------------------------------------
select tests.check('partner_application_tokens não tem coluna de segredo cru',
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'partner_application_tokens'
        and column_name in ('token','secret','raw_token','plain_token')) = 0);
select tests.check('token é guardado por hash',
    (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'partner_application_tokens'
        and column_name like '%hash%') >= 1);

-- ---------------------------------------------------------------------------
-- 4. Storage privado do M1
-- ---------------------------------------------------------------------------
select tests.check('bucket de documentos é PRIVADO',
    (select public = false from storage.buckets
      where id = 'partner-application-docs'));
select tests.check('bucket tem limite de tamanho e MIME permitidos',
    (select file_size_limit is not null and allowed_mime_types is not null
       from storage.buckets where id = 'partner-application-docs'));
select tests.check('anon não tem policy alguma no bucket',
    (select count(*) from pg_policies
      where schemaname = 'storage' and tablename = 'objects'
        and 'anon' = any(roles)) = 0);
-- M1C3: o applicant não apaga objeto (corrida de exclusão fechada).
select tests.check('policy de DELETE do titular foi removida (M1C3)',
    (select count(*) from pg_policies
      where schemaname = 'storage' and tablename = 'objects'
        and policyname = 'm1_partner_docs_titular_delete') = 0);

-- ---------------------------------------------------------------------------
-- 5. Aceite jurídico explícito e vinculado ao documento
-- ---------------------------------------------------------------------------
select tests.check('record_bound_legal_acceptance existe',
    to_regprocedure('public.record_bound_legal_acceptance(text,uuid,jsonb)') is not null);
select tests.check('aceite vinculado NÃO é executável por PUBLIC nem service_role',
    has_function_privilege('public',
        'public.record_bound_legal_acceptance(text,uuid,jsonb)', 'EXECUTE') = false
    and has_function_privilege('service_role',
        'public.record_bound_legal_acceptance(text,uuid,jsonb)', 'EXECUTE') = false);
select tests.check('legal_acceptances continua protegida contra DELETE',
    (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
      where c.relname = 'legal_acceptances' and not t.tgisinternal) >= 1);

-- ---------------------------------------------------------------------------
-- 6. Operações de serviço do M1 (semântica de notificação canônica)
-- ---------------------------------------------------------------------------
select tests.check('svc_* canônicos do M1 existem',
    to_regprocedure('public.svc_mint_partner_application_token(uuid)') is not null
    and to_regprocedure('public.svc_mark_notification_sent(uuid,text,text)') is not null
    and to_regprocedure('public.svc_mark_notification_failed(uuid,text,text)') is not null
    and to_regprocedure('public.svc_reschedule_notification(uuid,interval)') is not null);
select tests.check('svc_mint não é executável por authenticated nem anon',
    has_function_privilege('authenticated',
        'public.svc_mint_partner_application_token(uuid)', 'EXECUTE') = false
    and has_function_privilege('anon',
        'public.svc_mint_partner_application_token(uuid)', 'EXECUTE') = false);

-- ---------------------------------------------------------------------------
-- 7. RPC legada de owner segue desativada para papéis de API
-- ---------------------------------------------------------------------------
select tests.check('create_my_partner_owner_registration sem grant de API',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'create_my_partner_owner_registration'
        and (has_function_privilege('anon', p.oid, 'EXECUTE')
             or has_function_privilege('authenticated', p.oid, 'EXECUTE'))) = 0);
select tests.check('site_partner_members NÃO existe no schema canônico',
    to_regclass('public.site_partner_members') is null);

-- A RPC legada foi APOSENTADA (migration 20260907190000), nao removida: a
-- assinatura de sete argumentos continua sendo conferida pelos pre-flights
-- historicos do projeto.
select tests.check('assinatura legada de sete argumentos preservada',
    to_regprocedure(
      'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
    is not null);
-- O defeito que o lint hospedado apontou: o corpo referenciava uma tabela
-- inexistente. Nao pode voltar por descuido.
select tests.check('corpo da RPC legada nao referencia mais site_partner_members',
    (select p.prosrc !~* 'site_partner_members|site_monthly_partners|auth\.uid'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'create_my_partner_owner_registration'));
select tests.check('RPC legada continua SECURITY DEFINER com search_path fixo',
    (select p.prosecdef
        and coalesce(array_to_string(p.proconfig,','),'') = 'search_path=pg_catalog'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'create_my_partner_owner_registration'));
-- Falha FECHADA em tempo de execucao, pelo unico caminho administrativo que
-- ainda pode executa-la. Nao devolve sucesso nem inventa identificador.
begin;
select tests.impersonate('service_role', null);
select tests.check_raises('RPC legada falha fechada ao ser invocada',
    $sql$select public.create_my_partner_owner_registration(
      'Nome','52998224725','27999990000','Razao LTDA','Fantasia',
      '11222333000181','2733330000')$sql$,
    'RPC_LEGADA_DESATIVADA');
rollback;

-- ---------------------------------------------------------------------------
-- 8. RLS ligada em todo o domínio canônico de candidatura
-- ---------------------------------------------------------------------------
select tests.check('RLS ligada nas tabelas de candidatura',
    (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('partner_applications','partner_application_representatives',
                          'partner_application_documents','partner_application_tokens',
                          'partner_application_corrections')
        and not c.relrowsecurity) = 0);

select tests.finish('000_m1_canonical_invariants');
