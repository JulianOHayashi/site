-- ============================================================================
-- M2 / R8 — Venda manual e confirmação do pagamento devido à BDFlow
--
-- As primeiras vendas são pessoais: não existe checkout público. Estas
-- operações são administrativas, server-side, idempotentes e auditadas.
--
-- "PAGO" = o valor DEVIDO À BDFLOW foi confirmado como recebido.
-- A BDFlow NÃO custodia o pool contratual de benefício: ele permanece
-- obrigação do parceiro, honrada na própria rede. Confirmar o valor econômico
-- integral é recusado explicitamente.
--
-- O cliente NUNCA envia preço: o servidor recalcula pela regra vigente e
-- avalia a fidelidade pelo contexto CNPJ + cidade + nicho.
-- ============================================================================

CREATE FUNCTION public.admin_register_manual_commercial_order(
  p_opportunity_id uuid,
  p_company_id     uuid,
  p_order_version  text,
  p_signed_at      timestamptz,
  p_signatory_name text,
  p_expected_operation_start date,
  p_document_reference text DEFAULT NULL,
  p_document_hash      text DEFAULT NULL,
  p_external_signature_ref text DEFAULT NULL,
  p_exclusivity_period_days integer DEFAULT 28
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_opp      public.commercial_opportunities%ROWTYPE;
  v_excl     public.commercial_exclusivities%ROWTYPE;
  v_company  public.site_partner_companies%ROWTYPE;
  v_agree    public.commercial_master_agreements%ROWTYPE;
  v_region   public.commercial_regions%ROWTYPE;
  v_existing public.commercial_exclusivity_orders%ROWTYPE;
  v_city_key text;
  v_fidel    boolean;
  v_pricing  jsonb;
  v_id       uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signature_date');
  END IF;
  IF p_document_reference IS NULL AND p_document_hash IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_evidence_required');
  END IF;

  -- Trava a oportunidade: vendas concorrentes do mesmo nicho serializam.
  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = p_opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  -- Idempotência: oportunidade já vendida à MESMA empresa devolve o pedido.
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

  -- Um CNPJ ocupa no máximo um nicho na mesma exclusividade.
  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.exclusivity_id = v_opp.exclusivity_id
                AND o.company_id = p_company_id AND o.status <> 'cancelled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_already_in_exclusivity');
  END IF;

  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = p_company_id AND status = 'signed';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  SELECT c.city_key INTO v_city_key
    FROM public.commercial_region_cities c
   WHERE c.region_id = v_region.id AND c.is_active
   ORDER BY c.city_name LIMIT 1;

  v_fidel := EXISTS (
    SELECT 1 FROM public.commercial_fidelity_records f
     WHERE f.cnpj = v_company.cnpj AND f.uf = v_region.uf
       AND f.city_key = v_city_key AND f.niche_code = v_opp.niche_code);

  -- PREÇO AUTORITATIVO DO SERVIDOR: o chamador não envia valor algum.
  v_pricing := public.calculate_niche_contract_pricing(v_opp.niche_code, v_fidel);
  IF (v_pricing->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
                                         'reason', v_pricing->>'reason');
  END IF;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     external_signature_ref, status,
     expected_operation_start, exclusivity_period_days, registered_by)
  VALUES
    (v_opp.exclusivity_id, v_opp.id, p_company_id, v_agree.id, v_opp.niche_code,
     v_region.id, v_opp.contracted_quantity,
     (v_pricing->>'pricing_rule_version')::int, v_fidel, 'BRL',
     (v_pricing->>'economic_value_cents')::bigint,
     (v_pricing->>'pool_bps')::int,
     (v_pricing->>'contractual_pool_cents')::bigint,
     (v_pricing->>'bdflow_due_cents')::bigint,
     pg_catalog.btrim(p_order_version),
     nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_document_hash,'')), ''),
     p_signed_at, pg_catalog.btrim(p_signatory_name),
     nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
     'signed',
     p_expected_operation_start, p_exclusivity_period_days, auth.uid())
  RETURNING id INTO v_id;

  -- A oportunidade passa a aguardar a confirmação do valor devido.
  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL
   WHERE id = v_opp.id;

  -- O primeiro contrato do contexto estabelece a fidelidade dos próximos.
  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  VALUES (v_company.cnpj, v_region.uf, v_city_key, v_opp.niche_code, v_id)
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.manually_registered', v_id, 'admin',
    pg_catalog.jsonb_build_object(
      'company_id', p_company_id, 'niche_code', v_opp.niche_code,
      'economic_value_cents', (v_pricing->>'economic_value_cents')::bigint,
      'bdflow_due_cents', (v_pricing->>'bdflow_due_cents')::bigint,
      'fidelized', v_fidel));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'order_id', v_id,
    'niche_code', v_opp.niche_code, 'fidelized', v_fidel,
    'economic_value_cents', (v_pricing->>'economic_value_cents')::bigint,
    'contractual_pool_cents', (v_pricing->>'contractual_pool_cents')::bigint,
    'bdflow_due_cents', (v_pricing->>'bdflow_due_cents')::bigint);
END;
$$;

-- ----------------------------------------------------------------------------
-- Confirmação MANUAL do valor devido à BDFlow
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.admin_confirm_manual_bdflow_payment(
  p_order_id     uuid,
  p_amount_cents bigint,
  p_payment_external_ref text DEFAULT NULL,
  p_justification text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_ord public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  PERFORM public.m1_exigir_admin();

  SELECT * INTO v_ord FROM public.commercial_exclusivity_orders
   WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF v_ord.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;
  IF v_ord.status <> 'signed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_signed');
  END IF;

  -- Idempotência: já confirmado devolve o estado, sem sobrescrever.
  IF v_ord.payment_status = 'confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'payment_status', 'confirmed');
  END IF;

  -- "Pago" é o valor DEVIDO À BDFLOW. O pool NÃO é cobrado nem custodiado.
  IF p_amount_cents IS NULL OR p_amount_cents <> v_ord.bdflow_due_cents THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'amount_differs_from_due',
      'expected_cents', v_ord.bdflow_due_cents);
  END IF;

  UPDATE public.commercial_exclusivity_orders
     SET payment_status = 'confirmed',
         payment_confirmed_at = pg_catalog.now(),
         payment_confirmed_by = auth.uid(),
         payment_amount_cents = p_amount_cents,
         payment_external_ref = nullif(pg_catalog.btrim(coalesce(p_payment_external_ref,'')), '')
   WHERE id = p_order_id;

  UPDATE public.commercial_opportunities
     SET status = 'contracted' WHERE id = v_ord.opportunity_id;

  PERFORM public.m1_auditar('commercial_order.payment_confirmed', p_order_id, 'admin',
    pg_catalog.jsonb_build_object('payment_status','confirmed',
                                  'amount_cents', p_amount_cents),
    pg_catalog.jsonb_build_object('payment_status','pending'),
    pg_catalog.jsonb_build_object('justification', p_justification));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
                                       'payment_status', 'confirmed');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(
  uuid,uuid,text,timestamptz,text,date,text,text,text,integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(
  uuid,uuid,text,timestamptz,text,date,text,text,text,integer) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(
  uuid,uuid,text,timestamptz,text,date,text,text,text,integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_confirm_manual_bdflow_payment(
  uuid,bigint,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_confirm_manual_bdflow_payment(
  uuid,bigint,text,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_confirm_manual_bdflow_payment(
  uuid,bigint,text,text) TO authenticated;

COMMENT ON FUNCTION public.admin_confirm_manual_bdflow_payment(uuid,bigint,text,text) IS
  'Confirma o valor DEVIDO À BDFLOW como recebido. O pool contratual de '
  'benefício não é custodiado pela BDFlow e não é cobrado aqui.';
