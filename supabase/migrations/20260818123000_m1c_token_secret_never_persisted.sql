-- ===========================================================================
-- M1-C4 — O SEGREDO DO TOKEN NUNCA É PERSISTIDO (checkpoint de segurança)
-- ===========================================================================
-- DEFEITO CORRIGIDO
-- O desenho anterior colocava o segredo BRUTO em
-- notification_events.template_data para que o worker de e-mail o
-- entregasse. Isso persistia o segredo em claro numa tabela — verificável
-- por: sha256(template_data->>'token') == partner_application_tokens.token_hash.
-- Violava a regra SOMENTE_HASH_PERSISTIDO.
--
-- DESENHO NOVO — cunhagem no envio ("mint at send")
--   1. As RPCs públicas apenas ENFILEIRAM a instrução: template_data leva
--      application_id e purpose, jamais um segredo.
--   2. O worker de e-mail (service_role) chama
--      svc_mint_partner_application_token(notification_id): ela gera o
--      segredo, persiste SOMENTE o hash e DEVOLVE o bruto na resposta.
--   3. O bruto existe apenas em trânsito (retorno da função → worker →
--      corpo do e-mail). Nenhuma tabela, outbox, auditoria ou log o recebe.
--   4. Se o envio falhar, nada foi consumido; a retentativa cunha um token
--      novo, que invalida o anterior — single-use preservado.
--
-- Invariante de banco impede a regressão: nenhuma notificação de
-- partner_application pode conter a chave 'token' no payload.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Invariante estrutural
-- ---------------------------------------------------------------------------
ALTER TABLE public.notification_events
  ADD CONSTRAINT notification_events_sem_segredo_partner
    CHECK (
      correlation_entity_type IS DISTINCT FROM 'partner_application'
      OR NOT (template_data ? 'token')
    );

-- ---------------------------------------------------------------------------
-- 2. Enfileiramento sem segredo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.m1_enfileirar_email(
  p_address        text,
  p_template_key   text,
  p_template_data  jsonb,
  p_application_id uuid,
  p_idempotency    text
)
RETURNS void
LANGUAGE plpgsql VOLATILE
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  -- Defesa em profundidade: mesmo que alguém volte a passar um segredo,
  -- a função recusa antes de tocar a tabela.
  IF p_template_data ? 'token' OR p_template_data ? 'secret' THEN
    RAISE EXCEPTION 'segredo nao pode ser enfileirado (template=%)', p_template_key
      USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.notification_events
    (channel, recipient_address, template_key, template_data,
     idempotency_key, correlation_entity_type, correlation_entity_id)
  VALUES
    ('email', p_address, p_template_key, p_template_data,
     p_idempotency, 'partner_application', p_application_id::text)
  ON CONFLICT (channel, idempotency_key) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_enfileirar_email(text, text, jsonb, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_enfileirar_email(text, text, jsonb, uuid, text) FROM service_role;

-- ---------------------------------------------------------------------------
-- 3. Cunhagem no envio — exclusiva do worker (service_role)
-- ---------------------------------------------------------------------------
-- Lease de entrega: janela em que uma notificação em 'sending' é considerada
-- em posse de um worker vivo. Depois disso, outra tentativa é legítima.
CREATE FUNCTION public.m1_mint_lease()
RETURNS interval
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT interval '5 minutes';
$$;

REVOKE EXECUTE ON FUNCTION public.m1_mint_lease() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_mint_lease() FROM service_role;

-- Teto de tentativas: evita reenvio infinito de uma instrução defeituosa.
CREATE FUNCTION public.m1_mint_max_tentativas()
RETURNS integer
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT 5;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_mint_max_tentativas() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_mint_max_tentativas() FROM service_role;

CREATE FUNCTION public.svc_mint_partner_application_token(p_notification_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_evt     public.notification_events%ROWTYPE;
  v_app     public.partner_applications%ROWTYPE;
  v_purpose text;
  v_ttl     interval;
  v_segredo text;
BEGIN
  SELECT * INTO v_evt
    FROM public.notification_events
   WHERE id = p_notification_id
   FOR UPDATE;

  IF NOT FOUND OR v_evt.correlation_entity_type IS DISTINCT FROM 'partner_application' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- SERIALIZAÇÃO: o FOR UPDATE acima é o ponto de serialização. Uma segunda
  -- tentativa concorrente bloqueia ali e, ao prosseguir, relê a linha já em
  -- 'sending' com updated_at recente.
  --
  -- Três desfechos distintos, de propósito — o worker precisa saber o que
  -- fazer em cada um:
  --   lease_held        -> outro worker está com a entrega; tente depois
  --   not_dispatchable  -> a notificação não é elegível; não insista
  --   max_attempts      -> desistimos; exige nova instrução de envio
  IF v_evt.status = 'sending'
     AND v_evt.updated_at > pg_catalog.now() - public.m1_mint_lease() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'lease_held');
  END IF;

  -- Elegível: 'pending'; 'scheduled' cuja hora chegou; ou 'sending' com
  -- lease vencido (worker presumido morto). Recunhar é seguro porque cada
  -- cunhagem invalida o token anterior do mesmo propósito.
  IF v_evt.status = 'scheduled'
     AND (v_evt.scheduled_for IS NULL OR v_evt.scheduled_for > pg_catalog.now()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_due_yet');
  END IF;

  IF v_evt.status NOT IN ('pending','scheduled','sending') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- Lease vencido: a máquina de estados da baseline não admite
  -- sending -> sending nem sending -> pending. O caminho legítimo, quando
  -- não houve envio externo, é sending -> failed -> scheduled no PRÓPRIO
  -- evento. Fazemos essa recuperação aqui antes de recunhar.
  IF v_evt.status = 'sending' THEN
    UPDATE public.notification_events
       SET status          = 'failed',
           first_failed_at = coalesce(first_failed_at, pg_catalog.now()),
           last_failed_at  = pg_catalog.now(),
           error_code      = 'lease_expired'
     WHERE id = v_evt.id;
    UPDATE public.notification_events
       SET status        = 'scheduled',
           scheduled_for = pg_catalog.now()
     WHERE id = v_evt.id;
  END IF;

  IF v_evt.attempt_count >= public.m1_mint_max_tentativas() THEN
    UPDATE public.notification_events
       SET status          = 'failed',
           first_failed_at = coalesce(first_failed_at, pg_catalog.now()),
           last_failed_at  = pg_catalog.now(),
           error_code      = 'max_attempts',
           updated_at      = pg_catalog.now()
     WHERE id = v_evt.id;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'max_attempts');
  END IF;

  v_purpose := v_evt.template_data->>'purpose';
  IF v_purpose NOT IN ('email_verification','account_claim') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'no_token_needed');
  END IF;

  SELECT * INTO v_app
    FROM public.partner_applications
   WHERE id = (v_evt.template_data->>'application_id')::uuid
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_dispatchable');
  END IF;

  -- O propósito precisa continuar coerente com o estado atual: um envio
  -- atrasado não ressuscita etapa já vencida.
  IF (v_purpose = 'email_verification' AND v_app.status <> 'pending_email_verification')
     OR (v_purpose = 'account_claim'   AND v_app.status <> 'pending_account_setup') THEN
    UPDATE public.notification_events
       SET status = 'cancelled', updated_at = pg_catalog.now()
     WHERE id = v_evt.id;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'stale_for_state');
  END IF;

  v_ttl := CASE v_purpose
             WHEN 'email_verification' THEN interval '24 hours'
             ELSE interval '30 minutes'
           END;

  -- Gera e persiste SOMENTE o hash. O bruto sai apenas no retorno.
  v_segredo := public.m1_emitir_token(v_app.id, v_purpose, v_app.contact_email, v_ttl);

  UPDATE public.notification_events
     SET status        = 'sending',
         attempt_count = attempt_count + 1,
         updated_at    = pg_catalog.now()
   WHERE id = v_evt.id;

  -- Auditoria SEM segredo.
  PERFORM public.m1_auditar('partner_application.token_minted', v_app.id, 'system',
                            pg_catalog.jsonb_build_object('purpose', v_purpose,
                                                          'notification_id', v_evt.id));

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'application_id', v_app.id,
    'purpose', v_purpose,
    'recipient', v_app.contact_email,
    'token', v_segredo,
    'attempt', v_evt.attempt_count + 1,
    'expires_in_seconds', (extract(epoch FROM v_ttl))::bigint);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.svc_mint_partner_application_token(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.svc_mint_partner_application_token(uuid) TO service_role;

COMMENT ON FUNCTION public.svc_mint_partner_application_token(uuid) IS
  'Cunha o segredo no momento do envio e devolve o bruto APENAS no retorno. Persiste somente o hash. Exclusiva do worker service_role.';

CREATE FUNCTION public.svc_mark_notification_sent(
  p_notification_id     uuid,
  p_provider            text DEFAULT NULL,
  p_provider_message_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  UPDATE public.notification_events
     SET status              = 'sent',
         sent_at             = pg_catalog.now(),
         provider            = p_provider,
         provider_message_id = p_provider_message_id,
         updated_at          = pg_catalog.now()
   WHERE id = p_notification_id
     AND status = 'sending';

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_sending');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.svc_mark_notification_sent(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.svc_mark_notification_sent(uuid, text, text) TO service_role;

-- Falha explícita do worker: devolve a notificação para 'pending', de modo
-- que a retentativa não precisa esperar o lease. O token já cunhado
-- continua válido até ser invalidado pela próxima cunhagem.
-- Falha do worker. Respeita a máquina de estados da baseline:
-- sending -> failed é permitido; sending -> pending NÃO é.
CREATE FUNCTION public.svc_mark_notification_failed(
  p_notification_id uuid,
  p_error_code      text DEFAULT NULL,
  p_error_message   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  UPDATE public.notification_events
     SET status          = 'failed',
         first_failed_at = coalesce(first_failed_at, pg_catalog.now()),
         last_failed_at  = pg_catalog.now(),
         error_code      = pg_catalog.left(coalesce(p_error_code,'send_failed'), 100),
         error_message   = pg_catalog.left(p_error_message, 2000)
   WHERE id = p_notification_id
     AND status = 'sending';

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_sending');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'failed');
END;
$$;

-- Reagenda o MESMO evento (failed -> scheduled), que é o caminho prescrito
-- pela baseline quando a falha ocorreu antes de qualquer envio externo.
CREATE FUNCTION public.svc_reschedule_notification(
  p_notification_id uuid,
  p_delay           interval DEFAULT interval '1 minute'
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_att integer;
BEGIN
  SELECT attempt_count INTO v_att
    FROM public.notification_events
   WHERE id = p_notification_id AND status = 'failed'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_failed');
  END IF;

  IF v_att >= public.m1_mint_max_tentativas() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'max_attempts');
  END IF;

  UPDATE public.notification_events
     SET status = 'scheduled', scheduled_for = pg_catalog.now() + p_delay
   WHERE id = p_notification_id;

  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'scheduled');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.svc_reschedule_notification(uuid, interval) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.svc_reschedule_notification(uuid, interval) TO service_role;

REVOKE EXECUTE ON FUNCTION public.svc_mark_notification_failed(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.svc_mark_notification_failed(uuid, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. RPCs públicas: enfileiram instrução, não segredo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_partner_application(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_cnpj      text;
  v_cpf       text;
  v_email     text;
  v_rep_email text;
  v_app_id    uuid;
BEGIN
  IF p_payload IS NULL OR pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  END IF;

  v_cnpj      := pg_catalog.regexp_replace(coalesce(p_payload->>'cnpj',''), '[^0-9]', '', 'g');
  v_cpf       := pg_catalog.regexp_replace(coalesce(p_payload->>'representative_cpf',''), '[^0-9]', '', 'g');
  v_email     := pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'contact_email','')));
  v_rep_email := pg_catalog.lower(pg_catalog.btrim(coalesce(p_payload->>'representative_email', v_email)));

  IF NOT public.m1_cnpj_valido(v_cnpj) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_cnpj');
  END IF;
  IF NOT public.m1_cpf_valido(v_cpf) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_cpf');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.partner_applications a
     WHERE a.cnpj = v_cnpj
       AND a.status IN ('pending_email_verification','pending_account_setup',
                        'under_review','changes_requested')
  ) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'application_in_progress');
  END IF;

  BEGIN
    INSERT INTO public.partner_applications
      (cnpj, legal_name, trade_name, contact_email, contact_phone,
       postal_code, street, street_number, complement, district, city, uf)
    VALUES
      (v_cnpj,
       pg_catalog.btrim(p_payload->>'legal_name'),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'trade_name','')), ''),
       v_email,
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'contact_phone',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'postal_code',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'street','')), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'street_number','')), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'complement','')), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'district','')), ''),
       pg_catalog.btrim(p_payload->>'city'),
       pg_catalog.upper(pg_catalog.btrim(coalesce(p_payload->>'uf',''))))
    RETURNING id INTO v_app_id;

    INSERT INTO public.partner_application_representatives
      (application_id, full_name, cpf, email, phone, role_title)
    VALUES
      (v_app_id,
       pg_catalog.btrim(p_payload->>'representative_full_name'),
       v_cpf, v_rep_email,
       nullif(pg_catalog.regexp_replace(coalesce(p_payload->>'representative_phone',''), '[^0-9]', '', 'g'), ''),
       nullif(pg_catalog.btrim(coalesce(p_payload->>'representative_role_title','')), ''));

    PERFORM public.m1_registrar_aceites_preauth(
      v_app_id, pg_catalog.jsonb_build_object('collected_at', pg_catalog.now()));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'legal_document_unavailable');
    WHEN check_violation OR not_null_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_data');
    WHEN unique_violation THEN
      RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'application_in_progress');
  END;

  -- Instrução de envio. NENHUM segredo aqui: o worker cunha no envio.
  PERFORM public.m1_enfileirar_email(
    v_email, 'partner_application_email_verification',
    pg_catalog.jsonb_build_object('application_id', v_app_id, 'purpose', 'email_verification'),
    v_app_id,
    'pav:' || v_app_id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));

  PERFORM public.m1_auditar('partner_application.created', v_app_id, 'anon',
                            pg_catalog.jsonb_build_object('status','pending_email_verification'));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app_id,
                                       'status', 'pending_email_verification');
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_partner_application_email(p_token text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_tok   public.partner_application_tokens%ROWTYPE;
  v_app   public.partner_applications%ROWTYPE;
  v_claim text;
BEGIN
  IF p_token IS NULL OR pg_catalog.length(pg_catalog.btrim(p_token)) = 0 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;

  SELECT * INTO v_tok
    FROM public.partner_application_tokens
   WHERE token_hash = public.m1_token_hash(p_token)
     AND purpose    = 'email_verification'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_token');
  END IF;
  IF v_tok.consumed_at    IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_already_used');
  END IF;
  IF v_tok.invalidated_at IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_invalidated');
  END IF;
  IF v_tok.expires_at <= pg_catalog.now() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'token_expired');
  END IF;

  SELECT * INTO v_app FROM public.partner_applications WHERE id = v_tok.application_id FOR UPDATE;

  UPDATE public.partner_application_tokens SET consumed_at = pg_catalog.now() WHERE id = v_tok.id;

  IF v_app.email_verified_at IS NOT NULL THEN
    IF v_app.status = 'pending_account_setup' THEN
      v_claim := public.m1_emitir_token(v_app.id, 'account_claim', v_app.contact_email, interval '30 minutes');
      RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                           'status', v_app.status, 'already_confirmed', true,
                                           'claim_token', v_claim);
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                         'status', v_app.status, 'already_confirmed', true);
  END IF;

  UPDATE public.partner_applications
     SET email_verified_at = pg_catalog.now(),
         status            = 'pending_account_setup'
   WHERE id = v_app.id;

  -- O claim vai em TRÂNSITO na resposta desta chamada. Se a resposta se
  -- perder, a recuperação pública emite outro por e-mail (cunhado no envio).
  v_claim := public.m1_emitir_token(v_app.id, 'account_claim', v_app.contact_email, interval '30 minutes');

  PERFORM public.m1_auditar('partner_application.email_confirmed', v_app.id, 'anon',
                            pg_catalog.jsonb_build_object('status','pending_account_setup'),
                            pg_catalog.jsonb_build_object('status', v_app.status));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'application_id', v_app.id,
                                       'status', 'pending_account_setup',
                                       'already_confirmed', false,
                                       'claim_token', v_claim);
END;
$$;

CREATE OR REPLACE FUNCTION public.request_partner_application_recovery(
  p_cnpj  text,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_cnpj    text;
  v_email   text;
  v_app     public.partner_applications%ROWTYPE;
  v_recente boolean;
BEGIN
  v_cnpj  := pg_catalog.regexp_replace(coalesce(p_cnpj,''), '[^0-9]', '', 'g');
  v_email := pg_catalog.lower(pg_catalog.btrim(coalesce(p_email,'')));

  SELECT * INTO v_app
    FROM public.partner_applications a
   WHERE a.cnpj = v_cnpj
     AND a.contact_email = v_email
     AND a.status IN ('pending_email_verification','pending_account_setup')
   FOR UPDATE;

  IF FOUND THEN
    -- Rate limit agora medido no OUTBOX: com cunhagem no envio, o token só
    -- nasce depois, então contar tokens não conteria abuso.
    SELECT EXISTS (
      SELECT 1 FROM public.notification_events n
       WHERE n.correlation_entity_type = 'partner_application'
         AND n.correlation_entity_id   = v_app.id::text
         AND n.created_at > pg_catalog.now() - interval '1 minute'
    ) INTO v_recente;

    IF NOT v_recente THEN
      PERFORM public.m1_enfileirar_email(
        v_app.contact_email,
        CASE WHEN v_app.status = 'pending_email_verification'
             THEN 'partner_application_email_verification'
             ELSE 'partner_application_account_claim' END,
        pg_catalog.jsonb_build_object(
          'application_id', v_app.id,
          'purpose', CASE WHEN v_app.status = 'pending_email_verification'
                          THEN 'email_verification' ELSE 'account_claim' END),
        v_app.id,
        'rec:' || v_app.id::text || ':' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS'));

      PERFORM public.m1_auditar('partner_application.recovery_requested', v_app.id, 'anon',
                                pg_catalog.jsonb_build_object('status', v_app.status));
    END IF;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'message', 'Se houver uma solicitacao ativa para estes dados, enviaremos um e-mail.');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_partner_application(jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_partner_application(jsonb) TO anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.confirm_partner_application_email(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.confirm_partner_application_email(text) TO anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.request_partner_application_recovery(text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.request_partner_application_recovery(text, text) TO anon, authenticated, service_role;
