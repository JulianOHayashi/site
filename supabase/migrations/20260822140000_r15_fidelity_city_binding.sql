-- ============================================================================
-- R15 — Correção do vínculo geográfico da fidelidade
--
-- DEFEITO CORRIGIDO (provado em campo antes da correção)
-- ------------------------------------------------------------------
-- O R8 resolvia a cidade da fidelidade escolhendo a PRIMEIRA cidade ativa da
-- região comercial:
--
--     SELECT c.city_key FROM public.commercial_region_cities c
--      WHERE c.region_id = v_region.id AND c.is_active
--      ORDER BY c.city_name LIMIT 1;
--
-- Na única região semeada (Grande Vitória / ES) as cidades ativas são
-- Cariacica, Serra, Viana, Vila Velha e Vitória; a primeira por city_name é
-- CARIACICA. Executando as fixtures reais do R8 — seis empresas, todas com
-- cidade autoritativa "Vitória" — os seis registros de fidelidade nasceram
-- com city_key='cariacica', e a consequência foi verificada nos dois lados:
--
--     is_fidelized_context(cnpj,'ES','Vitória','supermarket')   -> false
--     is_fidelized_context(cnpj,'ES','Cariacica','supermarket') -> true
--
-- Ou seja: o fundador NÃO recebia a fidelidade na cidade em que de fato
-- opera, e a fidelidade passava a valer numa cidade onde nada foi contratado.
-- A chave assentada é CNPJ + cidade REAL da empresa + nicho.
--
-- CORREÇÃO
-- ------------------------------------------------------------------
-- 1. m2_resolve_company_fidelity_city: obtém a cidade autoritativa da empresa
--    em site_partner_companies, normaliza pela convenção já existente do
--    projeto (public.commercial_city_key: minúsculas, sem acentos, espaços
--    viram hífen) e EXIGE que a cidade normalizada pertença à região da
--    oportunidade. Falha fechada — nunca devolve uma cidade substituta.
-- 2. admin_register_manual_commercial_order passa a usar esse resolvedor e a
--    recusar a venda quando a cidade não puder ser resolvida.
-- 3. O CNPJ gravado na fidelidade passa por public.somente_digitos, alinhando
--    a ESCRITA com a LEITURA (is_fidelized_context já normalizava). Sem isso,
--    um CNPJ formatado gravaria uma chave que a leitura jamais encontraria —
--    m1_cnpj_valido aceita formatação, então isso era alcançável.
-- 4. A leitura da fidelidade na venda deixa de ser um EXISTS duplicado e
--    passa a ser a MESMA função de leitura pública do domínio,
--    is_fidelized_context, para que as duas não possam divergir de novo.
-- 5. Fidelidade não sobrevive ao pedido fundador cancelado (ver abaixo).
--
-- MIGRAÇÃO ADITIVA: nenhuma migração do M1 canônico ou do R0–R14 é reescrita.
-- CREATE OR REPLACE preserva os GRANTs já auditados das funções existentes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Resolvedor da cidade autoritativa da empresa dentro da região
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.m2_resolve_company_fidelity_city(
  p_company_id uuid,
  p_region_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_company public.site_partner_companies%ROWTYPE;
  v_uf      text;
  v_key     text;
  v_n       integer;
BEGIN
  SELECT * INTO v_company FROM public.site_partner_companies WHERE id = p_company_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_not_found');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.commercial_regions WHERE id = p_region_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'region_not_found');
  END IF;

  -- Cidade ausente ou só com espaços: falha fechada, sem substituto.
  v_key := public.commercial_city_key(v_company.city);
  IF v_key IS NULL OR pg_catalog.length(v_key) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_city_missing');
  END IF;

  IF NOT public.commercial_is_valid_uf(v_company.uf) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_uf_invalid');
  END IF;
  v_uf := pg_catalog.upper(pg_catalog.btrim(v_company.uf));

  -- A cidade REAL da empresa precisa pertencer à região da oportunidade.
  SELECT pg_catalog.count(*) INTO v_n
    FROM public.commercial_region_cities c
   WHERE c.region_id = p_region_id
     AND c.uf = v_uf
     AND c.city_key = v_key
     AND c.is_active;

  IF v_n = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'city_not_in_region');
  END IF;
  -- DEFESA EM PROFUNDIDADE: a baseline já impede a duplicidade por índice
  -- único (uf, city_key), então este ramo é inalcançável hoje. Ele existe
  -- para que, se a restrição algum dia cair, ambiguidade vire recusa — nunca
  -- escolha arbitrária. A suíte 910 prova a restrição que o torna inalcançável.
  IF v_n > 1 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'city_ambiguous');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'city_key', v_key, 'uf', v_uf, 'city_name', v_company.city);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m2_resolve_company_fidelity_city(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_resolve_company_fidelity_city(uuid,uuid)
  FROM anon, authenticated, service_role;

COMMENT ON FUNCTION public.m2_resolve_company_fidelity_city(uuid,uuid) IS
  'Resolve a cidade AUTORITATIVA da empresa (site_partner_companies) para a '
  'chave de cidade da região comercial. Falha fechada: nunca substitui a '
  'cidade da empresa pela primeira cidade da região.';

-- ----------------------------------------------------------------------------
-- 2. A fidelidade não sobrevive ao pedido fundador cancelado
--
-- O status 'cancelled' já é previsto no CHECK do pedido e o gatilho de
-- imutabilidade diz textualmente "Use cancelamento". Nenhuma RPC de
-- cancelamento existe ainda, e a política de cancelamento/estorno NÃO é
-- decidida aqui — inventá-la seria pior que registrá-la como pendente.
-- O que É inequívoco sob as regras já assentadas: um pedido cancelado não é
-- um engajamento comercial válido, logo não pode continuar fundando
-- fidelidade. A guarda vive na ÚNICA função de leitura do domínio, de modo
-- que qualquer política de cancelamento futura já nasça segura.
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_fidelity_records
  ADD CONSTRAINT cfr_pedido_fundador_fk
  FOREIGN KEY (established_by_order_id)
  REFERENCES public.commercial_exclusivity_orders (id);

CREATE OR REPLACE FUNCTION public.is_fidelized_context(
  p_cnpj text, p_uf text, p_city text, p_niche_code text
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.commercial_fidelity_records f
     WHERE f.cnpj = public.somente_digitos(p_cnpj)
       AND f.uf = pg_catalog.upper(pg_catalog.btrim(p_uf))
       AND f.city_key = public.commercial_city_key(p_city)
       AND f.niche_code = p_niche_code
       -- R15: pedido fundador cancelado não sustenta fidelidade futura.
       AND NOT EXISTS (
             SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.id = f.established_by_order_id
                AND o.status = 'cancelled'));
$$;

-- ----------------------------------------------------------------------------
-- 3. Venda manual: cidade autoritativa, chave normalizada, leitura única
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_register_manual_commercial_order(
  p_opportunity_id uuid,
  p_company_id     uuid,
  p_order_version  text,
  p_signed_at      timestamptz,
  p_signatory_name text,
  p_expected_operation_start date,
  p_document_reference text DEFAULT NULL,
  p_document_hash      text DEFAULT NULL,
  p_external_signature_ref text DEFAULT NULL,
  p_exclusivity_period_days integer DEFAULT 28
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
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
  v_id       uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signature_date');
  END IF;
  IF p_document_reference IS NULL AND p_document_hash IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'document_evidence_required');
  END IF;

  -- Trava a oportunidade: vendas concorrentes do mesmo nicho serializam.
  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = p_opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  -- Idempotência: oportunidade já vendida à MESMA empresa devolve o pedido.
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

  -- Um CNPJ ocupa no máximo um nicho na mesma exclusividade.
  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.exclusivity_id = v_opp.exclusivity_id
                AND o.company_id = p_company_id AND o.status <> 'cancelled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_already_in_exclusivity');
  END IF;

  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = p_company_id AND status = 'signed';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  -- R15: cidade AUTORITATIVA da empresa, validada contra a região. Falha
  -- fechada — nenhuma cidade substituta, nenhuma primeira-cidade-da-região.
  v_city := public.m2_resolve_company_fidelity_city(p_company_id, v_region.id);
  IF (v_city->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
                                         'reason', v_city->>'reason');
  END IF;
  v_city_key := v_city->>'city_key';
  v_cnpj     := public.somente_digitos(v_company.cnpj);

  -- LEITURA ÚNICA do domínio: a mesma função que o resto do sistema usa.
  v_fidel := public.is_fidelized_context(
      v_cnpj, v_region.uf, v_company.city, v_opp.niche_code);

  -- PREÇO AUTORITATIVO DO SERVIDOR: o chamador não envia valor algum.
  v_pricing := public.calculate_niche_contract_pricing(v_opp.niche_code, v_fidel);
  IF (v_pricing->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
                                         'reason', v_pricing->>'reason');
  END IF;

  INSERT INTO public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, niche_code,
     region_id, nominal_quantity, pricing_rule_version, fidelized, currency,
     economic_value_cents, pool_bps, contractual_pool_cents, bdflow_due_cents,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     external_signature_ref, status,
     expected_operation_start, exclusivity_period_days, registered_by)
  VALUES
    (v_opp.exclusivity_id, v_opp.id, p_company_id, v_agree.id, v_opp.niche_code,
     v_region.id, v_opp.contracted_quantity,
     (v_pricing->>'pricing_rule_version')::int, v_fidel, 'BRL',
     (v_pricing->>'economic_value_cents')::bigint,
     (v_pricing->>'pool_bps')::int,
     (v_pricing->>'contractual_pool_cents')::bigint,
     (v_pricing->>'bdflow_due_cents')::bigint,
     pg_catalog.btrim(p_order_version),
     nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_document_hash,'')), ''),
     p_signed_at, pg_catalog.btrim(p_signatory_name),
     nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
     'signed',
     p_expected_operation_start, p_exclusivity_period_days, auth.uid())
  RETURNING id INTO v_id;

  -- A oportunidade passa a aguardar a confirmação do valor devido.
  UPDATE public.commercial_opportunities
     SET status = 'payment_pending', reserved_until = NULL
   WHERE id = v_opp.id;

  -- O primeiro contrato do contexto estabelece a fidelidade dos próximos.
  -- Chave gravada EXATAMENTE como a leitura a procura.
  INSERT INTO public.commercial_fidelity_records
    (cnpj, uf, city_key, niche_code, established_by_order_id)
  VALUES (v_cnpj, v_region.uf, v_city_key, v_opp.niche_code, v_id)
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.manually_registered', v_id, 'admin',
    pg_catalog.jsonb_build_object(
      'company_id', p_company_id, 'niche_code', v_opp.niche_code,
      'city_key', v_city_key,
      'economic_value_cents', (v_pricing->>'economic_value_cents')::bigint,
      'bdflow_due_cents', (v_pricing->>'bdflow_due_cents')::bigint,
      'fidelized', v_fidel));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'order_id', v_id,
    'niche_code', v_opp.niche_code, 'fidelized', v_fidel,
    'city_key', v_city_key,
    'economic_value_cents', (v_pricing->>'economic_value_cents')::bigint,
    'contractual_pool_cents', (v_pricing->>'contractual_pool_cents')::bigint,
    'bdflow_due_cents', (v_pricing->>'bdflow_due_cents')::bigint);
END;
$$;
