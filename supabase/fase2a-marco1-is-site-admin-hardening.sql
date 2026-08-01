-- ============================================================================
-- BDFlow - Fase 2A / Marco 1
-- MIGRATION do hardening de public.is_site_admin()  (FAIL-CLOSED / transacional)
-- Arquivo: supabase/fase2a-marco1-is-site-admin-hardening.sql
--
-- NAO EXECUTAR AINDA: este arquivo e para revisao e sera autorizado em comando
-- separado, apos revisao do preflight.
--
-- Unica mutacao de catalogo permitida: fixar search_path = pg_catalog na funcao.
-- Corpo, assinatura, retorno, linguagem, volatilidade, SECURITY DEFINER,
-- proprietario e privilegios diretos permanecem intactos e sao conferidos
-- antes/depois, dentro da mesma transacao.
--
-- Normalizacao de corpo: md5( rtrim( regexp_replace( lower(prosrc),'\s','','g'), ';') )
-- Hash autoritativo esperado: a65d3c1394e3f45b4afdbf6bba6410a3
-- ============================================================================

BEGIN;

DO $migration$
DECLARE
  k_hash constant text := 'a65d3c1394e3f45b4afdbf6bba6410a3';

  v_oid  regprocedure;
  v_sa   regclass;
  v_uid  regprocedure;

  -- estado ANTES
  v_owner_before  oid;
  v_acl_before    aclitem[];
  v_src_before    text;
  v_hash_before   text;
  v_ret_before    oid;
  v_lang_before   name;
  v_vol_before    "char";
  v_secdef_before boolean;
  v_config_before      text[];
  v_schema_before      name;
  v_name_before        name;
  v_nargs_before       int;
  v_proargtypes_before text;
  v_identargs_before   text;

  -- dependencias
  v_uidcol_type text;
  v_uid_ret     text;
  v_uid_nargs   int;

  -- estado DEPOIS
  v_owner_after  oid;
  v_acl_after    aclitem[];
  v_src_after    text;
  v_hash_after   text;
  v_ret_after    oid;
  v_lang_after   name;
  v_vol_after    "char";
  v_secdef_after boolean;
  v_config_after text[];
  v_oid_after          regprocedure;
  v_schema_after       name;
  v_name_after         name;
  v_nargs_after        int;
  v_proargtypes_after  text;
  v_identargs_after    text;
BEGIN
  -- 0) resolver a funcao exata
  v_oid := to_regprocedure('public.is_site_admin()');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'BLOQUEIO: public.is_site_admin() nao existe.';
  END IF;

  -- capturar ANTES
  SELECT
    p.proowner, p.proacl, p.prosrc, p.prorettype, p.provolatile, p.prosecdef,
    p.proconfig, ns.nspname, p.proname, p.pronargs,
    p.proargtypes::text, pg_get_function_identity_arguments(p.oid),
    (SELECT lanname FROM pg_language WHERE oid = p.prolang)
  INTO
    v_owner_before, v_acl_before, v_src_before, v_ret_before, v_vol_before, v_secdef_before,
    v_config_before, v_schema_before, v_name_before, v_nargs_before,
    v_proargtypes_before, v_identargs_before,
    v_lang_before
  FROM pg_proc p
  JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE p.oid = v_oid;

  v_hash_before := md5(rtrim(regexp_replace(lower(v_src_before), '\s', '', 'g'), ';'));

  -- 1) checagens de identidade (fail-closed)
  IF v_schema_before <> 'public'        THEN RAISE EXCEPTION 'BLOQUEIO: schema divergente (%).', v_schema_before; END IF;
  IF v_name_before   <> 'is_site_admin' THEN RAISE EXCEPTION 'BLOQUEIO: nome divergente (%).', v_name_before;   END IF;
  IF v_nargs_before  <> 0               THEN RAISE EXCEPTION 'BLOQUEIO: aridade divergente (esperado 0, obtido %).', v_nargs_before; END IF;
  IF format_type(v_ret_before, NULL) <> 'boolean' THEN RAISE EXCEPTION 'BLOQUEIO: retorno nao e boolean (%).', format_type(v_ret_before, NULL); END IF;
  IF v_lang_before   <> 'sql'           THEN RAISE EXCEPTION 'BLOQUEIO: linguagem nao e sql (%).', v_lang_before; END IF;
  IF v_vol_before    <> 's'             THEN RAISE EXCEPTION 'BLOQUEIO: volatilidade nao e stable.'; END IF;
  IF NOT v_secdef_before                THEN RAISE EXCEPTION 'BLOQUEIO: funcao nao e SECURITY DEFINER.'; END IF;
  IF v_hash_before <> k_hash            THEN RAISE EXCEPTION 'BLOQUEIO: hash do corpo divergente (% != %).', v_hash_before, k_hash; END IF;

  -- referencias seguras (sobre corpo normalizado)
  IF position('public.site_admins' in rtrim(regexp_replace(lower(v_src_before),'\s','','g'),';')) = 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: corpo nao referencia public.site_admins.';
  END IF;
  IF position('auth.uid()' in rtrim(regexp_replace(lower(v_src_before),'\s','','g'),';')) = 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: corpo nao referencia auth.uid().';
  END IF;
  IF position('site_admins' in replace(rtrim(regexp_replace(lower(v_src_before),'\s','','g'),';'),'public.site_admins','')) > 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: referencia nao qualificada a site_admins detectada.';
  END IF;
  IF position('uid(' in replace(rtrim(regexp_replace(lower(v_src_before),'\s','','g'),';'),'auth.uid()','')) > 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: referencia nao qualificada a uid() detectada.';
  END IF;
  IF position('pg_temp' in lower(v_src_before)) > 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: dependencia de pg_temp detectada no corpo.';
  END IF;

  -- 2) dependencias
  v_sa := to_regclass('public.site_admins');
  IF v_sa IS NULL OR (SELECT relkind FROM pg_class WHERE oid = v_sa) <> 'r' THEN
    RAISE EXCEPTION 'BLOQUEIO: public.site_admins ausente ou nao e tabela.';
  END IF;

  SELECT format_type(at.atttypid, at.atttypmod) INTO v_uidcol_type
  FROM pg_attribute at
  WHERE at.attrelid = v_sa AND at.attname = 'user_id' AND at.attnum > 0 AND NOT at.attisdropped;
  IF v_uidcol_type IS NULL THEN RAISE EXCEPTION 'BLOQUEIO: coluna public.site_admins.user_id ausente.'; END IF;
  IF v_uidcol_type <> 'uuid' THEN RAISE EXCEPTION 'BLOQUEIO: public.site_admins.user_id nao e uuid (%).', v_uidcol_type; END IF;

  v_uid := to_regprocedure('auth.uid()');
  IF v_uid IS NULL THEN RAISE EXCEPTION 'BLOQUEIO: auth.uid() ausente.'; END IF;
  SELECT format_type(prorettype, NULL), pronargs INTO v_uid_ret, v_uid_nargs FROM pg_proc WHERE oid = v_uid;
  IF v_uid_ret <> 'uuid' OR v_uid_nargs <> 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: assinatura de auth.uid() divergente (ret=%, nargs=%).', v_uid_ret, v_uid_nargs;
  END IF;

  IF NOT has_table_privilege(pg_get_userbyid(v_owner_before), 'public.site_admins', 'SELECT') THEN
    RAISE EXCEPTION 'BLOQUEIO: proprietario da funcao sem SELECT efetivo em public.site_admins.';
  END IF;

  -- 3) configuracao atual: comparacao do proconfig INTEGRAL (nao filtrado)
  --    - exatamente ARRAY['search_path=pg_catalog'] -> ja aplicado (interrompe)
  --    - NULL ou vazio                              -> segue para o ALTER
  --    - qualquer outro conteudo                    -> BLOQUEIO exibindo tudo
  --      (nao preserva silenciosamente configuracoes adicionais)
  IF v_config_before IS NOT DISTINCT FROM ARRAY['search_path=pg_catalog'] THEN
    RAISE EXCEPTION 'HARDENING_IS_SITE_ADMIN_JA_APLICADO: proconfig ja e exatamente {search_path=pg_catalog}; nada a alterar. Rode a verificacao posterior.';
  END IF;
  IF v_config_before IS NOT NULL AND cardinality(v_config_before) > 0 THEN
    RAISE EXCEPTION 'BLOQUEIO: proconfig pre-existente divergente (integral): [%]. Nenhuma configuracao adicional sera preservada silenciosamente.',
      array_to_string(v_config_before, ' | ');
  END IF;

  -- 4) UNICA MUTACAO (fixar search_path; nao recompila o corpo)
  EXECUTE 'ALTER FUNCTION public.is_site_admin() SET search_path = pg_catalog';

  -- 5) reresolver a funcao pela assinatura exata e reler DEPOIS
  v_oid_after := to_regprocedure('public.is_site_admin()');
  IF v_oid_after IS NULL THEN
    RAISE EXCEPTION 'FALHA POS: public.is_site_admin() nao resolve apos o ALTER.';
  END IF;
  IF v_oid_after <> v_oid THEN
    RAISE EXCEPTION 'FALHA POS: OID resolvido mudou (% -> %).', v_oid::text, v_oid_after::text;
  END IF;

  SELECT
    p.proowner, p.proacl, p.prosrc, p.prorettype, p.provolatile, p.prosecdef, p.proconfig,
    ns.nspname, p.proname, p.pronargs, p.proargtypes::text,
    pg_get_function_identity_arguments(p.oid),
    (SELECT lanname FROM pg_language WHERE oid = p.prolang)
  INTO
    v_owner_after, v_acl_after, v_src_after, v_ret_after, v_vol_after, v_secdef_after, v_config_after,
    v_schema_after, v_name_after, v_nargs_after, v_proargtypes_after,
    v_identargs_after,
    v_lang_after
  FROM pg_proc p
  JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE p.oid = v_oid_after;

  v_hash_after := md5(rtrim(regexp_replace(lower(v_src_after), '\s', '', 'g'), ';'));

  -- 6) proconfig INTEGRAL deve ser exatamente ARRAY['search_path=pg_catalog']
  IF v_config_after IS DISTINCT FROM ARRAY['search_path=pg_catalog'] THEN
    RAISE EXCEPTION 'FALHA POS: proconfig integral nao ficou exatamente {search_path=pg_catalog} (proconfig=[%]).',
      coalesce(array_to_string(v_config_after, ' | '), '<nulo>');
  END IF;

  -- 7) assinatura preservada (identidade estrutural apos o ALTER)
  IF v_schema_after <> 'public'         THEN RAISE EXCEPTION 'FALHA POS: schema deixou de ser public (%).', v_schema_after; END IF;
  IF v_name_after   <> 'is_site_admin'  THEN RAISE EXCEPTION 'FALHA POS: nome deixou de ser is_site_admin (%).', v_name_after; END IF;
  IF v_nargs_after  <> 0                THEN RAISE EXCEPTION 'FALHA POS: aridade deixou de ser 0 (%).', v_nargs_after; END IF;
  IF v_proargtypes_after IS DISTINCT FROM v_proargtypes_before THEN
    RAISE EXCEPTION 'FALHA POS: proargtypes mudou (% -> %).', v_proargtypes_before, v_proargtypes_after; END IF;
  IF coalesce(v_identargs_after, '') <> '' THEN
    RAISE EXCEPTION 'FALHA POS: identity arguments deixaram de ser vazios (%).', v_identargs_after; END IF;
  IF v_identargs_after IS DISTINCT FROM v_identargs_before THEN
    RAISE EXCEPTION 'FALHA POS: identity arguments mudaram (% -> %).', v_identargs_before, v_identargs_after; END IF;

  -- 8) before == after (nada alem de proconfig pode ter mudado)
  IF v_owner_after  IS DISTINCT FROM v_owner_before  THEN RAISE EXCEPTION 'FALHA POS: proprietario mudou.'; END IF;
  IF v_acl_after    IS DISTINCT FROM v_acl_before    THEN RAISE EXCEPTION 'FALHA POS: proacl mudou.'; END IF;
  IF v_src_after    IS DISTINCT FROM v_src_before    THEN RAISE EXCEPTION 'FALHA POS: corpo (prosrc) mudou.'; END IF;
  IF v_hash_after   IS DISTINCT FROM v_hash_before   THEN RAISE EXCEPTION 'FALHA POS: hash do corpo mudou.'; END IF;
  IF v_ret_after    IS DISTINCT FROM v_ret_before    THEN RAISE EXCEPTION 'FALHA POS: retorno mudou.'; END IF;
  IF v_lang_after   IS DISTINCT FROM v_lang_before   THEN RAISE EXCEPTION 'FALHA POS: linguagem mudou.'; END IF;
  IF v_vol_after    IS DISTINCT FROM v_vol_before    THEN RAISE EXCEPTION 'FALHA POS: volatilidade mudou.'; END IF;
  IF v_secdef_after IS DISTINCT FROM v_secdef_before THEN RAISE EXCEPTION 'FALHA POS: SECURITY DEFINER mudou.'; END IF;
  IF v_hash_after   <> k_hash                        THEN RAISE EXCEPTION 'FALHA POS: hash nao corresponde ao autoritativo.'; END IF;

  RAISE NOTICE 'HARDENING_IS_SITE_ADMIN_APLICADO_COM_CORPO_OWNER_E_ACL_INTACTOS';
END
$migration$;

COMMIT;
