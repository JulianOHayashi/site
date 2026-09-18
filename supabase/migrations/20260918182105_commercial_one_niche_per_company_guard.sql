-- Uma empresa pode contratar somente um nicho por exclusividade.
CREATE OR REPLACE FUNCTION public.create_commercial_checkout_intent(
  p_company_id uuid,
  p_niche_code text,
  p_benefit_settlement_mode text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
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
$$;

CREATE OR REPLACE FUNCTION public.finalize_commercial_order_from_intent(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
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
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = v_i.company_id AND status = 'signed';
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
     benefit_settlement_mode, cash_user_pool_funding_cents,
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
     v_i.benefit_settlement_mode, v_i.cash_user_pool_funding_cents,
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
$$;


WITH conflitos AS (
  SELECT i.id, i.opportunity_id, i.reserved_until
    FROM public.commercial_checkout_intents i
   WHERE i.status IN ('draft','awaiting_contract')
     AND EXISTS (
       SELECT 1
         FROM public.commercial_exclusivity_orders o
        WHERE o.exclusivity_id = i.exclusivity_id
          AND o.company_id = i.company_id
          AND o.status <> 'cancelled'
          AND o.checkout_intent_id IS DISTINCT FROM i.id
     )
)
UPDATE public.commercial_opportunities o
   SET status = 'available',
       reserved_until = NULL,
       updated_at = pg_catalog.now()
  FROM conflitos c
 WHERE o.id = c.opportunity_id
   AND o.status = 'reserved';

UPDATE public.commercial_checkout_intents i
   SET status = 'cancelled'
 WHERE i.status IN ('draft','awaiting_contract')
   AND EXISTS (
     SELECT 1
       FROM public.commercial_exclusivity_orders o
      WHERE o.exclusivity_id = i.exclusivity_id
        AND o.company_id = i.company_id
        AND o.status <> 'cancelled'
        AND o.checkout_intent_id IS DISTINCT FROM i.id
   );

