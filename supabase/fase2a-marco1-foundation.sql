-- ============================================================================
-- BDFlow Site — FASE 2A · MARCO 1 · FUNDAÇÃO TRANSVERSAL (PROPOSTA) — V11
-- ----------------------------------------------------------------------------
-- Base autoritativa: commit cba451e da origin/main.
--
-- ESTE ARQUIVO NÃO FOI EXECUTADO. É proposta para inspeção humana.
-- Pré-requisito: preflight com PREFLIGHT_FASE2A_MARCO1_LIMPO.
--
-- ESTRATÉGIA: FAIL-CLOSED (NÃO É IDEMPOTENTE, POR DECISÃO DE PROJETO)
--   • Sem CREATE OR REPLACE, sem DROP ... IF EXISTS, sem CREATE ... IF NOT EXISTS.
--   • Guarda inicial interrompe se qualquer objeto proposto — ou qualquer
--     artefato antigo baseado em VIEW — já existir.
--   • Guarda inicial REVALIDA todas as dependências essenciais: não confia no
--     resultado de um preflight anterior.
--
-- SEGURANÇA
--   • Todas as funções novas usam SET search_path = pg_catalog e qualificam
--     integralmente objetos fora de pg_catalog (public.*, auth.uid, auth.users).
--   • service_role: REVOKE ALL antes dos GRANTs mínimos; sem DELETE/TRUNCATE/
--     REFERENCES/TRIGGER. BYPASSRLS é exigido pelo desenho (não há policy para
--     service_role) — GRANT e BYPASSRLS são AMBOS necessários.
--
-- NÃO TOCA: create_my_partner_owner_registration, tabelas comerciais da Fase 1,
--   site-schema-v2.sql, site-partner-core.sql, is_site_admin(), Auth, Storage,
--   rotas, React, preços, fidelidade, contratos, pagamentos.
-- ============================================================================

begin;

-- ===========================================================================
-- GUARDA FAIL-CLOSED
-- ===========================================================================
do $guard$
declare
  v_conf text[] := array[]::text[];
  v_dep  text[] := array[]::text[];
  v_nome text;
  v_seg  text;
  v_rec  record;
  v_i    int;
  v_oid  oid;
  v_cfg  text;
  v_txt  text;
  v_bool boolean;
  v_grupos bigint;
  v_linhas bigint;
  v_hash text;
  v_lang text;
  v_vol  text;
  v_src  text;
begin
  -- ---- 1. Objetos propostos devem estar LIVRES -------------------------
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname='public' and c.relname=v_nome and c.relkind in ('r','v','m','p','f')
    ) then
      v_conf := v_conf || ('relacao public.' || v_nome);
    end if;
  end loop;

  -- ---- 1b. Artefatos ANTIGOS (propostas baseadas em views) -------------
  foreach v_nome in array array[
    'my_notifications','my_legal_acceptances','legal_documents_public'
  ] loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname='public' and c.relname=v_nome
    ) then
      v_conf := v_conf || ('ARTEFATO ANTIGO public.' || v_nome
                           || ' (proposta baseada em VIEW; nao coexiste com esta proposta)');
    end if;
  end loop;

  foreach v_nome in array array[
    'fase2a_touch_updated_at','legal_documents_protect','legal_documents_check_overlap',
    'legal_acceptances_protect','audit_logs_block_mutation','notification_events_protect',
    'current_legal_document','get_current_legal_documents','legal_document_versions',
    'get_my_legal_acceptances','get_my_notifications','record_legal_acceptance','write_audit_log'
  ] loop
    if exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname=v_nome
    ) then
      v_conf := v_conf || ('funcao public.' || v_nome);
    end if;
  end loop;

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
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname='public' and c.relname=v_nome and c.relkind='i'
    ) then
      v_conf := v_conf || ('indice ' || v_nome);
    end if;
  end loop;

  foreach v_nome in array array[
    'trg_legal_documents_updated','trg_legal_documents_protect','trg_legal_documents_overlap',
    'trg_legal_acceptances_protect_upd','trg_legal_acceptances_protect_del',
    'trg_audit_logs_no_update','trg_audit_logs_no_delete',
    'trg_notification_events_updated','trg_notification_events_protect'
  ] loop
    if exists (
      select 1 from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname='public' and tg.tgname=v_nome and not tg.tgisinternal
    ) then
      v_conf := v_conf || ('trigger ' || v_nome);
    end if;
  end loop;

  foreach v_nome in array array[
    'legal_documents_admin_all','legal_acceptances_select_own',
    'audit_logs_admin_read','notification_events_select_own'
  ] loop
    if exists (select 1 from pg_policies where schemaname='public' and policyname=v_nome) then
      v_conf := v_conf || ('policy ' || v_nome);
    end if;
  end loop;

  if array_length(v_conf, 1) is not null then
    raise notice 'Objetos conflitantes encontrados:';
    for v_i in 1 .. array_length(v_conf, 1) loop
      raise notice '   (%) %', v_i, v_conf[v_i];
    end loop;
    raise exception
      'MIGRATION INTERROMPIDA (fail-closed): % objeto(s) conflitante(s). Nada foi substituido, removido ou adaptado. Exige analise manual.',
      array_length(v_conf, 1);
  end if;

  -- ---- 2. site_profiles: tabela, coluna uuid, nullable, sem duplicidade
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='site_profiles' and c.relkind='r'
  ) then
    v_dep := v_dep || 'public.site_profiles nao existe ou nao e tabela.';
  else
    select c.data_type, c.is_nullable into v_txt, v_cfg
      from information_schema.columns c
     where c.table_schema='public' and c.table_name='site_profiles' and c.column_name='auth_user_id';
    if v_txt is null then
      v_dep := v_dep || 'public.site_profiles.auth_user_id nao existe.';
    else
      if v_txt <> 'uuid' then
        v_dep := v_dep || format('site_profiles.auth_user_id tem tipo %s; esperado uuid.', v_txt);
      end if;
      if v_cfg = 'NO' then
        v_dep := v_dep || 'site_profiles.auth_user_id esta NOT NULL; registros provisorios exigem NULL.';
      end if;

      select count(*), coalesce(sum(qtd), 0) into v_grupos, v_linhas
        from (
          select auth_user_id, count(*) as qtd from public.site_profiles
           where auth_user_id is not null group by auth_user_id having count(*) > 1
        ) d;
      if v_grupos > 0 then
        v_dep := v_dep || format(
          '%s auth_user_id duplicados (%s linhas). Esta migration NAO corrige, NAO mescla e NAO escolhe vencedor.',
          v_grupos, v_linhas);
      end if;
    end if;
  end if;
  v_txt := null; v_cfg := null;

  -- ---- 3. Papéis: anon, authenticated, service_role (+ BYPASSRLS) ------
  foreach v_nome in array array['anon','authenticated','service_role'] loop
    if not exists (select 1 from pg_roles where rolname = v_nome) then
      v_dep := v_dep || format('Papel %s inexistente; GRANT/REVOKE falhariam.', v_nome);
    end if;
  end loop;

  select r.rolbypassrls into v_bool from pg_roles r where r.rolname = 'service_role';
  if v_bool is not null and not v_bool then
    v_dep := v_dep ||
      'service_role sem rolbypassrls=true. Neste desenho nao ha policy para service_role: GRANT sozinho nao basta.';
  end if;
  v_bool := null;

  -- ---- 4. gen_random_uuid, auth.uid (uuid) e auth.users (tabela) -------
  -- Exige a funcao do CATALOGO: public.gen_random_uuid() NAO e alternativa
  -- aceita (evita shadowing por funcao homonima em schema pesquisavel).
  v_oid := to_regprocedure('pg_catalog.gen_random_uuid()');
  if v_oid is null then
    v_dep := v_dep ||
      'pg_catalog.gen_random_uuid() indisponivel. public.gen_random_uuid() NAO e aceito como alternativa.';
  else
    if (select pg_catalog.format_type(p.prorettype, null) from pg_proc p where p.oid = v_oid) <> 'uuid' then
      v_dep := v_dep || 'pg_catalog.gen_random_uuid() nao retorna uuid.';
    end if;
  end if;

  v_oid := to_regprocedure('auth.uid()');
  if v_oid is null then
    v_dep := v_dep || 'auth.uid() inexistente com assinatura exata.';
  else
    select pg_catalog.format_type(p.prorettype, null) into v_txt from pg_proc p where p.oid = v_oid;
    if v_txt is distinct from 'uuid' then
      v_dep := v_dep || format('auth.uid() retorna %s; esperado uuid.', v_txt);
    end if;
  end if;
  v_txt := null;

  select c.relkind::text into v_txt
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='auth' and c.relname='users';
  if v_txt is null then
    v_dep := v_dep || 'auth.users inexistente.';
  elsif v_txt not in ('r','p') then
    v_dep := v_dep || format('auth.users com relkind=%s; esperado tabela.', v_txt);
  else
    -- auth.users.id: existe, e uuid e possui PK/unicidade (a FK exige isso).
    select a.atttypid::regtype::text into v_txt
      from pg_attribute a
     where a.attrelid = 'auth.users'::regclass and a.attname = 'id' and a.attnum > 0 and not a.attisdropped;
    if v_txt is null then
      v_dep := v_dep || 'auth.users.id nao existe; a FK de legal_acceptances nao poderia ser criada.';
    elsif v_txt <> 'uuid' then
      v_dep := v_dep || format('auth.users.id tem tipo %s; esperado uuid.', v_txt);
    else
      -- NOT NULL obrigatorio
      if not exists (
        select 1 from pg_attribute a
         where a.attrelid='auth.users'::regclass and a.attname='id' and a.attnotnull
      ) then
        v_dep := v_dep || 'auth.users.id nao e NOT NULL.';
      end if;

      -- Indice base da FK: unico, simples, valido, sem predicado/expressao/INCLUDE
      if not exists (
        select 1
          from pg_index ix
         where ix.indrelid = 'auth.users'::regclass
           and ix.indisunique
           and ix.indisvalid and ix.indisready and ix.indislive
           and ix.indnatts = 1 and ix.indnkeyatts = 1
           and ix.indpred is null
           and ix.indexprs is null
           and ix.indkey[0] = (select a.attnum from pg_attribute a
                                where a.attrelid='auth.users'::regclass and a.attname='id')
      ) then
        v_dep := v_dep ||
          'auth.users.id sem indice UNIQUE simples e valido (PK ou unique): indice parcial, invalido, com expressao, composto, com INCLUDE ou nao pronto NAO servem de base para a FK ON DELETE SET NULL.';
      end if;
    end if;
  end if;
  v_txt := null;

  -- ---- 5. is_site_admin(): comparacao com a DEFINICAO AUTORITATIVA -----
  --
  -- Definicao autoritativa (supabase/site-schema-v2.sql, base cba451e):
  --   create or replace function public.is_site_admin()
  --   returns boolean language sql stable security definer as
  --   $ select exists (select 1 from public.site_admins where user_id = auth.uid()) $
  --
  --   md5(corpo normalizado) = a65d3c1394e3f45b4afdbf6bba6410a3
  --   objetos referenciados: public.site_admins, auth.uid()  (ambos qualificados)
  --
  -- ATENCAO: essa definicao autoritativa NAO possui SET search_path. Uma funcao
  -- SECURITY DEFINER sem search_path fixo e insegura. Este marco NAO a corrige
  -- silenciosamente: interrompe e exige uma migration especifica e separada.
  v_oid := to_regprocedure('public.is_site_admin()');
  if v_oid is null then
    v_dep := v_dep || 'public.is_site_admin() inexistente com assinatura exata.';
  else
    select pg_catalog.format_type(p.prorettype, null), p.prosecdef,
           coalesce(array_to_string(p.proconfig, ','), ''),
           md5(lower(regexp_replace(p.prosrc, '\s+', '', 'g'))),
           (select l.lanname from pg_language l where l.oid = p.prolang),
           p.provolatile::text,
           lower(regexp_replace(p.prosrc, '\s+', '', 'g'))
      into v_txt, v_bool, v_cfg, v_hash, v_lang, v_vol, v_src
      from pg_proc p where p.oid = v_oid;

    if v_txt is distinct from 'boolean' then
      v_dep := v_dep || format('is_site_admin() retorna %s; esperado boolean.', v_txt);
    end if;
    if not coalesce(v_bool, false) then
      v_dep := v_dep || 'is_site_admin() nao e SECURITY DEFINER.';
    end if;
    if v_lang is distinct from 'sql' then
      v_dep := v_dep || format('is_site_admin() em linguagem %s; autoritativa e sql.', v_lang);
    end if;
    if v_vol is distinct from 's' then
      v_dep := v_dep || format('is_site_admin() com volatilidade %s; autoritativa e stable.', v_vol);
    end if;

    -- Corpo deve ser IDENTICO ao autoritativo do repositorio.
    if v_hash is distinct from 'a65d3c1394e3f45b4afdbf6bba6410a3' then
      v_dep := v_dep || format(
        'is_site_admin() do banco DIVERGE da definicao autoritativa do repositorio: md5(corpo)=%s (esperado a65d3c1394e3f45b4afdbf6bba6410a3).',
        v_hash);
    end if;

    -- Referencias qualificadas e ausencia de dependencia temporaria.
    if position('public.site_admins' in coalesce(v_src, '')) = 0 then
      v_dep := v_dep || 'is_site_admin() nao referencia public.site_admins de forma qualificada.';
    end if;
    if position('auth.uid()' in coalesce(v_src, '')) = 0 then
      v_dep := v_dep || 'is_site_admin() nao referencia auth.uid() de forma qualificada.';
    end if;
    if position('pg_temp' in coalesce(v_src, '')) > 0 then
      v_dep := v_dep || 'is_site_admin() depende de pg_temp (tabela temporaria).';
    end if;

    -- search_path: obrigatorio e sem shadowing.
    if position('search_path' in v_cfg) = 0 then
      v_dep := v_dep ||
        'DEFINICAO AUTORITATIVA INSEGURA: public.is_site_admin() e SECURITY DEFINER SEM SET search_path. Este marco NAO corrige a funcao. E NECESSARIA UMA MIGRATION ESPECIFICA E SEPARADA antes de aplicar esta fundacao.';
    else
      v_txt := btrim(split_part(v_cfg, 'search_path=', 2));
      foreach v_seg in array string_to_array(v_txt, ',') loop
        v_seg := btrim(replace(v_seg, '"', ''));
        if v_seg = '' then
          continue;
        elsif v_seg in ('$user','pg_temp') then
          v_dep := v_dep || format('is_site_admin() com search_path inseguro: "%s".', v_seg);
        elsif v_seg not in ('pg_catalog','public') then
          v_dep := v_dep || format('is_site_admin() com schema nao confiavel no search_path: "%s".', v_seg);
        end if;
      end loop;

      if position('public' in v_txt) > 0 then
        -- PUBLIC e PSEUDO-PAPEL: ler a ACL real (grantee 0 = PUBLIC).
        for v_rec in
          select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') as papel,
                 a.privilege_type as priv
            from pg_namespace n,
                 aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
           where n.nspname = 'public' and a.privilege_type = 'CREATE'
        loop
          if v_rec.papel = 'PUBLIC' then
            v_dep := v_dep ||
              'PUBLIC possui CREATE no schema public, que integra o search_path de is_site_admin() (shadowing).';
          elsif v_rec.papel in ('anon','authenticated') then
            v_dep := v_dep || format('%s possui CREATE direto no schema public.', v_rec.papel);
          end if;
        end loop;
        foreach v_nome in array array['anon','authenticated'] loop
          begin
            if has_schema_privilege(v_nome, 'public', 'CREATE') then
              v_dep := v_dep || format(
                '%s possui CREATE efetivo (direto ou herdado) no schema public.', v_nome);
            end if;
          exception when undefined_object then
            v_dep := v_dep || format('Papel %s inexistente ao checar CREATE em public.', v_nome);
          end;
        end loop;
      end if;
    end if;
  end if;

  if array_length(v_dep, 1) is not null then
    raise notice 'Dependencias ausentes/invalidas:';
    for v_i in 1 .. array_length(v_dep, 1) loop
      raise notice '   (%) %', v_i, v_dep[v_i];
    end loop;
    raise exception
      'MIGRATION INTERROMPIDA: % dependencia(s) essencial(is) nao atendida(s). Nenhum objeto foi criado.',
      array_length(v_dep, 1);
  end if;
end
$guard$;

-- ---------------------------------------------------------------------------
-- HELPER — updated_at
-- ---------------------------------------------------------------------------
create function public.fase2a_touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ===========================================================================
-- A. legal_documents
-- ---------------------------------------------------------------------------
-- Ciclo: draft -> published -> archived. Rascunho interno nunca vira histórico.
-- ===========================================================================
create table public.legal_documents (
  id                  uuid primary key default pg_catalog.gen_random_uuid(),
  doc_type            text        not null,
  version             text        not null,
  title               text        not null,
  content             text        null,
  content_url         text        null,
  content_hash        text        null,
  status              text        not null default 'draft',
  is_material_change  boolean     not null default false,
  effective_from      timestamptz null,
  effective_to        timestamptz null,
  published_at        timestamptz null,
  published_by        uuid        null,
  notes               text        null,   -- INTERNO
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint legal_documents_type_allowed check (
    doc_type in (
      'privacy_notice',
      'provisional_account_terms',
      'truthfulness_declaration',
      'document_analysis_authorization',
      'representation_declaration',
      'future_commercial_terms'
    )
  ),
  constraint legal_documents_status_allowed check (status in ('draft','published','archived')),
  constraint legal_documents_version_nonempty check (length(btrim(version)) > 0),
  constraint legal_documents_title_nonempty   check (length(btrim(title))   > 0),

  constraint legal_documents_published_complete check (
    status <> 'published'
    or (
      (
        (content is not null and length(btrim(content)) > 0)
        or (content_url is not null and length(btrim(content_url)) > 0)
      )
      and content_hash is not null and length(btrim(content_hash)) > 0
      and published_at   is not null
      and published_by   is not null
      and effective_from is not null
    )
  ),
  constraint legal_documents_archived_complete check (
    status <> 'archived'
    or (
      (
        (content is not null and length(btrim(content)) > 0)
        or (content_url is not null and length(btrim(content_url)) > 0)
      )
      and content_hash is not null and length(btrim(content_hash)) > 0
      and published_at   is not null
      and published_by   is not null
      and effective_from is not null
      and effective_to   is not null
    )
  ),
  constraint legal_documents_vigencia_coerente check (
    effective_to is null or (effective_from is not null and effective_to > effective_from)
  ),
  constraint legal_documents_type_version_unique unique (doc_type, version)
);

create unique index uq_legal_documents_vigente
  on public.legal_documents (doc_type)
  where status = 'published' and effective_to is null;

create index idx_legal_documents_type_status
  on public.legal_documents (doc_type, status, effective_from);

create trigger trg_legal_documents_updated
  before update on public.legal_documents
  for each row execute function public.fase2a_touch_updated_at();

-- Sobreposição de vigência: considera versões PUBLISHED **e ARCHIVED**, isto é,
-- toda a linha do tempo jurídica — arquivar não libera o intervalo já ocupado.
create function public.legal_documents_check_overlap()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_conflitos int;
begin
  if new.status not in ('published', 'archived') then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('legal_documents:' || new.doc_type));

  select count(*) into v_conflitos
    from public.legal_documents d
   where d.doc_type = new.doc_type
     and d.status in ('published', 'archived')
     and d.id <> new.id
     and tstzrange(d.effective_from, d.effective_to, '[)')
      && tstzrange(new.effective_from, new.effective_to, '[)');

  if v_conflitos > 0 then
    raise exception
      'Vigencia sobreposta: ja existe versao publicada ou arquivada de "%" cobrindo o intervalo informado.',
      new.doc_type;
  end if;
  return new;
end;
$$;

create trigger trg_legal_documents_overlap
  before insert or update on public.legal_documents
  for each row execute function public.legal_documents_check_overlap();

create function public.legal_documents_protect()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  -- DELETE: a imutabilidade juridica abrange exclusao. Neste marco NENHUM
  -- legal_document pode ser excluido — nem rascunho —, porque ainda nao existe
  -- RPC administrativa auditada para exclusao controlada. A exclusao de
  -- rascunhos (nunca publicados e sem aceite) sera criada em migration
  -- separada, com auditoria.
  if tg_op = 'DELETE' then
    raise exception
      'Documento juridico nao pode ser excluido (id=%, status=%). Publicados e arquivados sao imutaveis; a exclusao controlada de rascunhos exige RPC administrativa auditada (migration separada).',
      old.id, old.status;
  end if;

  if tg_op = 'INSERT' then
    if new.status = 'archived' then
      raise exception
        'Documento nao pode ser criado como archived: o arquivamento so ocorre a partir de published.';
    end if;
    return new;
  end if;

  if old.status = 'archived' then
    if new.status <> 'archived' then
      raise exception 'Versao arquivada nao pode retornar para "%" (id=%).', new.status, old.id;
    end if;
    if new.doc_type           is distinct from old.doc_type
    or new.version            is distinct from old.version
    or new.title              is distinct from old.title
    or new.content            is distinct from old.content
    or new.content_url        is distinct from old.content_url
    or new.content_hash       is distinct from old.content_hash
    or new.is_material_change is distinct from old.is_material_change
    or new.effective_from     is distinct from old.effective_from
    or new.effective_to       is distinct from old.effective_to
    or new.published_at       is distinct from old.published_at
    or new.published_by       is distinct from old.published_by then
      raise exception 'Versao arquivada e imutavel (id=%).', old.id;
    end if;
    return new;
  end if;

  if old.status = 'draft' then
    if new.status = 'archived' then
      raise exception
        'Rascunho nao pode ser arquivado (id=%): archived so a partir de published.', old.id;
    end if;
    if new.status not in ('draft','published') then
      raise exception 'Transicao invalida a partir de draft (id=%).', old.id;
    end if;
    return new;
  end if;

  if old.status = 'published' then
    if new.doc_type           is distinct from old.doc_type
    or new.version            is distinct from old.version
    or new.title              is distinct from old.title
    or new.content            is distinct from old.content
    or new.content_url        is distinct from old.content_url
    or new.content_hash       is distinct from old.content_hash
    or new.is_material_change is distinct from old.is_material_change
    or new.effective_from     is distinct from old.effective_from
    or new.published_at       is distinct from old.published_at
    or new.published_by       is distinct from old.published_by then
      raise exception 'Versao publicada e imutavel (id=%). Publique uma NOVA versao.', old.id;
    end if;

    if new.status not in ('published','archived') then
      raise exception 'Transicao invalida a partir de published (id=%).', old.id;
    end if;

    if old.effective_to is not null and new.effective_to is distinct from old.effective_to then
      raise exception 'effective_to ja definido nao pode ser alterado nem removido (id=%).', old.id;
    end if;
    if new.effective_to is not null and new.effective_to <= old.effective_from then
      raise exception 'effective_to deve ser posterior a effective_from (id=%).', old.id;
    end if;

    if new.status = 'archived' then
      if new.effective_to is null then
        raise exception 'Arquivamento exige effective_to definido (id=%).', old.id;
      end if;
      if new.effective_to > now() then
        raise exception
          'Arquivamento exige vigencia ja encerrada; effective_to esta no futuro (id=%).', old.id;
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_legal_documents_protect
  before insert or update or delete on public.legal_documents
  for each row execute function public.legal_documents_protect();

-- ===========================================================================
-- B. legal_acceptances
-- ===========================================================================
create table public.legal_acceptances (
  id                     uuid        primary key default pg_catalog.gen_random_uuid(),
  subject_type           text        not null,
  subject_id             uuid        not null,   -- identidade histórica (sem FK)
  linked_auth_user_id    uuid        null,       -- vínculo imutável (sem FK)
  auth_user_id           uuid        null
                           references auth.users(id) on delete set null,
  partner_application_id uuid        null,       -- FK no Marco 2
  legal_document_id      uuid        not null
                           references public.legal_documents(id) on delete restrict,
  accepted_at            timestamptz not null default now(),
  context                text        not null,
  origin                 text        not null default 'server',
  ip                     inet        null,
  user_agent             text        null,
  evidence               jsonb       not null default '{}'::jsonb,
  revoked_at             timestamptz null,
  revocation_reason      text        null,
  created_at             timestamptz not null default now(),

  constraint legal_acceptances_subject_allowed check (
    subject_type in ('auth_user','partner_application')
  ),
  constraint legal_acceptances_context_allowed check (
    context in (
      'partner_application',
      'provisional_account',
      'owner_authority',
      'manager_invite',
      'commercial_contract'
    )
  ),
  constraint legal_acceptances_subject_coerente check (
    (subject_type = 'auth_user'
       and partner_application_id is null
       and linked_auth_user_id is not null
       and linked_auth_user_id = subject_id)
    or
    (subject_type = 'partner_application'
       and partner_application_id is not null
       and partner_application_id = subject_id)
  ),
  constraint legal_acceptances_link_coerente check (
    auth_user_id is null
    or (linked_auth_user_id is not null and auth_user_id = linked_auth_user_id)
  ),
  constraint legal_acceptances_revocacao_coerente check (
    (revoked_at is null and revocation_reason is null)
    or (revoked_at is not null
        and revocation_reason is not null
        and length(btrim(revocation_reason)) > 0)
  ),
  constraint legal_acceptances_evidence_objeto check (jsonb_typeof(evidence) = 'object'),
  constraint legal_acceptances_evidence_limite check (length(evidence::text) <= 8192)
);

create unique index uq_legal_acceptances_ativo
  on public.legal_acceptances (subject_type, subject_id, legal_document_id, context)
  where revoked_at is null;

create index idx_legal_acceptances_subject   on public.legal_acceptances (subject_type, subject_id);
create index idx_legal_acceptances_auth_user on public.legal_acceptances (auth_user_id);
create index idx_legal_acceptances_linked    on public.legal_acceptances (linked_auth_user_id);
create index idx_legal_acceptances_doc       on public.legal_acceptances (legal_document_id);

create function public.legal_acceptances_protect()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Aceite juridico nao pode ser excluido (id=%). Use revogacao.', old.id;
  end if;

  if new.id                     is distinct from old.id
  or new.subject_type           is distinct from old.subject_type
  or new.subject_id             is distinct from old.subject_id
  or new.partner_application_id is distinct from old.partner_application_id
  or new.legal_document_id      is distinct from old.legal_document_id
  or new.accepted_at            is distinct from old.accepted_at
  or new.context                is distinct from old.context
  or new.origin                 is distinct from old.origin
  or new.ip                     is distinct from old.ip
  or new.user_agent             is distinct from old.user_agent
  or new.evidence               is distinct from old.evidence
  or new.created_at             is distinct from old.created_at then
    raise exception
      'Campos de evidencia do aceite sao imutaveis (id=%). Permitido apenas promover o vinculo ou revogar.', old.id;
  end if;

  -- PROMOCAO ATOMICA: a primeira associacao com uma conta deve preencher
  -- linked_auth_user_id E auth_user_id na MESMA atualizacao, com o mesmo valor.
  if old.linked_auth_user_id is null and new.linked_auth_user_id is not null then
    if new.auth_user_id is null then
      raise exception
        'Promocao deve ser atomica (id=%): auth_user_id nao pode ficar NULL ao definir linked_auth_user_id.', old.id;
    end if;
    if new.auth_user_id is distinct from new.linked_auth_user_id then
      raise exception
        'Promocao deve ser atomica (id=%): auth_user_id deve ser igual a linked_auth_user_id.', old.id;
    end if;
  end if;

  if old.linked_auth_user_id is not null
     and new.linked_auth_user_id is distinct from old.linked_auth_user_id then
    raise exception
      'linked_auth_user_id e imutavel (id=%): ja vinculado a %, nao pode ser apagado nem substituido.',
      old.id, old.linked_auth_user_id;
  end if;

  if new.auth_user_id is not null
     and new.auth_user_id is distinct from coalesce(new.linked_auth_user_id, new.auth_user_id) then
    raise exception 'auth_user_id deve ser igual a linked_auth_user_id (id=%).', old.id;
  end if;
  if old.auth_user_id is not null
     and new.auth_user_id is not null
     and new.auth_user_id is distinct from old.auth_user_id then
    raise exception 'auth_user_id ja vinculado nao pode ser trocado por outro (id=%).', old.id;
  end if;
  if old.auth_user_id is null
     and new.auth_user_id is not null
     and old.linked_auth_user_id is not null
     and new.auth_user_id is distinct from old.linked_auth_user_id then
    raise exception
      'Aceite ja vinculado a % nao pode ser revinculado a outra conta (id=%).',
      old.linked_auth_user_id, old.id;
  end if;

  if old.revoked_at is not null then
    if new.revoked_at is distinct from old.revoked_at then
      raise exception 'revoked_at e imutavel apos a revogacao (id=%).', old.id;
    end if;
    if new.revocation_reason is distinct from old.revocation_reason then
      raise exception 'revocation_reason e imutavel apos a revogacao (id=%).', old.id;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_legal_acceptances_protect_upd
  before update on public.legal_acceptances
  for each row execute function public.legal_acceptances_protect();

create trigger trg_legal_acceptances_protect_del
  before delete on public.legal_acceptances
  for each row execute function public.legal_acceptances_protect();

-- ===========================================================================
-- C. audit_logs — append-only
-- ===========================================================================
create table public.audit_logs (
  id               uuid        primary key default pg_catalog.gen_random_uuid(),
  occurred_at      timestamptz not null default now(),
  actor_user_id    uuid        null,
  actor_role       text        null,
  action           text        not null,
  entity_type      text        not null,
  entity_id        text        null,
  previous_state   jsonb       null,
  new_state        jsonb       null,
  justification    text        null,
  correlation_id   uuid        null,
  source           text        null,
  metadata         jsonb       not null default '{}'::jsonb,
  corrects_log_id  uuid        null references public.audit_logs(id) on delete restrict,

  constraint audit_logs_action_nonempty      check (length(btrim(action)) > 0),
  constraint audit_logs_entity_type_nonempty check (length(btrim(entity_type)) > 0),
  constraint audit_logs_nao_corrige_a_si     check (corrects_log_id is null or corrects_log_id <> id),
  constraint audit_logs_metadata_objeto      check (jsonb_typeof(metadata) = 'object')
);

create index idx_audit_logs_entity      on public.audit_logs (entity_type, entity_id);
create index idx_audit_logs_actor       on public.audit_logs (actor_user_id);
create index idx_audit_logs_occurred    on public.audit_logs (occurred_at);
create index idx_audit_logs_correlation on public.audit_logs (correlation_id);

create function public.audit_logs_block_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception
    'audit_logs e append-only: % bloqueado. Registre um NOVO evento com corrects_log_id.', tg_op;
  return null;
end;
$$;

create trigger trg_audit_logs_no_update
  before update on public.audit_logs
  for each row execute function public.audit_logs_block_mutation();

create trigger trg_audit_logs_no_delete
  before delete on public.audit_logs
  for each row execute function public.audit_logs_block_mutation();

-- ===========================================================================
-- D. notification_events
-- ---------------------------------------------------------------------------
-- MATRIZ DE TRANSIÇÕES:
--   pending   -> scheduled | sending | cancelled | failed
--   scheduled -> sending   | cancelled | failed
--   sending   -> sent      | failed  | cancelled
--   sent      -> delivered | failed
--   delivered -> read
--   failed    -> scheduled (RETENTATIVA) | cancelled
--   read / cancelled -> terminais
--
-- REGRAS ADICIONAIS
--   • "Processamento iniciado" considera o estado ANTIGO **ou** o NOVO, de modo
--     que destinatário/template/correlação não possam mudar na MESMA atualização
--     que inicia o processamento.
--   • pending|scheduled -> sending exige attempt_count = anterior + 1.
--   • failed -> scheduled PRESERVA o contador: um 'scheduled' apos falha pode
--     legitimamente ter attempt_count >= 1 (scheduled inicial tem 0).
--   • scheduled_for só pode ser reescrito EXATAMENTE em failed -> scheduled.
-- ===========================================================================
create table public.notification_events (
  id                       uuid        primary key default pg_catalog.gen_random_uuid(),
  channel                  text        not null,
  recipient_user_id        uuid        null,
  recipient_address        text        null,
  template_key             text        not null,
  template_data            jsonb       not null default '{}'::jsonb,
  status                   text        not null default 'pending',
  attempt_count            integer     not null default 0,
  scheduled_for            timestamptz null,
  sent_at                  timestamptz null,
  delivered_at             timestamptz null,
  read_at                  timestamptz null,
  first_failed_at          timestamptz null,   -- primeira falha (imutavel)
  last_failed_at           timestamptz null,   -- falha mais recente (avanca)
  error_code               text        null,   -- INTERNO
  error_message            text        null,   -- INTERNO
  provider                 text        null,   -- INTERNO
  provider_message_id      text        null,   -- INTERNO
  idempotency_key          text        not null,
  -- Retentativa que exigiu NOVO evento (envio externo ja realizado no anterior).
  retry_of_event_id        uuid        null
                             references public.notification_events(id) on delete restrict,
  correlation_entity_type  text        null,
  correlation_entity_id    text        null,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint notification_events_channel_allowed check (channel in ('email','whatsapp','in_app')),
  constraint notification_events_status_allowed check (
    status in ('pending','scheduled','sending','sent','delivered','read','failed','cancelled')
  ),
  constraint notification_events_template_nonempty check (length(btrim(template_key)) > 0),
  constraint notification_events_idem_nonempty     check (length(btrim(idempotency_key)) > 0),
  constraint notification_events_attempt_nao_neg   check (attempt_count >= 0),
  constraint notification_events_data_objeto       check (jsonb_typeof(template_data) = 'object'),
  constraint notification_events_data_limite       check (length(template_data::text) <= 8192),

  constraint notification_events_destinatario check (
    (channel = 'in_app'
       and recipient_user_id is not null
       and recipient_address is null)
    or
    (channel in ('email','whatsapp')
       and (recipient_user_id is not null or recipient_address is not null))
  ),
  constraint notification_events_endereco_no_envio check (
    channel = 'in_app'
    or status in ('pending','scheduled','cancelled')
    or recipient_address is not null
  ),

  constraint notification_events_st_scheduled check (
    status <> 'scheduled' or scheduled_for is not null),
  constraint notification_events_st_sent check (
    status <> 'sent' or sent_at is not null),
  constraint notification_events_st_delivered check (
    status <> 'delivered' or (sent_at is not null and delivered_at is not null)),
  constraint notification_events_st_read check (
    status <> 'read' or (sent_at is not null and delivered_at is not null and read_at is not null)),
  constraint notification_events_st_failed check (
    status <> 'failed' or (first_failed_at is not null and last_failed_at is not null)),
  -- Ambos os marcos de falha existem juntos ou nao existem.
  constraint notification_events_falha_par check (
    (first_failed_at is null) = (last_failed_at is null)),
  constraint notification_events_erro_tamanho check (
    (error_code is null or length(error_code) <= 100)
    and (error_message is null or length(error_message) <= 2000)),

  constraint notification_events_ts_sent      check (sent_at is null or sent_at >= created_at),
  constraint notification_events_ts_delivered check (
    delivered_at is null or (sent_at is not null and delivered_at >= sent_at)),
  constraint notification_events_ts_read check (
    read_at is null or (delivered_at is not null and read_at >= delivered_at)),
  -- Nao referencia a propria linha.
  constraint notification_events_retry_nao_self check (
    retry_of_event_id is null or retry_of_event_id <> id),
  -- Timestamps nunca existem antes do estado correspondente.
  constraint notification_events_sent_estado check (
    sent_at is null or status not in ('pending','scheduled','sending')),
  constraint notification_events_delivered_estado check (
    delivered_at is null or status in ('delivered','read')),
  constraint notification_events_read_estado check (
    read_at is null or status = 'read'),
  -- Dados do provedor nunca existem antes do envio comecar.
  constraint notification_events_provider_estado check (
    (provider_message_id is null and provider is null)
    or status not in ('pending','scheduled')),
  constraint notification_events_ts_first_failed check (
    first_failed_at is null or first_failed_at >= created_at),
  constraint notification_events_ts_last_failed check (
    last_failed_at is null or (first_failed_at is not null and last_failed_at >= first_failed_at))
);

create unique index uq_notification_events_idempotency
  on public.notification_events (channel, idempotency_key);

create index idx_notification_events_status on public.notification_events (status, scheduled_for);
create index idx_notification_events_recip  on public.notification_events (recipient_user_id);
create index idx_notification_events_correl on public.notification_events (correlation_entity_type, correlation_entity_id);
-- Cada evento pode ter NO MAXIMO UMA retentativa direta: o indice unico
-- parcial impede ramificacao da cadeia. Ele tambem atende as consultas por
-- retry_of_event_id, portanto NAO se mantem um indice simples redundante.
create unique index uq_notification_events_retry_parent
  on public.notification_events (retry_of_event_id)
  where retry_of_event_id is not null;

create trigger trg_notification_events_updated
  before update on public.notification_events
  for each row execute function public.fase2a_touch_updated_at();

create function public.notification_events_protect()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_iniciado_old boolean;
  v_iniciado_new boolean;
  v_iniciado     boolean;
  v_transicao    text;
  v_mudou        boolean;
  v_ant          public.notification_events;
  v_filho_id     uuid;
  v_permitidas   text[] := array[
    'pending>scheduled','pending>sending','pending>cancelled','pending>failed',
    'scheduled>sending','scheduled>cancelled','scheduled>failed',
    'sending>sent','sending>failed','sending>cancelled',
    'sent>delivered','sent>failed',
    'delivered>read',
    'failed>scheduled','failed>cancelled'
  ];
begin
  -- =====================================================================
  -- INSERT: a maquina de estados tambem vale na criacao. So se cria em
  -- pending ou scheduled; nenhum marco de progresso pode vir preenchido.
  -- =====================================================================
  if tg_op = 'INSERT' then
    if new.status not in ('pending','scheduled') then
      raise exception
        'Notificacao so pode ser criada como pending ou scheduled (recebido: %). Cancelamento e demais estados exigem transicao auditavel.',
        new.status;
    end if;
    if new.attempt_count <> 0 then
      raise exception 'attempt_count deve comecar em 0 (recebido: %).', new.attempt_count;
    end if;
    if new.status = 'pending' and new.scheduled_for is not null then
      raise exception 'Criacao em pending exige scheduled_for NULL.';
    end if;
    if new.status = 'scheduled' and new.scheduled_for is null then
      raise exception 'Criacao em scheduled exige scheduled_for preenchido.';
    end if;
    if new.sent_at is not null or new.delivered_at is not null or new.read_at is not null
    or new.first_failed_at is not null or new.last_failed_at is not null then
      raise exception
        'Criacao nao pode trazer marcos de envio, entrega, leitura ou falha preenchidos.';
    end if;
    if new.provider is not null or new.provider_message_id is not null
    or new.error_code is not null or new.error_message is not null then
      raise exception
        'Criacao nao pode trazer provider, provider_message_id ou dados de erro preenchidos.';
    end if;

    -- Cadeia de retentativa: o evento anterior precisa justificar um NOVO
    -- evento e ser integralmente equivalente ao atual.
    if new.retry_of_event_id is not null then
      if new.retry_of_event_id = new.id then
        raise exception 'retry_of_event_id nao pode referenciar a propria linha.';
      end if;

      -- BLOQUEIO DE LINHA (FOR SHARE): impede UPDATE/DELETE concorrente do
      -- evento anterior entre a validacao e a insercao desta retentativa.
      -- Sem ele, o anterior poderia sair de 'failed' (p.ex. para 'cancelled')
      -- logo apos a checagem, deixando uma cadeia de retentativa incoerente.
      -- E um bloqueio de LINHA, nunca da tabela inteira.
      select * into v_ant from public.notification_events
       where id = new.retry_of_event_id
       for share;
      if not found then
        raise exception 'retry_of_event_id % nao existe.', new.retry_of_event_id;
      end if;

      -- O anterior tem de estar TERMINAL em failed.
      if v_ant.status <> 'failed' then
        raise exception
          'retry_of_event_id deve apontar para evento com status failed (encontrado: %).', v_ant.status;
      end if;

      -- E precisa haver EVIDENCIA de envio externo: caso contrario a
      -- retentativa deveria permanecer no mesmo evento (failed -> scheduled).
      if v_ant.sent_at is null and v_ant.provider_message_id is null then
        raise exception
          'Evento % falhou ANTES de qualquer envio externo: use a transicao failed -> scheduled no proprio evento, sem criar um novo.',
          v_ant.id;
      end if;

      -- Equivalencia integral com o evento anterior.
      if v_ant.channel is distinct from new.channel then
        raise exception 'Retentativa deve usar o mesmo channel (% vs %).', new.channel, v_ant.channel;
      end if;
      if v_ant.recipient_user_id is distinct from new.recipient_user_id then
        raise exception 'Retentativa deve manter o mesmo recipient_user_id.';
      end if;
      if v_ant.recipient_address is distinct from new.recipient_address then
        raise exception 'Retentativa deve manter o mesmo recipient_address.';
      end if;
      if v_ant.template_key is distinct from new.template_key then
        raise exception 'Retentativa deve manter o mesmo template_key.';
      end if;
      if v_ant.template_data is distinct from new.template_data then
        raise exception 'Retentativa deve manter o mesmo template_data.';
      end if;
      if v_ant.correlation_entity_type is distinct from new.correlation_entity_type
      or v_ant.correlation_entity_id   is distinct from new.correlation_entity_id then
        raise exception 'Retentativa deve preservar a mesma correlacao empresarial.';
      end if;

      -- Nada e reaproveitado do envio anterior.
      if v_ant.idempotency_key = new.idempotency_key then
        raise exception 'Retentativa exige NOVA idempotency_key (a anterior nao pode ser reutilizada).';
      end if;
      if new.provider_message_id is not null then
        raise exception 'Retentativa nao pode reutilizar provider_message_id.';
      end if;
    end if;

    return new;
  end if;

  -- =====================================================================
  -- UPDATE
  -- =====================================================================
  if new.idempotency_key is distinct from old.idempotency_key then
    raise exception 'idempotency_key e imutavel (id=%).', old.id;
  end if;
  if new.channel is distinct from old.channel then
    raise exception 'channel e imutavel (id=%).', old.id;
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'created_at e imutavel (id=%).', old.id;
  end if;
  if new.retry_of_event_id is distinct from old.retry_of_event_id then
    raise exception 'retry_of_event_id e imutavel (id=%).', old.id;
  end if;

  -- ---------------------------------------------------------------------
  -- CONGELAMENTO DO EVENTO PAI: se já existe um filho apontando para esta
  -- linha, ela e a ORIGEM de uma cadeia de retentativa e precisa permanecer
  -- coerente com o filho. Le-se o filho com FOR SHARE (bloqueio de LINHA,
  -- nunca da tabela) para impedir que ele seja removido/alterado em paralelo
  -- enquanto validamos.
  -- ---------------------------------------------------------------------
  select f.id into v_filho_id
    from public.notification_events f
   where f.retry_of_event_id = old.id
   limit 1
   for share of f;

  if v_filho_id is not null then
    if new.status <> 'failed' then
      raise exception
        'Evento % e origem da retentativa % e deve permanecer failed (tentativa de ir para %).',
        old.id, v_filho_id, new.status;
    end if;
    if new.sent_at             is distinct from old.sent_at
    or new.provider_message_id is distinct from old.provider_message_id
    or new.channel             is distinct from old.channel
    or new.recipient_user_id   is distinct from old.recipient_user_id
    or new.recipient_address   is distinct from old.recipient_address
    or new.template_key        is distinct from old.template_key
    or new.template_data       is distinct from old.template_data
    or new.correlation_entity_type is distinct from old.correlation_entity_type
    or new.correlation_entity_id   is distinct from old.correlation_entity_id then
      raise exception
        'Evento % possui a retentativa %: os campos usados na validacao de equivalencia (sent_at, provider_message_id, channel, destinatario, template, template_data e correlacao) nao podem ser alterados.',
        old.id, v_filho_id;
    end if;
  end if;

  v_mudou     := new.status is distinct from old.status;
  v_transicao := old.status || '>' || new.status;

  if v_mudou and not (v_transicao = any(v_permitidas)) then
    raise exception 'Transicao de status invalida: % (id=%).', v_transicao, old.id;
  end if;

  -- Retentativa NO MESMO evento so antes de qualquer envio externo.
  if v_transicao = 'failed>scheduled' then
    if old.sent_at is not null
    or old.delivered_at is not null
    or old.provider_message_id is not null then
      raise exception
        'failed -> scheduled nao e permitido apos envio externo (id=%): sent_at/delivered_at/provider_message_id ja existem. Crie um NOVO notification_event com nova idempotency_key e retry_of_event_id apontando para este.',
        old.id;
    end if;
  end if;

  -- attempt_count: +1 exatamente ao entrar em sending.
  if v_mudou and v_transicao in ('pending>sending','scheduled>sending') then
    if new.attempt_count is distinct from old.attempt_count + 1 then
      raise exception
        'Entrada em sending exige attempt_count = anterior + 1 (id=%): % -> %.',
        old.id, old.attempt_count, new.attempt_count;
    end if;
  elsif new.attempt_count is distinct from old.attempt_count then
    raise exception
      'attempt_count so pode mudar ao entrar em sending (id=%, transicao=%): % -> %.',
      old.id, v_transicao, old.attempt_count, new.attempt_count;
  end if;

  -- Congelamento apos o inicio do processamento (estado antigo OU novo).
  v_iniciado_old := (old.attempt_count > 0) or (old.status not in ('pending','scheduled'));
  v_iniciado_new := (new.attempt_count > 0) or (new.status not in ('pending','scheduled'));
  v_iniciado := v_iniciado_old or v_iniciado_new;

  if v_iniciado then
    if new.recipient_user_id       is distinct from old.recipient_user_id
    or new.recipient_address       is distinct from old.recipient_address
    or new.template_key            is distinct from old.template_key
    or new.template_data           is distinct from old.template_data
    or new.correlation_entity_type is distinct from old.correlation_entity_type
    or new.correlation_entity_id   is distinct from old.correlation_entity_id then
      raise exception
        'Destinatario, template, template_data e correlacao congelam no inicio do processamento (id=%).', old.id;
    end if;
  end if;

  -- scheduled_for: apenas pending>scheduled e failed>scheduled.
  if new.scheduled_for is distinct from old.scheduled_for then
    if not (v_mudou and v_transicao in ('pending>scheduled','failed>scheduled')) then
      raise exception
        'scheduled_for so pode ser definido/alterado em pending->scheduled ou failed->scheduled (id=%, transicao=%).',
        old.id, v_transicao;
    end if;
  end if;

  -- Marcos de progresso: preenchidos apenas na transicao correspondente e
  -- nunca removidos ou reescritos.
  if old.sent_at is not null and new.sent_at is distinct from old.sent_at then
    raise exception 'sent_at preenchido nao pode ser removido nem reescrito (id=%).', old.id;
  end if;
  if old.sent_at is null and new.sent_at is not null and v_transicao <> 'sending>sent' then
    raise exception 'sent_at so pode ser preenchido na transicao sending -> sent (id=%).', old.id;
  end if;

  if old.delivered_at is not null and new.delivered_at is distinct from old.delivered_at then
    raise exception 'delivered_at preenchido nao pode ser removido nem reescrito (id=%).', old.id;
  end if;
  if old.delivered_at is null and new.delivered_at is not null and v_transicao <> 'sent>delivered' then
    raise exception 'delivered_at so pode ser preenchido na transicao sent -> delivered (id=%).', old.id;
  end if;

  if old.read_at is not null and new.read_at is distinct from old.read_at then
    raise exception 'read_at preenchido nao pode ser removido nem reescrito (id=%).', old.id;
  end if;
  if old.read_at is null and new.read_at is not null and v_transicao <> 'delivered>read' then
    raise exception 'read_at so pode ser preenchido na transicao delivered -> read (id=%).', old.id;
  end if;

  -- Falhas: first imutavel, last avanca; fora da entrada em failed, imutaveis.
  if v_mudou and new.status = 'failed' then
    if old.first_failed_at is null then
      if new.first_failed_at is null or new.last_failed_at is null then
        raise exception
          'Primeira falha exige first_failed_at e last_failed_at preenchidos (id=%).', old.id;
      end if;
    else
      if new.first_failed_at is distinct from old.first_failed_at then
        raise exception 'first_failed_at e imutavel apos a primeira falha (id=%).', old.id;
      end if;
      if new.last_failed_at is null or new.last_failed_at <= old.last_failed_at then
        raise exception
          'Nova falha exige last_failed_at posterior ao anterior (id=%): % -> %.',
          old.id, old.last_failed_at, new.last_failed_at;
      end if;
    end if;
  else
    if new.first_failed_at is distinct from old.first_failed_at then
      raise exception
        'first_failed_at so pode ser definido na entrada em failed (id=%, transicao=%).', old.id, v_transicao;
    end if;
    if new.last_failed_at is distinct from old.last_failed_at then
      raise exception
        'last_failed_at so pode avancar na entrada em failed (id=%, transicao=%).', old.id, v_transicao;
    end if;
  end if;

  -- Provedor: preenchimento unico, apenas em sending/sent.
  if old.provider is not null and new.provider is distinct from old.provider then
    raise exception 'provider preenchido nao pode ser removido nem substituido (id=%).', old.id;
  end if;
  if old.provider_message_id is not null
     and new.provider_message_id is distinct from old.provider_message_id then
    raise exception 'provider_message_id preenchido nao pode ser removido nem substituido (id=%).', old.id;
  end if;
  if (old.provider is null and new.provider is not null)
     or (old.provider_message_id is null and new.provider_message_id is not null) then
    if new.status not in ('sending','sent') then
      raise exception
        'provider/provider_message_id so podem ser preenchidos em sending ou sent (id=%, status=%).',
        old.id, new.status;
    end if;
  end if;

  -- Erros: apenas na entrada em failed.
  if new.error_code    is distinct from old.error_code
  or new.error_message is distinct from old.error_message then
    if not (v_mudou and new.status = 'failed') then
      raise exception
        'error_code/error_message so podem ser definidos na entrada em failed (id=%, transicao=%).',
        old.id, v_transicao;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_notification_events_protect
  before insert or update on public.notification_events
  for each row execute function public.notification_events_protect();

-- ===========================================================================
-- E. Índice único parcial em site_profiles.auth_user_id
-- ===========================================================================
create unique index uq_site_profiles_auth_user_id
  on public.site_profiles (auth_user_id)
  where auth_user_id is not null;

-- ===========================================================================
-- F. RPCs — leitura sanitizada e escrita controlada
-- ===========================================================================

-- F.1 Versão vigente (uso interno/backend).
create function public.current_legal_document(p_doc_type text)
returns public.legal_documents
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select d.*
    from public.legal_documents d
   where d.doc_type = p_doc_type
     and d.status = 'published'
     and d.effective_from <= now()
     and (d.effective_to is null or d.effective_to > now())
   order by d.effective_from desc, d.published_at desc, d.id
   limit 1;
$$;

-- F.2 Exposição PÚBLICA sanitizada: somente versões vigentes.
create function public.get_current_legal_documents()
returns table (
  doc_type           text,
  version            text,
  title              text,
  content            text,
  content_url        text,
  content_hash       text,
  is_material_change boolean,
  effective_from     timestamptz,
  effective_to       timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select d.doc_type, d.version, d.title, d.content, d.content_url, d.content_hash,
         d.is_material_change, d.effective_from, d.effective_to
    from public.legal_documents d
   where d.status = 'published'
     and d.effective_from <= now()
     and (d.effective_to is null or d.effective_to > now())
   order by d.doc_type;
$$;

-- F.3 Histórico do usuário comum: nunca revela versão futura nem rascunho.
create function public.legal_document_versions(p_doc_type text)
returns table (
  doc_type           text,
  version            text,
  title              text,
  content            text,
  content_url        text,
  content_hash       text,
  is_material_change boolean,
  effective_from     timestamptz,
  effective_to       timestamptz,
  status             text
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select d.doc_type, d.version, d.title, d.content, d.content_url, d.content_hash,
         d.is_material_change, d.effective_from, d.effective_to, d.status
    from public.legal_documents d
   where auth.uid() is not null
     and d.doc_type = p_doc_type
     and d.status in ('published','archived')
     and d.effective_from is not null
     and d.effective_from <= now()
   order by d.effective_from desc, d.version desc;
$$;

-- F.4 Comprovante dos próprios aceites (sem evidence, ip ou user_agent).
create function public.get_my_legal_acceptances()
returns table (
  acceptance_id      uuid,
  doc_type           text,
  version            text,
  title              text,
  content_hash       text,
  is_material_change boolean,
  context            text,
  accepted_at        timestamptz,
  revoked_at         timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select a.id, d.doc_type, d.version, d.title, d.content_hash,
         d.is_material_change, a.context, a.accepted_at, a.revoked_at
    from public.legal_acceptances a
    join public.legal_documents  d on d.id = a.legal_document_id
   where auth.uid() is not null
     and a.auth_user_id = auth.uid()
   order by a.accepted_at desc;
$$;

-- F.5 Notificações internas do próprio destinatário (sem template_data,
--     provider nem erros internos).
create function public.get_my_notifications()
returns table (
  notification_id         uuid,
  channel                 text,
  template_key            text,
  status_publico          text,
  correlation_entity_type text,
  correlation_entity_id   text,
  created_at              timestamptz,
  sent_at                 timestamptz,
  read_at                 timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select n.id, n.channel, n.template_key,
         case
           when n.status in ('pending','scheduled','sending') then 'processing'
           when n.status in ('sent','delivered')              then 'delivered'
           when n.status = 'read'                             then 'read'
           when n.status = 'failed'                           then 'failed'
           when n.status = 'cancelled'                        then 'cancelled'
         end,
         n.correlation_entity_type, n.correlation_entity_id,
         n.created_at, n.sent_at, n.read_at
    from public.notification_events n
   where auth.uid() is not null
     and n.recipient_user_id = auth.uid()
   order by n.created_at desc;
$$;

-- F.6 RPC PÚBLICA de aceite — contexto FIXO de conta provisória.
--     O navegador NÃO escolhe contexto, versão, identidade, data nem origem.
--     Documentos empresariais (truthfulness_declaration,
--     document_analysis_authorization, representation_declaration) NÃO passam
--     por aqui: serão registrados pelo backend do Marco 2, vinculados a uma
--     partner_application real.
create function public.record_legal_acceptance(
  p_doc_type      text,
  p_declared_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_user      uuid := auth.uid();
  v_doc       public.legal_documents;
  v_id        uuid;
  v_ctx       text := 'provisional_account';   -- FIXO server-side
  v_declarado jsonb := coalesce(p_declared_data, '{}'::jsonb);
  v_chave     text;
  v_allow     text[] := array['ui_locale','form_version','screen','client_timezone'];
begin
  if v_user is null then
    raise exception 'Aceite exige usuario autenticado.';
  end if;

  -- Somente documentos da conta provisória.
  if p_doc_type not in ('privacy_notice','provisional_account_terms') then
    raise exception
      'Tipo de documento "%" nao pode ser aceito por esta RPC publica. Documentos empresariais serao registrados pelo backend do Marco 2, vinculados a uma partner_application real.',
      p_doc_type;
  end if;

  if jsonb_typeof(v_declarado) <> 'object' then
    raise exception 'p_declared_data deve ser um objeto JSON.';
  end if;
  if length(v_declarado::text) > 1024 then
    raise exception 'p_declared_data excede o limite de 1024 caracteres.';
  end if;
  for v_chave in select jsonb_object_keys(v_declarado) loop
    if not (v_chave = any(v_allow)) then
      raise exception
        'Chave "%" nao permitida em p_declared_data. Permitidas: %.', v_chave, array_to_string(v_allow, ', ');
    end if;
    if jsonb_typeof(v_declarado -> v_chave) not in ('string','number','boolean') then
      raise exception 'Valor de "%" deve ser escalar.', v_chave;
    end if;
  end loop;

  v_doc := public.current_legal_document(p_doc_type);
  if v_doc.id is null then
    raise exception 'Nao ha versao publicada e vigente para o documento "%".', p_doc_type;
  end if;

  insert into public.legal_acceptances
    (subject_type, subject_id, linked_auth_user_id, auth_user_id, legal_document_id,
     accepted_at, context, origin, evidence)
  values
    ('auth_user', v_user, v_user, v_user, v_doc.id,
     now(), v_ctx, 'rpc',
     jsonb_build_object(
       'server', jsonb_build_object(
         'recorded_at',  now(),
         'source',       'record_legal_acceptance',
         'doc_type',     v_doc.doc_type,
         'doc_version',  v_doc.version,
         'content_hash', v_doc.content_hash
       ),
       'client_declared', v_declarado
     ))
  -- Alvo EXPLÍCITO correspondente ao índice parcial de aceite ativo.
  on conflict (subject_type, subject_id, legal_document_id, context)
    where revoked_at is null
    do nothing
  returning id into v_id;

  if v_id is null then
    select a.id into v_id
      from public.legal_acceptances a
     where a.subject_type = 'auth_user'
       and a.subject_id = v_user
       and a.legal_document_id = v_doc.id
       and a.context = v_ctx
       and a.revoked_at is null
     limit 1;
  end if;

  return v_id;
end;
$$;

-- F.7 Escrita de auditoria — backend/service_role.
create function public.write_audit_log(
  p_action          text,
  p_entity_type     text,
  p_entity_id       text  default null,
  p_actor_user_id   uuid  default null,
  p_actor_role      text  default null,
  p_previous_state  jsonb default null,
  p_new_state       jsonb default null,
  p_justification   text  default null,
  p_correlation_id  uuid  default null,
  p_source          text  default 'backend',
  p_metadata        jsonb default '{}'::jsonb,
  p_corrects_log_id uuid  default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_id uuid;
begin
  insert into public.audit_logs
    (action, entity_type, entity_id, actor_user_id, actor_role,
     previous_state, new_state, justification, correlation_id, source,
     metadata, corrects_log_id)
  values
    (p_action, p_entity_type, p_entity_id,
     coalesce(p_actor_user_id, auth.uid()), p_actor_role,
     p_previous_state, p_new_state, p_justification, p_correlation_id, p_source,
     coalesce(p_metadata, '{}'::jsonb), p_corrects_log_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- ===========================================================================
-- G. RLS, GRANTS E PRIVILÉGIOS DA SERVICE_ROLE
-- ---------------------------------------------------------------------------
-- BYPASSRLS **não** substitui GRANT (o papel precisa de privilégio SQL) e GRANT
-- **não** substitui BYPASSRLS neste desenho (não há policy para service_role).
-- Ambos são necessários. A chave da service_role é exclusiva do backend.
-- ===========================================================================
alter table public.legal_documents     enable row level security;
alter table public.legal_acceptances   enable row level security;
alter table public.audit_logs          enable row level security;
alter table public.notification_events enable row level security;

-- G.1 Zera privilégios de TODOS os papéis não-proprietários, inclusive
--     service_role (nada é herdado ou presumido).
revoke all on table public.legal_documents     from public, anon, authenticated, service_role;
revoke all on table public.legal_acceptances   from public, anon, authenticated, service_role;
revoke all on table public.audit_logs          from public, anon, authenticated, service_role;
revoke all on table public.notification_events from public, anon, authenticated, service_role;

-- G.2 Policies (defesa em profundidade; o cliente não tem grant nas tabelas).
create policy legal_documents_admin_all
  on public.legal_documents
  for all
  to authenticated
  using (public.is_site_admin())
  with check (public.is_site_admin());

create policy legal_acceptances_select_own
  on public.legal_acceptances
  for select
  to authenticated
  using (auth_user_id = auth.uid() or public.is_site_admin());

create policy audit_logs_admin_read
  on public.audit_logs
  for select
  to authenticated
  using (public.is_site_admin());

create policy notification_events_select_own
  on public.notification_events
  for select
  to authenticated
  using (recipient_user_id = auth.uid() or public.is_site_admin());

-- G.3 SERVICE_ROLE — privilégios mínimos, concedidos APÓS o revoke acima.
--     Sem DELETE, TRUNCATE, REFERENCES ou TRIGGER em nenhuma tabela.
grant select, insert, update on table public.legal_documents     to service_role;
grant select, insert, update on table public.legal_acceptances   to service_role;
grant select, insert         on table public.audit_logs          to service_role;
grant select, insert, update on table public.notification_events to service_role;

-- G.4 ACLs de FUNÇÃO — zeradas antes de qualquer concessão.
--     Não se presume que uma função recém-criada tenha apenas o EXECUTE padrão
--     de PUBLIC: revogamos explicitamente de todos os papéis não-proprietários.
revoke all on function public.fase2a_touch_updated_at()          from public, anon, authenticated, service_role;
revoke all on function public.legal_documents_protect()          from public, anon, authenticated, service_role;
revoke all on function public.legal_documents_check_overlap()    from public, anon, authenticated, service_role;
revoke all on function public.legal_acceptances_protect()        from public, anon, authenticated, service_role;
revoke all on function public.audit_logs_block_mutation()        from public, anon, authenticated, service_role;
revoke all on function public.notification_events_protect()      from public, anon, authenticated, service_role;
revoke all on function public.current_legal_document(text)       from public, anon, authenticated, service_role;
revoke all on function public.get_current_legal_documents()      from public, anon, authenticated, service_role;
revoke all on function public.legal_document_versions(text)      from public, anon, authenticated, service_role;
revoke all on function public.get_my_legal_acceptances()         from public, anon, authenticated, service_role;
revoke all on function public.get_my_notifications()             from public, anon, authenticated, service_role;
revoke all on function public.record_legal_acceptance(text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.write_audit_log(
  text, text, text, uuid, text, jsonb, jsonb, text, uuid, text, jsonb, uuid
) from public, anon, authenticated, service_role;

-- G.4.1 EXECUTE para o cliente autenticado — somente RPCs sanitizadas.
grant execute on function public.record_legal_acceptance(text, jsonb) to authenticated;

grant execute on function public.get_my_legal_acceptances() to authenticated;

grant execute on function public.get_my_notifications() to authenticated;

grant execute on function public.legal_document_versions(text) to authenticated;

-- Documentos vigentes: público (o cadastro ocorre antes do login).
grant execute on function public.get_current_legal_documents() to anon, authenticated;

-- G.5 EXECUTE para o backend.
grant execute on function public.current_legal_document(text) to service_role;

grant execute on function public.write_audit_log(
  text, text, text, uuid, text, jsonb, jsonb, text, uuid, text, jsonb, uuid
) to service_role;

-- G.6 Funções de trigger permanecem sem EXECUTE (revogadas em G.4; nenhum
--     grant lhes é concedido em momento algum).

-- ===========================================================================
-- H. ASSERTIVA FINAL DE SEGURANÇA (dentro da MESMA transação, antes do COMMIT)
-- ---------------------------------------------------------------------------
-- Qualquer divergência lança exceção e provoca ROLLBACK integral: a fundação
-- nunca fica parcialmente aplicada.
-- ===========================================================================
do $assert$
declare
  v_err  text[] := array[]::text[];
  v_i    int;
  v_nome text;
  v_par  text;
  v_sig  text;
  v_esp  text;
  v_rec  record;
  v_oid  oid;
  v_dono text;
  v_txt  text;
  v_bool boolean;
  v_aut  text[];
  v_ach  text[];
  v_priv text[] := array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  -- Papeis PREDEFINIDOS do PostgreSQL (NOLOGIN, capacidades globais inerentes).
  -- Sua simples existencia NAO e divergencia; o risco e um papel de aplicacao
  -- poder herda-los ou assumi-los via SET ROLE.
  v_predef text[] := array[
    'pg_read_all_data','pg_write_all_data','pg_monitor','pg_read_all_settings',
    'pg_read_all_stats','pg_stat_scan_tables','pg_database_owner',
    'pg_signal_backend','pg_checkpoint','pg_maintain','pg_use_reserved_connections',
    'pg_create_subscription','pg_execute_server_program','pg_read_server_files',
    'pg_write_server_files'
  ];
  -- Papeis de APLICACAO conhecidos (allowlist explicita e documentada).
  v_app    text[] := array['anon','authenticated','service_role'];
  -- Papeis INTERNOS da plataforma Supabase (allowlist EXATA e restrita — SOMENTE
  -- estes dois nomes; NUNCA um padrao amplo por prefixo "supabase_"). Recebem
  -- SELECT global via pg_read_all_data. NAO sao papeis de aplicacao. A migration
  -- NAO os cria, NAO os altera e NAO revoga privilegios deles. Fail-closed: se
  -- existirem com perfil/memberships divergentes, BLOQUEIA.
  v_supabase_read_roles text[] := array['supabase_etl_admin','supabase_read_only_user'];
  v_repl_esperado boolean;   -- rolreplication esperado por papel interno
  v_perfil_ok     boolean;
  v_atuante boolean;
begin
  -- ---------------------------------------------------------------------
  -- H.0 Papeis de aplicacao NAO podem herdar nem assumir papeis predefinidos
  -- ---------------------------------------------------------------------
  foreach v_nome in array v_app loop
    if exists (select 1 from pg_roles where rolname = v_nome) then
      foreach v_esp in array v_predef loop
        if exists (select 1 from pg_roles where rolname = v_esp) then
          if pg_has_role(v_nome, v_esp, 'USAGE') then
            v_err := v_err || format(
              'Papel de aplicacao %s HERDA o papel predefinido %s (privilegios globais inerentes).',
              v_nome, v_esp);
          elsif pg_has_role(v_nome, v_esp, 'MEMBER') then
            v_err := v_err || format(
              'Papel de aplicacao %s pode assumir (SET ROLE) o papel predefinido %s.', v_nome, v_esp);
          end if;
        end if;
      end loop;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- H.0b Papeis INTERNOS da plataforma Supabase (allowlist exata, fail-closed)
  -- ---------------------------------------------------------------------
  -- Validacao EXPLICITA (nao mero "ignore"): se o papel existir, exige o perfil
  -- e as memberships esperados; se divergir, BLOQUEIA; se nao existir, nao cria
  -- e nao bloqueia apenas pela ausencia. Somente os dois nomes EXATOS recebem
  -- este tratamento (jamais um padrao por prefixo "supabase_").
  foreach v_nome in array v_supabase_read_roles loop
    if exists (select 1 from pg_roles where rolname = v_nome) then
      -- rolreplication esperado difere por papel: etl_admin=true, read_only_user=false
      v_repl_esperado := (v_nome = 'supabase_etl_admin');
      select
        (    r.rolsuper       = false
         and r.rolcanlogin    = true
         and r.rolbypassrls   = true
         and r.rolreplication = v_repl_esperado
         and pg_has_role(r.rolname, 'pg_read_all_data', 'MEMBER')
         and not (exists (select 1 from pg_roles where rolname='pg_write_all_data')
                  and pg_has_role(r.rolname, 'pg_write_all_data', 'MEMBER')))
        into v_perfil_ok
      from pg_roles r
      where r.rolname = v_nome;

      if not coalesce(v_perfil_ok, false) then
        v_err := v_err || format(
          'Papel interno Supabase %s existe com perfil/memberships divergentes do esperado (rolsuper=false, rolcanlogin=true, rolbypassrls=true, rolreplication=%s, membro de pg_read_all_data, NAO membro de pg_write_all_data).',
          v_nome, v_repl_esperado);
      end if;
    else
      raise notice '[info] papel interno Supabase % ausente: sem excecao aplicada (nao criado, nao bloqueado apenas pela ausencia).', v_nome;
    end if;
  end loop;

  -- Isolamento: papeis de APLICACAO nao podem herdar (USAGE) nem assumir (MEMBER)
  -- os papeis internos da plataforma. Fecha o vetor de escalonamento via SET ROLE.
  foreach v_nome in array v_app loop
    if exists (select 1 from pg_roles where rolname = v_nome) then
      foreach v_esp in array v_supabase_read_roles loop
        if exists (select 1 from pg_roles where rolname = v_esp) then
          if pg_has_role(v_nome, v_esp, 'USAGE') then
            v_err := v_err || format(
              'Papel de aplicacao %s HERDA o papel interno Supabase %s (leitura global inerente).', v_nome, v_esp);
          elsif pg_has_role(v_nome, v_esp, 'MEMBER') then
            v_err := v_err || format(
              'Papel de aplicacao %s pode assumir (SET ROLE) o papel interno Supabase %s.', v_nome, v_esp);
          end if;
        end if;
      end loop;
    end if;
  end loop;

  -- =====================================================================
  -- H.1 RLS habilitada
  -- =====================================================================
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    if not (select c.relrowsecurity from pg_class c
              join pg_namespace n on n.oid=c.relnamespace
             where n.nspname='public' and c.relname=v_nome) then
      v_err := v_err || format('RLS nao habilitada em public.%s.', v_nome);
    end if;
  end loop;

  -- =====================================================================
  -- H.2 Nenhuma view antiga
  -- =====================================================================
  foreach v_nome in array array[
    'my_notifications','my_legal_acceptances','legal_documents_public'
  ] loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                where n.nspname='public' and c.relname=v_nome) then
      v_err := v_err || format('Artefato antigo public.%s presente.', v_nome);
    end if;
  end loop;

  -- =====================================================================
  -- H.3 Policies: schema, tabela, nome, comando, roles, USING e WITH CHECK
  -- =====================================================================
  -- Nenhuma policy adicional nas quatro tabelas, nem nome esperado em outra tabela
  for v_rec in
    select schemaname, tablename, policyname from pg_policies
     where (schemaname='public'
            and tablename in ('legal_documents','legal_acceptances','audit_logs','notification_events'))
        or policyname in ('legal_documents_admin_all','legal_acceptances_select_own',
                          'audit_logs_admin_read','notification_events_select_own')
  loop
    if (v_rec.schemaname || '.' || v_rec.tablename || '/' || v_rec.policyname) not in (
      'public.legal_documents/legal_documents_admin_all',
      'public.legal_acceptances/legal_acceptances_select_own',
      'public.audit_logs/audit_logs_admin_read',
      'public.notification_events/notification_events_select_own'
    ) then
      v_err := v_err || format('Policy inesperada: %s.%s/%s.',
        v_rec.schemaname, v_rec.tablename, v_rec.policyname);
    end if;
  end loop;

  foreach v_par in array array[
    -- tabela | policy | cmd | roles | USING canonico | WITH CHECK canonico ('-' = vazio)
    'legal_documents|legal_documents_admin_all|ALL|authenticated|is_site_admin()|is_site_admin()',
    'legal_acceptances|legal_acceptances_select_own|SELECT|authenticated|auth_user_id=auth.uid()oris_site_admin()|-',
    'audit_logs|audit_logs_admin_read|SELECT|authenticated|is_site_admin()|-',
    'notification_events|notification_events_select_own|SELECT|authenticated|recipient_user_id=auth.uid()oris_site_admin()|-'
  ] loop
    select p.cmd, array_to_string(p.roles, ','),
           lower(replace(replace(replace(replace(replace(coalesce(p.qual,''),' ',''),'public.',''),'::text',''),'(',''),')','')),
           lower(replace(replace(replace(replace(replace(coalesce(p.with_check,''),' ',''),'public.',''),'::text',''),'(',''),')',''))
      into v_txt, v_nome, v_sig, v_esp
      from pg_policies p
     where p.schemaname='public'
       and p.tablename  = split_part(v_par,'|',1)
       and p.policyname = split_part(v_par,'|',2);

    if v_txt is null then
      v_err := v_err || format('Policy esperada ausente: public.%s/%s.',
        split_part(v_par,'|',1), split_part(v_par,'|',2));
    else
      if v_txt <> split_part(v_par,'|',3) then
        v_err := v_err || format('Policy %s: cmd=%s (esperado %s).',
          split_part(v_par,'|',2), v_txt, split_part(v_par,'|',3));
      end if;
      if v_nome <> split_part(v_par,'|',4) then
        v_err := v_err || format('Policy %s: roles=[%s] (esperado exatamente [%s]).',
          split_part(v_par,'|',2), v_nome, split_part(v_par,'|',4));
      end if;

      -- comparacao canonica: remove espacos e parenteses dos dois lados
      if v_sig is distinct from
         replace(replace(replace(lower(split_part(v_par,'|',5)),' ',''),'(',''),')','') then
        v_err := v_err || format('Policy %s: USING canonico=[%s] (esperado [%s]).',
          split_part(v_par,'|',2), v_sig,
          replace(replace(replace(lower(split_part(v_par,'|',5)),' ',''),'(',''),')',''));
      end if;

      if split_part(v_par,'|',6) = '-' then
        if coalesce(v_esp,'') <> '' then
          v_err := v_err || format('Policy %s: WITH CHECK inesperado=[%s].',
            split_part(v_par,'|',2), v_esp);
        end if;
      else
        if v_esp is distinct from
           replace(replace(replace(lower(split_part(v_par,'|',6)),' ',''),'(',''),')','') then
          v_err := v_err || format('Policy %s: WITH CHECK canonico=[%s] (esperado [%s]).',
            split_part(v_par,'|',2), v_esp,
            replace(replace(replace(lower(split_part(v_par,'|',6)),' ',''),'(',''),')',''));
        end if;
      end if;
    end if;
    v_txt := null; v_nome := null; v_sig := null; v_esp := null;
  end loop;

  -- =====================================================================
  -- H.4 Objetos essenciais: trigger INSERT+UPDATE e indice de retentativa
  -- =====================================================================
  if not exists (
    select 1 from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='notification_events'
       and tg.tgname='trg_notification_events_protect'
       and not tg.tgisinternal
       and tg.tgtype::int = 23             -- ROW + BEFORE + INSERT + UPDATE
       and tg.tgfoid = to_regprocedure('public.notification_events_protect()')
       and tg.tgenabled = 'O'
  ) then
    v_err := v_err ||
      'trg_notification_events_protect ausente ou nao cobre BEFORE INSERT OR UPDATE FOR EACH ROW.';
  end if;

  -- Indice UNICO PARCIAL da cadeia de retentativas (impede ramificacao).
  if not exists (
    select 1 from pg_index ix
      join pg_class i on i.oid = ix.indexrelid
      join pg_class t on t.oid = ix.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname='public' and t.relname='notification_events'
       and i.relname='uq_notification_events_retry_parent'
       and ix.indisunique
       and ix.indisvalid and ix.indisready and ix.indislive
       and ix.indnatts = 1 and ix.indnkeyatts = 1
       and ix.indexprs is null
       and ix.indpred is not null
       and replace(replace(replace(lower(
             pg_get_expr(ix.indpred, ix.indrelid, true)), ' ', ''), '(', ''), ')', '')
           = 'retry_of_event_idisnotnull'
       and ix.indkey[0] = (select a.attnum from pg_attribute a
                            where a.attrelid='public.notification_events'::regclass
                              and a.attname='retry_of_event_id')
  ) then
    v_err := v_err ||
      'uq_notification_events_retry_parent ausente ou incorreto (esperado UNIQUE (retry_of_event_id) WHERE retry_of_event_id IS NOT NULL, valido/pronto/ativo, sem expressao).';
  end if;

  -- Nenhum evento pai pode ter mais de um filho.
  if exists (
    select 1 from public.notification_events
     where retry_of_event_id is not null
     group by retry_of_event_id having count(*) > 1
  ) then
    v_err := v_err || 'Existe evento com mais de uma retentativa direta (cadeia ramificada).';
  end if;

  -- Trigger de legal_documents deve cobrir INSERT, UPDATE e DELETE.
  -- tgtype esperado = 1(ROW)+2(BEFORE)+4(INSERT)+8(DELETE)+16(UPDATE) = 31
  if not exists (
    select 1 from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname='legal_documents'
       and tg.tgname='trg_legal_documents_protect'
       and not tg.tgisinternal
       and tg.tgtype::int = 31
       and tg.tgfoid = to_regprocedure('public.legal_documents_protect()')
       and tg.tgenabled = 'O'
  ) then
    v_err := v_err ||
      'trg_legal_documents_protect ausente ou nao cobre BEFORE INSERT OR UPDATE OR DELETE FOR EACH ROW.';
  end if;

  -- =====================================================================
  -- H.5 Funcoes SECURITY DEFINER com search_path esperado
  -- =====================================================================
  foreach v_sig in array array[
    'public.legal_documents_protect()','public.legal_documents_check_overlap()',
    'public.legal_acceptances_protect()','public.audit_logs_block_mutation()',
    'public.notification_events_protect()','public.current_legal_document(text)',
    'public.get_current_legal_documents()','public.legal_document_versions(text)',
    'public.get_my_legal_acceptances()','public.get_my_notifications()',
    'public.record_legal_acceptance(text,jsonb)',
    'public.write_audit_log(text,text,text,uuid,text,jsonb,jsonb,text,uuid,text,jsonb,uuid)'
  ] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      v_err := v_err || format('Funcao %s ausente.', v_sig);
    else
      select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '')
        into v_bool, v_txt from pg_proc p where p.oid = v_oid;
      if not coalesce(v_bool,false) then
        v_err := v_err || format('Funcao %s nao e SECURITY DEFINER.', v_sig);
      end if;
      if v_txt <> 'search_path=pg_catalog' then
        v_err := v_err || format('Funcao %s com proconfig [%s] (esperado search_path=pg_catalog).', v_sig, v_txt);
      end if;
    end if;
    v_txt := null; v_bool := null;
  end loop;

  -- =====================================================================
  -- H.6 ACLs das TABELAS — todos os papeis, comparacao EXATA (= ANY)
  -- =====================================================================
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    select pg_get_userbyid(c.relowner) into v_dono
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=v_nome;

    -- grants diretos: so dono e service_role
    for v_rec in
      select coalesce(nullif(a.grantee::regrole::text,'-'),'PUBLIC') as papel,
             a.privilege_type as priv
        from pg_class c join pg_namespace n on n.oid=c.relnamespace,
             aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
       where n.nspname='public' and c.relname=v_nome
    loop
      if not (v_rec.papel = any(array[v_dono, 'service_role'])) then
        v_err := v_err || format('ACL direta inesperada em public.%s: %s possui %s.',
          v_nome, v_rec.papel, v_rec.priv);
      end if;
    end loop;

    -- privilegio EFETIVO dos papeis que podem ATUAR de fato
    for v_rec in
      select r.rolname, r.rolsuper, r.rolcanlogin from pg_roles r order by r.rolname
    loop
      if v_rec.rolname = any(array[v_dono, 'service_role']) then
        continue;
      elsif v_rec.rolsuper then
        raise notice '[info] % e superusuario: privilegios implicitos ignorados', v_rec.rolname;
        continue;
      elsif v_rec.rolname = any(v_predef) then
        -- Predefinido NOLOGIN: registra e segue. O risco (heranca por papel de
        -- aplicacao) ja foi avaliado em H.0.
        raise notice '[info] papel predefinido % presente (capacidades globais inerentes)', v_rec.rolname;
        continue;
      elsif v_rec.rolname = any(v_supabase_read_roles) then
        -- Papel INTERNO da plataforma Supabase: perfil/memberships ja validados em
        -- H.0b, e ACL direta a ele ja e barrada no laco de grants diretos acima.
        -- Aqui exige-se SELECT efetivo = true (leitura global via pg_read_all_data)
        -- e permite-se EXCLUSIVAMENTE esse SELECT; qualquer outro privilegio
        -- efetivo BLOQUEIA.
        if not has_table_privilege(v_rec.rolname, 'public.' || v_nome, 'SELECT') then
          v_err := v_err || format(
            'Papel interno Supabase %s SEM SELECT efetivo em public.%s (esperado via pg_read_all_data).',
            v_rec.rolname, v_nome);
        end if;
        foreach v_esp in array v_priv loop
          if v_esp = 'SELECT' then
            continue;  -- SELECT global esperado; nao e divergencia
          elsif has_table_privilege(v_rec.rolname, 'public.' || v_nome, v_esp) then
            v_err := v_err || format(
              'Papel interno Supabase %s possui %s EFETIVO (nao permitido; somente SELECT global) em public.%s.',
              v_rec.rolname, v_esp, v_nome);
          end if;
        end loop;
        continue;
      end if;

      -- "Atuante" = pode logar OU pode ser assumido por algum papel com login.
      v_atuante := v_rec.rolcanlogin
                   or exists (select 1 from pg_roles l
                               where l.rolcanlogin and not l.rolsuper
                                 and pg_has_role(l.rolname, v_rec.rolname, 'MEMBER'));
      if not v_atuante then
        continue;
      end if;

      foreach v_esp in array v_priv loop
        if has_table_privilege(v_rec.rolname, 'public.' || v_nome, v_esp) then
          v_err := v_err || format('Papel %s possui %s EFETIVO em public.%s.',
            v_rec.rolname, v_esp, v_nome);
        end if;
      end loop;
    end loop;
  end loop;

  -- =====================================================================
  -- H.7 service_role — privilegios EFETIVOS exatos
  -- =====================================================================
  foreach v_par in array array[
    'legal_documents|SELECT,INSERT,UPDATE',
    'legal_acceptances|SELECT,INSERT,UPDATE',
    'audit_logs|SELECT,INSERT',
    'notification_events|SELECT,INSERT,UPDATE'
  ] loop
    v_nome := split_part(v_par,'|',1);
    v_aut  := string_to_array(split_part(v_par,'|',2), ',');
    foreach v_esp in array v_priv loop
      if has_table_privilege('service_role', 'public.' || v_nome, v_esp) then
        if not (v_esp = any(v_aut)) then
          v_err := v_err || format('service_role possui %s EFETIVO em public.%s (nao autorizado).',
            v_esp, v_nome);
        end if;
      else
        if v_esp = any(v_aut) then
          v_err := v_err || format('service_role NAO possui %s em public.%s (esperado).', v_esp, v_nome);
        end if;
      end if;
    end loop;
  end loop;

  -- =====================================================================
  -- H.8 ACLs das FUNCOES — arrays exatos, diretos e efetivos
  -- =====================================================================
  foreach v_par in array array[
    'public.record_legal_acceptance(text,jsonb)|authenticated',
    'public.get_my_legal_acceptances()|authenticated',
    'public.get_my_notifications()|authenticated',
    'public.legal_document_versions(text)|authenticated',
    'public.get_current_legal_documents()|anon,authenticated',
    'public.current_legal_document(text)|service_role',
    'public.write_audit_log(text,text,text,uuid,text,jsonb,jsonb,text,uuid,text,jsonb,uuid)|service_role',
    'public.fase2a_touch_updated_at()|',
    'public.legal_documents_protect()|',
    'public.legal_documents_check_overlap()|',
    'public.legal_acceptances_protect()|',
    'public.audit_logs_block_mutation()|',
    'public.notification_events_protect()|'
  ] loop
    v_sig := split_part(v_par,'|',1);
    v_aut := coalesce(string_to_array(nullif(split_part(v_par,'|',2),''), ','), array[]::text[]);
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      v_err := v_err || format('Funcao %s ausente.', v_sig);
      continue;
    end if;

    select pg_get_userbyid(p.proowner), (p.proacl is null)
      into v_dono, v_bool from pg_proc p where p.oid = v_oid;
    if v_bool then
      v_err := v_err || format('Funcao %s com proacl NULL: PUBLIC teria EXECUTE por default privilege.', v_sig);
      continue;
    end if;

    v_ach := array[]::text[];
    for v_rec in
      select coalesce(nullif(a.grantee::regrole::text,'-'),'PUBLIC') as papel,
             a.privilege_type as priv
        from pg_proc p, aclexplode(p.proacl) a
       where p.oid = v_oid
    loop
      if v_rec.papel = 'PUBLIC' then
        v_err := v_err || format('Funcao %s: PUBLIC possui %s.', v_sig, v_rec.priv);
      elsif v_rec.papel <> v_dono then
        if v_rec.priv <> 'EXECUTE' then
          v_err := v_err || format('Funcao %s: %s possui %s (esperado somente EXECUTE).',
            v_sig, v_rec.papel, v_rec.priv);
        end if;
        if not (v_rec.papel = any(v_ach)) then
          v_ach := v_ach || v_rec.papel;
        end if;
      end if;
    end loop;

    -- conjunto direto exato
    foreach v_esp in array v_ach loop
      if not (v_esp = any(v_aut)) then
        v_err := v_err || format('Funcao %s: EXECUTE direto para %s (nao autorizado).', v_sig, v_esp);
      end if;
    end loop;
    foreach v_esp in array v_aut loop
      if not (v_esp = any(v_ach)) then
        v_err := v_err || format('Funcao %s: falta EXECUTE direto para %s.', v_sig, v_esp);
      end if;
    end loop;

    -- efetivo para os papeis que podem ATUAR (ignora predefinidos NOLOGIN,
    -- ja avaliados em H.0, e papeis sem login que ninguem pode assumir)
    for v_rec in
      select r.rolname, r.rolsuper, r.rolcanlogin from pg_roles r order by r.rolname
    loop
      if v_rec.rolname = v_dono or v_rec.rolsuper or v_rec.rolname = any(v_predef) then
        continue;
      end if;
      v_atuante := v_rec.rolcanlogin
                   or exists (select 1 from pg_roles l
                               where l.rolcanlogin and not l.rolsuper
                                 and pg_has_role(l.rolname, v_rec.rolname, 'MEMBER'));
      if not v_atuante and not (v_rec.rolname = any(v_app)) then
        continue;
      end if;
      if has_function_privilege(v_rec.rolname, v_sig, 'execute') then
        if not (v_rec.rolname = any(v_aut)) then
          v_err := v_err || format('Funcao %s: %s possui EXECUTE EFETIVO nao autorizado.', v_sig, v_rec.rolname);
        end if;
      else
        if v_rec.rolname = any(v_aut) then
          v_err := v_err || format('Funcao %s: %s NAO possui EXECUTE efetivo (esperado).', v_sig, v_rec.rolname);
        end if;
      end if;
    end loop;
    v_dono := null; v_bool := null;
  end loop;

  -- =====================================================================
  -- H.9 Veredito
  -- =====================================================================
  if array_length(v_err, 1) is not null then
    raise notice 'ASSERTIVA FINAL — divergencias:';
    for v_i in 1 .. array_length(v_err, 1) loop
      raise notice '   (%) %', v_i, v_err[v_i];
    end loop;
    raise exception
      'ASSERTIVA FINAL FALHOU (% divergencia(s)): ROLLBACK integral. A fundacao NAO foi aplicada.',
      array_length(v_err, 1);
  end if;

  raise notice 'ASSERTIVA FINAL DE SEGURANCA: OK (policies, ACLs diretas e efetivas, RLS, search_path, trigger, indice de retentativa e views conferidos). OK: sem acesso aplicacional indevido; papeis internos Supabase limitados a SELECT global esperado.';
end
$assert$;

commit;

-- ============================================================================
-- FIM — revisar e executar MANUALMENTE apenas após autorização.
--
-- PENDÊNCIA DOCUMENTADA PARA O MARCO 2:
--   alter table public.legal_acceptances
--     add constraint legal_acceptances_application_fk
--     foreign key (partner_application_id)
--     references public.partner_applications(id) on delete restrict;
--   A promoção preenche linked_auth_user_id e auth_user_id nas linhas pré-auth,
--   UMA ÚNICA VEZ, sem criar novos registros. Os documentos empresariais serão
--   registrados por backend seguro, com contexto 'partner_application'.
-- ============================================================================
