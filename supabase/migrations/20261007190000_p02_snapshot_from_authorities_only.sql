-- ============================================================================
-- P0-2 — O SNAPSHOT PASSA A VIR SÓ DE REGISTRO PERSISTIDO E VALIDADO
--
-- `p_facts_supplied` SAI da autoridade de produção. Fato material jurídico não
-- pode chegar como objeto JSON arbitrário no momento da finalização: um JSON
-- vindo do navegador não vira substância legal.
--
-- A função antiga de três argumentos é REMOVIDA, não deixada ao lado. Deixá-la
-- viva manteria a porta aberta: bastaria chamar a versão antiga.
--
-- Agora cada fato material tem uma fonte canônica persistida ANTES da
-- finalização, e a proveniência no snapshot nomeia qual registro respondeu por
-- cada um:
--
--   site_company .................. razão social, CNPJ, nome fantasia, cidade, UF
--   site_unit ..................... unidade de execução, nome, cidade, UF
--   site_representative ........... representante, CPF, cargo, autoridade
--   contract_economics_authority .. economia congelada e valor da participação
--   commercial_activity_authority . descrição da atividade contratada
--   master_agreement .............. Mestre, documento canônico, versão, hash
--   legal_acceptance .............. ator e momento do aceite
--   commercial_order .............. identidade, nicho, quantidade, liquidação
--
-- A descrição da atividade continua BLOQUEADA em produção: o catálogo não tem
-- linha aprovada, então o construtor falha fechado com
-- `commercial_activity_description_unavailable`.
--
-- Sem push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calculate_niche_contract_pricing(p_niche_code text, p_fidelized boolean, p_pricing_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_rule      public.commercial_pricing_rules%ROWTYPE;
  v_qty       integer;
  v_economic  bigint;
  v_bps       integer;
  v_pool      bigint;
  v_cat       text;
  v_ratio     public.commercial_pool_share_ratios%ROWTYPE;
  v_sched     public.commercial_pricing_schedule%ROWTYPE;
  v_disp_pool text := NULL;
  v_disp_bdf  text := NULL;
BEGIN
  IF p_pricing_version IS NULL THEN
    SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE status = 'active';
  ELSE
    SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE version = p_pricing_version;
  END IF;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  SELECT contracted_quantity INTO v_qty
    FROM public.commercial_niches WHERE code = p_niche_code AND is_active;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_niche');
  END IF;

  -- Seis posições canônicas: supermercado usa a matriz de supermercado; os
  -- outros cinco usam a comum. OUTROS não é categorizado aqui de propósito —
  -- a fonte congelada não estabelece sua categoria de preço.
  v_cat := CASE WHEN p_niche_code = 'supermarket' THEN 'supermarket' ELSE 'common' END;

  -- -------------------------------------------------------------------------
  -- v1.4: tabela determinística. Falha fechada se a combinação não existir,
  -- em vez de cair numa fórmula que produziria um valor não contratado.
  -- -------------------------------------------------------------------------
  IF v_rule.pool_precision_model = 'explicit_schedule' THEN
    SELECT * INTO v_sched FROM public.commercial_pricing_schedule
      WHERE pricing_rule_version = v_rule.version
        AND commercial_category = v_cat
        AND fidelized = p_fidelized;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_schedule_missing',
        'pricing_rule_version', v_rule.version, 'commercial_category', v_cat,
        'fidelized', p_fidelized);
    END IF;

    -- CONTRATO DE RETORNO PRESERVADO. As chaves abaixo sao as mesmas que os
    -- consumidores ja leem (create_commercial_checkout_intent,
    -- admin_register_manual_commercial_order, preco publico). A v1.4 apenas
    -- ACRESCENTA a decomposicao; renomear qualquer chave existente quebraria
    -- os consumidores, inclusive payment_method, que e NOT NULL no destino.
    RETURN pg_catalog.jsonb_build_object(
      'ok', true,
      'pricing_rule_version', v_rule.version,
      'pool_precision_model', v_rule.pool_precision_model,
      'niche_code', p_niche_code,
      'niche_category', v_cat,
      'nominal_quantity', v_qty,
      'fidelized', p_fidelized,
      'currency', 'BRL',
      -- Sem pontos-base no modelo de tabela: nao ha razao honesta a declarar.
      'pool_bps', NULL::integer,
      'display_pool_percent', NULL::text,
      'display_bdflow_percent', NULL::text,
      'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
      -- Acrescimos da v1.4.
      'contract_economics_version', v_sched.contract_economics_version,
      'economic_value_cents', v_sched.economic_value_cents,
      -- Campos de compatibilidade preservados, de modo que
      -- economic_value_cents = contractual_pool_cents + bdflow_due_cents
      -- continue valendo. ATENÇÃO: sob v1.4, contractual_pool_cents NÃO é
      -- "dinheiro devido aos MEIs" — ele contém a QA, que é da SmallFlags.
      'contractual_pool_cents',
        v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents,
      'bdflow_due_cents', v_sched.smallflags_main_fee_cents,
      -- Decomposição explícita da v1.4.
      'mei_consideration_cents', v_sched.mei_consideration_cents,
      'smallflags_qa_cents', v_sched.smallflags_qa_cents,
      'smallflags_main_fee_cents', v_sched.smallflags_main_fee_cents,
      'smallflags_total_remuneration_cents', v_sched.smallflags_total_remuneration_cents,
      -- Valor de UMA participacao ordinaria, lido da propria autoridade. A
      -- fidelizacao nao o altera (clausula 6.7): a diferenca incide sobre a
      -- parcela operacional principal da SmallFlags.
      'ordinary_participation_value_cents', v_sched.ordinary_participation_value_cents
    );
  END IF;

  -- -------------------------------------------------------------------------
  -- V1 e V2: comportamento original, intacto.
  -- -------------------------------------------------------------------------
  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  IF v_rule.pool_precision_model = 'exact_ratio' THEN
    SELECT * INTO v_ratio FROM public.commercial_pool_share_ratios
      WHERE pricing_rule_version = v_rule.version AND niche_category = v_cat;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pool_ratio_unavailable');
    END IF;
    v_pool := (v_economic * v_ratio.pool_numerator) / v_ratio.pool_denominator;
    v_disp_pool := v_ratio.display_pool_percent;
    v_disp_bdf  := v_ratio.display_bdflow_percent;
  ELSE
    v_bps := CASE WHEN v_cat = 'supermarket'
                  THEN v_rule.pool_bps_supermarket ELSE v_rule.pool_bps_common END;
    v_pool := (v_economic * v_bps) / 10000;
  END IF;

  -- Contrato V1/V2 reproduzido LITERALMENTE, chave por chave.
  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'pricing_rule_version', v_rule.version,
    'pool_precision_model', v_rule.pool_precision_model,
    'niche_code', p_niche_code,
    'niche_category', v_cat,
    'nominal_quantity', v_qty,
    'fidelized', p_fidelized,
    'currency', 'BRL',
    'economic_value_cents', v_economic,
    'pool_bps', v_bps,
    'contractual_pool_cents', v_pool,
    'bdflow_due_cents', v_economic - v_pool,
    'display_pool_percent', v_disp_pool,
    'display_bdflow_percent', v_disp_bdf,
    'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END);
END;
$function$;

-- A versão de três argumentos é REMOVIDA: enquanto existir, basta chamá-la para
-- contornar a regra.
DROP FUNCTION IF EXISTS public.commercial_build_instrument_snapshot(uuid, uuid, jsonb);

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
  IF v_o.nfse_taker_cnpj IS DISTINCT FROM v_c.cnpj THEN
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
GRANT  EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid)
  TO service_role;

COMMENT ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) IS
  'Monta o snapshot individualizado SOMENTE a partir de registros persistidos e '
  'validados no servidor. NAO aceita fato de chamador: a versao de tres '
  'argumentos com p_facts_supplied foi removida. A proveniencia nomeia o '
  'registro canonico responsavel por cada fato.';

-- O aceite jurídico exige unidade de execução validada. Sem isso o titular
-- assinaria um instrumento cujo local de execução ninguém escolheu.
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_aceite_exige_unidade
  CHECK (status NOT IN ('awaiting_payment_provider', 'paid')
         OR execution_unit_id IS NOT NULL) NOT VALID;

-- ---------------------------------------------------------------------------
-- A lista de fatos exigidos do modelo v1.4 é realinhada aos nomes que as
-- autoridades agora produzem. O campo genérico `activity_location` sai: ele foi
-- substituído pela unidade canônica, que é mais forte — identidade de registro,
-- com empresa e situação verificáveis, em vez de texto livre de localização.
-- ---------------------------------------------------------------------------
UPDATE public.commercial_instrument_templates
   SET required_snapshot_fields = ARRAY[
     'company_legal_name','company_cnpj','company_trade_name',
     'representative_full_name','representative_cpf','representative_role_title',
     'representative_authority_status',
     'city','uf','region_id','exclusivity_id',
     'nfse_taker_cnpj',
     'execution_unit_id','execution_unit_name','execution_unit_city',
     'execution_unit_uf','execution_unit_company_id',
     'activity_description','activity_code',
     'niche_code','nominal_quantity','benefit_settlement_mode',
     'master_agreement_id','master_legal_document_id','master_agreement_version',
     'master_document_hash','order_id','pricing_rule_version',
     'contract_economics_version','economic_value_cents',
     'mei_consideration_cents','smallflags_qa_cents','smallflags_main_fee_cents',
     'smallflags_total_remuneration_cents',
     'total_monetary_funding_required_cents','participation_value_cents',
     'acceptance_actor_id','acceptance_at'
   ]
 WHERE template_code = 'SF-MINUTA-PRESENCIAL-v1.4';
