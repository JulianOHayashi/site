CREATE OR REPLACE FUNCTION public.owner_create_manager_invite(
  p_company_id uuid,
  p_email text,
  p_full_name text,
  p_unit_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_owner_member uuid;
  v_email text := pg_catalog.lower(pg_catalog.btrim(p_email));
  v_id uuid;
BEGIN
  SELECT m.id INTO v_owner_member
    FROM public.site_company_members m
   WHERE m.company_id = p_company_id
     AND m.auth_user_id = auth.uid()
     AND m.role = 'partner_owner'
     AND m.status = 'active';

  IF v_owner_member IS NULL THEN
    IF NOT public.is_site_admin() THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
    END IF;
    SELECT m.id INTO v_owner_member
      FROM public.site_company_members m
     WHERE m.company_id = p_company_id
       AND m.role = 'partner_owner'
       AND m.status = 'active';
    IF v_owner_member IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_without_owner');
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.site_partner_companies
     WHERE id = p_company_id
       AND status = 'active'
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;

  IF p_unit_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
      FROM public.site_partner_units
     WHERE id = p_unit_id
       AND company_id = p_company_id
       AND status = 'active'
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_unit');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.site_company_members m
     WHERE m.company_id = p_company_id
       AND m.role = 'partner_manager'
       AND m.status = 'revoked'
       AND pg_catalog.lower(pg_catalog.btrim(m.email)) = v_email
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'access_revoked');
  END IF;

  UPDATE public.site_manager_invites
     SET status = 'superseded'
   WHERE company_id = p_company_id
     AND email = v_email
     AND status = 'pending';

  UPDATE public.site_manager_invite_tokens t
     SET invalidated_at = pg_catalog.now()
    FROM public.site_manager_invites i
   WHERE t.invite_id = i.id
     AND i.status = 'superseded'
     AND i.company_id = p_company_id
     AND i.email = v_email
     AND t.consumed_at IS NULL
     AND t.invalidated_at IS NULL;

  BEGIN
    INSERT INTO public.site_manager_invites
      (company_id, unit_id, email, full_name, invited_by_member_id)
    VALUES
      (p_company_id, p_unit_id, v_email, pg_catalog.btrim(p_full_name), v_owner_member)
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN check_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
  END;

  PERFORM public.m1_enfileirar_email(
    v_email,
    'manager_invite',
    pg_catalog.jsonb_build_object(
      'invite_id', v_id,
      'purpose', 'manager_invite',
      'company_id', p_company_id
    ),
    NULL,
    'smi:' || v_id::text
  );

  PERFORM public.m1_auditar(
    'manager_invite.created',
    v_id,
    'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id, 'unit_id', p_unit_id)
  );

  RETURN pg_catalog.jsonb_build_object('ok', true, 'invite_id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_manager_invite(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_tok public.site_manager_invite_tokens%ROWTYPE;
  v_inv public.site_manager_invites%ROWTYPE;
  v_email text;
  v_member uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF p_token IS NULL OR pg_catalog.length(pg_catalog.btrim(p_token)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  SELECT * INTO v_tok
    FROM public.site_manager_invite_tokens
   WHERE token_hash = public.m1_token_hash(pg_catalog.btrim(p_token))
     AND purpose = 'manager_invite'
   FOR UPDATE;

  IF NOT FOUND OR v_tok.consumed_at IS NOT NULL OR v_tok.invalidated_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  IF v_tok.expires_at <= pg_catalog.now() THEN
    UPDATE public.site_manager_invite_tokens
       SET invalidated_at = pg_catalog.now()
     WHERE id = v_tok.id;
    UPDATE public.site_manager_invites
       SET status = 'expired'
     WHERE id = v_tok.invite_id
       AND status = 'pending';
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;

  SELECT * INTO v_inv
    FROM public.site_manager_invites
   WHERE id = v_tok.invite_id
   FOR UPDATE;

  IF v_inv.status <> 'pending' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.site_partner_companies
     WHERE id = v_inv.company_id
       AND status = 'active'
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;

  SELECT pg_catalog.lower(pg_catalog.btrim(u.email))
    INTO v_email
    FROM auth.users u
   WHERE u.id = v_uid;

  IF v_email IS DISTINCT FROM v_inv.email THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'email_mismatch');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.site_company_members
     WHERE company_id = v_inv.company_id
       AND auth_user_id = v_uid
       AND status = 'revoked'
  ) THEN
    UPDATE public.site_manager_invite_tokens
       SET invalidated_at = pg_catalog.now()
     WHERE id = v_tok.id;
    UPDATE public.site_manager_invites
       SET status = 'revoked',
           revoked_at = coalesce(revoked_at, pg_catalog.now())
     WHERE id = v_inv.id
       AND status = 'pending';
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'access_revoked');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.site_company_members
     WHERE company_id = v_inv.company_id
       AND auth_user_id = v_uid
       AND status IN ('active','suspended')
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_member');
  END IF;

  INSERT INTO public.site_company_members
    (company_id, auth_user_id, role, status, full_name, email, source)
  VALUES
    (v_inv.company_id, v_uid, 'partner_manager', 'active',
     v_inv.full_name, v_inv.email, 'manager_invite')
  RETURNING id INTO v_member;

  IF v_inv.unit_id IS NOT NULL THEN
    INSERT INTO public.site_member_unit_bindings (member_id, unit_id)
    VALUES (v_member, v_inv.unit_id);
  END IF;

  UPDATE public.site_manager_invite_tokens
     SET consumed_at = pg_catalog.now()
   WHERE id = v_tok.id;

  UPDATE public.site_manager_invites
     SET status = 'accepted',
         accepted_member_id = v_member,
         accepted_at = pg_catalog.now()
   WHERE id = v_inv.id;

  PERFORM public.m1_auditar(
    'manager_invite.accepted',
    v_inv.id,
    'partner_manager',
    pg_catalog.jsonb_build_object(
      'member_id', v_member,
      'company_id', v_inv.company_id,
      'unit_id', v_inv.unit_id
    )
  );

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'member_id', v_member,
    'company_id', v_inv.company_id
  );
END;
$function$;
