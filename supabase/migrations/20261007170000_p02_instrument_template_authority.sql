-- ============================================================================
-- P0-2 — INFRAESTRUTURA DO INSTRUMENTO COMERCIAL
--
-- A MINUTA v1.4 NÃO É ATIVADA. A fonte congelada diz, com todas as letras,
-- "MINUTA — ... — NÃO ASSINAR AINDA". Esta migration constrói a autoridade de
-- modelos com ciclo de vida e registra a v1.4 como `draft`, NÃO assinável, para
-- rastreabilidade. Como não existe nenhum instrumento legal assinável, o caminho
-- de produção falha fechado com `commercial_instrument_template_unavailable`.
-- Nada aqui promove a v1.4 de draft para signable, nem oferece meio de fazê-lo
-- silenciosamente: a promoção exige DML administrativa deliberada.
--
-- O QUE O ITEM D DEIXOU PELA METADE
-- A migration 20261005160000 criou colunas, índice único, trigger de
-- imutabilidade e leitor, e NENHUM caminho de escrita. Verificado em runtime
-- antes desta migration: 13 de 13 pedidos com `instrument_code` e
-- `instrument_snapshot` nulos, e `get_order_instrument` devolvendo
-- `instrument_snapshot_missing` para todos.
--
-- NUMERAÇÃO — SF-0001, SF-0002, ...
-- SF-0001..SF-0006 são NÚMEROS DE INSTRUMENTO, não identificadores de nicho: os
-- documentos congelados permitem escolher o nicho, e o número não codifica
-- supermercado, farmácia ou qualquer outro. A alocação é um serial global,
-- atômico e monotônico, implementado como SEQUENCE do PostgreSQL — que dá
-- exatamente as invariantes pedidas: unicidade, monotonicidade, nenhum reuso de
-- número comprometido e segurança sob concorrência. Transação revertida consome
-- o número candidato e deixa lacuna; lacuna NÃO é tratada como requisito legal,
-- porque a fonte congelada não a exige. O que nunca acontece é um número já
-- comprometido ser reaproveitado.
--
-- Pelo menos quatro dígitos, expandindo naturalmente além de 9999: SF-0001 e,
-- passado o décimo milésimo, SF-10000. O CHECK `^SF-[0-9]{4}$` do item D
-- impediria essa expansão e por isso é substituído por `^SF-[0-9]{4,}$`.
--
-- IDENTIDADE DO MODELO VERSUS DO INSTRUMENTO
-- São dois hashes com papéis diferentes, e eles NUNCA se confundem:
--   - `source_hash` do modelo: SHA-256 da fonte congelada. Igual para todo
--     instrumento emitido sob aquele modelo.
--   - `instrument_snapshot_hash`: SHA-256 da serialização canônica do snapshot
--     INDIVIDUALIZADO daquele pedido. Único por pedido.
-- Reusar o hash do modelo como hash do instrumento destruiria a capacidade de
-- provar que os fatos daquele pedido não mudaram, que é todo o propósito.
--
-- SERIALIZAÇÃO CANÔNICA
-- O hash é calculado sobre `jsonb::text`. A forma de texto de um `jsonb` no
-- PostgreSQL é normalizada — chaves ordenadas, duplicatas eliminadas, espaços
-- irrelevantes removidos —, portanto dois snapshots com os mesmos fatos
-- produzem exatamente a mesma string e o mesmo hash, independentemente da ordem
-- em que os campos foram montados.
--
-- OUTROS FICA DORMENTE
-- O modelo em papel tem a opção OUTROS, mas a autoridade de produto e preço tem
-- seis nichos canônicos. OUTROS NÃO é habilitado em checkout nem em preço aqui.
-- Fica como capacidade legal dormente, declarada no modelo e desligada, até que
-- uma decisão de produto/preço separada a ative.
--
-- Sem push, deploy, staging, produção, seed remoto ou migration remota.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. AUTORIDADE DE MODELOS, com ciclo de vida
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.commercial_instrument_templates (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_code           text NOT NULL,
  template_version        text NOT NULL,
  template_date           date NOT NULL,
  source_hash             text NOT NULL,
  lifecycle_status        text NOT NULL,
  -- O modelo congelado v1.4 é o da PRIMEIRA COMPRA, condição NÃO fidelizada.
  -- Um pedido fidelizado não pode ser regido por ele, e é isto que torna a
  -- restrição verificável em vez de combinada de boca.
  applies_to_fidelized    boolean NOT NULL,
  -- Capacidade legal dormente: o papel admite OUTROS, o produto não. Declarado
  -- e DESLIGADO.
  allows_outros_niche     boolean NOT NULL DEFAULT false,
  -- Fatos materiais que o modelo exige individualizados ANTES da assinatura.
  -- O construtor do snapshot falha fechado se qualquer um faltar.
  required_snapshot_fields text[] NOT NULL,
  notes                   text,
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cit_lifecycle_valido
    CHECK (lifecycle_status IN ('draft', 'signable', 'archived')),
  CONSTRAINT cit_version_nonempty
    CHECK (length(btrim(template_version)) > 0),
  CONSTRAINT cit_source_hash_sha256
    CHECK (source_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cit_campos_exigidos_nao_vazio
    CHECK (array_length(required_snapshot_fields, 1) >= 1),
  CONSTRAINT cit_code_unico UNIQUE (template_code)
);

-- No máximo UM modelo assinável por condição de fidelidade. Impede que duas
-- minutas assináveis disputem o mesmo pedido.
CREATE UNIQUE INDEX IF NOT EXISTS cit_signable_por_fidelidade_uidx
  ON public.commercial_instrument_templates (applies_to_fidelized)
  WHERE lifecycle_status = 'signable';

ALTER TABLE public.commercial_instrument_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_instrument_templates FROM PUBLIC;
REVOKE ALL ON public.commercial_instrument_templates FROM anon;
REVOKE ALL ON public.commercial_instrument_templates FROM authenticated;
GRANT SELECT ON public.commercial_instrument_templates TO service_role;

COMMENT ON TABLE public.commercial_instrument_templates IS
  'Autoridade de modelos de instrumento comercial, com ciclo de vida '
  'draft/signable/archived. Somente modelo signable rege assinatura. A minuta '
  'v1.4 esta registrada como draft porque a propria fonte congelada diz NAO '
  'ASSINAR AINDA.';
COMMENT ON COLUMN public.commercial_instrument_templates.source_hash IS
  'SHA-256 da FONTE CONGELADA do modelo. NUNCA e usado como hash do '
  'instrumento individualizado de um pedido.';
COMMENT ON COLUMN public.commercial_instrument_templates.allows_outros_niche IS
  'Capacidade dormente. O modelo em papel admite OUTROS; o produto tem seis '
  'nichos canonicos. Ligar isto exige decisao de produto/preco separada.';

-- A minuta v1.4 real, registrada como DRAFT, para rastreabilidade. O hash e o
-- da fonte congelada conferida contra o manifesto oficial.
INSERT INTO public.commercial_instrument_templates
  (template_code, template_version, template_date, source_hash,
   lifecycle_status, applies_to_fidelized, allows_outros_niche,
   required_snapshot_fields, notes)
VALUES
  ('SF-MINUTA-PRESENCIAL-v1.4', '1.4', DATE '2026-10-05',
   '03f36670adfc9b2940e9f331a00097c865c4129e7f9319e8099f3ff85b2b0c73',
   'draft', false, false,
   ARRAY[
     'company_legal_name','company_cnpj','company_trade_name',
     'representative_full_name','representative_cpf','representative_role_title',
     'representative_authority_status',
     'city','uf','region_id','exclusivity_id',
     'nfse_taker_cnpj','activity_description','activity_location',
     'niche_code','nominal_quantity','benefit_settlement_mode',
     'master_agreement_id','master_legal_document_id','master_agreement_version',
     'master_document_hash','order_id','pricing_rule_version',
     'contract_economics_version','economic_value_cents',
     'mei_consideration_cents','smallflags_qa_cents','smallflags_main_fee_cents',
     'smallflags_total_remuneration_cents',
     'total_monetary_funding_required_cents','participation_value_cents',
     'acceptance_actor_id','acceptance_at'
   ],
   'MINUTA v1.4 — NAO ASSINAR AINDA, conforme a propria fonte congelada. '
   'Registrada como draft para rastreabilidade do hash e da data. Primeira '
   'compra, condicao NAO fidelizada. OUTROS declarado e desligado.')
ON CONFLICT (template_code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. SERIAL GLOBAL DO INSTRUMENTO
-- ---------------------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS public.commercial_instrument_serial
  AS bigint START WITH 1 INCREMENT BY 1 NO CYCLE;

REVOKE ALL ON SEQUENCE public.commercial_instrument_serial FROM PUBLIC;
REVOKE ALL ON SEQUENCE public.commercial_instrument_serial FROM anon;
REVOKE ALL ON SEQUENCE public.commercial_instrument_serial FROM authenticated;

COMMENT ON SEQUENCE public.commercial_instrument_serial IS
  'Serial global do instrumento SmallFlags. SEQUENCE da unicidade, '
  'monotonicidade, seguranca sob concorrencia e ausencia de reuso. Transacao '
  'revertida consome o candidato e deixa lacuna; lacuna nao e requisito legal.';

-- O CHECK do item D fixava exatamente quatro digitos, o que travaria a
-- numeracao em SF-9999. Passa a exigir ao MENOS quatro.
ALTER TABLE public.commercial_exclusivity_orders
  DROP CONSTRAINT IF EXISTS ceo_instrument_code_format;
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_instrument_code_format
  CHECK (instrument_code IS NULL OR instrument_code ~ '^SF-[0-9]{4,}$') NOT VALID;

CREATE OR REPLACE FUNCTION public.commercial_next_instrument_code()
RETURNS text
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  -- ATENCAO: lpad() TRUNCA quando a entrada e mais longa que o alvo —
  -- lpad('10000', 4, '0') devolve '1000'. Usar lpad direto fazia SF-10000
  -- colidir com SF-1000 e destruia unicidade e monotonicidade de uma vez. Foi
  -- pego em runtime, nao em revisao. Por isso o zero-padding so se aplica
  -- ABAIXO de 10000; dali para cima o numero cresce por conta propria.
  SELECT 'SF-' || CASE
           WHEN n < 10000 THEN pg_catalog.lpad(n::text, 4, '0')
           ELSE n::text
         END
    FROM pg_catalog.nextval('public.commercial_instrument_serial') AS n;
$$;

ALTER FUNCTION public.commercial_next_instrument_code() OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.commercial_next_instrument_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.commercial_next_instrument_code() FROM anon;
REVOKE EXECUTE ON FUNCTION public.commercial_next_instrument_code() FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.commercial_next_instrument_code() TO service_role;

-- ---------------------------------------------------------------------------
-- 3. IDENTIDADE INDIVIDUALIZADA DO INSTRUMENTO NO PEDIDO
-- ---------------------------------------------------------------------------

ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS instrument_template_id    uuid
    REFERENCES public.commercial_instrument_templates(id),
  ADD COLUMN IF NOT EXISTS instrument_template_date  date,
  ADD COLUMN IF NOT EXISTS instrument_snapshot_hash  text;

COMMENT ON COLUMN public.commercial_exclusivity_orders.instrument_snapshot_hash IS
  'SHA-256 da serializacao canonica do snapshot INDIVIDUALIZADO deste pedido. '
  'Jamais igual ao source_hash do modelo, que e comum a todos os instrumentos '
  'emitidos sob ele.';

ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_snapshot_hash_sha256
  CHECK (instrument_snapshot_hash IS NULL
         OR instrument_snapshot_hash ~ '^[0-9a-f]{64}$') NOT VALID;

-- O hash do instrumento NUNCA pode ser o hash do modelo.
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_snapshot_hash_nao_e_do_modelo
  CHECK (instrument_snapshot_hash IS NULL
         OR instrument_template_hash IS NULL
         OR instrument_snapshot_hash <> instrument_template_hash) NOT VALID;

-- ATOMICIDADE: instrumento é tudo ou nada. Instrumento pela metade seria pior
-- que instrumento ausente — pareceria assinado sem o ser.
ALTER TABLE public.commercial_exclusivity_orders
  ADD CONSTRAINT ceo_instrumento_completo_ou_ausente
  CHECK (
    (instrument_code IS NULL AND instrument_template_id IS NULL
     AND instrument_template_version IS NULL AND instrument_template_hash IS NULL
     AND instrument_template_date IS NULL AND instrument_snapshot IS NULL
     AND instrument_snapshot_hash IS NULL)
    OR
    (instrument_code IS NOT NULL AND instrument_template_id IS NOT NULL
     AND instrument_template_version IS NOT NULL AND instrument_template_hash IS NOT NULL
     AND instrument_template_date IS NOT NULL AND instrument_snapshot IS NOT NULL
     AND instrument_snapshot_hash IS NOT NULL)
  ) NOT VALID;

-- ---------------------------------------------------------------------------
-- 4. RESOLVEDOR DO MODELO ASSINÁVEL — falha fechada enquanto não houver
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.commercial_signable_instrument_template(
  p_fidelized boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_t public.commercial_instrument_templates%ROWTYPE;
BEGIN
  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE lifecycle_status = 'signable'
     AND applies_to_fidelized = p_fidelized;
  IF NOT FOUND THEN
    -- Estado CORRENTE e esperado: a minuta v1.4 esta draft porque a fonte
    -- congelada manda nao assinar ainda.
    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'commercial_instrument_template_unavailable',
      'fidelized', p_fidelized);
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'template_id', v_t.id,
    'template_code', v_t.template_code,
    'template_version', v_t.template_version,
    'template_date', v_t.template_date,
    'source_hash', v_t.source_hash,
    'applies_to_fidelized', v_t.applies_to_fidelized,
    'allows_outros_niche', v_t.allows_outros_niche,
    'required_snapshot_fields', pg_catalog.to_jsonb(v_t.required_snapshot_fields));
END;
$function$;

ALTER FUNCTION public.commercial_signable_instrument_template(boolean) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.commercial_signable_instrument_template(boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.commercial_signable_instrument_template(boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.commercial_signable_instrument_template(boolean) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.commercial_signable_instrument_template(boolean)
  TO service_role;

COMMENT ON FUNCTION public.commercial_signable_instrument_template(boolean) IS
  'Devolve o modelo ASSINAVEL para a condicao de fidelidade pedida, ou falha '
  'fechada com commercial_instrument_template_unavailable. Modelo draft nunca '
  'rege assinatura.';

-- ---------------------------------------------------------------------------
-- 5. OBRIGATORIEDADE AUTOMÁTICA quando existir modelo assinável
--
-- Enquanto nenhum modelo for assinável, pedido sem instrumento continua válido
-- — é o estado de hoje, e os pedidos históricos seguem intocados. No instante em
-- que um modelo for promovido a signable, todo pedido NOVO daquela condição de
-- fidelidade passa a exigir o instrumento completo, na MESMA transação. A regra
-- não depende de ninguém lembrar de mudar código junto.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ceo_exigir_instrumento_quando_assinavel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_t public.commercial_instrument_templates%ROWTYPE;
BEGIN
  IF NEW.status <> 'signed' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE lifecycle_status = 'signable'
     AND applies_to_fidelized = coalesce(NEW.fidelized, false);
  IF NOT FOUND THEN
    -- Sem modelo assinável não há instrumento a exigir. Mas instrumento PELA
    -- METADE segue proibido pelo CHECK ceo_instrumento_completo_ou_ausente.
    RETURN NEW;
  END IF;

  IF NEW.instrument_code IS NULL
     OR NEW.instrument_template_id IS NULL
     OR NEW.instrument_snapshot IS NULL
     OR NEW.instrument_snapshot_hash IS NULL THEN
    RAISE EXCEPTION
      'instrumento_obrigatorio: existe modelo assinavel (%) para fidelizado=%, '
      'logo o pedido assinado exige codigo, modelo, snapshot e hash do snapshot '
      'na mesma transacao.',
      v_t.template_code, coalesce(NEW.fidelized, false)
      USING ERRCODE = 'check_violation';
  END IF;

  -- O instrumento tem de apontar para o modelo ASSINÁVEL daquela condição, e
  -- não para outro qualquer: é o que impede um pedido fidelizado nascer sob a
  -- minuta de primeira compra não fidelizada.
  IF NEW.instrument_template_id <> v_t.id THEN
    RAISE EXCEPTION
      'instrumento_modelo_incompativel: pedido com fidelizado=% nao pode ser '
      'regido pelo modelo %; o modelo assinavel desta condicao e %.',
      coalesce(NEW.fidelized, false), NEW.instrument_template_id, v_t.id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS ceo_exigir_instrumento ON public.commercial_exclusivity_orders;
CREATE TRIGGER ceo_exigir_instrumento
  BEFORE INSERT ON public.commercial_exclusivity_orders
  FOR EACH ROW EXECUTE FUNCTION public.ceo_exigir_instrumento_quando_assinavel();

COMMENT ON FUNCTION public.ceo_exigir_instrumento_quando_assinavel() IS
  'Torna o instrumento obrigatorio no instante em que existir modelo assinavel '
  'para a condicao de fidelidade do pedido, e amarra o pedido ao modelo daquela '
  'condicao. Sem modelo assinavel, nao exige nada e nao reescreve historico.';

-- ---------------------------------------------------------------------------
-- 6. CONSTRUTOR DO SNAPSHOT INDIVIDUALIZADO
--
-- Monta os fatos materiais daquele pedido a partir das FONTES CANÔNICAS do
-- Site, calcula o hash sobre a serialização canônica e falha fechado nomeando
-- qualquer fato material ausente.
--
-- A FUNÇÃO NÃO INFERE NADA. Três fatos exigidos pela minuta não têm fonte
-- canônica no Site hoje — auditado coluna por coluna:
--
--   nfse_taker_cnpj ....... não existe coluna de tomador de NFS-e em tabela
--                           alguma do schema;
--   activity_description .. não existe coluna de atividade, ramo ou CNAE;
--   activity_location ..... site_partner_units dá localização, mas uma empresa
--                           pode ter várias unidades e nada no schema diz qual
--                           é a do instrumento;
--   participation_value_cents — os R$ 141,99 existem no TEXTO do Acordo Mestre
--                           (cláusula 6.2) e não como dado; o divisor de sete
--                           participações só existe como constante de front
--                           (STAGE_COUNT). Derivar aqui seria inferir.
--
-- Por isso esses fatos só podem chegar por `p_facts_supplied`, com proveniência
-- registrada como `caller_supplied` no próprio snapshot. Em produção nada os
-- supre, então o caminho real falha fechado — que é o comportamento desejado
-- enquanto não houver instrumento assinável. Em QA a fixture os supre
-- explicitamente, e o snapshot deixa visível que não eram canônicos.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot(
  p_order_id       uuid,
  p_template_id    uuid,
  p_facts_supplied jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o      public.commercial_exclusivity_orders%ROWTYPE;
  v_c      public.site_partner_companies%ROWTYPE;
  v_a      public.commercial_master_agreements%ROWTYPE;
  v_rep    public.partner_application_representatives%ROWTYPE;
  v_ace    public.legal_acceptances%ROWTYPE;
  v_t      public.commercial_instrument_templates%ROWTYPE;
  v_snap   jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_faltam text[] := ARRAY[]::text[];
  v_campo  text;
  -- Fatos sem fonte canonica no Site: so podem vir do chamador.
  c_sem_fonte constant text[] := ARRAY[
    'nfse_taker_cnpj','activity_description','activity_location',
    'participation_value_cents'];
BEGIN
  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE id = p_template_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_unavailable');
  END IF;
  -- Modelo em rascunho nunca individualiza instrumento para assinatura.
  IF v_t.lifecycle_status <> 'signable' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_not_signable',
      'lifecycle_status', v_t.lifecycle_status,
      'template_code', v_t.template_code);
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  -- A condicao de fidelidade do pedido tem de casar com o escopo do modelo: a
  -- minuta de primeira compra nao fidelizada nao rege pedido fidelizado.
  IF coalesce(v_o.fidelized, false) <> v_t.applies_to_fidelized THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_fidelity_mismatch',
      'order_fidelized', coalesce(v_o.fidelized, false),
      'template_applies_to_fidelized', v_t.applies_to_fidelized);
  END IF;

  -- OUTROS segue dormente: nicho fora do catalogo canonico nao individualiza
  -- instrumento, mesmo que o papel admita a opcao.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_niches n
                  WHERE n.code = v_o.niche_code AND n.is_active) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_niche_not_canonical',
      'niche_code', v_o.niche_code,
      'allows_outros_niche', v_t.allows_outros_niche);
  END IF;

  SELECT * INTO v_c FROM public.site_partner_companies WHERE id = v_o.company_id;
  SELECT * INTO v_a FROM public.commercial_master_agreements
   WHERE id = v_o.master_agreement_id;
  SELECT * INTO v_rep FROM public.partner_application_representatives
   WHERE application_id = v_c.source_application_id AND is_current;
  IF v_o.legal_acceptance_id IS NOT NULL THEN
    SELECT * INTO v_ace FROM public.legal_acceptances WHERE id = v_o.legal_acceptance_id;
  END IF;

  -- Fatos de FONTE CANONICA.
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
    'acceptance_actor_id', coalesce(v_ace.linked_auth_user_id, v_o.registered_by),
    'acceptance_at', coalesce(v_ace.accepted_at, v_o.signed_at)));

  SELECT pg_catalog.jsonb_object_agg(k, 'site_canonical')
    INTO v_prov
    FROM pg_catalog.jsonb_object_keys(v_snap) AS k;
  v_prov := coalesce(v_prov, '{}'::jsonb);

  -- Fatos SEM fonte canonica: somente do chamador, com proveniencia explicita.
  FOREACH v_campo IN ARRAY c_sem_fonte LOOP
    IF p_facts_supplied ? v_campo
       AND pg_catalog.jsonb_typeof(p_facts_supplied -> v_campo) <> 'null' THEN
      v_snap := v_snap || pg_catalog.jsonb_build_object(
                            v_campo, p_facts_supplied -> v_campo);
      v_prov := v_prov || pg_catalog.jsonb_build_object(v_campo, 'caller_supplied');
    END IF;
  END LOOP;

  -- Falha fechada nomeando CADA fato material ausente.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_snap ? v_campo) THEN
      v_faltam := v_faltam || v_campo;
    END IF;
  END LOOP;
  IF array_length(v_faltam, 1) >= 1 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false,
      'reason', 'instrument_snapshot_material_fact_missing',
      'missing_fields', pg_catalog.to_jsonb(v_faltam),
      'template_code', v_t.template_code);
  END IF;

  -- Identidade do MODELO vai dentro do snapshot, e a proveniencia ao lado. O
  -- hash e calculado sobre a forma canonica do jsonb: chaves ordenadas,
  -- duplicatas eliminadas, logo determinista para os mesmos fatos.
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
      pg_catalog.encode(
        extensions.digest(v_snap::text, 'sha256'), 'hex'));
END;
$function$;

ALTER FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid, jsonb) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid, jsonb) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid, jsonb)
  TO service_role;

COMMENT ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid, jsonb) IS
  'Monta o snapshot individualizado do instrumento a partir das fontes '
  'canonicas do Site e calcula o hash sobre a forma canonica do jsonb. NAO '
  'infere: fato material ausente faz falhar fechado com missing_fields. Os '
  'quatro fatos sem fonte canonica (tomador de NFS-e, atividade, localizacao e '
  'valor da participacao) so chegam por p_facts_supplied, com proveniencia '
  'caller_supplied registrada no snapshot.';
