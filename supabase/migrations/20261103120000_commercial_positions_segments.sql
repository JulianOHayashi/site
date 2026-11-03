-- ============================================================================
-- SMALLFLAGS SITE — POSIÇÕES COMERCIAIS, CALÇADOS UNIFICADO E SEGMENTO OUTROS
-- Migration 20261103120000 · Etapa B da auditoria 14 · decisões D1–D9
--
-- PRINCÍPIOS
--   * Aditiva. Nada é apagado; nenhum pedido, intenção ou contrato existente é
--     reescrito. womens_footwear/mens_footwear permanecem como linhas
--     históricas (inativas para contratação nova) — FKs continuam válidas.
--   * POSIÇÃO ≠ SEGMENTO. commercial_opportunities.niche_code continua sendo a
--     POSIÇÃO comercial (6 por exclusividade, UNIQUE). O SEGMENTO efetivamente
--     contratado é um registro próprio (commercial_segments) copiado como
--     snapshot imutável em intenção, pedido, pré-compra e fila de venda.
--   * Supermercado nunca recebe segmento. A posição Outros sempre exige um.
--     Farmácia, Roupas F/M e Calçados podem ser ocupadas por um segmento de
--     Outros (substituição). Cada segmento (por classificação administrativa)
--     é único dentro da mesma exclusividade.
--   * Segmento não listado vira SOLICITAÇÃO (owner) e só existe após decisão
--     administrativa. Solicitação não reserva, não contrata, não aprova.
--   * Preço vigente preservado: Calçados e Outros usam a categoria common (D3).
--   * Fidelidade de segmento acompanha a CLASSIFICAÇÃO do segmento + CNPJ +
--     cidade (D4), não a posição.
--   * Provisionamento ao App falha fechado para formações com os códigos novos
--     ou com segmento (D8). Instrumento falha fechado para segmento (D9).
--   * D2 (remapeamento das oportunidades livres de calçados das exclusividades
--     em formação) está na seção B, guardado: aborta se houver qualquer
--     referência, em vez de pular em silêncio.
--
-- Sem push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A. CATÁLOGO DE NICHOS / POSIÇÕES (D1)
-- ---------------------------------------------------------------------------
ALTER TABLE public.commercial_niches
  DROP CONSTRAINT commercial_niches_canonical,
  DROP CONSTRAINT commercial_niches_code_allowed,
  DROP CONSTRAINT commercial_niches_sort_order_range;

-- Legados saem da ordem 1–6 (a ordem é única) e deixam de aceitar venda nova.
UPDATE public.commercial_niches
   SET sort_order = 105, is_active = false, updated_at = pg_catalog.now()
 WHERE code = 'womens_footwear';
UPDATE public.commercial_niches
   SET sort_order = 106, is_active = false, updated_at = pg_catalog.now()
 WHERE code = 'mens_footwear';

-- Só acrescenta as posições novas onde o catálogo já existe (Production e
-- staging). Em banco recém-criado o catálogo nasce do seed, já no formato novo.
INSERT INTO public.commercial_niches
  (code, display_name, contracted_quantity, sort_order, is_active)
SELECT v.code, v.display_name, 12, v.sort_order, true
  FROM (VALUES ('footwear', 'Calçados', 5), ('others', 'Outros', 6))
         AS v(code, display_name, sort_order)
 WHERE EXISTS (SELECT 1 FROM public.commercial_niches WHERE code = 'supermarket')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.commercial_niches
  ADD CONSTRAINT commercial_niches_code_allowed
    CHECK (code = ANY (ARRAY['supermarket','pharmacy','womens_clothing','mens_clothing','footwear','others','womens_footwear','mens_footwear'])),
  ADD CONSTRAINT commercial_niches_canonical CHECK (
       (code = 'supermarket'     AND contracted_quantity = 24 AND sort_order = 1)
    OR (code = 'pharmacy'        AND contracted_quantity = 12 AND sort_order = 2)
    OR (code = 'womens_clothing' AND contracted_quantity = 12 AND sort_order = 3)
    OR (code = 'mens_clothing'   AND contracted_quantity = 12 AND sort_order = 4)
    OR (code = 'footwear'        AND contracted_quantity = 12 AND sort_order = 5)
    OR (code = 'others'          AND contracted_quantity = 12 AND sort_order = 6)
    OR (code = 'womens_footwear' AND contracted_quantity = 12 AND sort_order = 105)
    OR (code = 'mens_footwear'   AND contracted_quantity = 12 AND sort_order = 106)),
  ADD CONSTRAINT commercial_niches_sort_order_range
    CHECK ((sort_order BETWEEN 1 AND 6) OR sort_order IN (105, 106)),
  ADD CONSTRAINT commercial_niches_legado_inativo
    CHECK (code NOT IN ('womens_footwear','mens_footwear') OR is_active = false);

COMMENT ON TABLE public.commercial_niches IS
  'Posicoes comerciais. Ativas: exatamente seis (supermarket 24; pharmacy, '
  'womens_clothing, mens_clothing, footwear e others 12) = 84 unidades. '
  'womens_footwear/mens_footwear sao historicos, inativos para venda nova.';

DO $inv$
DECLARE v_n int; v_u int;
BEGIN
  SELECT count(*), coalesce(sum(contracted_quantity),0) INTO v_n, v_u
    FROM public.commercial_niches WHERE is_active;
  -- Catálogo vazio (banco recém-criado) é válido: o seed o preenche.
  IF v_n > 0 AND (v_n <> 6 OR v_u <> 84) THEN
    RAISE EXCEPTION 'posicoes_ativas_invalidas: % posicoes, % unidades', v_n, v_u;
  END IF;
END $inv$;

-- ---------------------------------------------------------------------------
-- B. D2 — REMAPEAMENTO GUARDADO das oportunidades livres de calçados
--    em exclusividades AINDA EM FORMAÇÃO. Exclusividades fora de formação
--    mantêm os códigos históricos. Qualquer referência aborta a migration.
-- ---------------------------------------------------------------------------
DO $d2$
DECLARE
  r      record;
  v_refs bigint;
  v_novo text;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.commercial_sales_waitlist w
     WHERE w.niche_code IN ('womens_footwear','mens_footwear')
       AND w.status IN ('waiting','contact_pending','invited',
                        'reservation_offered','reservation_accepted')) THEN
    RAISE EXCEPTION 'd2_bloqueado: fila de venda ativa com codigo legado de calcados';
  END IF;

  FOR r IN
    SELECT o.*
      FROM public.commercial_opportunities o
      JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
     WHERE o.niche_code IN ('womens_footwear','mens_footwear')
       AND e.status = 'forming'
     ORDER BY o.exclusivity_id, o.niche_code
  LOOP
    IF r.status <> 'available' THEN
      RAISE EXCEPTION 'd2_bloqueado: oportunidade % (%) em status %',
        r.id, r.niche_code, r.status;
    END IF;

    SELECT (SELECT count(*) FROM public.commercial_checkout_intents i
             WHERE i.opportunity_id = r.id)
         + (SELECT count(*) FROM public.commercial_exclusivity_orders o2
             WHERE o2.opportunity_id = r.id)
         + (SELECT count(*) FROM public.commercial_preorders p
             WHERE p.target_exclusivity_id = r.exclusivity_id
               AND p.niche_code = r.niche_code)
      INTO v_refs;
    IF v_refs > 0 THEN
      RAISE EXCEPTION 'd2_bloqueado: oportunidade % (%) possui % referencia(s)',
        r.id, r.niche_code, v_refs;
    END IF;

    v_novo := CASE r.niche_code WHEN 'womens_footwear' THEN 'footwear' ELSE 'others' END;

    UPDATE public.commercial_opportunities
       SET niche_code = v_novo, updated_at = pg_catalog.now()
     WHERE id = r.id;

    INSERT INTO public.audit_logs
      (actor_role, action, entity_type, entity_id, previous_state, new_state,
       source, metadata)
    VALUES
      ('system', 'commercial_opportunity.position_remapped',
       'commercial_opportunity', r.id::text,
       pg_catalog.jsonb_build_object('niche_code', r.niche_code, 'status', r.status),
       pg_catalog.jsonb_build_object('niche_code', v_novo, 'status', r.status),
       'migration_20261103120000',
       pg_catalog.jsonb_build_object('decision', 'D2',
                                     'exclusivity_id', r.exclusivity_id));
  END LOOP;
END $d2$;

-- ---------------------------------------------------------------------------
-- C. CATÁLOGO DE SEGMENTOS (Outros e substitutos)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commercial_normalize_segment_label(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT pg_catalog.btrim(pg_catalog.regexp_replace(
           pg_catalog.translate(pg_catalog.lower(coalesce(p, '')),
             'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
           '[^a-z0-9]+', ' ', 'g'));
$$;
REVOKE ALL ON FUNCTION public.commercial_normalize_segment_label(text) FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE public.commercial_segments (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 text NOT NULL UNIQUE,
  display_name         text NOT NULL,
  -- Classificação ADMINISTRATIVA. É a identidade comercial do segmento:
  -- exclusividade e fidelidade usam esta chave, nunca o texto exibido.
  classification_key   text NOT NULL,
  description          text,
  overlaps_niche_code  text REFERENCES public.commercial_niches(code),
  delimitation_policy  text,
  status               text NOT NULL DEFAULT 'approved',
  created_by           uuid REFERENCES auth.users(id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  approved_by          uuid NOT NULL REFERENCES auth.users(id),
  approved_at          timestamptz NOT NULL DEFAULT now(),
  archived_by          uuid REFERENCES auth.users(id),
  archived_at          timestamptz,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cs_code_formato
    CHECK (code ~ '^[a-z][a-z0-9_]{2,47}$'),
  CONSTRAINT cs_classificacao_formato
    CHECK (classification_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  CONSTRAINT cs_nao_e_posicao_canonica
    CHECK (code <> ALL (ARRAY['supermarket','pharmacy','womens_clothing','mens_clothing','footwear','others','womens_footwear','mens_footwear'])
       AND classification_key <> ALL (ARRAY['supermarket','pharmacy','womens_clothing','mens_clothing','footwear','others','womens_footwear','mens_footwear'])),
  CONSTRAINT cs_nome
    CHECK (length(btrim(display_name)) BETWEEN 3 AND 80),
  CONSTRAINT cs_descricao
    CHECK (description IS NULL OR length(description) <= 500),
  CONSTRAINT cs_status CHECK (status IN ('approved','archived')),
  CONSTRAINT cs_arquivo_coerente
    CHECK ((status = 'archived') = (archived_at IS NOT NULL AND archived_by IS NOT NULL)),
  -- Sobreposição a nicho canônico só existe com política expressa (D5).
  CONSTRAINT cs_sobreposicao_alvo
    CHECK (overlaps_niche_code IS NULL OR overlaps_niche_code IN
           ('supermarket','pharmacy','womens_clothing','mens_clothing','footwear')),
  CONSTRAINT cs_sobreposicao_exige_delimitacao
    CHECK (overlaps_niche_code IS NULL
           OR length(btrim(coalesce(delimitation_policy, ''))) >= 20)
);

-- Uma classificação aprovada por vez: nomes diferentes do mesmo segmento não
-- geram exclusividade nem fidelidade paralelas.
CREATE UNIQUE INDEX cs_classificacao_aprovada_uidx
  ON public.commercial_segments (classification_key) WHERE status = 'approved';

CREATE OR REPLACE FUNCTION public.commercial_segments_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'commercial_segment_immutable: segmento nao pode ser excluido; arquive';
  END IF;
  IF NEW.code IS DISTINCT FROM OLD.code
  OR NEW.classification_key IS DISTINCT FROM OLD.classification_key
  OR NEW.display_name IS DISTINCT FROM OLD.display_name
  OR NEW.description IS DISTINCT FROM OLD.description
  OR NEW.overlaps_niche_code IS DISTINCT FROM OLD.overlaps_niche_code
  OR NEW.delimitation_policy IS DISTINCT FROM OLD.delimitation_policy
  OR NEW.created_by IS DISTINCT FROM OLD.created_by
  OR NEW.created_at IS DISTINCT FROM OLD.created_at
  OR NEW.approved_by IS DISTINCT FROM OLD.approved_by
  OR NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
    RAISE EXCEPTION 'commercial_segment_immutable: identidade do segmento e imutavel';
  END IF;
  IF OLD.status = 'archived' AND NEW.status <> 'archived' THEN
    RAISE EXCEPTION 'commercial_segment_immutable: segmento arquivado nao volta';
  END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.commercial_segments_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cs_protect
  BEFORE UPDATE OR DELETE ON public.commercial_segments
  FOR EACH ROW EXECUTE FUNCTION public.commercial_segments_protect();

ALTER TABLE public.commercial_segments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_segments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commercial_segments TO service_role;

-- ---------------------------------------------------------------------------
-- D. SOLICITAÇÕES DE SEGMENTO NÃO LISTADO (D6)
-- ---------------------------------------------------------------------------
CREATE TABLE public.commercial_segment_requests (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES public.site_partner_companies(id),
  requested_by         uuid NOT NULL REFERENCES auth.users(id),
  requested_label      text NOT NULL,
  normalized_label     text NOT NULL,
  justification        text,
  intended_niche_code  text REFERENCES public.commercial_niches(code),
  status               text NOT NULL DEFAULT 'pending',
  decided_by           uuid REFERENCES auth.users(id),
  decided_at           timestamptz,
  decision_note        text,
  resulting_segment_id uuid REFERENCES public.commercial_segments(id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT csr_rotulo CHECK (length(btrim(requested_label)) BETWEEN 3 AND 80),
  CONSTRAINT csr_rotulo_normalizado CHECK (length(normalized_label) >= 3),
  CONSTRAINT csr_justificativa CHECK (justification IS NULL OR length(justification) <= 1000),
  CONSTRAINT csr_posicao_pretendida
    CHECK (intended_niche_code IS NULL OR intended_niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others')),
  CONSTRAINT csr_status CHECK (status IN ('pending','approved','rejected','cancelled')),
  CONSTRAINT csr_decisao_coerente
    CHECK ((status = 'pending') = (decided_at IS NULL AND decided_by IS NULL)),
  CONSTRAINT csr_aprovada_tem_segmento
    CHECK ((status = 'approved') = (resulting_segment_id IS NOT NULL)),
  CONSTRAINT csr_rejeicao_motivada
    CHECK (status <> 'rejected' OR length(btrim(coalesce(decision_note, ''))) >= 5)
);
CREATE UNIQUE INDEX csr_pendente_por_empresa_uidx
  ON public.commercial_segment_requests (company_id, normalized_label)
  WHERE status = 'pending';
CREATE INDEX csr_status_idx
  ON public.commercial_segment_requests (status, created_at);

CREATE OR REPLACE FUNCTION public.commercial_segment_requests_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'commercial_segment_request_immutable: solicitacao nao pode ser excluida';
  END IF;
  IF OLD.status <> 'pending' THEN
    RAISE EXCEPTION 'commercial_segment_request_immutable: solicitacao ja decidida';
  END IF;
  IF NEW.company_id IS DISTINCT FROM OLD.company_id
  OR NEW.requested_by IS DISTINCT FROM OLD.requested_by
  OR NEW.requested_label IS DISTINCT FROM OLD.requested_label
  OR NEW.normalized_label IS DISTINCT FROM OLD.normalized_label
  OR NEW.justification IS DISTINCT FROM OLD.justification
  OR NEW.intended_niche_code IS DISTINCT FROM OLD.intended_niche_code
  OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'commercial_segment_request_immutable: conteudo da solicitacao e imutavel';
  END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.commercial_segment_requests_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER csr_protect
  BEFORE UPDATE OR DELETE ON public.commercial_segment_requests
  FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_requests_protect();

ALTER TABLE public.commercial_segment_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_segment_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.commercial_segment_requests TO service_role;

-- ---------------------------------------------------------------------------
-- E. SNAPSHOT DO SEGMENTO EM INTENÇÃO, PEDIDO, PRÉ-COMPRA E FILA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commercial_segment_snapshot_imutavel()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF NEW.segment_id IS DISTINCT FROM OLD.segment_id
  OR NEW.segment_code_snapshot IS DISTINCT FROM OLD.segment_code_snapshot
  OR NEW.segment_name_snapshot IS DISTINCT FROM OLD.segment_name_snapshot
  OR NEW.segment_classification_snapshot
       IS DISTINCT FROM OLD.segment_classification_snapshot THEN
    RAISE EXCEPTION 'commercial_segment_snapshot_immutable';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.commercial_segment_snapshot_imutavel() FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN segment_id uuid REFERENCES public.commercial_segments(id),
  ADD COLUMN segment_code_snapshot text,
  ADD COLUMN segment_name_snapshot text,
  ADD COLUMN segment_classification_snapshot text;
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_segmento_snapshot_coerente CHECK (
       (segment_id IS NULL AND segment_code_snapshot IS NULL
        AND segment_name_snapshot IS NULL AND segment_classification_snapshot IS NULL)
    OR (segment_id IS NOT NULL AND segment_code_snapshot IS NOT NULL
        AND segment_name_snapshot IS NOT NULL AND segment_classification_snapshot IS NOT NULL)),
  ADD CONSTRAINT cci_supermercado_sem_segmento
    CHECK (niche_code <> 'supermarket' OR segment_id IS NULL),
  ADD CONSTRAINT cci_segmento_posicao_elegivel
    CHECK (segment_id IS NULL OR niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others')),
  ADD CONSTRAINT cci_outros_exige_segmento
    CHECK (niche_code <> 'others' OR segment_id IS NOT NULL);
CREATE TRIGGER cci_segmento_imutavel
  BEFORE UPDATE ON public.commercial_checkout_intents
  FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel();

ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN segment_id uuid REFERENCES public.commercial_segments(id),
  ADD COLUMN segment_code_snapshot text,
  ADD COLUMN segment_name_snapshot text,
  ADD COLUMN segment_classification_snapshot text;
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_segmento_snapshot_coerente CHECK (
       (segment_id IS NULL AND segment_code_snapshot IS NULL
        AND segment_name_snapshot IS NULL AND segment_classification_snapshot IS NULL)
    OR (segment_id IS NOT NULL AND segment_code_snapshot IS NOT NULL
        AND segment_name_snapshot IS NOT NULL AND segment_classification_snapshot IS NOT NULL)),
  ADD CONSTRAINT ceo_supermercado_sem_segmento
    CHECK (niche_code <> 'supermarket' OR segment_id IS NULL),
  ADD CONSTRAINT ceo_segmento_posicao_elegivel
    CHECK (segment_id IS NULL OR niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others')),
  ADD CONSTRAINT ceo_outros_exige_segmento
    CHECK (niche_code <> 'others' OR segment_id IS NOT NULL);
CREATE TRIGGER ceo_segmento_imutavel
  BEFORE UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel();

ALTER TABLE public.commercial_preorders
  ADD COLUMN segment_id uuid REFERENCES public.commercial_segments(id),
  ADD COLUMN segment_code_snapshot text,
  ADD COLUMN segment_name_snapshot text,
  ADD COLUMN segment_classification_snapshot text;
ALTER TABLE public.commercial_preorders
  ADD CONSTRAINT cpo_segmento_snapshot_coerente CHECK (
       (segment_id IS NULL AND segment_code_snapshot IS NULL
        AND segment_name_snapshot IS NULL AND segment_classification_snapshot IS NULL)
    OR (segment_id IS NOT NULL AND segment_code_snapshot IS NOT NULL
        AND segment_name_snapshot IS NOT NULL AND segment_classification_snapshot IS NOT NULL)),
  ADD CONSTRAINT cpo_supermercado_sem_segmento
    CHECK (niche_code <> 'supermarket' OR segment_id IS NULL),
  ADD CONSTRAINT cpo_segmento_posicao_elegivel
    CHECK (segment_id IS NULL OR niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others')),
  ADD CONSTRAINT cpo_outros_exige_segmento
    CHECK (niche_code <> 'others' OR segment_id IS NOT NULL);
CREATE TRIGGER cpo_segmento_imutavel
  BEFORE UPDATE ON public.commercial_preorders
  FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel();

ALTER TABLE public.commercial_sales_waitlist
  ADD COLUMN segment_id uuid REFERENCES public.commercial_segments(id),
  ADD COLUMN segment_code_snapshot text,
  ADD COLUMN segment_name_snapshot text,
  ADD COLUMN segment_classification_snapshot text;
ALTER TABLE public.commercial_sales_waitlist
  ADD CONSTRAINT csw_segmento_snapshot_coerente CHECK (
       (segment_id IS NULL AND segment_code_snapshot IS NULL
        AND segment_name_snapshot IS NULL AND segment_classification_snapshot IS NULL)
    OR (segment_id IS NOT NULL AND segment_code_snapshot IS NOT NULL
        AND segment_name_snapshot IS NOT NULL AND segment_classification_snapshot IS NOT NULL)),
  ADD CONSTRAINT csw_supermercado_sem_segmento
    CHECK (niche_code <> 'supermarket' OR segment_id IS NULL),
  ADD CONSTRAINT csw_segmento_posicao_elegivel
    CHECK (segment_id IS NULL OR niche_code IN ('pharmacy','womens_clothing','mens_clothing','footwear','others')),
  ADD CONSTRAINT csw_outros_exige_segmento
    CHECK (niche_code <> 'others' OR segment_id IS NOT NULL);
CREATE TRIGGER csw_segmento_imutavel
  BEFORE UPDATE ON public.commercial_sales_waitlist
  FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel();

-- Um segmento efetivo por exclusividade (pedidos vivos), pela CLASSIFICAÇÃO.
CREATE UNIQUE INDEX ceo_segmento_por_exclusividade_idx
  ON public.commercial_exclusivity_orders (exclusivity_id, segment_classification_snapshot)
  WHERE status <> 'cancelled' AND segment_id IS NOT NULL;
-- Idem para pré-compras ativas da próxima exclusividade.
CREATE UNIQUE INDEX cpo_segmento_por_exclusividade_idx
  ON public.commercial_preorders (target_exclusivity_id, segment_classification_snapshot)
  WHERE segment_id IS NOT NULL
    AND status IN ('waiting','reservation_offered','reservation_accepted');

-- O pedido vindo de checkout carrega EXATAMENTE o segmento da intenção.
CREATE OR REPLACE FUNCTION public.ceo_segmento_da_intencao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_i public.commercial_checkout_intents%ROWTYPE;
BEGIN
  IF NEW.checkout_intent_id IS NOT NULL THEN
    SELECT * INTO v_i FROM public.commercial_checkout_intents
     WHERE id = NEW.checkout_intent_id;
    IF NOT FOUND
       OR NEW.segment_id IS DISTINCT FROM v_i.segment_id
       OR NEW.segment_classification_snapshot
            IS DISTINCT FROM v_i.segment_classification_snapshot
       OR NEW.niche_code IS DISTINCT FROM v_i.niche_code THEN
      RAISE EXCEPTION 'commercial_order_segment_mismatch';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.ceo_segmento_da_intencao() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ceo_segmento_da_intencao
  BEFORE INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_segmento_da_intencao();

-- ---------------------------------------------------------------------------
-- F. FIDELIDADE POR IDENTIDADE COMERCIAL (D4)
--    identidade = niche_code (posição canônica, como sempre foi) OU
--                 'segment:' || classificação do segmento contratado.
-- ---------------------------------------------------------------------------
ALTER TABLE public.commercial_fidelity_records ADD COLUMN fidelity_identity text;
UPDATE public.commercial_fidelity_records
   SET fidelity_identity = niche_code WHERE fidelity_identity IS NULL;
ALTER TABLE public.commercial_fidelity_records
  ALTER COLUMN fidelity_identity SET NOT NULL,
  ADD CONSTRAINT cfr_identidade_formato
    CHECK (fidelity_identity = niche_code
           OR fidelity_identity ~ '^segment:[a-z][a-z0-9_]{2,63}$');

CREATE OR REPLACE FUNCTION public.cfr_derivar_identidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_cls text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.fidelity_identity IS DISTINCT FROM OLD.fidelity_identity THEN
      RAISE EXCEPTION 'commercial_fidelity_identity_immutable';
    END IF;
    RETURN NEW;
  END IF;
  -- Derivada do pedido fundador; o chamador não escolhe.
  SELECT o.segment_classification_snapshot INTO v_cls
    FROM public.commercial_exclusivity_orders o
   WHERE o.id = NEW.established_by_order_id;
  NEW.fidelity_identity := CASE WHEN v_cls IS NOT NULL
                                THEN 'segment:' || v_cls
                                ELSE NEW.niche_code END;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.cfr_derivar_identidade() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cfr_derivar_identidade
  BEFORE INSERT OR UPDATE ON public.commercial_fidelity_records
  FOR EACH ROW EXECUTE FUNCTION public.cfr_derivar_identidade();

ALTER TABLE public.commercial_fidelity_records DROP CONSTRAINT cfr_unico;
CREATE UNIQUE INDEX cfr_identidade_unica
  ON public.commercial_fidelity_records (cnpj, uf, city_key, fidelity_identity);

CREATE OR REPLACE FUNCTION public.commercial_fidelity_identity(
  p_niche_code text, p_segment_id uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT CASE WHEN p_segment_id IS NULL THEN p_niche_code
              ELSE (SELECT 'segment:' || s.classification_key
                      FROM public.commercial_segments s
                     WHERE s.id = p_segment_id) END;
$$;
REVOKE ALL ON FUNCTION public.commercial_fidelity_identity(text, uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_fidelized_context(
  p_cnpj text, p_uf text, p_city text, p_niche_code text, p_segment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.commercial_fidelity_records f
     WHERE f.cnpj = public.somente_digitos(p_cnpj)
       AND f.uf = pg_catalog.upper(pg_catalog.btrim(p_uf))
       AND f.city_key = public.commercial_city_key(p_city)
       AND f.fidelity_identity = public.commercial_fidelity_identity(p_niche_code, p_segment_id)
       -- R15: pedido fundador cancelado não sustenta fidelidade futura.
       AND NOT EXISTS (
             SELECT 1 FROM public.commercial_exclusivity_orders o
              WHERE o.id = f.established_by_order_id
                AND o.status = 'cancelled'));
$$;
REVOKE ALL ON FUNCTION public.is_fidelized_context(text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_fidelized_context(text, text, text, text, uuid) TO service_role;

-- A assinatura antiga (posição sem segmento) passa a comparar pela identidade,
-- para que um registro de segmento nunca seja lido como fidelidade da posição.
CREATE OR REPLACE FUNCTION public.is_fidelized_context(
  p_cnpj text, p_uf text, p_city text, p_niche_code text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT public.is_fidelized_context(p_cnpj, p_uf, p_city, p_niche_code, NULL::uuid);
$$;

-- ---------------------------------------------------------------------------
-- G. RESOLVEDOR ÚNICO posição × segmento (servidor é a autoridade)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.commercial_resolve_position_segment(
  p_niche_code       text,
  p_segment_id       uuid,
  p_exclusivity_id   uuid,
  p_opportunity_id   uuid,
  p_check_exclusivity boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_s public.commercial_segments%ROWTYPE;
BEGIN
  IF p_niche_code = 'supermarket' AND p_segment_id IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'supermarket_not_substitutable');
  END IF;
  IF p_segment_id IS NULL THEN
    IF p_niche_code = 'others' THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_required');
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'segment_id', NULL);
  END IF;
  IF p_niche_code IS NULL OR p_niche_code NOT IN ('pharmacy','womens_clothing','mens_clothing','footwear','others') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'position_not_substitutable');
  END IF;

  SELECT * INTO v_s FROM public.commercial_segments WHERE id = p_segment_id;
  IF NOT FOUND OR v_s.status <> 'approved' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_not_approved');
  END IF;

  IF p_check_exclusivity AND p_exclusivity_id IS NOT NULL THEN
    -- Serializa quem disputa o MESMO segmento na MESMA exclusividade, mesmo
    -- que em posições diferentes (o FOR UPDATE da oportunidade não cobre isso).
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'commercial_segment:' || p_exclusivity_id::text || ':' || v_s.classification_key, 0));
    IF EXISTS (
         SELECT 1 FROM public.commercial_exclusivity_orders o
          WHERE o.exclusivity_id = p_exclusivity_id
            AND o.status <> 'cancelled'
            AND o.segment_classification_snapshot = v_s.classification_key
            AND o.opportunity_id IS DISTINCT FROM p_opportunity_id)
       OR EXISTS (
         SELECT 1 FROM public.commercial_checkout_intents i
          WHERE i.exclusivity_id = p_exclusivity_id
            AND i.segment_classification_snapshot = v_s.classification_key
            AND i.opportunity_id IS DISTINCT FROM p_opportunity_id
            AND i.status IN ('draft','awaiting_contract')
            AND i.reserved_until IS NOT NULL
            AND i.reserved_until > pg_catalog.now()) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_already_in_exclusivity');
    END IF;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'segment_id', v_s.id,
    'segment_code', v_s.code,
    'segment_name', v_s.display_name,
    'segment_classification', v_s.classification_key,
    'overlaps_niche_code', v_s.overlaps_niche_code);
END;
$$;
REVOKE ALL ON FUNCTION public.commercial_resolve_position_segment(text, uuid, uuid, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- H. CHECKOUT: create_commercial_checkout_intent ganha p_segment_id (opcional)
--    A assinatura antiga é removida para não criar chamada ambígua; a nova
--    aceita exatamente as mesmas chamadas de três argumentos.
-- ---------------------------------------------------------------------------
DROP FUNCTION public.create_commercial_checkout_intent(uuid, text, text);
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
REVOKE ALL ON FUNCTION public.create_commercial_checkout_intent(uuid, text, text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid, text, text, uuid) TO authenticated;

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
    'participant_target', p_i.participant_target);
$function$;

-- ---------------------------------------------------------------------------
-- I. FINALIZAÇÃO copia o segmento da intenção; fidelidade por identidade
-- ---------------------------------------------------------------------------
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
     legal_acceptance_id, checkout_intent_id,
     segment_id, segment_code_snapshot, segment_name_snapshot,
     segment_classification_snapshot)
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
     v_ace.id, v_i.id,
     v_i.segment_id, v_i.segment_code_snapshot, v_i.segment_name_snapshot,
     v_i.segment_classification_snapshot)
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
  -- Identidade derivada por cfr_derivar_identidade (D4).
  ON CONFLICT DO NOTHING;

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

-- ---------------------------------------------------------------------------
-- J. VENDA MANUAL ADMINISTRATIVA ganha p_segment_id (opcional, no fim)
-- ---------------------------------------------------------------------------
DROP FUNCTION public.admin_register_manual_commercial_order(uuid, uuid, text, timestamp with time zone, text, date, text, text, text, text, integer);
CREATE OR REPLACE FUNCTION public.admin_register_manual_commercial_order(p_opportunity_id uuid, p_company_id uuid, p_order_version text, p_signed_at timestamp with time zone, p_signatory_name text, p_expected_operation_start date, p_benefit_settlement_mode text, p_document_reference text DEFAULT NULL::text, p_document_hash text DEFAULT NULL::text, p_external_signature_ref text DEFAULT NULL::text, p_exclusivity_period_days integer DEFAULT 28, p_segment_id uuid DEFAULT NULL::uuid)
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
  v_seg      jsonb;
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

  -- Mesma regra posição × segmento do checkout público.
  v_seg := public.commercial_resolve_position_segment(
             v_opp.niche_code, p_segment_id, v_opp.exclusivity_id, v_opp.id, true);
  IF (v_seg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_seg;
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
      v_cnpj, v_region.uf, v_company.city, v_opp.niche_code, p_segment_id);

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
     expected_operation_start, exclusivity_period_days, registered_by,
     segment_id, segment_code_snapshot, segment_name_snapshot,
     segment_classification_snapshot)
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
     p_expected_operation_start, p_exclusivity_period_days, auth.uid(),
     (v_seg->>'segment_id')::uuid, v_seg->>'segment_code',
     v_seg->>'segment_name', v_seg->>'segment_classification')
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
  -- Identidade derivada por cfr_derivar_identidade (D4).
  ON CONFLICT DO NOTHING;

  PERFORM public.m1_auditar('commercial_order.manually_registered', v_id, 'admin',
    pg_catalog.jsonb_build_object(
      'pricing_rule_version', v_versao,
      'benefit_settlement_mode', p_benefit_settlement_mode,
      'payment_method', v_pricing->>'payment_method',
      'economic_value_cents', v_eco_grav,
      'contract_economics_version', v_econ_versao,
      'total_monetary_funding_required_cents', v_total_grav),
    NULL,
    pg_catalog.jsonb_build_object('opportunity_id', p_opportunity_id,
      'segment_code', v_seg->>'segment_code',
      'segment_classification', v_seg->>'segment_classification'));

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
REVOKE ALL ON FUNCTION public.admin_register_manual_commercial_order(uuid, uuid, text, timestamp with time zone, text, date, text, text, text, text, integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_register_manual_commercial_order(uuid, uuid, text, timestamp with time zone, text, date, text, text, text, text, integer, uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- K. PREÇO: categoria explícita (D3). Valores inalterados.
-- ---------------------------------------------------------------------------
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
    );
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

-- ---------------------------------------------------------------------------
-- L. FORMAÇÃO PÚBLICA: posição + segmento ocupante (chaves aditivas)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_current_commercial_formation(p_uf text, p_city text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_region jsonb;
  v_region_id uuid;
  v_exc record;
  v_opportunities jsonb;
  v_summary jsonb;
begin
  v_region := public.resolve_commercial_region(p_uf, p_city);

  if coalesce((v_region->>'region_available')::boolean, false) = false then
    return jsonb_build_object('region_available', false, 'region', v_region);
  end if;

  v_region_id := (v_region->>'region_id')::uuid;

  select e.* into v_exc
    from public.commercial_exclusivities e
    where e.region_id = v_region_id and e.is_current
    limit 1;

  if v_exc.id is null then
    return jsonb_build_object(
      'region_available', true,
      'exclusivity_available', false,
      'region', v_region
    );
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'id',                  o.id,
             'exclusivity_id',      o.exclusivity_id,
             'niche_code',          o.niche_code,
             'display_name',        n.display_name,
             'contracted_quantity', o.contracted_quantity,
             'status',              o.status,
             'sort_order',          n.sort_order,
             'accepts_segment',     o.niche_code in ('pharmacy','womens_clothing','mens_clothing','footwear','others'),
             'requires_segment',    o.niche_code = 'others',
             -- Segmento que ocupa a posição (pedido vivo ou reserva viva).
             -- Somente nome e código públicos; empresa e valores não saem.
             'segment',             coalesce(
               (select jsonb_build_object('code', x.segment_code_snapshot,
                                          'name', x.segment_name_snapshot)
                  from public.commercial_exclusivity_orders x
                 where x.opportunity_id = o.id and x.status <> 'cancelled'
                   and x.segment_id is not null
                 limit 1),
               (select jsonb_build_object('code', y.segment_code_snapshot,
                                          'name', y.segment_name_snapshot)
                  from public.commercial_checkout_intents y
                 where y.opportunity_id = o.id and y.segment_id is not null
                   and y.status in ('draft','awaiting_contract')
                   and y.reserved_until > now()
                 limit 1))
           ) order by n.sort_order
         )
    into v_opportunities
    from public.commercial_opportunities o
    join public.commercial_niches n on n.code = o.niche_code
    where o.exclusivity_id = v_exc.id;

  v_summary := public.commercial_formation_summary(v_exc.id);

  return jsonb_build_object(
    'region_available', true,
    'exclusivity_available', true,
    'region', v_region,
    'exclusivity', jsonb_build_object(
      'id',              v_exc.id,
      'region_id',       v_exc.region_id,
      'sequence_number', v_exc.sequence_number,
      'status',          v_exc.status,
      'is_current',      v_exc.is_current,
      'planned_start_at',v_exc.planned_start_at
    ),
    'summary', v_summary,
    'opportunities', coalesce(v_opportunities, '[]'::jsonb)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- M. PRÉ-COMPRA E FILA DE VENDA preservam o segmento (D7)
-- ---------------------------------------------------------------------------
DROP FUNCTION public.join_my_commercial_future_queue(uuid, text);
CREATE OR REPLACE FUNCTION public.join_my_commercial_future_queue(p_company_id uuid, p_niche_code text, p_segment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_company public.site_partner_companies%ROWTYPE;
  v_region jsonb;
  v_region_id uuid;
  v_current public.commercial_exclusivities%ROWTYPE;
  v_next public.commercial_exclusivities%ROWTYPE;
  v_opp public.commercial_opportunities%ROWTYPE;
  v_pre public.commercial_preorders%ROWTYPE;
  v_wait public.commercial_sales_waitlist%ROWTYPE;
  v_position bigint;
  v_id uuid;
  v_seg jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  SELECT * INTO v_company
    FROM public.site_partner_companies
   WHERE id = p_company_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.commercial_niches n
     WHERE n.code = p_niche_code AND n.is_active
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_niche');
  END IF;

  -- D7: o interesse futuro guarda o segmento efetivo desde já. A unicidade do
  -- segmento na próxima exclusividade é garantida pelo índice da pré-compra.
  v_seg := public.commercial_resolve_position_segment(
             p_niche_code, p_segment_id, NULL, NULL, false);
  IF (v_seg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_seg;
  END IF;

  v_region := public.resolve_commercial_region(v_company.uf, v_company.city);
  IF coalesce((v_region->>'region_available')::boolean, false) IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'region_not_operating');
  END IF;
  v_region_id := (v_region->>'region_id')::uuid;

  SELECT * INTO v_current
    FROM public.commercial_exclusivities e
   WHERE e.region_id = v_region_id AND e.is_current
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_current_exclusivity');
  END IF;

  SELECT * INTO v_opp
    FROM public.commercial_opportunities o
   WHERE o.exclusivity_id = v_current.id
     AND o.niche_code = p_niche_code
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_found');
  END IF;

  IF v_opp.status = 'available' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'current_opportunity_available');
  END IF;

  INSERT INTO public.commercial_exclusivities
    (region_id, sequence_number, status, is_current)
  VALUES
    (v_region_id, v_current.sequence_number + 1, 'forming', false)
  ON CONFLICT (region_id, sequence_number) DO NOTHING;

  SELECT * INTO v_next
    FROM public.commercial_exclusivities e
   WHERE e.region_id = v_region_id
     AND e.sequence_number = v_current.sequence_number + 1
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'next_exclusivity_unavailable');
  END IF;

  SELECT * INTO v_pre
    FROM public.commercial_preorders p
   WHERE p.target_exclusivity_id = v_next.id
     AND p.company_id = p_company_id
     AND p.status IN ('waiting','reservation_offered','reservation_accepted')
   ORDER BY p.created_at
   LIMIT 1;

  IF FOUND THEN
    IF v_pre.niche_code = p_niche_code
       AND v_pre.segment_id IS NOT DISTINCT FROM p_segment_id THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', true, 'already', true, 'mode', 'preorder',
        'preorder_id', v_pre.id,
        'status', v_pre.status,
        'target_exclusivity_id', v_next.id,
        'target_sequence_number', v_next.sequence_number);
    END IF;

    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'company_already_preordered_next_exclusivity',
      'target_sequence_number', v_next.sequence_number);
  END IF;

  v_id := NULL;
  INSERT INTO public.commercial_preorders
    (company_id, region_id, niche_code, target_exclusivity_id,
     status, source, created_by,
     segment_id, segment_code_snapshot, segment_name_snapshot,
     segment_classification_snapshot)
  VALUES
    (p_company_id, v_region_id, p_niche_code, v_next.id,
     'waiting', 'site', v_uid,
     (v_seg->>'segment_id')::uuid, v_seg->>'segment_code',
     v_seg->>'segment_name', v_seg->>'segment_classification')
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    PERFORM public.m1_auditar(
      'commercial_preorder.interest_registered',
      v_id,
      'owner',
      pg_catalog.jsonb_build_object(
        'company_id', p_company_id,
        'region_id', v_region_id,
        'niche_code', p_niche_code,
        'target_exclusivity_id', v_next.id,
        'target_sequence_number', v_next.sequence_number,
        'status', 'waiting'),
      NULL::jsonb,
      pg_catalog.jsonb_build_object(
        'contract_created', false,
        'reservation_created', false,
        'payment_started', false)
    );

    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'already', false, 'mode', 'preorder',
      'preorder_id', v_id,
      'status', 'waiting',
      'target_exclusivity_id', v_next.id,
      'target_sequence_number', v_next.sequence_number);
  END IF;

  SELECT * INTO v_wait
    FROM public.commercial_sales_waitlist w
   WHERE w.company_id = p_company_id
     AND w.region_id = v_region_id
     AND w.niche_code = p_niche_code
     AND w.status IN (
       'waiting','contact_pending','invited',
       'reservation_offered','reservation_accepted')
   ORDER BY w.created_at
   LIMIT 1;
  IF FOUND AND v_wait.segment_id IS DISTINCT FROM p_segment_id THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'company_already_waitlisted_other_segment');
  END IF;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'already', true, 'mode', 'sales_waitlist',
      'waitlist_id', v_wait.id,
      'status', v_wait.status,
      'position', v_wait.position,
      'first_possible_exclusivity_sequence',
        v_wait.first_possible_exclusivity_sequence);
  END IF;

  INSERT INTO public.commercial_sales_waitlist_counters
    (region_id, niche_code, next_position)
  VALUES
    (v_region_id, p_niche_code, 2)
  ON CONFLICT (region_id, niche_code)
  DO UPDATE SET next_position =
    commercial_sales_waitlist_counters.next_position + 1
  RETURNING next_position - 1 INTO v_position;

  INSERT INTO public.commercial_sales_waitlist
    (company_id, region_id, niche_code,
     first_possible_exclusivity_sequence, position,
     status, source, created_by,
     segment_id, segment_code_snapshot, segment_name_snapshot,
     segment_classification_snapshot)
  VALUES
    (p_company_id, v_region_id, p_niche_code,
     v_next.sequence_number + 1, v_position,
     'waiting', 'site', v_uid,
     (v_seg->>'segment_id')::uuid, v_seg->>'segment_code',
     v_seg->>'segment_name', v_seg->>'segment_classification')
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT * INTO v_wait
      FROM public.commercial_sales_waitlist w
     WHERE w.company_id = p_company_id
       AND w.region_id = v_region_id
       AND w.niche_code = p_niche_code
       AND w.status IN (
         'waiting','contact_pending','invited',
         'reservation_offered','reservation_accepted')
     ORDER BY w.created_at
     LIMIT 1;

    IF FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', true, 'already', true, 'mode', 'sales_waitlist',
        'waitlist_id', v_wait.id,
        'status', v_wait.status,
        'position', v_wait.position,
        'first_possible_exclusivity_sequence',
          v_wait.first_possible_exclusivity_sequence);
    END IF;

    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'queue_conflict');
  END IF;

  PERFORM public.m1_auditar(
    'commercial_sales_waitlist.joined',
    v_id,
    'owner',
    pg_catalog.jsonb_build_object(
      'company_id', p_company_id,
      'region_id', v_region_id,
      'niche_code', p_niche_code,
      'position', v_position,
      'first_possible_exclusivity_sequence', v_next.sequence_number + 1,
      'status', 'waiting'),
    NULL::jsonb,
    pg_catalog.jsonb_build_object('position_immutable', true)
  );

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false, 'mode', 'sales_waitlist',
    'waitlist_id', v_id,
    'status', 'waiting',
    'position', v_position,
    'first_possible_exclusivity_sequence', v_next.sequence_number + 1);
END;
$function$;
REVOKE ALL ON FUNCTION public.join_my_commercial_future_queue(uuid, text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.join_my_commercial_future_queue(uuid, text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_commercial_future_interest(p_company_id uuid, p_niche_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_pre public.commercial_preorders%ROWTYPE;
  v_wait public.commercial_sales_waitlist%ROWTYPE;
  v_seq integer;
BEGIN
  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;

  SELECT * INTO v_pre
    FROM public.commercial_preorders p
   WHERE p.company_id = p_company_id
     AND p.niche_code = p_niche_code
     AND p.status IN (
       'waiting','reservation_offered',
       'reservation_accepted','reservation_expired')
   ORDER BY p.created_at DESC
   LIMIT 1;

  IF FOUND THEN
    SELECT e.sequence_number INTO v_seq
      FROM public.commercial_exclusivities e
     WHERE e.id = v_pre.target_exclusivity_id;

    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'mode', 'preorder',
      'preorder_id', v_pre.id,
      'status', v_pre.status,
      'segment_name', v_pre.segment_name_snapshot,
      'target_exclusivity_id', v_pre.target_exclusivity_id,
      'target_sequence_number', v_seq);
  END IF;

  SELECT * INTO v_wait
    FROM public.commercial_sales_waitlist w
   WHERE w.company_id = p_company_id
     AND w.niche_code = p_niche_code
     AND w.status NOT IN ('converted','declined','cancelled')
   ORDER BY w.created_at DESC
   LIMIT 1;

  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', true, 'mode', 'sales_waitlist',
      'waitlist_id', v_wait.id,
      'status', v_wait.status,
      'segment_name', v_wait.segment_name_snapshot,
      'position', v_wait.position,
      'first_possible_exclusivity_sequence',
        v_wait.first_possible_exclusivity_sequence);
  END IF;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'mode', 'none');
END;
$function$;

-- ---------------------------------------------------------------------------
-- N. PROVISIONAMENTO AO APP falha fechado para posições/segmentos novos (D8)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.build_app_provisioning_payload(p_exclusivity_id uuid, p_environment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_excl   public.commercial_exclusivities%ROWTYPE;
  v_region public.commercial_regions%ROWTYPE;
  v_parts  jsonb;
  v_incompativeis integer;
BEGIN
  SELECT * INTO v_excl FROM public.commercial_exclusivities WHERE id = p_exclusivity_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  SELECT * INTO v_region FROM public.commercial_regions WHERE id = v_excl.region_id;

  -- Porta de compatibilidade: todo pedido assinado desta formação precisa
  -- carregar semântica V2 explícita antes de virar asserção para o App.
  SELECT count(*) INTO v_incompativeis
    FROM public.commercial_exclusivity_orders o
   WHERE o.exclusivity_id = p_exclusivity_id
     AND o.status = 'signed'
     AND (o.benefit_settlement_mode IS NULL
          OR o.benefit_distribution_policy_version IS DISTINCT FROM 2);
  IF v_incompativeis > 0 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'incompatible_distribution_policy',
      'incompatible_orders', v_incompativeis);
  END IF;

  -- D8 — PROTEÇÃO TEMPORÁRIA. O contrato v2 com o App conhece seis códigos de
  -- nicho com calçados F/M e nenhum segmento. Formação com Calçados unificado,
  -- Outros ou substituição NÃO vira asserção para o App até existir um
  -- contrato versionado (v3) com suporte comprovado do lado do App.
  SELECT count(*) INTO v_incompativeis
    FROM public.commercial_exclusivity_orders o
   WHERE o.exclusivity_id = p_exclusivity_id
     AND o.status = 'signed'
     AND (o.niche_code IN ('footwear','others') OR o.segment_id IS NOT NULL);
  IF v_incompativeis > 0 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'app_contract_v3_required',
      'incompatible_orders', v_incompativeis);
  END IF;

  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'partner_network_bridge_id', c.partner_network_bridge_id,
      'niche_code', o.niche_code,
      'site_order_reference', o.id,
      'nominal_quantity', o.nominal_quantity,
      'currency', o.currency,
      -- Pool INTEIRO, por compatibilidade. O App NAO deve tratar este valor
      -- como direito dos MEIs: a parcela QA esta dentro dele e e da SmallFlags.
      -- O direito dos MEIs e mei_consideration_cents.
      'contractual_pool_cents', o.contractual_pool_cents,
      'contract_economics_version', o.contract_economics_version,
      'mei_consideration_cents', o.mei_consideration_cents,
      'smallflags_qa_cents', o.smallflags_qa_cents,
      -- V2: escolha contratual por parceiro, lida do snapshot imutável.
      'benefit_settlement_mode', o.benefit_settlement_mode,
      'benefit_distribution_policy_version', o.benefit_distribution_policy_version,
      'expected_operation_start', o.expected_operation_start,
      'expected_operation_end',
        o.expected_operation_start + (o.exclusivity_period_days || ' days')::interval,
      'partner_status', c.status,
      'branches', coalesce((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'partner_branch_bridge_id', u.partner_branch_bridge_id,
                 'status', u.status) ORDER BY u.partner_branch_bridge_id)
          FROM public.site_partner_units u
         WHERE u.company_id = c.id AND u.status = 'active'), '[]'::jsonb),
      'validators', coalesce((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                 'validator_bridge_id', m.validator_bridge_id,
                 'role', m.role) ORDER BY m.validator_bridge_id)
          FROM public.site_company_members m
         WHERE m.company_id = c.id AND m.status = 'active'), '[]'::jsonb))
      ORDER BY o.niche_code), '[]'::jsonb)
    INTO v_parts
    FROM public.commercial_exclusivity_orders o
    JOIN public.site_partner_companies c ON c.id = o.company_id
   WHERE o.exclusivity_id = p_exclusivity_id AND o.status = 'signed';

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'schema_version', 'bdflow.commercial_provisioning.v2',
    'environment', p_environment,
    'commercial_exclusivity_id', v_excl.id,
    'region', pg_catalog.jsonb_build_object('uf', v_region.uf, 'name', v_region.name),
    'sequence_number', v_excl.sequence_number,
    'participant_target', 84,
    'distribution_policy_version', 2,
    -- Cronograma NÃO muda nesta tarefa: continua a matriz 7x7 versão 1.
    'schedule_policy_version', 1,
    'partners', v_parts);
END;
$function$;

-- ---------------------------------------------------------------------------
-- O. INSTRUMENTO falha fechado para segmento até a revisão jurídica (D9)
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

-- ---------------------------------------------------------------------------
-- P. RESUMO DO PORTAL mostra o segmento contratado (somente owner/admin)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_company_commercial_summary(p_company_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_owner boolean := public.m2_is_company_owner(p_company_id);
BEGIN
  IF NOT (public.m2_is_company_member(p_company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'company', (SELECT pg_catalog.jsonb_build_object(
                  'company_id', c.id, 'trade_name', coalesce(c.trade_name, c.legal_name),
                  'status', c.status)
                  FROM public.site_partner_companies c WHERE c.id = p_company_id),
    'units', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'unit_id', u.id, 'name', u.name, 'city', u.city, 'status', u.status)
                  ORDER BY u.name)
                  FROM public.site_partner_units u
                 WHERE u.company_id = p_company_id AND u.status <> 'archived'), '[]'::jsonb),
    'managers', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'member_id', m.id, 'full_name', m.full_name, 'status', m.status)
                  ORDER BY m.full_name)
                  FROM public.site_company_members m
                 WHERE m.company_id = p_company_id AND m.role = 'partner_manager'
                   AND m.status IN ('active','suspended')), '[]'::jsonb),
    -- Bloco financeiro SOMENTE para owner/admin.
    'commercial', CASE WHEN v_owner OR public.is_site_admin() THEN
        coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'order_id', o.id, 'niche_code', o.niche_code,
            'segment_code', o.segment_code_snapshot,
            'segment_name', o.segment_name_snapshot,
            'nominal_quantity', o.nominal_quantity, 'currency', o.currency,
            'economic_value_cents', o.economic_value_cents,
            -- Pool INTEIRO, mantido por compatibilidade. Inclui a parcela QA
            -- da SmallFlags e por isso NAO e dinheiro do MEI/usuario.
            'contractual_pool_cents', o.contractual_pool_cents,
            'contract_economics_version', o.contract_economics_version,
            'mei_consideration_cents', o.mei_consideration_cents,
            'smallflags_qa_cents', o.smallflags_qa_cents,
            'smallflags_main_fee_cents', o.smallflags_main_fee_cents,
            'smallflags_total_remuneration_cents', o.smallflags_total_remuneration_cents,
            'bdflow_due_cents', o.bdflow_due_cents,
            'payment_status', o.payment_status,
            'has_customization_image', public.order_has_customization_image(o.id),
            'expected_operation_start', o.expected_operation_start,
            'exclusivity_status', e.status))
            FROM public.commercial_exclusivity_orders o
            JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
           WHERE o.company_id = p_company_id AND o.status <> 'cancelled'), '[]'::jsonb)
      ELSE NULL END,
    'readiness', public.company_launch_readiness(p_company_id));
END;
$function$;

-- ---------------------------------------------------------------------------
-- Q. RPCs DE SEGMENTO
-- ---------------------------------------------------------------------------
-- Catálogo público: só segmentos aprovados, só dados de apresentação.
CREATE OR REPLACE FUNCTION public.list_commercial_segments()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT pg_catalog.jsonb_build_object('ok', true, 'segments', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'id', s.id, 'code', s.code, 'name', s.display_name,
             'description', s.description,
             'overlaps_niche_code', s.overlaps_niche_code)
           ORDER BY s.display_name)
      FROM public.commercial_segments s WHERE s.status = 'approved'), '[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.list_commercial_segments() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_commercial_segments() TO anon, authenticated;

-- Solicitação de segmento não listado: SOMENTE partner_owner ativo.
-- Não reserva, não contrata, não aprova (D6).
CREATE OR REPLACE FUNCTION public.request_commercial_segment(
  p_company_id uuid, p_label text, p_justification text DEFAULT NULL,
  p_intended_niche_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_norm text;
  v_id   uuid;
  v_seg  public.commercial_segments%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_partner_companies c
                  WHERE c.id = p_company_id AND c.status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_inactive');
  END IF;
  IF p_label IS NULL OR length(pg_catalog.btrim(p_label)) NOT BETWEEN 3 AND 80 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_label');
  END IF;
  IF p_justification IS NOT NULL AND length(p_justification) > 1000 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_justification');
  END IF;
  IF p_intended_niche_code IS NOT NULL
     AND p_intended_niche_code NOT IN ('pharmacy','womens_clothing','mens_clothing','footwear','others') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'position_not_substitutable');
  END IF;
  v_norm := public.commercial_normalize_segment_label(p_label);
  IF length(v_norm) < 3 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_label');
  END IF;

  -- Já existe segmento aprovado com esse nome: aponta para ele, sem duplicar.
  SELECT * INTO v_seg FROM public.commercial_segments s
   WHERE s.status = 'approved'
     AND public.commercial_normalize_segment_label(s.display_name) = v_norm
   LIMIT 1;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_already_listed',
      'segment_id', v_seg.id, 'segment_name', v_seg.display_name);
  END IF;

  -- Teto anti-abuso: no máximo cinco solicitações pendentes por empresa.
  IF (SELECT count(*) FROM public.commercial_segment_requests r
       WHERE r.company_id = p_company_id AND r.status = 'pending') >= 5 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'too_many_pending_requests');
  END IF;

  INSERT INTO public.commercial_segment_requests
    (company_id, requested_by, requested_label, normalized_label,
     justification, intended_niche_code)
  VALUES
    (p_company_id, v_uid, pg_catalog.btrim(p_label), v_norm,
     nullif(pg_catalog.btrim(coalesce(p_justification, '')), ''), p_intended_niche_code)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.commercial_segment_requests
     WHERE company_id = p_company_id AND normalized_label = v_norm AND status = 'pending';
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'request_id', v_id, 'status', 'pending');
  END IF;

  PERFORM public.m1_auditar('commercial_segment.requested', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
      'requested_label', pg_catalog.btrim(p_label),
      'intended_niche_code', p_intended_niche_code, 'status', 'pending'),
    NULL,
    pg_catalog.jsonb_build_object('reservation_created', false,
      'contract_created', false, 'approval_granted', false));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'request_id', v_id, 'status', 'pending');
END;
$$;
REVOKE ALL ON FUNCTION public.request_commercial_segment(uuid, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_commercial_segment(uuid, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_commercial_segment_requests(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  IF NOT public.m2_is_company_owner(p_company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'requests', coalesce((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'id', r.id, 'label', r.requested_label, 'status', r.status,
             'intended_niche_code', r.intended_niche_code,
             'decision_note', r.decision_note,
             'segment_name', s.display_name,
             'created_at', r.created_at, 'decided_at', r.decided_at)
           ORDER BY r.created_at DESC)
      FROM public.commercial_segment_requests r
      LEFT JOIN public.commercial_segments s ON s.id = r.resulting_segment_id
     WHERE r.company_id = p_company_id), '[]'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_commercial_segment_requests(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_commercial_segment_requests(uuid) TO authenticated;

-- ---- administração (m1_exigir_admin + auditoria)
CREATE OR REPLACE FUNCTION public.admin_list_commercial_segments()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  PERFORM public.m1_exigir_admin();
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'segments', coalesce((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id', s.id, 'code', s.code, 'name', s.display_name,
               'classification_key', s.classification_key,
               'description', s.description,
               'overlaps_niche_code', s.overlaps_niche_code,
               'delimitation_policy', s.delimitation_policy,
               'status', s.status, 'approved_at', s.approved_at,
               'archived_at', s.archived_at)
             ORDER BY s.status, s.display_name)
        FROM public.commercial_segments s), '[]'::jsonb),
    'requests', coalesce((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id', r.id, 'company_id', r.company_id,
               'company_name', c.trade_name,
               'label', r.requested_label, 'justification', r.justification,
               'intended_niche_code', r.intended_niche_code,
               'status', r.status, 'decision_note', r.decision_note,
               'resulting_segment_id', r.resulting_segment_id,
               'created_at', r.created_at, 'decided_at', r.decided_at)
             ORDER BY (r.status = 'pending') DESC, r.created_at)
        FROM public.commercial_segment_requests r
        JOIN public.site_partner_companies c ON c.id = r.company_id), '[]'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_commercial_segments() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_commercial_segments() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_create_commercial_segment(
  p_code text, p_display_name text, p_classification_key text,
  p_description text DEFAULT NULL, p_overlaps_niche_code text DEFAULT NULL,
  p_delimitation_policy text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM public.m1_exigir_admin();
  IF EXISTS (SELECT 1 FROM public.commercial_segments s
              WHERE s.status = 'approved' AND s.classification_key = p_classification_key) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'classification_already_approved');
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_segments s WHERE s.code = p_code) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_code_taken');
  END IF;
  BEGIN
    INSERT INTO public.commercial_segments
      (code, display_name, classification_key, description,
       overlaps_niche_code, delimitation_policy,
       created_by, approved_by)
    VALUES
      (p_code, pg_catalog.btrim(p_display_name), p_classification_key,
       nullif(pg_catalog.btrim(coalesce(p_description, '')), ''),
       p_overlaps_niche_code,
       nullif(pg_catalog.btrim(coalesce(p_delimitation_policy, '')), ''),
       auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  EXCEPTION WHEN check_violation OR foreign_key_violation THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_segment_definition');
  END;
  PERFORM public.m1_auditar('commercial_segment.created', v_id, 'admin',
    pg_catalog.jsonb_build_object('code', p_code, 'classification_key', p_classification_key,
      'overlaps_niche_code', p_overlaps_niche_code));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'segment_id', v_id);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_create_commercial_segment(text, text, text, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_create_commercial_segment(text, text, text, text, text, text) TO authenticated;

-- Decisão de solicitação: aprovar vinculando a um segmento EXISTENTE (mesma
-- classificação, sem duplicar) ou criando um novo; ou rejeitar com motivo.
CREATE OR REPLACE FUNCTION public.admin_decide_commercial_segment_request(
  p_request_id uuid, p_decision text,
  p_existing_segment_id uuid DEFAULT NULL,
  p_new_code text DEFAULT NULL, p_new_display_name text DEFAULT NULL,
  p_new_classification_key text DEFAULT NULL,
  p_new_overlaps_niche_code text DEFAULT NULL,
  p_new_delimitation_policy text DEFAULT NULL,
  p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_r   public.commercial_segment_requests%ROWTYPE;
  v_seg uuid;
  v_c   jsonb;
BEGIN
  PERFORM public.m1_exigir_admin();
  SELECT * INTO v_r FROM public.commercial_segment_requests
   WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_not_found');
  END IF;
  IF v_r.status <> 'pending' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'request_already_decided',
      'status', v_r.status);
  END IF;

  IF p_decision = 'reject' THEN
    IF length(pg_catalog.btrim(coalesce(p_note, ''))) < 5 THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'decision_note_required');
    END IF;
    UPDATE public.commercial_segment_requests
       SET status = 'rejected', decided_by = auth.uid(), decided_at = pg_catalog.now(),
           decision_note = pg_catalog.btrim(p_note)
     WHERE id = v_r.id;
    PERFORM public.m1_auditar('commercial_segment_request.rejected', v_r.id, 'admin',
      pg_catalog.jsonb_build_object('status', 'rejected', 'note', pg_catalog.btrim(p_note)),
      pg_catalog.jsonb_build_object('status', 'pending'));
    RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'rejected');
  END IF;

  IF p_decision IS DISTINCT FROM 'approve' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_decision');
  END IF;

  IF p_existing_segment_id IS NOT NULL THEN
    SELECT id INTO v_seg FROM public.commercial_segments
     WHERE id = p_existing_segment_id AND status = 'approved';
    IF v_seg IS NULL THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_not_approved');
    END IF;
  ELSE
    v_c := public.admin_create_commercial_segment(
             p_new_code, p_new_display_name, p_new_classification_key, NULL,
             p_new_overlaps_niche_code, p_new_delimitation_policy);
    IF (v_c->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_c;
    END IF;
    v_seg := (v_c->>'segment_id')::uuid;
  END IF;

  UPDATE public.commercial_segment_requests
     SET status = 'approved', decided_by = auth.uid(), decided_at = pg_catalog.now(),
         decision_note = nullif(pg_catalog.btrim(coalesce(p_note, '')), ''),
         resulting_segment_id = v_seg
   WHERE id = v_r.id;
  PERFORM public.m1_auditar('commercial_segment_request.approved', v_r.id, 'admin',
    pg_catalog.jsonb_build_object('status', 'approved', 'segment_id', v_seg),
    pg_catalog.jsonb_build_object('status', 'pending'),
    pg_catalog.jsonb_build_object('reservation_created', false, 'contract_created', false));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'approved', 'segment_id', v_seg);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_decide_commercial_segment_request(uuid, text, uuid, text, text, text, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_decide_commercial_segment_request(uuid, text, uuid, text, text, text, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_archive_commercial_segment(p_segment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  PERFORM public.m1_exigir_admin();
  UPDATE public.commercial_segments
     SET status = 'archived', archived_by = auth.uid(), archived_at = pg_catalog.now()
   WHERE id = p_segment_id AND status = 'approved';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'segment_not_approved');
  END IF;
  -- Pedidos e reservas existentes mantêm o snapshot; só vendas novas param.
  PERFORM public.m1_auditar('commercial_segment.archived', p_segment_id, 'admin',
    pg_catalog.jsonb_build_object('status', 'archived'),
    pg_catalog.jsonb_build_object('status', 'approved'));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'archived');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_archive_commercial_segment(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.admin_archive_commercial_segment(uuid) TO authenticated;

COMMIT;
