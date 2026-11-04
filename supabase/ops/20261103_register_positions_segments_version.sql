-- ============================================================================
-- Registro da migration 20261103120000 no histórico do CLI, DEPOIS de aplicá-la
-- pelo conteúdo exato do arquivo (SQL Editor ou execute_sql — nunca
-- apply_migration, que gravaria outro número de versão).
--
-- Pré-condições: a reconciliação já foi feita (62 linhas, hash do repositório)
-- e os objetos da migration existem. Sem isso, aborta sem gravar nada.
-- sha256 do arquivo aplicado: 3a6436a3f9645545bb201be70c99bff02e87d261cc977f2cfaedb568cf1af3b1
-- ============================================================================
BEGIN;
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;
DO $reg$
DECLARE v_n int; v_h text;
BEGIN
  SELECT count(*), md5(string_agg(version||':'||name, ',' ORDER BY version||':'||name))
    INTO v_n, v_h FROM supabase_migrations.schema_migrations;
  IF v_n <> 62 OR v_h <> 'c9924f1092689753d1bdfb59670aa8c4' THEN
    RAISE EXCEPTION 'registro_abortado: historico nao reconciliado (linhas=%, hash=%)', v_n, v_h;
  END IF;
  IF pg_catalog.to_regclass('public.commercial_segments') IS NULL
  OR pg_catalog.to_regprocedure('public.create_commercial_checkout_intent(uuid,text,text,uuid)') IS NULL
  OR (SELECT count(*) FROM public.commercial_niches WHERE is_active) <> 6 THEN
    RAISE EXCEPTION 'registro_abortado: migration 20261103120000 nao esta aplicada';
  END IF;
  INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
  VALUES ('20261103120000', 'commercial_positions_segments',
          ARRAY['-- aplicado pelo conteudo exato do arquivo do repositorio; sha256 3a6436a3f9645545bb201be70c99bff02e87d261cc977f2cfaedb568cf1af3b1'],
          'etapa-b-publicacao-coordenada');
END $reg$;
COMMIT;
