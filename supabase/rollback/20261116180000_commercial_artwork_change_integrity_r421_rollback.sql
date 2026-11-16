-- ===========================================================================
-- ROLLBACK da R4.2.1 (20261116180000) -> estado exato da R4.2 (20261116120000).
-- Recusado se já existir solicitação de alteração de arte, documento de
-- fornecedor, orçamento ou intenção/pedido vinculado. As funções alteradas
-- voltam com o texto exato da R4.2 (pg_get_functiondef do banco R4.2); as
-- RPCs de orçamento e de aceite voltam à assinatura da R4.2; as tabelas,
-- colunas, índices, políticas e o bucket novos saem; a linha do manifesto
-- R4.2.1 é retirada (ato do dono, com a trava do manifesto religada na mesma
-- transação), e o manifesto vigente volta a ser o R4.2.
-- ===========================================================================
DO $guarda$
BEGIN
  IF (SELECT manifest_label FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1) <> 'R4.2.1' THEN
    RAISE EXCEPTION 'rollback_r421_recusado: manifesto vigente nao e o R4.2.1';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests)
     OR EXISTS (SELECT 1 FROM public.commercial_artwork_change_supplier_documents)
     OR EXISTS (SELECT 1 FROM public.commercial_artwork_change_quotes)
     OR EXISTS (SELECT 1 FROM public.commercial_checkout_intents WHERE artwork_change_request_id IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders WHERE artwork_change_request_id IS NOT NULL) THEN
    RAISE EXCEPTION 'rollback_r421_recusado: ja ha solicitacao, documento, orcamento ou pedido vinculado';
  END IF;
END $guarda$;

-- Funções da R4.2 (texto exato).
CREATE OR REPLACE FUNCTION public.commercial_artwork_change_requests_protect()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: solicitacao nao e apagada' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'draft' OR NEW.row_version <> 1 THEN
      RAISE EXCEPTION 'alteracao_arte_estado_invalido: solicitacao nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.company_id IS DISTINCT FROM OLD.company_id
     OR NEW.base_order_id IS DISTINCT FROM OLD.base_order_id
     OR NEW.fidelity_identity IS DISTINCT FROM OLD.fidelity_identity
     OR NEW.target_campaign IS DISTINCT FROM OLD.target_campaign
     OR NEW.requested_by IS DISTINCT FROM OLD.requested_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: identidade da solicitacao nao muda' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'alteracao_arte_versao: row_version deve avancar exatamente 1' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status IN ('production_authorized', 'rejected', 'cancelled') THEN
    RAISE EXCEPTION 'alteracao_arte_final: solicitacao % encerrada (%)', OLD.id, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF NOT ((OLD.status, NEW.status) IN (
      ('draft', 'draft'), ('draft', 'submitted'), ('draft', 'cancelled'),
      ('submitted', 'submitted'), ('submitted', 'under_review'), ('submitted', 'cancelled'), ('submitted', 'rejected'),
      ('under_review', 'under_review'), ('under_review', 'quoted'), ('under_review', 'cancelled'),
      ('under_review', 'rejected'),
      ('quoted', 'quoted'), ('quoted', 'under_review'), ('quoted', 'accepted'), ('quoted', 'cancelled'),
      ('quoted', 'rejected'),
      ('accepted', 'accepted'), ('accepted', 'quoted'), ('accepted', 'production_authorized'),
      ('accepted', 'cancelled'), ('accepted', 'rejected'))) THEN
    RAISE EXCEPTION 'alteracao_arte_transicao_invalida: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  -- Exceção registrada não é desfeita nem reescrita.
  IF OLD.exception_approved_by IS NOT NULL AND (
       NEW.exception_approved_by IS DISTINCT FROM OLD.exception_approved_by
       OR NEW.exception_approved_at IS DISTINCT FROM OLD.exception_approved_at
       OR NEW.exception_reason IS DISTINCT FROM OLD.exception_reason
       OR NEW.exception_feasibility IS DISTINCT FROM OLD.exception_feasibility) THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: excecao registrada nao muda' USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.artwork_change_request_create(p_order_id uuid, p_target_campaign text DEFAULT 'next_campaign'::text, p_phrase_text text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o  public.commercial_exclusivity_orders%ROWTYPE;
  v_id uuid;
  v_identidade text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF public.commercial_artwork_change_actor(v_o.company_id) IS DISTINCT FROM 'partner_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_o.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;
  IF p_target_campaign IS NULL OR p_target_campaign NOT IN ('next_campaign', 'current_campaign') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_target');
  END IF;
  IF p_phrase_text IS NOT NULL AND length(btrim(p_phrase_text)) NOT BETWEEN 1 AND 280 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_phrase');
  END IF;
  v_identidade := public.commercial_fidelity_identity(v_o.niche_code, v_o.segment_id);
  IF EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests
              WHERE company_id = v_o.company_id AND fidelity_identity = v_identidade
                AND status IN ('draft', 'submitted', 'under_review', 'quoted', 'accepted')) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_change_already_open');
  END IF;
  BEGIN
    INSERT INTO public.commercial_artwork_change_requests
      (company_id, base_order_id, fidelity_identity, target_campaign, phrase_text, request_note, requested_by)
    VALUES (v_o.company_id, v_o.id, v_identidade, p_target_campaign,
            nullif(btrim(coalesce(p_phrase_text, '')), ''), nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_change_already_open');
  END;
  PERFORM public.commercial_artwork_change_event(v_id, 'created', NULL, 'draft', 'partner_owner',
    pg_catalog.jsonb_build_object('target_campaign', p_target_campaign));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'request_id', v_id, 'status', 'draft', 'row_version', 1);
END $function$;

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
  v_arte   uuid;
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
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  IF NOT NEW.fidelized THEN
    NEW.flag_production_new_units    := v_sched.new_flag_units;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_sched.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  -- R4.2 (decisão B): alteração voluntária de arte com produção AUTORIZADA
  -- para a próxima campanha substitui a reutilização das bandeiras antigas.
  -- Preço-base, participantes e QA fidelizados não mudam; a produção da nova
  -- arte é rubrica separada (orçamento aceito na solicitação).
  v_arte := public.commercial_artwork_change_for_renewal(NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF v_arte IS NOT NULL THEN
    NEW.flag_production_new_units    := 0;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := 0;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := v_arte;
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
  NEW.artwork_change_request_id    := NULL;
  RETURN NEW;
END $function$;

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
  v_arte   uuid;
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
    NEW.artwork_change_request_id    := NULL;
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
    NEW.artwork_change_request_id    := v_i.artwork_change_request_id;
    RETURN NEW;
  END IF;

  -- Venda manual: mesma autoridade da intenção.
  IF NOT NEW.fidelized THEN
    NEW.flag_production_new_units    := v_sched.new_flag_units;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_sched.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  -- R4.2 (decisão B): alteração voluntária de arte com produção AUTORIZADA
  -- para a próxima campanha substitui a reutilização das bandeiras antigas.
  -- Preço-base, participantes e QA fidelizados não mudam; a produção da nova
  -- arte é rubrica separada (orçamento aceito na solicitação).
  v_arte := public.commercial_artwork_change_for_renewal(NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF v_arte IS NOT NULL THEN
    NEW.flag_production_new_units    := 0;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := 0;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := v_arte;
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
  NEW.artwork_change_request_id    := NULL;
  RETURN NEW;
END $function$;

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
  -- R4.2 (decisão B): alteração de arte com produção autorizada para a próxima
  -- campanha substitui a reutilização; a fidelidade não depende das peças.
  IF v_p ? 'new_flag_units' AND v_fidel
     AND public.commercial_artwork_change_for_renewal(
           p_company_id, public.commercial_fidelity_identity(p_niche_code, p_segment_id)) IS NULL THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.artwork_change_requests_for_order(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o    public.commercial_exclusivity_orders%ROWTYPE;
  v_ator text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  v_ator := public.commercial_artwork_change_actor(v_o.company_id);
  IF v_ator IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'viewer_role', v_ator,
    'can_request', v_ator = 'partner_owner',
    'requests', coalesce((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'request_id', r.id, 'status', r.status, 'row_version', r.row_version,
        'target_campaign', r.target_campaign, 'phrase_text', r.phrase_text,
        'created_at', r.created_at, 'updated_at', r.updated_at,
        'exception_approved', r.exception_approved_by IS NOT NULL,
        'accepted_total_cents', r.accepted_total_cents, 'closed_reason', r.closed_reason,
        'versions', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'version_id', v.id, 'version_no', v.version_no, 'storage_path', v.storage_path,
            'mime_type', v.mime_type, 'byte_size', v.byte_size, 'sha256', v.sha256,
            'phrase_text', v.phrase_text, 'registered_at', v.registered_at) ORDER BY v.version_no)
          FROM public.commercial_artwork_change_versions v WHERE v.request_id = r.id), '[]'::jsonb),
        'quote', (SELECT pg_catalog.jsonb_build_object(
            'quote_id', q.id, 'quote_no', q.quote_no, 'status', q.status,
            'artwork_version_id', q.artwork_version_id, 'supplier_name', q.supplier_name,
            'supplier_document_reference', q.supplier_document_reference, 'scope', q.scope,
            'pieces_count', q.pieces_count, 'supplier_unit_cost_cents', q.supplier_unit_cost_cents,
            'supplier_total_cents', q.supplier_total_cents, 'partner_charge_cents', q.partner_charge_cents,
            'cap_cents', q.cap_cents, 'excluded_items', pg_catalog.to_jsonb(q.excluded_items))
          FROM public.commercial_artwork_change_quotes q
         WHERE q.request_id = r.id AND q.status IN ('open', 'accepted')
         ORDER BY q.quote_no DESC LIMIT 1))
        ORDER BY r.created_at DESC)
        FROM public.commercial_artwork_change_requests r WHERE r.base_order_id = v_o.id), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.commercial_guard_catalog()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  WITH tabelas AS (
    SELECT x.nome, pg_catalog.to_regclass('public.' || x.nome) AS rel
      FROM pg_catalog.unnest(ARRAY[
        'commercial_pricing_rules', 'commercial_pricing_schedule', 'commercial_settlement_terms',
        'commercial_checkout_intents', 'commercial_exclusivity_orders', 'commercial_payments',
        'commercial_pricing_activation_log', 'commercial_pricing_activation_approvals',
        'commercial_flag_sets', 'commercial_flag_set_inspections',
        'commercial_instrument_template_approvals', 'commercial_qa_operational_procedures',
        'commercial_guard_manifests']) AS x(nome)
  ), gatilhos AS (
    SELECT t.*
      FROM pg_catalog.pg_trigger t
      JOIN tabelas ON tabelas.rel = t.tgrelid
     WHERE NOT t.tgisinternal
  ), funcoes AS (
    SELECT p.oid
      FROM pg_catalog.pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname = ANY (ARRAY[
         'admin_activate_pricing_rule', 'commercial_pricing_activation_preflight',
         'commercial_activation_called_by_procedure', 'commercial_activation_guard_fingerprint',
         'commercial_guard_function_entry', 'commercial_guard_catalog', 'commercial_guard_integrity_failures',
         'admin_confirm_manual_bdflow_payment', 'commercial_build_instrument_snapshot',
         'commercial_order_settlement_check'])
    UNION
    SELECT g.tgfoid FROM gatilhos g
  )
  SELECT pg_catalog.jsonb_build_object(
    'format', 'smallflags-guard-catalog/1 (R4.1, sha256)',
    'tables', (SELECT pg_catalog.jsonb_agg(
                        pg_catalog.jsonb_build_object('table', 'public.' || nome, 'present', rel IS NOT NULL)
                        ORDER BY nome) FROM tabelas),
    'functions', coalesce((SELECT pg_catalog.jsonb_object_agg(f.oid::regprocedure::text,
                                    public.commercial_guard_function_entry(f.oid::regprocedure))
                             FROM funcoes f), '{}'::jsonb),
    'triggers', coalesce((SELECT pg_catalog.jsonb_object_agg(
        g.tgrelid::regclass::text || '.' || g.tgname,
        pg_catalog.jsonb_build_object(
          'state', g.tgenabled::text,
          'definition', pg_catalog.pg_get_triggerdef(g.oid, false),
          'definition_sha256', pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
                                 pg_catalog.pg_get_triggerdef(g.oid, false), 'UTF8')), 'hex'),
          'function', g.tgfoid::regprocedure::text,
          'function_sha256', public.commercial_guard_function_entry(g.tgfoid::regprocedure)->>'definition_sha256',
          'tgtype', g.tgtype,
          'args_sha256', pg_catalog.encode(pg_catalog.sha256(g.tgargs), 'hex'),
          'when', pg_catalog.pg_get_expr(g.tgqual, g.tgrelid),
          'columns', g.tgattr::text,
          'deferrable', g.tgdeferrable,
          'initially_deferred', g.tginitdeferred))
        FROM gatilhos g), '{}'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.commercial_guard_integrity_failures()
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_m     public.commercial_guard_manifests%ROWTYPE;
  v_viva  jsonb;
  v_f     text[] := ARRAY[]::text[];
  v_k     text;
  v_a     jsonb;
  v_b     jsonb;
  v_camp  text;
  v_dif   text[];
BEGIN
  IF pg_catalog.current_setting('session_replication_role') <> 'origin' THEN
    v_f := v_f || ('session_replication_role_not_origin:' || pg_catalog.current_setting('session_replication_role'));
  END IF;
  SELECT * INTO v_m FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN v_f || 'guard_manifest_missing'::text;
  END IF;
  v_viva := public.commercial_guard_catalog();

  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(v_m.catalog->'triggers') LOOP
    v_a := v_m.catalog->'triggers'->v_k;
    v_b := v_viva->'triggers'->v_k;
    IF v_b IS NULL THEN
      v_f := v_f || ('guard_trigger_missing:' || v_k);
      CONTINUE;
    END IF;
    IF v_b->>'state' IS DISTINCT FROM v_a->>'state' THEN
      v_f := v_f || format('guard_trigger_state_not_approved:%s:%s(aprovado %s)', v_k, v_b->>'state', v_a->>'state');
    END IF;
    v_dif := ARRAY[]::text[];
    FOREACH v_camp IN ARRAY ARRAY['definition_sha256', 'function', 'function_sha256', 'tgtype',
                                  'args_sha256', 'when', 'columns', 'deferrable', 'initially_deferred'] LOOP
      IF v_b->v_camp IS DISTINCT FROM v_a->v_camp THEN
        v_dif := v_dif || v_camp;
      END IF;
    END LOOP;
    IF array_length(v_dif, 1) > 0 THEN
      v_f := v_f || format('guard_trigger_definition_divergent:%s:%s', v_k, array_to_string(v_dif, ','));
    END IF;
  END LOOP;
  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(v_viva->'triggers')
             EXCEPT SELECT pg_catalog.jsonb_object_keys(v_m.catalog->'triggers') LOOP
    v_f := v_f || ('guard_trigger_not_approved:' || v_k);
  END LOOP;

  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(v_m.catalog->'functions')
             UNION SELECT pg_catalog.jsonb_object_keys(v_viva->'functions') LOOP
    IF v_viva->'functions'->v_k IS NULL THEN
      v_f := v_f || ('guard_function_missing:' || v_k);
    ELSIF v_m.catalog->'functions'->v_k IS NULL THEN
      v_f := v_f || ('guard_function_not_approved:' || v_k);
    ELSIF v_viva->'functions'->v_k IS DISTINCT FROM v_m.catalog->'functions'->v_k THEN
      v_f := v_f || ('guard_function_divergent:' || v_k);
    END IF;
  END LOOP;
  IF v_viva->'tables' IS DISTINCT FROM v_m.catalog->'tables' THEN
    v_f := v_f || 'guard_tables_divergent'::text;
  END IF;
  -- Rede de segurança: qualquer diferença não nomeada acima.
  IF v_viva IS DISTINCT FROM v_m.catalog AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.unnest(v_f) x WHERE x NOT LIKE 'session_replication_role%') THEN
    v_f := v_f || 'guard_manifest_divergent'::text;
  END IF;
  RETURN v_f;
END $function$;

CREATE OR REPLACE FUNCTION public.commercial_artwork_change_for_renewal(p_company_id uuid, p_fidelity_identity text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT r.id
    FROM public.commercial_artwork_change_requests r
   WHERE r.company_id = p_company_id
     AND r.fidelity_identity = p_fidelity_identity
     AND r.status = 'production_authorized'
     AND r.target_campaign = 'next_campaign'
     AND NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                      WHERE o.artwork_change_request_id = r.id AND o.status <> 'cancelled')
   ORDER BY r.production_authorized_at DESC, r.id
   LIMIT 1;
$function$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_for_renewal(uuid, text) FROM PUBLIC, anon, authenticated, service_role;

DROP FUNCTION public.admin_artwork_change_register_quote(uuid, integer, uuid, text, text, text, jsonb, bigint);
DROP FUNCTION public.artwork_change_accept_quote(uuid, integer, uuid, bigint, text);
CREATE FUNCTION public.admin_artwork_change_register_quote(p_request_id uuid, p_expected_row_version integer, p_supplier_name text, p_supplier_document_reference text, p_supplier_document_sha256 text, p_scope text, p_pieces_count integer, p_supplier_unit_cost_cents bigint, p_supplier_total_cents bigint, p_cap_cents bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  g     record;
  v_ver uuid;
  v_n   integer;
  v_id  uuid;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['site_admin'], ARRAY['under_review', 'quoted', 'accepted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  SELECT id INTO v_ver FROM public.commercial_artwork_change_versions
   WHERE request_id = (g.r).id ORDER BY version_no DESC LIMIT 1;
  IF v_ver IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_version_required');
  END IF;
  IF p_supplier_name IS NULL OR length(btrim(p_supplier_name)) < 2
     OR p_supplier_document_reference IS NULL OR length(btrim(p_supplier_document_reference)) < 5
     OR p_supplier_document_sha256 IS NULL OR p_supplier_document_sha256 !~ '^[0-9a-f]{64}$'
     OR p_scope IS NULL OR length(btrim(p_scope)) < 5 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'supplier_document_required');
  END IF;
  IF p_pieces_count IS NULL OR p_pieces_count <= 0 OR p_supplier_unit_cost_cents IS NULL
     OR p_supplier_unit_cost_cents <= 0 OR p_supplier_total_cents IS NULL OR p_supplier_total_cents <= 0
     OR p_cap_cents IS NULL OR p_cap_cents < p_supplier_total_cents THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_quote_values');
  END IF;

  UPDATE public.commercial_artwork_change_quotes SET status = 'superseded'
   WHERE request_id = (g.r).id AND status IN ('open', 'accepted');
  SELECT coalesce(max(quote_no), 0) + 1 INTO v_n FROM public.commercial_artwork_change_quotes
   WHERE request_id = (g.r).id;
  INSERT INTO public.commercial_artwork_change_quotes
    (request_id, quote_no, artwork_version_id, supplier_name, supplier_document_reference,
     supplier_document_sha256, scope, pieces_count, supplier_unit_cost_cents, supplier_total_cents,
     cap_cents, registered_by)
  VALUES ((g.r).id, v_n, v_ver, btrim(p_supplier_name), btrim(p_supplier_document_reference),
          p_supplier_document_sha256, btrim(p_scope), p_pieces_count, p_supplier_unit_cost_cents,
          p_supplier_total_cents, p_cap_cents, auth.uid())
  RETURNING id INTO v_id;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'quoted', accepted_quote_id = NULL,
         accepted_total_cents = NULL, accepted_by = NULL, accepted_at = NULL
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id,
    CASE WHEN (g.r).status = 'accepted' THEN 'quote_revised_acceptance_cleared' ELSE 'quote_registered' END,
    (g.r).status, 'quoted', 'site_admin',
    pg_catalog.jsonb_build_object('quote_id', v_id, 'quote_no', v_n, 'supplier_total_cents', p_supplier_total_cents,
                                  'cap_cents', p_cap_cents, 'artwork_version_id', v_ver));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'quote_id', v_id, 'quote_no', v_n, 'status', 'quoted',
    'partner_charge_cents', p_supplier_total_cents, 'row_version', (g.r).row_version + 1);
END $function$;
CREATE FUNCTION public.artwork_change_accept_quote(p_request_id uuid, p_expected_row_version integer, p_quote_id uuid, p_accepted_total_cents bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  g   record;
  v_q public.commercial_artwork_change_quotes%ROWTYPE;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['partner_owner'], ARRAY['quoted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  SELECT * INTO v_q FROM public.commercial_artwork_change_quotes
   WHERE id = p_quote_id AND request_id = (g.r).id;
  IF NOT FOUND OR v_q.status <> 'open' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quote_not_current');
  END IF;
  IF v_q.artwork_version_id IS DISTINCT FROM (SELECT id FROM public.commercial_artwork_change_versions
                                               WHERE request_id = (g.r).id ORDER BY version_no DESC LIMIT 1) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quote_not_current');
  END IF;
  IF p_accepted_total_cents IS DISTINCT FROM v_q.partner_charge_cents OR v_q.partner_charge_cents > v_q.cap_cents THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'accepted_total_mismatch',
      'partner_charge_cents', v_q.partner_charge_cents, 'cap_cents', v_q.cap_cents);
  END IF;
  UPDATE public.commercial_artwork_change_quotes SET status = 'accepted' WHERE id = v_q.id;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'accepted', accepted_quote_id = v_q.id,
         accepted_total_cents = v_q.partner_charge_cents, accepted_by = auth.uid(), accepted_at = pg_catalog.now()
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'quote_accepted', 'quoted', 'accepted', 'partner_owner',
    pg_catalog.jsonb_build_object('quote_id', v_q.id, 'partner_charge_cents', v_q.partner_charge_cents,
                                  'cap_cents', v_q.cap_cents));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'accepted', 'row_version', (g.r).row_version + 1);
END $function$;
REVOKE ALL ON FUNCTION public.admin_artwork_change_register_quote(uuid, integer, text, text, text, text, integer, bigint, bigint, bigint),
                       public.artwork_change_accept_quote(uuid, integer, uuid, bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_artwork_change_register_quote(uuid, integer, text, text, text, text, integer, bigint, bigint, bigint),
                          public.artwork_change_accept_quote(uuid, integer, uuid, bigint)
  TO authenticated;

-- Orçamento itemizado e documento do fornecedor.
DROP TABLE public.commercial_artwork_change_quote_items;
ALTER TABLE public.commercial_artwork_change_quotes
  DROP COLUMN supplier_document_id,
  DROP CONSTRAINT cacq_valores,
  ADD CONSTRAINT cacq_valores CHECK (pieces_count > 0 AND supplier_unit_cost_cents > 0
                                     AND supplier_total_cents > 0 AND cap_cents >= supplier_total_cents),
  ALTER COLUMN supplier_unit_cost_cents SET NOT NULL;
DROP TRIGGER cacq_concilia ON public.commercial_artwork_change_quotes;
DROP FUNCTION public.commercial_artwork_change_quote_reconcile();
DROP FUNCTION public.service_artwork_change_attest_supplier_document(uuid, uuid, text, bigint);
DROP FUNCTION public.admin_artwork_change_register_supplier_document(uuid, text, text);
DROP FUNCTION public.admin_artwork_change_supplier_document_path(uuid);
DROP FUNCTION public.commercial_artwork_change_document_valid(uuid, uuid);
DROP POLICY cacd_owner_select ON storage.objects;
DROP POLICY cacd_admin_select ON storage.objects;
DROP POLICY cacd_admin_insert ON storage.objects;
DROP FUNCTION public.commercial_artwork_change_document_readable(text);
DROP TABLE public.commercial_artwork_change_supplier_documents;
DROP FUNCTION public.commercial_artwork_change_supplier_document_protect();
DELETE FROM storage.buckets WHERE id = 'supplier-quote-documents'
   AND NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'supplier-quote-documents');

-- Campanha alvo, prontidão e trava.
DROP FUNCTION public.commercial_artwork_change_renewal_state(uuid, text, uuid);
DROP FUNCTION public.commercial_artwork_change_readiness(uuid);
DROP FUNCTION public.commercial_artwork_change_lock(uuid, text);
DROP INDEX public.cacr_uma_por_campanha_idx;
ALTER TABLE public.commercial_artwork_change_requests
  DROP CONSTRAINT cacr_alvo_sequencia,
  DROP COLUMN target_sequence_number,
  DROP COLUMN target_region_id,
  DROP COLUMN base_exclusivity_id;

-- Manifesto R4.2.1 retirado; o vigente volta a ser o R4.2.
ALTER TABLE public.commercial_guard_manifests DISABLE TRIGGER cgm_protect;
DELETE FROM public.commercial_guard_manifests WHERE manifest_label = 'R4.2.1';
ALTER TABLE public.commercial_guard_manifests ENABLE TRIGGER cgm_protect;

DO $confere$
BEGIN
  IF (SELECT manifest_label FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1) <> 'R4.2'
     OR coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0) > 0 THEN
    RAISE EXCEPTION 'rollback_r421: guardas nao voltaram ao manifesto R4.2: %', public.commercial_guard_integrity_failures();
  END IF;
END $confere$;
