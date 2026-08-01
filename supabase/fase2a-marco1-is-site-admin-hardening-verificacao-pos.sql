-- ============================================================================
-- BDFlow - Fase 2A / Marco 1
-- VERIFICACAO POSTERIOR do hardening de public.is_site_admin()
-- Arquivo: supabase/fase2a-marco1-is-site-admin-hardening-verificacao-pos.sql
--
-- ESTRITAMENTE SOMENTE LEITURA. NAO EXECUTAR AINDA: e para revisao.
-- Roda apos a migration. Exibe owner/ACL/proconfig/hashes/definicao para
-- confronto com o snapshot do preflight (a comparacao transacional before/after
-- ja foi feita pela migration; aqui apenas exibimos os valores).
--
-- Normalizacao de corpo: md5( rtrim( regexp_replace( lower(prosrc),'\s','','g'), ';') )
-- Hash autoritativo esperado: a65d3c1394e3f45b4afdbf6bba6410a3
--
-- Veredito final (via NOTICE e coluna "veredito"):
--   HARDENING_IS_SITE_ADMIN_VERIFICADO
--   HARDENING_IS_SITE_ADMIN_VERIFICACAO_FALHOU
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Snapshot pos + checagens + veredito (uma linha)
-- ----------------------------------------------------------------------------
WITH alvo AS (
  SELECT to_regprocedure('public.is_site_admin()') AS fn_oid
),
deps AS (
  SELECT to_regclass('public.site_admins') AS sa_oid,
         to_regprocedure('auth.uid()')     AS uid_oid
),
base AS (
  SELECT
    p.oid                                                      AS p_oid,
    p.proname, n.nspname AS schema, p.pronargs,
    p.proowner, pg_get_userbyid(p.proowner)                    AS owner_name,
    p.proacl, p.prosrc, p.prorettype, p.provolatile, p.prosecdef, p.proconfig,
    l.lanname                                                  AS language,
    pg_get_functiondef(p.oid)                                  AS functiondef,
    rtrim(regexp_replace(lower(p.prosrc), '\s', '', 'g'), ';') AS body_norm,
    d.sa_oid, d.uid_oid
  FROM alvo a
  LEFT JOIN pg_proc      p ON p.oid = a.fn_oid
  LEFT JOIN pg_namespace n ON n.oid = p.pronamespace
  LEFT JOIN pg_language  l ON l.oid = p.prolang
  CROSS JOIN deps d
),
calc AS (
  SELECT
    b.*,
    -- configuracao avaliada sobre o proconfig INTEGRAL
    (b.proconfig IS NOT DISTINCT FROM ARRAY['search_path=pg_catalog'])                                   AS d_config_igual_esperado,
    -- dependencia public.site_admins
    (SELECT format_type(at.atttypid, at.atttypmod)
       FROM pg_attribute at
      WHERE at.attrelid = b.sa_oid AND at.attname='user_id' AND at.attnum>0 AND NOT at.attisdropped)     AS c_user_id_tipo,
    -- dependencia auth.uid() por assinatura exata
    (SELECT format_type(up.prorettype, NULL) FROM pg_proc up WHERE up.oid = b.uid_oid)                   AS c_auth_uid_ret,
    (SELECT up.pronargs FROM pg_proc up WHERE up.oid = b.uid_oid)                                        AS c_auth_uid_nargs,
    -- proprietario da funcao com SELECT efetivo em public.site_admins
    (b.owner_name IS NOT NULL AND b.sa_oid IS NOT NULL
       AND has_table_privilege(b.owner_name, b.sa_oid, 'SELECT'))                                        AS c_owner_select_efetivo,
    -- RPCs protegidas resolvidas por SCHEMA + ASSINATURA EXATA (to_regprocedure)
    to_regprocedure('public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')  AS rpc_owner_reg_oid,
    to_regprocedure('public.resolve_commercial_region(text,text)')                                      AS rpc_resolve_region_oid,
    to_regprocedure('public.get_current_commercial_formation(text,text)')                               AS rpc_get_formation_oid
  FROM base b
)
SELECT
  c.p_oid                                                        AS oid,
  (c.p_oid IS NOT NULL)                                          AS existe,
  c.schema, c.proname, c.pronargs,
  format_type(c.prorettype, NULL)                               AS retorno,
  c.language                                                    AS linguagem,
  CASE c.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' WHEN 'v' THEN 'volatile' END AS volatilidade,
  c.prosecdef                                                   AS security_definer,
  c.proconfig                                                   AS proconfig_integral,
  c.d_config_igual_esperado,
  c.proowner                                                    AS owner_oid,
  c.owner_name,
  c.proacl,
  md5(coalesce(c.proacl::text, ''))                             AS md5_proacl,
  c.body_norm                                                   AS corpo_normalizado,
  md5(coalesce(c.body_norm, ''))                                AS md5_corpo,
  md5(coalesce(c.functiondef, ''))                              AS md5_functiondef,
  -- checagens
  (c.d_config_igual_esperado)                                   AS proconfig_ok,
  (md5(coalesce(c.body_norm,'')) = 'a65d3c1394e3f45b4afdbf6bba6410a3') AS hash_corpo_ok,
  (position('public.site_admins' in coalesce(c.body_norm,'')) > 0)    AS ref_site_admins,
  (position('auth.uid()' in coalesce(c.body_norm,'')) > 0)           AS ref_auth_uid,
  (position('pg_temp' in coalesce(c.body_norm,'')) = 0)             AS sem_pg_temp,
  -- dependencia site_admins (nome preciso; cobre existencia, relkind, tipo da coluna e SELECT do owner)
  (c.sa_oid IS NOT NULL AND (SELECT relkind FROM pg_class WHERE oid=c.sa_oid)='r'
     AND c.c_user_id_tipo='uuid' AND c.c_owner_select_efetivo)  AS dependencia_site_admins_valida,
  (c.c_user_id_tipo = 'uuid')                                   AS c_user_id_uuid,
  c.c_owner_select_efetivo,
  -- dependencia auth.uid() por assinatura exata
  (c.uid_oid IS NOT NULL)                                       AS c_auth_uid_existe,
  (c.c_auth_uid_ret = 'uuid' AND c.c_auth_uid_nargs = 0)        AS c_auth_uid_uuid_0args,
  -- RPCs protegidas: OID + assinatura encontrada (para revisao) e presenca por assinatura exata
  c.rpc_owner_reg_oid,
  pg_get_function_identity_arguments(c.rpc_owner_reg_oid)       AS rpc_owner_reg_assinatura,
  (c.rpc_owner_reg_oid IS NOT NULL)                             AS rpc_owner_reg,
  c.rpc_resolve_region_oid,
  pg_get_function_identity_arguments(c.rpc_resolve_region_oid)  AS rpc_resolve_region_assinatura,
  (c.rpc_resolve_region_oid IS NOT NULL)                        AS rpc_resolve_region,
  c.rpc_get_formation_oid,
  pg_get_function_identity_arguments(c.rpc_get_formation_oid)   AS rpc_get_formation_assinatura,
  (c.rpc_get_formation_oid IS NOT NULL)                         AS rpc_get_formation,
  -- veredito
  CASE WHEN (
        c.p_oid IS NOT NULL
    AND c.schema='public' AND c.proname='is_site_admin' AND c.pronargs=0
    AND format_type(c.prorettype,NULL)='boolean'
    AND c.language='sql' AND c.provolatile='s' AND c.prosecdef
    AND c.d_config_igual_esperado
    AND md5(coalesce(c.body_norm,''))='a65d3c1394e3f45b4afdbf6bba6410a3'
    AND position('public.site_admins' in coalesce(c.body_norm,''))>0
    AND position('auth.uid()' in coalesce(c.body_norm,''))>0
    AND position('pg_temp' in coalesce(c.body_norm,''))=0
    AND c.sa_oid IS NOT NULL AND (SELECT relkind FROM pg_class WHERE oid=c.sa_oid)='r'
    AND c.c_user_id_tipo='uuid' AND c.c_owner_select_efetivo
    AND c.uid_oid IS NOT NULL AND c.c_auth_uid_ret='uuid' AND c.c_auth_uid_nargs=0
    AND c.rpc_owner_reg_oid IS NOT NULL
    AND c.rpc_resolve_region_oid IS NOT NULL
    AND c.rpc_get_formation_oid IS NOT NULL
  ) THEN 'HARDENING_IS_SITE_ADMIN_VERIFICADO'
    ELSE 'HARDENING_IS_SITE_ADMIN_VERIFICACAO_FALHOU'
  END                                                           AS veredito,
  c.functiondef                                                 AS definicao_integral
FROM calc c;


-- ----------------------------------------------------------------------------
-- Privilegios diretos (aclexplode) - somente leitura
-- ----------------------------------------------------------------------------
SELECT
  pg_get_userbyid(ax.grantor)                                        AS concedente,
  CASE WHEN ax.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(ax.grantee) END AS beneficiario,
  ax.privilege_type,
  ax.is_grantable
FROM pg_proc p
CROSS JOIN LATERAL aclexplode(p.proacl) ax
WHERE p.oid = to_regprocedure('public.is_site_admin()')
ORDER BY beneficiario, ax.privilege_type;


-- ----------------------------------------------------------------------------
-- Veredito loud + lista de falhas (somente leitura; NOTICE)
-- ----------------------------------------------------------------------------
DO $verif$
DECLARE
  v_oid regprocedure := to_regprocedure('public.is_site_admin()');
  v_sa  regclass     := to_regclass('public.site_admins');
  v_uid regprocedure := to_regprocedure('auth.uid()');
  fail  text[] := '{}';
  v_src text; v_hash text; v_ret text; v_lang name; v_vol "char"; v_secdef boolean;
  v_config text[]; v_uidcol text; v_owner oid;
  v_uid_ret text; v_uid_nargs int;
  v_rpc_owner_reg      regprocedure := to_regprocedure('public.create_my_partner_owner_registration(text,text,text,text,text,text,text)');
  v_rpc_resolve_region regprocedure := to_regprocedure('public.resolve_commercial_region(text,text)');
  v_rpc_get_formation  regprocedure := to_regprocedure('public.get_current_commercial_formation(text,text)');
BEGIN
  IF v_oid IS NULL THEN
    fail := array_append(fail, 'funcao is_site_admin() ausente');
  ELSE
    SELECT p.prosrc, format_type(p.prorettype, NULL),
           (SELECT lanname FROM pg_language WHERE oid = p.prolang),
           p.provolatile, p.prosecdef, p.proconfig, p.proowner
      INTO v_src, v_ret, v_lang, v_vol, v_secdef, v_config, v_owner
      FROM pg_proc p WHERE p.oid = v_oid;

    v_hash := md5(rtrim(regexp_replace(lower(v_src), '\s', '', 'g'), ';'));

    IF v_ret  <> 'boolean' THEN fail := array_append(fail, 'retorno nao e boolean'); END IF;
    IF v_lang <> 'sql'     THEN fail := array_append(fail, 'linguagem nao e sql'); END IF;
    IF v_vol  <> 's'       THEN fail := array_append(fail, 'volatilidade nao e stable'); END IF;
    IF NOT v_secdef        THEN fail := array_append(fail, 'nao e SECURITY DEFINER'); END IF;
    IF v_hash <> 'a65d3c1394e3f45b4afdbf6bba6410a3' THEN fail := array_append(fail, 'hash do corpo divergente'); END IF;
    IF position('public.site_admins' in rtrim(regexp_replace(lower(v_src),'\s','','g'),';')) = 0 THEN fail := array_append(fail, 'sem referencia a public.site_admins'); END IF;
    IF position('auth.uid()' in rtrim(regexp_replace(lower(v_src),'\s','','g'),';')) = 0 THEN fail := array_append(fail, 'sem referencia a auth.uid()'); END IF;
    IF position('pg_temp' in lower(v_src)) > 0 THEN fail := array_append(fail, 'dependencia de pg_temp'); END IF;

    -- proconfig INTEGRAL deve ser exatamente {search_path=pg_catalog}
    IF v_config IS DISTINCT FROM ARRAY['search_path=pg_catalog'] THEN
      fail := array_append(fail, 'proconfig integral nao e exatamente {search_path=pg_catalog}: ['
        || coalesce(array_to_string(v_config,' | '),'<nulo>') || ']');
    END IF;
  END IF;

  -- dependencia public.site_admins (valida = tabela + user_id uuid + SELECT do owner)
  IF v_sa IS NULL OR (SELECT relkind FROM pg_class WHERE oid = v_sa) <> 'r' THEN
    fail := array_append(fail, 'dependencia_site_admins_valida: tabela public.site_admins ausente/invalida');
  ELSE
    SELECT format_type(at.atttypid, at.atttypmod) INTO v_uidcol
      FROM pg_attribute at
     WHERE at.attrelid = v_sa AND at.attname='user_id' AND at.attnum>0 AND NOT at.attisdropped;
    IF v_uidcol IS DISTINCT FROM 'uuid' THEN fail := array_append(fail, 'dependencia_site_admins_valida: user_id ausente ou nao uuid'); END IF;
    IF v_owner IS NULL OR NOT has_table_privilege(pg_get_userbyid(v_owner), v_sa, 'SELECT') THEN
      fail := array_append(fail, 'dependencia_site_admins_valida: proprietario da funcao sem SELECT efetivo em public.site_admins');
    END IF;
  END IF;

  -- dependencia auth.uid() por assinatura exata
  IF v_uid IS NULL THEN
    fail := array_append(fail, 'auth.uid() ausente');
  ELSE
    SELECT format_type(prorettype, NULL), pronargs INTO v_uid_ret, v_uid_nargs FROM pg_proc WHERE oid = v_uid;
    IF v_uid_ret <> 'uuid' OR v_uid_nargs <> 0 THEN
      fail := array_append(fail, 'auth.uid() assinatura divergente (ret=' || coalesce(v_uid_ret,'<nulo>') || ', nargs=' || coalesce(v_uid_nargs::text,'<nulo>') || ')');
    END IF;
  END IF;

  -- RPCs protegidas resolvidas por SCHEMA + ASSINATURA EXATA
  IF v_rpc_owner_reg IS NULL
    THEN fail := array_append(fail, 'create_my_partner_owner_registration(text,text,text,text,text,text,text) ausente na assinatura exata'); END IF;
  IF v_rpc_resolve_region IS NULL
    THEN fail := array_append(fail, 'resolve_commercial_region(text,text) ausente na assinatura exata'); END IF;
  IF v_rpc_get_formation IS NULL
    THEN fail := array_append(fail, 'get_current_commercial_formation(text,text) ausente na assinatura exata'); END IF;

  IF cardinality(fail) = 0 THEN
    RAISE NOTICE 'HARDENING_IS_SITE_ADMIN_VERIFICADO';
  ELSE
    RAISE NOTICE 'FALHAS (%): %', cardinality(fail), array_to_string(fail, ' | ');
    RAISE NOTICE 'HARDENING_IS_SITE_ADMIN_VERIFICACAO_FALHOU';
  END IF;
END
$verif$;
