-- ============================================================================
-- Registro da migration 20261103120000 no histórico do CLI, DEPOIS de aplicá-la
-- pelo conteúdo exato do arquivo (SQL Editor ou execute_sql — nunca
-- apply_migration, que gravaria outro número de versão).
--
-- Pré-condições (qualquer falha aborta sem gravar nada):
--   1. histórico reconciliado (62 linhas, hash do repositório);
--   2. IMPRESSÃO DIGITAL do que foi executado: as 28 funções que a migration
--      define (27 nomes; is_fidelized_context tem 2 assinaturas), por
--      assinatura + md5(prosrc) + SECURITY DEFINER + volatilidade +
--      search_path, têm de bater com 33d122ef4ed5c0af806c9d27f61ba7fb/28.
--      prosrc é o texto literal do corpo, igual em PG16 e PG17; o valor foi
--      medido aplicando o arquivo abaixo (via psql -f e em consulta única).
--      Um arquivo diferente, truncado ou de outra revisão não passa.
--   3. objetos e catálogo esperados (tabelas de segmento, 6 posições, 84 un.).
--
-- Arquivo: supabase/migrations/20261103120000_commercial_positions_segments.sql
-- sha256 da revisão FINAL (blob git 2d9fd44f639f4e0e32bdd8884dbaf4de0f5bb688):
--   3a6436a3f9645545bb201be70c99bff02e87d261cc977f2cfaedb568cf1af3b1
-- Atenção: no patch o arquivo aparece duas vezes (criado no commit 1/5,
-- alterado no 3/5). O sha256 da primeira versão (8dfad66c...) NÃO é o
-- aplicável. Confira com:  git show <HEAD>:<arquivo> | sha256sum
-- ============================================================================
BEGIN;
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;
DO $reg$
DECLARE v_n int; v_h text; v_fp text;
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
  SELECT pg_catalog.md5(pg_catalog.string_agg(
           p.oid::pg_catalog.regprocedure::text||':'||pg_catalog.md5(p.prosrc)||':'||p.prosecdef::text
           ||':'||p.provolatile::text||':'||coalesce(pg_catalog.array_to_string(p.proconfig, ','), ''),
           ',' ORDER BY p.oid::pg_catalog.regprocedure::text)) || '/' || count(*)
    INTO v_fp
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname IN ('admin_archive_commercial_segment','admin_create_commercial_segment','admin_decide_commercial_segment_request','admin_list_commercial_segments','admin_register_manual_commercial_order','build_app_provisioning_payload','calculate_niche_contract_pricing','cci_resposta_intencao','ceo_segmento_da_intencao','cfr_derivar_identidade','commercial_build_instrument_snapshot','commercial_fidelity_identity','commercial_normalize_segment_label','commercial_resolve_position_segment','commercial_segment_requests_protect','commercial_segment_snapshot_imutavel','commercial_segments_protect','create_commercial_checkout_intent','finalize_commercial_order_from_intent','get_current_commercial_formation','get_my_commercial_future_interest','get_my_commercial_segment_requests','get_my_company_commercial_summary','is_fidelized_context','join_my_commercial_future_queue','list_commercial_segments','request_commercial_segment');
  IF v_fp IS DISTINCT FROM '33d122ef4ed5c0af806c9d27f61ba7fb/28' THEN
    RAISE EXCEPTION 'registro_abortado: impressao digital das funcoes diverge do arquivo revisado (%)', v_fp;
  END IF;
  IF (SELECT sum(contracted_quantity) FROM public.commercial_niches WHERE is_active) <> 84
  OR pg_catalog.to_regclass('public.commercial_segment_requests') IS NULL THEN
    RAISE EXCEPTION 'registro_abortado: catalogo ou objetos da migration incompletos';
  END IF;
  INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
  VALUES ('20261103120000', 'commercial_positions_segments',
          ARRAY['-- aplicado pelo conteudo exato do arquivo do repositorio; sha256 3a6436a3f9645545bb201be70c99bff02e87d261cc977f2cfaedb568cf1af3b1; impressao verificada ' || v_fp],
          'etapa-b-publicacao-coordenada');
END $reg$;
COMMIT;
