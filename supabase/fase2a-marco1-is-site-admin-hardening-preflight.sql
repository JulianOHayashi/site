-- ============================================================================
-- BDFlow - Fase 2A / Marco 1
-- PREFLIGHT do hardening de public.is_site_admin()
-- Arquivo: supabase/fase2a-marco1-is-site-admin-hardening-preflight.sql
--
-- ESTRITAMENTE SOMENTE LEITURA (nenhuma instrucao de escrita de qualquer tipo).
-- NAO EXECUTAR AINDA: este arquivo e para revisao.
--
-- Normalizacao de corpo (identica nos tres SQLs do marco):
--   md5( rtrim( regexp_replace( lower(prosrc), '\s', '', 'g' ), ';' ) )
-- Hash autoritativo esperado: a65d3c1394e3f45b4afdbf6bba6410a3
--
-- Vereditos possiveis (coluna "veredito" do resultado principal):
--   HARDENING_IS_SITE_ADMIN_PREFLIGHT_READY    -> pronto para a migration
--   HARDENING_IS_SITE_ADMIN_ALREADY_APPLIED    -> ja fixado; so rode a verificacao
--   HARDENING_IS_SITE_ADMIN_PREFLIGHT_BLOCKED  -> identidade/dependencia/config divergente
-- ============================================================================


-- ----------------------------------------------------------------------------
-- SECOES A + B + C + D + E: snapshot, checagens e veredito (uma linha)
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
    a.fn_oid,
    p.oid                                                      AS p_oid,
    p.proname,
    n.nspname                                                  AS schema,
    p.pronargs,
    p.proowner,
    pg_get_userbyid(p.proowner)                                AS owner_name,
    p.proacl,
    p.prosrc,
    p.prorettype,
    p.provolatile,
    p.prosecdef,
    p.proconfig,
    p.proargtypes::text                                        AS proargtypes,
    pg_get_function_identity_arguments(p.oid)                  AS identity_args,
    l.lanname                                                  AS language,
    pg_get_functiondef(p.oid)                                  AS functiondef,
    rtrim(regexp_replace(lower(p.prosrc), '\s', '', 'g'), ';') AS body_norm,
    d.sa_oid,
    d.uid_oid
  FROM alvo a
  LEFT JOIN pg_proc      p ON p.oid = a.fn_oid
  LEFT JOIN pg_namespace n ON n.oid = p.pronamespace
  LEFT JOIN pg_language  l ON l.oid = p.prolang
  CROSS JOIN deps d
),
calc AS (
  SELECT
    b.*,
    -- referencias qualificadas / seguras (sobre corpo normalizado)
    (position('public.site_admins' in coalesce(b.body_norm,'')) > 0)                                     AS b_ref_site_admins,
    (position('auth.uid()'         in coalesce(b.body_norm,'')) > 0)                                     AS b_ref_auth_uid,
    (position('site_admins' in replace(coalesce(b.body_norm,''),'public.site_admins','')) = 0)           AS b_site_admins_qualificada,
    (position('uid('        in replace(coalesce(b.body_norm,''),'auth.uid()','')) = 0)                   AS b_uid_qualificada,
    (position('pg_temp'     in coalesce(b.body_norm,'')) = 0)                                            AS b_sem_pg_temp,
    -- dependencias
    (b.sa_oid IS NOT NULL AND (SELECT c.relkind FROM pg_class c WHERE c.oid = b.sa_oid) = 'r')           AS c_site_admins_tabela,
    (SELECT format_type(at.atttypid, at.atttypmod)
       FROM pg_attribute at
      WHERE at.attrelid = b.sa_oid AND at.attname = 'user_id' AND at.attnum > 0 AND NOT at.attisdropped) AS c_user_id_tipo,
    (b.uid_oid IS NOT NULL)                                                                              AS c_auth_uid_existe,
    (SELECT format_type(up.prorettype, NULL) FROM pg_proc up WHERE up.oid = b.uid_oid)                   AS c_auth_uid_ret,
    (SELECT up.pronargs FROM pg_proc up WHERE up.oid = b.uid_oid)                                        AS c_auth_uid_nargs,
    (b.owner_name IS NOT NULL AND b.sa_oid IS NOT NULL
       AND has_table_privilege(b.owner_name, b.sa_oid, 'SELECT'))                                        AS c_owner_select_efetivo,
    -- configuracao atual: avaliada SOBRE O proconfig INTEGRAL (nao filtrado)
    (b.proconfig IS NULL OR cardinality(b.proconfig) = 0)                                                AS d_config_vazia,
    (b.proconfig IS NOT DISTINCT FROM ARRAY['search_path=pg_catalog'])                                   AS d_config_igual_esperado,
    -- helper informativo (NAO usado para o veredito): apenas as entradas search_path=
    (SELECT array_agg(x ORDER BY x)
       FROM unnest(coalesce(b.proconfig, '{}'::text[])) x
      WHERE x LIKE 'search_path=%')                                                                      AS search_path_entradas
  FROM base b
)
SELECT
  -- E: snapshot
  c.p_oid                                                       AS oid,
  (c.p_oid IS NOT NULL)                                         AS a_existe,
  c.schema,
  c.proname,
  c.pronargs,
  format_type(c.prorettype, NULL)                              AS retorno,
  c.language                                                   AS linguagem,
  CASE c.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' WHEN 'v' THEN 'volatile' END AS volatilidade,
  c.prosecdef                                                  AS security_definer,
  c.proowner                                                   AS owner_oid,
  c.owner_name,
  c.proacl,
  md5(coalesce(c.proacl::text, ''))                            AS md5_proacl,
  c.proargtypes,
  c.identity_args,
  c.body_norm                                                  AS corpo_normalizado,
  md5(coalesce(c.body_norm, ''))                               AS md5_corpo,
  md5(coalesce(c.functiondef, ''))                             AS md5_functiondef,
  c.proconfig                                                  AS proconfig_integral,
  c.d_config_vazia,
  c.d_config_igual_esperado,
  c.search_path_entradas,
  -- A: identidade
  (md5(coalesce(c.body_norm,'')) = 'a65d3c1394e3f45b4afdbf6bba6410a3') AS a_hash_corpo_ok,
  -- B: referencias
  c.b_ref_site_admins,
  c.b_ref_auth_uid,
  c.b_site_admins_qualificada,
  c.b_uid_qualificada,
  c.b_sem_pg_temp,
  -- C: dependencias
  c.c_site_admins_tabela,
  (c.c_user_id_tipo IS NOT NULL)                               AS c_user_id_existe,
  (c.c_user_id_tipo = 'uuid')                                  AS c_user_id_uuid,
  c.c_auth_uid_existe,
  (c.c_auth_uid_ret = 'uuid' AND c.c_auth_uid_nargs = 0)       AS c_auth_uid_uuid_0args,
  c.c_owner_select_efetivo,
  -- identidade completa (A+B+C)
  (
        c.p_oid IS NOT NULL
    AND c.schema = 'public' AND c.proname = 'is_site_admin' AND c.pronargs = 0
    AND format_type(c.prorettype, NULL) = 'boolean'
    AND c.language = 'sql' AND c.provolatile = 's' AND c.prosecdef
    AND md5(coalesce(c.body_norm,'')) = 'a65d3c1394e3f45b4afdbf6bba6410a3'
    AND c.b_ref_site_admins AND c.b_ref_auth_uid
    AND c.b_site_admins_qualificada AND c.b_uid_qualificada AND c.b_sem_pg_temp
    AND c.c_site_admins_tabela AND c.c_user_id_tipo = 'uuid'
    AND c.c_auth_uid_existe AND c.c_auth_uid_ret = 'uuid' AND c.c_auth_uid_nargs = 0
    AND c.c_owner_select_efetivo
  )                                                            AS identidade_ok,
  -- D + veredito
  CASE
    WHEN NOT (
          c.p_oid IS NOT NULL
      AND c.schema = 'public' AND c.proname = 'is_site_admin' AND c.pronargs = 0
      AND format_type(c.prorettype, NULL) = 'boolean'
      AND c.language = 'sql' AND c.provolatile = 's' AND c.prosecdef
      AND md5(coalesce(c.body_norm,'')) = 'a65d3c1394e3f45b4afdbf6bba6410a3'
      AND c.b_ref_site_admins AND c.b_ref_auth_uid
      AND c.b_site_admins_qualificada AND c.b_uid_qualificada AND c.b_sem_pg_temp
      AND c.c_site_admins_tabela AND c.c_user_id_tipo = 'uuid'
      AND c.c_auth_uid_existe AND c.c_auth_uid_ret = 'uuid' AND c.c_auth_uid_nargs = 0
      AND c.c_owner_select_efetivo
    ) THEN 'HARDENING_IS_SITE_ADMIN_PREFLIGHT_BLOCKED'
    -- decisao de configuracao sobre o proconfig INTEGRAL:
    --   NULL/vazio                                  -> READY
    --   exatamente ARRAY['search_path=pg_catalog']  -> ALREADY_APPLIED
    --   qualquer outro conteudo (search_path diferente, correto + extra,
    --   apenas config nao relacionada, multiplas entradas, valor inesperado)
    --                                               -> BLOCKED
    WHEN c.d_config_igual_esperado
      THEN 'HARDENING_IS_SITE_ADMIN_ALREADY_APPLIED'
    WHEN c.d_config_vazia
      THEN 'HARDENING_IS_SITE_ADMIN_PREFLIGHT_READY'
    ELSE 'HARDENING_IS_SITE_ADMIN_PREFLIGHT_BLOCKED'
  END                                                          AS veredito,
  c.functiondef                                                AS definicao_integral
FROM calc c;


-- ----------------------------------------------------------------------------
-- E (cont.): privilegios diretos da funcao (aclexplode) - somente leitura
-- Se nao retornar linhas, o proacl e o default/implicito (proacl NULL).
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
