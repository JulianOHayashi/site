-- ============================================================================
-- CONSULTAS DE PAGAMENTO: resolução por identificador do provedor e leitura
-- de estado pelo titular.
--
-- Duas funções estreitas que faltavam para os endpoints HTTP:
--
--   prov_find_commercial_payment_by_provider_order  o webhook precisa
--     traduzir um identificador do provedor no pagamento local ANTES de
--     conciliar. Devolve só o id local — nada de valor, estado ou empresa,
--     porque quem chama ainda não provou nada.
--
--   get_my_commercial_payment_status  o navegador do titular precisa saber
--     em que pé está o próprio pagamento, sem tocar a API do provedor e sem
--     credencial privilegiada.
--
-- ADITIVA. Nenhuma das 34 migrations anteriores é editada.
-- ============================================================================

CREATE FUNCTION public.prov_find_commercial_payment_by_provider_order(
  p_provider_order_id text
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_id uuid;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF p_provider_order_id IS NULL OR pg_catalog.btrim(p_provider_order_id) = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'missing_identifier');
  END IF;

  SELECT id INTO v_id FROM public.commercial_payments
   WHERE provider = 'pagarme'
     AND (provider_order_id = p_provider_order_id
          OR provider_charge_id = p_provider_order_id
          OR provider_payment_link_id = p_provider_order_id)
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  -- Somente o id local. Nada do estado comercial atravessa antes da
  -- conciliação — quem chamou ainda não provou coisa alguma.
  RETURN pg_catalog.jsonb_build_object('ok', true, 'payment_id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prov_find_commercial_payment_by_provider_order(text)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_find_commercial_payment_by_provider_order(text)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_find_commercial_payment_by_provider_order(text)
  TO service_role;

-- ----------------------------------------------------------------------------
-- Estado do pagamento para o titular
--
-- Só os campos que a tela precisa. Nenhum identificador do provedor, nenhuma
-- credencial, nenhum dado de outra empresa. Os estados são os canônicos da
-- migration 34, sem apelido novo.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.get_my_commercial_payment_status(p_payment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_p public.commercial_payments%ROWTYPE;
  v_o public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_p FROM public.commercial_payments WHERE id = p_payment_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders
   WHERE id = v_p.commercial_order_id;
  IF NOT public.m2_is_company_owner(v_o.company_id) THEN
    -- Motivo genérico: confirmar existência a quem não é titular entregaria
    -- um oráculo de enumeração.
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'payment_id', v_p.id,
    'status', v_p.status,
    'payment_method', v_p.payment_method,
    'amount_cents', v_p.amount_cents,
    'installments', v_p.installments,
    'expires_at', v_p.expires_at,
    'paid_at', v_p.paid_at,
    -- Estados terminais: a tela para de consultar aqui.
    'terminal', v_p.status IN ('paid','expired','cancelled','failed','late_unreconciled'),
    'order_payment_status', v_o.payment_status);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_commercial_payment_status(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_commercial_payment_status(uuid)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.get_my_commercial_payment_status(uuid)
  TO authenticated;
