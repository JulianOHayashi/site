-- ============================================================================
-- P0-2 — AS FONTES CANÔNICAS DOS FATOS MATERIAIS
--
-- Os quatro fatos que o relatório anterior apontou como sem fonte canônica
-- passam a ter autoridade de servidor. Nenhum deles chega mais por entrada
-- arbitrária de chamador.
--
--   1. valor da participação ordinária → autoridade de economia contratual
--   2. tomador de NFS-e ............... → CNPJ da contratante, persistido
--   3. local de execução .............. → unidade canônica escolhida e validada
--   4. descrição da atividade ......... → catálogo próprio, SEM linha aprovada
--
-- O item 4 continua BLOQUEADO de propósito: a infraestrutura existe, e nenhuma
-- linha de produção nasce aprovada. Produção falha fechada com
-- `commercial_activity_description_unavailable` até a redação legal final
-- chegar. O nome de exibição do nicho NÃO é usado como se fosse a atividade
-- contratada: o instrumento congelado tem campo material próprio para
-- "Atividade contratada e local de execução", e nicho não é autoridade sobre
-- ele.
--
-- OUTROS segue dormente, e agora também fora do catálogo de atividades.
--
-- Sem push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. VALOR DA PARTICIPAÇÃO ORDINÁRIA — na autoridade de economia contratual
--
-- R$ 141,99 é fato contratual da SF-v1.4, não constante de interface nem
-- derivação oportunista no momento da finalização. Fica ao lado dos outros
-- centavos congelados, atrelado a pricing_rule_version 3 e
-- contract_economics_version 'SF-v1.4', e é dali que todo snapshot o lê.
--
-- Conferência que fecha dos dois lados: 7 participações × 141,99 = 993,93, e
-- 993,93 é exatamente a contraprestação por MEI completo calculada a partir de
-- mei_consideration_cents / 84. As duas contas vêm de origens independentes.
-- ---------------------------------------------------------------------------

ALTER TABLE public.commercial_pricing_schedule
  ADD COLUMN IF NOT EXISTS ordinary_participation_value_cents bigint;

COMMENT ON COLUMN public.commercial_pricing_schedule.ordinary_participation_value_cents IS
  'Valor economico de UMA participacao ordinaria, em centavos inteiros. '
  'SF-v1.4: 14199 (R$ 141,99), conforme a clausula 6.2 do Acordo Mestre. Unica '
  'fonte do valor: nao duplicar em RPC, UI nem codigo de provisionamento.';

UPDATE public.commercial_pricing_schedule
   SET ordinary_participation_value_cents = 14199
 WHERE pricing_rule_version = 3
   AND contract_economics_version = 'SF-v1.4'
   AND ordinary_participation_value_cents IS DISTINCT FROM 14199;

-- A fidelização NÃO reduz o valor da participação (cláusula 6.7): a diferença
-- entre fidelizado e não fidelizado incide sobre a parcela operacional
-- principal da SmallFlags. Logo as quatro linhas da v1.4 têm o MESMO valor.
ALTER TABLE public.commercial_pricing_schedule
  ADD CONSTRAINT cps_participacao_positiva
  CHECK (ordinary_participation_value_cents IS NULL
         OR ordinary_participation_value_cents > 0);

-- ---------------------------------------------------------------------------
-- 2. CATÁLOGO DE ATIVIDADE CONTRATADA — infraestrutura sem linha aprovada
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.commercial_contract_activity_catalog (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  catalog_version       text NOT NULL,
  niche_code            text NOT NULL,
  activity_code         text NOT NULL,
  activity_description  text NOT NULL,
  legal_template_version text NOT NULL,
  status                text NOT NULL,
  source_reference      text NOT NULL,
  source_hash           text NOT NULL,
  approved_at           timestamptz,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ccac_status_valido
    CHECK (status IN ('draft', 'approved', 'archived')),
  CONSTRAINT ccac_descricao_nonempty
    CHECK (length(btrim(activity_description)) >= 3),
  CONSTRAINT ccac_source_hash_sha256
    CHECK (source_hash ~ '^[0-9a-f]{64}$'),
  -- Aprovação exige momento registrado: linha aprovada sem data de aprovação
  -- não é auditável.
  CONSTRAINT ccac_aprovacao_coerente
    CHECK ((status = 'approved') = (approved_at IS NOT NULL)),
  CONSTRAINT ccac_chave_unica
    UNIQUE (catalog_version, niche_code, activity_code)
);

-- No máximo UMA atividade aprovada por (versão do catálogo, nicho).
CREATE UNIQUE INDEX IF NOT EXISTS ccac_aprovada_por_nicho_uidx
  ON public.commercial_contract_activity_catalog (catalog_version, niche_code)
  WHERE status = 'approved';

ALTER TABLE public.commercial_contract_activity_catalog ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_contract_activity_catalog FROM PUBLIC;
REVOKE ALL ON public.commercial_contract_activity_catalog FROM anon;
REVOKE ALL ON public.commercial_contract_activity_catalog FROM authenticated;
GRANT SELECT ON public.commercial_contract_activity_catalog TO service_role;

COMMENT ON TABLE public.commercial_contract_activity_catalog IS
  'Autoridade da ATIVIDADE CONTRATADA por nicho canonico. Nenhuma linha de '
  'producao nasce approved: o instrumento congelado tem campo material proprio '
  'para a atividade, e o nome de exibicao do nicho nao e autoridade sobre ele. '
  'Producao falha fechada com commercial_activity_description_unavailable ate a '
  'redacao legal final ser fornecida.';

CREATE OR REPLACE FUNCTION public.commercial_approved_contract_activity(
  p_niche_code      text,
  p_catalog_version text DEFAULT 'SF-v1.4')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_a public.commercial_contract_activity_catalog%ROWTYPE;
BEGIN
  -- OUTROS permanece dormente e por isso nao e consultavel aqui.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_niches n
                  WHERE n.code = p_niche_code AND n.is_active) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_activity_niche_not_canonical',
      'niche_code', p_niche_code);
  END IF;

  SELECT * INTO v_a FROM public.commercial_contract_activity_catalog
   WHERE catalog_version = p_catalog_version
     AND niche_code = p_niche_code
     AND status = 'approved';
  IF NOT FOUND THEN
    -- Estado CORRENTE e esperado em producao.
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_activity_description_unavailable',
      'niche_code', p_niche_code, 'catalog_version', p_catalog_version);
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'activity_catalog_id', v_a.id,
    'activity_code', v_a.activity_code,
    'activity_description', v_a.activity_description,
    'legal_template_version', v_a.legal_template_version,
    'catalog_version', v_a.catalog_version,
    'source_reference', v_a.source_reference,
    'source_hash', v_a.source_hash);
END;
$function$;

ALTER FUNCTION public.commercial_approved_contract_activity(text, text) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.commercial_approved_contract_activity(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.commercial_approved_contract_activity(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.commercial_approved_contract_activity(text, text) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.commercial_approved_contract_activity(text, text)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 3. TOMADOR DE NFS-e E UNIDADE DE EXECUÇÃO — persistidos, não inferidos
-- ---------------------------------------------------------------------------

ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN IF NOT EXISTS nfse_taker_cnpj   text,
  ADD COLUMN IF NOT EXISTS execution_unit_id uuid
    REFERENCES public.site_partner_units(id);

ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS nfse_taker_cnpj   text,
  ADD COLUMN IF NOT EXISTS execution_unit_id uuid
    REFERENCES public.site_partner_units(id);

COMMENT ON COLUMN public.commercial_checkout_intents.nfse_taker_cnpj IS
  'CNPJ do tomador da NFS-e, gravado no instante da reserva a partir de '
  'site_partner_companies.cnpj. No MVP fundador o tomador E a contratante; '
  'tomador alternativo falha fechado com alternate_nfse_taker_not_supported, '
  'porque o schema ainda nao modela CNPJ de filial nem a autoridade do '
  'representante dela.';
COMMENT ON COLUMN public.commercial_checkout_intents.execution_unit_id IS
  'Unidade canonica de execucao, escolhida pelo titular e VALIDADA no servidor '
  'antes do aceite juridico. Nunca a primeira unidade qualquer na finalizacao.';

ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_nfse_taker_formato
  CHECK (nfse_taker_cnpj IS NULL OR nfse_taker_cnpj ~ '^[0-9]{14}$') NOT VALID;
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_nfse_taker_formato
  CHECK (nfse_taker_cnpj IS NULL OR nfse_taker_cnpj ~ '^[0-9]{14}$') NOT VALID;

-- ---------------------------------------------------------------------------
-- 4. ESCOLHA DA UNIDADE DE EXECUÇÃO — RPC própria, validada no servidor
--
-- RPC separada de propósito: a assinatura de `create_commercial_checkout_intent`
-- não muda, e a escolha da unidade fica um ato explícito do titular, auditável,
-- anterior ao aceite jurídico.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_checkout_intent_execution_unit(
  p_intent_id uuid,
  p_unit_id   uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_i public.commercial_checkout_intents%ROWTYPE;
  v_u public.site_partner_units%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
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
  -- Depois do aceite a escolha deixa de ser ajustável: o fato já foi assinado.
  IF v_i.status NOT IN ('draft', 'awaiting_contract') THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'intent_not_editable', 'status', v_i.status);
  END IF;

  SELECT * INTO v_u FROM public.site_partner_units WHERE id = p_unit_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_found');
  END IF;
  -- A unidade tem de ser DA PRÓPRIA empresa: unidade de terceiro nunca vira
  -- local de execução de um contrato alheio.
  IF v_u.company_id IS DISTINCT FROM v_i.company_id THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_owned_by_company');
  END IF;
  IF v_u.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_active', 'status', v_u.status);
  END IF;

  UPDATE public.commercial_checkout_intents
     SET execution_unit_id = v_u.id, updated_at = pg_catalog.now()
   WHERE id = v_i.id;

  PERFORM public.m1_auditar('commercial_intent.execution_unit_selected', v_i.id, 'owner',
    pg_catalog.jsonb_build_object('execution_unit_id', v_u.id),
    pg_catalog.jsonb_build_object('execution_unit_id', v_i.execution_unit_id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'intent_id', v_i.id, 'execution_unit_id', v_u.id,
    'unit_name', v_u.name, 'city', v_u.city, 'uf', v_u.uf);
END;
$function$;

ALTER FUNCTION public.set_checkout_intent_execution_unit(uuid, uuid) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.set_checkout_intent_execution_unit(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_checkout_intent_execution_unit(uuid, uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.set_checkout_intent_execution_unit(uuid, uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.set_checkout_intent_execution_unit(uuid, uuid) IS
  'Titular escolhe a unidade de execucao; o servidor valida que ela e da '
  'propria empresa e esta ativa, e persiste antes do aceite juridico.';

-- ---------------------------------------------------------------------------
-- 5. PREENCHIMENTO NA RESERVA — tomador e, quando inequívoca, a unidade
--
-- Trigger BEFORE INSERT: o tomador de NFS-e é SEMPRE o CNPJ da contratante no
-- MVP fundador, e vem do registro canônico da empresa. Quando existe
-- exatamente UMA unidade ativa, ela é pré-selecionada por conveniência — mas o
-- fato canônico persistido continua sendo o ID da unidade, não "a primeira que
-- aparecer". Com duas ou mais, o servidor NÃO escolhe: o titular escolhe.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cci_preencher_fatos_materiais()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_cnpj   text;
  v_unidade uuid;
  v_qtd    integer;
BEGIN
  -- O CNPJ da empresa pode estar gravado formatado; o tomador e sempre em
  -- digitos. Normalizar aqui evita que a formatacao do cadastro vire divergencia
  -- de tomador.
  SELECT pg_catalog.regexp_replace(c.cnpj, '[^0-9]', '', 'g') INTO v_cnpj
    FROM public.site_partner_companies c WHERE c.id = NEW.company_id;

  IF NEW.nfse_taker_cnpj IS NULL THEN
    NEW.nfse_taker_cnpj := v_cnpj;
  ELSIF pg_catalog.regexp_replace(NEW.nfse_taker_cnpj, '[^0-9]', '', 'g')
        IS DISTINCT FROM v_cnpj THEN
    -- O instrumento congelado admite filial ou outro CNPJ tomador, mas exige
    -- que esse CNPJ e a autoridade do representante dele sejam validamente
    -- identificados. O schema nao modela isso ainda, e fingir que modela seria
    -- pior que recusar.
    RAISE EXCEPTION
      'alternate_nfse_taker_not_supported: no MVP fundador o tomador da NFS-e e '
      'o CNPJ da contratante. CNPJ de filial exige modelagem propria e '
      'verificacao de autoridade do representante.'
      USING ERRCODE = 'check_violation';
  ELSE
    NEW.nfse_taker_cnpj := v_cnpj;
  END IF;

  IF NEW.execution_unit_id IS NULL THEN
    SELECT count(*) INTO v_qtd FROM public.site_partner_units u
     WHERE u.company_id = NEW.company_id AND u.status = 'active';
    IF v_qtd = 1 THEN
      SELECT u.id INTO v_unidade FROM public.site_partner_units u
       WHERE u.company_id = NEW.company_id AND u.status = 'active';
      NEW.execution_unit_id := v_unidade;
    END IF;
    -- Com zero ou com duas ou mais, fica NULL de proposito. O aceite juridico
    -- recusa intencao sem unidade, e o titular escolhe por RPC.
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS cci_preencher_fatos ON public.commercial_checkout_intents;
CREATE TRIGGER cci_preencher_fatos
  BEFORE INSERT ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.cci_preencher_fatos_materiais();

-- A mesma exigência no caminho do pedido, para o tomador.
CREATE OR REPLACE FUNCTION public.ceo_preencher_fatos_materiais()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_cnpj text;
BEGIN
  -- O CNPJ da empresa pode estar gravado formatado; o tomador e sempre em
  -- digitos. Normalizar aqui evita que a formatacao do cadastro vire divergencia
  -- de tomador.
  SELECT pg_catalog.regexp_replace(c.cnpj, '[^0-9]', '', 'g') INTO v_cnpj
    FROM public.site_partner_companies c WHERE c.id = NEW.company_id;

  IF NEW.nfse_taker_cnpj IS NULL THEN
    NEW.nfse_taker_cnpj := v_cnpj;
  ELSIF pg_catalog.regexp_replace(NEW.nfse_taker_cnpj, '[^0-9]', '', 'g')
        IS DISTINCT FROM v_cnpj THEN
    RAISE EXCEPTION
      'alternate_nfse_taker_not_supported: no MVP fundador o tomador da NFS-e e '
      'o CNPJ da contratante.'
      USING ERRCODE = 'check_violation';
  ELSE
    NEW.nfse_taker_cnpj := v_cnpj;
  END IF;

  -- A unidade de execucao do pedido vem da INTENCAO, que ja foi validada. Na
  -- venda manual (sem intencao) ela e pre-selecionada so quando inequivoca.
  IF NEW.execution_unit_id IS NULL AND NEW.checkout_intent_id IS NOT NULL THEN
    SELECT i.execution_unit_id INTO NEW.execution_unit_id
      FROM public.commercial_checkout_intents i WHERE i.id = NEW.checkout_intent_id;
  END IF;
  IF NEW.execution_unit_id IS NULL THEN
    SELECT u.id INTO NEW.execution_unit_id
      FROM public.site_partner_units u
     WHERE u.company_id = NEW.company_id AND u.status = 'active'
     GROUP BY u.id
     HAVING (SELECT count(*) FROM public.site_partner_units u2
              WHERE u2.company_id = NEW.company_id AND u2.status = 'active') = 1;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS ceo_preencher_fatos ON public.commercial_exclusivity_orders;
CREATE TRIGGER ceo_preencher_fatos
  BEFORE INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_preencher_fatos_materiais();

COMMENT ON FUNCTION public.cci_preencher_fatos_materiais() IS
  'Grava o tomador da NFS-e a partir do CNPJ canonico da contratante e, quando '
  'existe exatamente UMA unidade ativa, pre-seleciona ela. Tomador divergente '
  'falha fechado com alternate_nfse_taker_not_supported.';
