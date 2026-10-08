-- ============================================================================
-- P0-3 (limpeza semântica) — A PARCELA QA NÃO É DINHEIRO DO USUÁRIO/MEI
--
-- A economia congelada NÃO muda. Nenhum centavo é reprecificado. O que muda é
-- o que o servidor AFIRMA sobre cada centavo.
--
-- O PROBLEMA
-- Sob a SF-v1.4:
--
--     contractual_pool_cents = mei_consideration_cents + smallflags_qa_cents
--
-- e a parcela QA pertence à SmallFlags, não ao MEI nem ao usuário. Mas o
-- servidor expunha o pool INTEIRO sob o nome `user_pool_cents` e derivava dele
-- o valor por usuário. Na formação fundadora completa:
--
--     contraprestação dos MEIs ....... 8.349.012  (o que é de fato do MEI)
--     parcela QA da SmallFlags .......    42.588  (NÃO é do MEI)
--     pool contratual (compat.) ...... 8.391.600
--
-- Efeito medido: `per_complete_user_base_cents` valia 8.391.600 / 84 = 99.900,
-- quando o que é efetivamente do MEI é 8.349.012 / 84 = 99.393 — exato, sem
-- resto. A vitrine pública superdeclarava R$ 5,07 por usuário.
--
-- O QUE ESTA MIGRATION FAZ
-- Acrescenta campos explícitos da v1.4 nas quatro superfícies onde o
-- significado importa — vitrine pública, resumo do parceiro, resposta da
-- intenção ao navegador e payload de provisionamento para o App — e publica o
-- valor por MEI calculado sobre a contraprestação dos MEIs, não sobre o pool.
--
-- COMPATIBILIDADE
-- `user_pool_cents`, `contractual_pool_cents`, `per_complete_user_base_cents` e
-- `pool_remainder_cents` continuam presentes, com os mesmos valores. Nada é
-- removido nem renomeado: consumidores existentes seguem funcionando. O que eles
-- deixam de poder fazer é apresentar o pool inteiro como dinheiro do usuário,
-- porque agora existe o campo que diz a verdade ao lado.
--
-- SEMÂNTICA HISTÓRICA PRESERVADA
-- Sob V1 e V2 não existia parcela QA alguma: a decomposição não é um fato
-- daquela época. Por isso os campos novos saem NULL para pricing_rule_version
-- < 3, em vez de fingir mei = pool e qa = 0. Afirmar decomposição onde ela não
-- existia seria inventar história.
--
-- Sem push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_public_formation_economics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_version    integer;
  v_economic   bigint := 0;
  v_pool       bigint := 0;
  v_n          record;
  v_p          jsonb;
  v_alvo       integer := 84;
  -- Decomposicao v1.4: so existe a partir da versao tecnica 3.
  v_mei        bigint := 0;
  v_qa         bigint := 0;
  v_tem_v14    boolean := true;
BEGIN
  SELECT version INTO v_version
    FROM public.commercial_pricing_rules WHERE status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  FOR v_n IN
    SELECT code FROM public.commercial_niches WHERE is_active ORDER BY sort_order
  LOOP
    v_p := public.calculate_niche_contract_pricing(v_n.code, false);
    IF (v_p->>'ok')::boolean IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_unavailable');
    END IF;
    v_economic := v_economic + (v_p->>'economic_value_cents')::bigint;
    v_pool     := v_pool     + (v_p->>'contractual_pool_cents')::bigint;
    -- A autoridade ativa devolve a decomposicao; as historicas nao.
    IF v_p ? 'mei_consideration_cents' AND v_p ? 'smallflags_qa_cents' THEN
      v_mei := v_mei + (v_p->>'mei_consideration_cents')::bigint;
      v_qa  := v_qa  + (v_p->>'smallflags_qa_cents')::bigint;
    ELSE
      v_tem_v14 := false;
    END IF;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'pricing_rule_version', v_version,
    'currency', 'BRL',
    'participant_target', v_alvo,
    'economic_value_cents', v_economic,
    'user_pool_cents', v_pool,
    'bdflow_ops_investment_cents', v_economic - v_pool,
    -- Divisão inteira: só é exata porque a política de resíduos distribui os
    -- centavos restantes. O valor aqui é o alvo por usuário completo.
    -- Divisão inteira. O alvo por usuário completo só fecha exatamente
    -- porque a política de resíduos distribui os centavos restantes; o
    -- resto é publicado para que ninguém precise deduzi-lo.
    'per_complete_user_base_cents', v_pool / v_alvo,
    'pool_remainder_cents', v_pool % v_alvo,
    -- ---- Campos EXPLICITOS da v1.4 -------------------------------------
    -- contractual_pool_cents / user_pool_cents acima sao o pool INTEIRO, que
    -- inclui a parcela QA da SmallFlags. O que e efetivamente dos MEIs e
    -- mei_consideration_cents. NULL sob V1/V2, onde a decomposicao nao existia.
    'contract_economics_version',
      CASE WHEN v_tem_v14 THEN v_p->>'contract_economics_version' END,
    'mei_consideration_cents',  CASE WHEN v_tem_v14 THEN v_mei END,
    'smallflags_qa_cents',      CASE WHEN v_tem_v14 THEN v_qa  END,
    -- Valor por MEI calculado sobre a contraprestacao dos MEIs, NAO sobre o
    -- pool: 8.349.012 / 84 = 99.393, exato.
    'per_complete_mei_base_cents',
      CASE WHEN v_tem_v14 THEN v_mei / v_alvo END,
    'mei_remainder_cents',
      CASE WHEN v_tem_v14 THEN v_mei % v_alvo END);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_company_commercial_summary(p_company_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_owner boolean := public.m2_is_company_owner(p_company_id);
BEGIN
  IF NOT (public.m2_is_company_member(p_company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'company', (SELECT pg_catalog.jsonb_build_object(
                  'company_id', c.id, 'trade_name', coalesce(c.trade_name, c.legal_name),
                  'status', c.status)
                  FROM public.site_partner_companies c WHERE c.id = p_company_id),
    'units', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'unit_id', u.id, 'name', u.name, 'city', u.city, 'status', u.status)
                  ORDER BY u.name)
                  FROM public.site_partner_units u
                 WHERE u.company_id = p_company_id AND u.status <> 'archived'), '[]'::jsonb),
    'managers', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'member_id', m.id, 'full_name', m.full_name, 'status', m.status)
                  ORDER BY m.full_name)
                  FROM public.site_company_members m
                 WHERE m.company_id = p_company_id AND m.role = 'partner_manager'
                   AND m.status IN ('active','suspended')), '[]'::jsonb),
    -- Bloco financeiro SOMENTE para owner/admin.
    'commercial', CASE WHEN v_owner OR public.is_site_admin() THEN
        coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'order_id', o.id, 'niche_code', o.niche_code,
            'nominal_quantity', o.nominal_quantity, 'currency', o.currency,
            'economic_value_cents', o.economic_value_cents,
            -- Pool INTEIRO, mantido por compatibilidade. Inclui a parcela QA
            -- da SmallFlags e por isso NAO e dinheiro do MEI/usuario.
            'contractual_pool_cents', o.contractual_pool_cents,
            'contract_economics_version', o.contract_economics_version,
            'mei_consideration_cents', o.mei_consideration_cents,
            'smallflags_qa_cents', o.smallflags_qa_cents,
            'smallflags_main_fee_cents', o.smallflags_main_fee_cents,
            'smallflags_total_remuneration_cents', o.smallflags_total_remuneration_cents,
            'bdflow_due_cents', o.bdflow_due_cents,
            'payment_status', o.payment_status,
            'has_customization_image', public.order_has_customization_image(o.id),
            'expected_operation_start', o.expected_operation_start,
            'exclusivity_status', e.status))
            FROM public.commercial_exclusivity_orders o
            JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
           WHERE o.company_id = p_company_id AND o.status <> 'cancelled'), '[]'::jsonb)
      ELSE NULL END,
    'readiness', public.company_launch_readiness(p_company_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.cci_resposta_intencao(p_i commercial_checkout_intents, p_ja boolean)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT pg_catalog.jsonb_build_object(
    'ok', true,
    'already', p_ja,
    'intent_id', p_i.id,
    'status', p_i.status,
    'opportunity_id', p_i.opportunity_id,
    'exclusivity_id', p_i.exclusivity_id,
    'region_id', p_i.region_id,
    'reserved_until', p_i.reserved_until,
    'reservation_minutes', 30,
    'pricing_rule_version', p_i.pricing_rule_version,
    'benefit_distribution_policy_version', p_i.benefit_distribution_policy_version,
    'niche_code', p_i.niche_code,
    'nominal_quantity', p_i.nominal_quantity,
    'fidelized', p_i.fidelized,
    'payment_method', p_i.payment_method,
    'benefit_settlement_mode', p_i.benefit_settlement_mode,
    'currency', p_i.currency,
    'economic_value_cents', p_i.economic_value_cents,
    -- Pool INTEIRO, por compatibilidade: inclui a parcela QA da SmallFlags.
    'user_pool_cents', p_i.user_pool_cents,
    'contract_economics_version', p_i.contract_economics_version,
    'mei_consideration_cents', p_i.mei_consideration_cents,
    'smallflags_qa_cents', p_i.smallflags_qa_cents,
    'smallflags_main_fee_cents', p_i.smallflags_main_fee_cents,
    'smallflags_total_remuneration_cents', p_i.smallflags_total_remuneration_cents,
    'bdflow_ops_investment_cents', p_i.bdflow_ops_investment_cents,
    'cash_user_pool_funding_cents', p_i.cash_user_pool_funding_cents,
    'total_monetary_funding_required_cents', p_i.total_monetary_funding_required_cents,
    'participant_target', p_i.participant_target);
$function$;

CREATE OR REPLACE FUNCTION public.build_app_provisioning_payload(p_exclusivity_id uuid, p_environment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_excl   public.commercial_exclusivities%ROWTYPE;
  v_region public.commercial_regions%ROWTYPE;
  v_parts  jsonb;
  v_incompativeis integer;
BEGIN
  SELECT * INTO v_excl FROM public.commercial_exclusivities WHERE id = p_exclusivity_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  -- Porta de compatibilidade: todo pedido assinado desta formação precisa
  -- carregar semântica V2 explícita antes de virar asserção para o App.
  SELECT count(*) INTO v_incompativeis
    FROM public.commercial_exclusivity_orders o
   WHERE o.exclusivity_id = p_exclusivity_id
     AND o.status = 'signed'
     AND (o.benefit_settlement_mode IS NULL
          OR o.benefit_distribution_policy_version IS DISTINCT FROM 2);
  IF v_incompativeis > 0 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'incompatible_distribution_policy',
      'incompatible_orders', v_incompativeis);
  END IF;

  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'partner_network_bridge_id', c.partner_network_bridge_id,
      'niche_code', o.niche_code,
      'site_order_reference', o.id,
      'nominal_quantity', o.nominal_quantity,
      'currency', o.currency,
      -- Pool INTEIRO, por compatibilidade. O App NAO deve tratar este valor
      -- como direito dos MEIs: a parcela QA esta dentro dele e e da SmallFlags.
      -- O direito dos MEIs e mei_consideration_cents.
      'contractual_pool_cents', o.contractual_pool_cents,
      'contract_economics_version', o.contract_economics_version,
      'mei_consideration_cents', o.mei_consideration_cents,
      'smallflags_qa_cents', o.smallflags_qa_cents,
      -- V2: escolha contratual por parceiro, lida do snapshot imutável.
      'benefit_settlement_mode', o.benefit_settlement_mode,
      'benefit_distribution_policy_version', o.benefit_distribution_policy_version,
      'expected_operation_start', o.expected_operation_start,
      'expected_operation_end',
        o.expected_operation_start + (o.exclusivity_period_days || ' days')::interval,
      'partner_status', c.status,
      'branches', coalesce((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'partner_branch_bridge_id', u.partner_branch_bridge_id,
                 'status', u.status) ORDER BY u.partner_branch_bridge_id)
          FROM public.site_partner_units u
         WHERE u.company_id = c.id AND u.status = 'active'), '[]'::jsonb),
      'validators', coalesce((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'validator_bridge_id', m.validator_bridge_id,
                 'role', m.role) ORDER BY m.validator_bridge_id)
          FROM public.site_company_members m
         WHERE m.company_id = c.id AND m.status = 'active'), '[]'::jsonb))
      ORDER BY o.niche_code), '[]'::jsonb)
    INTO v_parts
    FROM public.commercial_exclusivity_orders o
    JOIN public.site_partner_companies c ON c.id = o.company_id
   WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed';

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'schema_version', 'bdflow.commercial_provisioning.v2',
    'environment', p_environment,
    'commercial_exclusivity_id', v_excl.id,
    'region', pg_catalog.jsonb_build_object('uf', v_region.uf, 'name', v_region.name),
    'sequence_number', v_excl.sequence_number,
    'participant_target', 84,
    'distribution_policy_version', 2,
    -- Cronograma NÃO muda nesta tarefa: continua a matriz 7x7 versão 1.
    'schedule_policy_version', 1,
    'partners', v_parts);
END;
$function$;
