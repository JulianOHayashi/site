-- ============================================================================
-- M2 / R9 — Gate de formação comercial
--
-- A exclusividade só chega a operation_authorized quando o BACKEND PROVA
-- todas as condições. Reutiliza os estados já existentes na baseline
-- (forming / formed / start_scheduled / operation_authorized / ...).
--
-- Verificações (todas obrigatórias):
--   1. seis nichos contratados na MESMA exclusividade;
--   2. quantidades nominais conforme o catálogo canônico (24/12x5 = 84);
--   3. nenhum CNPJ ocupando mais de um nicho;
--   4. as seis empresas ativas;
--   5. acordo mestre vigente para cada empresa;
--   6. os seis pedidos assinados com evidência documental;
--   7. os seis valores devidos à BDFlow confirmados;
--   8. IMAGEM DE PERSONALIZAÇÃO corrente em cada pedido  (R7);
--   9. identidade de ponte presente em cada parceiro;
--  10. ao menos uma unidade ativa por parceiro;
--  11. ao menos um validador ativo por parceiro (owner OU manager);
--  12. data de início comum e coerente;
--  13. nenhuma autorização anterior.
--
-- A transição é idempotente e concorrência-segura: trava a linha da
-- exclusividade e REVALIDA o gate dentro da trava.
-- ============================================================================

CREATE FUNCTION public.commercial_formation_gate_report(p_exclusivity_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_excl    public.commercial_exclusivities%ROWTYPE;
  v_esperado int;
  v_pedidos  int;
  v_checks   jsonb;
BEGIN
  SELECT * INTO v_excl FROM public.commercial_exclusivities WHERE id = p_exclusivity_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- O relatório expõe pagamento e prontidão: só admin ou parceiro contratante.
  IF NOT (public.is_site_admin() OR EXISTS (
            SELECT 1 FROM public.commercial_exclusivity_orders o
             WHERE o.exclusivity_id = p_exclusivity_id AND o.status <> 'cancelled'
               AND public.m2_is_company_member(o.company_id))) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  SELECT count(*) INTO v_esperado FROM public.commercial_niches WHERE is_active;
  SELECT count(*) INTO v_pedidos FROM public.commercial_exclusivity_orders o
   WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed';

  SELECT pg_catalog.jsonb_build_object(
    'six_niches_contracted', v_pedidos = v_esperado,

    'nominal_quantities_ok', coalesce((
      SELECT bool_and(o.nominal_quantity = n.contracted_quantity)
             AND sum(o.nominal_quantity) = 84
        FROM public.commercial_exclusivity_orders o
        JOIN public.commercial_niches n ON n.code = o.niche_code
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'one_niche_per_cnpj', coalesce((
      SELECT count(DISTINCT o.company_id) = count(*)
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'companies_active', coalesce((
      SELECT bool_and(c.status = 'active')
        FROM public.commercial_exclusivity_orders o
        JOIN public.site_partner_companies c ON c.id = o.company_id
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'master_agreements_valid', coalesce((
      SELECT bool_and(EXISTS (SELECT 1 FROM public.commercial_master_agreements a
                               WHERE a.id = o.master_agreement_id AND a.status = 'signed'))
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'orders_signed', coalesce((
      SELECT bool_and(o.signed_at IS NOT NULL
                      AND (o.document_reference IS NOT NULL OR o.document_hash IS NOT NULL))
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'bdflow_payments_confirmed', coalesce((
      SELECT bool_and(o.payment_status = 'confirmed')
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    -- R7: requisito de lançamento.
    'customization_image_present', coalesce((
      SELECT bool_and(public.order_has_customization_image(o.id))
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'bridge_identity_present', coalesce((
      SELECT bool_and(c.partner_network_bridge_id IS NOT NULL)
        FROM public.commercial_exclusivity_orders o
        JOIN public.site_partner_companies c ON c.id = o.company_id
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'active_unit_per_partner', coalesce((
      SELECT bool_and((public.company_launch_readiness(o.company_id)->>'active_unit')::boolean)
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'active_validator_per_partner', coalesce((
      SELECT bool_and((public.company_launch_readiness(o.company_id)->>'active_validator')::boolean)
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'coherent_operation_start', coalesce((
      SELECT count(DISTINCT o.expected_operation_start) = 1
             AND min(o.expected_operation_start) >= current_date
        FROM public.commercial_exclusivity_orders o
       WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed'), false),

    'not_already_authorized', v_excl.operation_authorized_at IS NULL
  ) INTO v_checks;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'exclusivity_id', p_exclusivity_id,
    'status', v_excl.status,
    'contracted_niches', v_pedidos,
    'expected_niches', v_esperado,
    'checks', v_checks,
    'eligible', NOT EXISTS (SELECT 1 FROM jsonb_each(v_checks) e
                             WHERE e.value = 'false'::jsonb));
END;
$$;

CREATE FUNCTION public.admin_authorize_commercial_operation(
  p_exclusivity_id uuid, p_justification text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_excl   public.commercial_exclusivities%ROWTYPE;
  v_report jsonb;
  v_falhas text;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- TRAVA: autorizações concorrentes serializam aqui.
  SELECT * INTO v_excl FROM public.commercial_exclusivities
   WHERE id = p_exclusivity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF v_excl.operation_authorized_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'status', v_excl.status);
  END IF;

  -- REVALIDA o gate DENTRO da trava: o relatório sozinho não autoriza.
  v_report := public.commercial_formation_gate_report(p_exclusivity_id);
  IF (v_report->>'eligible')::boolean IS DISTINCT FROM true THEN
    SELECT string_agg(e.key, ', ') INTO v_falhas
      FROM jsonb_each(v_report->'checks') e WHERE e.value = 'false'::jsonb;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'gate_not_satisfied',
                                         'failed_checks', v_falhas);
  END IF;

  UPDATE public.commercial_exclusivities
     SET status = 'operation_authorized',
         formed_at = coalesce(formed_at, pg_catalog.now()),
         operation_authorized_at = pg_catalog.now()
   WHERE id = p_exclusivity_id;

  PERFORM public.m1_auditar('commercial_exclusivity.operation_authorized',
    p_exclusivity_id, 'admin',
    pg_catalog.jsonb_build_object('status','operation_authorized',
                                  'gate', v_report->'checks'),
    pg_catalog.jsonb_build_object('status', v_excl.status),
    pg_catalog.jsonb_build_object('justification', p_justification));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
                                       'status', 'operation_authorized');
END;
$$;

-- Resumo comercial do Portal (manager NÃO vê financeiro).
CREATE FUNCTION public.get_my_company_commercial_summary(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
            'contractual_pool_cents', o.contractual_pool_cents,
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
$$;

REVOKE EXECUTE ON FUNCTION public.commercial_formation_gate_report(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.commercial_formation_gate_report(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.commercial_formation_gate_report(uuid)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.admin_authorize_commercial_operation(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_authorize_commercial_operation(uuid,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_authorize_commercial_operation(uuid,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_my_company_commercial_summary(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_company_commercial_summary(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_my_company_commercial_summary(uuid)
  TO authenticated, service_role;
