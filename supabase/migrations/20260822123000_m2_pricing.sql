-- ============================================================================
-- M2 / R5 — Precificação comercial autoritativa (versionada, server-side)
--
-- REGRA VIGENTE:
--   não fidelizado -> PRIMEIRAS 12 unidades = R$ 19.999,00 (bloco fechado)
--                     cada unidade ACIMA de 12 = R$ 1.299,00
--   fidelizado     -> toda unidade = R$ 1.299,00 (sem bloco)
--   Fidelidade: CNPJ + cidade + nicho. O primeiro contrato do contexto é
--   fundador (não fidelizado).
--
-- 75% (supermercado) / 70% (demais) é POOL CONTRATUAL DE BENEFÍCIO: obrigação
-- que o parceiro honra na PRÓPRIA rede. Não é desconto nem repasse, e a
-- BDFlow não o custodia. Invariante garantida por construção e por CHECK:
--   valor_economico = pool_contratual + valor_devido_bdflow
--
-- Dinheiro SEMPRE em centavos inteiros (bigint). O navegador nunca é
-- autoridade de preço: a vitrine apenas apresenta o que a RPC devolveu.
--
-- REVISÃO DE SEGURANÇA (SECURITY DEFINER) — ver supabase/tests/130:
--   * search_path fixo 'pg_catalog' e todo objeto qualificado por schema;
--   * REVOKE EXECUTE FROM PUBLIC em todas;
--   * leitura pública é INTENCIONAL e mínima: preço de tabela é informação de
--     vitrine, exatamente como o M1 já expõe a formação comercial via
--     get_current_commercial_formation (também SECURITY DEFINER, porque
--     commercial_niches só é concedida a service_role);
--   * sem escalonamento: nenhum parâmetro carrega identidade, nenhuma função
--     lê auth.uid() nem consulta dado pessoal, e nenhuma escreve.
-- ============================================================================

CREATE TABLE public.commercial_pricing_rules (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version                    integer     NOT NULL UNIQUE,
  status                     text        NOT NULL DEFAULT 'active',
  block_units                integer     NOT NULL,
  block_price_cents          bigint      NOT NULL,
  extra_unit_price_cents     bigint      NOT NULL,
  fidelized_unit_price_cents bigint      NOT NULL,
  pool_bps_supermarket       integer     NOT NULL,
  pool_bps_common            integer     NOT NULL,
  effective_from             timestamptz NOT NULL DEFAULT now(),
  notes                      text,
  created_at                 timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cpr_status_allowed CHECK (status = ANY (ARRAY['active','superseded'])),
  CONSTRAINT cpr_positivos
    CHECK (block_units > 0 AND block_price_cents > 0
           AND extra_unit_price_cents > 0 AND fidelized_unit_price_cents > 0),
  CONSTRAINT cpr_bps_validos
    CHECK (pool_bps_supermarket BETWEEN 0 AND 10000
           AND pool_bps_common BETWEEN 0 AND 10000)
);

-- No máximo UMA regra ativa por vez.
CREATE UNIQUE INDEX cpr_uma_ativa_idx
  ON public.commercial_pricing_rules (status) WHERE status = 'active';

ALTER TABLE public.commercial_pricing_rules ENABLE ROW LEVEL SECURITY;

-- Sem policy: nenhuma role do Data API lê a tabela direto. O acesso público
-- é mediado pelas RPCs abaixo, que expõem apenas o necessário.
REVOKE ALL ON TABLE public.commercial_pricing_rules
  FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO public.commercial_pricing_rules
  (version, status, block_units, block_price_cents, extra_unit_price_cents,
   fidelized_unit_price_cents, pool_bps_supermarket, pool_bps_common, notes)
VALUES
  (1, 'active', 12, 1999900, 129900, 129900, 7500, 7000,
   'Primeiro lançamento Grande Vitória: bloco de 12 e pools 75/70.');

-- ----------------------------------------------------------------------------
-- Fidelidade por CNPJ + cidade + nicho
-- ----------------------------------------------------------------------------
CREATE TABLE public.commercial_fidelity_records (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cnpj                    text        NOT NULL,
  uf                      text        NOT NULL,
  city_key                text        NOT NULL,
  niche_code              text        NOT NULL REFERENCES public.commercial_niches(code),
  established_by_order_id uuid,
  created_at              timestamptz NOT NULL DEFAULT now(),

  -- Dígito verificador, coerente com o M1.
  CONSTRAINT cfr_cnpj_valido CHECK (public.m1_cnpj_valido(cnpj)),
  CONSTRAINT cfr_uf_valida   CHECK (public.commercial_is_valid_uf(uf)),
  CONSTRAINT cfr_city_nonempty CHECK (length(btrim(city_key)) > 0),
  CONSTRAINT cfr_unico UNIQUE (cnpj, uf, city_key, niche_code)
);

ALTER TABLE public.commercial_fidelity_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY cfr_admin_select ON public.commercial_fidelity_records
  FOR SELECT TO authenticated USING (public.is_site_admin());

REVOKE ALL ON TABLE public.commercial_fidelity_records
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_fidelity_records TO authenticated;

-- ----------------------------------------------------------------------------
-- Cálculo autoritativo por nicho
--
-- SECURITY DEFINER justificado: commercial_niches e commercial_pricing_rules
-- não são legíveis por anon/authenticated (padrão canônico). O cálculo é
-- read-only, determinístico e NÃO confia em identidade — os parâmetros são
-- apenas o nicho e a condição de fidelidade.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.calculate_niche_contract_pricing(
  p_niche_code text,
  p_fidelized  boolean,
  p_pricing_version integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_rule     public.commercial_pricing_rules%ROWTYPE;
  v_qty      integer;
  v_economic bigint;
  v_bps      integer;
  v_pool     bigint;
BEGIN
  IF p_pricing_version IS NULL THEN
    SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE status = 'active';
  ELSE
    SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE version = p_pricing_version;
  END IF;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  SELECT contracted_quantity INTO v_qty
    FROM public.commercial_niches WHERE code = p_niche_code AND is_active;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_niche');
  END IF;

  IF p_fidelized THEN
    v_economic := v_qty::bigint * v_rule.fidelized_unit_price_cents;
  ELSE
    v_economic := v_rule.block_price_cents
                -- GREATEST é construção SQL (não função de schema): não se qualifica.
                + greatest(0, v_qty - v_rule.block_units)::bigint
                  * v_rule.extra_unit_price_cents;
  END IF;

  v_bps  := CASE WHEN p_niche_code = 'supermarket'
                 THEN v_rule.pool_bps_supermarket ELSE v_rule.pool_bps_common END;
  v_pool := (v_economic * v_bps) / 10000;   -- divisão inteira (floor)

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'pricing_rule_version', v_rule.version,
    'niche_code', p_niche_code,
    'nominal_quantity', v_qty,
    'fidelized', p_fidelized,
    'currency', 'BRL',
    'economic_value_cents', v_economic,
    'pool_bps', v_bps,
    'contractual_pool_cents', v_pool,
    -- Invariante por construção: devido := econômico - pool.
    'bdflow_due_cents', v_economic - v_pool);
END;
$$;

-- Contexto de fidelidade (dado comercial interno: nunca público).
CREATE FUNCTION public.is_fidelized_context(
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
       AND f.niche_code = p_niche_code);
$$;

-- ----------------------------------------------------------------------------
-- Vitrine pública: preço vigente + composição transparente
-- Exposição pública INTENCIONAL e mínima — nenhum dado pessoal ou comercial
-- de parceiro é revelado, apenas a tabela de preços vigente.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.get_public_niche_pricing()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_version integer;
  v_itens   jsonb := '[]'::jsonb;
  v_n       record;
BEGIN
  SELECT version INTO v_version
    FROM public.commercial_pricing_rules WHERE status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_rule_unavailable');
  END IF;

  FOR v_n IN
    SELECT code, display_name, contracted_quantity
      FROM public.commercial_niches WHERE is_active ORDER BY sort_order
  LOOP
    v_itens := v_itens || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'niche_code', v_n.code,
      'display_name', v_n.display_name,
      'nominal_quantity', v_n.contracted_quantity,
      'founding',  public.calculate_niche_contract_pricing(v_n.code, false),
      'fidelized', public.calculate_niche_contract_pricing(v_n.code, true)));
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true, 'pricing_rule_version', v_version,
    'currency', 'BRL', 'niches', v_itens);
END;
$$;

-- ----------------------------------------------------------------------------
-- ACLs — mínimo exato
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.calculate_niche_contract_pricing(text,boolean,integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.calculate_niche_contract_pricing(text,boolean,integer)
  TO anon, authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_public_niche_pricing() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_public_niche_pricing()
  TO anon, authenticated, service_role;

-- Fidelidade NÃO é pública: revela relação comercial de CNPJ.
REVOKE EXECUTE ON FUNCTION public.is_fidelized_context(text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_fidelized_context(text,text,text,text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.is_fidelized_context(text,text,text,text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.get_public_niche_pricing() IS
  'Vitrine pública: preço vigente por nicho com a composição contratual '
  '(pool de benefício na rede do parceiro x valor devido à BDFlow). '
  'SECURITY DEFINER pelo mesmo motivo de get_current_commercial_formation.';
