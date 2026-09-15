-- ============================================================================
-- RESERVA COMERCIAL AUTORITATIVA DE 30 MINUTOS
-- e correção do portão de titular da Comercial V2
--
-- DEFEITO CORRIGIDO
-- A migration 28 confere `m.role = 'owner'` em dois lugares — na RPC de
-- intenção de checkout e na política `cci_owner_select`. O papel é restrito
-- por CHECK a `partner_owner` ou `partner_manager`, então `'owner'` é
-- INSATISFAZÍVEL: a RPC sempre devolveu `not_company_owner` e o titular nunca
-- conseguiu ler a própria intenção. Sobreviveu porque a única asserção sobre
-- essa RPC era negativa (anon não executa); nenhum teste jamais exercitou um
-- caminho de sucesso.
--
-- A correção reusa o helper canônico `m2_is_company_owner`, que já define
-- titular válido como partner_owner + ativo + auth.uid(), em vez de repetir
-- um terceiro literal de papel. Nada é concedido a partner_manager, a anônimo,
-- a titular de outra empresa nem a membro inativo.
--
-- O QUE ESTA MIGRATION ACRESCENTA
-- A reserva de 30 minutos que o schema já previa e ninguém havia implementado:
-- `commercial_opportunities` sempre teve `status` e `reserved_until`, mas
-- `reserved_until` só era ESCRITO como NULL, na venda manual.
--
-- RESOLUÇÃO AUTORITATIVA DA OPORTUNIDADE
-- Nenhuma regra nova de vínculo foi inventada. Três unicidades já existentes
-- encadeiam empresa + nicho numa única oportunidade:
--
--   empresa.uf + commercial_city_key(empresa.city)
--     -> commercial_region_cities     UNIQUE (uf, city_key)
--     -> commercial_exclusivities     UNIQUE (region_id) WHERE is_current
--     -> commercial_opportunities     UNIQUE (exclusivity_id, niche_code)
--
-- É a mesma leitura (uf, city_key) que a R15 já faz para fidelidade, usada no
-- sentido resolvente. O navegador não fornece nada disso.
--
-- ADITIVA. Nenhuma das 31 migrations anteriores é editada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Vínculo da intenção com a oportunidade reservada
--
-- As colunas são NULÁVEIS de propósito: linhas históricas (se houvesse) não
-- são reescritas, e o contrato imutável do instantâneo econômico continua
-- intacto — nenhum campo monetário muda aqui.
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN IF NOT EXISTS opportunity_id uuid
    REFERENCES public.commercial_opportunities(id),
  ADD COLUMN IF NOT EXISTS exclusivity_id uuid
    REFERENCES public.commercial_exclusivities(id),
  ADD COLUMN IF NOT EXISTS region_id uuid
    REFERENCES public.commercial_regions(id),
  ADD COLUMN IF NOT EXISTS reserved_until timestamptz;

-- No máximo UMA intenção viva por oportunidade. A serialização real é o
-- FOR UPDATE na oportunidade; este índice é a rede de proteção que transforma
-- um erro de lógica futuro em violação de unicidade em vez de reserva dupla.
CREATE UNIQUE INDEX IF NOT EXISTS cci_reserva_viva_por_oportunidade_idx
  ON public.commercial_checkout_intents (opportunity_id)
  WHERE status = 'draft' AND reserved_until IS NOT NULL;

COMMENT ON COLUMN public.commercial_checkout_intents.reserved_until IS
  'Instante de expiracao da reserva, SEMPRE derivado de now() no servidor. '
  'O navegador nunca fornece este valor; ele o recebe apenas para exibir.';

-- ----------------------------------------------------------------------------
-- 2. Política de leitura — mesmo defeito, mesma correção
--
-- O titular volta a enxergar a própria intenção. O caminho de admin é
-- preservado. A escrita continua exclusivamente por RPC: a tabela segue sem
-- INSERT/UPDATE/DELETE para qualquer papel de API.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS cci_owner_select ON public.commercial_checkout_intents;

CREATE POLICY cci_owner_select ON public.commercial_checkout_intents
  FOR SELECT TO authenticated
  USING (
    public.is_site_admin()
    OR public.m2_is_company_owner(commercial_checkout_intents.company_id)
  );

-- ----------------------------------------------------------------------------
-- 3. Intenção de checkout COM reserva de 30 minutos
--
-- A assinatura de entrada não muda, e continua não aceitando preço,
-- fidelidade, forma de pagamento, quantidade, componente monetário,
-- identidade de oportunidade nem prazo de expiração. Tudo isso é derivado.
--
-- Estender a função existente, em vez de criar uma paralela, é deliberado:
-- um segundo caminho de compra comercial seria um segundo lugar para a
-- autoridade divergir. E é seguro porque hoje ela não tem nenhum chamador
-- bem-sucedido — o portão quebrado garantia isso.
--
-- ORDEM DAS PORTAS
--   1. autenticado
--   2. modo de liquidação válido
--   3. empresa existe e está ativa
--   4. titular ativo da PRÓPRIA empresa (helper canônico)
--   5. região resolvida da empresa
--   6. exclusividade corrente da região
--   7. oportunidade do nicho, travada com FOR UPDATE
--   8. reserva vencida é recuperada; reserva viva de terceiro é respeitada
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_commercial_checkout_intent(
  p_company_id uuid,
  p_niche_code text,
  p_benefit_settlement_mode text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
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
               v_company.cnpj, v_company.uf, v_company.city, p_niche_code);

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
     created_by)
  VALUES
    (p_company_id, p_niche_code, 'draft', (v_p->>'pricing_rule_version')::int,
     2, v_fidel, v_p->>'payment_method',
     p_benefit_settlement_mode, 'BRL', (v_p->>'nominal_quantity')::int,
     (v_p->>'economic_value_cents')::bigint, v_pool, v_bdflow,
     v_cash, v_bdflow + v_cash,
     v_opp.id, v_excl, v_region, v_ate,
     v_uid)
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('commercial_checkout.reserved', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'opportunity_id', v_opp.id,
                                  'niche_code', p_niche_code,
                                  'reserved_until', v_ate));

  SELECT * INTO v_viva FROM public.commercial_checkout_intents WHERE id = v_id;
  RETURN public.cci_resposta_intencao(v_viva, false);
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Resposta única para os dois caminhos (nova reserva e retomada idempotente)
--
-- Uma só montagem para que o payload não possa divergir entre eles — divergir
-- seria a porta para o navegador confiar num campo que só existe num dos dois.
-- Nenhum segredo, nenhum identificador de auth, nenhum dado de outra empresa.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cci_resposta_intencao(
  p_i public.commercial_checkout_intents,
  p_ja boolean
)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
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
    'nominal_quantity', p_i.nominal_quantity,
    'fidelized', p_i.fidelized,
    'payment_method', p_i.payment_method,
    'benefit_settlement_mode', p_i.benefit_settlement_mode,
    'currency', p_i.currency,
    'economic_value_cents', p_i.economic_value_cents,
    'user_pool_cents', p_i.user_pool_cents,
    'bdflow_ops_investment_cents', p_i.bdflow_ops_investment_cents,
    'cash_user_pool_funding_cents', p_i.cash_user_pool_funding_cents,
    'total_monetary_funding_required_cents', p_i.total_monetary_funding_required_cents,
    'participant_target', p_i.participant_target);
$$;

-- ----------------------------------------------------------------------------
-- 5. Privilégios — reafirmados, jamais alargados
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.cci_resposta_intencao(
  public.commercial_checkout_intents, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cci_resposta_intencao(
  public.commercial_checkout_intents, boolean) FROM anon, authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text)
  TO authenticated;

COMMENT ON FUNCTION public.create_commercial_checkout_intent(uuid,text,text) IS
  'Intencao de checkout comercial COM reserva autoritativa de 30 minutos. '
  'Titular ativo (partner_owner) da propria empresa, via m2_is_company_owner. '
  'Regiao, exclusividade corrente e oportunidade sao resolvidas no servidor; '
  'preco, fidelidade, forma de pagamento, quantidade e expiracao tambem. O '
  'navegador nao fornece nenhum deles. Nicho inteiro, nunca unidades soltas.';
