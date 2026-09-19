CREATE OR REPLACE FUNCTION public.join_my_commercial_future_queue(
  p_company_id uuid,
  p_niche_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION public.join_my_commercial_future_queue(uuid,text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.join_my_commercial_future_queue(uuid,text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_commercial_future_interest(
  p_company_id uuid,
  p_niche_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_commercial_future_interest(uuid,text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_commercial_future_interest(uuid,text)
  TO authenticated;
