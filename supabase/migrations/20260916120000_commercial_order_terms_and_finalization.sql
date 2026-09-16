-- ============================================================================
-- CONTRATO COMERCIAL DO PEDIDO: publicação, aceite eletrônico e finalização
--
-- Fecha a ponte que faltava entre a reserva de 30 minutos (migration 32) e o
-- provedor de pagamento, que continua NÃO implementado:
--
--   draft (reservado)  ->  awaiting_contract
--                      ->  aceite do titular sobre os termos publicados
--                      ->  pedido criado do instantâneo imutável da intenção
--                      ->  awaiting_payment_provider
--
-- O QUE ESTA MIGRATION NÃO FAZ
-- Não escreve texto jurídico. Cria o TIPO `commercial_order_terms` e o
-- caminho de publicação, mas nenhum documento nasce daqui: sem uma versão
-- publicada de verdade, com conteúdo e hash fornecidos por quem responde
-- juridicamente, o aceite falha fechado com `terms_not_published`. A
-- infraestrutura existir não ativa nada.
--
-- Não fabrica acordo mestre. `admin_register_master_agreement` continua sendo
-- o único caminho, continua exigindo admin, e `master_agreement_missing`
-- continua barrando a finalização. A assinatura do acordo mestre segue
-- externa, como o MVP decidiu.
--
-- O QUE O ACEITE É, E O QUE ELE NÃO É
-- É aceite eletrônico autenticado dentro do Site: titular ativo, logado,
-- sobre a versão vigente exata. NÃO é assinatura ICP-Brasil, não é assinatura
-- eletrônica qualificada e não é certificado digital — e nenhum campo, nome
-- ou comentário aqui sugere que seja.
--
-- ADITIVA. Nenhuma das 32 migrations anteriores é editada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Novo tipo canônico de documento jurídico
--
-- `future_commercial_terms` NÃO é reaproveitado: pelo nome e pela posição no
-- onboarding, ele avisa sobre termos FUTUROS. Usar um aviso como instrumento
-- vinculante de um pedido específico seria inventar semântica jurídica.
--
-- O CHECK da baseline é recriado com o valor novo. Recriar constraint não é
-- editar migration histórica: o arquivo de 2026-08-14 continua byte-idêntico.
-- ----------------------------------------------------------------------------
ALTER TABLE public.legal_documents
  DROP CONSTRAINT legal_documents_type_allowed;

ALTER TABLE public.legal_documents
  ADD CONSTRAINT legal_documents_type_allowed
  CHECK (doc_type = ANY (ARRAY[
    'privacy_notice',
    'provisional_account_terms',
    'truthfulness_declaration',
    'document_analysis_authorization',
    'representation_declaration',
    'future_commercial_terms',
    -- Termos vinculantes de UM pedido de exclusividade comercial.
    'commercial_order_terms']));

-- ----------------------------------------------------------------------------
-- 2. Sujeito de aceite: a intenção de checkout
--
-- Vínculo RELACIONAL explícito, espelhando o padrão de partner_application_id
-- que já existe. Guardar o id da intenção apenas dentro do JSON de evidência
-- deixaria a amarra sem integridade referencial — e é justamente a amarra que
-- a finalização precisa provar.
-- ----------------------------------------------------------------------------
ALTER TABLE public.legal_acceptances
  ADD COLUMN IF NOT EXISTS commercial_checkout_intent_id uuid
    REFERENCES public.commercial_checkout_intents(id);

ALTER TABLE public.legal_acceptances
  DROP CONSTRAINT legal_acceptances_subject_allowed;
ALTER TABLE public.legal_acceptances
  ADD CONSTRAINT legal_acceptances_subject_allowed
  CHECK (subject_type = ANY (ARRAY[
    'auth_user', 'partner_application', 'commercial_checkout_intent']));

ALTER TABLE public.legal_acceptances
  DROP CONSTRAINT legal_acceptances_subject_coerente;
ALTER TABLE public.legal_acceptances
  ADD CONSTRAINT legal_acceptances_subject_coerente
  CHECK (
    (subject_type = 'auth_user'
       AND partner_application_id IS NULL
       AND commercial_checkout_intent_id IS NULL
       AND linked_auth_user_id IS NOT NULL
       AND linked_auth_user_id = subject_id)
    OR (subject_type = 'partner_application'
       AND partner_application_id IS NOT NULL
       AND commercial_checkout_intent_id IS NULL
       AND partner_application_id = subject_id)
    -- A intenção de checkout é o sujeito, e o titular autenticado fica
    -- amarrado em linked_auth_user_id: o aceite responde por QUEM aceitou e
    -- por QUAL contratação, não por um dos dois.
    OR (subject_type = 'commercial_checkout_intent'
       AND partner_application_id IS NULL
       AND commercial_checkout_intent_id IS NOT NULL
       AND commercial_checkout_intent_id = subject_id
       AND linked_auth_user_id IS NOT NULL)
  );

-- ----------------------------------------------------------------------------
-- 3. Publicação de documento jurídico — SOMENTE admin
--
-- O repositório não tinha caminho canônico de publicação: o único INSERT em
-- legal_documents vivia numa fixture de teste. Sem isto, "versão vigente" não
-- teria como existir de forma auditável.
--
-- Não há caminho pelo qual um usuário de navegador publique termos: a função
-- exige admin, e a tabela já tem RLS restrita a `is_site_admin()`.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.admin_publish_legal_document(
  p_doc_type       text,
  p_version        text,
  p_title          text,
  p_content        text,
  p_content_hash   text,
  p_content_url    text DEFAULT NULL,
  p_effective_from timestamptz DEFAULT NULL,
  p_is_material_change boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tipo    text := pg_catalog.btrim(coalesce(p_doc_type, ''));
  v_versao  text := pg_catalog.btrim(coalesce(p_version, ''));
  v_hash    text := pg_catalog.btrim(coalesce(p_content_hash, ''));
  v_desde   timestamptz;
  v_vigente public.legal_documents%ROWTYPE;
  v_id      uuid;
BEGIN
  PERFORM public.m1_exigir_admin();

  -- Allowlist explícita: publicar tipo fora dela seria criar categoria
  -- jurídica por parâmetro.
  IF v_tipo NOT IN ('privacy_notice','provisional_account_terms',
                    'truthfulness_declaration','document_analysis_authorization',
                    'representation_declaration','future_commercial_terms',
                    'commercial_order_terms') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'doc_type_not_allowed');
  END IF;
  IF v_versao = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'version_required');
  END IF;
  IF pg_catalog.btrim(coalesce(p_title,'')) = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'title_required');
  END IF;
  -- Conteúdo OU URL, como o schema já exige para status 'published'.
  IF pg_catalog.btrim(coalesce(p_content,'')) = ''
     AND pg_catalog.btrim(coalesce(p_content_url,'')) = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'content_required');
  END IF;
  IF v_hash = '' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'content_hash_required');
  END IF;

  -- TEMPO DO BANCO. O chamador pode agendar o início, nunca antedatar.
  v_desde := coalesce(p_effective_from, pg_catalog.now());
  IF v_desde < pg_catalog.now() - interval '1 minute' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'effective_from_in_past');
  END IF;

  -- Idempotência: republicar a mesma versão com o mesmo hash não cria linha.
  SELECT * INTO v_vigente FROM public.legal_documents
   WHERE doc_type = v_tipo AND version = v_versao;
  IF FOUND THEN
    IF v_vigente.status = 'published' AND v_vigente.content_hash = v_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
        'legal_document_id', v_vigente.id, 'doc_type', v_tipo,
        'version', v_versao, 'content_hash', v_vigente.content_hash);
    END IF;
    -- Mesma versão com conteúdo DIFERENTE seria reescrever, sob o mesmo
    -- rótulo, um texto que alguém já pode ter aceitado. Versão nova, então.
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'version_already_exists');
  END IF;

  -- A versão anterior vira histórica: o registro é preservado, nunca apagado.
  UPDATE public.legal_documents
     SET effective_to = v_desde, updated_at = pg_catalog.now()
   WHERE doc_type = v_tipo AND status = 'published'
     AND (effective_to IS NULL OR effective_to > v_desde);

  INSERT INTO public.legal_documents
    (doc_type, version, title, content, content_url, content_hash, status,
     is_material_change, effective_from, published_at, published_by)
  VALUES
    (v_tipo, v_versao, pg_catalog.btrim(p_title),
     nullif(pg_catalog.btrim(coalesce(p_content,'')), ''),
     nullif(pg_catalog.btrim(coalesce(p_content_url,'')), ''),
     v_hash, 'published', coalesce(p_is_material_change, false),
     v_desde, pg_catalog.now(), auth.uid())
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('legal_document.published', v_id, 'admin',
    pg_catalog.jsonb_build_object('doc_type', v_tipo, 'version', v_versao,
                                  'content_hash', v_hash));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'legal_document_id', v_id, 'doc_type', v_tipo, 'version', v_versao,
    'content_hash', v_hash, 'effective_from', v_desde);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_publish_legal_document(
  text,text,text,text,text,text,timestamptz,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_publish_legal_document(
  text,text,text,text,text,text,timestamptz,boolean) FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_publish_legal_document(
  text,text,text,text,text,text,timestamptz,boolean) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Vínculo do aceite ao pedido
--
-- FK explícita: a finalização prova a amarra pelo catálogo, não por JSON.
-- ----------------------------------------------------------------------------
ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN IF NOT EXISTS legal_acceptance_id uuid
    REFERENCES public.legal_acceptances(id),
  ADD COLUMN IF NOT EXISTS checkout_intent_id uuid
    REFERENCES public.commercial_checkout_intents(id);

CREATE UNIQUE INDEX IF NOT EXISTS ceo_intencao_unica_idx
  ON public.commercial_exclusivity_orders (checkout_intent_id)
  WHERE checkout_intent_id IS NOT NULL AND status <> 'cancelled';

-- ----------------------------------------------------------------------------
-- 5. draft -> awaiting_contract
--
-- Operação de servidor explícita. Não muda dinheiro, não estende reserva.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.advance_checkout_intent_to_contract(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_i public.commercial_checkout_intents%ROWTYPE;
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
  IF v_i.status = 'awaiting_contract' THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'status', v_i.status, 'reserved_until', v_i.reserved_until);
  END IF;
  -- Intenção cancelada NÃO ressuscita.
  IF v_i.status <> 'draft' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_draft',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
  END IF;

  UPDATE public.commercial_checkout_intents
     SET status = 'awaiting_contract' WHERE id = v_i.id;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'status', 'awaiting_contract', 'reserved_until', v_i.reserved_until);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.advance_checkout_intent_to_contract(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.advance_checkout_intent_to_contract(uuid)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.advance_checkout_intent_to_contract(uuid)
  TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Aceite eletrônico dos termos do pedido
--
-- O chamador manda UM identificador: qual intenção. Documento, versão, hash,
-- instante, identidade e empresa são todos resolvidos no servidor — nada
-- disso é aceito como parâmetro, porque nada disso pode vir de quem aceita.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.accept_commercial_order_terms(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_i   public.commercial_checkout_intents%ROWTYPE;
  v_doc public.legal_documents%ROWTYPE;
  v_ace public.legal_acceptances%ROWTYPE;
  v_ip  inet;
  v_ua  text;
  v_id  uuid;
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
  IF v_i.status <> 'awaiting_contract' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_awaiting_contract',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
  END IF;

  -- VERSÃO VIGENTE, resolvida no servidor. Sem documento publicado, o fluxo
  -- para aqui — que é o comportamento desejado enquanto o texto jurídico não
  -- existir.
  SELECT * INTO v_doc FROM public.legal_documents d
   WHERE d.doc_type = 'commercial_order_terms'
     AND d.status = 'published'
     AND d.effective_from <= pg_catalog.now()
     AND (d.effective_to IS NULL OR d.effective_to > pg_catalog.now())
   ORDER BY d.effective_from DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'terms_not_published');
  END IF;

  -- Idempotência: aceite vivo do MESMO documento para a MESMA intenção é
  -- devolvido como está. `uq_legal_acceptances_ativo` garante a unicidade.
  SELECT * INTO v_ace FROM public.legal_acceptances a
   WHERE a.subject_type = 'commercial_checkout_intent'
     AND a.subject_id = v_i.id
     AND a.legal_document_id = v_doc.id
     AND a.context = 'commercial_contract'
     AND a.revoked_at IS NULL;
  IF FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'already', true,
      'acceptance_id', v_ace.id, 'legal_document_id', v_doc.id,
      'doc_type', v_doc.doc_type, 'version', v_doc.version,
      'content_hash', v_doc.content_hash, 'accepted_at', v_ace.accepted_at);
  END IF;

  -- Evidência de rede quando o gateway a repassa; ausência não invalida o
  -- aceite, e inventar um valor seria pior que não ter.
  BEGIN
    v_ip := nullif(pg_catalog.btrim(
      coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', '')), '')::inet;
  EXCEPTION WHEN others THEN v_ip := NULL;
  END;
  BEGIN
    v_ua := nullif(pg_catalog.btrim(
      coalesce(current_setting('request.headers', true)::jsonb ->> 'user-agent', '')), '');
  EXCEPTION WHEN others THEN v_ua := NULL;
  END;

  INSERT INTO public.legal_acceptances
    (subject_type, subject_id, linked_auth_user_id, auth_user_id,
     commercial_checkout_intent_id, legal_document_id, context, origin,
     ip, user_agent, evidence)
  VALUES
    ('commercial_checkout_intent', v_i.id, v_uid, v_uid,
     v_i.id, v_doc.id, 'commercial_contract', 'server',
     v_ip, v_ua,
     -- A evidência JSON é leitura humana; a AUTORIDADE são as colunas e as
     -- chaves estrangeiras acima.
     pg_catalog.jsonb_build_object(
       'company_id', v_i.company_id,
       'niche_code', v_i.niche_code,
       'opportunity_id', v_i.opportunity_id,
       'document_version', v_doc.version,
       'content_hash', v_doc.content_hash,
       'acceptance_kind', 'authenticated_electronic_acceptance'))
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('commercial_order_terms.accepted', v_id, 'owner',
    pg_catalog.jsonb_build_object('intent_id', v_i.id,
                                  'legal_document_id', v_doc.id,
                                  'version', v_doc.version));

  SELECT * INTO v_ace FROM public.legal_acceptances WHERE id = v_id;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'already', false,
    'acceptance_id', v_ace.id, 'legal_document_id', v_doc.id,
    'doc_type', v_doc.doc_type, 'version', v_doc.version,
    'content_hash', v_doc.content_hash, 'accepted_at', v_ace.accepted_at);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.accept_commercial_order_terms(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.accept_commercial_order_terms(uuid)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.accept_commercial_order_terms(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. Finalização: pedido a partir do instantâneo imutável da intenção
--
-- Nenhum valor monetário é recalculado e nenhum vem do chamador: cada centavo
-- é COPIADO da intenção reservada. Recalcular abriria a porta para o preço
-- mudar entre a reserva e a contratação, que é exatamente o que a reserva
-- existe para impedir.
--
-- Os campos legados de assinatura são derivados de registros canônicos:
--   signed_at          <- legal_acceptances.accepted_at
--   signatory_name     <- site_company_members.full_name do titular
--   document_hash      <- legal_documents.content_hash
--   document_reference <- referência canônica ao aceite
--   order_version      <- versão do documento aceito
-- Nenhum deles recebe string arbitrária do navegador.
-- ----------------------------------------------------------------------------
CREATE FUNCTION public.finalize_commercial_order_from_intent(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
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

  IF v_i.status <> 'awaiting_contract' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'intent_not_awaiting_contract',
                                         'status', v_i.status);
  END IF;
  IF v_i.reserved_until IS NULL OR v_i.reserved_until <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reservation_expired');
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
  SELECT * INTO v_agree FROM public.commercial_master_agreements
   WHERE company_id = v_i.company_id AND status = 'signed';
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

  SELECT * INTO v_comp FROM public.site_partner_companies WHERE id = v_i.company_id;

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
     benefit_settlement_mode, cash_user_pool_funding_cents,
     total_monetary_funding_required_cents, benefit_distribution_policy_version,
     order_version, document_reference, document_hash, signed_at, signatory_name,
     status, expected_operation_start, registered_by,
     legal_acceptance_id, checkout_intent_id)
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
     v_i.benefit_settlement_mode, v_i.cash_user_pool_funding_cents,
     v_i.total_monetary_funding_required_cents,
     v_i.benefit_distribution_policy_version,
     v_doc.version,
     'bdflow:legal_acceptance/' || v_ace.id::text,
     v_doc.content_hash,
     v_ace.accepted_at, v_nome,
     'signed', (pg_catalog.now() + interval '30 days')::date, v_uid,
     v_ace.id, v_i.id)
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
  ON CONFLICT (cnpj, uf, city_key, niche_code) DO NOTHING;

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
$$;

REVOKE EXECUTE ON FUNCTION public.finalize_commercial_order_from_intent(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.finalize_commercial_order_from_intent(uuid)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.finalize_commercial_order_from_intent(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.accept_commercial_order_terms(uuid) IS
  'Aceite eletronico AUTENTICADO dos termos vigentes do pedido comercial pelo '
  'titular ativo. NAO e assinatura ICP-Brasil, nem assinatura eletronica '
  'qualificada, nem certificado digital. Documento, versao, hash, instante e '
  'identidade sao resolvidos no servidor; o cliente envia apenas qual intencao.';
