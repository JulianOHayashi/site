-- ============================================================================
-- ROLLBACK da migration 20261103120000 (posições comerciais e segmentos)
--
-- Só é seguro ANTES de qualquer venda nova sob o modelo novo. Ele aborta se
-- existir qualquer intenção, pedido, pré-compra, fila ou fidelidade que use
-- Calçados unificado, Outros ou segmento — nesse caso o retorno exige
-- tratamento contratual, não reversão de schema.
--
-- Restaura: catálogo de seis nichos com calçados F/M ativos, remapeamento
-- inverso das oportunidades LIVRES das exclusividades em formação, as
-- assinaturas e corpos anteriores das RPCs, e a unicidade antiga de
-- fidelidade. Remove tabelas, colunas, gatilhos e RPCs de segmento.
-- ============================================================================
BEGIN;

DO $guarda$
DECLARE v bigint;
BEGIN
  SELECT (SELECT count(*) FROM public.commercial_checkout_intents
           WHERE niche_code IN ('footwear','others') OR segment_id IS NOT NULL)
       + (SELECT count(*) FROM public.commercial_exclusivity_orders
           WHERE niche_code IN ('footwear','others') OR segment_id IS NOT NULL)
       + (SELECT count(*) FROM public.commercial_preorders
           WHERE niche_code IN ('footwear','others') OR segment_id IS NOT NULL)
       + (SELECT count(*) FROM public.commercial_sales_waitlist
           WHERE niche_code IN ('footwear','others') OR segment_id IS NOT NULL)
       + (SELECT count(*) FROM public.commercial_fidelity_records
           WHERE niche_code IN ('footwear','others') OR fidelity_identity <> niche_code)
       + (SELECT count(*) FROM public.commercial_territorial_waitlist
           WHERE niche_code IN ('footwear','others'))
       + (SELECT count(*) FROM public.commercial_contract_activity_catalog
           WHERE niche_code IN ('footwear','others'))
    INTO v;
  IF v > 0 THEN
    RAISE EXCEPTION 'rollback_bloqueado: % registro(s) ja usam o modelo novo', v;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.commercial_opportunities o
      JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
     WHERE o.niche_code IN ('footwear','others')
       AND (e.status <> 'forming' OR o.status <> 'available')) THEN
    RAISE EXCEPTION 'rollback_bloqueado: oportunidade nova fora de formacao ou ocupada';
  END IF;
END $guarda$;

-- Permissões das três RPCs que voltam à assinatura antiga: copiadas do banco.
CREATE TEMP TABLE _acl_preservada ON COMMIT DROP AS
SELECT v.nome, r.rolname,
       pg_catalog.has_function_privilege(r.oid, v.atual::regprocedure, 'EXECUTE') AS pode
  FROM (VALUES
    ('create_commercial_checkout_intent', 'public.create_commercial_checkout_intent(uuid,text,text,uuid)'),
    ('admin_register_manual_commercial_order', 'public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer,uuid)'),
    ('join_my_commercial_future_queue', 'public.join_my_commercial_future_queue(uuid,text,uuid)')) AS v(nome, atual)
 CROSS JOIN pg_catalog.pg_roles r
 WHERE r.rolname IN ('anon','authenticated','service_role');
CREATE OR REPLACE FUNCTION pg_temp.reaplicar_acl(p_nome text, p_antiga text)
RETURNS void LANGUAGE plpgsql AS $acl$
DECLARE r record;
BEGIN
  EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', p_antiga);
  FOR r IN SELECT rolname FROM _acl_preservada WHERE nome = p_nome AND pode LOOP
    EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO %I', p_antiga, r.rolname);
  END LOOP;
END $acl$;

-- RPCs e auxiliares novos
DROP FUNCTION public.admin_archive_commercial_segment(uuid);
DROP FUNCTION public.admin_decide_commercial_segment_request(uuid, text, uuid, text, text, text, text, text, text);
DROP FUNCTION public.admin_create_commercial_segment(text, text, text, text, text, text);
DROP FUNCTION public.admin_list_commercial_segments();
DROP FUNCTION public.get_my_commercial_segment_requests(uuid);
DROP FUNCTION public.request_commercial_segment(uuid, text, text, text);
DROP FUNCTION public.list_commercial_segments();

-- Assinaturas novas -> antigas
DROP FUNCTION public.create_commercial_checkout_intent(uuid, text, text, uuid);
DROP FUNCTION public.admin_register_manual_commercial_order(uuid, uuid, text, timestamp with time zone, text, date, text, text, text, text, integer, uuid);
DROP FUNCTION public.join_my_commercial_future_queue(uuid, text, uuid);
CREATE OR REPLACE FUNCTION public.create_commercial_checkout_intent(p_company_id uuid, p_niche_code text, p_benefit_settlement_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg jsonb;
  v_uid      uuid := auth.uid();
  v_company  public.site_partner_companies%ROWTYPE;
  v_key      text;
  v_uf       text;
  v_region   uuid;
  v_excl     uuid;
  v_opp      public.commercial_opportunities%ROWTYPE;
  v_viva     public.commercial_checkout_intents%ROWTYPE;
  v_fidel    boolean;
  v_p        jsonb;
  v_pool     bigint;
  v_bdflow   bigint;
  v_cash     bigint;
  v_ate      timestamptz;
  v_id       uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF p_benefit_settlement_mode IS NULL
     OR p_benefit_settlement_mode NOT IN ('direct_benefits','cash') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_settlement_mode');
  END IF;

  SELECT * INTO v_company FROM public.site_partner_companies WHERE id = p_company_id;
  IF NOT FOUND OR v_company.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_not_found');
  END IF;

  -- Helper canônico: partner_owner + ativo + auth.uid(). Gerente de unidade
  -- não decide contratação comercial — é decisão da empresa, não operacional.
  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;


  -- P0-1 PORTAO 1 de 4: elegibilidade do Acordo Mestre pela definicao UNICA.
  -- Falha CEDO: sem Mestre elegivel a empresa nao segura oportunidade escassa
  -- por 30 minutos nem gera aceite que jamais podera ser finalizado.
  v_eleg := public.m2_master_agreement_eligibility(p_company_id);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
  END IF;

  -- ---- resolução autoritativa: empresa -> região -> exclusividade -> oportunidade
  v_key := public.commercial_city_key(v_company.city);
  IF v_key IS NULL OR v_key = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_city_missing');
  END IF;
  IF NOT public.commercial_is_valid_uf(v_company.uf) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_uf_invalid');
  END IF;
  v_uf := pg_catalog.upper(pg_catalog.btrim(v_company.uf));

  SELECT c.region_id INTO v_region
    FROM public.commercial_region_cities c
   WHERE c.uf = v_uf AND c.city_key = v_key AND c.is_active;
  IF v_region IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'region_not_operating');
  END IF;

  SELECT e.id INTO v_excl
    FROM public.commercial_exclusivities e
   WHERE e.region_id = v_region AND e.is_current;
  IF v_excl IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_current_exclusivity');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.commercial_exclusivity_orders o
     WHERE o.exclusivity_id = v_excl
       AND o.company_id = p_company_id
       AND o.status <> 'cancelled'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'company_already_contracted_in_exclusivity');
  END IF;

  -- SERIALIZAÇÃO: daqui até o fim da transação, esta oportunidade é nossa.
  -- Duas empresas chegando ao mesmo tempo entram em fila aqui, e a segunda
  -- enxerga o estado já gravado pela primeira.
  SELECT * INTO v_opp
    FROM public.commercial_opportunities o
   WHERE o.exclusivity_id = v_excl AND o.niche_code = p_niche_code
     FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  -- ---- reserva viva da PRÓPRIA empresa: idempotente, e sem esticar o prazo.
  -- Renovar a cada requisição deixaria qualquer titular segurar a oportunidade
  -- para sempre, apertando F5.
  SELECT * INTO v_viva
    FROM public.commercial_checkout_intents i
   WHERE i.opportunity_id = v_opp.id
     AND i.status = 'draft'
     AND i.reserved_until IS NOT NULL
     AND i.reserved_until > pg_catalog.now();

  IF FOUND THEN
    IF v_viva.company_id <> p_company_id THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'opportunity_reserved',
        'reserved_until', v_viva.reserved_until);
    END IF;
    RETURN public.cci_resposta_intencao(v_viva, true);
  END IF;

  -- ---- reserva vencida NÃO bloqueia para sempre: é recuperada aqui.
  UPDATE public.commercial_checkout_intents
     SET status = 'cancelled'
   WHERE opportunity_id = v_opp.id
     AND status = 'draft'
     AND reserved_until IS NOT NULL
     AND reserved_until <= pg_catalog.now();

  IF v_opp.status = 'reserved'
     AND (v_opp.reserved_until IS NULL OR v_opp.reserved_until <= pg_catalog.now()) THEN
    v_opp.status := 'available';
  END IF;

  IF v_opp.status <> 'available' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', CASE WHEN v_opp.status = 'reserved' THEN 'opportunity_reserved'
                     ELSE 'opportunity_unavailable' END,
      'opportunity_status', v_opp.status);
  END IF;

  -- ---- instantâneo econômico: sempre do servidor, nunca do chamador
  v_fidel := public.is_fidelized_context(
               v_company.cnpj, v_company.uf, v_company.city, p_niche_code);

  v_p := public.calculate_niche_contract_pricing(p_niche_code, v_fidel);
  IF (v_p->>'ok')::boolean IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_unavailable');
  END IF;

  -- Nicho INTEIRO. A quantidade vem da oportunidade e da regra de preço, que
  -- têm de concordar; divergência é defeito de dados, não venda parcial.
  IF (v_p->>'nominal_quantity')::int <> v_opp.contracted_quantity THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quantity_mismatch');
  END IF;

  v_pool   := (v_p->>'contractual_pool_cents')::bigint;
  v_bdflow := (v_p->>'bdflow_due_cents')::bigint;
  v_cash   := CASE WHEN p_benefit_settlement_mode = 'cash' THEN v_pool ELSE 0 END;

  -- TEMPO DO BANCO. Trinta minutos exatos, a partir de now().
  v_ate := pg_catalog.now() + interval '30 minutes';

  UPDATE public.commercial_opportunities
     SET status = 'reserved', reserved_until = v_ate, updated_at = pg_catalog.now()
   WHERE id = v_opp.id;

  INSERT INTO public.commercial_checkout_intents
    (company_id, niche_code, status, pricing_rule_version,
     benefit_distribution_policy_version, fidelized, payment_method,
     benefit_settlement_mode, currency, nominal_quantity,
     economic_value_cents, user_pool_cents, bdflow_ops_investment_cents,
     cash_user_pool_funding_cents, total_monetary_funding_required_cents,
     opportunity_id, exclusivity_id, region_id, reserved_until,
     created_by)
  VALUES
    (p_company_id, p_niche_code, 'draft', (v_p->>'pricing_rule_version')::int,
     2, v_fidel, v_p->>'payment_method',
     p_benefit_settlement_mode, 'BRL', (v_p->>'nominal_quantity')::int,
     (v_p->>'economic_value_cents')::bigint, v_pool, v_bdflow,
     v_cash, v_bdflow + v_cash,
     v_opp.id, v_excl, v_region, v_ate,
     v_uid)
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('commercial_checkout.reserved', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'opportunity_id', v_opp.id,
                                  'niche_code', p_niche_code,
                                  'reserved_until', v_ate));

  SELECT * INTO v_viva FROM public.commercial_checkout_intents WHERE id = v_id;
  RETURN public.cci_resposta_intencao(v_viva, false);
END;
$function$;
SELECT pg_temp.reaplicar_acl('create_commercial_checkout_intent', 'public.create_commercial_checkout_intent(uuid,text,text)');

CREATE OR REPLACE FUNCTION public.admin_register_manual_commercial_order(p_opportunity_id uuid, p_company_id uuid, p_order_version text, p_signed_at timestamp with time zone, p_signatory_name text, p_expected_operation_start date, p_benefit_settlement_mode text, p_document_reference text DEFAULT NULL::text, p_document_hash text DEFAULT NULL::text, p_external_signature_ref text DEFAULT NULL::text, p_exclusivity_period_days integer DEFAULT 28)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg     jsonb;
  v_template jsonb;
  v_opp      public.commercial_opportunities%ROWTYPE;
  v_excl     public.commercial_exclusivities%ROWTYPE;
  v_company  public.site_partner_companies%ROWTYPE;
  v_agree    public.commercial_master_agreements%ROWTYPE;
  v_region   public.commercial_regions%ROWTYPE;
  v_existing public.commercial_exclusivity_orders%ROWTYPE;
  v_city     jsonb;
  v_city_key text;
  v_cnpj     text;
  v_fidel    boolean;
  v_pricing  jsonb;
  v_versao   integer;
  -- Valores COMO GRAVADOS, lidos de volta após o trigger da autoridade.
  v_eco_grav    bigint;
  v_pool_grav   bigint;
  v_bdflow_grav bigint;
  v_cash_grav   bigint;
  v_total_grav  bigint;
  v_econ_versao text;
  v_pool     bigint;
  v_bdflow   bigint;
  v_cash     bigint;
  v_id       uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- A ÚNICA escolha comercial aceita de fora. Preço, fidelidade, versão da
  -- tabela e forma de pagamento continuam derivados aqui.
  IF p_benefit_settlement_mode IS NULL
     OR p_benefit_settlement_mode NOT IN ('direct_benefits','cash') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_settlement_mode');
  END IF;

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signature_date');
  END IF;
  IF p_document_reference IS NULL AND p_document_hash IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_evidence_required');
  END IF;

  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = p_opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  SELECT * INTO v_existing FROM public.commercial_exclusivity_orders
   WHERE opportunity_id = p_opportunity_id AND status <> 'cancelled';
  IF FOUND THEN
    IF v_existing.company_id = p_company_id THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                           'order_id', v_existing.id);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_taken');
  END IF;

  SELECT * INTO v_excl FROM public.commercial_exclusivities
   WHERE id = v_opp.exclusivity_id;
  IF v_excl.status NOT IN ('forming','formed','start_scheduled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exclusivity_closed');
  END IF;

  SELECT * INTO v_company FROM public.site_partner_companies
   WHERE id = p_company_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_invalid');
  END IF;

  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.exclusivity_id = v_opp.exclusivity_id
                AND o.company_id = p_company_id AND o.status <> 'cancelled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_already_in_exclusivity');
  END IF;

  -- O caminho administrativo usa a MESMA definição canônica do fluxo público:
  -- status signed, documento master_agreement vinculado, empresa, versão e hash
  -- exatos, estado legal published/archived. p_lock=true preserva o P0-1.
  v_eleg := public.m2_master_agreement_eligibility(p_company_id, true);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
  END IF;
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE id = (v_eleg->>'master_agreement_id')::uuid;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  v_city := public.m2_resolve_company_fidelity_city(p_company_id, v_region.id);
  IF (v_city->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_city->>'reason');
  END IF;
  v_city_key := v_city->>'city_key';
  v_cnpj     := public.somente_digitos(v_company.cnpj);

  v_fidel := public.is_fidelized_context(
      v_cnpj, v_region.uf, v_company.city, v_opp.niche_code);

  v_pricing := public.calculate_niche_contract_pricing(v_opp.niche_code, v_fidel);
  IF (v_pricing->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_pricing->>'reason');
  END IF;

  v_versao := (v_pricing->>'pricing_rule_version')::int;
  IF v_versao >= 3 THEN
    v_template := public.commercial_signable_instrument_template(v_fidel);
    IF (v_template->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_template;
    END IF;
  END IF;
  v_pool   := (v_pricing->>'contractual_pool_cents')::bigint;
  v_bdflow := (v_pricing->>'bdflow_due_cents')::bigint;
  v_cash   := CASE WHEN p_benefit_settlement_mode = 'cash' THEN v_pool ELSE 0 END;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     benefit_settlement_mode, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     external_signature_ref, status,
     expected_operation_start, exclusivity_period_days, registered_by)
  VALUES
    (v_opp.exclusivity_id, v_opp.id, p_company_id, v_agree.id, v_opp.niche_code,
     v_region.id, v_opp.contracted_quantity,
     v_versao, v_fidel, 'BRL',
     (v_pricing->>'economic_value_cents')::bigint,
     -- NULL sob a V2: não existe ponto-base honesto, e inventar um seria
     -- gravar autoridade falsa só para satisfazer um formato antigo.
     CASE WHEN v_versao >= 2 THEN NULL ELSE (v_pricing->>'pool_bps')::int END,
     v_pool, v_bdflow,
     p_benefit_settlement_mode, v_cash, v_bdflow + v_cash,
     CASE WHEN v_versao >= 2 THEN 2 ELSE NULL END,
     pg_catalog.btrim(p_order_version),
     nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_document_hash,'')), ''),
     p_signed_at, pg_catalog.btrim(p_signatory_name),
     nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
     'signed',
     p_expected_operation_start, p_exclusivity_period_days, auth.uid())
  -- Lê de volta o que a AUTORIDADE gravou, não o que esta função supôs antes
  -- do trigger. Sob V1/V2 estes valores são idênticos aos pré-calculados.
  RETURNING id,
            economic_value_cents,
            contractual_pool_cents,
            bdflow_due_cents,
            cash_user_pool_funding_cents,
            total_monetary_funding_required_cents,
            contract_economics_version
       INTO v_id, v_eco_grav, v_pool_grav, v_bdflow_grav, v_cash_grav,
            v_total_grav, v_econ_versao;

  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL
   WHERE id = v_opp.id;

  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  VALUES (v_cnpj, v_region.uf, v_city_key, v_opp.niche_code, v_id)
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.manually_registered', v_id, 'admin',
    pg_catalog.jsonb_build_object(
      'pricing_rule_version', v_versao,
      'benefit_settlement_mode', p_benefit_settlement_mode,
      'payment_method', v_pricing->>'payment_method',
      'economic_value_cents', v_eco_grav,
      'contract_economics_version', v_econ_versao,
      'total_monetary_funding_required_cents', v_total_grav),
    NULL,
    pg_catalog.jsonb_build_object('opportunity_id', p_opportunity_id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'order_id', v_id,
    'pricing_rule_version', v_versao,
    'fidelized', v_fidel,
    'payment_method', v_pricing->>'payment_method',
    'benefit_settlement_mode', p_benefit_settlement_mode,
    'economic_value_cents', v_eco_grav,
    'user_pool_cents', v_pool_grav,
    'bdflow_ops_investment_cents', v_bdflow_grav,
    'cash_user_pool_funding_cents', v_cash_grav,
    'total_monetary_funding_required_cents', v_total_grav,
    -- NULL em pedido V1/V2: só a v1.4 tem rótulo legal de economia.
    'contract_economics_version', v_econ_versao);
END;
$function$;
SELECT pg_temp.reaplicar_acl('admin_register_manual_commercial_order', 'public.admin_register_manual_commercial_order(uuid,uuid,text,timestamp with time zone,text,date,text,text,text,text,integer)');

CREATE OR REPLACE FUNCTION public.join_my_commercial_future_queue(p_company_id uuid, p_niche_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_company public.site_partner_companies%ROWTYPE;
  v_region jsonb;
  v_region_id uuid;
  v_current public.commercial_exclusivities%ROWTYPE;
  v_next public.commercial_exclusivities%ROWTYPE;
  v_opp public.commercial_opportunities%ROWTYPE;
  v_pre public.commercial_preorders%ROWTYPE;
  v_wait public.commercial_sales_waitlist%ROWTYPE;
  v_position bigint;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  SELECT * INTO v_company
    FROM public.site_partner_companies
   WHERE id = p_company_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.commercial_niches n
     WHERE n.code = p_niche_code AND n.is_active
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_niche');
  END IF;

  v_region := public.resolve_commercial_region(v_company.uf, v_company.city);
  IF coalesce((v_region->>'region_available')::boolean, false) IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'region_not_operating');
  END IF;
  v_region_id := (v_region->>'region_id')::uuid;

  SELECT * INTO v_current
    FROM public.commercial_exclusivities e
   WHERE e.region_id = v_region_id AND e.is_current
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_current_exclusivity');
  END IF;

  SELECT * INTO v_opp
    FROM public.commercial_opportunities o
   WHERE o.exclusivity_id = v_current.id
     AND o.niche_code = p_niche_code
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  IF v_opp.status = 'available' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'current_opportunity_available');
  END IF;

  INSERT INTO public.commercial_exclusivities
    (region_id, sequence_number, status, is_current)
  VALUES
    (v_region_id, v_current.sequence_number + 1, 'forming', false)
  ON CONFLICT (region_id, sequence_number) DO NOTHING;

  SELECT * INTO v_next
    FROM public.commercial_exclusivities e
   WHERE e.region_id = v_region_id
     AND e.sequence_number = v_current.sequence_number + 1
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'next_exclusivity_unavailable');
  END IF;

  SELECT * INTO v_pre
    FROM public.commercial_preorders p
   WHERE p.target_exclusivity_id = v_next.id
     AND p.company_id = p_company_id
     AND p.status IN ('waiting','reservation_offered','reservation_accepted')
   ORDER BY p.created_at
   LIMIT 1;

  IF FOUND THEN
    IF v_pre.niche_code = p_niche_code THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', true, 'already', true, 'mode', 'preorder',
        'preorder_id', v_pre.id,
        'status', v_pre.status,
        'target_exclusivity_id', v_next.id,
        'target_sequence_number', v_next.sequence_number);
    END IF;

    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'company_already_preordered_next_exclusivity',
      'target_sequence_number', v_next.sequence_number);
  END IF;

  v_id := NULL;
  INSERT INTO public.commercial_preorders
    (company_id, region_id, niche_code, target_exclusivity_id,
     status, source, created_by)
  VALUES
    (p_company_id, v_region_id, p_niche_code, v_next.id,
     'waiting', 'site', v_uid)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    PERFORM public.m1_auditar(
      'commercial_preorder.interest_registered',
      v_id,
      'owner',
      pg_catalog.jsonb_build_object(
        'company_id', p_company_id,
        'region_id', v_region_id,
        'niche_code', p_niche_code,
        'target_exclusivity_id', v_next.id,
        'target_sequence_number', v_next.sequence_number,
        'status', 'waiting'),
      NULL::jsonb,
      pg_catalog.jsonb_build_object(
        'contract_created', false,
        'reservation_created', false,
        'payment_started', false)
    );

    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'already', false, 'mode', 'preorder',
      'preorder_id', v_id,
      'status', 'waiting',
      'target_exclusivity_id', v_next.id,
      'target_sequence_number', v_next.sequence_number);
  END IF;

  SELECT * INTO v_wait
    FROM public.commercial_sales_waitlist w
   WHERE w.company_id = p_company_id
     AND w.region_id = v_region_id
     AND w.niche_code = p_niche_code
     AND w.status IN (
       'waiting','contact_pending','invited',
       'reservation_offered','reservation_accepted')
   ORDER BY w.created_at
   LIMIT 1;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'already', true, 'mode', 'sales_waitlist',
      'waitlist_id', v_wait.id,
      'status', v_wait.status,
      'position', v_wait.position,
      'first_possible_exclusivity_sequence',
        v_wait.first_possible_exclusivity_sequence);
  END IF;

  INSERT INTO public.commercial_sales_waitlist_counters
    (region_id, niche_code, next_position)
  VALUES
    (v_region_id, p_niche_code, 2)
  ON CONFLICT (region_id, niche_code)
  DO UPDATE SET next_position =
    commercial_sales_waitlist_counters.next_position + 1
  RETURNING next_position - 1 INTO v_position;

  INSERT INTO public.commercial_sales_waitlist
    (company_id, region_id, niche_code,
     first_possible_exclusivity_sequence, position,
     status, source, created_by)
  VALUES
    (p_company_id, v_region_id, p_niche_code,
     v_next.sequence_number + 1, v_position,
     'waiting', 'site', v_uid)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT * INTO v_wait
      FROM public.commercial_sales_waitlist w
     WHERE w.company_id = p_company_id
       AND w.region_id = v_region_id
       AND w.niche_code = p_niche_code
       AND w.status IN (
         'waiting','contact_pending','invited',
         'reservation_offered','reservation_accepted')
     ORDER BY w.created_at
     LIMIT 1;

    IF FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', true, 'already', true, 'mode', 'sales_waitlist',
        'waitlist_id', v_wait.id,
        'status', v_wait.status,
        'position', v_wait.position,
        'first_possible_exclusivity_sequence',
          v_wait.first_possible_exclusivity_sequence);
    END IF;

    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'queue_conflict');
  END IF;

  PERFORM public.m1_auditar(
    'commercial_sales_waitlist.joined',
    v_id,
    'owner',
    pg_catalog.jsonb_build_object(
      'company_id', p_company_id,
      'region_id', v_region_id,
      'niche_code', p_niche_code,
      'position', v_position,
      'first_possible_exclusivity_sequence', v_next.sequence_number + 1,
      'status', 'waiting'),
    NULL::jsonb,
    pg_catalog.jsonb_build_object('position_immutable', true)
  );

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'mode', 'sales_waitlist',
    'waitlist_id', v_id,
    'status', 'waiting',
    'position', v_position,
    'first_possible_exclusivity_sequence', v_next.sequence_number + 1);
END;
$function$;
SELECT pg_temp.reaplicar_acl('join_my_commercial_future_queue', 'public.join_my_commercial_future_queue(uuid,text)');

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

CREATE OR REPLACE FUNCTION public.finalize_commercial_order_from_intent(p_intent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg     jsonb;
  v_template jsonb;
  v_uid      uuid := auth.uid();
  v_i     public.commercial_checkout_intents%ROWTYPE;
  v_opp   public.commercial_opportunities%ROWTYPE;
  v_ace   public.legal_acceptances%ROWTYPE;
  v_doc   public.legal_documents%ROWTYPE;
  v_agree public.commercial_master_agreements%ROWTYPE;
  v_comp  public.site_partner_companies%ROWTYPE;
  v_nome  text;
  v_exist uuid;
  v_id    uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_i FROM public.commercial_checkout_intents
   WHERE id = p_intent_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_found');
  END IF;
  IF NOT public.m2_is_company_owner(v_i.company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  -- Idempotência: a mesma intenção já finalizada devolve o mesmo pedido.
  SELECT id INTO v_exist FROM public.commercial_exclusivity_orders
   WHERE checkout_intent_id = v_i.id AND status <> 'cancelled';
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'order_id', v_exist, 'intent_status', v_i.status);
  END IF;

  SELECT * INTO v_comp
    FROM public.site_partner_companies
   WHERE id = v_i.company_id
   FOR UPDATE;

  SELECT id INTO v_exist
    FROM public.commercial_exclusivity_orders
   WHERE exclusivity_id = v_i.exclusivity_id
     AND company_id = v_i.company_id
     AND status <> 'cancelled'
   LIMIT 1;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'company_already_contracted_in_exclusivity',
      'existing_order_id', v_exist);
  END IF;

  IF v_i.status <> 'awaiting_contract' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_awaiting_contract',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
  END IF;

  -- P0-C: contratação nova sob a autoridade v1.4 não pode chegar a `signed`
  -- enquanto não existir instrumento juridicamente liberado para a condição.
  -- A trigger estrutural repete o gate na inserção para fechar qualquer caminho
  -- futuro; este preflight dá ao chamador o erro de domínio determinístico.
  IF v_i.pricing_rule_version >= 3 THEN
    v_template := public.commercial_signable_instrument_template(v_i.fidelized);
    IF (v_template->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_template;
    END IF;
  END IF;

  -- ---- aceite exato: do titular, desta intenção, do contexto e tipo certos
  SELECT a.* INTO v_ace
    FROM public.legal_acceptances a
    JOIN public.legal_documents d ON d.id = a.legal_document_id
   WHERE a.subject_type = 'commercial_checkout_intent'
     AND a.subject_id = v_i.id
     AND a.commercial_checkout_intent_id = v_i.id
     AND a.context = 'commercial_contract'
     AND a.linked_auth_user_id = v_uid
     AND a.revoked_at IS NULL
     AND d.doc_type = 'commercial_order_terms'
     AND d.status = 'published'
     AND d.effective_from <= pg_catalog.now()
     AND (d.effective_to IS NULL OR d.effective_to > pg_catalog.now())
   ORDER BY a.accepted_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'terms_not_accepted');
  END IF;

  SELECT * INTO v_doc FROM public.legal_documents WHERE id = v_ace.legal_document_id;

  -- O aceite tem de ter acontecido DENTRO da reserva viva.
  IF v_ace.accepted_at > v_i.reserved_until THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_outside_reservation');
  END IF;

  -- ---- acordo mestre vigente: obrigatório, e não fabricado aqui
  -- P0-1 PORTAO 4 de 4, AUTORITATIVO: mesma definicao unica de elegibilidade,
  -- agora COM LOCK. O FOR UPDATE acontece dentro do resolvedor, na transacao
  -- desta funcao, e e o que fecha a janela de corrida contra revogacao
  -- concorrente — comportamento provado por scripts/db-test/p01-master-race.sh.
  v_eleg := public.m2_master_agreement_eligibility(v_i.company_id, true);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
  END IF;
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE id = (v_eleg->>'master_agreement_id')::uuid;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  -- ---- oportunidade ainda reservada para ESTA intenção
  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = v_i.opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;
  IF v_opp.status <> 'reserved'
     OR v_opp.reserved_until IS NULL
     OR v_opp.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired',
                                         'opportunity_status', v_opp.status);
  END IF;

  -- v_comp já foi carregada com FOR UPDATE acima.

  -- Signatário: identidade canônica do titular ativo, não texto de formulário.
  SELECT m.full_name INTO v_nome FROM public.site_company_members m
   WHERE m.company_id = v_i.company_id AND m.auth_user_id = v_uid
     AND m.role = 'partner_owner' AND m.status = 'active';
  IF v_nome IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     contract_economics_version, mei_consideration_cents, smallflags_qa_cents,
     smallflags_main_fee_cents, smallflags_total_remuneration_cents,
     benefit_settlement_mode, mei_cash_funding_cents, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     status, expected_operation_start, registered_by,
     legal_acceptance_id, checkout_intent_id)
  VALUES
    (v_i.exclusivity_id, v_i.opportunity_id, v_i.company_id, v_agree.id, v_i.niche_code,
     v_i.region_id, v_i.nominal_quantity, v_i.pricing_rule_version, v_i.fidelized,
     v_i.currency,
     -- CÓPIA do instantâneo reservado, centavo a centavo.
     v_i.economic_value_cents,
     -- pool_bps e NULO sob a V2 e a intencao nao guarda bps algum: nao ha
     -- ponto-base honesto a gravar, e inventar um seria autoridade falsa.
     NULL::integer,
     v_i.user_pool_cents, v_i.bdflow_ops_investment_cents,
     -- A intenção é o snapshot da reserva. Copiamos também a decomposição
     -- v1.4 em vez de reconsultar a agenda no momento da finalização; assim
     -- nenhuma alteração futura da tabela de preços pode reprecificar uma
     -- reserva já aceita. O trigger ceo_aplicar_autoridade_v14 respeita
     -- snapshots que já trazem contract_economics_version.
     v_i.contract_economics_version,
     v_i.mei_consideration_cents, v_i.smallflags_qa_cents,
     v_i.smallflags_main_fee_cents, v_i.smallflags_total_remuneration_cents,
     v_i.benefit_settlement_mode, v_i.mei_cash_funding_cents,
     v_i.cash_user_pool_funding_cents,
     v_i.total_monetary_funding_required_cents,
     v_i.benefit_distribution_policy_version,
     v_doc.version,
     'bdflow:legal_acceptance/' || v_ace.id::text,
     v_doc.content_hash,
     v_ace.accepted_at, v_nome,
     'signed', (pg_catalog.now() + interval '30 days')::date, v_uid,
     v_ace.id, v_i.id)
  RETURNING id INTO v_id;

  -- A oportunidade sai da reserva e entra em pendência de pagamento, o mesmo
  -- estado canônico a que a venda manual sempre levou.
  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL,
         updated_at = pg_catalog.now()
   WHERE id = v_opp.id;

  UPDATE public.commercial_checkout_intents
     SET status = 'awaiting_payment_provider' WHERE id = v_i.id;

  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  SELECT v_comp.cnpj, r.uf, public.commercial_city_key(v_comp.city),
         v_i.niche_code, v_id
    FROM public.commercial_regions r WHERE r.id = v_i.region_id
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.finalized_by_owner', v_id, 'owner',
    pg_catalog.jsonb_build_object('intent_id', v_i.id,
                                  'legal_acceptance_id', v_ace.id,
                                  'master_agreement_id', v_agree.id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'order_id', v_id, 'intent_status', 'awaiting_payment_provider',
    'opportunity_status', 'payment_pending',
    'legal_acceptance_id', v_ace.id, 'document_version', v_doc.version,
    'content_hash', v_doc.content_hash,
    'economic_value_cents', v_i.economic_value_cents,
    'user_pool_cents', v_i.user_pool_cents,
    'bdflow_ops_investment_cents', v_i.bdflow_ops_investment_cents);
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_niche_contract_pricing(p_niche_code text, p_fidelized boolean, p_pricing_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_rule      public.commercial_pricing_rules%ROWTYPE;
  v_qty       integer;
  v_economic  bigint;
  v_bps       integer;
  v_pool      bigint;
  v_cat       text;
  v_ratio     public.commercial_pool_share_ratios%ROWTYPE;
  v_sched     public.commercial_pricing_schedule%ROWTYPE;
  v_disp_pool text := NULL;
  v_disp_bdf  text := NULL;
BEGIN
  IF p_pricing_version IS NULL THEN
    SELECT * INTO v_rule
      FROM public.commercial_pricing_rules
     WHERE status = 'active';
  ELSE
    SELECT * INTO v_rule
      FROM public.commercial_pricing_rules
     WHERE version = p_pricing_version;
  END IF;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  SELECT contracted_quantity INTO v_qty
    FROM public.commercial_niches
   WHERE code = p_niche_code AND is_active;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'invalid_niche');
  END IF;

  -- O catálogo ativo contém exatamente as seis posições canônicas. Enquanto
  -- OUTROS permanecer dormente ele não chega aqui, pois não existe como nicho
  -- ativo. Supermercado usa sua matriz; os outros cinco usam a matriz comum.
  v_cat := CASE WHEN p_niche_code = 'supermarket'
                THEN 'supermarket' ELSE 'common' END;

  -- SF-v1.4 e posteriores com agenda explícita.
  IF v_rule.pool_precision_model = 'explicit_schedule' THEN
    SELECT * INTO v_sched
      FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = v_rule.version
       AND commercial_category = v_cat
       AND fidelized = p_fidelized;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false,
        'reason', 'pricing_schedule_missing',
        'pricing_rule_version', v_rule.version,
        'commercial_category', v_cat,
        'fidelized', p_fidelized);
    END IF;

    RETURN pg_catalog.jsonb_build_object(
      'ok', true,
      'pricing_rule_version', v_rule.version,
      'pool_precision_model', v_rule.pool_precision_model,
      'niche_code', p_niche_code,
      'niche_category', v_cat,
      'nominal_quantity', v_qty,
      'fidelized', p_fidelized,
      'currency', 'BRL',
      'pool_bps', NULL::integer,
      'display_pool_percent', NULL::text,
      'display_bdflow_percent', NULL::text,
      'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
      'contract_economics_version', v_sched.contract_economics_version,
      'economic_value_cents', v_sched.economic_value_cents,
      'contractual_pool_cents',
        v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents,
      'bdflow_due_cents', v_sched.smallflags_main_fee_cents,
      'mei_consideration_cents', v_sched.mei_consideration_cents,
      'smallflags_qa_cents', v_sched.smallflags_qa_cents,
      'smallflags_main_fee_cents', v_sched.smallflags_main_fee_cents,
      'smallflags_total_remuneration_cents',
        v_sched.smallflags_total_remuneration_cents,
      'ordinary_participation_value_cents',
        v_sched.ordinary_participation_value_cents,
      -- NOVO: a UI lê estas três chaves; não reconstrói financiamento.
      'direct_benefit_deliverable_cents', v_sched.mei_consideration_cents,
      'funding_direct_benefits_cents',
        v_sched.smallflags_total_remuneration_cents,
      'funding_cash_cents', v_sched.economic_value_cents
    );
  END IF;

  -- V1/V2 históricos: cálculo original preservado.
  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  IF v_rule.pool_precision_model = 'exact_ratio' THEN
    SELECT * INTO v_ratio
      FROM public.commercial_pool_share_ratios
     WHERE pricing_rule_version = v_rule.version
       AND niche_category = v_cat;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'pool_ratio_unavailable');
    END IF;
    v_pool := (v_economic * v_ratio.pool_numerator) / v_ratio.pool_denominator;
    v_disp_pool := v_ratio.display_pool_percent;
    v_disp_bdf := v_ratio.display_bdflow_percent;
  ELSE
    v_bps := CASE WHEN v_cat = 'supermarket'
                  THEN v_rule.pool_bps_supermarket
                  ELSE v_rule.pool_bps_common END;
    v_pool := (v_economic * v_bps) / 10000;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'pricing_rule_version', v_rule.version,
    'pool_precision_model', v_rule.pool_precision_model,
    'niche_code', p_niche_code,
    'niche_category', v_cat,
    'nominal_quantity', v_qty,
    'fidelized', p_fidelized,
    'currency', 'BRL',
    'economic_value_cents', v_economic,
    'pool_bps', v_bps,
    'contractual_pool_cents', v_pool,
    'bdflow_due_cents', v_economic - v_pool,
    'display_pool_percent', v_disp_pool,
    'display_bdflow_percent', v_disp_bdf,
    'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
    -- NOVO: mesma semântica pública, resolvida pela autoridade histórica.
    'direct_benefit_deliverable_cents', v_pool,
    'funding_direct_benefits_cents', v_economic - v_pool,
    'funding_cash_cents', v_economic
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_current_commercial_formation(p_uf text, p_city text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_region jsonb;
  v_region_id uuid;
  v_exc record;
  v_opportunities jsonb;
  v_summary jsonb;
begin
  v_region := public.resolve_commercial_region(p_uf, p_city);

  if coalesce((v_region->>'region_available')::boolean, false) = false then
    return jsonb_build_object('region_available', false, 'region', v_region);
  end if;

  v_region_id := (v_region->>'region_id')::uuid;

  select e.* into v_exc
    from public.commercial_exclusivities e
    where e.region_id = v_region_id and e.is_current
    limit 1;

  if v_exc.id is null then
    return jsonb_build_object(
      'region_available', true,
      'exclusivity_available', false,
      'region', v_region
    );
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'id',                  o.id,
             'exclusivity_id',      o.exclusivity_id,
             'niche_code',          o.niche_code,
             'display_name',        n.display_name,
             'contracted_quantity', o.contracted_quantity,
             'status',              o.status,
             'sort_order',          n.sort_order
           ) order by n.sort_order
         )
    into v_opportunities
    from public.commercial_opportunities o
    join public.commercial_niches n on n.code = o.niche_code
    where o.exclusivity_id = v_exc.id;

  v_summary := public.commercial_formation_summary(v_exc.id);

  return jsonb_build_object(
    'region_available', true,
    'exclusivity_available', true,
    'region', v_region,
    'exclusivity', jsonb_build_object(
      'id',              v_exc.id,
      'region_id',       v_exc.region_id,
      'sequence_number', v_exc.sequence_number,
      'status',          v_exc.status,
      'is_current',      v_exc.is_current,
      'planned_start_at',v_exc.planned_start_at
    ),
    'summary', v_summary,
    'opportunities', coalesce(v_opportunities, '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_commercial_future_interest(p_company_id uuid, p_niche_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_pre public.commercial_preorders%ROWTYPE;
  v_wait public.commercial_sales_waitlist%ROWTYPE;
  v_seq integer;
BEGIN
  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  SELECT * INTO v_pre
    FROM public.commercial_preorders p
   WHERE p.company_id = p_company_id
     AND p.niche_code = p_niche_code
     AND p.status IN (
       'waiting','reservation_offered',
       'reservation_accepted','reservation_expired')
   ORDER BY p.created_at DESC
   LIMIT 1;

  IF FOUND THEN
    SELECT e.sequence_number INTO v_seq
      FROM public.commercial_exclusivities e
     WHERE e.id = v_pre.target_exclusivity_id;

    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'mode', 'preorder',
      'preorder_id', v_pre.id,
      'status', v_pre.status,
      'target_exclusivity_id', v_pre.target_exclusivity_id,
      'target_sequence_number', v_seq);
  END IF;

  SELECT * INTO v_wait
    FROM public.commercial_sales_waitlist w
   WHERE w.company_id = p_company_id
     AND w.niche_code = p_niche_code
     AND w.status NOT IN ('converted','declined','cancelled')
   ORDER BY w.created_at DESC
   LIMIT 1;

  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'mode', 'sales_waitlist',
      'waitlist_id', v_wait.id,
      'status', v_wait.status,
      'position', v_wait.position,
      'first_possible_exclusivity_sequence',
        v_wait.first_possible_exclusivity_sequence);
  END IF;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'mode', 'none');
END;
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

CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot(p_order_id uuid, p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o      public.commercial_exclusivity_orders%ROWTYPE;
  v_c      public.site_partner_companies%ROWTYPE;
  v_u      public.site_partner_units%ROWTYPE;
  v_a      public.commercial_master_agreements%ROWTYPE;
  v_rep    public.partner_application_representatives%ROWTYPE;
  v_ace    public.legal_acceptances%ROWTYPE;
  v_t      public.commercial_instrument_templates%ROWTYPE;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_ativ   jsonb;
  v_snap   jsonb;
  v_prov   jsonb;
  v_faltam text[] := ARRAY[]::text[];
  v_campo  text;
BEGIN
  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE id = p_template_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_unavailable');
  END IF;
  IF v_t.lifecycle_status <> 'signable' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_not_signable',
      'lifecycle_status', v_t.lifecycle_status, 'template_code', v_t.template_code);
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF coalesce(v_o.fidelized, false) <> v_t.applies_to_fidelized THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_fidelity_mismatch',
      'order_fidelized', coalesce(v_o.fidelized, false),
      'template_applies_to_fidelized', v_t.applies_to_fidelized);
  END IF;

  -- OUTROS dormente: nicho fora do catalogo canonico nao individualiza nada.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_niches n
                  WHERE n.code = v_o.niche_code AND n.is_active) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_niche_not_canonical',
      'niche_code', v_o.niche_code);
  END IF;

  SELECT * INTO v_c FROM public.site_partner_companies WHERE id = v_o.company_id;
  SELECT * INTO v_a FROM public.commercial_master_agreements
   WHERE id = v_o.master_agreement_id;
  SELECT * INTO v_rep FROM public.partner_application_representatives
   WHERE application_id = v_c.source_application_id AND is_current;
  IF v_o.legal_acceptance_id IS NOT NULL THEN
    SELECT * INTO v_ace FROM public.legal_acceptances WHERE id = v_o.legal_acceptance_id;
  END IF;

  -- ---- UNIDADE DE EXECUCAO: persistida e revalidada, nunca "a primeira".
  IF v_o.execution_unit_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_selected', 'order_id', v_o.id);
  END IF;
  SELECT * INTO v_u FROM public.site_partner_units WHERE id = v_o.execution_unit_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_found');
  END IF;
  IF v_u.company_id IS DISTINCT FROM v_o.company_id THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_owned_by_company');
  END IF;
  IF v_u.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_active', 'status', v_u.status);
  END IF;

  -- ---- TOMADOR DE NFS-e: tem de ser o CNPJ da contratante no MVP fundador.
  IF v_o.nfse_taker_cnpj IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'nfse_taker_not_persisted');
  END IF;
  IF pg_catalog.regexp_replace(v_o.nfse_taker_cnpj, '[^0-9]', '', 'g')
       IS DISTINCT FROM
       pg_catalog.regexp_replace(v_c.cnpj, '[^0-9]', '', 'g') THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'alternate_nfse_taker_not_supported',
      'persisted_taker', v_o.nfse_taker_cnpj);
  END IF;

  -- ---- ECONOMIA: da autoridade, incluindo o valor da participacao.
  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = v_o.pricing_rule_version
     AND contract_economics_version = v_o.contract_economics_version
     AND commercial_category = CASE WHEN v_o.niche_code = 'supermarket'
                                    THEN 'supermarket' ELSE 'common' END
     AND fidelized = coalesce(v_o.fidelized, false);
  IF NOT FOUND OR v_sched.ordinary_participation_value_cents IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'contract_economics_authority_unavailable',
      'pricing_rule_version', v_o.pricing_rule_version);
  END IF;

  -- ---- ATIVIDADE CONTRATADA: do catalogo. Bloqueada em producao.
  v_ativ := public.commercial_approved_contract_activity(
              v_o.niche_code, v_o.contract_economics_version);
  IF (v_ativ->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_ativ;
  END IF;

  v_snap := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'company_legal_name', v_c.legal_name,
    'company_cnpj', v_c.cnpj,
    'company_trade_name', v_c.trade_name,
    'representative_full_name', v_rep.full_name,
    'representative_cpf', v_rep.cpf,
    'representative_role_title', v_rep.role_title,
    'representative_authority_status', v_rep.authority_status,
    'city', v_c.city,
    'uf', v_c.uf,
    'region_id', v_o.region_id,
    'exclusivity_id', v_o.exclusivity_id,
    'nfse_taker_cnpj', v_o.nfse_taker_cnpj,
    'execution_unit_id', v_u.id,
    'execution_unit_name', v_u.name,
    'execution_unit_city', v_u.city,
    'execution_unit_uf', v_u.uf,
    'execution_unit_company_id', v_u.company_id,
    'activity_description', v_ativ->>'activity_description',
    'activity_code', v_ativ->>'activity_code',
    'activity_catalog_id', v_ativ->>'activity_catalog_id',
    'activity_source_hash', v_ativ->>'source_hash',
    'niche_code', v_o.niche_code,
    'nominal_quantity', v_o.nominal_quantity,
    'benefit_settlement_mode', v_o.benefit_settlement_mode,
    'master_agreement_id', v_a.id,
    'master_legal_document_id', v_a.legal_document_id,
    'master_agreement_version', v_a.agreement_version,
    'master_document_hash', v_a.document_hash,
    'order_id', v_o.id,
    'pricing_rule_version', v_o.pricing_rule_version,
    'contract_economics_version', v_o.contract_economics_version,
    'economic_value_cents', v_o.economic_value_cents,
    'mei_consideration_cents', v_o.mei_consideration_cents,
    'smallflags_qa_cents', v_o.smallflags_qa_cents,
    'smallflags_main_fee_cents', v_o.smallflags_main_fee_cents,
    'smallflags_total_remuneration_cents', v_o.smallflags_total_remuneration_cents,
    'total_monetary_funding_required_cents', v_o.total_monetary_funding_required_cents,
    'participation_value_cents', v_sched.ordinary_participation_value_cents,
    'acceptance_actor_id', coalesce(v_ace.linked_auth_user_id, v_o.registered_by),
    'acceptance_at', coalesce(v_ace.accepted_at, v_o.signed_at)));

  -- Proveniencia por REGISTRO CANONICO, nao por "veio do chamador".
  v_prov := pg_catalog.jsonb_build_object(
    'company_legal_name', 'site_company',
    'company_cnpj', 'site_company',
    'company_trade_name', 'site_company',
    'city', 'site_company',
    'uf', 'site_company',
    'nfse_taker_cnpj', 'site_company',
    'representative_full_name', 'site_representative',
    'representative_cpf', 'site_representative',
    'representative_role_title', 'site_representative',
    'representative_authority_status', 'site_representative',
    'execution_unit_id', 'site_unit',
    'execution_unit_name', 'site_unit',
    'execution_unit_city', 'site_unit',
    'execution_unit_uf', 'site_unit',
    'execution_unit_company_id', 'site_unit',
    'activity_description', 'commercial_activity_authority',
    'activity_code', 'commercial_activity_authority',
    'activity_catalog_id', 'commercial_activity_authority',
    'activity_source_hash', 'commercial_activity_authority',
    'participation_value_cents', 'contract_economics_authority',
    'economic_value_cents', 'contract_economics_authority',
    'mei_consideration_cents', 'contract_economics_authority',
    'smallflags_qa_cents', 'contract_economics_authority',
    'smallflags_main_fee_cents', 'contract_economics_authority',
    'smallflags_total_remuneration_cents', 'contract_economics_authority',
    'total_monetary_funding_required_cents', 'contract_economics_authority',
    'contract_economics_version', 'contract_economics_authority',
    'pricing_rule_version', 'contract_economics_authority',
    'master_agreement_id', 'master_agreement',
    'master_legal_document_id', 'master_agreement',
    'master_agreement_version', 'master_agreement',
    'master_document_hash', 'master_agreement',
    'acceptance_actor_id', 'legal_acceptance',
    'acceptance_at', 'legal_acceptance',
    'order_id', 'commercial_order',
    'region_id', 'commercial_order',
    'exclusivity_id', 'commercial_order',
    'niche_code', 'commercial_order',
    'nominal_quantity', 'commercial_order',
    'benefit_settlement_mode', 'commercial_order');

  -- Falha fechada nomeando CADA fato material ausente.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_snap ? v_campo) THEN
      v_faltam := v_faltam || v_campo;
    END IF;
  END LOOP;
  IF array_length(v_faltam, 1) >= 1 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'instrument_snapshot_material_fact_missing',
      'missing_fields', pg_catalog.to_jsonb(v_faltam),
      'template_code', v_t.template_code);
  END IF;

  -- Nenhum fato do snapshot pode ter vindo de fora das autoridades: toda chave
  -- material tem de ter proveniencia declarada.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_prov ? v_campo) THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'instrument_snapshot_provenance_undeclared',
        'field', v_campo);
    END IF;
  END LOOP;

  v_snap := v_snap || pg_catalog.jsonb_build_object(
    'instrument_template_code', v_t.template_code,
    'instrument_template_version', v_t.template_version,
    'instrument_template_date', v_t.template_date,
    'instrument_template_source_hash', v_t.source_hash,
    'field_provenance', v_prov);

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'template_id', v_t.id,
    'template_version', v_t.template_version,
    'template_date', v_t.template_date,
    'template_source_hash', v_t.source_hash,
    'snapshot', v_snap,
    'snapshot_hash',
      pg_catalog.encode(extensions.digest(v_snap::text, 'sha256'), 'hex'));
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

CREATE OR REPLACE FUNCTION public.is_fidelized_context(p_cnpj text, p_uf text, p_city text, p_niche_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.commercial_fidelity_records f
     WHERE f.cnpj = public.somente_digitos(p_cnpj)
       AND f.uf = pg_catalog.upper(pg_catalog.btrim(p_uf))
       AND f.city_key = public.commercial_city_key(p_city)
       AND f.niche_code = p_niche_code
       -- R15: pedido fundador cancelado não sustenta fidelidade futura.
       AND NOT EXISTS (
             SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.id = f.established_by_order_id
                AND o.status = 'cancelled'));
$function$;

DROP FUNCTION public.is_fidelized_context(text, text, text, text, uuid);
DROP FUNCTION public.commercial_resolve_position_segment(text, uuid, uuid, uuid, boolean);
DROP FUNCTION public.commercial_fidelity_identity(text, uuid);

-- Fidelidade: volta a unicidade por (cnpj, uf, cidade, nicho)
DROP TRIGGER cfr_derivar_identidade ON public.commercial_fidelity_records;
DROP FUNCTION public.cfr_derivar_identidade();
DROP INDEX public.cfr_identidade_unica;
ALTER TABLE public.commercial_fidelity_records
  DROP CONSTRAINT cfr_identidade_formato,
  DROP COLUMN fidelity_identity,
  ADD CONSTRAINT cfr_unico UNIQUE (cnpj, uf, city_key, niche_code);

-- Snapshot de segmento
DROP TRIGGER ceo_segmento_da_intencao ON public.commercial_exclusivity_orders;
DROP FUNCTION public.ceo_segmento_da_intencao();
DROP INDEX public.ceo_segmento_por_exclusividade_idx;
DROP INDEX public.cpo_segmento_por_exclusividade_idx;
DROP TRIGGER cci_segmento_imutavel ON public.commercial_checkout_intents;
ALTER TABLE public.commercial_checkout_intents
  DROP CONSTRAINT cci_segmento_snapshot_coerente,
  DROP CONSTRAINT cci_supermercado_sem_segmento,
  DROP CONSTRAINT cci_segmento_posicao_elegivel,
  DROP CONSTRAINT cci_outros_exige_segmento,
  DROP COLUMN segment_classification_snapshot,
  DROP COLUMN segment_name_snapshot,
  DROP COLUMN segment_code_snapshot,
  DROP COLUMN segment_id;
DROP TRIGGER ceo_segmento_imutavel ON public.commercial_exclusivity_orders;
ALTER TABLE public.commercial_exclusivity_orders
  DROP CONSTRAINT ceo_segmento_snapshot_coerente,
  DROP CONSTRAINT ceo_supermercado_sem_segmento,
  DROP CONSTRAINT ceo_segmento_posicao_elegivel,
  DROP CONSTRAINT ceo_outros_exige_segmento,
  DROP COLUMN segment_classification_snapshot,
  DROP COLUMN segment_name_snapshot,
  DROP COLUMN segment_code_snapshot,
  DROP COLUMN segment_id;
DROP TRIGGER cpo_segmento_imutavel ON public.commercial_preorders;
ALTER TABLE public.commercial_preorders
  DROP CONSTRAINT cpo_segmento_snapshot_coerente,
  DROP CONSTRAINT cpo_supermercado_sem_segmento,
  DROP CONSTRAINT cpo_segmento_posicao_elegivel,
  DROP CONSTRAINT cpo_outros_exige_segmento,
  DROP COLUMN segment_classification_snapshot,
  DROP COLUMN segment_name_snapshot,
  DROP COLUMN segment_code_snapshot,
  DROP COLUMN segment_id;
DROP TRIGGER csw_segmento_imutavel ON public.commercial_sales_waitlist;
ALTER TABLE public.commercial_sales_waitlist
  DROP CONSTRAINT csw_segmento_snapshot_coerente,
  DROP CONSTRAINT csw_supermercado_sem_segmento,
  DROP CONSTRAINT csw_segmento_posicao_elegivel,
  DROP CONSTRAINT csw_outros_exige_segmento,
  DROP COLUMN segment_classification_snapshot,
  DROP COLUMN segment_name_snapshot,
  DROP COLUMN segment_code_snapshot,
  DROP COLUMN segment_id;
DROP FUNCTION public.commercial_segment_snapshot_imutavel();

-- Tabelas de segmento (a auditoria das decisões permanece em audit_logs)
DROP TABLE public.commercial_segment_requests;
DROP TABLE public.commercial_segments;
DROP FUNCTION public.commercial_segment_requests_protect();
DROP FUNCTION public.commercial_segments_protect();
DROP FUNCTION public.commercial_normalize_segment_label(text);

-- Remapeamento inverso das oportunidades livres em formação
DO $volta$
DECLARE r record; v_legado text;
BEGIN
  FOR r IN
    SELECT o.* FROM public.commercial_opportunities o
      JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
     WHERE o.niche_code IN ('footwear','others') AND e.status = 'forming'
  LOOP
    v_legado := CASE r.niche_code WHEN 'footwear' THEN 'womens_footwear' ELSE 'mens_footwear' END;
    -- o nicho legado precisa aceitar a oportunidade (canonical_qty exige linha)
    UPDATE public.commercial_opportunities
       SET niche_code = v_legado, updated_at = pg_catalog.now()
     WHERE id = r.id;
    INSERT INTO public.audit_logs
      (actor_role, action, entity_type, entity_id, previous_state, new_state, source, metadata)
    VALUES ('system', 'commercial_opportunity.position_remap_reverted', 'commercial_opportunity',
            r.id::text, pg_catalog.jsonb_build_object('niche_code', r.niche_code),
            pg_catalog.jsonb_build_object('niche_code', v_legado),
            'rollback_20261103120000', pg_catalog.jsonb_build_object('decision', 'D2'));
  END LOOP;
END $volta$;

-- Catálogo: seis nichos com calçados F/M
ALTER TABLE public.commercial_niches
  DROP CONSTRAINT commercial_niches_legado_inativo,
  DROP CONSTRAINT commercial_niches_canonical,
  DROP CONSTRAINT commercial_niches_code_allowed,
  DROP CONSTRAINT commercial_niches_sort_order_range;
DELETE FROM public.commercial_niches WHERE code IN ('footwear','others');
UPDATE public.commercial_niches SET sort_order = 5, is_active = true, updated_at = pg_catalog.now()
 WHERE code = 'womens_footwear';
UPDATE public.commercial_niches SET sort_order = 6, is_active = true, updated_at = pg_catalog.now()
 WHERE code = 'mens_footwear';
ALTER TABLE public.commercial_niches
  ADD CONSTRAINT commercial_niches_canonical CHECK ((((code = 'supermarket'::text) AND (contracted_quantity = 24) AND (sort_order = 1)) OR ((code = 'pharmacy'::text) AND (contracted_quantity = 12) AND (sort_order = 2)) OR ((code = 'womens_clothing'::text) AND (contracted_quantity = 12) AND (sort_order = 3)) OR ((code = 'mens_clothing'::text) AND (contracted_quantity = 12) AND (sort_order = 4)) OR ((code = 'womens_footwear'::text) AND (contracted_quantity = 12) AND (sort_order = 5)) OR ((code = 'mens_footwear'::text) AND (contracted_quantity = 12) AND (sort_order = 6)))),
  ADD CONSTRAINT commercial_niches_code_allowed CHECK ((code = ANY (ARRAY['supermarket'::text, 'pharmacy'::text, 'womens_clothing'::text, 'mens_clothing'::text, 'womens_footwear'::text, 'mens_footwear'::text]))),
  ADD CONSTRAINT commercial_niches_sort_order_range CHECK (((sort_order >= 1) AND (sort_order <= 6)));
COMMENT ON TABLE public.commercial_niches IS NULL;

COMMIT;
