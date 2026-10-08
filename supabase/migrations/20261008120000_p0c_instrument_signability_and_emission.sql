-- ============================================================================
-- P0-C — CONTRATAÇÃO V1.4 EXIGE MODELO ASSINÁVEL E EMITE O INSTRUMENTO
--
-- A minuta real SF-v1.4 continua `draft`. Esta migration NÃO publica, promove
-- ou altera texto jurídico. Enquanto não existir um modelo signable para a
-- condição de fidelidade, nenhuma contratação NOVA sob pricing_rule_version >= 3
-- pode nascer com status signed. V1/V2 históricos permanecem intocados.
--
-- Quando, em momento futuro e por ato administrativo deliberado, um modelo for
-- juridicamente liberado como signable, o instrumento individualizado é emitido
-- automaticamente na MESMA transação do pedido. Falha ao construir o snapshot
-- aborta a inserção inteira.
-- ============================================================================

-- 1. Corrige comparação do tomador: o registro do pedido usa 14 dígitos; o
-- cadastro empresarial pode conservar pontuação. Identidade é comparada após
-- normalização dos dois lados. Todo o restante do builder permanece server-side.

CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot(
  p_order_id    uuid,
  p_template_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o      public.commercial_exclusivity_orders%ROWTYPE;
  v_c      public.site_partner_companies%ROWTYPE;
  v_u      public.site_partner_units%ROWTYPE;
  v_a      public.commercial_master_agreements%ROWTYPE;
  v_rep    public.partner_application_representatives%ROWTYPE;
  v_ace    public.legal_acceptances%ROWTYPE;
  v_t      public.commercial_instrument_templates%ROWTYPE;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_ativ   jsonb;
  v_snap   jsonb;
  v_prov   jsonb;
  v_faltam text[] := ARRAY[]::text[];
  v_campo  text;
BEGIN
  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE id = p_template_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_unavailable');
  END IF;
  IF v_t.lifecycle_status <> 'signable' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_not_signable',
      'lifecycle_status', v_t.lifecycle_status, 'template_code', v_t.template_code);
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF coalesce(v_o.fidelized, false) <> v_t.applies_to_fidelized THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_fidelity_mismatch',
      'order_fidelized', coalesce(v_o.fidelized, false),
      'template_applies_to_fidelized', v_t.applies_to_fidelized);
  END IF;

  -- OUTROS dormente: nicho fora do catalogo canonico nao individualiza nada.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_niches n
                  WHERE n.code = v_o.niche_code AND n.is_active) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_niche_not_canonical',
      'niche_code', v_o.niche_code);
  END IF;

  SELECT * INTO v_c FROM public.site_partner_companies WHERE id = v_o.company_id;
  SELECT * INTO v_a FROM public.commercial_master_agreements
   WHERE id = v_o.master_agreement_id;
  SELECT * INTO v_rep FROM public.partner_application_representatives
   WHERE application_id = v_c.source_application_id AND is_current;
  IF v_o.legal_acceptance_id IS NOT NULL THEN
    SELECT * INTO v_ace FROM public.legal_acceptances WHERE id = v_o.legal_acceptance_id;
  END IF;

  -- ---- UNIDADE DE EXECUCAO: persistida e revalidada, nunca "a primeira".
  IF v_o.execution_unit_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_selected', 'order_id', v_o.id);
  END IF;
  SELECT * INTO v_u FROM public.site_partner_units WHERE id = v_o.execution_unit_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_found');
  END IF;
  IF v_u.company_id IS DISTINCT FROM v_o.company_id THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_owned_by_company');
  END IF;
  IF v_u.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_active', 'status', v_u.status);
  END IF;

  -- ---- TOMADOR DE NFS-e: tem de ser o CNPJ da contratante no MVP fundador.
  IF v_o.nfse_taker_cnpj IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'nfse_taker_not_persisted');
  END IF;
  IF pg_catalog.regexp_replace(v_o.nfse_taker_cnpj, '[^0-9]', '', 'g')
       IS DISTINCT FROM
       pg_catalog.regexp_replace(v_c.cnpj, '[^0-9]', '', 'g') THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'alternate_nfse_taker_not_supported',
      'persisted_taker', v_o.nfse_taker_cnpj);
  END IF;

  -- ---- ECONOMIA: da autoridade, incluindo o valor da participacao.
  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = v_o.pricing_rule_version
     AND contract_economics_version = v_o.contract_economics_version
     AND commercial_category = CASE WHEN v_o.niche_code = 'supermarket'
                                    THEN 'supermarket' ELSE 'common' END
     AND fidelized = coalesce(v_o.fidelized, false);
  IF NOT FOUND OR v_sched.ordinary_participation_value_cents IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'contract_economics_authority_unavailable',
      'pricing_rule_version', v_o.pricing_rule_version);
  END IF;

  -- ---- ATIVIDADE CONTRATADA: do catalogo. Bloqueada em producao.
  v_ativ := public.commercial_approved_contract_activity(
              v_o.niche_code, v_o.contract_economics_version);
  IF (v_ativ->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_ativ;
  END IF;

  v_snap := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'company_legal_name', v_c.legal_name,
    'company_cnpj', v_c.cnpj,
    'company_trade_name', v_c.trade_name,
    'representative_full_name', v_rep.full_name,
    'representative_cpf', v_rep.cpf,
    'representative_role_title', v_rep.role_title,
    'representative_authority_status', v_rep.authority_status,
    'city', v_c.city,
    'uf', v_c.uf,
    'region_id', v_o.region_id,
    'exclusivity_id', v_o.exclusivity_id,
    'nfse_taker_cnpj', v_o.nfse_taker_cnpj,
    'execution_unit_id', v_u.id,
    'execution_unit_name', v_u.name,
    'execution_unit_city', v_u.city,
    'execution_unit_uf', v_u.uf,
    'execution_unit_company_id', v_u.company_id,
    'activity_description', v_ativ->>'activity_description',
    'activity_code', v_ativ->>'activity_code',
    'activity_catalog_id', v_ativ->>'activity_catalog_id',
    'activity_source_hash', v_ativ->>'source_hash',
    'niche_code', v_o.niche_code,
    'nominal_quantity', v_o.nominal_quantity,
    'benefit_settlement_mode', v_o.benefit_settlement_mode,
    'master_agreement_id', v_a.id,
    'master_legal_document_id', v_a.legal_document_id,
    'master_agreement_version', v_a.agreement_version,
    'master_document_hash', v_a.document_hash,
    'order_id', v_o.id,
    'pricing_rule_version', v_o.pricing_rule_version,
    'contract_economics_version', v_o.contract_economics_version,
    'economic_value_cents', v_o.economic_value_cents,
    'mei_consideration_cents', v_o.mei_consideration_cents,
    'smallflags_qa_cents', v_o.smallflags_qa_cents,
    'smallflags_main_fee_cents', v_o.smallflags_main_fee_cents,
    'smallflags_total_remuneration_cents', v_o.smallflags_total_remuneration_cents,
    'total_monetary_funding_required_cents', v_o.total_monetary_funding_required_cents,
    'participation_value_cents', v_sched.ordinary_participation_value_cents,
    'acceptance_actor_id', coalesce(v_ace.linked_auth_user_id, v_o.registered_by),
    'acceptance_at', coalesce(v_ace.accepted_at, v_o.signed_at)));

  -- Proveniencia por REGISTRO CANONICO, nao por "veio do chamador".
  v_prov := pg_catalog.jsonb_build_object(
    'company_legal_name', 'site_company',
    'company_cnpj', 'site_company',
    'company_trade_name', 'site_company',
    'city', 'site_company',
    'uf', 'site_company',
    'nfse_taker_cnpj', 'site_company',
    'representative_full_name', 'site_representative',
    'representative_cpf', 'site_representative',
    'representative_role_title', 'site_representative',
    'representative_authority_status', 'site_representative',
    'execution_unit_id', 'site_unit',
    'execution_unit_name', 'site_unit',
    'execution_unit_city', 'site_unit',
    'execution_unit_uf', 'site_unit',
    'execution_unit_company_id', 'site_unit',
    'activity_description', 'commercial_activity_authority',
    'activity_code', 'commercial_activity_authority',
    'activity_catalog_id', 'commercial_activity_authority',
    'activity_source_hash', 'commercial_activity_authority',
    'participation_value_cents', 'contract_economics_authority',
    'economic_value_cents', 'contract_economics_authority',
    'mei_consideration_cents', 'contract_economics_authority',
    'smallflags_qa_cents', 'contract_economics_authority',
    'smallflags_main_fee_cents', 'contract_economics_authority',
    'smallflags_total_remuneration_cents', 'contract_economics_authority',
    'total_monetary_funding_required_cents', 'contract_economics_authority',
    'contract_economics_version', 'contract_economics_authority',
    'pricing_rule_version', 'contract_economics_authority',
    'master_agreement_id', 'master_agreement',
    'master_legal_document_id', 'master_agreement',
    'master_agreement_version', 'master_agreement',
    'master_document_hash', 'master_agreement',
    'acceptance_actor_id', 'legal_acceptance',
    'acceptance_at', 'legal_acceptance',
    'order_id', 'commercial_order',
    'region_id', 'commercial_order',
    'exclusivity_id', 'commercial_order',
    'niche_code', 'commercial_order',
    'nominal_quantity', 'commercial_order',
    'benefit_settlement_mode', 'commercial_order');

  -- Falha fechada nomeando CADA fato material ausente.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_snap ? v_campo) THEN
      v_faltam := v_faltam || v_campo;
    END IF;
  END LOOP;
  IF array_length(v_faltam, 1) >= 1 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'instrument_snapshot_material_fact_missing',
      'missing_fields', pg_catalog.to_jsonb(v_faltam),
      'template_code', v_t.template_code);
  END IF;

  -- Nenhum fato do snapshot pode ter vindo de fora das autoridades: toda chave
  -- material tem de ter proveniencia declarada.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_prov ? v_campo) THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'instrument_snapshot_provenance_undeclared',
        'field', v_campo);
    END IF;
  END LOOP;

  v_snap := v_snap || pg_catalog.jsonb_build_object(
    'instrument_template_code', v_t.template_code,
    'instrument_template_version', v_t.template_version,
    'instrument_template_date', v_t.template_date,
    'instrument_template_source_hash', v_t.source_hash,
    'field_provenance', v_prov);

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'template_id', v_t.id,
    'template_version', v_t.template_version,
    'template_date', v_t.template_date,
    'template_source_hash', v_t.source_hash,
    'snapshot', v_snap,
    'snapshot_hash',
      pg_catalog.encode(extensions.digest(v_snap::text, 'sha256'), 'hex'));
END;
$function$;

ALTER FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) TO service_role;

-- 2. Uma única transição NULL -> instrumento completo é a EMISSÃO, não uma
-- reescrita histórica. Depois dela todos os campos instrumentais ficam imutáveis.
CREATE OR REPLACE FUNCTION public.ceo_instrumento_imutavel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_primeiro_preenchimento boolean;
  v_build jsonb;
BEGIN
  IF OLD.signed_at IS NULL THEN
    RETURN NEW;
  END IF;

  v_primeiro_preenchimento :=
    OLD.instrument_code IS NULL
    AND OLD.instrument_template_id IS NULL
    AND OLD.instrument_template_version IS NULL
    AND OLD.instrument_template_hash IS NULL
    AND OLD.instrument_template_date IS NULL
    AND OLD.instrument_snapshot IS NULL
    AND OLD.instrument_snapshot_hash IS NULL
    AND NEW.instrument_code IS NOT NULL
    AND NEW.instrument_template_id IS NOT NULL
    AND NEW.instrument_template_version IS NOT NULL
    AND NEW.instrument_template_hash IS NOT NULL
    AND NEW.instrument_template_date IS NOT NULL
    AND NEW.instrument_snapshot IS NOT NULL
    AND NEW.instrument_snapshot_hash IS NOT NULL;

  IF v_primeiro_preenchimento THEN
    -- O preenchimento permitido tem de ser exatamente o snapshot que as
    -- autoridades do servidor constroem para este pedido e este modelo.
    v_build := public.commercial_build_instrument_snapshot(OLD.id, NEW.instrument_template_id);
    IF (v_build->>'ok')::boolean IS NOT TRUE
       OR NEW.instrument_template_version IS DISTINCT FROM v_build->>'template_version'
       OR NEW.instrument_template_date IS DISTINCT FROM (v_build->>'template_date')::date
       OR NEW.instrument_template_hash IS DISTINCT FROM v_build->>'template_source_hash'
       OR NEW.instrument_snapshot IS DISTINCT FROM v_build->'snapshot'
       OR NEW.instrument_snapshot_hash IS DISTINCT FROM v_build->>'snapshot_hash' THEN
      RAISE EXCEPTION 'instrumento_emissao_invalida: preenchimento nao corresponde as autoridades do servidor'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.instrument_snapshot IS DISTINCT FROM OLD.instrument_snapshot
     OR NEW.instrument_code IS DISTINCT FROM OLD.instrument_code
     OR NEW.instrument_template_id IS DISTINCT FROM OLD.instrument_template_id
     OR NEW.instrument_template_version IS DISTINCT FROM OLD.instrument_template_version
     OR NEW.instrument_template_hash IS DISTINCT FROM OLD.instrument_template_hash
     OR NEW.instrument_template_date IS DISTINCT FROM OLD.instrument_template_date
     OR NEW.instrument_snapshot_hash IS DISTINCT FROM OLD.instrument_snapshot_hash
     OR NEW.mei_consideration_cents IS DISTINCT FROM OLD.mei_consideration_cents
     OR NEW.smallflags_qa_cents IS DISTINCT FROM OLD.smallflags_qa_cents
     OR NEW.order_version IS DISTINCT FROM OLD.order_version
     OR NEW.document_hash IS DISTINCT FROM OLD.document_hash THEN
    RAISE EXCEPTION
      'instrumento assinado e imutavel: snapshot, identidade, versao, hash e decomposicao economica nao podem ser alterados apos signed_at'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

-- Trigger function não é RPC. Não precisa (nem deve) ser executável por cliente.
REVOKE EXECUTE ON FUNCTION public.ceo_instrumento_imutavel()
  FROM PUBLIC, anon, authenticated, service_role;

-- 3. Barreira estrutural. V3+ signed sem modelo signable nunca entra na tabela.
-- O instrumento NÃO pode vir pré-preenchido do caller; o emissor AFTER INSERT é
-- a única rotina que o individualiza a partir das autoridades persistidas.
CREATE OR REPLACE FUNCTION public.ceo_exigir_instrumento_quando_assinavel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_t public.commercial_instrument_templates%ROWTYPE;
BEGIN
  IF NEW.status <> 'signed'
     OR NEW.pricing_rule_version IS NULL
     OR NEW.pricing_rule_version < 3 THEN
    RETURN NEW;
  END IF;

  IF NEW.instrument_code IS NOT NULL
     OR NEW.instrument_template_id IS NOT NULL
     OR NEW.instrument_template_version IS NOT NULL
     OR NEW.instrument_template_hash IS NOT NULL
     OR NEW.instrument_template_date IS NOT NULL
     OR NEW.instrument_snapshot IS NOT NULL
     OR NEW.instrument_snapshot_hash IS NOT NULL THEN
    RAISE EXCEPTION 'instrumento_prepreenchido_nao_permitido: fatos instrumentais sao emitidos pelo servidor'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE lifecycle_status = 'signable'
     AND applies_to_fidelized = coalesce(NEW.fidelized, false);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'commercial_instrument_template_unavailable: fidelized=%',
      coalesce(NEW.fidelized, false)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.ceo_exigir_instrumento_quando_assinavel()
  FROM PUBLIC, anon, authenticated, service_role;

-- 4. Emissão automática após a linha existir. Qualquer falha do builder levanta
-- exceção e reverte também o INSERT original: pedido e instrumento são atômicos.
CREATE OR REPLACE FUNCTION public.ceo_emitir_instrumento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_t jsonb;
  v_b jsonb;
  v_code text;
BEGIN
  IF NEW.status <> 'signed'
     OR NEW.pricing_rule_version IS NULL
     OR NEW.pricing_rule_version < 3 THEN
    RETURN NEW;
  END IF;

  v_t := public.commercial_signable_instrument_template(coalesce(NEW.fidelized, false));
  IF (v_t->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'commercial_instrument_template_unavailable: fidelized=%',
      coalesce(NEW.fidelized, false)
      USING ERRCODE = 'check_violation';
  END IF;

  v_b := public.commercial_build_instrument_snapshot(
    NEW.id, (v_t->>'template_id')::uuid);
  IF (v_b->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'commercial_instrument_snapshot_unavailable: reason=%, detail=%',
      coalesce(v_b->>'reason', 'unknown'), v_b::text
      USING ERRCODE = 'check_violation';
  END IF;

  v_code := public.commercial_next_instrument_code();

  UPDATE public.commercial_exclusivity_orders
     SET instrument_code = v_code,
         instrument_template_id = (v_b->>'template_id')::uuid,
         instrument_template_version = v_b->>'template_version',
         instrument_template_hash = v_b->>'template_source_hash',
         instrument_template_date = (v_b->>'template_date')::date,
         instrument_snapshot = v_b->'snapshot',
         instrument_snapshot_hash = v_b->>'snapshot_hash'
   WHERE id = NEW.id;

  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.ceo_emitir_instrumento()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS ceo_emitir_instrumento ON public.commercial_exclusivity_orders;
CREATE TRIGGER ceo_emitir_instrumento
  AFTER INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_emitir_instrumento();

COMMENT ON FUNCTION public.ceo_emitir_instrumento() IS
  'Emite o instrumento de pedido v1.4+ na mesma transacao. Usa apenas modelo '
  'signable e fatos server-side; falha do snapshot reverte o pedido inteiro.';

-- 5. Portão público: erro de domínio determinístico ANTES da escrita.
CREATE OR REPLACE FUNCTION public.finalize_commercial_order_from_intent(p_intent_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg     jsonb;
  v_template jsonb;
  v_uid      uuid := auth.uid();
  v_i     public.commercial_checkout_intents%ROWTYPE;
  v_opp   public.commercial_opportunities%ROWTYPE;
  v_ace   public.legal_acceptances%ROWTYPE;
  v_doc   public.legal_documents%ROWTYPE;
  v_agree public.commercial_master_agreements%ROWTYPE;
  v_comp  public.site_partner_companies%ROWTYPE;
  v_nome  text;
  v_exist uuid;
  v_id    uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_i FROM public.commercial_checkout_intents
   WHERE id = p_intent_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_found');
  END IF;
  IF NOT public.m2_is_company_owner(v_i.company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  -- Idempotência: a mesma intenção já finalizada devolve o mesmo pedido.
  SELECT id INTO v_exist FROM public.commercial_exclusivity_orders
   WHERE checkout_intent_id = v_i.id AND status <> 'cancelled';
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'order_id', v_exist, 'intent_status', v_i.status);
  END IF;

  SELECT * INTO v_comp
    FROM public.site_partner_companies
   WHERE id = v_i.company_id
   FOR UPDATE;

  SELECT id INTO v_exist
    FROM public.commercial_exclusivity_orders
   WHERE exclusivity_id = v_i.exclusivity_id
     AND company_id = v_i.company_id
     AND status <> 'cancelled'
   LIMIT 1;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'company_already_contracted_in_exclusivity',
      'existing_order_id', v_exist);
  END IF;

  IF v_i.status <> 'awaiting_contract' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_awaiting_contract',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
  END IF;

  -- P0-C: contratação nova sob a autoridade v1.4 não pode chegar a `signed`
  -- enquanto não existir instrumento juridicamente liberado para a condição.
  -- A trigger estrutural repete o gate na inserção para fechar qualquer caminho
  -- futuro; este preflight dá ao chamador o erro de domínio determinístico.
  IF v_i.pricing_rule_version >= 3 THEN
    v_template := public.commercial_signable_instrument_template(v_i.fidelized);
    IF (v_template->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_template;
    END IF;
  END IF;

  -- ---- aceite exato: do titular, desta intenção, do contexto e tipo certos
  SELECT a.* INTO v_ace
    FROM public.legal_acceptances a
    JOIN public.legal_documents d ON d.id = a.legal_document_id
   WHERE a.subject_type = 'commercial_checkout_intent'
     AND a.subject_id = v_i.id
     AND a.commercial_checkout_intent_id = v_i.id
     AND a.context = 'commercial_contract'
     AND a.linked_auth_user_id = v_uid
     AND a.revoked_at IS NULL
     AND d.doc_type = 'commercial_order_terms'
     AND d.status = 'published'
     AND d.effective_from <= pg_catalog.now()
     AND (d.effective_to IS NULL OR d.effective_to > pg_catalog.now())
   ORDER BY a.accepted_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'terms_not_accepted');
  END IF;

  SELECT * INTO v_doc FROM public.legal_documents WHERE id = v_ace.legal_document_id;

  -- O aceite tem de ter acontecido DENTRO da reserva viva.
  IF v_ace.accepted_at > v_i.reserved_until THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'acceptance_outside_reservation');
  END IF;

  -- ---- acordo mestre vigente: obrigatório, e não fabricado aqui
  -- P0-1 PORTAO 4 de 4, AUTORITATIVO: mesma definicao unica de elegibilidade,
  -- agora COM LOCK. O FOR UPDATE acontece dentro do resolvedor, na transacao
  -- desta funcao, e e o que fecha a janela de corrida contra revogacao
  -- concorrente — comportamento provado por scripts/db-test/p01-master-race.sh.
  v_eleg := public.m2_master_agreement_eligibility(v_i.company_id, true);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
  END IF;
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE id = (v_eleg->>'master_agreement_id')::uuid;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  -- ---- oportunidade ainda reservada para ESTA intenção
  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = v_i.opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;
  IF v_opp.status <> 'reserved'
     OR v_opp.reserved_until IS NULL
     OR v_opp.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired',
                                         'opportunity_status', v_opp.status);
  END IF;

  -- v_comp já foi carregada com FOR UPDATE acima.

  -- Signatário: identidade canônica do titular ativo, não texto de formulário.
  SELECT m.full_name INTO v_nome FROM public.site_company_members m
   WHERE m.company_id = v_i.company_id AND m.auth_user_id = v_uid
     AND m.role = 'partner_owner' AND m.status = 'active';
  IF v_nome IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     contract_economics_version, mei_consideration_cents, smallflags_qa_cents,
     smallflags_main_fee_cents, smallflags_total_remuneration_cents,
     benefit_settlement_mode, mei_cash_funding_cents, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     status, expected_operation_start, registered_by,
     legal_acceptance_id, checkout_intent_id)
  VALUES
    (v_i.exclusivity_id, v_i.opportunity_id, v_i.company_id, v_agree.id, v_i.niche_code,
     v_i.region_id, v_i.nominal_quantity, v_i.pricing_rule_version, v_i.fidelized,
     v_i.currency,
     -- CÓPIA do instantâneo reservado, centavo a centavo.
     v_i.economic_value_cents,
     -- pool_bps e NULO sob a V2 e a intencao nao guarda bps algum: nao ha
     -- ponto-base honesto a gravar, e inventar um seria autoridade falsa.
     NULL::integer,
     v_i.user_pool_cents, v_i.bdflow_ops_investment_cents,
     -- A intenção é o snapshot da reserva. Copiamos também a decomposição
     -- v1.4 em vez de reconsultar a agenda no momento da finalização; assim
     -- nenhuma alteração futura da tabela de preços pode reprecificar uma
     -- reserva já aceita. O trigger ceo_aplicar_autoridade_v14 respeita
     -- snapshots que já trazem contract_economics_version.
     v_i.contract_economics_version,
     v_i.mei_consideration_cents, v_i.smallflags_qa_cents,
     v_i.smallflags_main_fee_cents, v_i.smallflags_total_remuneration_cents,
     v_i.benefit_settlement_mode, v_i.mei_cash_funding_cents,
     v_i.cash_user_pool_funding_cents,
     v_i.total_monetary_funding_required_cents,
     v_i.benefit_distribution_policy_version,
     v_doc.version,
     'bdflow:legal_acceptance/' || v_ace.id::text,
     v_doc.content_hash,
     v_ace.accepted_at, v_nome,
     'signed', (pg_catalog.now() + interval '30 days')::date, v_uid,
     v_ace.id, v_i.id)
  RETURNING id INTO v_id;

  -- A oportunidade sai da reserva e entra em pendência de pagamento, o mesmo
  -- estado canônico a que a venda manual sempre levou.
  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL,
         updated_at = pg_catalog.now()
   WHERE id = v_opp.id;

  UPDATE public.commercial_checkout_intents
     SET status = 'awaiting_payment_provider' WHERE id = v_i.id;

  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  SELECT v_comp.cnpj, r.uf, public.commercial_city_key(v_comp.city),
         v_i.niche_code, v_id
    FROM public.commercial_regions r WHERE r.id = v_i.region_id
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.finalized_by_owner', v_id, 'owner',
    pg_catalog.jsonb_build_object('intent_id', v_i.id,
                                  'legal_acceptance_id', v_ace.id,
                                  'master_agreement_id', v_agree.id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'order_id', v_id, 'intent_status', 'awaiting_payment_provider',
    'opportunity_status', 'payment_pending',
    'legal_acceptance_id', v_ace.id, 'document_version', v_doc.version,
    'content_hash', v_doc.content_hash,
    'economic_value_cents', v_i.economic_value_cents,
    'user_pool_cents', v_i.user_pool_cents,
    'bdflow_ops_investment_cents', v_i.bdflow_ops_investment_cents);
END;
$function$;

-- 6. Portão administrativo: mesma regra de signability E mesma elegibilidade
-- canônica do Master Agreement do fluxo público.
CREATE OR REPLACE FUNCTION public.admin_register_manual_commercial_order(p_opportunity_id uuid, p_company_id uuid, p_order_version text, p_signed_at timestamp with time zone, p_signatory_name text, p_expected_operation_start date, p_benefit_settlement_mode text, p_document_reference text DEFAULT NULL::text, p_document_hash text DEFAULT NULL::text, p_external_signature_ref text DEFAULT NULL::text, p_exclusivity_period_days integer DEFAULT 28)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg     jsonb;
  v_template jsonb;
  v_opp      public.commercial_opportunities%ROWTYPE;
  v_excl     public.commercial_exclusivities%ROWTYPE;
  v_company  public.site_partner_companies%ROWTYPE;
  v_agree    public.commercial_master_agreements%ROWTYPE;
  v_region   public.commercial_regions%ROWTYPE;
  v_existing public.commercial_exclusivity_orders%ROWTYPE;
  v_city     jsonb;
  v_city_key text;
  v_cnpj     text;
  v_fidel    boolean;
  v_pricing  jsonb;
  v_versao   integer;
  -- Valores COMO GRAVADOS, lidos de volta após o trigger da autoridade.
  v_eco_grav    bigint;
  v_pool_grav   bigint;
  v_bdflow_grav bigint;
  v_cash_grav   bigint;
  v_total_grav  bigint;
  v_econ_versao text;
  v_pool     bigint;
  v_bdflow   bigint;
  v_cash     bigint;
  v_id       uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- A ÚNICA escolha comercial aceita de fora. Preço, fidelidade, versão da
  -- tabela e forma de pagamento continuam derivados aqui.
  IF p_benefit_settlement_mode IS NULL
     OR p_benefit_settlement_mode NOT IN ('direct_benefits','cash') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_settlement_mode');
  END IF;

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signature_date');
  END IF;
  IF p_document_reference IS NULL AND p_document_hash IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_evidence_required');
  END IF;

  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = p_opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  SELECT * INTO v_existing FROM public.commercial_exclusivity_orders
   WHERE opportunity_id = p_opportunity_id AND status <> 'cancelled';
  IF FOUND THEN
    IF v_existing.company_id = p_company_id THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                           'order_id', v_existing.id);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_taken');
  END IF;

  SELECT * INTO v_excl FROM public.commercial_exclusivities
   WHERE id = v_opp.exclusivity_id;
  IF v_excl.status NOT IN ('forming','formed','start_scheduled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exclusivity_closed');
  END IF;

  SELECT * INTO v_company FROM public.site_partner_companies
   WHERE id = p_company_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_invalid');
  END IF;

  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.exclusivity_id = v_opp.exclusivity_id
                AND o.company_id = p_company_id AND o.status <> 'cancelled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_already_in_exclusivity');
  END IF;

  -- O caminho administrativo usa a MESMA definição canônica do fluxo público:
  -- status signed, documento master_agreement vinculado, empresa, versão e hash
  -- exatos, estado legal published/archived. p_lock=true preserva o P0-1.
  v_eleg := public.m2_master_agreement_eligibility(p_company_id, true);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
  END IF;
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE id = (v_eleg->>'master_agreement_id')::uuid;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  v_city := public.m2_resolve_company_fidelity_city(p_company_id, v_region.id);
  IF (v_city->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_city->>'reason');
  END IF;
  v_city_key := v_city->>'city_key';
  v_cnpj     := public.somente_digitos(v_company.cnpj);

  v_fidel := public.is_fidelized_context(
      v_cnpj, v_region.uf, v_company.city, v_opp.niche_code);

  v_pricing := public.calculate_niche_contract_pricing(v_opp.niche_code, v_fidel);
  IF (v_pricing->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_pricing->>'reason');
  END IF;

  v_versao := (v_pricing->>'pricing_rule_version')::int;
  IF v_versao >= 3 THEN
    v_template := public.commercial_signable_instrument_template(v_fidel);
    IF (v_template->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_template;
    END IF;
  END IF;
  v_pool   := (v_pricing->>'contractual_pool_cents')::bigint;
  v_bdflow := (v_pricing->>'bdflow_due_cents')::bigint;
  v_cash   := CASE WHEN p_benefit_settlement_mode = 'cash' THEN v_pool ELSE 0 END;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     benefit_settlement_mode, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     external_signature_ref, status,
     expected_operation_start, exclusivity_period_days, registered_by)
  VALUES
    (v_opp.exclusivity_id, v_opp.id, p_company_id, v_agree.id, v_opp.niche_code,
     v_region.id, v_opp.contracted_quantity,
     v_versao, v_fidel, 'BRL',
     (v_pricing->>'economic_value_cents')::bigint,
     -- NULL sob a V2: não existe ponto-base honesto, e inventar um seria
     -- gravar autoridade falsa só para satisfazer um formato antigo.
     CASE WHEN v_versao >= 2 THEN NULL ELSE (v_pricing->>'pool_bps')::int END,
     v_pool, v_bdflow,
     p_benefit_settlement_mode, v_cash, v_bdflow + v_cash,
     CASE WHEN v_versao >= 2 THEN 2 ELSE NULL END,
     pg_catalog.btrim(p_order_version),
     nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_document_hash,'')), ''),
     p_signed_at, pg_catalog.btrim(p_signatory_name),
     nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
     'signed',
     p_expected_operation_start, p_exclusivity_period_days, auth.uid())
  -- Lê de volta o que a AUTORIDADE gravou, não o que esta função supôs antes
  -- do trigger. Sob V1/V2 estes valores são idênticos aos pré-calculados.
  RETURNING id,
            economic_value_cents,
            contractual_pool_cents,
            bdflow_due_cents,
            cash_user_pool_funding_cents,
            total_monetary_funding_required_cents,
            contract_economics_version
       INTO v_id, v_eco_grav, v_pool_grav, v_bdflow_grav, v_cash_grav,
            v_total_grav, v_econ_versao;

  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL
   WHERE id = v_opp.id;

  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  VALUES (v_cnpj, v_region.uf, v_city_key, v_opp.niche_code, v_id)
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.manually_registered', v_id, 'admin',
    pg_catalog.jsonb_build_object(
      'pricing_rule_version', v_versao,
      'benefit_settlement_mode', p_benefit_settlement_mode,
      'payment_method', v_pricing->>'payment_method',
      'economic_value_cents', v_eco_grav,
      'contract_economics_version', v_econ_versao,
      'total_monetary_funding_required_cents', v_total_grav),
    NULL,
    pg_catalog.jsonb_build_object('opportunity_id', p_opportunity_id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'order_id', v_id,
    'pricing_rule_version', v_versao,
    'fidelized', v_fidel,
    'payment_method', v_pricing->>'payment_method',
    'benefit_settlement_mode', p_benefit_settlement_mode,
    'economic_value_cents', v_eco_grav,
    'user_pool_cents', v_pool_grav,
    'bdflow_ops_investment_cents', v_bdflow_grav,
    'cash_user_pool_funding_cents', v_cash_grav,
    'total_monetary_funding_required_cents', v_total_grav,
    -- NULL em pedido V1/V2: só a v1.4 tem rótulo legal de economia.
    'contract_economics_version', v_econ_versao);
END;
$function$;
