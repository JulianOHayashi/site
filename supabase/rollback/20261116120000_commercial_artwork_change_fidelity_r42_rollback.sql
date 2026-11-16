-- ===========================================================================
-- ROLLBACK da R4.2 (20261116120000) -> estado exato da R4.1 (20261113200000).
-- Recusado se já existir solicitação de alteração de arte ou intenção/pedido
-- vinculado a uma. As 6 funções alteradas voltam com o texto exato da R4.1
-- (pg_get_functiondef do banco R4.1); os CHECKs voltam à definição da R4.1;
-- a linha do manifesto R4.2 é retirada (ato do dono, com a trava do
-- manifesto religada na mesma transação), e o manifesto vigente volta a ser
-- o R4.1.
-- ===========================================================================
BEGIN;
DO $guarda$
BEGIN
  IF EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests)
     OR EXISTS (SELECT 1 FROM public.commercial_checkout_intents WHERE artwork_change_request_id IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders WHERE artwork_change_request_id IS NOT NULL) THEN
    RAISE EXCEPTION 'rollback_r42_recusado: ja ha solicitacao de alteracao de arte ou pedido vinculado';
  END IF;
END $guarda$;

CREATE OR REPLACE FUNCTION public.cci_validar_producao_bandeiras()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_status text;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_r      jsonb;
BEGIN
  SELECT status INTO v_status FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_status = 'prepared' THEN
    RAISE EXCEPTION 'pricing_rule_not_published: versao % ainda nao e vigente', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.pricing_rule_version IS NOT NULL AND NEW.pricing_rule_version >= 3 THEN
    SELECT * INTO v_sched FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = NEW.pricing_rule_version
       AND commercial_category = CASE WHEN NEW.niche_code = 'supermarket'
                                      THEN 'supermarket' ELSE 'common' END
       AND fidelized = NEW.fidelized;
  END IF;

  -- Economia sem produção de bandeiras: nenhum fato de produção é aceito.
  IF v_sched.new_flag_units IS NULL THEN
    NEW.flag_production_new_units    := NULL;
    NEW.flag_unit_reference_cents    := NULL;
    NEW.flag_production_charge_cents := NULL;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    RETURN NEW;
  END IF;

  IF NOT NEW.fidelized THEN
    NEW.flag_production_new_units    := v_sched.new_flag_units;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_sched.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    RETURN NEW;
  END IF;

  v_r := public.commercial_flag_reuse_resolution(
           NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF (v_r->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '%: %', v_r->>'reason', v_r->>'detail'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.flag_production_new_units    := 0;
  NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
  NEW.flag_production_charge_cents := 0;
  NEW.flag_reuse_set_id            := (v_r->>'flag_set_id')::uuid;
  NEW.flag_reuse_inspection_id     := (v_r->>'inspection_id')::uuid;
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.ceo_validar_producao_bandeiras()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_status text;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_i      public.commercial_checkout_intents%ROWTYPE;
  v_r      jsonb;
BEGIN
  SELECT status INTO v_status FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_status = 'prepared' THEN
    RAISE EXCEPTION 'pricing_rule_not_published: versao % ainda nao e vigente', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.pricing_rule_version IS NOT NULL AND NEW.pricing_rule_version >= 3 THEN
    SELECT * INTO v_sched FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = NEW.pricing_rule_version
       AND commercial_category = CASE WHEN NEW.niche_code = 'supermarket'
                                      THEN 'supermarket' ELSE 'common' END
       AND fidelized = NEW.fidelized;
  END IF;

  IF v_sched.new_flag_units IS NULL THEN
    NEW.flag_production_new_units    := NULL;
    NEW.flag_unit_reference_cents    := NULL;
    NEW.flag_production_charge_cents := NULL;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    RETURN NEW;
  END IF;

  -- Pedido vindo de intenção: CÓPIA do que a reserva congelou.
  IF NEW.checkout_intent_id IS NOT NULL THEN
    SELECT * INTO v_i FROM public.commercial_checkout_intents WHERE id = NEW.checkout_intent_id;
    IF NOT FOUND
       OR v_i.pricing_rule_version IS DISTINCT FROM NEW.pricing_rule_version
       OR v_i.fidelized IS DISTINCT FROM NEW.fidelized
       OR v_i.flag_production_new_units IS NULL THEN
      RAISE EXCEPTION 'flag_production_snapshot_divergente: intencao sem fatos de producao coerentes'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.flag_production_new_units    := v_i.flag_production_new_units;
    NEW.flag_unit_reference_cents    := v_i.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_i.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := v_i.flag_reuse_set_id;
    NEW.flag_reuse_inspection_id     := v_i.flag_reuse_inspection_id;
    RETURN NEW;
  END IF;

  -- Venda manual: mesma autoridade da intenção.
  IF NOT NEW.fidelized THEN
    NEW.flag_production_new_units    := v_sched.new_flag_units;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_sched.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    RETURN NEW;
  END IF;

  v_r := public.commercial_flag_reuse_resolution(
           NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF (v_r->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '%: %', v_r->>'reason', v_r->>'detail'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.flag_production_new_units    := 0;
  NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
  NEW.flag_production_charge_cents := 0;
  NEW.flag_reuse_set_id            := (v_r->>'flag_set_id')::uuid;
  NEW.flag_reuse_inspection_id     := (v_r->>'inspection_id')::uuid;
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.commercial_flag_facts_imutaveis()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF NEW.flag_production_new_units    IS DISTINCT FROM OLD.flag_production_new_units
  OR NEW.flag_unit_reference_cents    IS DISTINCT FROM OLD.flag_unit_reference_cents
  OR NEW.flag_production_charge_cents IS DISTINCT FROM OLD.flag_production_charge_cents
  OR NEW.flag_reuse_set_id            IS DISTINCT FROM OLD.flag_reuse_set_id
  OR NEW.flag_reuse_inspection_id     IS DISTINCT FROM OLD.flag_reuse_inspection_id THEN
    RAISE EXCEPTION 'pedido_imutavel: fatos de producao de bandeiras sao imutaveis (%, id=%)',
      TG_TABLE_NAME, OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $function$

;

CREATE OR REPLACE FUNCTION public.create_commercial_checkout_intent(p_company_id uuid, p_niche_code text, p_benefit_settlement_mode text, p_segment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg jsonb;
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
  v_seg      jsonb;
  v_reuso    jsonb;
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


  -- P0-1 PORTAO 1 de 4: elegibilidade do Acordo Mestre pela definicao UNICA.
  -- Falha CEDO: sem Mestre elegivel a empresa nao segura oportunidade escassa
  -- por 30 minutos nem gera aceite que jamais podera ser finalizado.
  v_eleg := public.m2_master_agreement_eligibility(p_company_id);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
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

  -- ---- posição × segmento: Supermercado sem segmento, Outros com segmento
  -- aprovado, substituto só em posição elegível, e o segmento ainda livre
  -- nesta exclusividade. Decidido aqui, nunca pelo navegador.
  v_seg := public.commercial_resolve_position_segment(
             p_niche_code, p_segment_id, v_excl, v_opp.id, true);
  IF (v_seg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_seg;
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
    IF v_viva.segment_id IS DISTINCT FROM p_segment_id THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'reservation_segment_mismatch',
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
               v_company.cnpj, v_company.uf, v_company.city, p_niche_code, p_segment_id);

  v_p := public.calculate_niche_contract_pricing(p_niche_code, v_fidel);
  IF (v_p->>'ok')::boolean IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_unavailable');
  END IF;

  -- Nicho INTEIRO. A quantidade vem da oportunidade e da regra de preço, que
  -- têm de concordar; divergência é defeito de dados, não venda parcial.
  IF (v_p->>'nominal_quantity')::int <> v_opp.contracted_quantity THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quantity_mismatch');
  END IF;

  -- ---- SF-v1.5: o preço fidelizado PRESSUPÕE reutilização das bandeiras.
  -- Sem conjunto do mesmo anunciante e da mesma identidade, com inspeção
  -- aprovando todas as peças e ainda não usada, não há reserva nem preço.
  -- Reposição sem política aprovada também não tem preço. Antes de tocar na
  -- oportunidade: nada fica reservado.
  IF v_p ? 'new_flag_units' AND v_fidel THEN
    v_reuso := public.commercial_flag_reuse_resolution(
                 p_company_id,
                 public.commercial_fidelity_identity(p_niche_code, p_segment_id));
    IF (v_reuso->>'ok')::boolean IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', v_reuso->>'reason', 'detail', v_reuso->>'detail');
    END IF;
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
     created_by, segment_id, segment_code_snapshot, segment_name_snapshot,
     segment_classification_snapshot)
  VALUES
    (p_company_id, p_niche_code, 'draft', (v_p->>'pricing_rule_version')::int,
     2, v_fidel, v_p->>'payment_method',
     p_benefit_settlement_mode, 'BRL', (v_p->>'nominal_quantity')::int,
     (v_p->>'economic_value_cents')::bigint, v_pool, v_bdflow,
     v_cash, v_bdflow + v_cash,
     v_opp.id, v_excl, v_region, v_ate,
     v_uid, (v_seg->>'segment_id')::uuid, v_seg->>'segment_code',
     v_seg->>'segment_name', v_seg->>'segment_classification')
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('commercial_checkout.reserved', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'opportunity_id', v_opp.id,
                                  'niche_code', p_niche_code,
                                  'segment_code', v_seg->>'segment_code',
                                  'segment_classification', v_seg->>'segment_classification',
                                  'reserved_until', v_ate));

  SELECT * INTO v_viva FROM public.commercial_checkout_intents WHERE id = v_id;
  RETURN public.cci_resposta_intencao(v_viva, false);
END;
$function$

;

CREATE OR REPLACE FUNCTION public.request_customization_image_path(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$

;

CREATE OR REPLACE FUNCTION public.register_customization_image(p_order_id uuid, p_storage_path text, p_mime_type text DEFAULT NULL::text, p_byte_size bigint DEFAULT NULL::bigint, p_checksum text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$

;

DROP INDEX public.ceo_alteracao_arte_unica_idx;
ALTER TABLE public.commercial_checkout_intents DROP CONSTRAINT cci_bandeiras_coerente;
ALTER TABLE public.commercial_exclusivity_orders DROP CONSTRAINT ceo_bandeiras_coerente;
ALTER TABLE public.commercial_checkout_intents DROP COLUMN artwork_change_request_id;
ALTER TABLE public.commercial_exclusivity_orders DROP COLUMN artwork_change_request_id;
ALTER TABLE public.commercial_checkout_intents ADD CONSTRAINT cci_bandeiras_coerente CHECK ((((flag_production_new_units IS NULL) AND (flag_unit_reference_cents IS NULL) AND (flag_production_charge_cents IS NULL) AND (flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)) OR ((NOT fidelized) AND (flag_production_new_units > 0) AND (flag_unit_reference_cents > 0) AND (flag_production_charge_cents = (flag_production_new_units * flag_unit_reference_cents)) AND (flag_production_charge_cents <= smallflags_main_fee_cents) AND (flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)) OR (fidelized AND (flag_production_new_units = 0) AND (flag_unit_reference_cents > 0) AND (flag_production_charge_cents = 0) AND (flag_reuse_set_id IS NOT NULL) AND (flag_reuse_inspection_id IS NOT NULL))));
ALTER TABLE public.commercial_exclusivity_orders ADD CONSTRAINT ceo_bandeiras_coerente CHECK ((((flag_production_new_units IS NULL) AND (flag_unit_reference_cents IS NULL) AND (flag_production_charge_cents IS NULL) AND (flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)) OR ((NOT fidelized) AND (flag_production_new_units > 0) AND (flag_unit_reference_cents > 0) AND (flag_production_charge_cents = (flag_production_new_units * flag_unit_reference_cents)) AND (flag_production_charge_cents <= smallflags_main_fee_cents) AND (flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)) OR (fidelized AND (flag_production_new_units = 0) AND (flag_unit_reference_cents > 0) AND (flag_production_charge_cents = 0) AND (flag_reuse_set_id IS NOT NULL) AND (flag_reuse_inspection_id IS NOT NULL))));

ALTER TABLE public.commercial_guard_manifests DISABLE TRIGGER cgm_protect;
DELETE FROM public.commercial_guard_manifests WHERE manifest_label = 'R4.2';
ALTER TABLE public.commercial_guard_manifests ENABLE TRIGGER cgm_protect;

DROP FUNCTION public.artwork_change_request_create(uuid, text, text, text);
DROP FUNCTION public.artwork_change_image_path(uuid);
DROP FUNCTION public.artwork_change_register_version(uuid, integer, text, text, text);
DROP FUNCTION public.artwork_change_submit(uuid, integer);
DROP FUNCTION public.artwork_change_accept_quote(uuid, integer, uuid, bigint);
DROP FUNCTION public.artwork_change_cancel(uuid, integer, text);
DROP FUNCTION public.admin_artwork_change_start_review(uuid, integer);
DROP FUNCTION public.admin_artwork_change_register_quote(uuid, integer, text, text, text, text, integer, bigint, bigint, bigint);
DROP FUNCTION public.admin_artwork_change_approve_exception(uuid, integer, text, text);
DROP FUNCTION public.admin_artwork_change_authorize_production(uuid, integer);
DROP FUNCTION public.admin_artwork_change_reject(uuid, integer, text);
DROP FUNCTION public.artwork_change_requests_for_order(uuid);
DROP FUNCTION public.commercial_artwork_change_for_renewal(uuid, text);
DROP FUNCTION public.commercial_order_artwork_locked(uuid);
DROP FUNCTION public.commercial_artwork_change_gate(uuid, integer, text[], text[]);
DROP FUNCTION public.commercial_artwork_change_event(uuid, text, text, text, text, jsonb);
DROP FUNCTION public.commercial_artwork_change_actor(uuid);
DROP TABLE public.commercial_artwork_change_events;
DROP TABLE public.commercial_artwork_change_quotes;
DROP TABLE public.commercial_artwork_change_versions;
DROP TABLE public.commercial_artwork_change_requests;
DROP FUNCTION public.commercial_artwork_change_requests_protect();
DROP FUNCTION public.commercial_artwork_change_append_only();
COMMIT;
