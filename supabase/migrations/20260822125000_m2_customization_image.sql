-- ============================================================================
-- M2 / R7 — Imagem de personalização OBRIGATÓRIA, vinculada ao pedido
--
-- Requisito de lançamento: ao menos uma referência de imagem privada,
-- fornecida pelo parceiro, precisa estar vinculada ao Pedido de Exclusividade
-- ANTES de a formação ser autorizada (o gate do R9 exige).
--
-- Segurança de Storage seguindo o padrão canônico do M1:
--   * bucket PRIVADO e dedicado;
--   * caminho DERIVADO NO SERVIDOR (order_id/...) — o navegador não escolhe
--     caminho arbitrário;
--   * o objeto precisa existir no Storage e pertencer a quem registra;
--   * MIME e tamanho AUTORITATIVOS vêm do Storage quando disponíveis;
--   * metadados append-only, com versão corrente e histórico;
--   * sem superfície de DELETE direto para o cliente (nada de corrida).
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'partner-customization-images',
  'partner-customization-images',
  false,
  10485760,                                   -- 10 MiB
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE public.commercial_order_customization_images (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES public.commercial_exclusivity_orders(id),
  storage_bucket text        NOT NULL DEFAULT 'partner-customization-images',
  storage_path   text        NOT NULL,
  mime_type      text        NOT NULL,
  byte_size      bigint      NOT NULL,
  checksum       text,
  is_current     boolean     NOT NULL DEFAULT true,
  status         text        NOT NULL DEFAULT 'active',
  registered_by  uuid        NOT NULL,
  registered_at  timestamptz NOT NULL DEFAULT now(),
  replaced_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT coci_bucket_fixo
    CHECK (storage_bucket = 'partner-customization-images'),
  CONSTRAINT coci_path_do_pedido
    CHECK (storage_path LIKE (order_id::text || '/%')),
  CONSTRAINT coci_mime_allowed
    CHECK (mime_type = ANY (ARRAY['image/jpeg','image/png','image/webp'])),
  CONSTRAINT coci_tamanho_valido
    CHECK (byte_size > 0 AND byte_size <= 10485760),
  CONSTRAINT coci_status_allowed
    CHECK (status = ANY (ARRAY['active','replaced'])),
  CONSTRAINT coci_corrente_coerente
    CHECK ((is_current AND status = 'active' AND replaced_at IS NULL)
           OR (NOT is_current AND status = 'replaced' AND replaced_at IS NOT NULL))
);

-- Uma imagem CORRENTE por pedido; o histórico permanece.
CREATE UNIQUE INDEX coci_corrente_idx
  ON public.commercial_order_customization_images (order_id) WHERE is_current;
CREATE UNIQUE INDEX coci_path_idx
  ON public.commercial_order_customization_images (storage_bucket, storage_path);

-- Append-only: metadado registrado não é editado nem excluído; só é
-- SUBSTITUÍDO pela RPC, que marca o anterior como replaced.
CREATE FUNCTION public.m2_customization_images_protect()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'imagem_imutavel: metadado de imagem nao pode ser excluido (id=%).', OLD.id;
  END IF;
  IF NEW.order_id     IS DISTINCT FROM OLD.order_id
  OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
  OR NEW.storage_bucket IS DISTINCT FROM OLD.storage_bucket
  OR NEW.mime_type    IS DISTINCT FROM OLD.mime_type
  OR NEW.byte_size    IS DISTINCT FROM OLD.byte_size
  OR NEW.checksum     IS DISTINCT FROM OLD.checksum
  OR NEW.registered_by IS DISTINCT FROM OLD.registered_by
  OR NEW.registered_at IS DISTINCT FROM OLD.registered_at THEN
    RAISE EXCEPTION 'imagem_imutavel: evidencia da imagem e imutavel (id=%). Registre uma nova versao.', OLD.id;
  END IF;
  -- Só a transição corrente -> substituída é permitida.
  IF OLD.is_current = false AND NEW.is_current = true THEN
    RAISE EXCEPTION 'imagem_imutavel: versao substituida nao volta a ser corrente (id=%).', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_coci_protect
  BEFORE UPDATE OR DELETE ON public.commercial_order_customization_images
  FOR EACH ROW EXECUTE FUNCTION public.m2_customization_images_protect();

ALTER TABLE public.commercial_order_customization_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY coci_owner_select ON public.commercial_order_customization_images
  FOR SELECT TO authenticated
  USING (public.is_site_admin()
         OR EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                     WHERE o.id = order_id
                       AND public.m2_is_company_owner(o.company_id)));

REVOKE ALL ON TABLE public.commercial_order_customization_images
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_order_customization_images TO authenticated;

-- ----------------------------------------------------------------------------
-- Policies de Storage: bucket privado, caminho preso ao pedido do parceiro.
-- SEM policy de DELETE para o titular (mesma decisão do M1C3).
-- anon não recebe policy alguma.
-- ----------------------------------------------------------------------------
CREATE POLICY m2_custom_img_owner_select
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'partner-customization-images'
    AND EXISTS (
      SELECT 1 FROM public.commercial_exclusivity_orders o
       WHERE o.id::text = split_part(storage.objects.name, '/', 1)
         AND public.m2_is_company_owner(o.company_id)));

CREATE POLICY m2_custom_img_owner_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'partner-customization-images'
    AND EXISTS (
      SELECT 1 FROM public.commercial_exclusivity_orders o
       WHERE o.id::text = split_part(storage.objects.name, '/', 1)
         AND public.m2_is_company_owner(o.company_id)));

CREATE POLICY m2_custom_img_admin_select
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'partner-customization-images' AND public.is_site_admin());

-- ----------------------------------------------------------------------------
-- Caminho DERIVADO NO SERVIDOR: o cliente nunca escolhe o path.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.request_customization_image_path(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_ord public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_ord FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_ord.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_ord.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'bucket', 'partner-customization-images',
    -- Sempre um caminho NOVO: reenvio nunca sobrescreve objeto anterior.
    'storage_path', p_order_id::text || '/' ||
                    pg_catalog.replace(gen_random_uuid()::text, '-', ''));
END;
$$;

-- ----------------------------------------------------------------------------
-- Registro do metadado: valida o objeto real e usa MIME/tamanho do Storage.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.register_customization_image(
  p_order_id     uuid,
  p_storage_path text,
  p_mime_type    text DEFAULT NULL,
  p_byte_size    bigint DEFAULT NULL,
  p_checksum     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_ord  public.commercial_exclusivity_orders%ROWTYPE;
  v_obj  storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
  v_id   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_ord FROM public.commercial_exclusivity_orders
   WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_ord.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_ord.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;

  -- O caminho é preso ao pedido: nada de path arbitrário do navegador.
  IF p_storage_path IS NULL OR p_storage_path NOT LIKE (p_order_id::text || '/%') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_path');
  END IF;

  -- O objeto precisa EXISTIR no Storage.
  SELECT * INTO v_obj FROM storage.objects o
   WHERE o.bucket_id = 'partner-customization-images' AND o.name = p_storage_path;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_found');
  END IF;
  IF v_obj.owner IS NOT NULL AND v_obj.owner <> v_uid THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_owned');
  END IF;

  -- MIME e tamanho AUTORITATIVOS do Storage; o cliente é apenas fallback.
  v_size := coalesce((v_obj.metadata->>'size')::bigint, p_byte_size);
  v_mime := coalesce(nullif(v_obj.metadata->>'mimetype',''), p_mime_type);
  IF v_size IS NULL OR v_mime IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_metadata');
  END IF;
  IF v_mime NOT IN ('image/jpeg','image/png','image/webp') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_mime');
  END IF;
  IF v_size <= 0 OR v_size > 10485760 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_size');
  END IF;

  -- Substituição: a versão anterior vira histórico (append-only).
  UPDATE public.commercial_order_customization_images
     SET is_current = false, status = 'replaced', replaced_at = pg_catalog.now()
   WHERE order_id = p_order_id AND is_current;

  INSERT INTO public.commercial_order_customization_images
    (order_id, storage_path, mime_type, byte_size, checksum, registered_by)
  VALUES (p_order_id, p_storage_path, v_mime, v_size,
          nullif(pg_catalog.btrim(coalesce(p_checksum,'')), ''), v_uid)
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('order_customization_image.registered', p_order_id, 'owner',
    pg_catalog.jsonb_build_object('image_id', v_id, 'mime_type', v_mime,
                                  'byte_size', v_size));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'image_id', v_id,
                                       'mime_type', v_mime, 'byte_size', v_size);
END;
$$;

-- Predicado usado pelo gate do R9.
CREATE FUNCTION public.order_has_customization_image(p_order_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.commercial_order_customization_images i
     WHERE i.order_id = p_order_id AND i.is_current AND i.status = 'active');
$$;

REVOKE EXECUTE ON FUNCTION public.request_customization_image_path(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.request_customization_image_path(uuid) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.request_customization_image_path(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.register_customization_image(uuid,text,text,bigint,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_customization_image(uuid,text,text,bigint,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.register_customization_image(uuid,text,text,bigint,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.order_has_customization_image(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.order_has_customization_image(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.order_has_customization_image(uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.m2_customization_images_protect() FROM PUBLIC;
