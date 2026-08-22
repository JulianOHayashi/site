-- ============================================================================
-- M2 / R3 — Contexto POSITIVO de parceiro
--
-- O PortalGuard canônico do M1 já é fail-closed e só libera diante de
-- `parceiro_autorizado`. Esta migration fornece a única fonte capaz de
-- produzir esse veredito: um vínculo DURÁVEL ativo em empresa ativa.
--
-- Nada aqui altera o guard, a candidatura canônica ou o fluxo de onboarding.
-- Ausência de vínculo NUNCA é autorização.
-- ============================================================================

CREATE FUNCTION public.get_my_partner_context()
RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_memberships jsonb;
BEGIN
  -- Fail-closed: sem sessão não existe contexto algum.
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'authorized', false, 'memberships', '[]'::jsonb);
  END IF;

  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'company_id',   c.id,
             'trade_name',   coalesce(c.trade_name, c.legal_name),
             'company_status', c.status,
             'member_id',    m.id,
             'role',         m.role,
             'member_status', m.status,
             'city',         c.city,
             'uf',           c.uf)
           ORDER BY coalesce(c.trade_name, c.legal_name)), '[]'::jsonb)
    INTO v_memberships
    FROM public.site_company_members m
    JOIN public.site_partner_companies c ON c.id = m.company_id
   WHERE m.auth_user_id = v_uid
     AND m.status = 'active'
     AND c.status = 'active';

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    -- Autorização POSITIVA: exige vínculo ativo em empresa ativa.
    'authorized', pg_catalog.jsonb_array_length(v_memberships) > 0,
    'memberships', v_memberships);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_partner_context() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_partner_context() FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_my_partner_context() FROM service_role;
GRANT  EXECUTE ON FUNCTION public.get_my_partner_context() TO authenticated;

COMMENT ON FUNCTION public.get_my_partner_context() IS
  'M2: única fonte de `parceiro_autorizado`. Exige vínculo durável ativo em '
  'empresa ativa; ausência de vínculo nunca autoriza.';
