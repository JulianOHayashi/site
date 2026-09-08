-- ============================================================================
-- COMERCIAL V2 — ENDURECIMENTO DO SNAPSHOT DE PROVISIONAMENTO
--
-- POR QUE ESTA MIGRATION EXISTE
-- A migration 28 acrescentou ao snapshot do pedido quatro campos que passaram
-- a carregar o significado comercial da V2 — modo de liquidação, caixa
-- exigido para o pool, financiamento monetário total e versão da política de
-- distribuição — mas duas peças anteriores a ela não foram atualizadas:
--
--   F-03  m2_orders_protect() é anterior à 28 e não conhece esses campos.
--         O snapshot economico estava congelado; a escolha contratual da V2,
--         não.
--   F-01  build_app_provisioning_payload() ainda emite
--         schema_version = bdflow.commercial_provisioning.v1 e
--         distribution_policy_version = 1.
--   F-02  e o payload não carrega o modo de liquidação por parceiro.
--
-- A ordem importa: construir o transporte assinado sobre um payload
-- semanticamente V1 entregaria com segurança criptográfica o significado
-- errado. Primeiro a asserção comercial fica correta; o transporte vem depois.
--
-- ADITIVA. Nenhuma das 29 migrations anteriores é editada. Nenhuma linha
-- histórica é reescrita: pedidos e mensagens já finalizados permanecem como
-- estão, porque eram verdadeiros quando foram criados.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. F-03 — imutabilidade dos campos V2 do snapshot do pedido
--
-- O bloco econômico existente congela seus campos a partir de QUALQUER
-- UPDATE, sem depender do estado do ciclo de vida: não há porta de rascunho.
-- Os quatro campos da V2 entram exatamente nesse mesmo bloco, com a mesma
-- fronteira e a mesma mensagem de erro. Espelhar a proteção existente é
-- deliberado — inventar um ciclo de vida novo aqui seria endurecer o que o
-- contrato não pediu.
--
-- IS DISTINCT FROM já é seguro para nulo: as linhas históricas têm NULL nos
-- quatro campos e continuam podendo ser atualizadas em tudo o mais, desde que
-- esses valores não mudem. Elas não são normalizadas para a V2.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.m2_orders_protect()
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
  -- Campos V2 do snapshot (migration 28). Mesma fronteira, mesmo bloco.
  OR NEW.benefit_settlement_mode               IS DISTINCT FROM OLD.benefit_settlement_mode
  OR NEW.cash_user_pool_funding_cents          IS DISTINCT FROM OLD.cash_user_pool_funding_cents
  OR NEW.total_monetary_funding_required_cents IS DISTINCT FROM OLD.total_monetary_funding_required_cents
  OR NEW.benefit_distribution_policy_version   IS DISTINCT FROM OLD.benefit_distribution_policy_version
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

REVOKE EXECUTE ON FUNCTION public.m2_orders_protect() FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 2. F-01 e F-02 — payload de provisionamento na versão 2
--
-- O que muda: schema_version, distribution_policy_version, e dois campos
-- semânticos por parceiro. O que NÃO muda: todos os campos operacionais que o
-- App já consome, o identificador da exclusividade, a janela operacional, os
-- UUIDs de ponte e a política de cronograma. Isto é uma versão nova do mesmo
-- contrato, não um payload diferente.
--
-- MINIMIZAÇÃO DE DADOS (inalterada e reafirmada)
-- Continua fora: CNPJ, razão social, CPF, e-mail, telefone, documentos,
-- valor econômico, devido à BDFlow, forma de pagamento, fidelidade e
-- qualquer contabilidade interna. Os dois campos acrescentados são semântica
-- operacional, não contabilidade: o App precisa saber COMO o benefício será
-- disponibilizado e sob QUAL política o pool se converte em benefício.
--
-- cash_user_pool_funding_cents e total_monetary_funding_required_cents são
-- congelados no pedido pela seção 1, mas NÃO entram no payload: são o
-- financiamento devido à BDFlow, assunto do Site. O App opera com o pool
-- contratual e o modo.
--
-- FALHA FECHADA
-- A autoridade é o snapshot imutável de cada pedido, jamais a tabela de
-- preços vigente. Se algum dos pedidos assinados não declarar modo de
-- liquidação, ou declarar política diferente de 2, o payload NÃO é montado:
-- coagir silenciosamente para 2 seria afirmar uma escolha que ninguém fez.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.build_app_provisioning_payload(
  p_exclusivity_id uuid, p_environment text
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
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

  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'partner_network_bridge_id', c.partner_network_bridge_id,
      'niche_code', o.niche_code,
      'site_order_reference', o.id,
      'nominal_quantity', o.nominal_quantity,
      'currency', o.currency,
      'contractual_pool_cents', o.contractual_pool_cents,
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
$$;

REVOKE EXECUTE ON FUNCTION public.build_app_provisioning_payload(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.build_app_provisioning_payload(uuid,text)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.build_app_provisioning_payload(uuid,text) TO service_role;

-- ----------------------------------------------------------------------------
-- 3. A coluna schema_version passa a dizer a verdade
--
-- A tabela nasceu com DEFAULT v1 e o enfileiramento nunca preencheu a coluna
-- explicitamente — o payload dizia uma coisa e a coluna, outra. Com a V2 isso
-- deixaria de ser detalhe: é a coluna que um worker leria para decidir. O
-- enfileiramento passa a carimbar a versão A PARTIR do payload que acabou de
-- montar, e o DEFAULT acompanha.
--
-- Nenhuma linha existente é tocada: ALTER COLUMN ... SET DEFAULT vale para
-- inserções futuras. Mensagens V1 já gravadas continuam declarando v1, que é
-- exatamente o que elas são.
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_provisioning_messages
  ALTER COLUMN schema_version SET DEFAULT 'bdflow.commercial_provisioning.v2';

CREATE OR REPLACE FUNCTION public.admin_enqueue_app_provisioning(
  p_exclusivity_id uuid, p_environment text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_excl    public.commercial_exclusivities%ROWTYPE;
  v_exist   public.app_provisioning_messages%ROWTYPE;
  v_payload jsonb;
  v_id      uuid;
BEGIN
  PERFORM public.m1_exigir_admin();
  IF p_environment NOT IN ('local','staging','production') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_environment');
  END IF;

  SELECT * INTO v_excl FROM public.commercial_exclusivities
   WHERE id = p_exclusivity_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF v_excl.operation_authorized_at IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'operation_not_authorized');
  END IF;

  -- Idempotência por (exclusividade, ambiente) permanece intacta: uma única
  -- mensagem viva. O índice parcial apm_viva_idx cobre pending/dispatching/
  -- accepted, então uma mensagem V1 recusada e marcada 'failed' pela seção 4
  -- libera espaço para o reenfileiramento em V2 sem duplicar ciclo algum.
  SELECT * INTO v_exist FROM public.app_provisioning_messages
   WHERE exclusivity_id = p_exclusivity_id AND environment = p_environment
     AND status IN ('pending','dispatching','accepted');
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'message_id', v_exist.id, 'correlation_id', v_exist.correlation_id,
      'status', v_exist.status);
  END IF;

  v_payload := public.build_app_provisioning_payload(p_exclusivity_id, p_environment);
  IF (v_payload->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', v_payload->>'reason');
  END IF;

  INSERT INTO public.app_provisioning_messages
    (environment, exclusivity_id, schema_version, payload, payload_hash, created_by)
  VALUES (p_environment, p_exclusivity_id, v_payload->>'schema_version', v_payload,
          pg_catalog.encode(pg_catalog.sha256(
            pg_catalog.convert_to(v_payload::text,'UTF8')), 'hex'),
          auth.uid())
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('app_provisioning.enqueued', v_id, 'admin',
    pg_catalog.jsonb_build_object('exclusivity_id', p_exclusivity_id,
                                  'environment', p_environment,
                                  'schema_version', v_payload->>'schema_version'));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'message_id', v_id,
    'correlation_id', (SELECT correlation_id FROM public.app_provisioning_messages
                        WHERE id = v_id),
    'status', 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_enqueue_app_provisioning(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_enqueue_app_provisioning(uuid,text)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_enqueue_app_provisioning(uuid,text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. F-04 do ponto de vista da fila — a mensagem V1 pendente não vira V2 por
--    acidente, e também não vira despacho errado
--
-- O PROBLEMA REAL
-- Uma mensagem enfileirada antes desta migration carrega payload v1. O
-- payload e o schema_version da linha são IMUTÁVEIS por
-- m2_provisioning_protect(): reconstruir a mensagem no lugar exigiria
-- enfraquecer essa proteção. Não vamos enfraquecê-la, e também não vamos
-- reescrever histórico com DML amplo.
--
-- A ESCOLHA
-- Recusa no momento da reivindicação, com transição de estado que o próprio
-- ciclo de vida já previa. Ao ser reivindicada, uma mensagem cujo payload não
-- esteja na versão corrente é marcada 'failed' com last_error explícito e NÃO
-- é despachada. Isso libera o índice parcial de unicidade e permite ao admin
-- reenfileirar, o que gera uma mensagem V2 nova, determinística, montada dos
-- mesmos snapshots imutáveis.
--
-- Por que é seguro:
--   - mensagens 'accepted' retornam antes, intocadas;
--   - 'rejected' cai em not_dispatchable, intocada;
--   - a transição só alcança pending/dispatching/failed, que já são os
--     estados que o caminho de max_attempts alterava;
--   - é determinística e idempotente: reivindicar de novo dá o mesmo
--     resultado;
--   - nenhuma linha finalizada é reescrita e nenhum payload é mutado.
--
-- Falha fechada: na dúvida, não despacha.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prov_claim_provisioning_message(p_message_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_msg public.app_provisioning_messages%ROWTYPE;
  v_versao_payload text;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  SELECT * INTO v_msg FROM public.app_provisioning_messages
   WHERE id = p_message_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF v_msg.status = 'accepted' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
                                         'status', 'accepted');
  END IF;
  -- Lease: outro worker está despachando agora.
  IF v_msg.status = 'dispatching'
     AND v_msg.updated_at > pg_catalog.now() - public.m1_mint_lease() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'lease_held');
  END IF;
  IF v_msg.status NOT IN ('pending','dispatching','failed') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- Porta de versão. A autoridade é o payload gravado, não a coluna: é o
  -- payload que seria assinado e transportado.
  v_versao_payload := v_msg.payload->>'schema_version';
  IF v_versao_payload IS DISTINCT FROM 'bdflow.commercial_provisioning.v2' THEN
    UPDATE public.app_provisioning_messages
       SET status = 'failed', last_error = 'stale_schema_version'
     WHERE id = v_msg.id;
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'stale_schema_version',
      'message_id', v_msg.id,
      'found_schema_version', v_versao_payload,
      'expected_schema_version', 'bdflow.commercial_provisioning.v2');
  END IF;

  IF v_msg.attempt_count >= public.m1_mint_max_tentativas() THEN
    UPDATE public.app_provisioning_messages
       SET status = 'failed', last_error = 'max_attempts'
     WHERE id = v_msg.id;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'max_attempts');
  END IF;

  UPDATE public.app_provisioning_messages
     SET status = 'dispatching', attempt_count = attempt_count + 1,
         dispatched_at = pg_catalog.now()
   WHERE id = v_msg.id;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'already', false,
    'message_id', v_msg.id,
    'correlation_id', v_msg.correlation_id,   -- JTI
    'environment', v_msg.environment,
    'schema_version', v_msg.schema_version,
    'payload', v_msg.payload,
    'payload_hash', v_msg.payload_hash,
    'attempt', v_msg.attempt_count + 1);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prov_claim_provisioning_message(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_claim_provisioning_message(uuid)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_claim_provisioning_message(uuid) TO service_role;

COMMENT ON FUNCTION public.build_app_provisioning_payload(uuid,text) IS
  'Asserção comercial imutável do Site para o App, schema '
  'bdflow.commercial_provisioning.v2, política de distribuição 2. Autoridade '
  'é o snapshot de cada pedido, nunca a tabela de preços vigente. Falha '
  'fechada se algum pedido assinado não declarar modo de liquidação ou '
  'declarar política diferente de 2. Não transporta nada: entrega HTTP e '
  'assinatura são checkpoint posterior.';
