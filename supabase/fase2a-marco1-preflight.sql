-- ============================================================================
-- BDFlow Site — FASE 2A · MARCO 1 · PREFLIGHT (SOMENTE LEITURA) — V11
-- ----------------------------------------------------------------------------
-- Base autoritativa: commit cba451e da origin/main.
--
-- OBJETIVO
--   Verificar, ANTES de qualquer aplicação, se o banco está apto a receber
--   supabase/fase2a-marco1-foundation.sql (que é FAIL-CLOSED).
--
-- GARANTIAS
--   • NÃO insere, NÃO atualiza, NÃO exclui, NÃO cria, NÃO altera, NÃO corrige.
--   • Todo o diagnóstico roda dentro de um único bloco DO, com SQL dinâmico
--     executado somente quando o objeto consultado existir.
--   • Seção B contém apenas EXEMPLOS INTEGRALMENTE COMENTADOS.
--
-- POLÍTICA FAIL-CLOSED
--   Qualquer objeto proposto já existente é BLOQUEIO. Artefatos das propostas
--   antigas baseadas em VIEWS (my_notifications, my_legal_acceptances,
--   legal_documents_public) também são BLOQUEIO — não podem coexistir com esta proposta
--   e NÃO são removidos automaticamente.
--
-- SAÍDA
--   PREFLIGHT_FASE2A_MARCO1_LIMPO  ou  PREFLIGHT_FASE2A_MARCO1_BLOQUEADO
--   Guarde o hash da RPC antiga impresso no item [12].
-- ============================================================================

do $preflight$
declare
  v_bloqueios  text[] := array[]::text[];
  v_avisos     text[] := array[]::text[];
  v_nome       text;
  v_tab        text;
  v_sig        text;
  v_i          int;
  v_rec        record;
  v_tem_tabela boolean := false;
  v_tem_coluna boolean := false;
  v_tipo       text;
  v_nullable   text;
  v_grupos     bigint := 0;
  v_linhas     bigint := 0;
  v_sem_auth   bigint := 0;
  v_total      bigint := 0;
  v_orfaos     bigint := 0;
  v_oid        oid;
  v_txt        text;
  v_cfg        text;
  v_bool       boolean;
  v_seg        text;
  v_hash       text;
  v_lang       text;
  v_vol        text;
  v_src        text;
  v_requer_hardening boolean := false;
  v_is_admin_autoritativa_ok boolean := false;
  v_is_admin_sem_search_path boolean := false;
  v_admin_div int := 0;
  -- [13] Papeis INTERNOS da plataforma Supabase (allowlist EXATA e restrita)
  v_supabase_read_roles text[] := array['supabase_etl_admin','supabase_read_only_user'];
  v_app_roles           text[] := array['anon','authenticated','service_role'];
  v_repl_esperado boolean;
  v_perfil_ok     boolean;
  v_mem_read      boolean;
  v_mem_write     boolean;
  v_role_oid      oid;
begin
  raise notice '===========================================================';
  raise notice 'PREFLIGHT FASE 2A - MARCO 1 (V11, somente leitura)';
  raise notice 'Executado em: %', now();
  raise notice '===========================================================';

  -- ====================================================================
  -- [1] public.site_profiles precisa ser TABELA
  -- ====================================================================
  select (c.relkind = 'r') into v_tem_tabela
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'site_profiles';

  if coalesce(v_tem_tabela, false) then
    raise notice '[1] public.site_profiles ............ TABELA';
  else
    raise notice '[1] public.site_profiles ............ AUSENTE ou nao e tabela -> BLOQUEIO';
    v_bloqueios := v_bloqueios ||
      'public.site_profiles nao existe ou nao e uma tabela; o indice unico parcial nao pode ser criado.';
    v_tem_tabela := false;
  end if;

  -- ====================================================================
  -- [2][3] auth_user_id: existência, tipo uuid e NULLABLE
  -- ====================================================================
  if v_tem_tabela then
    select true, c.data_type, c.is_nullable
      into v_tem_coluna, v_tipo, v_nullable
      from information_schema.columns c
     where c.table_schema='public' and c.table_name='site_profiles' and c.column_name='auth_user_id';

    if coalesce(v_tem_coluna, false) then
      raise notice '[2] coluna auth_user_id ............. ENCONTRADA';
      raise notice '[3] tipo / nulidade ................. % / nullable=%', v_tipo, v_nullable;
      if v_tipo is distinct from 'uuid' then
        v_bloqueios := v_bloqueios || format('auth_user_id tem tipo "%s"; esperado uuid.', v_tipo);
      end if;
      if v_nullable = 'NO' then
        v_bloqueios := v_bloqueios ||
          'auth_user_id esta NOT NULL. O fluxo aprovado exige solicitacao ANTES da conta Auth.';
      end if;
    else
      v_tem_coluna := false;
      raise notice '[2] coluna auth_user_id ............. AUSENTE -> BLOQUEIO';
      v_bloqueios := v_bloqueios || 'Coluna public.site_profiles.auth_user_id nao existe.';
    end if;
  else
    raise notice '[2] coluna auth_user_id ............. NAO VERIFICADA';
    raise notice '[3] tipo / nulidade ................. NAO VERIFICADO';
  end if;

  -- ====================================================================
  -- [4] Duplicidades não nulas de auth_user_id
  -- ====================================================================
  if v_tem_coluna then
    execute $q$
      select count(*), coalesce(sum(qtd), 0)
        from (
          select auth_user_id, count(*) as qtd
            from public.site_profiles
           where auth_user_id is not null
           group by auth_user_id
          having count(*) > 1
        ) d
    $q$ into v_grupos, v_linhas;

    if coalesce(v_grupos, 0) = 0 then
      raise notice '[4] duplicidades de auth_user_id .... NENHUMA';
    else
      raise notice '[4] duplicidades de auth_user_id .... % grupo(s), % linha(s) -> BLOQUEIO',
        v_grupos, v_linhas;
      v_bloqueios := v_bloqueios || format(
        'Existem %s auth_user_id duplicados (%s linhas). A migration NAO corrige, NAO mescla e NAO escolhe vencedor.',
        v_grupos, v_linhas);
      raise notice '    amostra (ate 10 grupos):';
      for v_rec in
        execute $q$
          select auth_user_id::text as chave, count(*) as qtd
            from public.site_profiles
           where auth_user_id is not null
           group by auth_user_id having count(*) > 1
           order by count(*) desc limit 10
        $q$
      loop
        raise notice '      auth_user_id=% -> % perfis', v_rec.chave, v_rec.qtd;
      end loop;
    end if;

    execute $q$
      select count(*) filter (where auth_user_id is null), count(*) from public.site_profiles
    $q$ into v_sem_auth, v_total;
    raise notice '[4b] perfis sem auth_user_id ........ % de % (permanece permitido)', v_sem_auth, v_total;

    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='auth' and c.relname='users'
    ) then
      begin
        execute $q$
          select count(*) from public.site_profiles p
           where p.auth_user_id is not null
             and not exists (select 1 from auth.users u where u.id = p.auth_user_id)
        $q$ into v_orfaos;
        if coalesce(v_orfaos, 0) = 0 then
          raise notice '[4c] auth_user_id orfaos ............ NENHUM';
        else
          raise notice '[4c] auth_user_id orfaos ............ %', v_orfaos;
          v_avisos := v_avisos || format('%s perfil(is) referenciam auth.users inexistente.', v_orfaos);
        end if;
      exception when insufficient_privilege then
        v_avisos := v_avisos || 'Sem permissao para ler auth.users; verificar orfaos manualmente.';
      end;
    end if;
  else
    raise notice '[4] duplicidades .................... NAO VERIFICADO (coluna ausente)';
  end if;

  -- ====================================================================
  -- [5] Índices existentes sobre auth_user_id
  -- ====================================================================
  raise notice '[5] indices que envolvem site_profiles.auth_user_id:';
  if v_tem_tabela then
    for v_rec in
      select i.relname as idx, ix.indisunique as uniq, pg_get_indexdef(ix.indexrelid) as def
        from pg_index ix
        join pg_class i on i.oid = ix.indexrelid
        join pg_class t on t.oid = ix.indrelid
        join pg_namespace n on n.oid = t.relnamespace
       where n.nspname='public' and t.relname='site_profiles'
         and pg_get_indexdef(ix.indexrelid) ilike '%auth_user_id%'
       order by i.relname
    loop
      raise notice '      - % (unique=%) :: %', v_rec.idx, v_rec.uniq, v_rec.def;
    end loop;
  else
    raise notice '      (nao verificado)';
  end if;

  -- ====================================================================
  -- [6] FAIL-CLOSED — tabelas propostas devem estar LIVRES
  -- ====================================================================
  raise notice '[6] tabelas propostas (devem estar livres):';
  raise notice '      OBS: esta proposta NAO cria views; dados pessoais so por RPC SECURITY DEFINER.';
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    select c.relkind::text into v_txt
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname=v_nome and c.relkind in ('r','v','m','p','f');
    if v_txt is not null then
      raise notice '      - public.% ... JA EXISTE (relkind=%) -> BLOQUEIO', v_nome, v_txt;
      v_bloqueios := v_bloqueios || format(
        'Objeto public.%s ja existe. A migration e FAIL-CLOSED: nao substitui, nao remove e nao adapta.', v_nome);
    else
      raise notice '      - public.% ... livre', v_nome;
    end if;
    v_txt := null;
  end loop;

  -- ====================================================================
  -- [6b] FAIL-CLOSED — ARTEFATOS ANTIGOS (propostas baseadas em views)
  -- ====================================================================
  raise notice '[6b] artefatos das propostas antigas (NAO podem existir):';
  foreach v_nome in array array[
    'my_notifications','my_legal_acceptances','legal_documents_public'
  ] loop
    select c.relkind::text into v_txt
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname=v_nome;
    if v_txt is not null then
      raise notice '      - public.% ... EXISTE (relkind=%) -> BLOQUEIO', v_nome, v_txt;
      v_bloqueios := v_bloqueios || format(
        'Artefato antigo public.%s existe (proposta baseada em VIEW). Nao coexiste com esta proposta e NAO sera removido automaticamente: exige analise manual.',
        v_nome);
    else
      raise notice '      - public.% ... ausente (ok)', v_nome;
    end if;
    v_txt := null;
  end loop;

  -- ====================================================================
  -- [7] FAIL-CLOSED — funções propostas, por ASSINATURA EXATA
  -- ====================================================================
  raise notice '[7] funcoes propostas (assinatura exata; devem estar livres):';
  foreach v_sig in array array[
    'public.fase2a_touch_updated_at()',
    'public.legal_documents_protect()',
    'public.legal_documents_check_overlap()',
    'public.legal_acceptances_protect()',
    'public.audit_logs_block_mutation()',
    'public.notification_events_protect()',
    'public.current_legal_document(text)',
    'public.get_current_legal_documents()',
    'public.legal_document_versions(text)',
    'public.get_my_legal_acceptances()',
    'public.get_my_notifications()',
    'public.record_legal_acceptance(text,jsonb)',
    'public.write_audit_log(text,text,text,uuid,text,jsonb,jsonb,text,uuid,text,jsonb,uuid)'
  ] loop
    if to_regprocedure(v_sig) is not null then
      raise notice '      - % ... JA EXISTE -> BLOQUEIO', v_sig;
      v_bloqueios := v_bloqueios || format(
        'Funcao %s ja existe. A migration usa CREATE FUNCTION (sem OR REPLACE).', v_sig);
    else
      raise notice '      - % ... livre', v_sig;
    end if;
  end loop;

  -- Colisão por NOME (qualquer sobrecarga) também bloqueia.
  foreach v_nome in array array[
    'fase2a_touch_updated_at','legal_documents_protect','legal_documents_check_overlap',
    'legal_acceptances_protect','audit_logs_block_mutation','notification_events_protect',
    'current_legal_document','get_current_legal_documents','legal_document_versions',
    'get_my_legal_acceptances','get_my_notifications','record_legal_acceptance','write_audit_log'
  ] loop
    for v_rec in
      select pg_get_function_identity_arguments(p.oid) as args
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname = v_nome
    loop
      v_bloqueios := v_bloqueios || format(
        'Ja existe public.%s(%s) — colisao de nome. Nao havera substituicao automatica.', v_nome, v_rec.args);
    end loop;
  end loop;

  -- ====================================================================
  -- [8] FAIL-CLOSED — índices, triggers e policies propostos
  -- ====================================================================
  raise notice '[8a] indices propostos (devem estar livres):';
  foreach v_nome in array array[
    'uq_legal_documents_vigente','idx_legal_documents_type_status',
    'uq_legal_acceptances_ativo','idx_legal_acceptances_subject',
    'idx_legal_acceptances_auth_user','idx_legal_acceptances_linked',
    'idx_legal_acceptances_doc',
    'idx_audit_logs_entity','idx_audit_logs_actor','idx_audit_logs_occurred',
    'idx_audit_logs_correlation','uq_notification_events_idempotency',
    'idx_notification_events_status','idx_notification_events_recip',
    'idx_notification_events_correl','uq_notification_events_retry_parent',
    'uq_site_profiles_auth_user_id'
  ] loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relname=v_nome and c.relkind='i'
    ) then
      raise notice '      - % ... JA EXISTE -> BLOQUEIO', v_nome;
      v_bloqueios := v_bloqueios || format('Indice %s ja existe.', v_nome);
    else
      raise notice '      - % ... livre', v_nome;
    end if;
  end loop;

  raise notice '[8b] triggers propostos:';
  foreach v_sig in array array[
    'trg_legal_documents_updated|legal_documents',
    'trg_legal_documents_protect|legal_documents',
    'trg_legal_documents_overlap|legal_documents',
    'trg_legal_acceptances_protect_upd|legal_acceptances',
    'trg_legal_acceptances_protect_del|legal_acceptances',
    'trg_audit_logs_no_update|audit_logs',
    'trg_audit_logs_no_delete|audit_logs',
    'trg_notification_events_updated|notification_events',
    'trg_notification_events_protect|notification_events'
  ] loop
    v_nome := split_part(v_sig, '|', 1);
    v_tab  := split_part(v_sig, '|', 2);
    if exists (
      select 1 from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname='public' and tg.tgname = v_nome and not tg.tgisinternal
    ) then
      raise notice '      - % ... JA EXISTE -> BLOQUEIO', v_nome;
      v_bloqueios := v_bloqueios || format('Trigger %s ja existe (alvo esperado: %s).', v_nome, v_tab);
    else
      raise notice '      - % (alvo: %) ... livre', v_nome, v_tab;
    end if;
  end loop;

  raise notice '[8c] policies propostas:';
  foreach v_sig in array array[
    'legal_documents_admin_all|legal_documents',
    'legal_acceptances_select_own|legal_acceptances',
    'audit_logs_admin_read|audit_logs',
    'notification_events_select_own|notification_events'
  ] loop
    v_nome := split_part(v_sig, '|', 1);
    v_tab  := split_part(v_sig, '|', 2);
    if exists (select 1 from pg_policies where schemaname='public' and policyname=v_nome) then
      raise notice '      - % ... JA EXISTE -> BLOQUEIO', v_nome;
      v_bloqueios := v_bloqueios || format('Policy %s ja existe.', v_nome);
    else
      raise notice '      - % (alvo: %) ... livre', v_nome, v_tab;
    end if;
  end loop;

  -- ====================================================================
  -- [9] PAPÉIS — anon, authenticated e service_role (com BYPASSRLS)
  -- ====================================================================
  raise notice '[9] papeis:';
  foreach v_nome in array array['anon','authenticated','service_role'] loop
    if exists (select 1 from pg_roles where rolname = v_nome) then
      raise notice '      - % ... presente', v_nome;
    else
      raise notice '      - % ... AUSENTE -> BLOQUEIO', v_nome;
      v_bloqueios := v_bloqueios || format('Papel %s inexistente; os GRANTs/REVOKEs falhariam.', v_nome);
    end if;
  end loop;

  -- BYPASSRLS é requisito do desenho: o backend NAO tem policy propria.
  select r.rolbypassrls into v_bool from pg_roles r where r.rolname = 'service_role';
  if v_bool is null then
    null; -- ausencia ja registrada acima
  elsif v_bool then
    raise notice '      - service_role.rolbypassrls = true (ok)';
  else
    raise notice '      - service_role SEM BYPASSRLS -> BLOQUEIO';
    v_bloqueios := v_bloqueios ||
      'service_role nao possui rolbypassrls=true. Neste desenho nao ha policy para service_role: GRANT sozinho nao basta.';
  end if;
  v_bool := null;

  -- ====================================================================
  -- [10] DEPENDÊNCIAS DE FUNÇÃO — todas BLOQUEIAM
  -- ====================================================================
  raise notice '[10] dependencias essenciais:';

  -- Exige a funcao do CATALOGO com assinatura exata e retorno uuid.
  -- public.gen_random_uuid() NAO e aceito como alternativa: os defaults usam
  -- pg_catalog.gen_random_uuid() para evitar shadowing por funcao homonima.
  v_oid := to_regprocedure('pg_catalog.gen_random_uuid()');
  if v_oid is null then
    raise notice '      - pg_catalog.gen_random_uuid() ... AUSENTE -> BLOQUEIO';
    v_bloqueios := v_bloqueios ||
      'pg_catalog.gen_random_uuid() indisponivel. public.gen_random_uuid() NAO e alternativa aceita.';
  else
    select pg_catalog.format_type(p.prorettype, null) into v_txt from pg_proc p where p.oid = v_oid;
    raise notice '      - pg_catalog.gen_random_uuid() ... disponivel (retorno=%)', v_txt;
    if v_txt is distinct from 'uuid' then
      v_bloqueios := v_bloqueios || format('pg_catalog.gen_random_uuid() retorna %s; esperado uuid.', v_txt);
    end if;
  end if;
  if to_regprocedure('public.gen_random_uuid()') is not null then
    v_avisos := v_avisos ||
      'Existe public.gen_random_uuid(): os defaults qualificam pg_catalog explicitamente, mas confirme que nenhum objeto do projeto depende da versao em public.';
  end if;
  v_txt := null;

  -- auth.uid() deve existir E retornar uuid
  v_oid := to_regprocedure('auth.uid()');
  if v_oid is null then
    raise notice '      - auth.uid() ................ AUSENTE -> BLOQUEIO';
    v_bloqueios := v_bloqueios || 'auth.uid() inexistente com assinatura exata.';
  else
    select pg_catalog.format_type(p.prorettype, null) into v_txt from pg_proc p where p.oid = v_oid;
    raise notice '      - auth.uid() ................ presente (retorno=%)', v_txt;
    if v_txt is distinct from 'uuid' then
      v_bloqueios := v_bloqueios || format('auth.uid() retorna "%s"; esperado uuid.', v_txt);
    end if;
  end if;

  -- auth.users deve ser TABELA
  select c.relkind::text into v_txt
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='auth' and c.relname='users';
  if v_txt is null then
    raise notice '      - auth.users ................ AUSENTE -> BLOQUEIO';
    v_bloqueios := v_bloqueios || 'auth.users inexistente.';
  elsif v_txt not in ('r','p') then
    raise notice '      - auth.users ................ relkind=% -> BLOQUEIO', v_txt;
    v_bloqueios := v_bloqueios || format('auth.users existe com relkind=%s; esperado tabela.', v_txt);
  else
    raise notice '      - auth.users ................ tabela (ok)';
    -- auth.users.id: existe, e uuid e tem PK/unicidade (a FK depende disso).
    select a.atttypid::regtype::text into v_txt
      from pg_attribute a
     where a.attrelid = 'auth.users'::regclass and a.attname = 'id'
       and a.attnum > 0 and not a.attisdropped;
    if v_txt is null then
      raise notice '      - auth.users.id ............. AUSENTE -> BLOQUEIO';
      v_bloqueios := v_bloqueios ||
        'auth.users.id nao existe; a FK legal_acceptances.auth_user_id nao poderia ser criada.';
    elsif v_txt <> 'uuid' then
      raise notice '      - auth.users.id ............. tipo % -> BLOQUEIO', v_txt;
      v_bloqueios := v_bloqueios || format('auth.users.id tem tipo %s; esperado uuid.', v_txt);
    else
      if not exists (
        select 1 from pg_attribute a
         where a.attrelid='auth.users'::regclass and a.attname='id' and a.attnotnull
      ) then
        raise notice '      - auth.users.id ............. NAO e NOT NULL -> BLOQUEIO';
        v_bloqueios := v_bloqueios || 'auth.users.id nao e NOT NULL.';
      end if;

      -- Indice base da FK: unico, simples, valido/ready/live, sem predicado
      -- parcial, sem expressao e sem INCLUDE.
      if exists (
        select 1 from pg_index ix
         where ix.indrelid = 'auth.users'::regclass
           and ix.indisunique
           and ix.indisvalid and ix.indisready and ix.indislive
           and ix.indnatts = 1 and ix.indnkeyatts = 1
           and ix.indpred is null and ix.indexprs is null
           and ix.indkey[0] = (select a.attnum from pg_attribute a
                                where a.attrelid='auth.users'::regclass and a.attname='id')
      ) then
        raise notice '      - auth.users.id ............. uuid, NOT NULL, indice unico simples e valido (FK viavel)';
      else
        raise notice '      - auth.users.id ............. SEM indice unico simples valido -> BLOQUEIO';
        v_bloqueios := v_bloqueios ||
          'auth.users.id sem indice UNIQUE simples e valido: indice parcial, invalido, com expressao, composto, com INCLUDE ou nao pronto NAO servem de base para a FK ON DELETE SET NULL.';
      end if;
    end if;
  end if;
  v_txt := null;

  -- ====================================================================
  -- [11] is_site_admin() — assinatura, retorno, SECURITY DEFINER e
  --      SEARCH_PATH COMPLETO (rejeita pg_temp, "$user" e schema nao confiavel)
  --      NAO altera a funcao: apenas valida.
  -- ====================================================================
  raise notice '[11] public.is_site_admin() — comparacao com a DEFINICAO AUTORITATIVA:';
  raise notice '      Autoritativa (supabase/site-schema-v2.sql @ cba451e):';
  raise notice '        returns boolean language sql stable security definer';
  raise notice '        corpo: select exists (select 1 from public.site_admins where user_id = auth.uid())';
  raise notice '        md5(corpo normalizado) = a65d3c1394e3f45b4afdbf6bba6410a3';
  raise notice '        objetos referenciados: public.site_admins, auth.uid()';
  raise notice '      ATENCAO: a definicao autoritativa NAO possui SET search_path.';

  v_oid := to_regprocedure('public.is_site_admin()');
  if v_oid is null then
    raise notice '      AUSENTE -> BLOQUEIO';
    v_admin_div := v_admin_div + 1;
    v_bloqueios := v_bloqueios || 'public.is_site_admin() nao existe com assinatura exata.';
    for v_rec in
      select pg_get_function_identity_arguments(p.oid) as args
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='is_site_admin'
    loop
      v_bloqueios := v_bloqueios || format('Existe public.is_site_admin(%s) com assinatura diferente.', v_rec.args);
    end loop;
  else
    select pg_catalog.format_type(p.prorettype, null), p.prosecdef,
           coalesce(array_to_string(p.proconfig, ','), ''),
           md5(lower(regexp_replace(p.prosrc, '\s+', '', 'g'))),
           (select l.lanname from pg_language l where l.oid = p.prolang),
           p.provolatile::text,
           lower(regexp_replace(p.prosrc, '\s+', '', 'g'))
      into v_txt, v_bool, v_cfg, v_hash, v_lang, v_vol, v_src
      from pg_proc p where p.oid = v_oid;

    raise notice '      banco: retorno=% | secdef=% | lang=% | vol=% | proconfig=[%]',
      v_txt, v_bool, v_lang, v_vol, coalesce(nullif(v_cfg,''), '(vazio)');
    raise notice '      banco: md5(corpo normalizado) = %', v_hash;

    if v_txt is distinct from 'boolean' then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || format('is_site_admin() retorna "%s"; esperado boolean.', v_txt);
    end if;
    if not coalesce(v_bool, false) then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || 'is_site_admin() NAO e SECURITY DEFINER.';
    end if;
    if v_lang is distinct from 'sql' then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || format('is_site_admin() em linguagem %s; autoritativa e sql.', v_lang);
    end if;
    if v_vol is distinct from 's' then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || format('is_site_admin() com volatilidade %s; autoritativa e stable.', v_vol);
    end if;

    -- Corpo IDENTICO ao autoritativo do repositorio
    if v_hash is distinct from 'a65d3c1394e3f45b4afdbf6bba6410a3' then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || format(
        'is_site_admin() do banco DIVERGE da definicao autoritativa do repositorio (md5 do corpo = %s; esperado a65d3c1394e3f45b4afdbf6bba6410a3).',
        v_hash);
    end if;

    -- Qualificacao por schema e ausencia de dependencia temporaria
    if position('public.site_admins' in coalesce(v_src,'')) = 0 then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || 'is_site_admin() nao referencia public.site_admins qualificado por schema.';
    end if;
    if position('auth.uid()' in coalesce(v_src,'')) = 0 then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || 'is_site_admin() nao referencia auth.uid() qualificado por schema.';
    end if;
    if position('pg_temp' in coalesce(v_src,'')) > 0 then
      v_admin_div := v_admin_div + 1;
      v_bloqueios := v_bloqueios || 'is_site_admin() depende de pg_temp.';
    end if;

    if position('search_path' in v_cfg) = 0 then
      raise notice '      -> SEM search_path fixo: unica deficiencia identificada -> BLOQUEIO';
      v_is_admin_sem_search_path := true;
      v_bloqueios := v_bloqueios ||
        'DEFINICAO AUTORITATIVA INSEGURA: public.is_site_admin() e SECURITY DEFINER SEM SET search_path. Este marco NAO corrige a funcao silenciosamente. E NECESSARIA UMA MIGRATION ESPECIFICA E SEPARADA; a fundacao NAO deve ser aplicada antes disso.';
    else
      v_txt := btrim(split_part(v_cfg, 'search_path=', 2));
      raise notice '      search_path completo = [%]', v_txt;
      foreach v_seg in array string_to_array(v_txt, ',') loop
        v_seg := btrim(replace(v_seg, '"', ''));
        if v_seg = '' then
          continue;
        elsif v_seg in ('$user','pg_temp') then
          v_bloqueios := v_bloqueios || format('is_site_admin() com search_path inseguro: "%s".', v_seg);
        elsif v_seg in ('pg_catalog','public') then
          raise notice '        schema "%": aceito', v_seg;
        else
          v_bloqueios := v_bloqueios || format('is_site_admin() com schema nao confiavel: "%s".', v_seg);
        end if;
      end loop;

      if position('public' in v_txt) > 0 then
        raise notice '        search_path inclui "public": checando CREATE via ACL real';
        v_bool := false;
        for v_rec in
          select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') as papel,
                 a.privilege_type as priv
            from pg_namespace n,
                 aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
           where n.nspname = 'public' and a.privilege_type = 'CREATE'
        loop
          raise notice '          ACL: % possui CREATE em public', v_rec.papel;
          if v_rec.papel = 'PUBLIC' then
            v_bool := true;
            v_bloqueios := v_bloqueios ||
              'PUBLIC possui CREATE no schema public e esse schema esta no search_path de is_site_admin() (shadowing).';
          elsif v_rec.papel in ('anon','authenticated') then
            v_bool := true;
            v_bloqueios := v_bloqueios || format('%s possui CREATE direto no schema public.', v_rec.papel);
          end if;
        end loop;
        foreach v_nome in array array['anon','authenticated'] loop
          begin
            if has_schema_privilege(v_nome, 'public', 'CREATE') then
              v_bool := true;
              v_bloqueios := v_bloqueios || format(
                '%s possui CREATE efetivo (direto ou herdado) no schema public.', v_nome);
            end if;
          exception when undefined_object then
            v_bloqueios := v_bloqueios || format('Papel %s inexistente ao checar CREATE em public.', v_nome);
          end;
        end loop;
        if not v_bool then
          raise notice '        OK: PUBLIC, anon e authenticated sem CREATE no schema public';
        end if;
      end if;
    end if;
  end if;
  -- Consolidacao: a funcao so e AUTORITATIVA E INTEGRA quando NENHUMA das
  -- verificacoes acima divergiu (assinatura, retorno, linguagem, volatilidade,
  -- SECURITY DEFINER, hash do corpo e qualificacao das referencias).
  v_is_admin_autoritativa_ok := (v_admin_div = 0);
  v_requer_hardening := v_is_admin_autoritativa_ok and v_is_admin_sem_search_path;

  if v_is_admin_sem_search_path and not v_is_admin_autoritativa_ok then
    raise notice '      ATENCAO: alem da ausencia de search_path ha % divergencia(s) na definicao.', v_admin_div;
    raise notice '      NAO se pode afirmar que a funcao corresponde ao corpo autoritativo;';
    raise notice '      um simples ALTER FUNCTION ... SET search_path NAO resolve este caso.';
  end if;
  v_txt := null; v_bool := null; v_cfg := null;

  -- ====================================================================
  -- [12] RPC antiga — presença + HASH (permanece INTACTA)
  -- ====================================================================
  raise notice '[12] objetos protegidos da base cba451e (ausencia = BLOQUEIO):';

  -- 12.1 RPC antiga: presenca + assinatura exata + hashes para comparacao
  v_oid := to_regprocedure(
    'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)');
  if v_oid is null then
    raise notice '      create_my_partner_owner_registration(7x text) ... AUSENTE/DIVERGENTE -> BLOQUEIO';
    v_bloqueios := v_bloqueios ||
      'create_my_partner_owner_registration(text,text,text,text,text,text,text) ausente ou com assinatura divergente da base cba451e. A especificacao declara preserva-la INTACTA; a verificacao posterior falharia.';
    for v_rec in
      select pg_get_function_identity_arguments(p.oid) as args
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='create_my_partner_owner_registration'
    loop
      raise notice '        encontrada com assinatura divergente: (%)', v_rec.args;
      v_bloqueios := v_bloqueios || format(
        'Existe create_my_partner_owner_registration(%s) — assinatura diferente da esperada.', v_rec.args);
    end loop;
  else
    raise notice '      create_my_partner_owner_registration(7x text) ... PRESENTE (INTACTA)';
    raise notice '        md5(pg_get_functiondef) = %', md5(pg_get_functiondef(v_oid));
    raise notice '        md5(prosrc)             = %', (select md5(p.prosrc) from pg_proc p where p.oid = v_oid);
    raise notice '        >>> ANOTE: a verificacao posterior compara estes hashes.';
  end if;

  -- 12.2 Tabelas comerciais protegidas da Fase 1
  foreach v_nome in array array[
    'commercial_regions','commercial_region_cities','commercial_niches',
    'commercial_exclusivities','commercial_opportunities'
  ] loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relname=v_nome and c.relkind='r'
    ) then
      raise notice '      commercial: public.% ... presente', v_nome;
    else
      raise notice '      commercial: public.% ... AUSENTE -> BLOQUEIO', v_nome;
      v_bloqueios := v_bloqueios || format(
        'Tabela comercial protegida da Fase 1 ausente: public.%s. A base nao corresponde a cba451e.', v_nome);
    end if;
  end loop;

  -- 12.3 RPCs comerciais que a especificacao declara preservar
  foreach v_sig in array array[
    'public.resolve_commercial_region(text,text)',
    'public.get_current_commercial_formation(text,text)'
  ] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise notice '      RPC comercial % ... AUSENTE/DIVERGENTE -> BLOQUEIO', v_sig;
      v_bloqueios := v_bloqueios || format(
        'RPC comercial protegida ausente ou com assinatura divergente: %s.', v_sig);
    else
      raise notice '      RPC comercial % ... presente | md5=%', v_sig, md5(pg_get_functiondef(v_oid));
    end if;
  end loop;

  -- ====================================================================
  -- [13] Papeis INTERNOS da plataforma Supabase — perfil, memberships e
  --      isolamento (SOMENTE LEITURA). Bloqueia se um papel EXISTENTE divergir
  --      do perfil permitido, ou se anon/authenticated/service_role puderem
  --      herdar (USAGE) ou assumir (MEMBER) qualquer um deles. Ausencia NAO
  --      bloqueia. Somente os dois nomes EXATOS recebem tratamento (sem prefixo).
  -- ====================================================================
  foreach v_nome in array v_supabase_read_roles loop
    select r.oid into v_role_oid from pg_roles r where r.rolname = v_nome;
    if v_role_oid is null then
      raise notice '[13] papel interno % ............ AUSENTE (sem excecao; nao bloqueia pela ausencia)', v_nome;
      continue;
    end if;
    v_repl_esperado := (v_nome = 'supabase_etl_admin');
    v_mem_read  := pg_has_role(v_nome, 'pg_read_all_data', 'MEMBER');
    v_mem_write := exists (select 1 from pg_roles where rolname='pg_write_all_data')
                   and pg_has_role(v_nome, 'pg_write_all_data', 'MEMBER');
    select (r.rolsuper=false and r.rolcanlogin=true and r.rolbypassrls=true
            and r.rolreplication=v_repl_esperado and v_mem_read and not v_mem_write)
      into v_perfil_ok
      from pg_roles r where r.rolname = v_nome;
    raise notice '[13] % | oid=% | canlogin=% super=% bypassrls=% replication=% | membro pg_read_all_data=% pg_write_all_data=%',
      v_nome, v_role_oid,
      (select rolcanlogin   from pg_roles where rolname=v_nome),
      (select rolsuper      from pg_roles where rolname=v_nome),
      (select rolbypassrls  from pg_roles where rolname=v_nome),
      (select rolreplication from pg_roles where rolname=v_nome),
      v_mem_read, v_mem_write;
    if not coalesce(v_perfil_ok, false) then
      raise notice '     -> perfil DIVERGENTE do esperado (replication esperado=%) -> BLOQUEIO', v_repl_esperado;
      v_bloqueios := v_bloqueios || format(
        'Papel interno Supabase %s existe com perfil/memberships divergentes (esperado: rolsuper=false, rolcanlogin=true, rolbypassrls=true, rolreplication=%s, membro de pg_read_all_data, NAO membro de pg_write_all_data).',
        v_nome, v_repl_esperado);
    else
      raise notice '     -> perfil conforme; SELECT global via pg_read_all_data e o unico privilegio efetivo esperado.';
    end if;
    foreach v_tab in array v_app_roles loop
      if exists (select 1 from pg_roles where rolname = v_tab) then
        if pg_has_role(v_tab, v_nome, 'USAGE') then
          raise notice '     -> %: HERDA (USAGE) % -> BLOQUEIO', v_tab, v_nome;
          v_bloqueios := v_bloqueios || format('Papel de aplicacao %s HERDA o papel interno Supabase %s.', v_tab, v_nome);
        elsif pg_has_role(v_tab, v_nome, 'MEMBER') then
          raise notice '     -> %: pode assumir (SET ROLE) % -> BLOQUEIO', v_tab, v_nome;
          v_bloqueios := v_bloqueios || format('Papel de aplicacao %s pode assumir (SET ROLE) o papel interno Supabase %s.', v_tab, v_nome);
        else
          raise notice '     -> %: nao herda nem assume % (ok)', v_tab, v_nome;
        end if;
      end if;
    end loop;
    -- matriz por tabela (equivalencia com [10h] do verificador e H.6 da fundacao):
    -- SELECT=true; INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER=false; sem ACL
    -- direta. Como o preflight roda ANTES da fundacao, as quatro tabelas
    -- normalmente ainda nao existem: nesse caso a matriz nao se aplica (a mesma
    -- LOGICA fica presente e coerente com as demais etapas).
    foreach v_tab in array array['legal_documents','legal_acceptances','audit_logs','notification_events'] loop
      if to_regclass('public.'||v_tab) is null then
        continue;
      end if;
      if not has_table_privilege(v_nome, 'public.'||v_tab, 'SELECT') then
        raise notice '     -> % / public.%: SEM SELECT efetivo -> BLOQUEIO', v_nome, v_tab;
        v_bloqueios := v_bloqueios || format('Papel interno %s SEM SELECT efetivo em public.%s.', v_nome, v_tab);
      end if;
      foreach v_sig in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
        if has_table_privilege(v_nome, 'public.'||v_tab, v_sig) then
          raise notice '     -> % / public.%: % EFETIVO indevido -> BLOQUEIO', v_nome, v_tab, v_sig;
          v_bloqueios := v_bloqueios || format('Papel interno %s possui %s EFETIVO (nao permitido) em public.%s.', v_nome, v_sig, v_tab);
        end if;
      end loop;
      if exists (
        select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace,
               aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
         where n.nspname='public' and c.relname=v_tab
           and coalesce(nullif(a.grantee::regrole::text,'-'),'PUBLIC') = v_nome) then
        raise notice '     -> % / public.%: ACL DIRETA indevida -> BLOQUEIO', v_nome, v_tab;
        v_bloqueios := v_bloqueios || format('Papel interno %s possui ACL DIRETA em public.%s (nao permitido).', v_nome, v_tab);
      end if;
      raise notice '     matriz % / public.% -> SELECT=% INSERT=% UPDATE=% DELETE=% TRUNCATE=% REFERENCES=% TRIGGER=%',
        v_nome, v_tab,
        has_table_privilege(v_nome,'public.'||v_tab,'SELECT'),
        has_table_privilege(v_nome,'public.'||v_tab,'INSERT'),
        has_table_privilege(v_nome,'public.'||v_tab,'UPDATE'),
        has_table_privilege(v_nome,'public.'||v_tab,'DELETE'),
        has_table_privilege(v_nome,'public.'||v_tab,'TRUNCATE'),
        has_table_privilege(v_nome,'public.'||v_tab,'REFERENCES'),
        has_table_privilege(v_nome,'public.'||v_tab,'TRIGGER');
    end loop;
    v_role_oid := null; v_perfil_ok := null; v_mem_read := null; v_mem_write := null;
  end loop;

  -- ====================================================================
  -- VEREDITO
  -- ====================================================================
  raise notice '-----------------------------------------------------------';
  if array_length(v_avisos, 1) is not null then
    raise notice 'AVISOS (nao bloqueiam):';
    for v_i in 1 .. array_length(v_avisos, 1) loop
      raise notice '   (%) %', v_i, v_avisos[v_i];
    end loop;
  else
    raise notice 'AVISOS: nenhum.';
  end if;

  if array_length(v_bloqueios, 1) is null then
    raise notice '-----------------------------------------------------------';
    raise notice 'PREFLIGHT_FASE2A_MARCO1_LIMPO';
  else
    raise notice 'BLOQUEIOS (%):', array_length(v_bloqueios, 1);
    for v_i in 1 .. array_length(v_bloqueios, 1) loop
      raise notice '   (%) %', v_i, v_bloqueios[v_i];
    end loop;
    raise notice '-----------------------------------------------------------';
    raise notice 'PREFLIGHT_FASE2A_MARCO1_BLOQUEADO';
    if v_requer_hardening then
      raise notice 'PREFLIGHT_FASE2A_MARCO1_BLOQUEADO_REQUER_HARDENING_IS_SITE_ADMIN';
      raise notice '   A funcao do banco CORRESPONDE ao corpo autoritativo do commit cba451e.';
      raise notice '   O problema e a AUSENCIA de search_path fixo numa funcao SECURITY DEFINER.';
      raise notice '   A fundacao NAO sera executavel ate que uma migration SEPARADA corrija';
      raise notice '   somente essa configuracao. Essa migration sera criada em outro prompt;';
      raise notice '   este pacote (V11) nao a cria, nao a altera e nao a executa.';
    end if;
    raise notice 'NAO aplicar fase2a-marco1-foundation.sql. Resolver manualmente (Secao B, comentada).';
  end if;
end
$preflight$;


-- ============================================================================
-- SEÇÃO B — EXEMPLOS DE REVISÃO MANUAL (INTEGRALMENTE COMENTADOS)
-- ----------------------------------------------------------------------------
-- Não são executados. Copie individualmente APENAS se houver bloqueio e após
-- confirmar que as tabelas/colunas citadas existem. Nenhuma correção automática.
-- ============================================================================
--
-- B.1 — Duplicidades de auth_user_id:
-- select auth_user_id, count(*) as qtd, array_agg(id) as perfis
--   from public.site_profiles where auth_user_id is not null
--  group by auth_user_id having count(*) > 1 order by qtd desc;
--
-- B.2 — Linhas envolvidas:
-- select p.id, p.auth_user_id, p.email, p.created_at
--   from public.site_profiles p
--   join (select auth_user_id from public.site_profiles
--          where auth_user_id is not null group by auth_user_id having count(*) > 1) d
--     on d.auth_user_id = p.auth_user_id
--  order by p.auth_user_id, p.created_at;
--
-- B.3 — Índices atuais de site_profiles:
-- select i.relname, ix.indisunique, pg_get_indexdef(ix.indexrelid)
--   from pg_index ix join pg_class i on i.oid = ix.indexrelid
--   join pg_class t on t.oid = ix.indrelid
--   join pg_namespace n on n.oid = t.relnamespace
--  where n.nspname='public' and t.relname='site_profiles' order by i.relname;
--
-- B.4 — Artefatos antigos baseados em views (decidir manualmente o destino):
-- select c.relname, c.relkind, pg_get_viewdef(c.oid, true)
--   from pg_class c join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname='public'
--    and c.relname in ('my_notifications','my_legal_acceptances','legal_documents_public');
--
-- B.5 — search_path e ACL de is_site_admin():
-- select p.proname, p.prosecdef, p.proconfig, p.proacl
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname='public' and p.proname='is_site_admin';
--
-- B.6 — Quem tem CREATE no schema public:
-- select grantee, privilege_type
--   from information_schema.usage_privileges where object_name = 'public';
-- -- ou: select * from aclexplode((select nspacl from pg_namespace where nspname='public'));
--
-- B.7 — Definição completa da RPC antiga (diff manual):
-- select pg_get_functiondef(
--   to_regprocedure('public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')::oid);
--
-- ============================================================================
-- FIM DO PREFLIGHT — somente leitura.
-- ============================================================================
