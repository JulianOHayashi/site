-- ============================================================================
-- PRÉ-CHECAGEM SOMENTE LEITURA da publicação da Etapa B (migration
-- 20261103120000). Só SELECT. Rodar imediatamente antes da reconciliação e
-- de novo antes da migration. Toda linha tem de devolver ok = true; qualquer
-- false interrompe a publicação.
-- ============================================================================
WITH h AS (
  SELECT count(*) n, md5(string_agg(version||':'||name, ',' ORDER BY version||':'||name)) hash
    FROM supabase_migrations.schema_migrations
), checks(item, valor, ok) AS (
  SELECT 'historico (62 linhas; hash pre ou pos reconciliacao)', h.n||' / '||h.hash,
         h.n = 62 AND h.hash IN ('f13ee66fee74cc39a82cb2a69c99e205','c9924f1092689753d1bdfb59670aa8c4') FROM h
  UNION ALL
  SELECT 'catalogo antigo de 6 nichos ativos, 84 unidades',
         (SELECT string_agg(code||':'||contracted_quantity||':'||is_active, ',' ORDER BY sort_order) FROM public.commercial_niches),
         (SELECT count(*) = 6 AND sum(contracted_quantity) = 84 AND bool_and(is_active)
                 AND bool_or(code = 'womens_footwear') AND bool_or(code = 'mens_footwear')
            FROM public.commercial_niches)
  UNION ALL
  SELECT 'calcados F/M: so oportunidades livres em exclusividade em formacao',
         (SELECT string_agg(e.sequence_number||':'||e.status||':'||o.niche_code||':'||o.status, ',' ORDER BY o.niche_code)
            FROM public.commercial_opportunities o JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
           WHERE o.niche_code IN ('womens_footwear','mens_footwear')),
         NOT EXISTS (SELECT 1 FROM public.commercial_opportunities o JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
                      WHERE o.niche_code IN ('womens_footwear','mens_footwear')
                        AND (e.status <> 'forming' OR o.status <> 'available'))
  UNION ALL
  SELECT 'nenhuma referencia comercial a calcados F/M',
         ((SELECT count(*) FROM public.commercial_checkout_intents WHERE niche_code LIKE '%_footwear')
        + (SELECT count(*) FROM public.commercial_exclusivity_orders WHERE niche_code LIKE '%_footwear')
        + (SELECT count(*) FROM public.commercial_preorders WHERE niche_code LIKE '%_footwear')
        + (SELECT count(*) FROM public.commercial_sales_waitlist WHERE niche_code LIKE '%_footwear'))::text,
         ((SELECT count(*) FROM public.commercial_checkout_intents WHERE niche_code LIKE '%_footwear')
        + (SELECT count(*) FROM public.commercial_exclusivity_orders WHERE niche_code LIKE '%_footwear')
        + (SELECT count(*) FROM public.commercial_preorders WHERE niche_code LIKE '%_footwear')
        + (SELECT count(*) FROM public.commercial_sales_waitlist WHERE niche_code LIKE '%_footwear')) = 0
  UNION ALL
  SELECT 'volumes (intents/pedidos/pre-compras/fila/fidelidade/provisionamento)',
         (SELECT count(*) FROM public.commercial_checkout_intents)||'/'||(SELECT count(*) FROM public.commercial_exclusivity_orders)
         ||'/'||(SELECT count(*) FROM public.commercial_preorders)||'/'||(SELECT count(*) FROM public.commercial_sales_waitlist)
         ||'/'||(SELECT count(*) FROM public.commercial_fidelity_records)||'/'||(SELECT count(*) FROM public.app_provisioning_messages),
         true  -- informativo: qualquer valor > 0 exige reler o impacto antes de seguir
  UNION ALL
  SELECT 'objetos novos ainda inexistentes',
         coalesce(pg_catalog.to_regclass('public.commercial_segments')::text, '-')||' '
         ||coalesce(pg_catalog.to_regprocedure('public.create_commercial_checkout_intent(uuid,text,text,uuid)')::text, '-'),
         pg_catalog.to_regclass('public.commercial_segments') IS NULL
         AND pg_catalog.to_regclass('public.commercial_segment_requests') IS NULL
         AND pg_catalog.to_regprocedure('public.create_commercial_checkout_intent(uuid,text,text,uuid)') IS NULL
  UNION ALL
  SELECT 'restricao cfr_unico presente', '',
         EXISTS (SELECT 1 FROM pg_catalog.pg_constraint WHERE conname = 'cfr_unico')
  UNION ALL
  SELECT 'site_admin existe (decide segmentos)', (SELECT count(*) FROM public.site_admins)::text,
         (SELECT count(*) FROM public.site_admins) >= 1
  UNION ALL
  SELECT 'ACL reserva/fila/manual para authenticated (informativo; a migration preserva)',
         has_function_privilege('authenticated','public.create_commercial_checkout_intent(uuid,text,text)','EXECUTE')||'/'
         ||has_function_privilege('authenticated','public.join_my_commercial_future_queue(uuid,text)','EXECUTE')||'/'
         ||has_function_privilege('authenticated','public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer)','EXECUTE'),
         true
)
SELECT item, valor, ok FROM checks;
