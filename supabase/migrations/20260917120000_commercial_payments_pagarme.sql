-- ============================================================================
-- PAGAMENTO COMERCIAL — modelo neutro de provedor e transições autoritativas
--
-- POR QUE NÃO REAPROVEITAR public.payments
-- A tabela legada `payments` é da loja de camisas: `order_id` aponta para
-- `public.orders` (domínio revogado), o provedor tem default 'mercado_pago',
-- `raw_webhook jsonb` guarda o payload BRUTO do provedor, `amount_cents` é
-- integer, não há CHECK de status, não há idempotência, não há expiração e não
-- há RLS. Guardar payload bruto é exatamente o que este marco proíbe, e
-- pendurar pagamento comercial numa FK para um domínio morto seria dívida
-- nascendo pronta. Modelo novo, aditivo, neutro de provedor.
--
-- O QUE ESTA MIGRATION NÃO FAZ
-- Não fala com provedor nenhum, não guarda credencial e não cria pagamento.
-- Ela estabelece o registro local, os estados e as transições que o adaptador
-- HTTP vai usar — e que precisam estar certas ANTES de existir HTTP.
--
-- ADITIVA. Nenhuma das 33 migrations anteriores é editada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Estado final da intenção de checkout
--
-- O ciclo parava em `awaiting_payment_provider`. Faltavam o fim feliz e o fim
-- por decurso de prazo. `cancelled` já existia e continua sendo o cancelamento
-- deliberado; `expired` é o decurso do prazo de reserva, que é outra coisa.
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_checkout_intents
  DROP CONSTRAINT cci_status_valido;
ALTER TABLE public.commercial_checkout_intents
  ADD CONSTRAINT cci_status_valido
  CHECK (status = ANY (ARRAY[
    'draft','awaiting_contract','awaiting_payment_provider',
    'paid','expired','cancelled']));

-- ----------------------------------------------------------------------------
-- 2. Quem confirmou o pagamento
--
-- `ceo_pagamento_coerente` exige `payment_confirmed_by` NOT NULL quando
-- confirmado — desenho correto para a confirmação MANUAL por admin, que era o
-- único caminho existente. Na conciliação com provedor não há ator humano, e
-- carimbar o titular ou um admin diria que uma pessoa confirmou algo que ela
-- não confirmou.
--
-- A constraint é recriada para admitir os dois caminhos, cada um com sua
-- exigência. O caminho manual não fica mais frouxo: continua exigindo ator.
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS payment_confirmed_source text;

ALTER TABLE public.commercial_exclusivity_orders
  DROP CONSTRAINT ceo_pagamento_coerente;
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_pagamento_coerente
  CHECK (
    (payment_status = 'pending'
       AND payment_confirmed_at IS NULL AND payment_confirmed_by IS NULL
       AND payment_amount_cents IS NULL AND payment_confirmed_source IS NULL)
    OR (payment_status = 'confirmed'
       AND payment_confirmed_at IS NOT NULL
       AND payment_amount_cents IS NOT NULL
       AND ((payment_confirmed_source = 'admin_manual'
               AND payment_confirmed_by IS NOT NULL)
            -- Conciliação com provedor: sem ator humano, e a evidência é o
            -- registro de pagamento comercial, não uma pessoa.
            OR (payment_confirmed_source = 'payment_provider'
               AND payment_confirmed_by IS NULL)))
  );

-- A confirmação manual histórica passa a declarar sua origem.
CREATE OR REPLACE FUNCTION public.ceo_marcar_origem_manual()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF NEW.payment_status = 'confirmed' AND NEW.payment_confirmed_source IS NULL THEN
    NEW.payment_confirmed_source := 'admin_manual';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ceo_origem_pagamento
  BEFORE INSERT OR UPDATE ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_marcar_origem_manual();

-- ----------------------------------------------------------------------------
-- 3. Registro de pagamento comercial — neutro de provedor
--
-- NÃO PERSISTE: chave secreta, número de cartão, CVV, payload bruto. Só
-- identificadores do provedor, valor, prazo e estado.
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_payments (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commercial_order_id      uuid NOT NULL REFERENCES public.commercial_exclusivity_orders(id),
  checkout_intent_id       uuid NOT NULL REFERENCES public.commercial_checkout_intents(id),
  provider                 text NOT NULL,
  provider_order_id        text,
  provider_charge_id       text,
  provider_payment_link_id text,
  provider_reference       text,
  payment_method           text NOT NULL,
  amount_cents             bigint NOT NULL,
  installments             integer,
  status                   text NOT NULL DEFAULT 'created',
  expires_at               timestamptz NOT NULL,
  idempotency_key          text NOT NULL,
  paid_at                  timestamptz,
  -- Motivo de estado excepcional (pagamento tardio, divergência). Texto curto
  -- e controlado, jamais payload do provedor.
  exception_reason         text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cp_provider_allowed CHECK (provider = ANY (ARRAY['pagarme'])),
  CONSTRAINT cp_method_allowed
    CHECK (payment_method = ANY (ARRAY['pix','credit_card'])),
  CONSTRAINT cp_status_allowed
    CHECK (status = ANY (ARRAY['created','pending','paid','expired',
                               'cancelled','failed','late_unreconciled'])),
  CONSTRAINT cp_amount_positivo CHECK (amount_cents > 0),
  -- Parcelas só existem no cartão, e o teto é seis.
  CONSTRAINT cp_parcelas_coerentes
    CHECK ((payment_method = 'pix' AND installments IS NULL)
           OR (payment_method = 'credit_card'
               AND installments IS NOT NULL
               AND installments BETWEEN 1 AND 6)),
  CONSTRAINT cp_pago_coerente
    CHECK ((status = 'paid') = (paid_at IS NOT NULL)),
  CONSTRAINT cp_excecao_coerente
    CHECK ((status <> 'late_unreconciled')
           OR (exception_reason IS NOT NULL
               AND length(btrim(exception_reason)) > 0)),
  CONSTRAINT cp_idem_nonempty CHECK (length(btrim(idempotency_key)) > 0),
  CONSTRAINT cp_timestamps CHECK (updated_at >= created_at)
);

-- A chave de idempotência é global: a mesma tentativa lógica nunca cria dois
-- recursos no provedor.
CREATE UNIQUE INDEX cp_idem_idx ON public.commercial_payments (idempotency_key);

-- UMA tentativa viva por pedido. Estados terminais liberam nova tentativa;
-- `paid` não libera, porque pago é pago.
CREATE UNIQUE INDEX cp_tentativa_viva_idx
  ON public.commercial_payments (commercial_order_id)
  WHERE status IN ('created','pending','paid');

CREATE INDEX cp_provider_charge_idx
  ON public.commercial_payments (provider, provider_charge_id)
  WHERE provider_charge_id IS NOT NULL;
CREATE INDEX cp_provider_order_idx
  ON public.commercial_payments (provider, provider_order_id)
  WHERE provider_order_id IS NOT NULL;

CREATE TRIGGER trg_cp_touch
  BEFORE UPDATE ON public.commercial_payments
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- Valor e prazo são imutáveis: eles vêm do instantâneo contratual.
CREATE FUNCTION public.cp_proteger()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'pagamento_imutavel: registro de pagamento nao e excluido (id=%)', OLD.id;
  END IF;
  IF NEW.commercial_order_id IS DISTINCT FROM OLD.commercial_order_id
  OR NEW.checkout_intent_id  IS DISTINCT FROM OLD.checkout_intent_id
  OR NEW.provider            IS DISTINCT FROM OLD.provider
  OR NEW.payment_method      IS DISTINCT FROM OLD.payment_method
  OR NEW.amount_cents        IS DISTINCT FROM OLD.amount_cents
  OR NEW.installments        IS DISTINCT FROM OLD.installments
  OR NEW.expires_at          IS DISTINCT FROM OLD.expires_at
  OR NEW.idempotency_key     IS DISTINCT FROM OLD.idempotency_key THEN
    RAISE EXCEPTION 'pagamento_imutavel: valor, prazo, metodo e chave de idempotencia sao imutaveis (id=%)', OLD.id;
  END IF;
  IF OLD.status = 'paid' AND NEW.status <> 'paid' THEN
    RAISE EXCEPTION 'pagamento_imutavel: pagamento confirmado nao volta atras (id=%)', OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cp_proteger
  BEFORE UPDATE OR DELETE ON public.commercial_payments
  FOR EACH ROW EXECUTE FUNCTION public.cp_proteger();

ALTER TABLE public.commercial_payments ENABLE ROW LEVEL SECURITY;

-- O titular lê o próprio pagamento; escrita é exclusivamente por RPC.
CREATE POLICY cp_owner_select ON public.commercial_payments
  FOR SELECT TO authenticated
  USING (
    public.is_site_admin()
    OR EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                WHERE o.id = commercial_payments.commercial_order_id
                  AND public.m2_is_company_owner(o.company_id))
  );

REVOKE ALL ON TABLE public.commercial_payments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.commercial_payments TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Abertura da tentativa de pagamento
--
-- Roda ANTES de qualquer chamada ao provedor: se o estado comercial não
-- permite, o adaptador nem chega a montar requisição. Devolve valor, método,
-- prazo e chave de idempotência — tudo derivado, nada recebido.
--
-- O prazo é o `reserved_until` da intenção, sem recalcular. Pix que sobrevive
-- à reserva é oportunidade vendida duas vezes.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.open_commercial_payment_attempt(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_o   public.commercial_exclusivity_orders%ROWTYPE;
  v_i   public.commercial_checkout_intents%ROWTYPE;
  v_opp public.commercial_opportunities%ROWTYPE;
  v_p   public.commercial_payments%ROWTYPE;
  v_parc integer;
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders
   WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;
  IF NOT public.m2_is_company_owner(v_o.company_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_company_owner');
  END IF;
  IF v_o.payment_status = 'confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_paid');
  END IF;
  IF v_o.status <> 'signed' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_signed');
  END IF;
  -- Evidência contratual exigida: aceite e acordo mestre amarrados ao pedido.
  IF v_o.legal_acceptance_id IS NULL OR v_o.checkout_intent_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_from_checkout');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.commercial_master_agreements
                  WHERE id = v_o.master_agreement_id AND status = 'signed') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'master_agreement_missing');
  END IF;

  SELECT * INTO v_i FROM public.commercial_checkout_intents
   WHERE id = v_o.checkout_intent_id FOR UPDATE;
  IF v_i.status <> 'awaiting_payment_provider' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_awaiting_payment',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
  END IF;

  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = v_o.opportunity_id FOR UPDATE;
  IF v_opp.status <> 'payment_pending' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'opportunity_not_payment_pending',
                                         'opportunity_status', v_opp.status);
  END IF;

  -- Tentativa viva: MESMA chave, para o provedor não criar recurso novo.
  SELECT * INTO v_p FROM public.commercial_payments
   WHERE commercial_order_id = v_o.id AND status IN ('created','pending','paid');
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'payment_id', v_p.id, 'status', v_p.status,
      'payment_method', v_p.payment_method, 'amount_cents', v_p.amount_cents,
      'installments', v_p.installments, 'expires_at', v_p.expires_at,
      'idempotency_key', v_p.idempotency_key,
      'provider_order_id', v_p.provider_order_id,
      'provider_charge_id', v_p.provider_charge_id,
      'provider_payment_link_id', v_p.provider_payment_link_id);
  END IF;

  -- Método DERIVADO da fidelidade, como a V2 já decide. Parcelamento só no
  -- cartão, e o teto de seis é da regra comercial, não do provedor.
  v_parc := CASE WHEN v_o.fidelized THEN 6 ELSE NULL END;

  INSERT INTO public.commercial_payments
    (commercial_order_id, checkout_intent_id, provider, payment_method,
     amount_cents, installments, status, expires_at, idempotency_key)
  VALUES
    (v_o.id, v_i.id, 'pagarme',
     CASE WHEN v_o.fidelized THEN 'credit_card' ELSE 'pix' END,
     -- VALOR DO INSTANTÂNEO CONTRATUAL. Nunca recalculado, nunca do cliente.
     v_o.total_monetary_funding_required_cents,
     v_parc, 'created',
     -- PRAZO DA RESERVA. Sem now() + 30 minutos aqui.
     v_i.reserved_until,
     'bdflow-order-' || v_o.id::text)
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('commercial_payment.attempt_opened', v_id, 'owner',
    pg_catalog.jsonb_build_object('order_id', v_o.id,
                                  'method', CASE WHEN v_o.fidelized THEN 'credit_card' ELSE 'pix' END,
                                  'amount_cents', v_o.total_monetary_funding_required_cents,
                                  'expires_at', v_i.reserved_until));

  SELECT * INTO v_p FROM public.commercial_payments WHERE id = v_id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'payment_id', v_p.id, 'status', v_p.status,
    'payment_method', v_p.payment_method, 'amount_cents', v_p.amount_cents,
    'installments', v_p.installments, 'expires_at', v_p.expires_at,
    'idempotency_key', v_p.idempotency_key);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.open_commercial_payment_attempt(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.open_commercial_payment_attempt(uuid)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.open_commercial_payment_attempt(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Registro dos identificadores devolvidos pelo provedor
--
-- Só identificadores. Nenhum payload, nenhum dado de cartão.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.prov_record_payment_identifiers(
  p_payment_id uuid,
  p_provider_order_id text DEFAULT NULL,
  p_provider_charge_id text DEFAULT NULL,
  p_provider_payment_link_id text DEFAULT NULL,
  p_provider_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE v_p public.commercial_payments%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  SELECT * INTO v_p FROM public.commercial_payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'payment_not_found');
  END IF;
  IF v_p.status NOT IN ('created','pending') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'payment_not_open');
  END IF;

  UPDATE public.commercial_payments
     SET provider_order_id = coalesce(p_provider_order_id, provider_order_id),
         provider_charge_id = coalesce(p_provider_charge_id, provider_charge_id),
         provider_payment_link_id = coalesce(p_provider_payment_link_id, provider_payment_link_id),
         provider_reference = coalesce(p_provider_reference, provider_reference),
         status = 'pending'
   WHERE id = v_p.id;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'payment_id', v_p.id, 'status', 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prov_record_payment_identifiers(
  uuid,text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_record_payment_identifiers(
  uuid,text,text,text,text) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_record_payment_identifiers(
  uuid,text,text,text,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 6. Confirmação autoritativa — só depois de conciliação servidor-a-servidor
--
-- Os parâmetros são o que o SERVIDOR leu do provedor consultando a API com a
-- chave secreta, jamais o que um corpo de webhook afirmou. A função confere
-- valor, método e referência contra o registro local antes de mudar estado:
-- webhook forjado não tem como produzir `paid`.
--
-- PAGAMENTO TARDIO: se a oportunidade já foi legitimamente reatribuída, a
-- função NÃO contrata. Marca `late_unreconciled` e para — duas empresas com a
-- mesma exclusividade é o pior desfecho possível, pior que um estorno manual.
-- Não existe modelo canônico de estorno no projeto, e inventar um aqui seria
-- inventar processo financeiro.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.prov_confirm_commercial_payment(
  p_payment_id uuid,
  p_provider_status text,
  p_provider_amount_cents bigint,
  p_provider_payment_method text,
  p_provider_reference text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_p   public.commercial_payments%ROWTYPE;
  v_o   public.commercial_exclusivity_orders%ROWTYPE;
  v_opp public.commercial_opportunities%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  SELECT * INTO v_p FROM public.commercial_payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'payment_not_found');
  END IF;

  -- Idempotência: confirmar de novo devolve o mesmo resultado.
  IF v_p.status = 'paid' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'payment_id', v_p.id, 'status', 'paid', 'paid_at', v_p.paid_at);
  END IF;

  -- CONCILIAÇÃO: cada campo confere contra o registro local imutável.
  IF p_provider_status IS DISTINCT FROM 'paid' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'provider_status_not_paid',
                                         'provider_status', p_provider_status);
  END IF;
  IF p_provider_amount_cents IS DISTINCT FROM v_p.amount_cents THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'amount_mismatch');
  END IF;
  IF p_provider_payment_method IS DISTINCT FROM v_p.payment_method THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'method_mismatch');
  END IF;
  IF v_p.provider_reference IS NOT NULL
     AND p_provider_reference IS DISTINCT FROM v_p.provider_reference THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reference_mismatch');
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders
   WHERE id = v_p.commercial_order_id FOR UPDATE;
  SELECT * INTO v_opp FROM public.commercial_opportunities
   WHERE id = v_o.opportunity_id FOR UPDATE;

  -- PAGAMENTO TARDIO sobre oportunidade já reatribuída: falha fechada.
  IF v_opp.status NOT IN ('payment_pending','contracted')
     OR (v_opp.status = 'contracted'
         AND NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o2
                          WHERE o2.opportunity_id = v_opp.id AND o2.id = v_o.id
                            AND o2.payment_status = 'confirmed')) THEN
    UPDATE public.commercial_payments
       SET status = 'late_unreconciled',
           exception_reason = 'pagamento confirmado apos a oportunidade sair de payment_pending'
     WHERE id = v_p.id;
    PERFORM public.m1_auditar('commercial_payment.late_unreconciled', v_p.id, 'system',
      pg_catalog.jsonb_build_object('order_id', v_o.id,
                                    'opportunity_status', v_opp.status));
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'late_payment_unreconciled',
      'payment_status', 'late_unreconciled',
      'follow_up', 'conciliacao manual e eventual estorno: nao existe modelo canonico de estorno');
  END IF;

  UPDATE public.commercial_payments
     SET status = 'paid', paid_at = pg_catalog.now() WHERE id = v_p.id;

  UPDATE public.commercial_exclusivity_orders
     SET payment_status = 'confirmed',
         payment_confirmed_at = pg_catalog.now(),
         payment_amount_cents = v_p.amount_cents,
         payment_confirmed_source = 'payment_provider',
         payment_external_ref = v_p.provider_charge_id
   WHERE id = v_o.id;

  UPDATE public.commercial_opportunities
     SET status = 'contracted', reserved_until = NULL, updated_at = pg_catalog.now()
   WHERE id = v_opp.id;

  UPDATE public.commercial_checkout_intents
     SET status = 'paid' WHERE id = v_p.checkout_intent_id;

  PERFORM public.m1_auditar('commercial_payment.confirmed', v_p.id, 'system',
    pg_catalog.jsonb_build_object('order_id', v_o.id, 'amount_cents', v_p.amount_cents));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'payment_id', v_p.id, 'status', 'paid',
    'order_payment_status', 'confirmed',
    'opportunity_status', 'contracted',
    'intent_status', 'paid');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prov_confirm_commercial_payment(
  uuid,text,bigint,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_confirm_commercial_payment(
  uuid,text,bigint,text,text) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_confirm_commercial_payment(
  uuid,text,bigint,text,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 7. Expiração sem pagamento
--
-- O histórico contratual NÃO é apagado e nenhum centavo muda: o pedido fica,
-- a intenção fica, e apenas a oportunidade volta a ser reclamável pelas
-- mesmas regras de reserva que já existiam.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.prov_expire_commercial_payment(p_payment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_p   public.commercial_payments%ROWTYPE;
  v_o   public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  SELECT * INTO v_p FROM public.commercial_payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'payment_not_found');
  END IF;
  IF v_p.status = 'paid' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'already_paid');
  END IF;
  IF v_p.status = 'expired' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true, 'status', 'expired');
  END IF;
  IF v_p.expires_at > pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_expired_yet');
  END IF;

  UPDATE public.commercial_payments SET status = 'expired' WHERE id = v_p.id;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders
   WHERE id = v_p.commercial_order_id FOR UPDATE;

  UPDATE public.commercial_checkout_intents
     SET status = 'expired' WHERE id = v_p.checkout_intent_id
       AND status = 'awaiting_payment_provider';

  -- A oportunidade volta a ser reclamável. O pedido e a intenção permanecem
  -- como história: nada é excluído.
  UPDATE public.commercial_opportunities
     SET status = 'available', reserved_until = NULL, updated_at = pg_catalog.now()
   WHERE id = v_o.opportunity_id AND status = 'payment_pending';

  PERFORM public.m1_auditar('commercial_payment.expired', v_p.id, 'system',
    pg_catalog.jsonb_build_object('order_id', v_o.id));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'status', 'expired', 'opportunity_status', 'available');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prov_expire_commercial_payment(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_expire_commercial_payment(uuid)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_expire_commercial_payment(uuid) TO service_role;

COMMENT ON TABLE public.commercial_payments IS
  'Tentativa de pagamento comercial, neutra de provedor. NAO guarda chave '
  'secreta, numero de cartao, CVV nem payload bruto do provedor — apenas '
  'identificadores, valor, prazo e estado. Valor e prazo sao imutaveis: vem '
  'do instantaneo contratual e da reserva.';
