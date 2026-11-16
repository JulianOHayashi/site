-- ===========================================================================
-- ROLLBACK da R4.3 (20261116210000) -> estado exato da R4.2.1.
-- Recusado se a versão 4 já tiver modalidade habilitada ou saído de
-- 'prepared', ou se o manifesto vigente não for o R4.3.
-- ===========================================================================
DO $guarda$
BEGIN
  IF (SELECT manifest_label FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1) <> 'R4.3' THEN
    RAISE EXCEPTION 'rollback_r43_recusado: manifesto vigente nao e o R4.3';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_pricing_rules WHERE enabled_settlement_modes IS NOT NULL)
     OR (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared' THEN
    RAISE EXCEPTION 'rollback_r43_recusado: modalidade ja habilitada ou versao 4 fora de prepared';
  END IF;
END $guarda$;

CREATE OR REPLACE FUNCTION public.commercial_pricing_activation_preflight(p_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_rule    public.commercial_pricing_rules%ROWTYPE;
  v_falhas  text[] := ARRAY[]::text[];
  v_econ    text;
  v_cat     text;
  v_fid     boolean;
  v_modo    text;
  v_n       integer;
  v_nichos  integer;
BEGIN
  SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE version = p_version;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'version', p_version,
      'failures', pg_catalog.to_jsonb(ARRAY['rule_not_found']));
  END IF;
  IF v_rule.status <> 'prepared' THEN
    v_falhas := v_falhas || ('rule_not_prepared:' || v_rule.status);
  END IF;

  -- A4: política de QA e termos das DUAS modalidades, coerentes.
  IF v_rule.qa_policy IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    v_falhas := v_falhas || 'qa_policy_missing'::text;
  END IF;
  SELECT count(*) INTO v_n FROM public.commercial_pricing_schedule WHERE pricing_rule_version = p_version;
  IF v_n <> 4 THEN
    v_falhas := v_falhas || ('schedule_incomplete:' || v_n);
  END IF;
  SELECT max(contract_economics_version) INTO v_econ
    FROM public.commercial_pricing_schedule WHERE pricing_rule_version = p_version;
  FOREACH v_cat IN ARRAY ARRAY['supermarket', 'common'] LOOP
    FOREACH v_fid IN ARRAY ARRAY[false, true] LOOP
      FOREACH v_modo IN ARRAY ARRAY['direct_benefits', 'cash'] LOOP
        IF NOT EXISTS (SELECT 1 FROM public.commercial_settlement_terms t
                        WHERE t.pricing_rule_version = p_version AND t.commercial_category = v_cat
                          AND t.fidelized = v_fid AND t.benefit_settlement_mode = v_modo) THEN
          v_falhas := v_falhas || format('settlement_terms_missing:%s/%s/%s', v_cat,
                                         CASE WHEN v_fid THEN 'fidelizado' ELSE 'novo' END, v_modo);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  -- A6: minuta assinável que redige o modelo de liquidação, para as duas
  -- condições de fidelidade; e atividade contratada aprovada no catálogo da
  -- economia da versão, para toda posição ativa (A2).
  FOREACH v_fid IN ARRAY ARRAY[false, true] LOOP
    -- R4: minuta assinável COM aprovação jurídica do mesmo conteúdo, para a
    -- economia da versão, o modelo de liquidação e as DUAS modalidades.
    IF NOT EXISTS (SELECT 1 FROM public.commercial_instrument_templates t
                     JOIN public.commercial_instrument_template_approvals a
                       ON a.template_id = t.id
                      AND a.content_sha256 = t.source_hash
                      AND a.contract_economics_version = v_econ
                      AND a.settlement_model = v_rule.qa_policy
                      AND a.applies_to_fidelized = v_fid
                      AND a.settlement_modes @> ARRAY['direct_benefits', 'cash']::text[]
                    WHERE t.lifecycle_status = 'signable' AND t.applies_to_fidelized = v_fid
                      AND t.settlement_model IS NOT DISTINCT FROM v_rule.qa_policy
                      AND v_rule.qa_policy IS NOT NULL) THEN
      v_falhas := v_falhas || format('instrument_template_missing:%s',
                                     CASE WHEN v_fid THEN 'fidelizado' ELSE 'novo' END);
    END IF;
  END LOOP;
  SELECT count(*) INTO v_nichos FROM public.commercial_niches WHERE is_active;
  SELECT count(DISTINCT c.niche_code) INTO v_n
    FROM public.commercial_contract_activity_catalog c
    JOIN public.commercial_niches n ON n.code = c.niche_code AND n.is_active
   WHERE c.catalog_version = v_econ AND c.status = 'approved';
  IF v_econ IS NULL OR v_n < v_nichos THEN
    v_falhas := v_falhas || format('activity_catalog_incomplete:%s/%s', v_n, v_nichos);
  END IF;

  -- R4.1: as guardas precisam ser IGUAIS ao manifesto aprovado: estado
  -- aprovado ('O'; 'R', 'A', 'D' ou ausente recusados), definição, função
  -- executada, momento, eventos, argumentos e condição. Nome não basta.
  v_falhas := v_falhas || public.commercial_guard_integrity_failures();

  -- R4.1: lançamento aprovado fora do banco e registrado antes do ato.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_approvals a
                  WHERE a.pricing_rule_version = p_version) THEN
    v_falhas := v_falhas || 'activation_approval_missing'::text;
  END IF;

  -- R4.1: QA em produtos só com procedimento operacional aprovado para a
  -- economia da versão (autorização, recebimento, testes, evidências e não
  -- cumprimento).
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms t
              WHERE t.pricing_rule_version = p_version
                AND t.benefit_settlement_mode = 'direct_benefits' AND t.qa_in_kind_cents > 0)
     AND NOT EXISTS (SELECT 1 FROM public.commercial_qa_operational_procedures q
                      WHERE q.contract_economics_version = v_econ) THEN
    v_falhas := v_falhas || format('qa_operational_procedure_missing:%s', coalesce(v_econ, '?'));
  END IF;

  -- Reserva viva sob a versão anterior seria finalizada com o preço antigo.
  SELECT count(*) INTO v_n FROM public.commercial_checkout_intents
   WHERE status IN ('draft', 'awaiting_contract')
     AND reserved_until IS NOT NULL AND reserved_until > pg_catalog.now();
  IF v_n > 0 THEN
    v_falhas := v_falhas || ('live_reservations:' || v_n);
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', coalesce(array_length(v_falhas, 1), 0) = 0,
    'version', p_version,
    'failures', pg_catalog.to_jsonb(v_falhas));
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
  v_ac       jsonb;
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
  -- R4.2.1: alteração destinada a esta campanha pendente ou não pronta
  -- bloqueia (sem cair para as bandeiras antigas); pronta substitui o reuso.
  IF v_p ? 'new_flag_units' AND v_fidel THEN
    v_ac := public.commercial_artwork_change_renewal_state(
              p_company_id, public.commercial_fidelity_identity(p_niche_code, p_segment_id), v_excl);
    IF v_ac->>'state' IN ('pending', 'not_ready') THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_ac->>'reason',
        'detail', coalesce(v_ac->'missing', pg_catalog.to_jsonb(v_ac->>'status')));
    END IF;
  END IF;
  IF v_p ? 'new_flag_units' AND v_fidel AND coalesce(v_ac->>'state', 'none') <> 'ready' THEN
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

CREATE OR REPLACE FUNCTION public.commercial_settlement_public_v15(p_version integer, p_qa_policy text, p_niche_code text, p_fidelized boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_d public.commercial_settlement_terms%ROWTYPE;
  v_c public.commercial_settlement_terms%ROWTYPE;
BEGIN
  v_d := public.commercial_settlement_terms_for(p_version, p_niche_code, p_fidelized, 'direct_benefits');
  v_c := public.commercial_settlement_terms_for(p_version, p_niche_code, p_fidelized, 'cash');
  RETURN pg_catalog.jsonb_build_object(
    'qa_policy', p_qa_policy,
    'settlement_modes', pg_catalog.jsonb_build_object(
      'direct_benefits', public.commercial_settlement_mode_json(v_d),
      'cash', public.commercial_settlement_mode_json(v_c)),
    -- Remuneração MONETÁRIA da SmallFlags: a parcela principal, sem a QA.
    'smallflags_total_remuneration_cents', v_d.smallflags_main_fee_cents,
    'funding_direct_benefits_cents', v_d.total_monetary_funding_required_cents,
    'funding_cash_cents', v_c.total_monetary_funding_required_cents,
    'qa_in_kind_deliverable_cents', v_d.qa_in_kind_cents);
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
        'commercial_guard_manifests',
        'commercial_artwork_change_requests', 'commercial_artwork_change_versions',
        'commercial_artwork_change_quotes', 'commercial_artwork_change_quote_items',
        'commercial_artwork_change_events', 'commercial_artwork_change_supplier_documents']) AS x(nome)
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
         'commercial_order_settlement_check',
         'commercial_artwork_change_actor', 'commercial_artwork_change_gate', 'commercial_artwork_change_event',
         'commercial_artwork_change_lock', 'commercial_artwork_change_readiness',
         'commercial_artwork_change_renewal_state', 'commercial_artwork_change_document_valid',
         'commercial_artwork_change_document_readable', 'commercial_artwork_change_quote_reconcile',
         'artwork_change_request_create', 'artwork_change_image_path', 'artwork_change_register_version',
         'artwork_change_submit', 'artwork_change_accept_quote', 'artwork_change_cancel',
         'artwork_change_requests_for_order', 'admin_artwork_change_start_review',
         'admin_artwork_change_register_quote', 'admin_artwork_change_approve_exception',
         'admin_artwork_change_authorize_production', 'admin_artwork_change_reject',
         'admin_artwork_change_supplier_document_path', 'admin_artwork_change_register_supplier_document',
         'service_artwork_change_attest_supplier_document',
         'commercial_order_artwork_locked', 'request_customization_image_path', 'register_customization_image',
         'create_commercial_checkout_intent', 'commercial_flag_reuse_resolution', 'commercial_fidelity_identity',
         'is_site_admin', 'm2_is_company_owner', 'm2_is_company_member'])
    UNION
    SELECT g.tgfoid FROM gatilhos g
  ), entrada AS (
    SELECT p.oid,
           pg_catalog.jsonb_build_object('definition_sha256',
             pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid), 'UTF8')), 'hex'))
           || CASE WHEN p.prorettype = 'trigger'::pg_catalog.regtype THEN '{}'::jsonb
                   ELSE pg_catalog.jsonb_build_object('execute', coalesce((
                          SELECT pg_catalog.jsonb_agg(x.r ORDER BY x.r)
                            FROM (SELECT DISTINCT coalesce(nullif(g.grantee, 0)::pg_catalog.regrole::text, 'PUBLIC') AS r
                                    FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) g
                                   WHERE g.privilege_type = 'EXECUTE' AND g.grantee <> p.proowner) x),
                          '[]'::jsonb))
              END AS e
      FROM pg_catalog.pg_proc p
     WHERE p.oid IN (SELECT oid FROM funcoes)
  ), tab AS (
    SELECT tb.nome, tb.rel,
      pg_catalog.jsonb_build_object(
        'table', 'public.' || tb.nome,
        'present', tb.rel IS NOT NULL,
        'rls', c.relrowsecurity,
        'rls_forced', c.relforcerowsecurity,
        'acl', coalesce((SELECT pg_catalog.jsonb_agg(x.r ORDER BY x.r)
                           FROM (SELECT DISTINCT coalesce(nullif(a.grantee, 0)::pg_catalog.regrole::text, 'PUBLIC')
                                          || ':' || a.privilege_type AS r
                                   FROM pg_catalog.aclexplode(coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))) a
                                  -- MAINTAIN (PG17+) fora: só manutenção, não altera dados.
                                  WHERE a.grantee <> c.relowner AND a.privilege_type <> 'MAINTAIN') x), '[]'::jsonb),
        'columns_sha256', pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce((
            SELECT pg_catalog.string_agg(pg_catalog.concat_ws('|', a.attname,
                     pg_catalog.format_type(a.atttypid, a.atttypmod), a.attnotnull::text, a.attgenerated::text,
                     a.attidentity::text, pg_catalog.pg_get_expr(d.adbin, d.adrelid)), E'\n' ORDER BY a.attnum)
              FROM pg_catalog.pg_attribute a
              LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
             WHERE a.attrelid = tb.rel AND a.attnum > 0 AND NOT a.attisdropped), ''), 'UTF8')), 'hex'),
        'constraints', coalesce((SELECT pg_catalog.jsonb_object_agg(k.conname, pg_catalog.pg_get_constraintdef(k.oid))
                                   FROM pg_catalog.pg_constraint k WHERE k.conrelid = tb.rel), '{}'::jsonb),
        'indexes', coalesce((SELECT pg_catalog.jsonb_object_agg(ic.relname, pg_catalog.pg_get_indexdef(i.indexrelid))
                               FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid
                              WHERE i.indrelid = tb.rel), '{}'::jsonb),
        'policies', coalesce((SELECT pg_catalog.jsonb_object_agg(po.polname, pg_catalog.jsonb_build_object(
                                 'cmd', po.polcmd::text, 'permissive', po.polpermissive,
                                 'roles', (SELECT pg_catalog.jsonb_agg(coalesce(nullif(r, 0)::pg_catalog.regrole::text, 'PUBLIC') ORDER BY 1)
                                             FROM pg_catalog.unnest(po.polroles) r),
                                 'using', pg_catalog.pg_get_expr(po.polqual, po.polrelid),
                                 'check', pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid)))
                                FROM pg_catalog.pg_policy po WHERE po.polrelid = tb.rel), '{}'::jsonb)) AS j
      FROM tabelas tb LEFT JOIN pg_catalog.pg_class c ON c.oid = tb.rel
  )
  SELECT pg_catalog.jsonb_build_object(
    'format', 'smallflags-guard-catalog/2 (R4.2.1, sha256)',
    'tables', (SELECT pg_catalog.jsonb_agg(tab.j ORDER BY tab.nome) FROM tab),
    'functions', coalesce((SELECT pg_catalog.jsonb_object_agg(en.oid::pg_catalog.regprocedure::text, en.e)
                             FROM entrada en), '{}'::jsonb),
    'triggers', coalesce((SELECT pg_catalog.jsonb_object_agg(
        g.tgrelid::pg_catalog.regclass::text || '.' || g.tgname,
        pg_catalog.jsonb_build_object(
          'state', g.tgenabled::text,
          'definition', pg_catalog.pg_get_triggerdef(g.oid, false),
          'definition_sha256', pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
                                 pg_catalog.pg_get_triggerdef(g.oid, false), 'UTF8')), 'hex'),
          'function', g.tgfoid::pg_catalog.regprocedure::text,
          'function_sha256', en.e->>'definition_sha256',
          'tgtype', g.tgtype,
          'args_sha256', pg_catalog.encode(pg_catalog.sha256(g.tgargs), 'hex'),
          'when', pg_catalog.pg_get_expr(g.tgqual, g.tgrelid),
          'columns', g.tgattr::text,
          'deferrable', g.tgdeferrable,
          'initially_deferred', g.tginitdeferred))
        FROM gatilhos g JOIN entrada en ON en.oid = g.tgfoid), '{}'::jsonb),
    'storage', pg_catalog.jsonb_build_object(
      'objects_rls', (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
                       WHERE c.oid = pg_catalog.to_regclass('storage.objects')),
      'buckets', coalesce((SELECT pg_catalog.jsonb_object_agg(b.id, pg_catalog.jsonb_build_object(
                             'public', b.public, 'file_size_limit', b.file_size_limit,
                             'allowed_mime_types', pg_catalog.to_jsonb(b.allowed_mime_types)))
                             FROM storage.buckets b
                            WHERE b.id IN ('partner-customization-images', 'supplier-quote-documents')), '{}'::jsonb),
      'policies', coalesce((SELECT pg_catalog.jsonb_object_agg(po.polname, pg_catalog.jsonb_build_object(
                             'cmd', po.polcmd::text, 'permissive', po.polpermissive,
                             'roles', (SELECT pg_catalog.jsonb_agg(coalesce(nullif(r, 0)::pg_catalog.regrole::text, 'PUBLIC') ORDER BY 1)
                                         FROM pg_catalog.unnest(po.polroles) r),
                             'using', pg_catalog.pg_get_expr(po.polqual, po.polrelid),
                             'check', pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid)))
                             FROM pg_catalog.pg_policy po
                            WHERE po.polrelid = pg_catalog.to_regclass('storage.objects')
                              AND (coalesce(pg_catalog.pg_get_expr(po.polqual, po.polrelid), '')
                                   || coalesce(pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid), ''))
                                  ~ '(partner-customization-images|supplier-quote-documents)'), '{}'::jsonb)));
$function$;

DROP TRIGGER cci_modalidade_habilitada ON public.commercial_checkout_intents;
DROP TRIGGER ceo_modalidade_habilitada ON public.commercial_exclusivity_orders;
DROP FUNCTION public.commercial_settlement_mode_enabled_guard();
DROP FUNCTION public.commercial_enabled_settlement_modes(integer);
ALTER TABLE public.commercial_pricing_rules
  DROP CONSTRAINT cpr_modalidades_so_v15,
  DROP CONSTRAINT cpr_modalidades_habilitadas,
  DROP COLUMN enabled_settlement_modes;

ALTER TABLE public.commercial_guard_manifests DISABLE TRIGGER cgm_protect;
DELETE FROM public.commercial_guard_manifests WHERE manifest_label = 'R4.3';
ALTER TABLE public.commercial_guard_manifests ENABLE TRIGGER cgm_protect;

DO $confere$
BEGIN
  IF (SELECT manifest_label FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1) <> 'R4.2.1'
     OR coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0) > 0 THEN
    RAISE EXCEPTION 'rollback_r43: guardas nao voltaram ao manifesto R4.2.1: %', public.commercial_guard_integrity_failures();
  END IF;
END $confere$;
