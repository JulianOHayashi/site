-- Commercial future demand foundation.
-- Territorial waitlist, pre-purchase interest and later-sales waitlist.
-- Pre-purchase alone creates no contract/reservation/payment/fidelity.
-- Sales-waitlist invite TTL is fixed at 48h.
-- Sales queue position is immutable and sequential per region+niche.

CREATE TABLE public.commercial_territorial_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cnpj text NOT NULL,
  company_name text NOT NULL,
  responsible_name text NOT NULL,
  email text NOT NULL,
  phone text,
  uf text NOT NULL,
  city text NOT NULL,
  city_key text NOT NULL,
  niche_code text NOT NULL REFERENCES public.commercial_niches(code),
  status text NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting','contacted','converted','cancelled')),
  source text NOT NULL DEFAULT 'site',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX commercial_territorial_waitlist_active_uniq
  ON public.commercial_territorial_waitlist
    (cnpj, uf, city_key, niche_code)
  WHERE status IN ('waiting','contacted');

CREATE TABLE public.commercial_preorders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.site_partner_companies(id),
  region_id uuid NOT NULL REFERENCES public.commercial_regions(id),
  niche_code text NOT NULL REFERENCES public.commercial_niches(code),
  target_exclusivity_id uuid NOT NULL REFERENCES public.commercial_exclusivities(id),
  status text NOT NULL DEFAULT 'waiting'
    CHECK (status IN (
      'waiting',
      'reservation_offered',
      'reservation_accepted',
      'reservation_expired',
      'converted',
      'declined',
      'cancelled'
    )),
  source text NOT NULL DEFAULT 'site',
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX commercial_preorders_slot_active_uniq
  ON public.commercial_preorders (target_exclusivity_id, niche_code)
  WHERE status IN ('waiting','reservation_offered','reservation_accepted');

CREATE UNIQUE INDEX commercial_preorders_company_active_uniq
  ON public.commercial_preorders (target_exclusivity_id, company_id)
  WHERE status IN ('waiting','reservation_offered','reservation_accepted');

CREATE TABLE public.commercial_sales_waitlist_counters (
  region_id uuid NOT NULL REFERENCES public.commercial_regions(id),
  niche_code text NOT NULL REFERENCES public.commercial_niches(code),
  next_position bigint NOT NULL CHECK (next_position >= 2),
  PRIMARY KEY (region_id, niche_code)
);

CREATE TABLE public.commercial_sales_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.site_partner_companies(id),
  region_id uuid NOT NULL REFERENCES public.commercial_regions(id),
  niche_code text NOT NULL REFERENCES public.commercial_niches(code),
  first_possible_exclusivity_sequence integer NOT NULL
    CHECK (first_possible_exclusivity_sequence > 0),
  position bigint NOT NULL CHECK (position > 0),
  status text NOT NULL DEFAULT 'waiting'
    CHECK (status IN (
      'waiting',
      'contact_pending',
      'invited',
      'reservation_offered',
      'reservation_accepted',
      'reservation_expired',
      'converted',
      'declined',
      'cancelled'
    )),
  confirmed_interest_at timestamptz,
  source text NOT NULL DEFAULT 'site',
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (region_id, niche_code, position)
);

CREATE UNIQUE INDEX commercial_sales_waitlist_active_company_uniq
  ON public.commercial_sales_waitlist (company_id, region_id, niche_code)
  WHERE status IN (
    'waiting','contact_pending','invited',
    'reservation_offered','reservation_accepted'
  );

CREATE TABLE public.commercial_sales_waitlist_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  waitlist_id uuid NOT NULL REFERENCES public.commercial_sales_waitlist(id),
  status text NOT NULL DEFAULT 'issued'
    CHECK (status IN ('issued','accepted','expired','declined','cancelled')),
  issued_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  declined_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX commercial_sales_waitlist_invite_active_uniq
  ON public.commercial_sales_waitlist_invites (waitlist_id)
  WHERE status = 'issued';

CREATE OR REPLACE FUNCTION public.commercial_waitlist_position_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF NEW.position IS DISTINCT FROM OLD.position THEN
    RAISE EXCEPTION 'commercial waitlist position is immutable';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_commercial_waitlist_position_immutable
BEFORE UPDATE OF position ON public.commercial_sales_waitlist
FOR EACH ROW EXECUTE FUNCTION public.commercial_waitlist_position_immutable();

CREATE OR REPLACE FUNCTION public.commercial_waitlist_invite_fixed_ttl()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  NEW.issued_at := coalesce(NEW.issued_at, pg_catalog.now());
  NEW.expires_at := NEW.issued_at + interval '48 hours';
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_commercial_waitlist_invite_fixed_ttl
BEFORE INSERT ON public.commercial_sales_waitlist_invites
FOR EACH ROW EXECUTE FUNCTION public.commercial_waitlist_invite_fixed_ttl();

ALTER TABLE public.commercial_territorial_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_preorders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_sales_waitlist_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_sales_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_sales_waitlist_invites ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.commercial_territorial_waitlist FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.commercial_preorders FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.commercial_sales_waitlist_counters FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.commercial_sales_waitlist FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.commercial_sales_waitlist_invites FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.commercial_preorders TO authenticated;
GRANT SELECT ON public.commercial_sales_waitlist TO authenticated;
GRANT SELECT ON public.commercial_sales_waitlist_invites TO authenticated;

CREATE POLICY commercial_preorders_owner_select
ON public.commercial_preorders
FOR SELECT TO authenticated
USING (
  public.is_site_admin()
  OR public.m2_is_company_owner(company_id)
);

CREATE POLICY commercial_sales_waitlist_owner_select
ON public.commercial_sales_waitlist
FOR SELECT TO authenticated
USING (
  public.is_site_admin()
  OR public.m2_is_company_owner(company_id)
);

CREATE POLICY commercial_sales_waitlist_invites_owner_select
ON public.commercial_sales_waitlist_invites
FOR SELECT TO authenticated
USING (
  public.is_site_admin()
  OR EXISTS (
    SELECT 1
      FROM public.commercial_sales_waitlist w
     WHERE w.id = commercial_sales_waitlist_invites.waitlist_id
       AND public.m2_is_company_owner(w.company_id)
  )
);

CREATE OR REPLACE FUNCTION public.register_territorial_waitlist_interest(
  p_cnpj text,
  p_company_name text,
  p_responsible_name text,
  p_email text,
  p_phone text,
  p_uf text,
  p_city text,
  p_niche_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_cnpj text := pg_catalog.regexp_replace(coalesce(p_cnpj,''), '[^0-9]', '', 'g');
  v_company text := pg_catalog.btrim(coalesce(p_company_name,''));
  v_responsible text := pg_catalog.btrim(coalesce(p_responsible_name,''));
  v_email text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_email,'')));
  v_phone text := nullif(pg_catalog.btrim(coalesce(p_phone,'')), '');
  v_uf text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_uf,'')));
  v_city text := pg_catalog.btrim(coalesce(p_city,''));
  v_city_key text;
  v_region jsonb;
  v_existing uuid;
  v_id uuid;
BEGIN
  IF NOT public.m1_cnpj_valido(v_cnpj) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_cnpj');
  END IF;
  IF pg_catalog.length(v_company) < 2 OR pg_catalog.length(v_company) > 160 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_company_name');
  END IF;
  IF pg_catalog.length(v_responsible) < 2 OR pg_catalog.length(v_responsible) > 160 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_responsible_name');
  END IF;
  IF pg_catalog.length(v_email) < 5 OR pg_catalog.length(v_email) > 254
     OR pg_catalog.strpos(v_email, '@') <= 1 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_email');
  END IF;
  IF NOT public.commercial_is_valid_uf(v_uf) OR v_city = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_location');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.commercial_niches n
     WHERE n.code = p_niche_code AND n.is_active
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_niche');
  END IF;

  v_region := public.resolve_commercial_region(v_uf, v_city);
  IF coalesce((v_region->>'region_available')::boolean, false) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'region_already_active');
  END IF;

  v_city_key := public.commercial_city_key(v_city);
  IF v_city_key IS NULL OR v_city_key = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_location');
  END IF;

  SELECT w.id INTO v_existing
    FROM public.commercial_territorial_waitlist w
   WHERE w.cnpj = v_cnpj
     AND w.uf = v_uf
     AND w.city_key = v_city_key
     AND w.niche_code = p_niche_code
     AND w.status IN ('waiting','contacted')
   LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'already', true, 'waitlist_id', v_existing);
  END IF;

  INSERT INTO public.commercial_territorial_waitlist
    (cnpj, company_name, responsible_name, email, phone,
     uf, city, city_key, niche_code, status, source)
  VALUES
    (v_cnpj, v_company, v_responsible, v_email, v_phone,
     v_uf, v_city, v_city_key, p_niche_code, 'waiting', 'site')
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar(
    'commercial_territorial_waitlist.joined',
    v_id,
    'visitor',
    pg_catalog.jsonb_build_object(
      'uf', v_uf, 'city_key', v_city_key, 'niche_code', p_niche_code,
      'status', 'waiting'),
    NULL::jsonb,
    pg_catalog.jsonb_build_object('source','site')
  );

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'waitlist_id', v_id, 'status', 'waiting');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.register_territorial_waitlist_interest(
  text,text,text,text,text,text,text,text
) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.register_territorial_waitlist_interest(
  text,text,text,text,text,text,text,text
) TO anon, authenticated;

COMMENT ON TABLE public.commercial_preorders IS
  'Pre-purchase interest for a specific next commercial exclusivity. Registration alone creates no contract, reservation, payment or fidelity.';
COMMENT ON COLUMN public.commercial_sales_waitlist.position IS
  'Immutable historical queue position assigned sequentially per region+niche.';
COMMENT ON COLUMN public.commercial_sales_waitlist_invites.expires_at IS
  'Always issued_at + 48 hours by trigger.';
