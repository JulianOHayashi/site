-- ===========================================================================
-- VERIFICAÇÃO SOMENTE LEITURA da R3 (20261113150000). Não escreve nada.
-- Cada linha deve sair `true`; a última lista as pendências de ativação.
-- ===========================================================================
SELECT 'SF-v1.4 vigente sem politica R3; SF-v1.5 preparada com QA so em produtos' AS item,
       ((SELECT status = 'active' AND qa_policy IS NULL FROM public.commercial_pricing_rules WHERE version = 3)
        AND (SELECT status = 'prepared' AND qa_policy = 'in_kind_direct_benefits_only'
               FROM public.commercial_pricing_rules WHERE version = 4))::text AS valor
UNION ALL
SELECT 'beneficio direto v4: 4 termos, QA so em produtos, dinheiro = parcela principal',
       ((SELECT count(*) = 4 AND bool_and(qa_cash_cents = 0 AND total_monetary_funding_required_cents = smallflags_main_fee_cents)
           FROM public.commercial_settlement_terms
          WHERE pricing_rule_version = 4 AND benefit_settlement_mode = 'direct_benefits'))::text
UNION ALL
SELECT 'preco do DINHEIRO v4 (Cenario A ou B) gravado?',
       (EXISTS (SELECT 1 FROM public.commercial_settlement_terms WHERE benefit_settlement_mode = 'cash'))::text
UNION ALL
SELECT 'autoatendimento travado no banco (versao minima)',
       (SELECT min_pricing_rule_version::text FROM public.commercial_checkout_gate)
UNION ALL
SELECT 'nenhuma ativacao registrada',
       (NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log))::text
UNION ALL
SELECT 'travas R3 ligadas (gatilhos)',
       ((SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled <> 'D' AND tgname IN
         ('cst_protect','cci_liquidar_modalidade_v15','cci_portao_autoatendimento',
          'ceo_liquidar_modalidade_v15','ceo_liquidacao_v15_imutavel','ceo_pagamento_confere_snapshot',
          'ceo_revalidar_reutilizacao_bandeiras','cp_valor_confere_pedido','cpal_protect','ccg_protect')) = 10)::text
UNION ALL
SELECT 'pedidos confirmados com valor diferente do snapshot (historico; deve ser 0)',
       (SELECT count(*)::text FROM public.commercial_exclusivity_orders
         WHERE payment_status = 'confirmed' AND payment_amount_cents IS DISTINCT FROM total_monetary_funding_required_cents)
UNION ALL
SELECT 'pendencias para ativar a versao 4',
       (public.commercial_pricing_activation_preflight(4)->'failures')::text;
