CREATE OR REPLACE FUNCTION public.owner_set_manager_status(
  p_member_id uuid,
  p_action text,
  p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_m public.site_company_members%ROWTYPE;
BEGIN
  IF p_action NOT IN ('suspend','reactivate','revoke') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_action');
  END IF;

  SELECT * INTO v_m
    FROM public.site_company_members
   WHERE id = p_member_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT (public.m2_is_company_owner(v_m.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  IF v_m.role <> 'partner_manager' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'manager_only');
  END IF;

  IF p_action = 'revoke' THEN
    IF v_m.status = 'revoked' THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true);
    END IF;

    IF p_reason IS NULL OR pg_catalog.length(pg_catalog.btrim(p_reason)) < 3 THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reason_required');
    END IF;

    UPDATE public.site_company_members
       SET status = 'revoked',
           revoked_at = pg_catalog.now(),
           revocation_reason = pg_catalog.btrim(p_reason)
     WHERE id = p_member_id;

    UPDATE public.site_member_unit_bindings
       SET status = 'revoked',
           revoked_at = pg_catalog.now(),
           revocation_reason = 'manager revogado'
     WHERE member_id = p_member_id
       AND status = 'active';

    UPDATE public.site_manager_invite_tokens t
       SET invalidated_at = pg_catalog.now()
     WHERE t.consumed_at IS NULL
       AND t.invalidated_at IS NULL
       AND EXISTS (
         SELECT 1
           FROM public.site_manager_invites i
          WHERE i.id = t.invite_id
            AND i.company_id = v_m.company_id
            AND i.status = 'pending'
            AND pg_catalog.lower(pg_catalog.btrim(i.email))
                = pg_catalog.lower(pg_catalog.btrim(v_m.email))
       );

    UPDATE public.site_manager_invites i
       SET status = 'revoked',
           revoked_at = pg_catalog.now()
     WHERE i.company_id = v_m.company_id
       AND i.status = 'pending'
       AND pg_catalog.lower(pg_catalog.btrim(i.email))
           = pg_catalog.lower(pg_catalog.btrim(v_m.email));

    UPDATE public.notification_events e
       SET status = 'cancelled',
           updated_at = pg_catalog.now()
     WHERE e.template_key = 'manager_invite'
       AND e.status IN ('pending','scheduled','sending')
       AND EXISTS (
         SELECT 1
           FROM public.site_manager_invites i
          WHERE i.id::text = e.template_data->>'invite_id'
            AND i.company_id = v_m.company_id
            AND i.status = 'revoked'
            AND pg_catalog.lower(pg_catalog.btrim(i.email))
                = pg_catalog.lower(pg_catalog.btrim(v_m.email))
       );

  ELSIF p_action = 'suspend' THEN
    IF v_m.status <> 'active' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_transition');
    END IF;
    UPDATE public.site_company_members SET status = 'suspended' WHERE id = p_member_id;
  ELSE
    IF v_m.status <> 'suspended' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_transition');
    END IF;
    UPDATE public.site_company_members SET status = 'active' WHERE id = p_member_id;
  END IF;

  PERFORM public.m1_auditar(
    'company_member.status_changed',
    p_member_id,
    'owner',
    pg_catalog.jsonb_build_object('action', p_action),
    pg_catalog.jsonb_build_object('status', v_m.status),
    pg_catalog.jsonb_build_object('reason', p_reason)
  );

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false);
END;
$function$;

UPDATE public.site_manager_invite_tokens t
   SET invalidated_at = pg_catalog.now()
 WHERE t.consumed_at IS NULL
   AND t.invalidated_at IS NULL
   AND EXISTS (
     SELECT 1
       FROM public.site_manager_invites i
       JOIN public.site_company_members m
         ON m.company_id = i.company_id
        AND pg_catalog.lower(pg_catalog.btrim(m.email))
            = pg_catalog.lower(pg_catalog.btrim(i.email))
      WHERE i.id = t.invite_id
        AND i.status = 'pending'
        AND m.role = 'partner_manager'
        AND m.status = 'revoked'
   );

UPDATE public.site_manager_invites i
   SET status = 'revoked',
       revoked_at = pg_catalog.now()
 WHERE i.status = 'pending'
   AND EXISTS (
     SELECT 1
       FROM public.site_company_members m
      WHERE m.company_id = i.company_id
        AND m.role = 'partner_manager'
        AND m.status = 'revoked'
        AND pg_catalog.lower(pg_catalog.btrim(m.email))
            = pg_catalog.lower(pg_catalog.btrim(i.email))
   );

UPDATE public.notification_events e
   SET status = 'cancelled',
       updated_at = pg_catalog.now()
 WHERE e.template_key = 'manager_invite'
   AND e.status IN ('pending','scheduled','sending')
   AND EXISTS (
     SELECT 1
       FROM public.site_manager_invites i
      WHERE i.id::text = e.template_data->>'invite_id'
        AND i.status = 'revoked'
   );
