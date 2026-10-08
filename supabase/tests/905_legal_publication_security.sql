-- ===========================================================================
-- 905 — SEGURANÇA DA PUBLICAÇÃO LEGAL PÚBLICA
--
-- POR QUE ESTA SUÍTE EXISTE
-- `public.get_legal_document_version(text, text)` é anon-executável de propósito:
-- o Site precisa exibir a versão legal histórica exata que um contrato antigo
-- referencia. Essa exposição foi verificada fail-closed em runtime quando a
-- função entrou na matriz anon da suíte 900 — mas a verificação foi
-- TRANSITÓRIA, feita à mão e descartada. Uma função declarada como pública sem
-- guarda própria contra regressão é uma declaração sem prova.
--
-- Aqui as onze verificações passam a ser permanentes. O contrato de segurança é
-- o que está sob teste; nenhum número mágico de contagem é.
--
-- A suíte 900 segue cuidando da MATRIZ de atores (quem pode executar o quê).
-- Esta cuida do COMPORTAMENTO de uma função cuja exposição pública é
-- intencional. Responsabilidades separadas de propósito.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- Fixture: um doc_type ainda sem linha alguma, para não colidir com vigências
-- já publicadas pelas suítes anteriores.
-- ---------------------------------------------------------------------------
select user_id as uid_admin905 from public.site_admins limit 1 \gset

insert into public.legal_documents
  (doc_type, version, title, content, content_hash, status)
values ('future_commercial_terms', '905-rascunho', '[QA FICTICIO] rascunho 905',
        'corpo de rascunho 905',
        encode(extensions.digest('corpo de rascunho 905', 'sha256'), 'hex'),
        'draft');

insert into public.legal_documents
  (doc_type, version, title, content, content_hash, status,
   published_at, published_by, effective_from)
values ('future_commercial_terms', '905-publicado', '[QA FICTICIO] publicado 905',
        'corpo publicado 905',
        encode(extensions.digest('corpo publicado 905', 'sha256'), 'hex'),
        'published', now() - interval '3 days', (:'uid_admin905')::uuid,
        now() - interval '3 days');

-- Uma versão ARQUIVADA, alcançada pelo caminho legítimo published -> archived.
insert into public.legal_documents
  (doc_type, version, title, content, content_hash, status,
   published_at, published_by, effective_from)
values ('representation_declaration', '905-arquivado', '[QA FICTICIO] arquivado 905',
        'corpo arquivado 905',
        encode(extensions.digest('corpo arquivado 905', 'sha256'), 'hex'),
        'published', now() - interval '5 days', (:'uid_admin905')::uuid,
        now() - interval '5 days');
update public.legal_documents
   set status = 'archived', effective_to = now() - interval '4 days'
 where doc_type = 'representation_declaration' and version = '905-arquivado';

-- ---------------------------------------------------------------------------
-- 1. COMPORTAMENTO, sob o papel anon — é assim que o visitante chama.
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('anon', null);

select tests.check('SEG: versao PUBLICADA exata e visivel',
    (select count(*) = 1 from public.get_legal_document_version(
       'future_commercial_terms', '905-publicado')));
select tests.check('SEG: versao ARQUIVADA exata e visivel, por design',
    (select count(*) = 1 from public.get_legal_document_version(
       'representation_declaration', '905-arquivado')));
select tests.check('SEG: a arquivada devolve status archived, sem disfarce',
    (select status = 'archived' from public.get_legal_document_version(
       'representation_declaration', '905-arquivado')));

-- RASCUNHO nunca aparece, nem pedido pela versão exata.
select tests.check('SEG: RASCUNHO e invisivel mesmo pela versao exata',
    (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', '905-rascunho')));

-- Curingas não casam: a busca é por igualdade, não por padrão.
select tests.check('SEG: curinga em version NAO casa nada',
    (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', '%')));
select tests.check('SEG: curinga em doc_type NAO casa nada',
    (select count(*) = 0 from public.get_legal_document_version(
       '%', '905-publicado')));
select tests.check('SEG: sublinhado do LIKE tambem nao casa',
    (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', '905-publicad_')));

select tests.check('SEG: entrada vazia nao casa nada',
    (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', ''))
    and (select count(*) = 0 from public.get_legal_document_version(
       '', '905-publicado')));
select tests.check('SEG: NULL nao casa nada',
    (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', null))
    and (select count(*) = 0 from public.get_legal_document_version(
       null, '905-publicado')));

-- Tipo cruzado: a versão existe, mas sob OUTRO doc_type.
select tests.check('SEG: busca com doc_type cruzado nao vaza documento alheio',
    (select count(*) = 0 from public.get_legal_document_version(
       'master_agreement', '905-publicado'))
    and (select count(*) = 0 from public.get_legal_document_version(
       'privacy_notice', '905-arquivado')));

-- Entrada com aparência de injeção devolve zero linhas, não erro e não dado.
select tests.check('SEG: entrada com cara de injecao devolve zero linhas',
    (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', ''' or 1=1 --'))
    and (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms', ''' union select * from legal_documents --'))
    and (select count(*) = 0 from public.get_legal_document_version(
       'future_commercial_terms; drop table legal_documents', '905-publicado')));

-- No máximo UMA linha, sempre.
select tests.check('SEG: nunca devolve mais de uma linha',
    (select count(*) <= 1 from public.get_legal_document_version(
       'future_commercial_terms', '905-publicado'))
    and (select count(*) <= 1 from public.get_legal_document_version(
       'master_agreement', 'v1')));

-- anon não lê nem escreve a tabela diretamente.
select tests.check_raises('SEG: anon NAO le legal_documents direto',
    'select count(*) from public.legal_documents', 'permission denied');
select tests.check_raises('SEG: anon NAO escreve em legal_documents',
    $sql$update public.legal_documents set title = 'x'$sql$, 'permission denied');
select tests.check_raises('SEG: anon NAO apaga de legal_documents',
    'delete from public.legal_documents', 'permission denied');

rollback;

-- ---------------------------------------------------------------------------
-- 2. CONTRATO ESTRUTURAL, lido do catálogo e não do arquivo
-- ---------------------------------------------------------------------------
select tests.check('SEG: search_path fixo em pg_catalog',
    (select coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=pg_catalog'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: e STABLE, logo nao escreve',
    (select p.provolatile = 's'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: linguagem sql, que nao permite EXECUTE dinamico',
    (select l.lanname = 'sql'
       from pg_proc p join pg_language l on l.oid = p.prolang
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: corpo sem caminho de escrita e sem SQL dinamico',
    (select p.prosrc !~* '\y(insert|update|delete|truncate|alter|drop|execute)\y'
        and p.prosrc !~* '(format\(|quote_ident|quote_literal)'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: filtra por igualdade, sem LIKE nem regex',
    (select p.prosrc !~* '\y(like|ilike|similar to)\y' and p.prosrc !~ '~'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: restringe status a published/archived no proprio corpo',
    (select p.prosrc ~* 'status\s+in\s*\(\s*''published''\s*,\s*''archived''\s*\)'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: limita a uma linha no proprio corpo',
    (select p.prosrc ~* 'limit\s+1'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: SECURITY DEFINER com owner postgres',
    (select p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));

-- ---------------------------------------------------------------------------
-- 3. SUPERFÍCIE DE PRIVILÉGIO — a exposição anon é intencional e declarada
-- ---------------------------------------------------------------------------
select tests.check('SEG: PUBLIC nao executa; anon, authenticated e service_role executam',
    has_function_privilege('public',
      'public.get_legal_document_version(text,text)', 'EXECUTE') = false
    and has_function_privilege('anon',
      'public.get_legal_document_version(text,text)', 'EXECUTE') = true
    and has_function_privilege('authenticated',
      'public.get_legal_document_version(text,text)', 'EXECUTE') = true
    and has_function_privilege('service_role',
      'public.get_legal_document_version(text,text)', 'EXECUTE') = true);
select tests.check('SEG: a exposicao anon esta DECLARADA na matriz da suite 900',
    (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_legal_document_version'));
select tests.check('SEG: anon nao tem grant de tabela em legal_documents',
    (select count(*) = 0 from information_schema.role_table_grants
      where table_name = 'legal_documents' and grantee = 'anon'));

-- ---------------------------------------------------------------------------
-- 4. INVARIANTES DE ESTADO que sustentam o contrato acima
-- ---------------------------------------------------------------------------
-- Os triggers de legal_documents disparam em ordem alfabetica, e o de VIGENCIA
-- vem antes do de PROTECAO. Por isso a janela e futura e o doc_type e o que tem
-- apenas uma versao arquivada e ja encerrada: assim nada se sobrepoe e quem
-- responde e a trava que esta sob teste.
select tests.check_raises('SEG: documento nao pode NASCER arquivado',
  $sql$insert into public.legal_documents
    (doc_type, version, title, content, content_hash, status, published_at,
     published_by, effective_from, effective_to)
   values ('representation_declaration','905-nasce-arq','T','C',
           'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
           'archived', now(), null,
           now() + interval '100 days', now() + interval '101 days')$sql$,
  'archived');
select tests.check_raises('SEG: publicado NAO volta para rascunho',
  $sql$update public.legal_documents set status = 'draft'
    where doc_type = 'future_commercial_terms' and version = '905-publicado'$sql$,
  'Transicao invalida');
select tests.check_raises('SEG: conteudo de versao publicada e imutavel',
  $sql$update public.legal_documents set content = 'adulterado'
    where doc_type = 'future_commercial_terms' and version = '905-publicado'$sql$,
  'imutavel');
select tests.check_raises('SEG: documento juridico nao pode ser excluido',
  $sql$delete from public.legal_documents
    where doc_type = 'future_commercial_terms' and version = '905-publicado'$sql$,
  'nao pode ser excluido');

select tests.finish('905_legal_publication_security');
