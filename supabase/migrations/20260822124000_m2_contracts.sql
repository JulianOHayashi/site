-- ============================================================================
-- M2 / R6 — Instrumentos contratuais (modelo TÉCNICO)
--
-- Dois instrumentos, sem NENHUM texto jurídico de produção:
--   A) commercial_master_agreements  — Acordo Mestre de Parceria, por empresa.
--   B) commercial_exclusivity_orders — Pedido de Exclusividade, um por
--      (nicho + região + exclusividade comercial), com SNAPSHOT econômico.
--
-- O pedido nasce em 'draft': a venda manual e a confirmação de pagamento são
-- do R8, e a imagem de personalização obrigatória é do R7. Aqui só existe o
-- modelo técnico e o registro do instrumento assinado.
--
-- Invariante econômica garantida por CHECK:
--   economic_value_cents = contractual_pool_cents + bdflow_due_cents
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) Acordo Mestre de Parceria
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_master_agreements (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             uuid NOT NULL REFERENCES public.site_partner_companies(id),
  agreement_version      text        NOT NULL,
  document_reference     text,
  document_hash          text,
  status                 text        NOT NULL DEFAULT 'signed',
  signed_at              timestamptz NOT NULL,
  signatory_name         text        NOT NULL,
  signed_by_member_id    uuid REFERENCES public.site_company_members(id),
  external_signature_ref text,
  supersedes_agreement_id uuid REFERENCES public.commercial_master_agreements(id),
  superseded_at          timestamptz,
  registered_by          uuid        NOT NULL,
  registered_at          timestamptz NOT NULL DEFAULT now(),
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cma_status_allowed
    CHECK (status = ANY (ARRAY['signed','superseded','terminated'])),
  CONSTRAINT cma_version_nonempty
    CHECK (length(btrim(agreement_version)) BETWEEN 1 AND 60),
  CONSTRAINT cma_signatario_nonempty
    CHECK (length(btrim(signatory_name)) BETWEEN 3 AND 200),
  -- Evidência mínima do documento assinado: referência OU hash.
  CONSTRAINT cma_evidencia
    CHECK ((document_reference IS NOT NULL AND length(btrim(document_reference)) > 0)
           OR (document_hash IS NOT NULL AND length(btrim(document_hash)) > 0)),
  CONSTRAINT cma_supersessao_coerente
    CHECK ((status = 'superseded') = (superseded_at IS NOT NULL)),
  CONSTRAINT cma_nao_supersede_a_si
    CHECK (supersedes_agreement_id IS NULL OR supersedes_agreement_id <> id),
  CONSTRAINT cma_timestamps CHECK (updated_at >= created_at)
);

-- Um acordo vigente por empresa.
CREATE UNIQUE INDEX cma_vigente_idx
  ON public.commercial_master_agreements (company_id) WHERE status = 'signed';

CREATE TRIGGER trg_cma_touch
  BEFORE UPDATE ON public.commercial_master_agreements
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ----------------------------------------------------------------------------
-- B) Pedido de Exclusividade
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_exclusivity_orders (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exclusivity_id        uuid NOT NULL REFERENCES public.commercial_exclusivities(id),
  opportunity_id        uuid NOT NULL UNIQUE REFERENCES public.commercial_opportunities(id),
  company_id            uuid NOT NULL REFERENCES public.site_partner_companies(id),
  master_agreement_id   uuid NOT NULL REFERENCES public.commercial_master_agreements(id),
  niche_code            text NOT NULL REFERENCES public.commercial_niches(code),
  region_id             uuid NOT NULL REFERENCES public.commercial_regions(id),
  nominal_quantity      integer NOT NULL,

  -- SNAPSHOT econômico imutável (centavos inteiros)
  pricing_rule_version  integer NOT NULL
                          REFERENCES public.commercial_pricing_rules(version),
  fidelized             boolean NOT NULL,
  currency              text    NOT NULL DEFAULT 'BRL',
  economic_value_cents  bigint  NOT NULL,
  pool_bps              integer NOT NULL,
  contractual_pool_cents bigint NOT NULL,
  bdflow_due_cents      bigint  NOT NULL,

  -- Instrumento assinado
  order_version          text,
  document_reference     text,
  document_hash          text,
  signed_at              timestamptz,
  signatory_name         text,
  external_signature_ref text,

  -- Ciclo de vida (venda manual e pagamento chegam no R8)
  status                 text NOT NULL DEFAULT 'draft',
  payment_status         text NOT NULL DEFAULT 'pending',
  payment_confirmed_at   timestamptz,
  payment_confirmed_by   uuid,
  payment_amount_cents   bigint,
  payment_external_ref   text,

  expected_operation_start date        NOT NULL,
  exclusivity_period_days  integer     NOT NULL DEFAULT 28,
  registered_by            uuid        NOT NULL,
  registered_at            timestamptz NOT NULL DEFAULT now(),
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ceo_status_allowed
    CHECK (status = ANY (ARRAY['draft','signed','cancelled'])),
  CONSTRAINT ceo_payment_status_allowed
    CHECK (payment_status = ANY (ARRAY['pending','confirmed'])),
  CONSTRAINT ceo_qty_positiva CHECK (nominal_quantity > 0),
  CONSTRAINT ceo_moeda CHECK (currency = 'BRL'),
  CONSTRAINT ceo_valores_nao_negativos
    CHECK (economic_value_cents > 0 AND contractual_pool_cents >= 0
           AND bdflow_due_cents >= 0),
  -- INVARIANTE ECONÔMICA
  CONSTRAINT ceo_invariante_economica
    CHECK (economic_value_cents = contractual_pool_cents + bdflow_due_cents),
  CONSTRAINT ceo_periodo_positivo CHECK (exclusivity_period_days > 0),
  -- Assinado exige instrumento completo.
  CONSTRAINT ceo_assinatura_coerente
    CHECK (status <> 'signed'
           OR (signed_at IS NOT NULL
               AND signatory_name IS NOT NULL
               AND length(btrim(signatory_name)) >= 3
               AND order_version IS NOT NULL
               AND ((document_reference IS NOT NULL AND length(btrim(document_reference)) > 0)
                    OR (document_hash IS NOT NULL AND length(btrim(document_hash)) > 0)))),
  -- Pagamento confirmado exige ator, data e valor recebido.
  CONSTRAINT ceo_pagamento_coerente
    CHECK ((payment_status = 'pending'
            AND payment_confirmed_at IS NULL AND payment_confirmed_by IS NULL
            AND payment_amount_cents IS NULL)
           OR (payment_status = 'confirmed'
               AND payment_confirmed_at IS NOT NULL
               AND payment_confirmed_by IS NOT NULL
               AND payment_amount_cents IS NOT NULL)),
  -- Pagamento só existe sobre pedido assinado.
  CONSTRAINT ceo_pagamento_exige_assinatura
    CHECK (payment_status = 'pending' OR status = 'signed'),
  CONSTRAINT ceo_timestamps CHECK (updated_at >= created_at)
);

-- Um nicho por exclusividade e UM CNPJ em no máximo UM nicho da exclusividade.
CREATE UNIQUE INDEX ceo_nicho_por_exclusividade_idx
  ON public.commercial_exclusivity_orders (exclusivity_id, niche_code)
  WHERE status <> 'cancelled';
CREATE UNIQUE INDEX ceo_empresa_por_exclusividade_idx
  ON public.commercial_exclusivity_orders (exclusivity_id, company_id)
  WHERE status <> 'cancelled';

CREATE TRIGGER trg_ceo_touch
  BEFORE UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ----------------------------------------------------------------------------
-- Proteção: snapshot imutável, sem DELETE, confirmação de pagamento definitiva
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.m2_orders_protect()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'pedido_imutavel: pedido de exclusividade nao pode ser excluido (id=%). Use cancelamento.', OLD.id;
  END IF;

  IF NEW.exclusivity_id         IS DISTINCT FROM OLD.exclusivity_id
  OR NEW.opportunity_id         IS DISTINCT FROM OLD.opportunity_id
  OR NEW.company_id             IS DISTINCT FROM OLD.company_id
  OR NEW.niche_code             IS DISTINCT FROM OLD.niche_code
  OR NEW.region_id              IS DISTINCT FROM OLD.region_id
  OR NEW.nominal_quantity       IS DISTINCT FROM OLD.nominal_quantity
  OR NEW.pricing_rule_version   IS DISTINCT FROM OLD.pricing_rule_version
  OR NEW.fidelized              IS DISTINCT FROM OLD.fidelized
  OR NEW.economic_value_cents   IS DISTINCT FROM OLD.economic_value_cents
  OR NEW.pool_bps               IS DISTINCT FROM OLD.pool_bps
  OR NEW.contractual_pool_cents IS DISTINCT FROM OLD.contractual_pool_cents
  OR NEW.bdflow_due_cents       IS DISTINCT FROM OLD.bdflow_due_cents
  OR NEW.registered_by          IS DISTINCT FROM OLD.registered_by THEN
    RAISE EXCEPTION 'pedido_imutavel: snapshot economico/contratual do pedido e imutavel (id=%).', OLD.id;
  END IF;

  -- Assinatura registrada não é reescrita.
  IF OLD.status = 'signed' THEN
    IF NEW.signed_at IS DISTINCT FROM OLD.signed_at
    OR NEW.document_hash IS DISTINCT FROM OLD.document_hash
    OR NEW.document_reference IS DISTINCT FROM OLD.document_reference THEN
      RAISE EXCEPTION 'pedido_imutavel: instrumento assinado e imutavel (id=%).', OLD.id;
    END IF;
  END IF;

  -- Confirmação de pagamento é definitiva.
  IF OLD.payment_status = 'confirmed' THEN
    IF NEW.payment_status IS DISTINCT FROM 'confirmed'
    OR NEW.payment_confirmed_at IS DISTINCT FROM OLD.payment_confirmed_at
    OR NEW.payment_confirmed_by IS DISTINCT FROM OLD.payment_confirmed_by
    OR NEW.payment_amount_cents IS DISTINCT FROM OLD.payment_amount_cents THEN
      RAISE EXCEPTION 'pedido_imutavel: confirmacao de pagamento e imutavel (id=%).', OLD.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ceo_protect
  BEFORE UPDATE OR DELETE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.m2_orders_protect();

CREATE FUNCTION public.m2_agreements_protect()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'acordo_imutavel: acordo mestre nao pode ser excluido (id=%).', OLD.id;
  END IF;
  IF NEW.company_id        IS DISTINCT FROM OLD.company_id
  OR NEW.agreement_version IS DISTINCT FROM OLD.agreement_version
  OR NEW.signed_at         IS DISTINCT FROM OLD.signed_at
  OR NEW.document_hash     IS DISTINCT FROM OLD.document_hash
  OR NEW.document_reference IS DISTINCT FROM OLD.document_reference
  OR NEW.registered_by     IS DISTINCT FROM OLD.registered_by THEN
    RAISE EXCEPTION 'acordo_imutavel: evidencia do acordo e imutavel (id=%).', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cma_protect
  BEFORE UPDATE OR DELETE ON public.commercial_master_agreements
  FOR EACH ROW EXECUTE FUNCTION public.m2_agreements_protect();

-- ----------------------------------------------------------------------------
-- RLS: owner e admin leem; MANAGER NÃO TEM ACESSO FINANCEIRO
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_master_agreements  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_exclusivity_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY cma_owner_select ON public.commercial_master_agreements
  FOR SELECT TO authenticated
  USING (public.m2_is_company_owner(company_id) OR public.is_site_admin());

CREATE POLICY ceo_owner_select ON public.commercial_exclusivity_orders
  FOR SELECT TO authenticated
  USING (public.m2_is_company_owner(company_id) OR public.is_site_admin());

REVOKE ALL ON TABLE public.commercial_master_agreements
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.commercial_exclusivity_orders
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_master_agreements  TO authenticated;
GRANT SELECT ON public.commercial_exclusivity_orders TO authenticated;

-- ----------------------------------------------------------------------------
-- RPC administrativa — registrar Acordo Mestre assinado
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.admin_register_master_agreement(
  p_company_id        uuid,
  p_agreement_version text,
  p_signed_at         timestamptz,
  p_signatory_name    text,
  p_document_reference text DEFAULT NULL,
  p_document_hash      text DEFAULT NULL,
  p_external_signature_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_atual public.commercial_master_agreements%ROWTYPE;
  v_id uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  IF p_signed_at IS NULL OR p_signed_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_signature_date');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_partner_companies
                  WHERE id = p_company_id AND status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_invalid');
  END IF;

  -- Serializa por empresa.
  PERFORM 1 FROM public.site_partner_companies WHERE id = p_company_id FOR UPDATE;

  SELECT * INTO v_atual FROM public.commercial_master_agreements
   WHERE company_id = p_company_id AND status = 'signed';

  IF FOUND THEN
    -- Idempotência: mesma versão e mesma assinatura.
    IF v_atual.agreement_version = pg_catalog.btrim(p_agreement_version)
       AND v_atual.signed_at = p_signed_at THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                           'agreement_id', v_atual.id);
    END IF;
    UPDATE public.commercial_master_agreements
       SET status = 'superseded', superseded_at = pg_catalog.now()
     WHERE id = v_atual.id;
  END IF;

  BEGIN
    INSERT INTO public.commercial_master_agreements
      (company_id, agreement_version, document_reference, document_hash,
       signed_at, signatory_name, external_signature_ref,
       supersedes_agreement_id, registered_by)
    VALUES
      (p_company_id, pg_catalog.btrim(p_agreement_version),
       nullif(pg_catalog.btrim(coalesce(p_document_reference,'')), ''),
       nullif(pg_catalog.btrim(coalesce(p_document_hash,'')), ''),
       p_signed_at, pg_catalog.btrim(p_signatory_name),
       nullif(pg_catalog.btrim(coalesce(p_external_signature_ref,'')), ''),
       v_atual.id, auth.uid())
    RETURNING id INTO v_id;
  EXCEPTION
    WHEN check_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
  END;

  PERFORM public.m1_auditar('master_agreement.registered', v_id, 'admin',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'agreement_version', pg_catalog.btrim(p_agreement_version),
                                  'supersedes', v_atual.id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
                                       'agreement_id', v_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_register_master_agreement(
  uuid,text,timestamptz,text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_register_master_agreement(
  uuid,text,timestamptz,text,text,text,text) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_register_master_agreement(
  uuid,text,timestamptz,text,text,text,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.m2_orders_protect() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m2_agreements_protect() FROM PUBLIC;

COMMENT ON TABLE public.commercial_exclusivity_orders IS
  'Pedido de Exclusividade: modelo TÉCNICO com snapshot econômico imutável. '
  'Nenhum texto jurídico de produção é definido aqui.';
