-- ============================================================================
-- CONTRATOS V2 — PUBLICIDADE VISUAL EM VEÍCULOS (BANDEIRA SOBRE O TETO)
-- Infraestrutura PREPARATÓRIA, aditiva e fail-closed.
--
-- NÃO publica Acordo Mestre nem Termos do Pedido, NÃO cria modelo de
-- instrumento, NÃO promove a v1.4 (continua draft), NÃO cria especificação
-- técnica aprovada, NÃO cria aceite. Sem push, deploy ou execução remota.
--
-- 1. commercial_advertising_specs: autoridade versionada da especificação
--    técnica da peça publicitária (anexo técnico). Nasce VAZIA. Uma linha só
--    pode ser 'approved' com responsável técnico, registro profissional e hash
--    do laudo; nasce sempre draft; aprovada, é imutável (só pode ser
--    arquivada, sem alterar nenhum outro campo). No máximo uma
--    aprovada por modalidade. Nenhuma RPC aprova: exige ato administrativo
--    deliberado, como a promoção de modelo de instrumento.
-- 2. commercial_instrument_templates ganha `advertising_modality` e
--    `requires_advertising_spec` (default false). A v1.4 fica com false e o
--    comportamento dela não muda.
-- 3. commercial_order_effective_activity(order): posição × atividade efetiva
--    lidas SÓ dos snapshots imutáveis do pedido (nicho, ou
--    'segment:'||classificação congelada). Nome comercial nunca é identidade.
-- 4. commercial_build_instrument_snapshot: quando o modelo exige
--    especificação, acrescenta modalidade, especificação aprovada (código,
--    versão, hash, dimensões de referência da arte), região, número da
--    exclusividade, posição, atividade efetiva, fidelização e prazo, todos com
--    procedência declarada. Sem especificação aprovada:
--    commercial_advertising_spec_not_approved. O bloqueio D9 (segmento e
--    Outros) permanece ANTES deste ponto, inalterado.
-- ============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Autoridade da especificação técnica
-- ---------------------------------------------------------------------------
CREATE TABLE public.commercial_advertising_specs (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  spec_code                     text NOT NULL,
  spec_version                  text NOT NULL,
  modality                      text NOT NULL,
  -- Dimensões de REFERÊNCIA da arte (não do conjunto instalado).
  artwork_reference_width_mm    integer NOT NULL,
  artwork_reference_height_mm   integer NOT NULL,
  -- SHA-256 do anexo técnico (documento) desta versão.
  source_hash                   text NOT NULL,
  lifecycle_status              text NOT NULL DEFAULT 'draft',
  technical_responsible_name    text,
  technical_responsible_registration text,
  technical_report_hash         text,
  approved_by                   uuid,
  approved_at                   timestamptz,
  archived_at                   timestamptz,
  notes                         text,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cas_modality_valida
    CHECK (modality IN ('vehicle_roof_visual_flag')),
  CONSTRAINT cas_lifecycle_valido
    CHECK (lifecycle_status IN ('draft', 'approved', 'archived')),
  CONSTRAINT cas_dimensoes_positivas
    CHECK (artwork_reference_width_mm > 0 AND artwork_reference_height_mm > 0),
  CONSTRAINT cas_source_hash_sha256 CHECK (source_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cas_versao_nao_vazia CHECK (length(btrim(spec_version)) > 0),
  CONSTRAINT cas_aprovacao_completa CHECK (
    lifecycle_status = 'draft'
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL
        AND length(btrim(coalesce(technical_responsible_name, ''))) > 0
        AND length(btrim(coalesce(technical_responsible_registration, ''))) > 0
        AND coalesce(technical_report_hash, '') ~ '^[0-9a-f]{64}$')),
  CONSTRAINT cas_arquivo_coerente CHECK (
    (lifecycle_status = 'archived') = (archived_at IS NOT NULL)),
  CONSTRAINT cas_codigo_versao_unico UNIQUE (spec_code, spec_version)
);
CREATE UNIQUE INDEX cas_uma_aprovada_por_modalidade_uidx
  ON public.commercial_advertising_specs (modality)
  WHERE lifecycle_status = 'approved';

ALTER TABLE public.commercial_advertising_specs ENABLE ROW LEVEL SECURITY;
-- Os privilégios padrão do schema public (Production: postgres concede
-- arwdDxtm a service_role) dariam INSERT/UPDATE/DELETE/TRUNCATE ao
-- service_role, que ignora RLS. Esta autoridade só é LIDA pelo servidor:
-- revoga tudo de todos e concede apenas SELECT ao service_role.
REVOKE ALL ON public.commercial_advertising_specs FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_advertising_specs TO service_role;

COMMENT ON TABLE public.commercial_advertising_specs IS
  'Especificacao tecnica versionada da peca publicitaria (anexo tecnico). '
  'Nasce vazia. approved exige responsavel tecnico, registro e hash do laudo; '
  'aprovada e imutavel (so arquiva). Dimensoes sao REFERENCIA da arte, nao '
  'homologacao do conjunto instalado.';

-- Máquina de estados (única fonte da garantia; nenhuma RPC a contorna):
--   INSERT               -> só 'draft' (aprovar é sempre uma TRANSIÇÃO)
--   draft    -> draft    edição livre, exceto id e created_at
--   draft    -> approved ato administrativo; cas_aprovacao_completa valida
--   approved -> archived to_jsonb(NEW) = to_jsonb(OLD) excluídos SOMENTE
--                        lifecycle_status e archived_at; archived_at não
--                        anterior a approved_at
--   draft    -> archived recusado (rascunho nunca aprovado é apagado)
--   approved -> draft/approved, archived -> * : recusados
--   DELETE               -> só 'draft'; TRUNCATE: gatilho de instrução abaixo
--
-- Por que to_jsonb: a comparação cobre TODAS as colunas, inclusive as que
-- forem acrescentadas no futuro (falha fechada: coluna nova nasce protegida).
-- Tipos atuais: uuid e text viram string JSON exata; integer vira número
-- (igualdade numérica exata); timestamptz vira string ISO 8601 com
-- microssegundos, renderizada para OLD e NEW na MESMA sessão (mesmo
-- TimeZone), logo instantes iguais geram texto igual e qualquer diferença,
-- até 1 µs, gera texto diferente; NULL vira JSON null, distinto de ''.
-- `jsonb - text` remove só a chave nomeada. IS DISTINCT FROM em jsonb compara
-- estrutura e valores, sem depender da ordem das chaves.
CREATE FUNCTION public.commercial_advertising_specs_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.lifecycle_status IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'advertising_spec_transicao_invalida: especificacao nasce draft (recebido %)',
        NEW.lifecycle_status;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.lifecycle_status IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'advertising_spec_imutavel: % nao pode ser apagada', OLD.lifecycle_status;
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE. Identidade primária e auditoria nunca mudam, em nenhum estado.
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'advertising_spec_imutavel: id e created_at nao podem ser alterados';
  END IF;

  IF OLD.lifecycle_status = 'archived' THEN
    RAISE EXCEPTION 'advertising_spec_imutavel: versao arquivada';
  END IF;

  IF OLD.lifecycle_status = 'approved' THEN
    IF NEW.lifecycle_status IS DISTINCT FROM 'archived' THEN
      RAISE EXCEPTION 'advertising_spec_imutavel: versao aprovada so pode ser arquivada';
    END IF;
    IF (to_jsonb(NEW) - 'lifecycle_status' - 'archived_at')
         IS DISTINCT FROM
       (to_jsonb(OLD) - 'lifecycle_status' - 'archived_at') THEN
      RAISE EXCEPTION 'advertising_spec_imutavel: arquivamento so altera lifecycle_status e archived_at';
    END IF;
    IF NEW.archived_at < OLD.approved_at THEN
      RAISE EXCEPTION 'advertising_spec_transicao_invalida: arquivamento anterior a aprovacao';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.lifecycle_status = 'draft' THEN
    IF NEW.lifecycle_status IS NULL OR NEW.lifecycle_status NOT IN ('draft', 'approved') THEN
      RAISE EXCEPTION 'advertising_spec_transicao_invalida: rascunho so permanece draft ou e aprovado (recebido %)',
        NEW.lifecycle_status;
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'advertising_spec_transicao_invalida: estado de origem desconhecido %', OLD.lifecycle_status;
END $$;
REVOKE ALL ON FUNCTION public.commercial_advertising_specs_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cas_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_advertising_specs
  FOR EACH ROW EXECUTE FUNCTION public.commercial_advertising_specs_protect();

-- TRUNCATE não dispara gatilho de linha: recusa se apagaria versão aprovada
-- ou arquivada (vale também para o dono da tabela).
CREATE FUNCTION public.commercial_advertising_specs_protect_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.commercial_advertising_specs
              WHERE lifecycle_status IS DISTINCT FROM 'draft') THEN
    RAISE EXCEPTION 'advertising_spec_imutavel: TRUNCATE apagaria versao aprovada ou arquivada';
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.commercial_advertising_specs_protect_truncate() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cas_protect_truncate
  BEFORE TRUNCATE ON public.commercial_advertising_specs
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_advertising_specs_protect_truncate();

-- ---------------------------------------------------------------------------
-- 2. Modelos de instrumento: modalidade e exigência de especificação
-- ---------------------------------------------------------------------------
ALTER TABLE public.commercial_instrument_templates
  ADD COLUMN advertising_modality text,
  ADD COLUMN requires_advertising_spec boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT cit_modalidade_valida
    CHECK (advertising_modality IS NULL OR advertising_modality IN ('vehicle_roof_visual_flag')),
  ADD CONSTRAINT cit_especificacao_exige_modalidade
    CHECK (NOT requires_advertising_spec OR advertising_modality IS NOT NULL);

COMMENT ON COLUMN public.commercial_instrument_templates.requires_advertising_spec IS
  'Modelo V2 (publicidade visual em veiculos): o snapshot so e emitido com '
  'especificacao tecnica APROVADA para a modalidade. v1.4: false.';

-- ---------------------------------------------------------------------------
-- 3. Posição × atividade efetiva, só dos snapshots imutáveis do pedido
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.commercial_order_effective_activity(p_order_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT CASE
           WHEN o.segment_id IS NULL THEN pg_catalog.jsonb_build_object(
             'position_code', o.niche_code, 'kind', 'niche',
             'identity', o.niche_code)
           ELSE pg_catalog.jsonb_build_object(
             'position_code', o.niche_code, 'kind', 'segment',
             'identity', 'segment:' || o.segment_classification_snapshot,
             'segment_code', o.segment_code_snapshot,
             'segment_name', o.segment_name_snapshot,
             'segment_classification', o.segment_classification_snapshot)
         END
    FROM public.commercial_exclusivity_orders o
   WHERE o.id = p_order_id;
$$;
REVOKE ALL ON FUNCTION public.commercial_order_effective_activity(uuid) FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION public.commercial_order_effective_activity(uuid) IS
  'Posicao e atividade efetiva do pedido a partir dos snapshots congelados. '
  'Dois nomes comerciais da mesma classificacao sao a mesma atividade.';

-- ---------------------------------------------------------------------------
-- 4. Construtor do snapshot: acréscimo V2, condicionado ao modelo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot(p_order_id uuid, p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
  v_spec   public.commercial_advertising_specs%ROWTYPE;
  v_reg    public.commercial_regions%ROWTYPE;
  v_exc    public.commercial_exclusivities%ROWTYPE;
  v_ativ_ef jsonb;
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

  -- D9: a minuta vigente não identifica posição × segmento nem tem atividade
  -- contratada por segmento. Até a revisão jurídica, pedido com segmento (ou
  -- na posição Outros) não individualiza instrumento — falha fechado.
  IF v_o.segment_id IS NOT NULL OR v_o.niche_code = 'others' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_segment_activity_unavailable',
      'niche_code', v_o.niche_code,
      'segment_code', v_o.segment_code_snapshot);
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

  -- ---- V2 (publicidade visual em veiculos): SO para modelo que exige
  -- especificacao tecnica. O modelo v1.4 nao exige e segue identico.
  -- Sem especificacao APROVADA para a modalidade, falha fechada.
  IF v_t.requires_advertising_spec THEN
    SELECT * INTO v_spec FROM public.commercial_advertising_specs
     WHERE modality = v_t.advertising_modality
       AND lifecycle_status = 'approved';
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'commercial_advertising_spec_not_approved',
        'modality', v_t.advertising_modality, 'template_code', v_t.template_code);
    END IF;
    SELECT * INTO v_reg FROM public.commercial_regions WHERE id = v_o.region_id;
    SELECT * INTO v_exc FROM public.commercial_exclusivities WHERE id = v_o.exclusivity_id;
    v_ativ_ef := public.commercial_order_effective_activity(v_o.id);

    v_snap := v_snap || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'advertising_modality', v_spec.modality,
      'advertising_spec_id', v_spec.id,
      'advertising_spec_code', v_spec.spec_code,
      'advertising_spec_version', v_spec.spec_version,
      'advertising_spec_source_hash', v_spec.source_hash,
      'artwork_reference_width_mm', v_spec.artwork_reference_width_mm,
      'artwork_reference_height_mm', v_spec.artwork_reference_height_mm,
      'region_name', v_reg.name,
      'region_uf', v_reg.uf,
      'exclusivity_sequence_number', v_exc.sequence_number,
      'position_code', v_ativ_ef->>'position_code',
      'effective_activity_kind', v_ativ_ef->>'kind',
      'effective_activity_identity', v_ativ_ef->>'identity',
      'fidelized', v_o.fidelized,
      'exclusivity_period_days', v_o.exclusivity_period_days,
      'expected_operation_start', v_o.expected_operation_start));

    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'advertising_modality', 'advertising_spec_authority',
      'advertising_spec_id', 'advertising_spec_authority',
      'advertising_spec_code', 'advertising_spec_authority',
      'advertising_spec_version', 'advertising_spec_authority',
      'advertising_spec_source_hash', 'advertising_spec_authority',
      'artwork_reference_width_mm', 'advertising_spec_authority',
      'artwork_reference_height_mm', 'advertising_spec_authority',
      'region_name', 'commercial_region',
      'region_uf', 'commercial_region',
      'exclusivity_sequence_number', 'commercial_exclusivity',
      'position_code', 'commercial_order',
      'effective_activity_kind', 'commercial_order',
      'effective_activity_identity', 'commercial_order',
      'fidelized', 'commercial_order',
      'exclusivity_period_days', 'commercial_order',
      'expected_operation_start', 'commercial_order');
  END IF;

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

COMMIT;
