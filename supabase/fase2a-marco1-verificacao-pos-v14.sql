-- ============================================================================
-- BDFlow Site — FASE 2A · MARCO 1 · VERIFICAÇÃO PÓS-APLICAÇÃO — V14 (SOMENTE LEITURA)
-- (SOMENTE LEITURA)
-- ----------------------------------------------------------------------------
-- Base autoritativa: commit cba451e da origin/main.
-- USO: somente DEPOIS de aplicação autorizada da fundação.
--
-- GARANTIAS
--   • Não insere, não atualiza, não exclui, não cria e não altera nada.
--   • Nenhuma checagem aborta o script: ausência vira FALHA e segue adiante.
--   • Consultas dinâmicas só rodam após confirmar tabela E colunas.
--   • v_ok só incrementa quando TODAS as checagens do objeto passam.
--
-- ESTRATÉGIA DE VERIFICAÇÃO DE FUNÇÕES
--   Nome/assinatura/retorno/SECURITY DEFINER/search_path NÃO bastam. Para cada
--   RPC verificamos também a DEFINIÇÃO (pg_proc.prosrc normalizado): exigimos
--   trechos obrigatórios e proibimos trechos perigosos, e imprimimos
--   md5(prosrc) como âncora reprodutível para comparação entre ambientes.
--
-- LIMITAÇÕES REAIS
--   • Verifica estrutura e definição textual, não comportamento em runtime:
--     não prova RLS contra um cliente real, não testa concorrência nem valida
--     conteúdo jurídico.
--   • Objetos protegidos: confirma presença e imprime hash para comparação
--     manual com o preflight.
--
-- SAÍDA: POST_FASE2A_MARCO1_OK ou lista objetiva de falhas.
-- ============================================================================

do $pos$
declare
  v_falhas text[] := array[]::text[];
  v_ok     int    := 0;
  v_i      int;
  v_rec    record;
  v_nome   text;
  v_tab    text;
  v_sig    text;
  v_par    text;
  v_oid    oid;
  v_idx    oid;
  v_txt    text;
  v_bool   boolean;
  v_cnt    bigint;
  v_def    text;
  v_cols   text;
  v_pred   text;
  v_esp    text;
  v_obj_ok boolean;
  v_falta  text;
  v_seg    text;
  v_src    text;
  v_priv   text;
  v_esperadas text[];
  v_achadas   text[];
  v_aut       text[];
  v_atuante   boolean;
  v_grp_esp   int;
  v_grp_ok    int;
  v_grp_fail  int;
  v_bal       int;
  v_ext       boolean;
  v_predef    text[] := array[
    'pg_read_all_data','pg_write_all_data','pg_monitor','pg_read_all_settings',
    'pg_read_all_stats','pg_stat_scan_tables','pg_database_owner',
    'pg_signal_backend','pg_checkpoint','pg_maintain','pg_use_reserved_connections',
    'pg_create_subscription','pg_execute_server_program','pg_read_server_files',
    'pg_write_server_files'];
  v_app       text[] := array['anon','authenticated','service_role'];
  v_supabase_read_roles text[] := array['supabase_etl_admin','supabase_read_only_user'];
  v_owner_tecnico text;   -- proprietario tecnico do banco (derivado de pg_database.datdba)
  v_rawdef text;          -- definicao integral de pg_get_constraintdef (sem normalizacao global)
  v_coid   oid;           -- oid da constraint corrente
  v_in_s boolean;         -- dentro de literal ' '
  v_in_d boolean;         -- dentro de identificador " "
  v_ch   text;            -- caractere atual do scanner
  v_n    int;             -- comprimento de v_rawdef
  v_privs     text[] := array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
begin
  raise notice '===========================================================';
  raise notice 'VERIFICACAO POS FASE 2A - MARCO 1 (V14, somente leitura)';
  raise notice 'Executado em: %', now();
  raise notice '===========================================================';

  -- ====================================================================
  -- [1] Tabelas; artefatos antigos NÃO podem existir
  -- ====================================================================
  raise notice '[1] Tabelas:';
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    v_grp_esp := v_grp_esp + 1;
    select c.relkind::text into v_txt
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname=v_nome;
    if v_txt is null then
      v_falhas := v_falhas || format('Tabela public.%s ausente.', v_nome);
      v_grp_fail := v_grp_fail + 1;
    elsif v_txt <> 'r' then
      v_falhas := v_falhas || format('public.%s com relkind=%s (esperado r).', v_nome, v_txt);
      v_grp_fail := v_grp_fail + 1;
    else
      v_grp_ok := v_grp_ok + 1;
      v_ok := v_ok + 1;
    end if;
    v_txt := null;
  end loop;
  if v_grp_fail = 0 then
    raise notice '      OK  tabelas: % esperadas / % aprovadas / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      tabelas: % esperadas / % aprovadas / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  foreach v_nome in array array[
    'my_notifications','my_legal_acceptances','legal_documents_public'
  ] loop
    if exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relname=v_nome
    ) then
      v_falhas := v_falhas || format(
        'Artefato antigo public.%s existe: esta proposta usa RPCs SECURITY DEFINER no lugar de views.', v_nome);
    else
      v_ok := v_ok + 1;
    end if;
  end loop;

  -- ====================================================================
  -- [2] Colunas essenciais e nulidade
  -- ====================================================================
  raise notice '[2] Colunas essenciais:';
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  foreach v_par in array array[
    'legal_documents|doc_type','legal_documents|version','legal_documents|title',
    'legal_documents|content','legal_documents|content_url','legal_documents|content_hash',
    'legal_documents|status','legal_documents|is_material_change',
    'legal_documents|effective_from','legal_documents|effective_to',
    'legal_documents|published_at','legal_documents|published_by','legal_documents|notes',
    'legal_acceptances|subject_type','legal_acceptances|subject_id',
    'legal_acceptances|linked_auth_user_id','legal_acceptances|auth_user_id',
    'legal_acceptances|partner_application_id','legal_acceptances|legal_document_id',
    'legal_acceptances|accepted_at','legal_acceptances|context','legal_acceptances|origin',
    'legal_acceptances|ip','legal_acceptances|user_agent','legal_acceptances|evidence',
    'legal_acceptances|revoked_at','legal_acceptances|revocation_reason',
    'audit_logs|actor_user_id','audit_logs|actor_role','audit_logs|action',
    'audit_logs|entity_type','audit_logs|entity_id','audit_logs|previous_state',
    'audit_logs|new_state','audit_logs|justification','audit_logs|correlation_id',
    'audit_logs|source','audit_logs|metadata','audit_logs|corrects_log_id',
    'notification_events|channel','notification_events|recipient_user_id',
    'notification_events|recipient_address','notification_events|template_key',
    'notification_events|template_data','notification_events|status',
    'notification_events|attempt_count','notification_events|scheduled_for',
    'notification_events|sent_at','notification_events|delivered_at',
    'notification_events|read_at','notification_events|first_failed_at',
    'notification_events|last_failed_at',
    'notification_events|error_code','notification_events|error_message',
    'notification_events|provider','notification_events|provider_message_id',
    'notification_events|idempotency_key','notification_events|retry_of_event_id',
    'notification_events|correlation_entity_type',
    'notification_events|correlation_entity_id'
  ] loop
    v_grp_esp := v_grp_esp + 1;
    if not exists (
      select 1 from information_schema.columns
       where table_schema='public'
         and table_name  = split_part(v_par,'|',1)
         and column_name = split_part(v_par,'|',2)
    ) then
      v_falhas := v_falhas || format('Coluna %s.%s ausente.',
        split_part(v_par,'|',1), split_part(v_par,'|',2));
      v_grp_fail := v_grp_fail + 1;
    else
      v_grp_ok := v_grp_ok + 1;
      v_ok := v_ok + 1;
    end if;
  end loop;
  if v_grp_fail = 0 then
    raise notice '      OK  colunas: % esperadas / % aprovadas / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      colunas: % esperadas / % aprovadas / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  foreach v_par in array array[
    'legal_acceptances|auth_user_id|YES',
    'legal_acceptances|linked_auth_user_id|YES',
    'legal_acceptances|subject_id|NO',
    'legal_acceptances|subject_type|NO',
    'site_profiles|auth_user_id|YES'
  ] loop
    select is_nullable into v_txt
      from information_schema.columns
     where table_schema='public'
       and table_name  = split_part(v_par,'|',1)
       and column_name = split_part(v_par,'|',2);
    if v_txt is null then
      v_falhas := v_falhas || format('Coluna %s.%s ausente.',
        split_part(v_par,'|',1), split_part(v_par,'|',2));
    elsif v_txt <> split_part(v_par,'|',3) then
      v_falhas := v_falhas || format('Coluna %s.%s is_nullable=%s (esperado %s).',
        split_part(v_par,'|',1), split_part(v_par,'|',2), v_txt, split_part(v_par,'|',3));
    else
      v_ok := v_ok + 1;
    end if;
    v_txt := null;
  end loop;

  -- ====================================================================
  -- [3] FKs — attnum = ANY(conkey), inclusive compostas
  -- ====================================================================
  raise notice '[3] Chaves estrangeiras de legal_acceptances:';
  if to_regclass('public.legal_acceptances') is null then
    v_falhas := v_falhas || 'legal_acceptances ausente: FKs nao verificaveis.';
  else
    -- 3a. linked_auth_user_id NAO pode participar de NENHUMA FK
    v_cnt := 0;
    for v_rec in
      select c.conname
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
       where n.nspname='public' and t.relname='legal_acceptances' and c.contype='f'
         and (select a.attnum from pg_attribute a
               where a.attrelid = c.conrelid and a.attname = 'linked_auth_user_id') = any(c.conkey)
    loop
      v_cnt := v_cnt + 1;
      v_falhas := v_falhas || format(
        'linked_auth_user_id participa da FK %s; deveria ser ancora imutavel SEM FK.', v_rec.conname);
    end loop;
    if v_cnt = 0 then
      raise notice '      OK  linked_auth_user_id nao participa de nenhuma FK';
      v_ok := v_ok + 1;
    end if;

    -- 3b. auth_user_id: exatamente UMA FK simples -> auth.users(id) SET NULL
    v_cnt := 0; v_obj_ok := true;
    for v_rec in
      select c.conname, c.confdeltype, array_length(c.conkey,1) as ncols,
             c.confrelid::regclass::text as destino,
             (select a.attname from pg_attribute a
               where a.attrelid = c.confrelid and a.attnum = c.confkey[1]) as col_destino
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
       where n.nspname='public' and t.relname='legal_acceptances' and c.contype='f'
         and (select a.attnum from pg_attribute a
               where a.attrelid = c.conrelid and a.attname = 'auth_user_id') = any(c.conkey)
    loop
      v_cnt := v_cnt + 1;
      raise notice '      FK % -> %(%) confdeltype=% ncols=%',
        v_rec.conname, v_rec.destino, v_rec.col_destino, v_rec.confdeltype, v_rec.ncols;
      if v_rec.ncols <> 1 then
        v_falhas := v_falhas || format('FK %s e composta; esperada FK simples.', v_rec.conname);
        v_obj_ok := false;
      end if;
      if v_rec.destino not in ('auth.users','users') then
        v_falhas := v_falhas || format('FK %s aponta para %s (esperado auth.users).',
          v_rec.conname, v_rec.destino);
        v_obj_ok := false;
      end if;
      if v_rec.col_destino is distinct from 'id' then
        v_falhas := v_falhas || format('FK %s referencia %s (esperado id).',
          v_rec.conname, v_rec.col_destino);
        v_obj_ok := false;
      end if;
      if v_rec.confdeltype <> 'n' then
        v_falhas := v_falhas || format(
          'FK %s com confdeltype=%s (esperado n = ON DELETE SET NULL).', v_rec.conname, v_rec.confdeltype);
        v_obj_ok := false;
      end if;
    end loop;
    if v_cnt <> 1 then
      v_falhas := v_falhas || format(
        'auth_user_id participa de %s FK(s); esperado exatamente 1.', v_cnt);
      v_obj_ok := false;
    end if;
    if v_obj_ok and v_cnt = 1 then
      raise notice '      OK  auth_user_id com exatamente 1 FK simples SET NULL';
      v_ok := v_ok + 1;
    end if;
  end if;

  -- ====================================================================
  -- [4] Constraints — nome + tabela
  -- ====================================================================
  raise notice '[4] Constraints — comparacao EXATA (integral, byte a byte) com o gabarito do catalogo (45):';
  --   V14: comparacao TEXTUAL INTEGRAL. Para cada constraint obtem-se
  --   pg_catalog.pg_get_constraintdef(oid, false), normaliza-se APENAS CRLF/LF e
  --   compara-se BYTE A BYTE com a renderizacao exata exportada do banco (CSV do
  --   diagnostico), alem do MD5 exato. NENHUMA outra transformacao: sem lower/
  --   translate/regexp para canonicalizar, sem remover whitespace, casts ou
  --   parenteses, sem reordenar operandos. Qualquer alteracao (cast/tipo do cast,
  --   literal, capitalizacao de literal, whitespace dentro/fora de literal,
  --   coluna, operador, funcao, parenteses, precedencia, AND/OR/NOT, ordem em
  --   ARRAY, UNIQUE e ordem/numero de suas colunas) muda a definicao ou o MD5 e
  --   FALHA com CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE.
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  for v_rec in
    select * from (values
      ('audit_logs','audit_logs_action_nonempty','c','ffdcda57591f92e19512236d8dcc288e','CHECK ((length(btrim(action)) > 0))'),
      ('audit_logs','audit_logs_entity_type_nonempty','c','eb7e0447ad940bffc68eadd0fbe8ec7f','CHECK ((length(btrim(entity_type)) > 0))'),
      ('audit_logs','audit_logs_metadata_objeto','c','fa278f88e142c2799f6ee09e4b429646','CHECK ((jsonb_typeof(metadata) = ''object''::text))'),
      ('audit_logs','audit_logs_nao_corrige_a_si','c','190a091aeed0190eef54656057ce6bfe','CHECK (((corrects_log_id IS NULL) OR (corrects_log_id <> id)))'),
      ('legal_acceptances','legal_acceptances_context_allowed','c','f4fd70de899fe80bc9bf8cd9ecb3afa8','CHECK ((context = ANY (ARRAY[''partner_application''::text, ''provisional_account''::text, ''owner_authority''::text, ''manager_invite''::text, ''commercial_contract''::text])))'),
      ('legal_acceptances','legal_acceptances_evidence_limite','c','25cfa595a51a78ee1a9924b73ecb6075','CHECK ((length((evidence)::text) <= 8192))'),
      ('legal_acceptances','legal_acceptances_evidence_objeto','c','d1135ccf63d7ebc522890622b8d27ff6','CHECK ((jsonb_typeof(evidence) = ''object''::text))'),
      ('legal_acceptances','legal_acceptances_link_coerente','c','7e5e6c670958cdd70e621a4f82bd2b35','CHECK (((auth_user_id IS NULL) OR ((linked_auth_user_id IS NOT NULL) AND (auth_user_id = linked_auth_user_id))))'),
      ('legal_acceptances','legal_acceptances_revocacao_coerente','c','c4679571b0565669d8e2d7b17c6ae7e3','CHECK ((((revoked_at IS NULL) AND (revocation_reason IS NULL)) OR ((revoked_at IS NOT NULL) AND (revocation_reason IS NOT NULL) AND (length(btrim(revocation_reason)) > 0))))'),
      ('legal_acceptances','legal_acceptances_subject_allowed','c','576f3ac65f092c9dee303286c168a8d6','CHECK ((subject_type = ANY (ARRAY[''auth_user''::text, ''partner_application''::text])))'),
      ('legal_acceptances','legal_acceptances_subject_coerente','c','62bcd9cf5b081ae6518d53a4bcdeddb1','CHECK ((((subject_type = ''auth_user''::text) AND (partner_application_id IS NULL) AND (linked_auth_user_id IS NOT NULL) AND (linked_auth_user_id = subject_id)) OR ((subject_type = ''partner_application''::text) AND (partner_application_id IS NOT NULL) AND (partner_application_id = subject_id))))'),
      ('legal_documents','legal_documents_archived_complete','c','776822306b1d84d60962bae615dbbecd','CHECK (((status <> ''archived''::text) OR ((((content IS NOT NULL) AND (length(btrim(content)) > 0)) OR ((content_url IS NOT NULL) AND (length(btrim(content_url)) > 0))) AND (content_hash IS NOT NULL) AND (length(btrim(content_hash)) > 0) AND (published_at IS NOT NULL) AND (published_by IS NOT NULL) AND (effective_from IS NOT NULL) AND (effective_to IS NOT NULL))))'),
      ('legal_documents','legal_documents_published_complete','c','261fe71528fb07a301de9078ba6748ca','CHECK (((status <> ''published''::text) OR ((((content IS NOT NULL) AND (length(btrim(content)) > 0)) OR ((content_url IS NOT NULL) AND (length(btrim(content_url)) > 0))) AND (content_hash IS NOT NULL) AND (length(btrim(content_hash)) > 0) AND (published_at IS NOT NULL) AND (published_by IS NOT NULL) AND (effective_from IS NOT NULL))))'),
      ('legal_documents','legal_documents_status_allowed','c','10cff5c766ac5bea792bbc573a098ca6','CHECK ((status = ANY (ARRAY[''draft''::text, ''published''::text, ''archived''::text])))'),
      ('legal_documents','legal_documents_title_nonempty','c','1950f394886189039cc457b420d8e511','CHECK ((length(btrim(title)) > 0))'),
      ('legal_documents','legal_documents_type_allowed','c','cf7069313902d2ca952b42e1e0ca99bb','CHECK ((doc_type = ANY (ARRAY[''privacy_notice''::text, ''provisional_account_terms''::text, ''truthfulness_declaration''::text, ''document_analysis_authorization''::text, ''representation_declaration''::text, ''future_commercial_terms''::text])))'),
      ('legal_documents','legal_documents_type_version_unique','u','88bc98285af92159e1afdf82bc867f74','UNIQUE (doc_type, version)'),
      ('legal_documents','legal_documents_version_nonempty','c','dc2404768d98d284b29a44e92fc4db11','CHECK ((length(btrim(version)) > 0))'),
      ('legal_documents','legal_documents_vigencia_coerente','c','58246d384b7768ace627785f8282a5e3','CHECK (((effective_to IS NULL) OR ((effective_from IS NOT NULL) AND (effective_to > effective_from))))'),
      ('notification_events','notification_events_attempt_nao_neg','c','d20cf8ce7b1715b5e0b7c272d3c0afc4','CHECK ((attempt_count >= 0))'),
      ('notification_events','notification_events_channel_allowed','c','0adc6c7f3135dc73fc24bd35f221e8e1','CHECK ((channel = ANY (ARRAY[''email''::text, ''whatsapp''::text, ''in_app''::text])))'),
      ('notification_events','notification_events_data_limite','c','d6c34196f5f4c89d47ac247768bb7293','CHECK ((length((template_data)::text) <= 8192))'),
      ('notification_events','notification_events_data_objeto','c','67481cc7de7e2e9f28d392af29f73794','CHECK ((jsonb_typeof(template_data) = ''object''::text))'),
      ('notification_events','notification_events_delivered_estado','c','9dca9cbcf9722e456fd8f8604b6ce065','CHECK (((delivered_at IS NULL) OR (status = ANY (ARRAY[''delivered''::text, ''read''::text]))))'),
      ('notification_events','notification_events_destinatario','c','56838d1949e2e548749d0440d99e4bee','CHECK ((((channel = ''in_app''::text) AND (recipient_user_id IS NOT NULL) AND (recipient_address IS NULL)) OR ((channel = ANY (ARRAY[''email''::text, ''whatsapp''::text])) AND ((recipient_user_id IS NOT NULL) OR (recipient_address IS NOT NULL)))))'),
      ('notification_events','notification_events_endereco_no_envio','c','56d2b57ff18c0aff6a3c08e11c21bc60','CHECK (((channel = ''in_app''::text) OR (status = ANY (ARRAY[''pending''::text, ''scheduled''::text, ''cancelled''::text])) OR (recipient_address IS NOT NULL)))'),
      ('notification_events','notification_events_erro_tamanho','c','308f2887f25eaedd4e4af7da9d329357','CHECK ((((error_code IS NULL) OR (length(error_code) <= 100)) AND ((error_message IS NULL) OR (length(error_message) <= 2000))))'),
      ('notification_events','notification_events_falha_par','c','1a08b9234746367f5e11c473f33a41e2','CHECK (((first_failed_at IS NULL) = (last_failed_at IS NULL)))'),
      ('notification_events','notification_events_idem_nonempty','c','25fc3a3e3b5ffc4089a1efc98f98bf5d','CHECK ((length(btrim(idempotency_key)) > 0))'),
      ('notification_events','notification_events_provider_estado','c','1f6bdb0c1330a8ff4d23c1290fe5793d','CHECK ((((provider_message_id IS NULL) AND (provider IS NULL)) OR (status <> ALL (ARRAY[''pending''::text, ''scheduled''::text]))))'),
      ('notification_events','notification_events_read_estado','c','d3e5db8b8aff9028d735241b04898060','CHECK (((read_at IS NULL) OR (status = ''read''::text)))'),
      ('notification_events','notification_events_retry_nao_self','c','6c59dec4d927de19c526877fa02c6f02','CHECK (((retry_of_event_id IS NULL) OR (retry_of_event_id <> id)))'),
      ('notification_events','notification_events_sent_estado','c','02940ea1e95b9de376113affe7be24dd','CHECK (((sent_at IS NULL) OR (status <> ALL (ARRAY[''pending''::text, ''scheduled''::text, ''sending''::text]))))'),
      ('notification_events','notification_events_st_delivered','c','ae94ffd67a83ad0c24d580130dd35a50','CHECK (((status <> ''delivered''::text) OR ((sent_at IS NOT NULL) AND (delivered_at IS NOT NULL))))'),
      ('notification_events','notification_events_st_failed','c','e4aee8b9ef4c83bc11e93004c4682426','CHECK (((status <> ''failed''::text) OR ((first_failed_at IS NOT NULL) AND (last_failed_at IS NOT NULL))))'),
      ('notification_events','notification_events_st_read','c','9c11258e82023c86a49682784bb9deed','CHECK (((status <> ''read''::text) OR ((sent_at IS NOT NULL) AND (delivered_at IS NOT NULL) AND (read_at IS NOT NULL))))'),
      ('notification_events','notification_events_st_scheduled','c','4f9c887c61d58f8397b8ed1cccffe26c','CHECK (((status <> ''scheduled''::text) OR (scheduled_for IS NOT NULL)))'),
      ('notification_events','notification_events_st_sent','c','a58860433476ba64a48f31334b760e02','CHECK (((status <> ''sent''::text) OR (sent_at IS NOT NULL)))'),
      ('notification_events','notification_events_status_allowed','c','e4484aed890cb6b7b9269e706a4fdfc3','CHECK ((status = ANY (ARRAY[''pending''::text, ''scheduled''::text, ''sending''::text, ''sent''::text, ''delivered''::text, ''read''::text, ''failed''::text, ''cancelled''::text])))'),
      ('notification_events','notification_events_template_nonempty','c','067496307c808ecab6b7ce5f26549907','CHECK ((length(btrim(template_key)) > 0))'),
      ('notification_events','notification_events_ts_delivered','c','fbe4242dd975663b60da24008b7f61bc','CHECK (((delivered_at IS NULL) OR ((sent_at IS NOT NULL) AND (delivered_at >= sent_at))))'),
      ('notification_events','notification_events_ts_first_failed','c','6da5e2a0fb544fc73376f908a675fdf2','CHECK (((first_failed_at IS NULL) OR (first_failed_at >= created_at)))'),
      ('notification_events','notification_events_ts_last_failed','c','4a9966faccf53ce6361e152272bbee54','CHECK (((last_failed_at IS NULL) OR ((first_failed_at IS NOT NULL) AND (last_failed_at >= first_failed_at))))'),
      ('notification_events','notification_events_ts_read','c','83a0738844d862559c9270f4d4b9b82b','CHECK (((read_at IS NULL) OR ((delivered_at IS NOT NULL) AND (read_at >= delivered_at))))'),
      ('notification_events','notification_events_ts_sent','c','bd41a23baf688374d90466aa322af67e','CHECK (((sent_at IS NULL) OR (sent_at >= created_at)))')
    ) as g(tab, nome, contype, md5x, def)
  loop
    v_grp_esp := v_grp_esp + 1;
    v_obj_ok := true;
    if to_regclass('public.' || v_rec.tab) is null then
      v_falhas := v_falhas || format('CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE: tabela public.%s ausente (constraint %s).', v_rec.tab, v_rec.nome);
      v_grp_fail := v_grp_fail + 1; continue;
    end if;
    select c.oid, c.contype::text
      into v_coid, v_txt
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname='public' and t.relname = v_rec.tab and c.conname = v_rec.nome;
    if v_coid is null then
      v_falhas := v_falhas || format('CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE: constraint %s ausente em public.%s.', v_rec.nome, v_rec.tab);
      v_grp_fail := v_grp_fail + 1; continue;
    end if;
    v_rawdef := replace(replace(pg_catalog.pg_get_constraintdef(v_coid, false), E'\r\n', E'\n'), E'\r', E'\n');
    if v_txt <> v_rec.contype then
      v_falhas := v_falhas || format('CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE: %s.%s contype real=%s esperado=%s.',
        v_rec.tab, v_rec.nome, v_txt, v_rec.contype);
      v_obj_ok := false;
    end if;
    if v_rawdef <> v_rec.def then
      v_falhas := v_falhas || format('CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE: %s.%s definicao integral divergente.%s  tipo real/esperado = %s / %s%s  real     = [%s]%s  esperada = [%s]%s  md5 real=%s  md5 esperado=%s',
        v_rec.tab, v_rec.nome, chr(10), v_txt, v_rec.contype, chr(10), v_rawdef, chr(10), v_rec.def, chr(10), md5(v_rawdef), v_rec.md5x);
      v_obj_ok := false;
    end if;
    if md5(v_rawdef) <> v_rec.md5x then
      v_falhas := v_falhas || format('CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE: %s.%s md5 real=%s esperado=%s.',
        v_rec.tab, v_rec.nome, md5(v_rawdef), v_rec.md5x);
      v_obj_ok := false;
    end if;
    if v_obj_ok then
      v_grp_ok := v_grp_ok + 1; v_ok := v_ok + 1;
    else
      v_grp_fail := v_grp_fail + 1;
    end if;
    v_coid := null; v_txt := null; v_rawdef := null;
  end loop;

  -- Inventario: exatamente 45 gabaritos (44 c / 1 u). A UNICA unique esperada e
  -- public.legal_documents.legal_documents_type_version_unique = UNIQUE (doc_type, version).
  if v_grp_esp <> 45 then
    v_falhas := v_falhas || format('Inventario de constraints: esperado=45, gabaritos=%s.', v_grp_esp);
  end if;

  -- 4b. Nenhuma constraint EXTRA (c/u) alem das 45 esperadas nas quatro tabelas.
  for v_rec in
    select t.relname as tabela, c.conname as nome, c.contype::text as tipo
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname='public'
       and t.relname in ('legal_documents','legal_acceptances','audit_logs','notification_events')
       and c.contype in ('c','u')
  loop
    if not ((v_rec.tabela || '|' || v_rec.nome || '|' || v_rec.tipo) = any (array[
      'audit_logs|audit_logs_action_nonempty|c',
      'audit_logs|audit_logs_entity_type_nonempty|c',
      'audit_logs|audit_logs_metadata_objeto|c',
      'audit_logs|audit_logs_nao_corrige_a_si|c',
      'legal_acceptances|legal_acceptances_context_allowed|c',
      'legal_acceptances|legal_acceptances_evidence_limite|c',
      'legal_acceptances|legal_acceptances_evidence_objeto|c',
      'legal_acceptances|legal_acceptances_link_coerente|c',
      'legal_acceptances|legal_acceptances_revocacao_coerente|c',
      'legal_acceptances|legal_acceptances_subject_allowed|c',
      'legal_acceptances|legal_acceptances_subject_coerente|c',
      'legal_documents|legal_documents_archived_complete|c',
      'legal_documents|legal_documents_published_complete|c',
      'legal_documents|legal_documents_status_allowed|c',
      'legal_documents|legal_documents_title_nonempty|c',
      'legal_documents|legal_documents_type_allowed|c',
      'legal_documents|legal_documents_type_version_unique|u',
      'legal_documents|legal_documents_version_nonempty|c',
      'legal_documents|legal_documents_vigencia_coerente|c',
      'notification_events|notification_events_attempt_nao_neg|c',
      'notification_events|notification_events_channel_allowed|c',
      'notification_events|notification_events_data_limite|c',
      'notification_events|notification_events_data_objeto|c',
      'notification_events|notification_events_delivered_estado|c',
      'notification_events|notification_events_destinatario|c',
      'notification_events|notification_events_endereco_no_envio|c',
      'notification_events|notification_events_erro_tamanho|c',
      'notification_events|notification_events_falha_par|c',
      'notification_events|notification_events_idem_nonempty|c',
      'notification_events|notification_events_provider_estado|c',
      'notification_events|notification_events_read_estado|c',
      'notification_events|notification_events_retry_nao_self|c',
      'notification_events|notification_events_sent_estado|c',
      'notification_events|notification_events_st_delivered|c',
      'notification_events|notification_events_st_failed|c',
      'notification_events|notification_events_st_read|c',
      'notification_events|notification_events_st_scheduled|c',
      'notification_events|notification_events_st_sent|c',
      'notification_events|notification_events_status_allowed|c',
      'notification_events|notification_events_template_nonempty|c',
      'notification_events|notification_events_ts_delivered|c',
      'notification_events|notification_events_ts_first_failed|c',
      'notification_events|notification_events_ts_last_failed|c',
      'notification_events|notification_events_ts_read|c',
      'notification_events|notification_events_ts_sent|c'
    ])) then
      v_falhas := v_falhas || format('Constraint inesperada em public.%s: %s (%s).', v_rec.tabela, v_rec.nome, v_rec.tipo);
      v_grp_fail := v_grp_fail + 1;
    end if;
  end loop;

  if v_grp_fail = 0 then
    raise notice 'CONSTRAINTS_DEFINICAO_EXATA_OK: 45 constraints conferem BYTE A BYTE (definicao integral + MD5) com o gabarito do catalogo (44 c / 1 u).';
    raise notice '      OK  constraints: % esperadas / % aprovadas / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      constraints: % esperadas / % aprovadas / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  -- ====================================================================
  -- [5] Índices — via catálogos (indkey/indnkeyatts/indnatts/indpred)
  -- ====================================================================
  raise notice '[5] Indices (catalogos, sem parsing textual do indexdef):';
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  foreach v_par in array array[
    -- nome | tabela | unico | colunas exatas | predicado normalizado ('-' = nenhum)
    'uq_legal_documents_vigente|legal_documents|t|doc_type|status=''published''andeffective_toisnull',
    'idx_legal_documents_type_status|legal_documents|f|doc_type,status,effective_from|-',
    'uq_legal_acceptances_ativo|legal_acceptances|t|subject_type,subject_id,legal_document_id,context|revoked_atisnull',
    'idx_legal_acceptances_subject|legal_acceptances|f|subject_type,subject_id|-',
    'idx_legal_acceptances_auth_user|legal_acceptances|f|auth_user_id|-',
    'idx_legal_acceptances_linked|legal_acceptances|f|linked_auth_user_id|-',
    'idx_legal_acceptances_doc|legal_acceptances|f|legal_document_id|-',
    'idx_audit_logs_entity|audit_logs|f|entity_type,entity_id|-',
    'idx_audit_logs_actor|audit_logs|f|actor_user_id|-',
    'idx_audit_logs_occurred|audit_logs|f|occurred_at|-',
    'idx_audit_logs_correlation|audit_logs|f|correlation_id|-',
    'uq_notification_events_idempotency|notification_events|t|channel,idempotency_key|-',
    'idx_notification_events_status|notification_events|f|status,scheduled_for|-',
    'idx_notification_events_recip|notification_events|f|recipient_user_id|-',
    'idx_notification_events_correl|notification_events|f|correlation_entity_type,correlation_entity_id|-',
    'uq_notification_events_retry_parent|notification_events|t|retry_of_event_id|retry_of_event_idisnotnull',
    'uq_site_profiles_auth_user_id|site_profiles|t|auth_user_id|auth_user_idisnotnull'
  ] loop
    v_nome := split_part(v_par,'|',1);
    v_tab  := split_part(v_par,'|',2);
    v_esp  := split_part(v_par,'|',4);
    v_pred := split_part(v_par,'|',5);
    v_obj_ok := true;
    v_grp_esp := v_grp_esp + 1;
    v_idx := to_regclass('public.' || v_nome);

    if v_idx is null then
      v_falhas := v_falhas || format('Indice %s ausente.', v_nome);
      v_obj_ok := false;
    else
      select ix.indisunique          as is_unique,
             ix.indisvalid           as is_valid,
             ix.indisready           as is_ready,
             ix.indislive            as is_live,
             ix.indnatts             as n_atts,
             ix.indnkeyatts          as n_key_atts,
             (select am.amname from pg_am am
               join pg_class ic on ic.relam = am.oid
              where ic.oid = v_idx)  as am_name,
             (select cl.relname from pg_class cl
              where cl.oid = ix.indrelid) as tabela,
             coalesce(pg_get_expr(ix.indpred, ix.indrelid, true), '') as predicado
        into v_rec
        from pg_index ix where ix.indexrelid = v_idx;

      if v_rec.tabela is distinct from v_tab then
        v_falhas := v_falhas || format('Indice %s pertence a %s (esperado %s).',
          v_nome, v_rec.tabela, v_tab);
        v_obj_ok := false;
      end if;
      if (split_part(v_par,'|',3) = 't') <> coalesce(v_rec.is_unique, false) then
        v_falhas := v_falhas || format('Indice %s: unicidade=%s (esperado %s).',
          v_nome, v_rec.is_unique, split_part(v_par,'|',3) = 't');
        v_obj_ok := false;
      end if;
      if not (coalesce(v_rec.is_valid,false) and coalesce(v_rec.is_ready,false)
              and coalesce(v_rec.is_live,false)) then
        v_falhas := v_falhas || format('Indice %s nao esta valid/ready/live (%s/%s/%s).',
          v_nome, v_rec.is_valid, v_rec.is_ready, v_rec.is_live);
        v_obj_ok := false;
      end if;
      if v_rec.am_name is distinct from 'btree' then
        v_falhas := v_falhas || format('Indice %s usa metodo %s (esperado btree).', v_nome, v_rec.am_name);
        v_obj_ok := false;
      end if;
      if v_rec.n_atts <> v_rec.n_key_atts then
        v_falhas := v_falhas || format(
          'Indice %s possui colunas INCLUDE (indnatts=%s, indnkeyatts=%s); nao esperado.',
          v_nome, v_rec.n_atts, v_rec.n_key_atts);
        v_obj_ok := false;
      end if;

      -- Colunas-chave na ORDEM exata, via pg_get_indexdef(oid, posicao, true)
      v_cols := '';
      for v_i in 1 .. v_rec.n_key_atts loop
        v_cols := v_cols || case when v_cols = '' then '' else ',' end
                  || lower(replace(pg_get_indexdef(v_idx, v_i, true), '"', ''));
      end loop;
      if v_cols is distinct from lower(replace(v_esp, ' ', '')) then
        v_falhas := v_falhas || format(
          'Indice %s com colunas [%s] (esperado [%s]) — composicao/ordem/expressao devem coincidir.',
          v_nome, v_cols, v_esp);
        v_obj_ok := false;
      end if;

      -- Predicado via pg_get_expr, normalizado
      v_txt := lower(v_rec.predicado);
      v_txt := replace(replace(replace(replace(v_txt, ' ', ''), '::text', ''), '(', ''), ')', '');
      if v_pred = '-' then
        if v_txt <> '' then
          v_falhas := v_falhas || format('Indice %s tem predicado inesperado [%s].', v_nome, v_txt);
          v_obj_ok := false;
        end if;
      else
        if v_txt is distinct from lower(replace(v_pred, ' ', '')) then
          v_falhas := v_falhas || format('Indice %s com predicado [%s] (esperado [%s]).',
            v_nome, v_txt, v_pred);
          v_obj_ok := false;
        end if;
      end if;
    end if;

    if v_obj_ok then
      v_grp_ok := v_grp_ok + 1;
      v_ok := v_ok + 1;
    else
      v_grp_fail := v_grp_fail + 1;
    end if;
    v_cols := null; v_txt := null;
  end loop;
  if v_grp_fail = 0 then
    raise notice '      OK  indices: % esperados / % aprovados / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      indices: % esperados / % aprovados / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  -- ====================================================================
  -- [6] RLS habilitada
  -- ====================================================================
  raise notice '[6] RLS:';
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    select c.relrowsecurity into v_bool
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=v_nome and c.relkind='r';
    if v_bool is null then
      v_falhas := v_falhas || format('Tabela public.%s ausente (RLS nao verificavel).', v_nome);
    elsif not v_bool then
      v_falhas := v_falhas || format('RLS NAO habilitada em public.%s.', v_nome);
    else
      raise notice '      OK  % (RLS on)', v_nome;
      v_ok := v_ok + 1;
    end if;
    v_bool := null;
  end loop;

  -- ====================================================================
  -- [7] Policies — CONJUNTO EXATO, roles exatos, USING/WITH CHECK exatos
  -- ====================================================================
  raise notice '[7] Policies (conjunto exato):';
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  -- Identidade da policy = TABELA + NOME. Assim, uma policy esperada criada na
  -- tabela errada, ou um nome repetido em outra tabela, e detectada.
  v_esperadas := array[
    'public.legal_documents/legal_documents_admin_all',
    'public.legal_acceptances/legal_acceptances_select_own',
    'public.audit_logs/audit_logs_admin_read',
    'public.notification_events/notification_events_select_own'
  ];

  -- Pares encontrados em TODO o schema public (nao apenas nas 4 tabelas), para
  -- flagrar um nome esperado aplicado a outra tabela.
  select coalesce(array_agg(('public.' || tablename || '/' || policyname) order by tablename, policyname),
                  array[]::text[])
    into v_achadas
    from pg_policies
   where schemaname='public'
     and (tablename in ('legal_documents','legal_acceptances','audit_logs','notification_events')
          or policyname in ('legal_documents_admin_all','legal_acceptances_select_own',
                            'audit_logs_admin_read','notification_events_select_own'));

  foreach v_seg in array v_achadas loop
    if not (v_seg = any(v_esperadas)) then
      v_falhas := v_falhas || format(
        'Par policy inesperado: %s (adicional, duplicado ou na tabela errada).', v_seg);
    end if;
  end loop;
  foreach v_seg in array v_esperadas loop
    if not (v_seg = any(v_achadas)) then
      v_falhas := v_falhas || format('Par policy ESPERADO ausente: %s.', v_seg);
    end if;
  end loop;
  raise notice '      pares presentes: %', array_to_string(v_achadas, ', ');

  foreach v_par in array array[
    -- tabela | policy | cmd | roles exatos | USING normalizado | WITH CHECK normalizado ('-' = deve ser vazio)
    'legal_documents|legal_documents_admin_all|ALL|authenticated|is_site_admin()|is_site_admin()',
    'legal_acceptances|legal_acceptances_select_own|SELECT|authenticated|auth_user_id=auth.uid()oris_site_admin()|-',
    'audit_logs|audit_logs_admin_read|SELECT|authenticated|is_site_admin()|-',
    'notification_events|notification_events_select_own|SELECT|authenticated|recipient_user_id=auth.uid()oris_site_admin()|-'
  ] loop
    v_tab  := split_part(v_par,'|',1);
    v_nome := split_part(v_par,'|',2);
    v_sig  := split_part(v_par,'|',3);
    v_esp  := split_part(v_par,'|',4);
    v_obj_ok := true;
    v_grp_esp := v_grp_esp + 1;

    select p.cmd, array_to_string(p.roles, ','), coalesce(p.qual,''), coalesce(p.with_check,'')
      into v_txt, v_cols, v_def, v_pred
      from pg_policies p
     where p.schemaname='public' and p.tablename=v_tab and p.policyname=v_nome;

    if v_txt is null then
      v_falhas := v_falhas || format('Policy %s ausente na tabela %s.', v_nome, v_tab);
      v_obj_ok := false;
    else
      if v_txt <> v_sig then
        v_falhas := v_falhas || format('Policy %s cmd=%s (esperado %s).', v_nome, v_txt, v_sig);
        v_obj_ok := false;
      end if;
      if v_cols is distinct from v_esp then
        v_falhas := v_falhas || format('Policy %s roles=[%s] (esperado exatamente [%s]).',
          v_nome, v_cols, v_esp);
        v_obj_ok := false;
      end if;

      -- Normalização estrutural (não é substring): remove espacos, aspas de
      -- schema, casts e parenteses.
      v_def  := lower(v_def);
      v_def  := replace(replace(replace(replace(replace(v_def, ' ', ''), 'public.', ''), '::text', ''), '(', ''), ')', '');
      v_def  := replace(v_def, 'is_site_admin', 'is_site_admin()');
      v_pred := lower(v_pred);
      v_pred := replace(replace(replace(replace(replace(v_pred, ' ', ''), 'public.', ''), '::text', ''), '(', ''), ')', '');
      v_pred := replace(v_pred, 'is_site_admin', 'is_site_admin()');

      v_seg := lower(replace(split_part(v_par,'|',5), ' ', ''));
      v_seg := replace(replace(v_seg, '(', ''), ')', '');
      v_seg := replace(v_seg, 'is_site_admin', 'is_site_admin()');
      if v_def is distinct from v_seg then
        v_falhas := v_falhas || format('Policy %s USING normalizado=[%s] (esperado [%s]).',
          v_nome, v_def, v_seg);
        v_obj_ok := false;
      end if;

      v_seg := split_part(v_par,'|',6);
      if v_seg = '-' then
        if coalesce(v_pred,'') <> '' then
          v_falhas := v_falhas || format('Policy %s possui WITH CHECK inesperado=[%s].', v_nome, v_pred);
          v_obj_ok := false;
        end if;
      else
        v_seg := lower(replace(v_seg, ' ', ''));
        v_seg := replace(replace(v_seg, '(', ''), ')', '');
        v_seg := replace(v_seg, 'is_site_admin', 'is_site_admin()');
        if v_pred is distinct from v_seg then
          v_falhas := v_falhas || format('Policy %s WITH CHECK normalizado=[%s] (esperado [%s]).',
            v_nome, v_pred, v_seg);
          v_obj_ok := false;
        end if;
      end if;
    end if;

    if v_obj_ok then
      v_grp_ok := v_grp_ok + 1;
      v_ok := v_ok + 1;
    else
      v_grp_fail := v_grp_fail + 1;
    end if;
    v_txt := null; v_cols := null; v_def := null; v_pred := null;
  end loop;
  if v_grp_fail = 0 then
    raise notice '      OK  policies: % esperadas / % aprovadas / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      policies: % esperadas / % aprovadas / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  -- 7b. Escrita: avalia USING e WITH CHECK SEPARADAMENTE.
  for v_rec in
    select tablename, policyname, cmd, coalesce(qual,'') as usando, coalesce(with_check,'') as checando
      from pg_policies
     where schemaname='public'
       and tablename in ('legal_documents','legal_acceptances','audit_logs','notification_events')
       and cmd in ('INSERT','UPDATE','DELETE','ALL')
  loop
    if v_rec.cmd in ('UPDATE','DELETE','ALL')
       and v_rec.usando not ilike '%is_site_admin%' then
      v_falhas := v_falhas || format(
        'Policy de escrita %s (%s): USING sem is_site_admin — parte insegura.', v_rec.policyname, v_rec.cmd);
    end if;
    if v_rec.cmd in ('INSERT','UPDATE','ALL')
       and v_rec.checando not ilike '%is_site_admin%' then
      v_falhas := v_falhas || format(
        'Policy de escrita %s (%s): WITH CHECK sem is_site_admin — parte insegura.', v_rec.policyname, v_rec.cmd);
    end if;
  end loop;
  raise notice '      escrita avaliada em USING e WITH CHECK separadamente';

  -- ====================================================================
  -- [8] Funções — assinatura, retorno, secdef, search_path EXATO e DEFINIÇÃO
  -- ====================================================================
  raise notice '[8] Funcoes (inclui verificacao da definicao):';
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  foreach v_par in array array[
    -- assinatura | secdef | retorno | linguagem | volatilidade(i/s/v) | obrigatorios(;) | proibidos(;)
    'public.fase2a_touch_updated_at()|f|trigger|plpgsql|v|new.updated_at||1c4318bee4240d4113d86fad7eb15623',
    'public.legal_documents_protect()|t|trigger|plpgsql|v|archived;published;draft;tg_op=''delete''||f8ae1dfddf836f4fae823b4c5747c76c',
    'public.legal_documents_check_overlap()|t|trigger|plpgsql|v|pg_advisory_xact_lock;''published'';''archived'';tstzrange;d.id<>new.id||18b7a46d5827a3e61fb5a7aeff447fcc',
    'public.legal_acceptances_protect()|t|trigger|plpgsql|v|linked_auth_user_id;revoked_at;promocaodeveseratomica||7cc83000e288a78db1b23a28842ae3cf',
    'public.audit_logs_block_mutation()|t|trigger|plpgsql|v|append-only||6413b1656a76064244a2862127cc0b6f',
    'public.notification_events_protect()|t|trigger|plpgsql|v|v_permitidas;old.attempt_count+1;first_failed_at;last_failed_at;failed>scheduled;provider_message_id;error_message;tg_op=''insert'';retry_of_event_id||0c4c7d3278df157463e1091c3c5f164d',
    'public.current_legal_document(text)|t|legal_documents|sql|s|effective_from<=now||ae30f8772d7f385466dc1154ec2683d5',
    'public.get_current_legal_documents()|t|record|sql|s|''published'';effective_from<=now;effective_to>now|notes;published_by|2abc386cc80ae52357bb42d939bcfebf',
    'public.legal_document_versions(text)|t|record|sql|s|effective_from<=now;auth.uid()isnotnull|notes;published_by|2b654fa635c32a198b9d989b56acae04',
    'public.get_my_legal_acceptances()|t|record|sql|s|auth.uid;a.auth_user_id=auth.uid|evidence;a.ip;user_agent|5597d10f8003009123cc2b9470fc0927',
    'public.get_my_notifications()|t|record|sql|s|auth.uid;n.recipient_user_id=auth.uid|template_data;provider;error_code;error_message|e4af17b22f58766b8e42a4116b4a5fa6',
    'public.record_legal_acceptance(text,jsonb)|t|uuid|plpgsql|v|auth.uid;''provisional_account'';privacy_notice;provisional_account_terms;current_legal_document;onconflict;revoked_atisnull|p_context|c9545e89b58ca524443e0161127f74ba',
    'public.write_audit_log(text,text,text,uuid,text,jsonb,jsonb,text,uuid,text,jsonb,uuid)|t|uuid|plpgsql|v|audit_logs||6184573864d04dd6b3478257a586779e'
  ] loop
    v_sig := split_part(v_par,'|',1);
    v_obj_ok := true;
    v_grp_esp := v_grp_esp + 1;
    v_oid := to_regprocedure(v_sig);

    if v_oid is null then
      v_falhas := v_falhas || format('Funcao %s ausente (assinatura exata).', v_sig);
      v_obj_ok := false;
    else
      select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), ''),
             pg_catalog.format_type(p.prorettype, null),
             (select l.lanname from pg_language l where l.oid = p.prolang),
             p.provolatile::text,
             replace(replace(p.prosrc, E'\r\n', E'\n'), E'\r', E'\n')
        into v_bool, v_def, v_cols, v_txt, v_priv, v_src
        from pg_proc p where p.oid = v_oid;

      if (split_part(v_par,'|',2) = 't') <> coalesce(v_bool, false) then
        v_falhas := v_falhas || format('Funcao %s: SECURITY DEFINER=%s (esperado %s).',
          v_sig, v_bool, split_part(v_par,'|',2) = 't');
        v_obj_ok := false;
      end if;
      -- Comparacao EXATA do tipo de retorno (nunca substring).
      if lower(coalesce(v_cols,'')) is distinct from lower(split_part(v_par,'|',3)) then
        v_falhas := v_falhas || format('Funcao %s retorna [%s] (esperado exatamente [%s]).',
          v_sig, v_cols, split_part(v_par,'|',3));
        v_obj_ok := false;
      end if;
      if v_txt is distinct from split_part(v_par,'|',4) then
        v_falhas := v_falhas || format('Funcao %s em linguagem %s (esperado %s).',
          v_sig, v_txt, split_part(v_par,'|',4));
        v_obj_ok := false;
      end if;
      if v_priv is distinct from split_part(v_par,'|',5) then
        v_falhas := v_falhas || format('Funcao %s com volatilidade %s (esperado %s).',
          v_sig, v_priv, split_part(v_par,'|',5));
        v_obj_ok := false;
      end if;
      -- search_path EXATO: pg_catalog
      if coalesce(v_def,'') <> 'search_path=pg_catalog' then
        v_falhas := v_falhas || format(
          'Funcao %s com proconfig=[%s] (esperado exatamente search_path=pg_catalog).',
          v_sig, coalesce(nullif(v_def,''), '(vazio)'));
        v_obj_ok := false;
      end if;

      -- DEFINIÇÃO: trechos obrigatórios
      foreach v_seg in array string_to_array(split_part(v_par,'|',6), ';') loop
        if btrim(v_seg) <> '' then
          if position(lower(replace(btrim(v_seg), ' ', '')) in lower(regexp_replace(v_src, '\s+', '', 'g'))) = 0 then
            v_falhas := v_falhas || format(
              'Definicao de %s NAO contem o trecho obrigatorio "%s".', v_sig, btrim(v_seg));
            v_obj_ok := false;
          end if;
        end if;
      end loop;

      -- DEFINIÇÃO: trechos proibidos
      foreach v_seg in array string_to_array(split_part(v_par,'|',7), ';') loop
        if btrim(v_seg) <> '' then
          if position(lower(replace(btrim(v_seg), ' ', '')) in lower(regexp_replace(v_src, '\s+', '', 'g'))) > 0 then
            v_falhas := v_falhas || format(
              'Definicao de %s contem trecho PROIBIDO "%s" (possivel vazamento).', v_sig, btrim(v_seg));
            v_obj_ok := false;
          end if;
        end if;
      end loop;

      -- HASH ESPERADO do corpo: md5 do prosrc com normalizacao APENAS de
      -- CRLF/LF (sem lower/translate/remocao de espacos/comentarios). AUTORIDADE
      -- da checagem: qualquer alteracao de string, comentario, whitespace,
      -- comando, operador, literal, capitalizacao ou pontuacao muda o hash. Os
      -- tokens acima permanecem como diagnostico COMPLEMENTAR.
      v_txt := split_part(v_par, '|', 8);
      if btrim(coalesce(v_txt, '')) <> '' then
        if md5(v_src) is distinct from btrim(v_txt) then
          v_falhas := v_falhas || format(
            'Definicao de %s divergente: md5(prosrc)=%s (esperado %s). O corpo da funcao foi alterado.',
            v_sig, md5(v_src), btrim(v_txt));
          v_obj_ok := false;
        end if;
      end if;
      raise notice '      % md5(prosrc)=%', v_sig, md5(v_src);
    end if;

    if v_obj_ok then
      v_grp_ok := v_grp_ok + 1;
      v_ok := v_ok + 1;
    else
      v_grp_fail := v_grp_fail + 1;
    end if;
    v_bool := null; v_def := null; v_cols := null; v_txt := null; v_priv := null; v_src := null;
  end loop;
  if v_grp_fail = 0 then
    raise notice '      OK  funcoes: % esperadas / % aprovadas / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      funcoes: % esperadas / % aprovadas / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  -- Registro V12 (§7): corpo funcional de record_legal_acceptance intacto, via
  -- normalizacao ASCII DETERMINISTICA (independente de locale). O hash antigo
  -- fd5e0318... provinha de lower() que, no locale do servidor, nao rebaixava o
  -- 'Í' de um comentario; o hash determinista e 03d6e6aa...
  if to_regprocedure('public.record_legal_acceptance(text,jsonb)') is not null then
    select md5(replace(replace(p.prosrc, E'\r\n', E'\n'), E'\r', E'\n'))
      into v_txt
      from pg_proc p where p.oid = to_regprocedure('public.record_legal_acceptance(text,jsonb)');
    if v_txt = 'c9545e89b58ca524443e0161127f74ba' then
      raise notice 'RECORD_LEGAL_ACCEPTANCE_CORPO_FUNCIONAL_INTACTO (md5 exato CRLF/LF=%).', v_txt;
    else
      raise notice '[!] record_legal_acceptance md5 exato=% (esperado c9545e89b58ca524443e0161127f74ba).', v_txt;
    end if;
    v_txt := null;
  end if;

  -- 8b. RETURNS TABLE — colunas OUT conferidas pelo CATALOGO:
  --     proargmodes ('t' = coluna de saida), proargnames e proallargtypes.
  --     Confere quantidade, ordem, nomes e tipos.
  raise notice '[8b] Colunas de retorno (proargmodes/proargnames/proallargtypes):';
  foreach v_par in array array[
    'public.get_current_legal_documents()|doc_type:text,version:text,title:text,content:text,content_url:text,content_hash:text,is_material_change:boolean,effective_from:timestamp with time zone,effective_to:timestamp with time zone',
    'public.get_my_legal_acceptances()|acceptance_id:uuid,doc_type:text,version:text,title:text,content_hash:text,is_material_change:boolean,context:text,accepted_at:timestamp with time zone,revoked_at:timestamp with time zone',
    'public.get_my_notifications()|notification_id:uuid,channel:text,template_key:text,status_publico:text,correlation_entity_type:text,correlation_entity_id:text,created_at:timestamp with time zone,sent_at:timestamp with time zone,read_at:timestamp with time zone',
    'public.legal_document_versions(text)|doc_type:text,version:text,title:text,content:text,content_url:text,content_hash:text,is_material_change:boolean,effective_from:timestamp with time zone,effective_to:timestamp with time zone,status:text'
  ] loop
    v_sig := split_part(v_par,'|',1);
    v_esp := split_part(v_par,'|',2);
    v_obj_ok := true;
    v_oid := to_regprocedure(v_sig);

    if v_oid is null then
      v_falhas := v_falhas || format('RPC %s ausente: colunas OUT nao verificaveis.', v_sig);
      v_obj_ok := false;
    else
      select coalesce(string_agg(nome || ':' || tipo, ',' order by ord), '')
        into v_cols
        from (
          select p.proargnames[i] as nome,
                 pg_catalog.format_type(
                   (coalesce(p.proallargtypes, p.proargtypes::oid[]))[i], null) as tipo,
                 i as ord
            from pg_proc p,
                 generate_subscripts(p.proargnames, 1) as i
           where p.oid = v_oid
             and (coalesce(p.proargmodes, array[]::"char"[]))[i] = 't'
        ) z;

      if v_cols is distinct from v_esp then
        v_falhas := v_falhas || format(
          'RPC %s com colunas OUT [%s] (esperado exatamente [%s]) — nome, tipo, ordem e quantidade devem coincidir.',
          v_sig, v_cols, v_esp);
        v_obj_ok := false;
      end if;
    end if;

    if v_obj_ok then
      raise notice '      OK  % -> [%]', v_sig, v_cols;
      v_ok := v_ok + 1;
    end if;
    v_cols := null;
  end loop;

  -- ====================================================================
  -- [9] Triggers — tgtype por bits exatos + tgfoid via to_regprocedure
  -- ====================================================================
  raise notice '[9] Triggers:';
  v_grp_esp := 0; v_grp_ok := 0; v_grp_fail := 0;
  foreach v_par in array array[
    -- nome | tabela | tgtype esperado | funcao esperada
    -- tgtype: 1=ROW, 2=BEFORE, 4=INSERT, 8=DELETE, 16=UPDATE
    'trg_legal_documents_updated|legal_documents|19|public.fase2a_touch_updated_at()',
    'trg_legal_documents_protect|legal_documents|31|public.legal_documents_protect()',
    'trg_legal_documents_overlap|legal_documents|23|public.legal_documents_check_overlap()',
    'trg_legal_acceptances_protect_upd|legal_acceptances|19|public.legal_acceptances_protect()',
    'trg_legal_acceptances_protect_del|legal_acceptances|11|public.legal_acceptances_protect()',
    'trg_audit_logs_no_update|audit_logs|19|public.audit_logs_block_mutation()',
    'trg_audit_logs_no_delete|audit_logs|11|public.audit_logs_block_mutation()',
    'trg_notification_events_updated|notification_events|19|public.fase2a_touch_updated_at()',
    'trg_notification_events_protect|notification_events|23|public.notification_events_protect()'
  ] loop
    v_nome := split_part(v_par,'|',1);
    v_tab  := split_part(v_par,'|',2);
    v_esp  := split_part(v_par,'|',3);
    v_sig  := split_part(v_par,'|',4);
    v_obj_ok := true;
    v_grp_esp := v_grp_esp + 1;

    select tg.tgtype::int, tg.tgfoid, tg.tgenabled::text, n.nspname
      into v_cnt, v_oid, v_txt, v_cols
      from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relname=v_tab and tg.tgname=v_nome and not tg.tgisinternal;

    if v_cnt is null then
      v_falhas := v_falhas || format('Trigger %s ausente em public.%s.', v_nome, v_tab);
      v_obj_ok := false;
    else
      if v_cnt <> v_esp::int then
        v_falhas := v_falhas || format(
          'Trigger %s com tgtype=%s (esperado %s: timing/eventos/nivel divergem).', v_nome, v_cnt, v_esp);
        v_obj_ok := false;
      end if;
      if v_oid is distinct from to_regprocedure(v_sig) then
        v_falhas := v_falhas || format('Trigger %s executa oid=%s (esperado %s).', v_nome, v_oid, v_sig);
        v_obj_ok := false;
      end if;
      if v_txt <> 'O' then
        v_falhas := v_falhas || format('Trigger %s nao habilitado (tgenabled=%s).', v_nome, v_txt);
        v_obj_ok := false;
      end if;
      if v_cols is distinct from 'public' then
        v_falhas := v_falhas || format('Trigger %s em schema %s (esperado public).', v_nome, v_cols);
        v_obj_ok := false;
      end if;
    end if;

    if v_obj_ok then
      v_grp_ok := v_grp_ok + 1;
      v_ok := v_ok + 1;
    else
      v_grp_fail := v_grp_fail + 1;
    end if;
    v_cnt := null; v_txt := null; v_cols := null;
  end loop;
  if v_grp_fail = 0 then
    raise notice '      OK  triggers: % esperados / % aprovados / 0 falhas', v_grp_esp, v_grp_ok;
  else
    raise notice '      triggers: % esperados / % aprovados / % falhas', v_grp_esp, v_grp_ok, v_grp_fail;
  end if;

  -- ====================================================================
  -- [10] ACLs EXATAS — tabelas e funcoes
  --   Le relacl/proacl com aclexplode (grantee 0 = PUBLIC) e trata proacl NULL
  --   como EXECUTE para PUBLIC. Confere tambem privilegio EFETIVO
  --   (has_table_privilege / has_function_privilege), que cobre heranca via
  --   pg_auth_members. Qualquer papel inesperado — alem do proprietario
  --   tecnico — e falha.
  -- ====================================================================
  raise notice '[10] ACLs de tabela:';
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    if to_regclass('public.' || v_nome) is null then
      v_falhas := v_falhas || format('Tabela %s ausente: ACL nao verificavel.', v_nome);
      continue;
    end if;
    v_obj_ok := true;

    -- proprietario tecnico (ignorado nas comparacoes)
    select pg_get_userbyid(c.relowner) into v_priv
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=v_nome;

    -- 10a. Qualquer papel com privilegio DIRETO alem do dono e service_role
    for v_rec in
      select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') as papel,
             a.privilege_type as priv
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace,
             aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
       where n.nspname='public' and c.relname=v_nome
    loop
      if v_rec.papel = v_priv then
        continue;                       -- proprietario tecnico
      elsif v_rec.papel = 'service_role' then
        continue;                       -- conferido em 10b
      else
        v_falhas := v_falhas || format(
          'ACL inesperada: papel %s possui %s em public.%s (esperado: apenas o proprietario e service_role).',
          v_rec.papel, v_rec.priv, v_nome);
        v_obj_ok := false;
      end if;
    end loop;

    -- 10b. Privilegio EFETIVO de TODOS os papeis (direto ou herdado via
    --      pg_auth_members). Ignora apenas: proprietario tecnico, service_role
    --      (conferida em 10c) e superusuarios (registrados como informacao).
    for v_rec in
      select r.rolname, r.rolsuper, r.rolcanlogin from pg_roles r order by r.rolname
    loop
      if v_rec.rolname = v_priv or v_rec.rolname = 'service_role' then
        continue;
      elsif v_rec.rolsuper then
        raise notice '      [info] % e superusuario: privilegios implicitos ignorados', v_rec.rolname;
        continue;
      elsif v_rec.rolname = any(v_predef) then
        -- Papel PREDEFINIDO NOLOGIN do PostgreSQL: capacidades globais sao
        -- inerentes. Sua existencia nao e divergencia; o risco (heranca por
        -- papel de aplicacao) e avaliado na secao [10f].
        raise notice '      [info] papel predefinido % presente', v_rec.rolname;
        continue;
      elsif v_rec.rolname = any(v_supabase_read_roles) then
        -- Papel INTERNO da plataforma Supabase: NAO avaliado aqui para evitar
        -- falso positivo sobre o SELECT global. Toda a validacao (perfil,
        -- memberships, isolamento e matriz por tabela) e centralizada, fail-closed,
        -- na secao [10h]. Aqui apenas registra e segue.
        raise notice '      [info] papel interno Supabase % presente: avaliado integralmente em [10h].', v_rec.rolname;
        continue;
      end if;

      -- Considera apenas papeis que podem ATUAR: com login, ou assumiveis por
      -- algum papel com login, ou papeis de aplicacao conhecidos.
      v_atuante := v_rec.rolcanlogin
                   or v_rec.rolname = any(v_app)
                   or exists (select 1 from pg_roles l
                               where l.rolcanlogin and not l.rolsuper
                                 and pg_has_role(l.rolname, v_rec.rolname, 'MEMBER'));
      if not v_atuante then
        continue;
      end if;

      foreach v_sig in array v_privs loop
        if has_table_privilege(v_rec.rolname, 'public.' || v_nome, v_sig) then
          v_falhas := v_falhas || format(
            'Privilegio EFETIVO indevido: papel %s possui %s em public.%s (direto ou herdado).',
            v_rec.rolname, v_sig, v_nome);
          v_obj_ok := false;
        end if;
      end loop;
    end loop;

    if v_obj_ok then
      raise notice '      OK  public.% sem privilegios para PUBLIC/anon/authenticated', v_nome;
      v_ok := v_ok + 1;
    end if;
    v_priv := null;
  end loop;

  -- 10c. service_role: BYPASSRLS + privilegios EXATOS por tabela
  raise notice '[10c] service_role:';
  if not exists (select 1 from pg_roles where rolname='service_role') then
    v_falhas := v_falhas || 'Papel service_role inexistente.';
  else
    select r.rolbypassrls into v_bool from pg_roles r where r.rolname='service_role';
    if not coalesce(v_bool, false) then
      v_falhas := v_falhas ||
        'service_role sem BYPASSRLS: neste desenho nao ha policy para o papel, entao GRANT sozinho nao basta.';
    else
      raise notice '      OK  service_role com BYPASSRLS';
      v_ok := v_ok + 1;
    end if;
    v_bool := null;

    foreach v_par in array array[
      'legal_documents|SELECT,INSERT,UPDATE',
      'legal_acceptances|SELECT,INSERT,UPDATE',
      'audit_logs|SELECT,INSERT',
      'notification_events|SELECT,INSERT,UPDATE'
    ] loop
      v_tab := split_part(v_par,'|',1);
      v_esp := split_part(v_par,'|',2);
      v_obj_ok := true;
      if to_regclass('public.' || v_tab) is null then
        v_falhas := v_falhas || format('Tabela %s ausente: privilegios de service_role nao verificaveis.', v_tab);
        continue;
      end if;

      -- conjunto DIRETO
      select coalesce(string_agg(distinct a.privilege_type, ',' order by a.privilege_type), '')
        into v_cols
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace,
             aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
       where n.nspname='public' and c.relname=v_tab
         and a.grantee = 'service_role'::regrole;

      select coalesce(string_agg(x, ',' order by x), '') into v_txt
        from unnest(string_to_array(v_esp, ',')) as x;

      if v_cols is distinct from v_txt then
        v_falhas := v_falhas || format(
          'service_role em public.%s com privilegios diretos [%s] (esperado exatamente [%s]).',
          v_tab, v_cols, v_txt);
        v_obj_ok := false;
      end if;

      -- conjunto EFETIVO (pega heranca): comparacao EXATA por array, nunca
      -- por substring — "auth" nao pode casar com "authenticated".
      v_aut := string_to_array(v_esp, ',');
      foreach v_sig in array v_privs loop
        if has_table_privilege('service_role', 'public.' || v_tab, v_sig) then
          if not (v_sig = any(v_aut)) then
            v_falhas := v_falhas || format(
              'service_role possui %s EFETIVO em public.%s (nao autorizado; verifique heranca de papeis).',
              v_sig, v_tab);
            v_obj_ok := false;
          end if;
        else
          if v_sig = any(v_aut) then
            v_falhas := v_falhas || format(
              'service_role NAO possui %s efetivo em public.%s (esperado).', v_sig, v_tab);
            v_obj_ok := false;
          end if;
        end if;
      end loop;

      if v_obj_ok then
        raise notice '      OK  service_role em public.% = [%]', v_tab, v_cols;
        v_ok := v_ok + 1;
      end if;
      v_cols := null; v_txt := null;
    end loop;
  end if;

  -- 10d. ACLs de FUNCAO — conjunto exato de papeis com EXECUTE
  raise notice '[10d] ACLs de funcao:';
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
    v_esp := split_part(v_par,'|',2);
    v_obj_ok := true;
    v_oid := to_regprocedure(v_sig);

    if v_oid is null then
      v_falhas := v_falhas || format('Funcao %s ausente: ACL nao verificavel.', v_sig);
      continue;
    end if;

    select pg_get_userbyid(p.proowner), (p.proacl is null)
      into v_priv, v_bool
      from pg_proc p where p.oid = v_oid;

    if v_bool then
      -- proacl NULL => EXECUTE para PUBLIC por padrao (acldefault).
      v_falhas := v_falhas || format(
        'Funcao %s com proacl NULL: PUBLIC possui EXECUTE por padrao. Faltou REVOKE explicito.', v_sig);
      v_obj_ok := false;
    else
      v_achadas := array[]::text[];
      for v_rec in
        select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') as papel,
               a.privilege_type as priv
          from pg_proc p, aclexplode(p.proacl) a
         where p.oid = v_oid
      loop
        if v_rec.papel = 'PUBLIC' then
          v_falhas := v_falhas || format('Funcao %s: PUBLIC possui %s.', v_sig, v_rec.priv);
          v_obj_ok := false;
        elsif v_rec.papel = v_priv then
          continue;                       -- proprietario tecnico
        else
          if v_rec.priv <> 'EXECUTE' then
            v_falhas := v_falhas || format(
              'Funcao %s: papel %s possui privilegio %s (esperado somente EXECUTE).',
              v_sig, v_rec.papel, v_rec.priv);
            v_obj_ok := false;
          end if;
          v_achadas := v_achadas || v_rec.papel;
        end if;
      end loop;

      select coalesce(string_agg(distinct x, ',' order by x), '') into v_txt
        from unnest(v_achadas) as x;
      select coalesce(string_agg(x, ',' order by x), '') into v_cols
        from unnest(string_to_array(nullif(v_esp,''), ',')) as x;
      v_aut := coalesce(string_to_array(nullif(v_esp,''), ','), array[]::text[]);

      if v_txt is distinct from coalesce(v_cols,'') then
        v_falhas := v_falhas || format(
          'Funcao %s com EXECUTE direto para [%s] (esperado exatamente [%s]).',
          v_sig, v_txt, coalesce(v_cols,''));
        v_obj_ok := false;
      end if;

      -- EFETIVO para TODOS os papeis (heranca via pg_auth_members). Ignora
      -- apenas o proprietario tecnico e superusuarios (informados).
      for v_rec in
        select r.rolname, r.rolsuper, r.rolcanlogin from pg_roles r order by r.rolname
      loop
        if v_rec.rolname = v_priv then
          continue;
        elsif v_rec.rolsuper then
          continue;   -- superusuario: privilegio implicito, registrado em 10a
        elsif v_rec.rolname = any(v_predef) then
          continue;   -- predefinido NOLOGIN: avaliado em [10f]
        end if;
        v_atuante := v_rec.rolcanlogin
                     or v_rec.rolname = any(v_app)
                     or exists (select 1 from pg_roles l
                                 where l.rolcanlogin and not l.rolsuper
                                   and pg_has_role(l.rolname, v_rec.rolname, 'MEMBER'));
        if not v_atuante then
          continue;
        end if;
        v_bool := has_function_privilege(v_rec.rolname, v_sig, 'execute');
        if v_bool and not (v_rec.rolname = any(v_aut)) then
          v_falhas := v_falhas || format(
            'Funcao %s: papel %s possui EXECUTE EFETIVO nao autorizado (direto ou herdado).',
            v_sig, v_rec.rolname);
          v_obj_ok := false;
        elsif (not v_bool) and (v_rec.rolname = any(v_aut)) then
          v_falhas := v_falhas || format(
            'Funcao %s: %s NAO possui EXECUTE efetivo (esperado).', v_sig, v_rec.rolname);
          v_obj_ok := false;
        end if;
      end loop;
    end if;

    if v_obj_ok then
      raise notice '      OK  % EXECUTE=[%]', v_sig, coalesce(nullif(v_esp,''), '(ninguem)');
      v_ok := v_ok + 1;
    end if;
    v_bool := null; v_txt := null; v_cols := null; v_priv := null;
  end loop;

  -- 10e. CREATE no schema public — por ACL REAL (grantee 0 = PUBLIC)
  raise notice '[10e] CREATE no schema public:';
  v_obj_ok := true;
  for v_rec in
    select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') as papel,
           a.privilege_type as priv
      from pg_namespace n,
           aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
     where n.nspname='public' and a.privilege_type='CREATE'
  loop
    if v_rec.papel = 'PUBLIC' then
      v_falhas := v_falhas ||
        'PUBLIC possui CREATE no schema public (shadowing de objetos usados por funcoes SECURITY DEFINER).';
      v_obj_ok := false;
    elsif v_rec.papel in ('anon','authenticated') then
      v_falhas := v_falhas || format('%s possui CREATE direto no schema public.', v_rec.papel);
      v_obj_ok := false;
    end if;
  end loop;
  foreach v_seg in array array['anon','authenticated'] loop
    begin
      if has_schema_privilege(v_seg, 'public', 'CREATE') then
        v_falhas := v_falhas || format('%s possui CREATE efetivo (direto ou herdado) no schema public.', v_seg);
        v_obj_ok := false;
      end if;
    exception when undefined_object then
      v_falhas := v_falhas || format('Papel %s inexistente ao checar CREATE em public.', v_seg);
      v_obj_ok := false;
    end;
  end loop;
  if v_obj_ok then
    raise notice '      OK  PUBLIC/anon/authenticated sem CREATE no schema public';
    v_ok := v_ok + 1;
  end if;

  -- ====================================================================
  -- [11] Duplicidades e coerência de dados
  -- ====================================================================
  raise notice '[11] Duplicidades:';
  v_falta := null;
  if to_regclass('public.site_profiles') is null then
    v_falta := 'tabela site_profiles';
  elsif not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='site_profiles' and column_name='auth_user_id'
  ) then
    v_falta := 'coluna site_profiles.auth_user_id';
  end if;
  if v_falta is not null then
    v_falhas := v_falhas || format('Duplicidades nao verificaveis: %s ausente.', v_falta);
  else
    execute $q$
      select count(*) from (
        select auth_user_id from public.site_profiles
         where auth_user_id is not null group by auth_user_id having count(*) > 1) d
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format('%s auth_user_id duplicados apos a migration.', v_cnt);
    else
      raise notice '      OK  sem duplicidades de auth_user_id';
      v_ok := v_ok + 1;
    end if;
  end if;

  if to_regclass('public.notification_events') is not null
     and exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='notification_events' and column_name='channel')
     and exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='notification_events' and column_name='idempotency_key') then
    execute $q$
      select count(*) from (
        select channel, idempotency_key from public.notification_events
         group by channel, idempotency_key having count(*) > 1) d
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format('%s pares (channel, idempotency_key) duplicados.', v_cnt);
    else
      raise notice '      OK  idempotencia unica por canal';
      v_ok := v_ok + 1;
    end if;
  else
    v_falhas := v_falhas || 'Idempotencia nao verificavel: tabela/colunas ausentes.';
  end if;

  if to_regclass('public.legal_acceptances') is not null
     and exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='legal_acceptances' and column_name='linked_auth_user_id')
     and exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='legal_acceptances' and column_name='auth_user_id') then
    execute $q$
      select count(*) from public.legal_acceptances
       where auth_user_id is not null
         and (linked_auth_user_id is null or auth_user_id <> linked_auth_user_id)
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format('%s aceite(s) com auth_user_id divergente de linked_auth_user_id.', v_cnt);
    else
      raise notice '      OK  vinculo vivo coerente com o vinculo imutavel';
      v_ok := v_ok + 1;
    end if;
  end if;

  -- ====================================================================
  -- [11b] auth.users.id — uuid com PK/unicidade (base da FK SET NULL)
  -- ====================================================================
  raise notice '[11b] auth.users.id:';
  if to_regclass('auth.users') is null then
    v_falhas := v_falhas || 'auth.users ausente.';
  else
    v_obj_ok := true;
    select a.atttypid::regtype::text into v_txt
      from pg_attribute a
     where a.attrelid = 'auth.users'::regclass and a.attname='id'
       and a.attnum > 0 and not a.attisdropped;
    if v_txt is null then
      v_falhas := v_falhas || 'auth.users.id nao existe.';
      v_obj_ok := false;
    elsif v_txt <> 'uuid' then
      v_falhas := v_falhas || format('auth.users.id tem tipo %s (esperado uuid).', v_txt);
      v_obj_ok := false;
    end if;

    if v_obj_ok then
      if not exists (
        select 1 from pg_attribute a
         where a.attrelid='auth.users'::regclass and a.attname='id' and a.attnotnull
      ) then
        v_falhas := v_falhas || 'auth.users.id nao e NOT NULL.';
        v_obj_ok := false;
      end if;

      -- Mesma exigencia do preflight/guarda: unico, simples, valido, sem
      -- predicado, sem expressao e sem INCLUDE.
      if not exists (
        select 1 from pg_index ix
         where ix.indrelid = 'auth.users'::regclass
           and ix.indisunique
           and ix.indisvalid and ix.indisready and ix.indislive
           and ix.indnatts = 1 and ix.indnkeyatts = 1
           and ix.indpred is null and ix.indexprs is null
           and ix.indkey[0] = (select a.attnum from pg_attribute a
                                where a.attrelid='auth.users'::regclass and a.attname='id')
      ) then
        v_falhas := v_falhas ||
          'auth.users.id sem indice UNIQUE simples e valido (rejeitados: parcial, composto, com expressao, com INCLUDE, invalido, nao pronto ou nao ativo).';
        v_obj_ok := false;
      end if;
    end if;

    if v_obj_ok then
      raise notice '      OK  auth.users.id uuid com PK/unicidade';
      v_ok := v_ok + 1;
    end if;
    v_txt := null;
  end if;

  -- ====================================================================
  -- [10f] Papeis predefinidos NOLOGIN e risco de heranca/SET ROLE
  -- ====================================================================
  raise notice '[10f] Papeis predefinidos e heranca:';
  v_obj_ok := true;

  -- V12: proprietario tecnico do banco derivado de pg_database.datdba (NAO
  -- hardcode "postgres"). Sera excluido — por nome EXATO — da busca de papeis
  -- aplicacionais desconhecidos com login. Suas memberships sao INFORMACAO.
  select pg_get_userbyid(d.datdba) into v_owner_tecnico
    from pg_database d where d.datname = current_database();
  raise notice '      [info] proprietario tecnico (pg_database.datdba) = %', coalesce(v_owner_tecnico,'(desconhecido)');
  if v_owner_tecnico is not null then
    for v_rec in
      select m.rolname as papel
        from pg_auth_members am
        join pg_roles rr on rr.oid = am.member
        join pg_roles m  on m.oid  = am.roleid
       where rr.rolname = v_owner_tecnico
       order by 1
    loop
      raise notice '      [info] proprietario tecnico % e membro de % (gerenciado pela plataforma)', v_owner_tecnico, v_rec.papel;
    end loop;
    -- coerencia de propriedade: as quatro tabelas
    foreach v_nome in array array['legal_documents','legal_acceptances','audit_logs','notification_events'] loop
      if to_regclass('public.'||v_nome) is not null
         and pg_get_userbyid((select relowner from pg_class where oid=('public.'||v_nome)::regclass)) <> v_owner_tecnico then
        v_falhas := v_falhas || format('public.%s nao pertence ao proprietario tecnico %s.', v_nome, v_owner_tecnico);
        v_obj_ok := false;
      end if;
    end loop;
    -- coerencia de propriedade: as funcoes esperadas da fundacao
    foreach v_nome in array array[
      'public.legal_documents_protect()','public.legal_documents_check_overlap()',
      'public.legal_acceptances_protect()','public.audit_logs_block_mutation()',
      'public.notification_events_protect()','public.fase2a_touch_updated_at()',
      'public.current_legal_document(text)','public.get_current_legal_documents()',
      'public.legal_document_versions(text)','public.get_my_legal_acceptances()',
      'public.get_my_notifications()','public.record_legal_acceptance(text,jsonb)',
      'public.write_audit_log(text,text,text,uuid,text,jsonb,jsonb,text,uuid,text,jsonb,uuid)'
    ] loop
      if to_regprocedure(v_nome) is not null
         and pg_get_userbyid((select proowner from pg_proc where oid=to_regprocedure(v_nome))) <> v_owner_tecnico then
        v_falhas := v_falhas || format('Funcao %s nao pertence ao proprietario tecnico %s.', v_nome, v_owner_tecnico);
        v_obj_ok := false;
      end if;
    end loop;
    -- isolamento: papeis de aplicacao nao herdam nem assumem o proprietario tecnico
    foreach v_nome in array v_app loop
      if exists (select 1 from pg_roles where rolname=v_nome) then
        if pg_has_role(v_nome, v_owner_tecnico, 'USAGE') then
          v_falhas := v_falhas || format('Papel de aplicacao %s HERDA o proprietario tecnico %s.', v_nome, v_owner_tecnico);
          v_obj_ok := false;
        elsif pg_has_role(v_nome, v_owner_tecnico, 'MEMBER') then
          v_falhas := v_falhas || format('Papel de aplicacao %s pode assumir (SET ROLE) o proprietario tecnico %s.', v_nome, v_owner_tecnico);
          v_obj_ok := false;
        end if;
      end if;
    end loop;
  end if;

  foreach v_seg in array v_predef loop
    if exists (select 1 from pg_roles where rolname = v_seg) then
      raise notice '      [info] % existe (capacidades globais inerentes do PostgreSQL)', v_seg;
      foreach v_nome in array v_app loop
        if exists (select 1 from pg_roles where rolname = v_nome) then
          if pg_has_role(v_nome, v_seg, 'USAGE') then
            v_falhas := v_falhas || format(
              'Papel de aplicacao %s HERDA o papel predefinido %s (privilegios globais inerentes).',
              v_nome, v_seg);
            v_obj_ok := false;
          elsif pg_has_role(v_nome, v_seg, 'MEMBER') then
            v_falhas := v_falhas || format(
              'Papel de aplicacao %s pode assumir (SET ROLE) o papel predefinido %s.', v_nome, v_seg);
            v_obj_ok := false;
          end if;
        end if;
      end loop;

      -- Qualquer papel COM LOGIN inesperado que possa assumir um predefinido.
      -- Excecao EXATA (nunca por prefixo): supabase_etl_admin e
      -- supabase_read_only_user sao validados integralmente em [10h]. Qualquer
      -- TERCEIRO papel com login (mesmo membro de pg_read_all_data) continua
      -- sendo capturado aqui.
      for v_rec in
        select r.rolname from pg_roles r
         where r.rolcanlogin and not r.rolsuper
           and not (r.rolname = any(v_app))
           and not (r.rolname = any(v_supabase_read_roles))
           and (v_owner_tecnico is null or r.rolname <> v_owner_tecnico)
           and pg_has_role(r.rolname, v_seg, 'MEMBER')
      loop
        v_falhas := v_falhas || format(
          'Papel com login %s (fora da allowlist) pode assumir o predefinido %s.', v_rec.rolname, v_seg);
        v_obj_ok := false;
      end loop;
    end if;
  end loop;
  if v_obj_ok then
    raise notice '      OK  nenhum papel de aplicacao herda ou assume papeis predefinidos';
    v_ok := v_ok + 1;
  end if;

  -- ====================================================================
  -- [10g] Defaults das colunas id: pg_catalog.gen_random_uuid()
  -- ====================================================================
  raise notice '[10g] Defaults de id (exige qualificacao pg_catalog):';
  foreach v_nome in array array[
    'legal_documents','legal_acceptances','audit_logs','notification_events'
  ] loop
    if to_regclass('public.' || v_nome) is null then
      v_falhas := v_falhas || format('Tabela %s ausente: default de id nao verificavel.', v_nome);
      continue;
    end if;
    select pg_get_expr(d.adbin, d.adrelid) into v_txt
      from pg_attrdef d
      join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
     where d.adrelid = ('public.' || v_nome)::regclass and a.attname = 'id';

    -- V12: o deparser do catalogo pode recompor 'pg_catalog.gen_random_uuid()'
    -- como 'gen_random_uuid()' (apresentacao), o que NAO prova resolucao para
    -- public.gen_random_uuid(). Aprovacao fail-closed exige TODAS as condicoes:
    --   (1) default existe; (2) expressao renderizada normalizada e exatamente
    --   'gen_random_uuid()' ou 'pg_catalog.gen_random_uuid()' (sem argumentos,
    --   sem outra funcao/operador); (3) pg_catalog.gen_random_uuid() existe com
    --   assinatura exata; (4) retorna uuid; (5) public.gen_random_uuid() NAO
    --   existe (ambiguidade). referenced_functions vazio NAO e falha isolada
    --   (dependencias de objetos internos/pinned podem nao aparecer).
    if v_txt is null then
      v_falhas := v_falhas || format('public.%s.id sem DEFAULT.', v_nome);
    else
      v_cols := lower(replace(v_txt, ' ', ''));
      if v_cols not in ('gen_random_uuid()','pg_catalog.gen_random_uuid()') then
        v_falhas := v_falhas || format(
          'public.%s.id com default [%s] normalizado [%s] (esperado gen_random_uuid() ou pg_catalog.gen_random_uuid(), sem argumentos nem outra funcao/operador).',
          v_nome, v_txt, v_cols);
      elsif to_regprocedure('pg_catalog.gen_random_uuid()') is null
            or (select pg_catalog.format_type(p.prorettype, null)
                  from pg_proc p where p.oid = to_regprocedure('pg_catalog.gen_random_uuid()')) is distinct from 'uuid' then
        v_falhas := v_falhas || format(
          'public.%s.id: pg_catalog.gen_random_uuid() ausente ou nao retorna uuid.', v_nome);
      elsif to_regprocedure('public.gen_random_uuid()') is not null then
        v_falhas := v_falhas || format(
          'public.%s.id: public.gen_random_uuid() existe -> AMBIGUIDADE; o default deve resolver para pg_catalog.', v_nome);
      else
        raise notice '      OK  public.%.id default = % (resolve para pg_catalog.gen_random_uuid(); public ausente)', v_nome, v_txt;
        v_ok := v_ok + 1;
      end if;
      v_cols := null;
    end if;
    v_txt := null;
  end loop;

  -- ====================================================================
  -- [10h] Papeis INTERNOS da plataforma Supabase — perfil, memberships,
  --       isolamento e MATRIZ por tabela (fail-closed; cada condicao participa
  --       do veredito). Espelha o preflight [13] e a assertiva final da Foundation
  --       (H.0b/H.6). Allowlist EXATA (nunca por prefixo "supabase_"):
  --       supabase_etl_admin e supabase_read_only_user. Papel ausente: sem
  --       excecao aplicada, sem bloqueio apenas pela ausencia.
  -- ====================================================================
  raise notice '[10h] Papeis internos Supabase (perfil, memberships, isolamento, matriz):';
  foreach v_seg in array v_supabase_read_roles loop
    if not exists (select 1 from pg_roles where rolname = v_seg) then
      raise notice '      [info] % ausente: sem excecao (nao criado, nao bloqueado pela ausencia; matriz nao aplicavel).', v_seg;
      continue;
    end if;
    v_bal := coalesce(array_length(v_falhas, 1), 0);

    -- perfil e memberships esperados (rolreplication difere por papel)
    v_ext  := (v_seg = 'supabase_etl_admin');            -- rolreplication esperado
    v_bool := pg_has_role(v_seg, 'pg_read_all_data', 'MEMBER');
    if not coalesce(v_bool, false) then
      v_falhas := v_falhas || format('Papel interno %s NAO e membro de pg_read_all_data.', v_seg);
    end if;
    if exists (select 1 from pg_roles where rolname='pg_write_all_data')
       and pg_has_role(v_seg, 'pg_write_all_data', 'MEMBER') then
      v_falhas := v_falhas || format('Papel interno %s e membro de pg_write_all_data (nao permitido).', v_seg);
    end if;
    for v_rec in
      select rolsuper, rolcanlogin, rolbypassrls, rolreplication from pg_roles where rolname = v_seg
    loop
      if v_rec.rolsuper       <> false then v_falhas := v_falhas || format('Papel interno %s com rolsuper<>false.', v_seg); end if;
      if v_rec.rolcanlogin    <> true  then v_falhas := v_falhas || format('Papel interno %s com rolcanlogin<>true.', v_seg); end if;
      if v_rec.rolbypassrls   <> true  then v_falhas := v_falhas || format('Papel interno %s com rolbypassrls<>true.', v_seg); end if;
      if v_rec.rolreplication <> v_ext then v_falhas := v_falhas || format('Papel interno %s com rolreplication<>%s.', v_seg, v_ext); end if;
      raise notice '      % | super=% canlogin=% bypassrls=% replication=% (esperado=%) | membro pg_read_all_data=%',
        v_seg, v_rec.rolsuper, v_rec.rolcanlogin, v_rec.rolbypassrls, v_rec.rolreplication, v_ext, v_bool;
    end loop;

    -- isolamento: anon/authenticated/service_role nao podem herdar (USAGE) nem
    -- assumir (MEMBER/SET ROLE) este papel interno.
    foreach v_nome in array v_app loop
      if exists (select 1 from pg_roles where rolname = v_nome) then
        if pg_has_role(v_nome, v_seg, 'USAGE') then
          v_falhas := v_falhas || format('Papel de aplicacao %s HERDA o papel interno Supabase %s.', v_nome, v_seg);
        elsif pg_has_role(v_nome, v_seg, 'MEMBER') then
          v_falhas := v_falhas || format('Papel de aplicacao %s pode assumir (SET ROLE) o papel interno Supabase %s.', v_nome, v_seg);
        end if;
      end if;
    end loop;

    -- matriz por tabela: SELECT=true; INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/
    -- TRIGGER=false; nenhuma ACL direta especifica.
    foreach v_tab in array array['legal_documents','legal_acceptances','audit_logs','notification_events'] loop
      if to_regclass('public.'||v_tab) is null then
        continue;  -- ausencia de tabela ja tratada em 10a
      end if;
      if not has_table_privilege(v_seg, 'public.'||v_tab, 'SELECT') then
        v_falhas := v_falhas || format('Papel interno %s SEM SELECT efetivo em public.%s (esperado via pg_read_all_data).', v_seg, v_tab);
      end if;
      foreach v_sig in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
        if has_table_privilege(v_seg, 'public.'||v_tab, v_sig) then
          v_falhas := v_falhas || format('Papel interno %s possui %s EFETIVO (nao permitido) em public.%s.', v_seg, v_sig, v_tab);
        end if;
      end loop;
      if exists (
        select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace,
               aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
         where n.nspname='public' and c.relname=v_tab
           and coalesce(nullif(a.grantee::regrole::text,'-'),'PUBLIC') = v_seg) then
        v_falhas := v_falhas || format('Papel interno %s possui ACL DIRETA em public.%s (nao permitido).', v_seg, v_tab);
      end if;
      raise notice '      % / public.% -> SELECT=% INSERT=% UPDATE=% DELETE=% TRUNCATE=% REFERENCES=% TRIGGER=%',
        v_seg, v_tab,
        has_table_privilege(v_seg,'public.'||v_tab,'SELECT'),
        has_table_privilege(v_seg,'public.'||v_tab,'INSERT'),
        has_table_privilege(v_seg,'public.'||v_tab,'UPDATE'),
        has_table_privilege(v_seg,'public.'||v_tab,'DELETE'),
        has_table_privilege(v_seg,'public.'||v_tab,'TRUNCATE'),
        has_table_privilege(v_seg,'public.'||v_tab,'REFERENCES'),
        has_table_privilege(v_seg,'public.'||v_tab,'TRIGGER');
    end loop;

    if coalesce(array_length(v_falhas, 1), 0) = v_bal then
      raise notice '      OK  % conferido (perfil, memberships, isolamento e matriz).', v_seg;
      v_ok := v_ok + 1;
    else
      raise notice '      -> % apresentou divergencia(s) (ver lista final).', v_seg;
    end if;
  end loop;
  v_bool := null; v_ext := null;

  -- ====================================================================
  -- [11c] Máquina de estados de notification_events (dados existentes)
  -- ====================================================================
  raise notice '[11c] notification_events — invariantes de estado:';
  if to_regclass('public.notification_events') is null then
    v_falhas := v_falhas || 'notification_events ausente: invariantes nao verificaveis.';
  else
    v_obj_ok := true;

    -- FK de retry_of_event_id -> notification_events(id) ON DELETE RESTRICT
    v_cnt := 0;
    for v_rec in
      select c.conname, c.confdeltype, c.confrelid::regclass::text as destino
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
       where n.nspname='public' and t.relname='notification_events' and c.contype='f'
         and (select a.attnum from pg_attribute a
               where a.attrelid=c.conrelid and a.attname='retry_of_event_id') = any(c.conkey)
    loop
      v_cnt := v_cnt + 1;
      if v_rec.destino not in ('notification_events','public.notification_events') then
        v_falhas := v_falhas || format('FK %s de retry_of_event_id aponta para %s.', v_rec.conname, v_rec.destino);
        v_obj_ok := false;
      end if;
      if v_rec.confdeltype <> 'r' then
        v_falhas := v_falhas || format(
          'FK %s de retry_of_event_id com confdeltype=%s (esperado r = ON DELETE RESTRICT).',
          v_rec.conname, v_rec.confdeltype);
        v_obj_ok := false;
      end if;
    end loop;
    if v_cnt <> 1 then
      v_falhas := v_falhas || format(
        'retry_of_event_id participa de %s FK(s) (esperado exatamente 1, simples e sem FK adicional).', v_cnt);
      v_obj_ok := false;
    end if;

    -- Dados existentes: estado inicial, attempt_count e retry apos envio
    -- Invariantes de attempt_count (a matriz permite pending/scheduled -> failed
    -- ANTES de qualquer envio, caso em que attempt_count = 0 e legitimo).
    execute $q$
      select count(*) from public.notification_events
       where status in ('sending','sent','delivered','read') and attempt_count < 1
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s notificacao(oes) em sending/sent/delivered/read com attempt_count < 1.', v_cnt);
      v_obj_ok := false;
    end if;

    execute $q$
      select count(*) from public.notification_events
       where status = 'failed'
         and (sent_at is not null or provider_message_id is not null)
         and attempt_count < 1
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s notificacao(oes) failed com envio externo e attempt_count < 1.', v_cnt);
      v_obj_ok := false;
    end if;

    -- pending: sempre estado inicial, sem tentativa e sem historico de falha.
    execute $q$
      select count(*) from public.notification_events
       where status = 'pending'
         and (attempt_count <> 0 or first_failed_at is not null or last_failed_at is not null)
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s notificacao(oes) em pending com attempt_count <> 0 ou historico de falha.', v_cnt);
      v_obj_ok := false;
    end if;

    -- scheduled INICIAL: attempt_count = 0 e sem historico de falha.
    execute $q$
      select count(*) from public.notification_events
       where status = 'scheduled'
         and first_failed_at is null
         and attempt_count <> 0
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s notificacao(oes) em scheduled inicial (sem falha registrada) com attempt_count <> 0.', v_cnt);
      v_obj_ok := false;
    end if;

    -- scheduled APOS failed -> scheduled: attempt_count pode ser >= 1, mas o
    -- historico de falha deve estar completo e nao pode haver envio externo.
    execute $q$
      select count(*) from public.notification_events
       where status = 'scheduled'
         and first_failed_at is not null
         and (last_failed_at is null
              or sent_at is not null
              or delivered_at is not null
              or provider_message_id is not null)
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s notificacao(oes) reagendadas com historico de falha incompleto ou com envio externo ja realizado.', v_cnt);
      v_obj_ok := false;
    end if;


    -- Cadeia de retentativa: o anterior deve estar failed COM evidencia de
    -- envio externo, e o novo evento deve ser integralmente equivalente.
    execute $q$
      select count(*)
        from public.notification_events n
        join public.notification_events a on a.id = n.retry_of_event_id
       where n.retry_of_event_id is not null
         and (
              n.retry_of_event_id = n.id
           or a.status <> 'failed'
           or (a.sent_at is null and a.provider_message_id is null)
           or a.channel                 is distinct from n.channel
           or a.recipient_user_id       is distinct from n.recipient_user_id
           or a.recipient_address       is distinct from n.recipient_address
           or a.template_key            is distinct from n.template_key
           or a.template_data           is distinct from n.template_data
           or a.correlation_entity_type is distinct from n.correlation_entity_type
           or a.correlation_entity_id   is distinct from n.correlation_entity_id
           or a.idempotency_key = n.idempotency_key
           or (a.provider_message_id is not null
               and a.provider_message_id = n.provider_message_id)
         )
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s retentativa(s) com cadeia invalida: anterior nao esta failed com envio externo, ou canal/destinatario/template/correlacao divergem, ou reutilizam idempotency_key/provider_message_id.',
        v_cnt);
      v_obj_ok := false;
    end if;

    -- Referencia orfa (FK garante, mas confirmamos os dados existentes).
    execute $q$
      select count(*) from public.notification_events n
       where n.retry_of_event_id is not null
         and not exists (select 1 from public.notification_events a where a.id = n.retry_of_event_id)
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format('%s retry_of_event_id apontando para evento inexistente.', v_cnt);
      v_obj_ok := false;
    end if;

    -- Cadeia sem ramificacao: no maximo UM filho por evento pai.
    execute $q$
      select count(*) from (
        select retry_of_event_id from public.notification_events
         where retry_of_event_id is not null
         group by retry_of_event_id having count(*) > 1) d
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s evento(s) com mais de uma retentativa direta (cadeia ramificada).', v_cnt);
      v_obj_ok := false;
    end if;

    -- Evento PAI referenciado deve permanecer failed e coerente com o filho.
    execute $q$
      select count(*)
        from public.notification_events a
        join public.notification_events f on f.retry_of_event_id = a.id
       where a.status <> 'failed'
          or (a.sent_at is null and a.provider_message_id is null)
          or a.channel                 is distinct from f.channel
          or a.recipient_user_id       is distinct from f.recipient_user_id
          or a.recipient_address       is distinct from f.recipient_address
          or a.template_key            is distinct from f.template_key
          or a.template_data           is distinct from f.template_data
          or a.correlation_entity_type is distinct from f.correlation_entity_type
          or a.correlation_entity_id   is distinct from f.correlation_entity_id
    $q$ into v_cnt;
    if coalesce(v_cnt,0) > 0 then
      v_falhas := v_falhas || format(
        '%s evento(s) pai deixaram de estar failed ou perderam a equivalencia com o filho da cadeia.', v_cnt);
      v_obj_ok := false;
    end if;

    if v_obj_ok then
      raise notice '      OK  FK de retentativa, cadeia sem ramificacao e pais coerentes';
      v_ok := v_ok + 1;
    end if;
  end if;

  -- ====================================================================
  -- [11d] is_site_admin() — hash autoritativo do repositorio
  -- ====================================================================
  raise notice '[11d] is_site_admin() (autoritativa: md5 a65d3c1394e3f45b4afdbf6bba6410a3):';
  v_oid := to_regprocedure('public.is_site_admin()');
  if v_oid is null then
    v_falhas := v_falhas || 'public.is_site_admin() ausente.';
  else
    select md5(lower(regexp_replace(p.prosrc, '\s+', '', 'g'))),
           coalesce(array_to_string(p.proconfig, ','), '')
      into v_txt, v_def
      from pg_proc p where p.oid = v_oid;
    raise notice '      md5(corpo)=% | proconfig=[%]', v_txt, coalesce(nullif(v_def,''), '(vazio)');
    if v_txt is distinct from 'a65d3c1394e3f45b4afdbf6bba6410a3' then
      v_falhas := v_falhas || format(
        'is_site_admin() diverge da definicao autoritativa (md5=%s).', v_txt);
    else
      v_ok := v_ok + 1;
    end if;
    if position('search_path' in coalesce(v_def,'')) = 0 then
      v_falhas := v_falhas ||
        'is_site_admin() continua SECURITY DEFINER sem search_path: exige migration especifica e separada.';
    end if;
  end if;
  v_txt := null; v_def := null;

  -- ====================================================================
  -- [11e] Marcadores de versao: FORA DO ESCOPO deste verificador
  -- ----------------------------------------------------------------------
  -- A conferencia de marcadores desatualizados (por exemplo, referencias a
  -- versoes anteriores da proposta) pertence a VALIDACAO ESTATICA DO
  -- REPOSITORIO, feita por busca textual nos quatro arquivos. Este verificador
  -- roda no banco e NAO tem acesso ao conteudo dos arquivos locais: nao ha
  -- consulta SQL capaz de conferir isso, e nenhuma afirmacao a respeito e feita
  -- aqui. Marcadores proibidos (buscados estaticamente): '(V7)', '(V8)',
  -- 'esta proposta (V7)', 'este pacote (V7)', 'esta proposta (V8)',
  -- 'este pacote (V8)' quando descrevendo a versao atual.
  -- ====================================================================

  -- ====================================================================
  -- [12] Objetos protegidos — presença + hash (comparar com o preflight)
  -- ====================================================================
  raise notice '[12] Objetos protegidos:';
  v_oid := to_regprocedure(
    'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)');
  if v_oid is null then
    v_falhas := v_falhas ||
      'create_my_partner_owner_registration(7x text) ausente ou alterada (deveria estar INTACTA).';
  else
    raise notice '      OK  create_my_partner_owner_registration(7x text) presente';
    raise notice '          md5(pg_get_functiondef) = %', md5(pg_get_functiondef(v_oid));
    raise notice '          md5(prosrc)             = %', (select md5(p.prosrc) from pg_proc p where p.oid=v_oid);
    raise notice '          >>> COMPARE com os hashes do preflight.';
    v_ok := v_ok + 1;
  end if;

  foreach v_nome in array array[
    'commercial_regions','commercial_region_cities','commercial_niches',
    'commercial_exclusivities','commercial_opportunities'
  ] loop
    if to_regclass('public.' || v_nome) is null then
      v_falhas := v_falhas || format('Tabela comercial da Fase 1 ausente: %s.', v_nome);
    else
      v_ok := v_ok + 1;
    end if;
  end loop;
  raise notice '      tabelas comerciais da Fase 1 conferidas (conteudo NAO auditado)';

  -- RPCs comerciais protegidas: MESMO conjunto exigido pelo preflight.
  -- Ausencia ou assinatura divergente e FALHA (nao aviso).
  foreach v_sig in array array[
    'public.resolve_commercial_region(text,text)',
    'public.get_current_commercial_formation(text,text)'
  ] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      v_falhas := v_falhas || format(
        'RPC comercial protegida ausente ou com assinatura divergente: %s (exigida pela base cba451e).', v_sig);
    else
      raise notice '      OK  % | md5(functiondef)=%', v_sig, md5(pg_get_functiondef(v_oid));
      v_ok := v_ok + 1;
    end if;
  end loop;

  -- ====================================================================
  -- VEREDITO
  -- ====================================================================
  raise notice '-----------------------------------------------------------';
  raise notice 'Checagens aprovadas: %', v_ok;
  if array_length(v_falhas, 1) is null then
    raise notice 'POST_FASE2A_MARCO1_OK';
  else
    raise notice 'FALHAS (%):', array_length(v_falhas, 1);
    for v_i in 1 .. array_length(v_falhas, 1) loop
      raise notice '   (%) %', v_i, v_falhas[v_i];
    end loop;
    raise notice '-----------------------------------------------------------';
    raise notice 'POST_FASE2A_MARCO1_COM_FALHAS - revisar antes de prosseguir.';
  end if;
end
$pos$;

-- ============================================================================
-- FIM — somente leitura.
-- ============================================================================
