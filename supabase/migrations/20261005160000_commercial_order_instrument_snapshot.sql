-- ---------------------------------------------------------------------------
-- Item D — snapshot imutável do instrumento comercial por pedido
--
-- Migration ADITIVA. Nenhuma migration histórica é editada; nenhuma linha
-- existente é reescrita; nenhum dado de produção é tocado.
--
-- O QUE A MINUTA v1.4 EXIGE E O SCHEMA NÃO REPRESENTAVA
--
-- Fonte congelada: SMALLFLAGS_SEIS_CONTRATOS_PRESENCIAIS_SF-0001_A_SF-0006
-- _MINUTA_v1_4_CONTEUDO_CONGELADO.md, SHA-256
-- 03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73,
-- conferido contra o manifesto oficial de congelamento.
--
-- O QUADRO FINANCEIRO decompõe o pool em DUAS parcelas com titulares
-- diferentes:
--
--   supermercado (24):  pool 23.976,00 = MEIs 23.854,32 + QA SmallFlags 121,68
--   demais     (12):    pool 11.988,00 = MEIs 11.927,16 + QA SmallFlags  60,84
--
-- O schema tinha `contractual_pool_cents` (o pool inteiro) e `bdflow_due_cents`
-- (a parcela operacional principal), mas NADA que separasse a contraprestação
-- devida aos MEIs da parcela QA, que está dentro do pool e pertence à
-- SmallFlags. Sem essa separação o Site não consegue afirmar, nem exportar ao
-- App, quanto do pool é direito do MEI — e tratar a parcela QA como direito do
-- MEI seria errado, assim como escondê-la do pool seria divergir da minuta.
--
-- O INSTRUMENTO precisa de identidade própria por pedido (SF-0001..SF-0006).
-- Os seis arquivos NÃO viram seis documentos públicos: eles são a fonte
-- congelada do MODELO. Cada pedido assinado recebe um snapshot derivado desse
-- modelo mais os fatos reais daquele pedido.
-- ---------------------------------------------------------------------------

-- 1. Decomposição econômica do pool ------------------------------------------
--
-- Nullable: pedidos existentes continuam válidos e não são reescritos. A trava
-- de coerência abaixo só age quando as colunas estão preenchidas.

ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS mei_consideration_cents bigint,
  ADD COLUMN IF NOT EXISTS smallflags_qa_cents     bigint;

COMMENT ON COLUMN public.commercial_exclusivity_orders.mei_consideration_cents IS
  'Parcela do pool devida aos MEIs (contraprestacoes ordinarias). v1.4: '
  'R$ 23.854,32 supermercado, R$ 11.927,16 demais posicoes.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.smallflags_qa_cents IS
  'Parcela QA PROPRIA da SmallFlags, dentro do pool. NAO e direito do MEI. '
  'v1.4: R$ 121,68 supermercado, R$ 60,84 demais posicoes.';

-- Invariante: as duas parcelas somam exatamente o pool. Evita que a soma
-- divirja do valor contratado por arredondamento ou digitação.
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_pool_decomposition_sums
  CHECK (
    mei_consideration_cents IS NULL
    OR smallflags_qa_cents IS NULL
    OR mei_consideration_cents + smallflags_qa_cents = contractual_pool_cents
  ) NOT VALID;

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_pool_decomposition_nonneg
  CHECK (
    (mei_consideration_cents IS NULL OR mei_consideration_cents >= 0)
    AND (smallflags_qa_cents IS NULL OR smallflags_qa_cents >= 0)
  ) NOT VALID;

-- 2. Identidade e snapshot do instrumento ------------------------------------

ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS instrument_code             text,
  ADD COLUMN IF NOT EXISTS instrument_template_version text,
  ADD COLUMN IF NOT EXISTS instrument_template_hash    text,
  ADD COLUMN IF NOT EXISTS instrument_snapshot         jsonb;

COMMENT ON COLUMN public.commercial_exclusivity_orders.instrument_code IS
  'Identidade do instrumento presencial deste pedido (SF-0001..SF-0006). '
  'Um por pedido; nao ha numeracao fixada no codigo.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.instrument_template_hash IS
  'SHA-256 da fonte congelada do MODELO (as seis minutas v1.4), nao do '
  'instrumento preenchido.';
COMMENT ON COLUMN public.commercial_exclusivity_orders.instrument_snapshot IS
  'Fatos do pedido congelados na assinatura. Imutavel apos assinado.';

-- Formato do código: SF seguido de quatro dígitos. Não fixa quais existem —
-- fixar SF-0001..SF-0006 no banco seria embutir os seis primeiros pedidos
-- como se fossem regra permanente.
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_instrument_code_format
  CHECK (instrument_code IS NULL OR instrument_code ~ '^SF-[0-9]{4}$') NOT VALID;

-- Um instrumento identifica UM pedido.
CREATE UNIQUE INDEX IF NOT EXISTS ceo_instrument_code_uidx
  ON public.commercial_exclusivity_orders (instrument_code)
  WHERE instrument_code IS NOT NULL;

-- 3. Imutabilidade do snapshot depois de assinado ----------------------------
--
-- É o que garante a exigência 5 do item D: publicar um modelo ou um Mestre
-- novo não pode reescrever um pedido antigo. A trava é do banco, não da
-- aplicação.

CREATE OR REPLACE FUNCTION public.ceo_instrumento_imutavel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  -- Antes da assinatura o snapshot ainda pode ser ajustado.
  IF OLD.signed_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.instrument_snapshot IS DISTINCT FROM OLD.instrument_snapshot
     OR NEW.instrument_code IS DISTINCT FROM OLD.instrument_code
     OR NEW.instrument_template_version IS DISTINCT FROM OLD.instrument_template_version
     OR NEW.instrument_template_hash IS DISTINCT FROM OLD.instrument_template_hash
     OR NEW.mei_consideration_cents IS DISTINCT FROM OLD.mei_consideration_cents
     OR NEW.smallflags_qa_cents IS DISTINCT FROM OLD.smallflags_qa_cents
     OR NEW.order_version IS DISTINCT FROM OLD.order_version
     OR NEW.document_hash IS DISTINCT FROM OLD.document_hash THEN
    RAISE EXCEPTION
      'instrumento assinado e imutavel: snapshot, identidade, versao, hash e '
      'decomposicao economica nao podem ser alterados apos signed_at'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ceo_instrumento_imutavel ON public.commercial_exclusivity_orders;
CREATE TRIGGER ceo_instrumento_imutavel
  BEFORE UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_instrumento_imutavel();

-- 4. Leitura do instrumento de um pedido -------------------------------------
--
-- Só o titular ativo da empresa do pedido lê. Serve ao Portal e à exportação
-- para o App; não expõe nada publicamente.

CREATE OR REPLACE FUNCTION public.get_order_instrument(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_o public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.site_company_members m
                  WHERE m.company_id = v_o.company_id AND m.auth_user_id = auth.uid()
                    AND m.role = 'partner_owner' AND m.status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;
  IF v_o.instrument_snapshot IS NULL THEN
    -- Pedido anterior a esta migration, ou ainda sem instrumento congelado.
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'instrument_snapshot_missing');
  END IF;

  RETURN pg_catalog.jsonb_build_object('ok', true,
    'order_id', v_o.id,
    'instrument_code', v_o.instrument_code,
    'template_version', v_o.instrument_template_version,
    'template_hash', v_o.instrument_template_hash,
    'order_version', v_o.order_version,
    'document_hash', v_o.document_hash,
    'document_reference', v_o.document_reference,
    'signed_at', v_o.signed_at,
    'economic_value_cents', v_o.economic_value_cents,
    'contractual_pool_cents', v_o.contractual_pool_cents,
    'mei_consideration_cents', v_o.mei_consideration_cents,
    'smallflags_qa_cents', v_o.smallflags_qa_cents,
    'bdflow_due_cents', v_o.bdflow_due_cents,
    'benefit_settlement_mode', v_o.benefit_settlement_mode,
    'snapshot', v_o.instrument_snapshot);
END;
$$;

ALTER FUNCTION public.get_order_instrument(uuid) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.get_order_instrument(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_order_instrument(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_order_instrument(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.get_order_instrument(uuid) IS
  'Instrumento comercial congelado de um pedido, para o titular ativo da '
  'empresa. Falha fechada quando o snapshot nao existe.';
