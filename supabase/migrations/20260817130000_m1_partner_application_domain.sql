-- ===========================================================================
-- M1 — ONBOARDING FASE 2A: DOMÍNIO DA APLICAÇÃO EMPRESARIAL
-- ===========================================================================
-- Cria a solicitação empresarial PRÉ-AUTH e suas entidades de apoio.
--
-- Princípios aplicados:
--   * a solicitação nasce ANTES de existir conta Auth completa;
--   * empresa e autoridade do representante são analisadas separadamente;
--   * CNPJ tem unicidade PARCIAL (apenas estados não terminais), o que
--     preserva histórico e permite reaplicação após decisão terminal;
--   * conta provisória não recebe autoridade de parceiro aprovado;
--   * token de e-mail é persistido SOMENTE como hash;
--   * auditoria reusa public.audit_logs (append-only já existente);
--   * outbox reusa public.notification_events (já existente);
--   * a RPC legada create_my_partner_owner_registration NÃO é usada.
--
-- Grants: nenhuma escrita direta é concedida a anon/authenticated. Toda
-- mutação passa por RPC SECURITY DEFINER com search_path fixo (migration
-- seguinte). O H1 já garante que objetos novos nasçam fail-closed; ainda
-- assim cada grant necessário é declarado explicitamente aqui.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. partner_applications
-- ---------------------------------------------------------------------------
CREATE TABLE public.partner_applications (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identificação empresarial
  cnpj                      text        NOT NULL,
  legal_name                text        NOT NULL,
  trade_name                text,

  -- Contato principal da solicitação
  contact_email             text        NOT NULL,
  contact_phone             text,

  -- Endereço / resolução territorial
  postal_code               text,
  street                    text,
  street_number             text,
  complement                text,
  district                  text,
  city                      text        NOT NULL,
  uf                        text        NOT NULL,

  -- Estado geral da solicitação
  status                    text        NOT NULL DEFAULT 'pending_email_verification',

  -- Análises separadas (empresa != autoridade do representante)
  company_review_status     text        NOT NULL DEFAULT 'pending',
  authority_review_status   text        NOT NULL DEFAULT 'pending',

  -- Confirmação de e-mail pré-Auth
  email_verified_at         timestamptz,

  -- Vínculo posterior com Auth (conta provisória)
  account_kind              text        NOT NULL DEFAULT 'none',
  account_user_id           uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  account_linked_at         timestamptz,

  -- Decisão administrativa
  decided_at                timestamptz,
  decided_by                uuid,
  decision_reason           text,

  -- Reconsideração: 1 vez, prazo de 10 dias
  reconsideration_count     integer     NOT NULL DEFAULT 0,
  reconsideration_deadline  timestamptz,
  reconsidered_by           uuid,

  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT partner_applications_cnpj_formato
    CHECK (cnpj ~ '^[0-9]{14}$'),
  CONSTRAINT partner_applications_legal_name_nonempty
    CHECK (length(btrim(legal_name)) BETWEEN 2 AND 200),
  CONSTRAINT partner_applications_trade_name_tamanho
    CHECK (trade_name IS NULL OR length(btrim(trade_name)) BETWEEN 2 AND 200),
  CONSTRAINT partner_applications_email_formato
    CHECK (contact_email = lower(btrim(contact_email))
           AND contact_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
           AND length(contact_email) <= 320),
  CONSTRAINT partner_applications_phone_formato
    CHECK (contact_phone IS NULL OR contact_phone ~ '^[0-9]{10,13}$'),
  CONSTRAINT partner_applications_postal_code_formato
    CHECK (postal_code IS NULL OR postal_code ~ '^[0-9]{8}$'),
  CONSTRAINT partner_applications_city_nonempty
    CHECK (length(btrim(city)) BETWEEN 2 AND 120),
  CONSTRAINT partner_applications_uf_valida
    CHECK (public.commercial_is_valid_uf(uf)),
  CONSTRAINT partner_applications_status_allowed
    CHECK (status = ANY (ARRAY[
      'pending_email_verification',
      'under_review',
      'changes_requested',
      'approved',
      'rejected',
      'withdrawn'
    ])),
  CONSTRAINT partner_applications_company_review_allowed
    CHECK (company_review_status = ANY (ARRAY['pending','approved','rejected','changes_requested'])),
  CONSTRAINT partner_applications_authority_review_allowed
    CHECK (authority_review_status = ANY (ARRAY['pending','approved','rejected','changes_requested'])),
  -- Coerência entre confirmação de e-mail e estado
  CONSTRAINT partner_applications_email_verificado_coerente
    CHECK ((status = 'pending_email_verification') = (email_verified_at IS NULL)),
  -- Conta provisória só existe com usuário Auth vinculado
  CONSTRAINT partner_applications_account_kind_allowed
    CHECK (account_kind = ANY (ARRAY['none','provisional'])),
  CONSTRAINT partner_applications_account_coerente
    CHECK ((account_kind = 'provisional')
           = (account_user_id IS NOT NULL AND account_linked_at IS NOT NULL)),
  -- Conta só pode ser vinculada após confirmação de e-mail
  CONSTRAINT partner_applications_account_exige_email
    CHECK (account_user_id IS NULL OR email_verified_at IS NOT NULL),
  -- Decisão terminal exige carimbo
  CONSTRAINT partner_applications_decisao_coerente
    CHECK ((status IN ('approved','rejected')) = (decided_at IS NOT NULL)),
  CONSTRAINT partner_applications_decision_reason_tamanho
    CHECK (decision_reason IS NULL OR length(btrim(decision_reason)) BETWEEN 3 AND 2000),
  -- Reconsideração: no máximo uma
  CONSTRAINT partner_applications_reconsideracao_limite
    CHECK (reconsideration_count BETWEEN 0 AND 1),
  CONSTRAINT partner_applications_reconsideracao_coerente
    CHECK ((reconsideration_count = 0) = (reconsideration_deadline IS NULL)),
  CONSTRAINT partner_applications_timestamps
    CHECK (updated_at >= created_at)
);

COMMENT ON TABLE public.partner_applications IS
  'Solicitação empresarial de parceria (Fase 2A). Nasce pré-Auth; empresa e autoridade do representante são analisadas separadamente.';

-- Unicidade PARCIAL de CNPJ: apenas uma aplicação NÃO TERMINAL por CNPJ.
-- Estados terminais (approved/rejected/withdrawn) ficam de fora, preservando
-- histórico e permitindo reaplicação quando aplicável.
CREATE UNIQUE INDEX partner_applications_cnpj_nao_terminal_uk
  ON public.partner_applications (cnpj)
  WHERE status IN ('pending_email_verification','under_review','changes_requested');

-- Uma conta Auth provisória serve a no máximo uma aplicação viva.
CREATE UNIQUE INDEX partner_applications_account_user_uk
  ON public.partner_applications (account_user_id)
  WHERE account_user_id IS NOT NULL;

CREATE INDEX partner_applications_status_idx     ON public.partner_applications (status, created_at DESC);
CREATE INDEX partner_applications_uf_city_idx    ON public.partner_applications (uf, city);
CREATE INDEX partner_applications_created_at_idx ON public.partner_applications (created_at DESC);

CREATE TRIGGER trg_partner_applications_touch
  BEFORE UPDATE ON public.partner_applications
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ---------------------------------------------------------------------------
-- 2. partner_application_representatives
-- ---------------------------------------------------------------------------
-- A autoridade do representante é analisada à parte da empresa. Rejeitar o
-- representante NÃO rejeita a empresa: basta indicar outro representante,
-- sem criar nova aplicação empresarial.
CREATE TABLE public.partner_application_representatives (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id    uuid        NOT NULL REFERENCES public.partner_applications(id) ON DELETE CASCADE,
  full_name         text        NOT NULL,
  cpf               text        NOT NULL,
  email             text        NOT NULL,
  phone             text,
  role_title        text,
  authority_status  text        NOT NULL DEFAULT 'pending',
  is_current        boolean     NOT NULL DEFAULT true,
  decision_reason   text,
  decided_at        timestamptz,
  decided_by        uuid,
  replaced_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT par_full_name_nonempty CHECK (length(btrim(full_name)) BETWEEN 3 AND 200),
  CONSTRAINT par_cpf_formato        CHECK (cpf ~ '^[0-9]{11}$'),
  CONSTRAINT par_email_formato
    CHECK (email = lower(btrim(email))
           AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
           AND length(email) <= 320),
  CONSTRAINT par_phone_formato      CHECK (phone IS NULL OR phone ~ '^[0-9]{10,13}$'),
  CONSTRAINT par_authority_allowed
    CHECK (authority_status = ANY (ARRAY['pending','approved','rejected','changes_requested'])),
  CONSTRAINT par_decisao_coerente
    CHECK ((authority_status IN ('approved','rejected')) = (decided_at IS NOT NULL)),
  CONSTRAINT par_substituido_nao_corrente
    CHECK ((replaced_at IS NULL) OR (is_current = false)),
  CONSTRAINT par_timestamps CHECK (updated_at >= created_at)
);

COMMENT ON TABLE public.partner_application_representatives IS
  'Representante/autoridade inicial da aplicação. Histórico preservado: substituição marca o anterior como não corrente.';

CREATE UNIQUE INDEX par_um_corrente_por_aplicacao_uk
  ON public.partner_application_representatives (application_id)
  WHERE is_current;

CREATE INDEX par_application_idx ON public.partner_application_representatives (application_id, created_at DESC);

CREATE TRIGGER trg_par_touch
  BEFORE UPDATE ON public.partner_application_representatives
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ---------------------------------------------------------------------------
-- 3. partner_application_tokens
-- ---------------------------------------------------------------------------
-- Token próprio pré-Auth. Persistimos SOMENTE o hash (sha256 do segredo).
-- Uso único, expirável, e a emissão de um novo invalida o anterior do
-- mesmo propósito.
CREATE TABLE public.partner_application_tokens (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id  uuid        NOT NULL REFERENCES public.partner_applications(id) ON DELETE CASCADE,
  purpose         text        NOT NULL,
  email           text        NOT NULL,
  token_hash      bytea       NOT NULL,
  expires_at      timestamptz NOT NULL,
  consumed_at     timestamptz,
  invalidated_at  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT pat_purpose_allowed
    CHECK (purpose = ANY (ARRAY['email_verification','account_claim'])),
  CONSTRAINT pat_email_formato
    CHECK (email = lower(btrim(email)) AND length(email) <= 320),
  CONSTRAINT pat_hash_tamanho   CHECK (octet_length(token_hash) = 32),
  CONSTRAINT pat_expira_depois  CHECK (expires_at > created_at),
  CONSTRAINT pat_consumo_unico  CHECK (consumed_at IS NULL OR invalidated_at IS NULL)
);

COMMENT ON TABLE public.partner_application_tokens IS
  'Tokens pré-Auth. Somente o hash sha256 é persistido; o segredo em claro nunca é armazenado.';
COMMENT ON COLUMN public.partner_application_tokens.token_hash IS
  'sha256(segredo). O segredo em claro só trafega uma vez, via outbox de notificação.';

CREATE UNIQUE INDEX pat_token_hash_uk ON public.partner_application_tokens (token_hash);

-- No máximo um token vivo por (aplicação, propósito).
CREATE UNIQUE INDEX pat_um_vivo_por_proposito_uk
  ON public.partner_application_tokens (application_id, purpose)
  WHERE consumed_at IS NULL AND invalidated_at IS NULL;

CREATE INDEX pat_expires_idx ON public.partner_application_tokens (expires_at)
  WHERE consumed_at IS NULL AND invalidated_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. partner_application_documents
-- ---------------------------------------------------------------------------
-- Somente METADADOS. O arquivo vive em bucket PRIVADO do Storage.
CREATE TABLE public.partner_application_documents (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id     uuid        NOT NULL REFERENCES public.partner_applications(id) ON DELETE CASCADE,
  doc_type           text        NOT NULL,
  storage_bucket     text        NOT NULL DEFAULT 'partner-application-docs',
  storage_path       text        NOT NULL,
  original_filename  text        NOT NULL,
  mime_type          text        NOT NULL,
  byte_size          bigint      NOT NULL,
  checksum_sha256    text,
  uploaded_by        uuid,
  review_status      text        NOT NULL DEFAULT 'received',
  review_notes       text,
  reviewed_at        timestamptz,
  reviewed_by        uuid,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT pad_doc_type_allowed
    CHECK (doc_type = ANY (ARRAY[
      'contrato_social','cartao_cnpj','documento_representante',
      'procuracao','comprovante_endereco','outro'
    ])),
  CONSTRAINT pad_bucket_privado    CHECK (storage_bucket = 'partner-application-docs'),
  CONSTRAINT pad_path_nonempty     CHECK (length(btrim(storage_path)) BETWEEN 3 AND 1024),
  -- O caminho é sempre prefixado pelo id da aplicação: base do isolamento
  -- por pasta no Storage.
  CONSTRAINT pad_path_prefixado    CHECK (storage_path LIKE (application_id::text || '/%')),
  CONSTRAINT pad_filename_nonempty CHECK (length(btrim(original_filename)) BETWEEN 1 AND 300),
  CONSTRAINT pad_mime_allowed
    CHECK (mime_type = ANY (ARRAY['application/pdf','image/jpeg','image/png','image/webp'])),
  CONSTRAINT pad_tamanho           CHECK (byte_size > 0 AND byte_size <= 20971520),
  CONSTRAINT pad_checksum_formato  CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT pad_review_allowed
    CHECK (review_status = ANY (ARRAY['received','accepted','rejected'])),
  CONSTRAINT pad_review_coerente
    CHECK ((review_status IN ('accepted','rejected')) = (reviewed_at IS NOT NULL)),
  CONSTRAINT pad_timestamps        CHECK (updated_at >= created_at)
);

COMMENT ON TABLE public.partner_application_documents IS
  'Metadados de documentos empresariais. Arquivos ficam em bucket privado; nunca público.';

CREATE UNIQUE INDEX pad_storage_path_uk ON public.partner_application_documents (storage_bucket, storage_path);
CREATE INDEX pad_application_idx ON public.partner_application_documents (application_id, created_at DESC);

CREATE TRIGGER trg_pad_touch
  BEFORE UPDATE ON public.partner_application_documents
  FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at();

-- ---------------------------------------------------------------------------
-- 5. partner_application_corrections
-- ---------------------------------------------------------------------------
CREATE TABLE public.partner_application_corrections (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id    uuid        NOT NULL REFERENCES public.partner_applications(id) ON DELETE CASCADE,
  scope             text        NOT NULL,
  message           text        NOT NULL,
  requested_by      uuid        NOT NULL,
  requested_at      timestamptz NOT NULL DEFAULT now(),
  response_message  text,
  responded_at      timestamptz,
  responded_by      uuid,

  CONSTRAINT pac_scope_allowed
    CHECK (scope = ANY (ARRAY['company','authority','documents'])),
  CONSTRAINT pac_message_tamanho   CHECK (length(btrim(message)) BETWEEN 3 AND 2000),
  CONSTRAINT pac_response_tamanho
    CHECK (response_message IS NULL OR length(btrim(response_message)) BETWEEN 1 AND 2000),
  CONSTRAINT pac_resposta_coerente
    CHECK ((responded_at IS NULL) = (response_message IS NULL)),
  CONSTRAINT pac_resposta_depois
    CHECK (responded_at IS NULL OR responded_at >= requested_at)
);

COMMENT ON TABLE public.partner_application_corrections IS
  'Correções solicitadas pela administração e as respostas do solicitante.';

CREATE INDEX pac_application_idx ON public.partner_application_corrections (application_id, requested_at DESC);
CREATE INDEX pac_pendentes_idx   ON public.partner_application_corrections (application_id)
  WHERE responded_at IS NULL;

-- ===========================================================================
-- RLS — habilitada explicitamente (o event trigger ensure_rls já habilita,
-- mas não dependemos disso: declaramos por escrito).
-- ===========================================================================
ALTER TABLE public.partner_applications                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_application_representatives  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_application_tokens           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_application_documents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_application_corrections      ENABLE ROW LEVEL SECURITY;

-- Tokens: NENHUMA policy. Nem anon nem authenticated leem esta tabela em
-- hipótese alguma; o acesso é exclusivo das RPCs SECURITY DEFINER.
-- (Sem policy + RLS ativa = fail-closed.)

-- partner_applications ------------------------------------------------------
-- O titular provisório enxerga apenas a própria solicitação.
CREATE POLICY partner_applications_titular_select
  ON public.partner_applications FOR SELECT TO authenticated
  USING (account_user_id = auth.uid());

-- Administrador autorizado enxerga todas (autorização server-side real).
CREATE POLICY partner_applications_admin_select
  ON public.partner_applications FOR SELECT TO authenticated
  USING (public.is_site_admin());

-- representantes ------------------------------------------------------------
CREATE POLICY par_titular_select
  ON public.partner_application_representatives FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.partner_applications a
     WHERE a.id = application_id AND a.account_user_id = auth.uid()
  ));

CREATE POLICY par_admin_select
  ON public.partner_application_representatives FOR SELECT TO authenticated
  USING (public.is_site_admin());

-- documentos ----------------------------------------------------------------
CREATE POLICY pad_titular_select
  ON public.partner_application_documents FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.partner_applications a
     WHERE a.id = application_id AND a.account_user_id = auth.uid()
  ));

CREATE POLICY pad_admin_select
  ON public.partner_application_documents FOR SELECT TO authenticated
  USING (public.is_site_admin());

-- correções -----------------------------------------------------------------
CREATE POLICY pac_titular_select
  ON public.partner_application_corrections FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.partner_applications a
     WHERE a.id = application_id AND a.account_user_id = auth.uid()
  ));

CREATE POLICY pac_admin_select
  ON public.partner_application_corrections FOR SELECT TO authenticated
  USING (public.is_site_admin());

-- ===========================================================================
-- GRANTS EXPLÍCITOS
-- ===========================================================================
-- anon não recebe NADA nessas tabelas. Toda a interação anônima acontece por
-- RPC SECURITY DEFINER, cujo EXECUTE é concedido na migration seguinte.
-- authenticated recebe apenas SELECT, e a RLS acima restringe as linhas.
-- Nenhuma escrita direta é concedida a nenhuma role do Data API.
GRANT SELECT ON public.partner_applications                TO authenticated;
GRANT SELECT ON public.partner_application_representatives TO authenticated;
GRANT SELECT ON public.partner_application_documents       TO authenticated;
GRANT SELECT ON public.partner_application_corrections     TO authenticated;

-- service_role mantém acesso operacional completo (backend/servidor).
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_applications                TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_application_representatives TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_application_tokens          TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_application_documents       TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_application_corrections     TO service_role;
