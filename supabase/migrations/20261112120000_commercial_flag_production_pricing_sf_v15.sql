-- ===========================================================================
-- SF-v1.5 — Precificação com produção de bandeiras e reutilização por
-- fidelização. Migration ADITIVA, preparada para auditoria.
--
-- Decisão do operador (handoff de 12/11/2026):
--   * anunciante novo (não fidelizado) exige 84 bandeiras físicas novas;
--     custo nominal R$ 35,00/peça -> R$ 2.940,00, somado UMA vez ao preço;
--   * fidelizado com bandeiras conservadas: reutiliza, sem novo adicional,
--     com o preço fidelizado da SF-v1.4;
--   * bandeira danificada: reposição identificada, sem cobrança e sem preço
--     enquanto não houver política aprovada.
--
-- O QUE ESTA MIGRATION NÃO FAZ:
--   * não ativa a SF-v1.5: a versão 4 nasce 'prepared'; a regra 3 (SF-v1.4)
--     continua vigente e intacta. Ativação: supabase/ops/, só com autorização;
--   * não altera MEI (R$ 141,99 × 588), QA, pool, modalidades de liquidação,
--     fidelidade, pedidos históricos, contratos, templates ou o App;
--   * não cria RPC administrativa nem permissão pública.
--
-- CORREÇÃO DE SEGURANÇA INCLUÍDA: em Production, commercial_pricing_schedule
-- dava arwdDxtm ao service_role (privilégios padrão do schema) e nem a agenda
-- nem as regras tinham proteção: os centavos da SF-v1.4 eram alteráveis.
-- ===========================================================================

-- ===========================================================================
-- A. REGRAS DE PREÇO: estado 'prepared' e proteção estrutural
-- ---------------------------------------------------------------------------
-- Uma versão nasce 'prepared': existe, é auditável, mas não é vigente nem
-- consultável pelo preço público. A ativação é um ato operacional separado
-- (supabase/ops/20261112_ativar_precificacao_v4_bandeiras.sql), executado só
-- com autorização. Transições: prepared -> active -> superseded.
-- ===========================================================================
ALTER TABLE public.commercial_pricing_rules DROP CONSTRAINT cpr_status_allowed;
ALTER TABLE public.commercial_pricing_rules
  ADD CONSTRAINT cpr_status_allowed
  CHECK (status = ANY (ARRAY['prepared'::text, 'active'::text, 'superseded'::text]));

CREATE FUNCTION public.commercial_pricing_rules_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'pricing_rule_imutavel: regra nova nasce prepared (recebido %)', NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.status IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'pricing_rule_imutavel: regra % (%) nao pode ser apagada', OLD.version, OLD.status
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  -- UPDATE: valores nunca mudam depois de a regra sair de 'prepared'; em
  -- 'prepared' a regra ainda é editável. Só status (e effective_from na
  -- ativação) mudam nas transições.
  IF OLD.status = 'prepared' AND NEW.status = 'prepared' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.version IS DISTINCT FROM OLD.version THEN
      RAISE EXCEPTION 'pricing_rule_imutavel: id e version nao mudam'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NOT ((OLD.status = 'prepared' AND NEW.status = 'active')
          OR (OLD.status = 'active' AND NEW.status = 'superseded')) THEN
    RAISE EXCEPTION 'pricing_rule_imutavel: transicao % -> % recusada (versao %)',
      OLD.status, NEW.status, OLD.version
      USING ERRCODE = 'check_violation';
  END IF;
  IF (pg_catalog.to_jsonb(NEW) - 'status' - 'effective_from')
       IS DISTINCT FROM
     (pg_catalog.to_jsonb(OLD) - 'status' - 'effective_from') THEN
    RAISE EXCEPTION 'pricing_rule_imutavel: valores da versao % nao mudam', OLD.version
      USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'active' AND NEW.effective_from IS DISTINCT FROM OLD.effective_from THEN
    RAISE EXCEPTION 'pricing_rule_imutavel: effective_from so muda na ativacao'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_pricing_rules_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cpr_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_pricing_rules
  FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_rules_protect();

CREATE FUNCTION public.commercial_pricing_protect_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  RAISE EXCEPTION 'pricing_rule_imutavel: TRUNCATE de % recusado', TG_TABLE_NAME
    USING ERRCODE = 'check_violation';
END $$;
REVOKE ALL ON FUNCTION public.commercial_pricing_protect_truncate() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cpr_protect_truncate
  BEFORE TRUNCATE ON public.commercial_pricing_rules
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- ===========================================================================
-- B. AGENDA: produção de bandeiras como fato separado, e agenda protegida
-- ---------------------------------------------------------------------------
-- new_flag_units é a quantidade de PEÇAS FÍSICAS que a contratação exige
-- fabricar: 84 por anunciante novo (os participantes da formação de
-- referência), independentemente da posição. NÃO é contracted_quantity (24 ou
-- 12 unidades comerciais).
--
-- flag_production_charge_cents é a parcela do preço que corresponde ao custo
-- NOMINAL de fabricação (84 × R$ 35,00 = R$ 2.940,00). Ela está CONTIDA em
-- smallflags_main_fee_cents: as invariantes vigentes (econômico = MEI + QA +
-- principal; remuneração = QA + principal) continuam valendo sem alteração, e
-- o adicional nunca reduz a contraprestação dos MEIs nem a QA. O custo
-- EFETIVO de fabricação é outro fato, registrado em commercial_flag_sets.
--
-- Linhas da SF-v1.4 ficam com as três colunas NULL: aquela economia não
-- previa produção de bandeiras, e nada é inventado para ela.
-- ===========================================================================
ALTER TABLE public.commercial_pricing_schedule
  ADD COLUMN new_flag_units               integer,
  ADD COLUMN flag_unit_reference_cents    bigint,
  ADD COLUMN flag_production_charge_cents bigint;

ALTER TABLE public.commercial_pricing_schedule
  ADD CONSTRAINT cps_bandeiras_coerente CHECK (
    (new_flag_units IS NULL AND flag_unit_reference_cents IS NULL
       AND flag_production_charge_cents IS NULL)
    OR (new_flag_units IS NOT NULL AND flag_unit_reference_cents IS NOT NULL
        AND flag_production_charge_cents IS NOT NULL
        AND new_flag_units >= 0
        AND flag_unit_reference_cents > 0
        AND flag_production_charge_cents = new_flag_units * flag_unit_reference_cents
        AND flag_production_charge_cents <= smallflags_main_fee_cents
        -- O preço fidelizado da agenda PRESSUPÕE reutilização: zero peças novas.
        AND (NOT fidelized OR new_flag_units = 0)
        AND (fidelized OR new_flag_units > 0)));

COMMENT ON COLUMN public.commercial_pricing_schedule.new_flag_units IS
  'Bandeiras fisicas novas que a contratacao exige fabricar (84 por anunciante '
  'novo). Nao e contracted_quantity. 0 no fidelizado: o preco pressupoe '
  'reutilizacao verificada. NULL nas economias anteriores (SF-v1.4).';
COMMENT ON COLUMN public.commercial_pricing_schedule.flag_production_charge_cents IS
  'Parcela do preco correspondente ao custo NOMINAL de fabricacao, contida em '
  'smallflags_main_fee_cents. Nao e o custo efetivo (commercial_flag_sets).';

-- A agenda guarda centavos contratuais. Os privilégios padrão do schema davam
-- escrita ao service_role, que ignora RLS: revoga-se, e linhas de versões já
-- publicadas (active/superseded) ficam imutáveis também para o dono.
REVOKE ALL ON public.commercial_pricing_schedule FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_pricing_schedule TO service_role;

CREATE FUNCTION public.commercial_pricing_schedule_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_status_old text;
  v_status_new text;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT status INTO v_status_old FROM public.commercial_pricing_rules
     WHERE version = OLD.pricing_rule_version;
    IF v_status_old IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'pricing_schedule_imutavel: agenda da versao % (%) nao muda',
        OLD.pricing_rule_version, v_status_old
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT status INTO v_status_new FROM public.commercial_pricing_rules
     WHERE version = NEW.pricing_rule_version;
    IF v_status_new IS DISTINCT FROM 'prepared' THEN
      RAISE EXCEPTION 'pricing_schedule_imutavel: agenda so e escrita com a versao em prepared (versao %, %)',
        NEW.pricing_rule_version, v_status_new
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION public.commercial_pricing_schedule_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cps_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_pricing_schedule
  FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_schedule_protect();
CREATE TRIGGER cps_protect_truncate
  BEFORE TRUNCATE ON public.commercial_pricing_schedule
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- Regras: o dono já é o único com escrita; o service_role só lê.
REVOKE ALL ON public.commercial_pricing_rules FROM PUBLIC, anon, authenticated, service_role;

-- ===========================================================================
-- C. pricing_rule_version = 4: SF-v1.5, PREPARADA (não vigente)
-- ---------------------------------------------------------------------------
-- Não fidelizado: preço SF-v1.4 + R$ 2.940,00 (84 × R$ 35,00), uma única vez,
--   dentro da parcela principal. MEI, QA e participação: idênticos à SF-v1.4.
-- Fidelizado: preço fidelizado da SF-v1.4, sem adicional (reutilização).
-- ===========================================================================
INSERT INTO public.commercial_pricing_rules
  (version, status, block_units, block_price_cents, extra_unit_price_cents,
   fidelized_unit_price_cents, pool_bps_supermarket, pool_bps_common,
   pool_precision_model, effective_from, notes)
VALUES
  (4, 'prepared',
   -- Campos de fórmula: compatibilidade de schema, não usados no modelo de
   -- tabela (mesmo critério da versão 3).
   12, 1999900, 129900, 129900, NULL, NULL,
   -- effective_from registra a preparação; a ativação o redefine.
   'explicit_schedule', now(),
   'SF-v1.5: SF-v1.4 + fabricacao nominal de 84 bandeiras (R$ 35,00/peca) '
   'no nao fidelizado; fidelizado mantem SF-v1.4 com reutilizacao verificada. '
   'PREPARADA: ativacao so por ato autorizado.');

INSERT INTO public.commercial_pricing_schedule
  (pricing_rule_version, contract_economics_version, commercial_category,
   fidelized, economic_value_cents, mei_consideration_cents,
   smallflags_qa_cents, smallflags_main_fee_cents,
   smallflags_total_remuneration_cents, ordinary_participation_value_cents,
   new_flag_units, flag_unit_reference_cents, flag_production_charge_cents,
   notes)
VALUES
  (4, 'SF-v1.5', 'supermarket', false, 3293900, 2385432, 12168,  896300,  908468, 14199, 84, 3500, 294000,
   'SF-v1.5 supermercado 24 unidades, nao fidelizado: SF-v1.4 2.999.900 + 294.000 de fabricacao de 84 bandeiras'),
  (4, 'SF-v1.5', 'common',      false, 2293900, 1192716,  6084, 1095100, 1101184, 14199, 84, 3500, 294000,
   'SF-v1.5 demais posicoes 12 unidades, nao fidelizado: SF-v1.4 1.999.900 + 294.000 de fabricacao de 84 bandeiras'),
  (4, 'SF-v1.5', 'supermarket', true,  2817600, 2385432, 12168,  420000,  432168, 14199,  0, 3500,      0,
   'SF-v1.5 supermercado 24 unidades, fidelizado com reutilizacao verificada das bandeiras'),
  (4, 'SF-v1.5', 'common',      true,  1618800, 1192716,  6084,  420000,  426084, 14199,  0, 3500,      0,
   'SF-v1.5 demais posicoes 12 unidades, fidelizado com reutilizacao verificada das bandeiras');

-- ===========================================================================
-- D. INVENTÁRIO DE BANDEIRAS: conjuntos produzidos e inspeções de conservação
-- ---------------------------------------------------------------------------
-- Mínimo seguro. Escrita só pelo dono (ato administrativo deliberado); nenhuma
-- RPC nova; service_role só lê. A operação de campo (distribuição, alternância,
-- etapas) continua sendo do App.
--
-- Um conjunto nasce de UM pedido que exigiu produção (não fidelizado sob
-- SF-v1.5). Empresa, identidade de fidelidade e quantidade de peças vêm desse
-- pedido; o registrador não as escolhe.
-- ===========================================================================
CREATE TABLE public.commercial_flag_sets (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin_order_id       uuid NOT NULL UNIQUE
                        REFERENCES public.commercial_exclusivity_orders(id),
  company_id            uuid NOT NULL REFERENCES public.site_partner_companies(id),
  fidelity_identity     text NOT NULL,
  pieces_count          integer NOT NULL,
  produced_at           timestamptz NOT NULL,
  supplier_name         text NOT NULL,
  -- Custo EFETIVO por peça informado pelo fornecedor (referência: 3.500).
  -- Frete, embalagem, instalação, suporte, tributos e perdas NÃO estão aqui.
  unit_cost_cents       bigint NOT NULL,
  production_cost_cents bigint GENERATED ALWAYS AS (pieces_count * unit_cost_cents) STORED,
  artwork_hash          text,
  status                text NOT NULL DEFAULT 'active',
  retired_at            timestamptz,
  retired_reason        text,
  recorded_by           uuid NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  notes                 text,
  CONSTRAINT cfs_pecas_positivas CHECK (pieces_count > 0),
  CONSTRAINT cfs_custo_positivo CHECK (unit_cost_cents > 0),
  CONSTRAINT cfs_fornecedor CHECK (length(btrim(supplier_name)) >= 2),
  CONSTRAINT cfs_arte_hash CHECK (artwork_hash IS NULL OR artwork_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cfs_status_valido CHECK (status IN ('active', 'retired')),
  CONSTRAINT cfs_retirada_coerente CHECK (
    (status = 'active' AND retired_at IS NULL AND retired_reason IS NULL)
    OR (status = 'retired' AND retired_at IS NOT NULL
        AND retired_reason IS NOT NULL AND length(btrim(retired_reason)) >= 3)),
  CONSTRAINT cfs_identidade_formato CHECK (
    fidelity_identity ~ '^[a-z][a-z_]{2,63}$'
    OR fidelity_identity ~ '^segment:[a-z][a-z0-9_]{2,63}$')
);
CREATE INDEX cfs_empresa_identidade_idx
  ON public.commercial_flag_sets (company_id, fidelity_identity, produced_at DESC);

COMMENT ON TABLE public.commercial_flag_sets IS
  'Conjunto fisico de bandeiras de UM anunciante, produzido para UM pedido. '
  'Base para a reutilizacao na contratacao fidelizada.';

CREATE TABLE public.commercial_flag_set_inspections (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_set_id         uuid NOT NULL REFERENCES public.commercial_flag_sets(id),
  inspected_at        timestamptz NOT NULL,
  inspector_name      text NOT NULL,
  -- SHA-256 do relatório de inspeção (fotos, contagem, observações).
  evidence_hash       text NOT NULL,
  pieces_inspected    integer NOT NULL,
  pieces_fit          integer NOT NULL,
  pieces_unfit        integer NOT NULL,
  unfit_categories    text[] NOT NULL DEFAULT '{}',
  conservation_result text GENERATED ALWAYS AS
                      (CASE WHEN pieces_unfit = 0 THEN 'reusable'
                            ELSE 'replacement_needed' END) STORED,
  recorded_by         uuid NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  notes               text,
  CONSTRAINT cfi_inspetor CHECK (length(btrim(inspector_name)) >= 3),
  CONSTRAINT cfi_evidencia CHECK (evidence_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cfi_contagem CHECK (pieces_inspected > 0 AND pieces_fit >= 0
                                 AND pieces_unfit >= 0
                                 AND pieces_fit + pieces_unfit = pieces_inspected),
  CONSTRAINT cfi_categorias_validas CHECK (
    unfit_categories <@ ARRAY['damaged', 'lost', 'worn', 'unfit_for_display',
                              'art_incompatible', 'unsafe']::text[]),
  CONSTRAINT cfi_categorias_coerentes CHECK (
    (pieces_unfit = 0 AND cardinality(unfit_categories) = 0)
    OR (pieces_unfit > 0 AND cardinality(unfit_categories) > 0))
);
CREATE INDEX cfi_conjunto_idx
  ON public.commercial_flag_set_inspections (flag_set_id, inspected_at DESC, created_at DESC);

COMMENT ON TABLE public.commercial_flag_set_inspections IS
  'Inspecao de CONSERVACAO e compatibilidade com a arte de um conjunto. Nao e '
  'aprovacao tecnica de seguranca da bandeira ou do suporte, que pertence a '
  'commercial_advertising_specs e ao responsavel tecnico.';

-- Conjunto: empresa, identidade e peças derivadas do pedido de origem;
-- depois de registrado, só pode ser aposentado.
CREATE FUNCTION public.commercial_flag_sets_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_o public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = NEW.origin_order_id;
    IF NOT FOUND OR v_o.status = 'cancelled' THEN
      RAISE EXCEPTION 'flag_set_origem_invalida: pedido de origem inexistente ou cancelado'
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_o.flag_production_new_units IS NULL OR v_o.flag_production_new_units <= 0 THEN
      RAISE EXCEPTION 'flag_set_origem_invalida: o pedido de origem nao exigiu producao de bandeiras'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION 'flag_set_transicao_invalida: conjunto nasce active'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.produced_at > pg_catalog.now() THEN
      RAISE EXCEPTION 'flag_set_transicao_invalida: produced_at no futuro'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.company_id        := v_o.company_id;
    NEW.fidelity_identity := CASE WHEN v_o.segment_classification_snapshot IS NOT NULL
                                  THEN 'segment:' || v_o.segment_classification_snapshot
                                  ELSE v_o.niche_code END;
    NEW.pieces_count      := v_o.flag_production_new_units;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'flag_set_imutavel: conjunto registrado nao e apagado (aposente-o)'
      USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'retired' THEN
    RAISE EXCEPTION 'flag_set_imutavel: conjunto aposentado' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IS DISTINCT FROM 'retired' THEN
    RAISE EXCEPTION 'flag_set_imutavel: conjunto ativo so pode ser aposentado'
      USING ERRCODE = 'check_violation';
  END IF;
  -- production_cost_cents é coluna GERADA: num gatilho BEFORE ela ainda vem
  -- NULL em NEW. Sai da comparação; seus insumos (pieces_count e
  -- unit_cost_cents) continuam comparados.
  IF (pg_catalog.to_jsonb(NEW) - 'status' - 'retired_at' - 'retired_reason' - 'production_cost_cents')
       IS DISTINCT FROM
     (pg_catalog.to_jsonb(OLD) - 'status' - 'retired_at' - 'retired_reason' - 'production_cost_cents') THEN
    RAISE EXCEPTION 'flag_set_imutavel: aposentadoria so altera status, retired_at e retired_reason'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_flag_sets_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cfs_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_flag_sets
  FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_sets_protect();

-- Inspeção: append-only; peças inspecionadas = peças do conjunto.
CREATE FUNCTION public.commercial_flag_set_inspections_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_s public.commercial_flag_sets%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'flag_inspection_imutavel: inspecao registrada nao muda nem e apagada'
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_s FROM public.commercial_flag_sets WHERE id = NEW.flag_set_id;
  IF NOT FOUND OR v_s.status <> 'active' THEN
    RAISE EXCEPTION 'flag_inspection_invalida: conjunto inexistente ou aposentado'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.pieces_inspected IS DISTINCT FROM v_s.pieces_count THEN
    RAISE EXCEPTION 'flag_inspection_invalida: inspecionar todas as % pecas do conjunto (recebido %)',
      v_s.pieces_count, NEW.pieces_inspected
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.inspected_at < v_s.produced_at OR NEW.inspected_at > pg_catalog.now() THEN
    RAISE EXCEPTION 'flag_inspection_invalida: inspected_at fora do intervalo [producao, agora]'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_flag_set_inspections_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cfi_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_flag_set_inspections
  FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_set_inspections_protect();

CREATE FUNCTION public.commercial_flag_inventory_protect_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  RAISE EXCEPTION 'flag_inventory_imutavel: TRUNCATE de % recusado', TG_TABLE_NAME
    USING ERRCODE = 'check_violation';
END $$;
REVOKE ALL ON FUNCTION public.commercial_flag_inventory_protect_truncate() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cfs_protect_truncate
  BEFORE TRUNCATE ON public.commercial_flag_sets
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_flag_inventory_protect_truncate();
CREATE TRIGGER cfi_protect_truncate
  BEFORE TRUNCATE ON public.commercial_flag_set_inspections
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_flag_inventory_protect_truncate();

ALTER TABLE public.commercial_flag_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_flag_set_inspections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_flag_sets FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.commercial_flag_set_inspections FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_flag_sets TO service_role;
GRANT SELECT ON public.commercial_flag_set_inspections TO service_role;

-- ===========================================================================
-- E. RESOLVEDOR DE REUTILIZAÇÃO (fidelizado sob economia com bandeiras)
-- ---------------------------------------------------------------------------
-- Fidelização e conservação são fatos DISTINTOS: este resolvedor não altera a
-- fidelidade; ele só diz se existe um conjunto do MESMO anunciante e da MESMA
-- identidade, com inspeção mais recente aprovando TODAS as peças, ainda não
-- consumida por outro pedido. Cada reutilização exige inspeção própria.
--
-- Falhas (nenhuma produz preço):
--   flag_reuse_not_verified       sem conjunto, sem inspeção, ou inspeção já usada
--   flag_replacement_policy_pending  inspeção com peças inadequadas: reposição
--                                    sem política aprovada não tem preço
-- ===========================================================================
CREATE FUNCTION public.commercial_flag_reuse_resolution(
  p_company_id uuid, p_fidelity_identity text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_s public.commercial_flag_sets%ROWTYPE;
  v_i public.commercial_flag_set_inspections%ROWTYPE;
BEGIN
  SELECT * INTO v_s FROM public.commercial_flag_sets
   WHERE company_id = p_company_id
     AND fidelity_identity = p_fidelity_identity
     AND status = 'active'
   ORDER BY produced_at DESC, created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'flag_reuse_not_verified', 'detail', 'flag_set_not_registered');
  END IF;

  SELECT * INTO v_i FROM public.commercial_flag_set_inspections
   WHERE flag_set_id = v_s.id
   ORDER BY inspected_at DESC, created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'flag_reuse_not_verified', 'detail', 'flag_inspection_missing');
  END IF;

  IF v_i.conservation_result <> 'reusable' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'flag_replacement_policy_pending',
      'detail', 'flag_replacement_needed',
      'pieces_unfit', v_i.pieces_unfit,
      'pieces_count', v_s.pieces_count);
  END IF;

  IF EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.flag_reuse_inspection_id = v_i.id
                AND o.status <> 'cancelled') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'flag_reuse_not_verified', 'detail', 'flag_inspection_already_used');
  END IF;

  RETURN pg_catalog.jsonb_build_object('ok', true,
    'flag_set_id', v_s.id, 'inspection_id', v_i.id,
    'pieces_count', v_s.pieces_count);
END $$;
REVOKE ALL ON FUNCTION public.commercial_flag_reuse_resolution(uuid, text) FROM PUBLIC, anon, authenticated, service_role;

-- ===========================================================================
-- F. FATOS DE PRODUÇÃO NA INTENÇÃO E NO PEDIDO (snapshot imutável)
-- ===========================================================================
ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN flag_production_new_units    integer,
  ADD COLUMN flag_unit_reference_cents    bigint,
  ADD COLUMN flag_production_charge_cents bigint,
  ADD COLUMN flag_reuse_set_id            uuid REFERENCES public.commercial_flag_sets(id),
  ADD COLUMN flag_reuse_inspection_id     uuid REFERENCES public.commercial_flag_set_inspections(id);
ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN flag_production_new_units    integer,
  ADD COLUMN flag_unit_reference_cents    bigint,
  ADD COLUMN flag_production_charge_cents bigint,
  ADD COLUMN flag_reuse_set_id            uuid REFERENCES public.commercial_flag_sets(id),
  ADD COLUMN flag_reuse_inspection_id     uuid REFERENCES public.commercial_flag_set_inspections(id);

ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_bandeiras_coerente CHECK (
    (flag_production_new_units IS NULL AND flag_unit_reference_cents IS NULL
       AND flag_production_charge_cents IS NULL AND flag_reuse_set_id IS NULL
       AND flag_reuse_inspection_id IS NULL)
    OR (NOT fidelized AND flag_production_new_units > 0
        AND flag_unit_reference_cents > 0
        AND flag_production_charge_cents = flag_production_new_units * flag_unit_reference_cents
        AND flag_production_charge_cents <= smallflags_main_fee_cents
        AND flag_reuse_set_id IS NULL AND flag_reuse_inspection_id IS NULL)
    OR (fidelized AND flag_production_new_units = 0
        AND flag_unit_reference_cents > 0 AND flag_production_charge_cents = 0
        AND flag_reuse_set_id IS NOT NULL AND flag_reuse_inspection_id IS NOT NULL));
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_bandeiras_coerente CHECK (
    (flag_production_new_units IS NULL AND flag_unit_reference_cents IS NULL
       AND flag_production_charge_cents IS NULL AND flag_reuse_set_id IS NULL
       AND flag_reuse_inspection_id IS NULL)
    OR (NOT fidelized AND flag_production_new_units > 0
        AND flag_unit_reference_cents > 0
        AND flag_production_charge_cents = flag_production_new_units * flag_unit_reference_cents
        AND flag_production_charge_cents <= smallflags_main_fee_cents
        AND flag_reuse_set_id IS NULL AND flag_reuse_inspection_id IS NULL)
    OR (fidelized AND flag_production_new_units = 0
        AND flag_unit_reference_cents > 0 AND flag_production_charge_cents = 0
        AND flag_reuse_set_id IS NOT NULL AND flag_reuse_inspection_id IS NOT NULL));

-- Uma inspeção autoriza UMA reutilização.
CREATE UNIQUE INDEX ceo_inspecao_reuso_unica_idx
  ON public.commercial_exclusivity_orders (flag_reuse_inspection_id)
  WHERE flag_reuse_inspection_id IS NOT NULL AND status <> 'cancelled';

COMMENT ON COLUMN public.commercial_exclusivity_orders.flag_production_new_units IS
  'Bandeiras fisicas novas exigidas por este pedido (84 nao fidelizado, 0 '
  'fidelizado com reutilizacao). NULL sob economias sem producao (SF-v1.4).';
COMMENT ON COLUMN public.commercial_exclusivity_orders.flag_production_charge_cents IS
  'Parcela do preco referente a fabricacao nominal, contida em '
  'smallflags_main_fee_cents. Cobrada uma unica vez, no pedido que exige producao.';

-- Resolução no INSERT, da mesma autoridade, para todo caminho de gravação.
-- Roda depois de *_aplicar_autoridade_v14 (ordem alfabética dos gatilhos).
CREATE FUNCTION public.cci_validar_producao_bandeiras()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
END $$;
REVOKE ALL ON FUNCTION public.cci_validar_producao_bandeiras() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cci_validar_producao_bandeiras
  BEFORE INSERT ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.cci_validar_producao_bandeiras();

CREATE FUNCTION public.ceo_validar_producao_bandeiras()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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
END $$;
REVOKE ALL ON FUNCTION public.ceo_validar_producao_bandeiras() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ceo_validar_producao_bandeiras
  BEFORE INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_validar_producao_bandeiras();

-- Fatos de produção são parte do snapshot: imutáveis depois do INSERT.
CREATE FUNCTION public.commercial_flag_facts_imutaveis()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
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
END $$;
REVOKE ALL ON FUNCTION public.commercial_flag_facts_imutaveis() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cci_bandeiras_imutaveis
  BEFORE UPDATE ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_facts_imutaveis();
CREATE TRIGGER ceo_bandeiras_imutaveis
  BEFORE UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_facts_imutaveis();

-- ===========================================================================
-- G. PRODUÇÃO DA FORMAÇÃO: soma dos PEDIDOS efetivos (não classificação global)
-- ===========================================================================
CREATE FUNCTION public.commercial_exclusivity_flag_production(p_exclusivity_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT pg_catalog.jsonb_build_object(
    'ok', true,
    'exclusivity_id', p_exclusivity_id,
    'orders', count(*),
    'orders_without_flag_facts', count(*) FILTER (WHERE o.flag_production_new_units IS NULL),
    'orders_new_production', count(*) FILTER (WHERE o.flag_production_new_units > 0),
    'orders_reusing_flags', count(*) FILTER (WHERE o.flag_reuse_set_id IS NOT NULL),
    'new_flag_units', coalesce(sum(o.flag_production_new_units), 0),
    'flag_production_charge_cents', coalesce(sum(o.flag_production_charge_cents), 0),
    'economic_value_cents', coalesce(sum(o.economic_value_cents), 0),
    'mei_consideration_cents', coalesce(sum(o.mei_consideration_cents), 0),
    'smallflags_qa_cents', coalesce(sum(o.smallflags_qa_cents), 0),
    'smallflags_total_remuneration_cents', coalesce(sum(o.smallflags_total_remuneration_cents), 0))
    FROM public.commercial_exclusivity_orders o
   WHERE o.exclusivity_id = p_exclusivity_id
     AND o.status <> 'cancelled';
$$;
REVOKE ALL ON FUNCTION public.commercial_exclusivity_flag_production(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commercial_exclusivity_flag_production(uuid) TO service_role;

-- ===========================================================================
-- H. PREÇO: versão preparada não é consultável; fatos de bandeira aditivos
-- ===========================================================================
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
    SELECT * INTO v_rule
      FROM public.commercial_pricing_rules
     WHERE status = 'active';
  ELSE
    SELECT * INTO v_rule
      FROM public.commercial_pricing_rules
     WHERE version = p_pricing_version;
  END IF;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  -- SF-v1.5: versão PREPARADA não é preço vigente nem consultável, nem por
  -- versão explícita. Ela só passa a existir para o público depois da
  -- ativação autorizada.
  IF v_rule.status = 'prepared' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_rule_not_published');
  END IF;

  SELECT contracted_quantity INTO v_qty
    FROM public.commercial_niches
   WHERE code = p_niche_code AND is_active;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'invalid_niche');
  END IF;

  -- Seis posições ativas. Supermercado usa sua matriz; as cinco posições de
  -- 12 unidades (inclusive Calçados e Outros, decisão D3) usam a comum.
  -- Código fora desta lista falha fechado em vez de cair numa categoria por
  -- omissão.
  v_cat := CASE WHEN p_niche_code = 'supermarket' THEN 'supermarket'
                WHEN p_niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others') THEN 'common'
                ELSE NULL END;
  IF v_cat IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'pricing_category_unavailable',
      'niche_code', p_niche_code);
  END IF;

  -- SF-v1.4 e posteriores com agenda explícita.
  IF v_rule.pool_precision_model = 'explicit_schedule' THEN
    SELECT * INTO v_sched
      FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = v_rule.version
       AND commercial_category = v_cat
       AND fidelized = p_fidelized;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false,
        'reason', 'pricing_schedule_missing',
        'pricing_rule_version', v_rule.version,
        'commercial_category', v_cat,
        'fidelized', p_fidelized);
    END IF;

    RETURN pg_catalog.jsonb_build_object(
      'ok', true,
      'pricing_rule_version', v_rule.version,
      'pool_precision_model', v_rule.pool_precision_model,
      'niche_code', p_niche_code,
      'niche_category', v_cat,
      'nominal_quantity', v_qty,
      'fidelized', p_fidelized,
      'currency', 'BRL',
      'pool_bps', NULL::integer,
      'display_pool_percent', NULL::text,
      'display_bdflow_percent', NULL::text,
      'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
      'contract_economics_version', v_sched.contract_economics_version,
      'economic_value_cents', v_sched.economic_value_cents,
      'contractual_pool_cents',
        v_sched.mei_consideration_cents + v_sched.smallflags_qa_cents,
      'bdflow_due_cents', v_sched.smallflags_main_fee_cents,
      'mei_consideration_cents', v_sched.mei_consideration_cents,
      'smallflags_qa_cents', v_sched.smallflags_qa_cents,
      'smallflags_main_fee_cents', v_sched.smallflags_main_fee_cents,
      'smallflags_total_remuneration_cents',
        v_sched.smallflags_total_remuneration_cents,
      'ordinary_participation_value_cents',
        v_sched.ordinary_participation_value_cents,
      -- NOVO: a UI lê estas três chaves; não reconstrói financiamento.
      'direct_benefit_deliverable_cents', v_sched.mei_consideration_cents,
      'funding_direct_benefits_cents',
        v_sched.smallflags_total_remuneration_cents,
      'funding_cash_cents', v_sched.economic_value_cents
    )
    -- SF-v1.5: fatos de produção de bandeiras, só quando a economia os prevê.
    -- A SF-v1.4 continua devolvendo exatamente as mesmas chaves.
    || CASE WHEN v_sched.new_flag_units IS NULL THEN '{}'::jsonb
       ELSE pg_catalog.jsonb_build_object(
         'new_flag_units', v_sched.new_flag_units,
         'flag_unit_reference_cents', v_sched.flag_unit_reference_cents,
         'flag_production_charge_cents', v_sched.flag_production_charge_cents,
         'flag_reuse_required', p_fidelized) END;
  END IF;

  -- V1/V2 históricos: cálculo original preservado.
  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  IF v_rule.pool_precision_model = 'exact_ratio' THEN
    SELECT * INTO v_ratio
      FROM public.commercial_pool_share_ratios
     WHERE pricing_rule_version = v_rule.version
       AND niche_category = v_cat;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'pool_ratio_unavailable');
    END IF;
    v_pool := (v_economic * v_ratio.pool_numerator) / v_ratio.pool_denominator;
    v_disp_pool := v_ratio.display_pool_percent;
    v_disp_bdf := v_ratio.display_bdflow_percent;
  ELSE
    v_bps := CASE WHEN v_cat = 'supermarket'
                  THEN v_rule.pool_bps_supermarket
                  ELSE v_rule.pool_bps_common END;
    v_pool := (v_economic * v_bps) / 10000;
  END IF;

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
    'payment_method', CASE WHEN p_fidelized THEN 'credit_card' ELSE 'pix' END,
    -- NOVO: mesma semântica pública, resolvida pela autoridade histórica.
    'direct_benefit_deliverable_cents', v_pool,
    'funding_direct_benefits_cents', v_economic - v_pool,
    'funding_cash_cents', v_economic
  );
END;
$function$;

-- ===========================================================================
-- I. RESERVA: fidelizado sem reutilização verificada não reserva nem recebe preço
-- ===========================================================================
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
$function$;

-- ===========================================================================
-- J. RESPOSTA DA RESERVA: fatos de produção congelados
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.cci_resposta_intencao(p_i commercial_checkout_intents, p_ja boolean)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT pg_catalog.jsonb_build_object(
    'ok', true,
    'already', p_ja,
    'intent_id', p_i.id,
    'status', p_i.status,
    'opportunity_id', p_i.opportunity_id,
    'exclusivity_id', p_i.exclusivity_id,
    'region_id', p_i.region_id,
    'reserved_until', p_i.reserved_until,
    'reservation_minutes', 30,
    'pricing_rule_version', p_i.pricing_rule_version,
    'benefit_distribution_policy_version', p_i.benefit_distribution_policy_version,
    'niche_code', p_i.niche_code,
    'segment_code', p_i.segment_code_snapshot,
    'segment_name', p_i.segment_name_snapshot,
    'nominal_quantity', p_i.nominal_quantity,
    'fidelized', p_i.fidelized,
    'payment_method', p_i.payment_method,
    'benefit_settlement_mode', p_i.benefit_settlement_mode,
    'currency', p_i.currency,
    'economic_value_cents', p_i.economic_value_cents,
    -- Pool INTEIRO, por compatibilidade: inclui a parcela QA da SmallFlags.
    'user_pool_cents', p_i.user_pool_cents,
    'contract_economics_version', p_i.contract_economics_version,
    'mei_consideration_cents', p_i.mei_consideration_cents,
    'smallflags_qa_cents', p_i.smallflags_qa_cents,
    'smallflags_main_fee_cents', p_i.smallflags_main_fee_cents,
    'smallflags_total_remuneration_cents', p_i.smallflags_total_remuneration_cents,
    'bdflow_ops_investment_cents', p_i.bdflow_ops_investment_cents,
    'cash_user_pool_funding_cents', p_i.cash_user_pool_funding_cents,
    'total_monetary_funding_required_cents', p_i.total_monetary_funding_required_cents,
    'participant_target', p_i.participant_target,
    -- SF-v1.5: fatos de produção congelados na reserva (NULL na SF-v1.4).
    'new_flag_units', p_i.flag_production_new_units,
    'flag_unit_reference_cents', p_i.flag_unit_reference_cents,
    'flag_production_charge_cents', p_i.flag_production_charge_cents,
    'flag_reuse', (p_i.flag_reuse_set_id IS NOT NULL));
$function$;

-- ===========================================================================
-- K. INSTRUMENTO: fatos de produção no bloco V2 (só modelos que exigem especificação)
-- ===========================================================================
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

    -- SF-v1.5: fatos de produção de bandeiras do PEDIDO (snapshot imutável).
    -- Ausentes sob a SF-v1.4; um modelo que os exija falha fechado ali.
    v_snap := v_snap || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'flag_production_new_units', v_o.flag_production_new_units,
      'flag_unit_reference_cents', v_o.flag_unit_reference_cents,
      'flag_production_charge_cents', v_o.flag_production_charge_cents,
      'flag_reuse_set_id', v_o.flag_reuse_set_id,
      'flag_reuse_inspection_id', v_o.flag_reuse_inspection_id));

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
    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'flag_production_new_units', 'contract_economics_authority',
      'flag_unit_reference_cents', 'contract_economics_authority',
      'flag_production_charge_cents', 'contract_economics_authority',
      'flag_reuse_set_id', 'flag_inventory_authority',
      'flag_reuse_inspection_id', 'flag_inventory_authority');
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

-- ===========================================================================
-- Z. AUTOVERIFICAÇÃO: a SF-v1.4 continua vigente e intacta; a SF-v1.5 está só preparada
-- ===========================================================================
DO $verif$
DECLARE v_falhas text[] := '{}';
BEGIN
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 3) <> 'active' THEN
    v_falhas := v_falhas || 'versao 3 deixou de ser a ativa'::text; END IF;
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared' THEN
    v_falhas := v_falhas || 'versao 4 nao esta prepared'::text; END IF;
  IF (SELECT string_agg(format('%s/%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
            economic_value_cents, mei_consideration_cents, smallflags_qa_cents,
            smallflags_main_fee_cents, smallflags_total_remuneration_cents), ';'
            ORDER BY commercial_category, fidelized)
        FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 3)
     IS DISTINCT FROM
     'common/false/1999900/1192716/6084/801100/807184;common/true/1618800/1192716/6084/420000/426084;'
     || 'supermarket/false/2999900/2385432/12168/602300/614468;supermarket/true/2817600/2385432/12168/420000/432168' THEN
    v_falhas := v_falhas || 'agenda SF-v1.4 divergente'::text; END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 3
              AND (new_flag_units IS NOT NULL OR flag_production_charge_cents IS NOT NULL)) THEN
    v_falhas := v_falhas || 'SF-v1.4 ganhou fatos de bandeira'::text; END IF;
  IF (SELECT sum(economic_value_cents) FILTER (WHERE NOT fidelized AND commercial_category = 'supermarket')
           + 5 * sum(economic_value_cents) FILTER (WHERE NOT fidelized AND commercial_category = 'common')
        FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 4) <> 14763400 THEN
    v_falhas := v_falhas || 'formacao SF-v1.5 nao fidelizada <> 147.634,00'::text; END IF;
  IF (SELECT sum(economic_value_cents) FILTER (WHERE fidelized AND commercial_category = 'supermarket')
           + 5 * sum(economic_value_cents) FILTER (WHERE fidelized AND commercial_category = 'common')
        FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 4) <> 10911600 THEN
    v_falhas := v_falhas || 'formacao SF-v1.5 fidelizada <> 109.116,00'::text; END IF;
  IF cardinality(v_falhas) > 0 THEN
    RAISE EXCEPTION 'SF-v1.5 autoverificacao falhou: %', array_to_string(v_falhas, '; ');
  END IF;
END
$verif$;

-- Integridade do transporte: arquivo UTF-8 com LF. "Produção" em UTF-8 tem
-- os bytes c3 a7 c3 a3; mojibake ou CR abortam aqui, antes do COMMIT.
DO $z$
BEGIN
  IF convert_to('Produção', 'UTF8') <> '\x50726f6475c3a7c3a36f'::bytea THEN
    RAISE EXCEPTION 'transporte corrompeu a codificacao do arquivo';
  END IF;
  IF position(chr(13) in $cr$x
x$cr$) > 0 THEN
    RAISE EXCEPTION 'transporte introduziu CR no arquivo';
  END IF;
END
$z$;
