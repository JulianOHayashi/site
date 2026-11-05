-- ============================================================================
-- Registro da versão 20261103120000 (63ª) no histórico do CLI, DEPOIS de
-- aplicar a migration pelo conteúdo exato do arquivo, numa única execução.
--
-- Só grava se TUDO abaixo for verdade; senão aborta sem gravar nada:
--   1. histórico reconciliado: 62 linhas, hash c9924f10… e a versão ainda
--      não registrada;
--   2. cada uma das 28 funções que a migration cria está no banco com o
--      MESMO corpo (md5 de prosrc), SECURITY DEFINER, volatilidade,
--      search_path e linguagem do manifesto — e nenhuma a mais com esses
--      nomes. A comparação é por função, com assinatura canônica
--      (search_path fixo em pg_catalog), então não depende da versão do
--      PostgreSQL nem da sessão; a mensagem de erro diz QUAL função difere e
--      COMO (CR, comentários, codificação, conteúdo, atributos);
--   3. tabelas, índices, gatilhos e restrições da migration presentes;
--   4. catálogo: 6 posições ativas, 84 unidades, Calçados gravado em UTF-8,
--      calçados F/M inativos.
--
-- Arquivo: supabase/migrations/20261103120000_commercial_positions_segments.sql
-- sha256 do arquivo revisado: d1b0fdbe6a55201cb96fd1799777a42bf8c6e6bd1364d41c8387641b7b7302f4
-- Manifesto: 28 funções (md5 do manifesto f6dee6c2fadd306a53dcfdde05086f1e), 2 tabelas,
-- 6 índices, 8 gatilhos, 21 restrições.
-- Gerado por scripts/db-test/gen-register-version.py (não editar à mão).
-- ============================================================================
BEGIN;
SET LOCAL search_path = pg_catalog;
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;
DO $reg$
DECLARE v_n int; v_h text; v_dif text; v_ndif int; v_obj text;
BEGIN
  SELECT count(*), md5(string_agg(version || ':' || name, ',' ORDER BY version || ':' || name))
    INTO v_n, v_h FROM supabase_migrations.schema_migrations;
  IF v_n <> 62 OR v_h <> 'c9924f1092689753d1bdfb59670aa8c4' THEN
    RAISE EXCEPTION 'registro_abortado: historico nao esta no estado reconciliado (linhas=%, hash=%)', v_n, v_h;
  END IF;

  WITH esperado(assinatura, md5_src, md5_norm, secdef, volat, config, lang) AS (
      VALUES
        ('public.admin_archive_commercial_segment(uuid)', '9c66e8a1be77c8e9d775cf7df2bc0b4e', 'c0a5fe3fd57a86dabaf55ef4dfcb04b9', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.admin_create_commercial_segment(text,text,text,text,text,text)', '16608d2715b9bd6036dfa54684173099', 'b2d4d200c9ee21baecdf51a4253a3e4c', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.admin_decide_commercial_segment_request(uuid,text,uuid,text,text,text,text,text,text)', 'b596c07c4c197831a62a6bf1287ce390', '4ca98eeb9b6239caa8e22a78b5edfe1f', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.admin_list_commercial_segments()', 'c28ade39a60aaf500a84d506534f00dc', '46c8f08cc726ab241ba166c8c4b5b1d3', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer,uuid)', 'b359c76391d7e46d22d6bc6240f1c9ff', 'ee4daf1bc2fe563ca58ae343f8b39246', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.build_app_provisioning_payload(uuid,text)', '6170302780aea59f2ed4af060258aa33', '9baa55eca32c3f379d4b035cf9c4cd92', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.calculate_niche_contract_pricing(text,boolean,integer)', '0e8e969f9ebf380315091ef51d4c3884', '37a7873c1453fcf23cd1fb9436e95bff', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.cci_resposta_intencao(public.commercial_checkout_intents,boolean)', 'e4ecd698c55e08c74900c9b772cdb825', '333a839a805377df411aaa23dce3b8b9', 'false', 'i', 'search_path=pg_catalog', 'sql'),
        ('public.ceo_segmento_da_intencao()', 'd2b1c17c82fa6b871196c3271f96dd78', '0d635e8236b17fb79acf4f19aca50586', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.cfr_derivar_identidade()', '3e0f2c514cf65df5f23981ee43afb4b5', '2bab036caae04a09b0cb74f133f886e5', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.commercial_build_instrument_snapshot(uuid,uuid)', 'a722d810fabc327f8fbfac9c008efced', 'd19d56b1f442df950da2b4fa0c2d37a8', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.commercial_fidelity_identity(text,uuid)', 'fdc4f1e9cc0a9fb203a80a1e76d335e5', '281e5cdc3b66048212d3808a2c19cb62', 'true', 's', 'search_path=pg_catalog', 'sql'),
        ('public.commercial_normalize_segment_label(text)', '10c6e2af52be2e10357444c8b315c74b', '53472c2a6bd9a289a99462309ae29f4d', 'false', 'i', 'search_path=pg_catalog', 'sql'),
        ('public.commercial_resolve_position_segment(text,uuid,uuid,uuid,boolean)', 'ebd866d4a81087d3f724568cb3b31050', '728856bf32cb8ecc13799e5ed6926268', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.commercial_segment_requests_protect()', 'b79e8db381f60d0a429039908bd613f2', '0813f4e027790b9717ed32652b6555f2', 'false', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.commercial_segment_snapshot_imutavel()', 'f1e0c120892830737e0760a855a0cb6a', 'a19bf6bd4b89f9936169c8b589cd69ee', 'false', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.commercial_segments_protect()', 'e0d3872ab68a1a930e3850375585b58a', '2d867828c47fe1eaac53cfc6ce1dcd6a', 'false', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.create_commercial_checkout_intent(uuid,text,text,uuid)', '536be9b7a9ffdd3ce1a734ab08ff1d90', '898d0aa37bd4179e29c91954d5cb1082', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.finalize_commercial_order_from_intent(uuid)', 'd0d049ee409c020e35a81f27a6382c4c', '52fef8ef4418ca3fcf7f142028da3cdd', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.get_current_commercial_formation(text,text)', '71440f5f0a27ac5a94d4bd899b155f2d', '5471c6abaf759cd4f7ae1b715c6bd188', 'true', 's', 'search_path=public', 'plpgsql'),
        ('public.get_my_commercial_future_interest(uuid,text)', '450ee798a74a5738dd957e4ccbef3efe', '46d0abf90aabfb23a004849bc7b180b6', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.get_my_commercial_segment_requests(uuid)', '678020bc629527b5b31e0f41fd681dba', '0838e967389b68a1f84a43a5a32a955c', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.get_my_company_commercial_summary(uuid)', '63e0ac7fb9b159448b1f10ba3776b454', '56c2d7eaf9350a2d0f18f20526252809', 'true', 's', 'search_path=pg_catalog', 'plpgsql'),
        ('public.is_fidelized_context(text,text,text,text)', '3bc8cb1a2b8d1212ea027c0906398e58', '999353eb7f1c521751b279a37210f318', 'true', 's', 'search_path=pg_catalog', 'sql'),
        ('public.is_fidelized_context(text,text,text,text,uuid)', '8d4a2aa61710ffed40c7f0cb875040b6', '4b1bbbfdd63b8932479d6ee061c85a5f', 'true', 's', 'search_path=pg_catalog', 'sql'),
        ('public.join_my_commercial_future_queue(uuid,text,uuid)', 'f6e401d8e3e641293510cda9a92cfda2', '276a34889f62716250a836a48586064e', 'true', 'v', 'search_path=pg_catalog', 'plpgsql'),
        ('public.list_commercial_segments()', '406213757689a8c93553ebb8b79cbdbe', 'e82ecc41a958d257ea2cecabd1af2bfb', 'true', 's', 'search_path=pg_catalog', 'sql'),
        ('public.request_commercial_segment(uuid,text,text,text)', '62594ee9b5691f521d5180e61f038611', '29a6ba31a8cacbff4bfaed26eb9789c1', 'true', 'v', 'search_path=pg_catalog', 'plpgsql')
  ), observado AS (
  SELECT p.oid::pg_catalog.regprocedure::text AS assinatura,
         pg_catalog.md5(p.prosrc) AS md5_src,
         pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.replace(p.prosrc, pg_catalog.chr(13), ''), '--[^\n]*', '', 'g'), '\s+', '', 'g')) AS md5_norm,
         p.prosecdef::text AS secdef, p.provolatile::text AS volat,
         coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') AS config, l.lanname AS lang
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_language l ON l.oid = p.prolang
   WHERE n.nspname = 'public' AND p.proname IN ('admin_archive_commercial_segment','admin_create_commercial_segment','admin_decide_commercial_segment_request','admin_list_commercial_segments','admin_register_manual_commercial_order','build_app_provisioning_payload','calculate_niche_contract_pricing','cci_resposta_intencao','ceo_segmento_da_intencao','cfr_derivar_identidade','commercial_build_instrument_snapshot','commercial_fidelity_identity','commercial_normalize_segment_label','commercial_resolve_position_segment','commercial_segment_requests_protect','commercial_segment_snapshot_imutavel','commercial_segments_protect','create_commercial_checkout_intent','finalize_commercial_order_from_intent','get_current_commercial_formation','get_my_commercial_future_interest','get_my_commercial_segment_requests','get_my_company_commercial_summary','is_fidelized_context','join_my_commercial_future_queue','list_commercial_segments','request_commercial_segment')
  ), cmp AS (
    SELECT coalesce(e.assinatura, o.assinatura) AS assinatura,
           CASE
             WHEN o.assinatura IS NULL THEN 'ausente'
             WHEN e.assinatura IS NULL THEN 'inesperada'
             WHEN (o.secdef, o.volat, o.config, o.lang) IS DISTINCT FROM (e.secdef, e.volat, e.config, e.lang)
               THEN 'atributos(secdef=' || o.secdef || ',volat=' || o.volat || ',config=' || o.config || ',lang=' || o.lang || ')'
             WHEN o.md5_src = e.md5_src THEN 'ok'
             WHEN o.md5_norm = e.md5_norm AND pg_catalog.strpos(src.prosrc, pg_catalog.chr(13)) > 0
               THEN 'textual:CR(fim de linha CRLF no transporte)'
             WHEN o.md5_norm = e.md5_norm THEN 'textual:comentarios_ou_espacos'
             WHEN src.prosrc ~ ('[' || pg_catalog.chr(194) || pg_catalog.chr(195) || '][' || pg_catalog.chr(128) || '-' || pg_catalog.chr(191) || ']')
               THEN 'codificacao:acentuacao convertida duas vezes (client_encoding nao UTF8)'
             ELSE 'conteudo:corpo diferente do arquivo revisado'
           END AS classe
      FROM esperado e
      FULL JOIN observado o ON o.assinatura = e.assinatura
      LEFT JOIN LATERAL (SELECT p.prosrc FROM pg_catalog.pg_proc p
                          WHERE p.oid = pg_catalog.to_regprocedure(o.assinatura)) src ON true
  ), obj AS (
    SELECT x.tipo, x.nome,
           CASE x.tipo
             WHEN 'tabela' THEN pg_catalog.to_regclass('public.' || x.nome) IS NOT NULL
             WHEN 'indice' THEN pg_catalog.to_regclass('public.' || x.nome) IS NOT NULL
             WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgname = x.nome AND NOT t.tgisinternal)
             ELSE EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conname = x.nome)
           END AS presente
      FROM (VALUES
        ('tabela', 'commercial_segment_requests'),
        ('tabela', 'commercial_segments'),
        ('indice', 'ceo_segmento_por_exclusividade_idx'),
        ('indice', 'cfr_identidade_unica'),
        ('indice', 'cpo_segmento_por_exclusividade_idx'),
        ('indice', 'cs_classificacao_aprovada_uidx'),
        ('indice', 'csr_pendente_por_empresa_uidx'),
        ('indice', 'csr_status_idx'),
        ('gatilho', 'cci_segmento_imutavel'),
        ('gatilho', 'ceo_segmento_da_intencao'),
        ('gatilho', 'ceo_segmento_imutavel'),
        ('gatilho', 'cfr_derivar_identidade'),
        ('gatilho', 'cpo_segmento_imutavel'),
        ('gatilho', 'cs_protect'),
        ('gatilho', 'csr_protect'),
        ('gatilho', 'csw_segmento_imutavel'),
        ('restricao', 'cci_outros_exige_segmento'),
        ('restricao', 'cci_segmento_posicao_elegivel'),
        ('restricao', 'cci_segmento_snapshot_coerente'),
        ('restricao', 'cci_supermercado_sem_segmento'),
        ('restricao', 'ceo_outros_exige_segmento'),
        ('restricao', 'ceo_segmento_posicao_elegivel'),
        ('restricao', 'ceo_segmento_snapshot_coerente'),
        ('restricao', 'ceo_supermercado_sem_segmento'),
        ('restricao', 'cfr_identidade_formato'),
        ('restricao', 'commercial_niches_canonical'),
        ('restricao', 'commercial_niches_code_allowed'),
        ('restricao', 'commercial_niches_legado_inativo'),
        ('restricao', 'commercial_niches_sort_order_range'),
        ('restricao', 'cpo_outros_exige_segmento'),
        ('restricao', 'cpo_segmento_posicao_elegivel'),
        ('restricao', 'cpo_segmento_snapshot_coerente'),
        ('restricao', 'cpo_supermercado_sem_segmento'),
        ('restricao', 'csw_outros_exige_segmento'),
        ('restricao', 'csw_segmento_posicao_elegivel'),
        ('restricao', 'csw_segmento_snapshot_coerente'),
        ('restricao', 'csw_supermercado_sem_segmento')) AS x(tipo, nome)
  )
  SELECT count(*) FILTER (WHERE classe <> 'ok'),
         string_agg(assinatura || ' => ' || classe, '; ' ORDER BY assinatura) FILTER (WHERE classe <> 'ok'),
         (SELECT string_agg(tipo || ':' || nome, ', ' ORDER BY tipo, nome) FROM obj WHERE NOT presente)
    INTO v_ndif, v_dif, v_obj
    FROM cmp;
  IF v_ndif > 0 THEN
    RAISE EXCEPTION 'registro_abortado: % funcao(oes) diferem do arquivo revisado: %', v_ndif, v_dif;
  END IF;
  IF v_obj IS NOT NULL THEN
    RAISE EXCEPTION 'registro_abortado: objetos da migration ausentes: %', v_obj;
  END IF;

  IF (SELECT count(*) FROM public.commercial_niches WHERE is_active) <> 6
  OR (SELECT sum(contracted_quantity) FROM public.commercial_niches WHERE is_active) <> 84
  OR (SELECT convert_to(display_name, 'UTF8') FROM public.commercial_niches WHERE code = 'footwear')
       IS DISTINCT FROM '\x43616cc3a761646f73'::bytea
  OR EXISTS (SELECT 1 FROM public.commercial_niches
              WHERE code IN ('womens_footwear', 'mens_footwear') AND is_active) THEN
    RAISE EXCEPTION 'registro_abortado: catalogo de posicoes diferente do esperado';
  END IF;

  INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
  VALUES ('20261103120000', 'commercial_positions_segments',
          ARRAY['-- aplicado pelo conteudo exato do arquivo do repositorio; sha256 d1b0fdbe6a55201cb96fd1799777a42bf8c6e6bd1364d41c8387641b7b7302f4; manifesto 28 funcoes md5 f6dee6c2fadd306a53dcfdde05086f1e verificado'],
          'etapa-b-publicacao-coordenada');

  IF (SELECT count(*) FROM supabase_migrations.schema_migrations) <> 63 THEN
    RAISE EXCEPTION 'registro_abortado: historico nao ficou com 63 versoes';
  END IF;
END $reg$;
COMMIT;
