-- ===========================================================================
-- VERIFICAÇÃO SOMENTE LEITURA — SF-v1.5 (migration 20261112120000)
--
-- Rodar em Production DEPOIS de aplicar a migration e ANTES de qualquer
-- ativação. Não escreve nada: só SELECT. Cada linha deve sair com ok = true.
-- ===========================================================================
SELECT 'regra 3 (SF-v1.4) vigente' AS verificacao,
       (SELECT status FROM public.commercial_pricing_rules WHERE version = 3) = 'active' AS ok
UNION ALL
SELECT 'regra 4 (SF-v1.5) apenas preparada',
       (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) = 'prepared'
UNION ALL
SELECT 'agenda SF-v1.4 intacta',
       (SELECT string_agg(format('%s/%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
               economic_value_cents, mei_consideration_cents, smallflags_qa_cents,
               smallflags_main_fee_cents, smallflags_total_remuneration_cents), ';'
               ORDER BY commercial_category, fidelized)
          FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 3)
       = 'common/false/1999900/1192716/6084/801100/807184;common/true/1618800/1192716/6084/420000/426084;'
         'supermarket/false/2999900/2385432/12168/602300/614468;supermarket/true/2817600/2385432/12168/420000/432168'
UNION ALL
SELECT 'agenda SF-v1.5 com os quatro valores do operador',
       (SELECT string_agg(format('%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
               economic_value_cents, smallflags_main_fee_cents, new_flag_units,
               flag_production_charge_cents), ';' ORDER BY commercial_category, fidelized)
          FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 4)
       = 'common/false/2293900/1095100/84/294000;common/true/1618800/420000/0/0;'
         'supermarket/false/3293900/896300/84/294000;supermarket/true/2817600/420000/0/0'
UNION ALL
SELECT 'preço público continua SF-v1.4',
       (public.get_public_niche_pricing()->'niches'->0->'founding'->>'contract_economics_version') = 'SF-v1.4'
UNION ALL
SELECT 'SF-v1.5 não consultável antes da ativação',
       (public.calculate_niche_contract_pricing('supermarket', false, 4)->>'reason') = 'pricing_rule_not_published'
UNION ALL
SELECT 'service_role só lê a agenda',
       has_table_privilege('service_role', 'public.commercial_pricing_schedule', 'SELECT')
       AND NOT has_table_privilege('service_role', 'public.commercial_pricing_schedule', 'UPDATE')
       AND NOT has_table_privilege('service_role', 'public.commercial_pricing_schedule', 'INSERT')
       AND NOT has_table_privilege('service_role', 'public.commercial_pricing_schedule', 'DELETE')
UNION ALL
SELECT 'inventário de bandeiras vazio e fechado ao público',
       NOT EXISTS (SELECT 1 FROM public.commercial_flag_sets)
       AND NOT EXISTS (SELECT 1 FROM public.commercial_flag_set_inspections)
       AND NOT has_table_privilege('authenticated', 'public.commercial_flag_sets', 'SELECT')
       AND NOT has_table_privilege('anon', 'public.commercial_flag_sets', 'SELECT')
UNION ALL
SELECT 'proteções instaladas (regras, agenda, inventário, pedidos, intenções)',
       (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
         ('cpr_protect','cpr_protect_truncate','cps_protect','cps_protect_truncate',
          'cfs_protect','cfs_protect_truncate','cfi_protect','cfi_protect_truncate',
          'cci_validar_producao_bandeiras','ceo_validar_producao_bandeiras',
          'cci_bandeiras_imutaveis','ceo_bandeiras_imutaveis')) = 12
UNION ALL
SELECT 'nenhum pedido ou intenção com fatos de produção',
       NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders WHERE flag_production_new_units IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM public.commercial_checkout_intents WHERE flag_production_new_units IS NOT NULL);
