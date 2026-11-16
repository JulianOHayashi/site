-- ===========================================================================
-- R4.2 — INTEGRAÇÃO COMERCIAL: alteração voluntária de frase/arte e
-- fidelidade independente da reutilização das bandeiras.
--
-- Migration PREPARATÓRIA, NÃO aplicada. Depende de 20261112120000 (SF-v1.5),
-- 20261113150000 (R3), 20261113180000 (R4) e 20261113200000 (R4.1), também
-- não aplicadas. Não grava preço, modalidade, aprovação, procedimento de QA
-- nem pedido de alteração; não ativa versão; não altera linha histórica.
--
-- Decisões (missão R4.2, 16/11/2026; documentos-fonte citados pelo nome):
--   B. Fidelidade != reutilização: mudar frase/arte voluntariamente não tira
--      a condição fidelizada (que continua decidida pelas regras próprias do
--      servidor). Na renovação fidelizada sem reutilização verificada, uma
--      alteração de arte com produção AUTORIZADA para a próxima campanha
--      substitui a reutilização: preço-base, participantes e QA fidelizados
--      não mudam; a produção da nova arte fica em rubrica separada.
--   C. Custo comprovado do fornecedor, SEM margem: o valor ao parceiro é o
--      total do documento do fornecedor (coluna gerada); teto obrigatório;
--      frete, criação de arte, instalação, tributos e serviços ficam
--      expressamente NÃO incluídos; aceite prévio do partner_owner; novo
--      orçamento derruba o aceite.
--   D. Vigência: próxima campanha por padrão; campanha atual só com exceção
--      registrada por administrador (motivo e viabilidade). A imagem do
--      pedido fica travada depois da produção: troca só por solicitação.
--   E. Bandeiras danificadas: inalterado (bloqueio seguro).
--   F. QA: inalterado (trava R4.1 preservada).
-- Cobrança e produção externas NÃO são implementadas: o fluxo termina em
-- 'production_authorized'.
-- ===========================================================================

-- ===========================================================================
-- A. PEDIDO DE ALTERAÇÃO DE ARTE
-- ===========================================================================
CREATE TABLE public.commercial_artwork_change_requests (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                uuid NOT NULL REFERENCES public.site_partner_companies(id),
  base_order_id             uuid NOT NULL REFERENCES public.commercial_exclusivity_orders(id),
  fidelity_identity         text NOT NULL,
  target_campaign           text NOT NULL,
  status                    text NOT NULL DEFAULT 'draft',
  row_version               integer NOT NULL DEFAULT 1,
  phrase_text               text,
  request_note              text,
  requested_by              uuid NOT NULL,
  accepted_quote_id         uuid,
  accepted_total_cents      bigint,
  accepted_by               uuid,
  accepted_at               timestamptz,
  exception_reason          text,
  exception_feasibility     text,
  exception_approved_by     uuid,
  exception_approved_at     timestamptz,
  production_authorized_by  uuid,
  production_authorized_at  timestamptz,
  closed_reason             text,
  closed_by                 uuid,
  closed_at                 timestamptz,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cacr_alvo CHECK (target_campaign IN ('next_campaign', 'current_campaign')),
  CONSTRAINT cacr_status CHECK (status IN ('draft', 'submitted', 'under_review', 'quoted', 'accepted',
                                           'production_authorized', 'rejected', 'cancelled')),
  CONSTRAINT cacr_frase CHECK (phrase_text IS NULL OR length(btrim(phrase_text)) BETWEEN 1 AND 280),
  CONSTRAINT cacr_identidade CHECK (fidelity_identity ~ '^[a-z][a-z_]{2,63}$'
                                    OR fidelity_identity ~ '^segment:[a-z][a-z0-9_]{2,63}$'),
  CONSTRAINT cacr_aceite_coerente CHECK (
    (status IN ('accepted', 'production_authorized')
       AND accepted_quote_id IS NOT NULL AND accepted_total_cents > 0
       AND accepted_by IS NOT NULL AND accepted_at IS NOT NULL)
    OR (status NOT IN ('accepted', 'production_authorized')
       AND accepted_quote_id IS NULL AND accepted_total_cents IS NULL
       AND accepted_by IS NULL AND accepted_at IS NULL)
    OR status IN ('cancelled', 'rejected')),
  CONSTRAINT cacr_excecao_coerente CHECK (
    (exception_approved_by IS NULL AND exception_approved_at IS NULL
       AND exception_reason IS NULL AND exception_feasibility IS NULL)
    OR (target_campaign = 'current_campaign'
       AND exception_approved_by IS NOT NULL AND exception_approved_at IS NOT NULL
       AND length(btrim(exception_reason)) >= 10 AND length(btrim(exception_feasibility)) >= 10)),
  CONSTRAINT cacr_producao_coerente CHECK (
    (status = 'production_authorized' AND production_authorized_by IS NOT NULL
       AND production_authorized_at IS NOT NULL
       AND (target_campaign = 'next_campaign' OR exception_approved_by IS NOT NULL))
    OR (status <> 'production_authorized' AND production_authorized_by IS NULL
       AND production_authorized_at IS NULL)),
  CONSTRAINT cacr_encerramento_coerente CHECK (
    (status IN ('cancelled', 'rejected') AND closed_at IS NOT NULL AND closed_by IS NOT NULL
       AND length(btrim(coalesce(closed_reason, ''))) >= 3)
    OR (status NOT IN ('cancelled', 'rejected') AND closed_at IS NULL AND closed_by IS NULL
       AND closed_reason IS NULL))
);
COMMENT ON TABLE public.commercial_artwork_change_requests IS
  'R4.2: solicitacao VOLUNTARIA de alteracao de frase/arte. Nao substitui a arte em execucao; '
  'vale na proxima campanha, ou na atual por excecao registrada por administrador. Custo ao '
  'parceiro = custo comprovado do fornecedor, sem margem (commercial_artwork_change_quotes).';

-- Uma solicitação em andamento por empresa e identidade de fidelidade
-- (dupla solicitação é recusada também na corrida, pelo índice).
CREATE UNIQUE INDEX cacr_uma_aberta_idx
  ON public.commercial_artwork_change_requests (company_id, fidelity_identity)
  WHERE status IN ('draft', 'submitted', 'under_review', 'quoted', 'accepted');
CREATE INDEX cacr_pedido_idx ON public.commercial_artwork_change_requests (base_order_id, created_at DESC);

-- Versões da arte final (append-only), no bucket privado já existente.
CREATE TABLE public.commercial_artwork_change_versions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      uuid NOT NULL REFERENCES public.commercial_artwork_change_requests(id),
  version_no      integer NOT NULL,
  storage_bucket  text NOT NULL DEFAULT 'partner-customization-images',
  storage_path    text NOT NULL,
  mime_type       text NOT NULL,
  byte_size       bigint NOT NULL,
  sha256          text NOT NULL,
  phrase_text     text,
  registered_by   uuid NOT NULL,
  registered_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cacv_bucket CHECK (storage_bucket = 'partner-customization-images'),
  CONSTRAINT cacv_mime CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  CONSTRAINT cacv_tamanho CHECK (byte_size > 0 AND byte_size <= 10485760),
  CONSTRAINT cacv_sha256 CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cacv_frase CHECK (phrase_text IS NULL OR length(btrim(phrase_text)) BETWEEN 1 AND 280),
  CONSTRAINT cacv_numero UNIQUE (request_id, version_no),
  CONSTRAINT cacv_caminho UNIQUE (storage_bucket, storage_path)
);

-- Orçamento do fornecedor. Valor ao parceiro = total do fornecedor: a coluna
-- é gerada, não há onde pôr margem.
CREATE TABLE public.commercial_artwork_change_quotes (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id                   uuid NOT NULL REFERENCES public.commercial_artwork_change_requests(id),
  quote_no                     integer NOT NULL,
  artwork_version_id           uuid NOT NULL REFERENCES public.commercial_artwork_change_versions(id),
  supplier_name                text NOT NULL,
  supplier_document_reference  text NOT NULL,
  supplier_document_sha256     text NOT NULL,
  scope                        text NOT NULL,
  pieces_count                 integer NOT NULL,
  supplier_unit_cost_cents     bigint NOT NULL,
  supplier_total_cents         bigint NOT NULL,
  partner_charge_cents         bigint GENERATED ALWAYS AS (supplier_total_cents) STORED,
  cap_cents                    bigint NOT NULL,
  excluded_items               text[] NOT NULL
                               DEFAULT ARRAY['frete', 'criacao_de_arte', 'instalacao', 'tributos', 'servicos'],
  status                       text NOT NULL DEFAULT 'open',
  registered_by                uuid NOT NULL,
  registered_at                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cacq_fornecedor CHECK (length(btrim(supplier_name)) >= 2),
  CONSTRAINT cacq_documento CHECK (length(btrim(supplier_document_reference)) >= 5
                                   AND supplier_document_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cacq_escopo CHECK (length(btrim(scope)) >= 5),
  CONSTRAINT cacq_valores CHECK (pieces_count > 0 AND supplier_unit_cost_cents > 0
                                 AND supplier_total_cents > 0 AND cap_cents >= supplier_total_cents),
  CONSTRAINT cacq_nao_incluidos CHECK (
    excluded_items @> ARRAY['frete', 'criacao_de_arte', 'instalacao', 'tributos', 'servicos']),
  CONSTRAINT cacq_status CHECK (status IN ('open', 'superseded', 'accepted')),
  CONSTRAINT cacq_numero UNIQUE (request_id, quote_no)
);
CREATE UNIQUE INDEX cacq_um_aberto_idx
  ON public.commercial_artwork_change_quotes (request_id) WHERE status = 'open';
COMMENT ON COLUMN public.commercial_artwork_change_quotes.partner_charge_cents IS
  'R4.2: valor ao parceiro = custo comprovado do fornecedor (supplier_total_cents), sem margem de fabricacao.';
COMMENT ON COLUMN public.commercial_artwork_change_quotes.excluded_items IS
  'R4.2: rubricas NAO incluidas e NAO autorizadas automaticamente; exigem decisao propria.';

-- Trilha (append-only).
CREATE TABLE public.commercial_artwork_change_events (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id   uuid NOT NULL REFERENCES public.commercial_artwork_change_requests(id),
  event        text NOT NULL,
  from_status  text,
  to_status    text NOT NULL,
  actor_uid    uuid,
  actor_role   text NOT NULL,
  detail       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cace_papel CHECK (actor_role IN ('partner_owner', 'site_admin', 'system'))
);
CREATE INDEX cace_pedido_idx ON public.commercial_artwork_change_events (request_id, id);

-- ---------------------------------------------------------------------------
-- Proteções: máquina de estados no gatilho (vale para qualquer caminho).
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.commercial_artwork_change_requests_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: solicitacao nao e apagada' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'draft' OR NEW.row_version <> 1 THEN
      RAISE EXCEPTION 'alteracao_arte_estado_invalido: solicitacao nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.company_id IS DISTINCT FROM OLD.company_id
     OR NEW.base_order_id IS DISTINCT FROM OLD.base_order_id
     OR NEW.fidelity_identity IS DISTINCT FROM OLD.fidelity_identity
     OR NEW.target_campaign IS DISTINCT FROM OLD.target_campaign
     OR NEW.requested_by IS DISTINCT FROM OLD.requested_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: identidade da solicitacao nao muda' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.row_version <> OLD.row_version + 1 THEN
    RAISE EXCEPTION 'alteracao_arte_versao: row_version deve avancar exatamente 1' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status IN ('production_authorized', 'rejected', 'cancelled') THEN
    RAISE EXCEPTION 'alteracao_arte_final: solicitacao % encerrada (%)', OLD.id, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF NOT ((OLD.status, NEW.status) IN (
      ('draft', 'draft'), ('draft', 'submitted'), ('draft', 'cancelled'),
      ('submitted', 'submitted'), ('submitted', 'under_review'), ('submitted', 'cancelled'), ('submitted', 'rejected'),
      ('under_review', 'under_review'), ('under_review', 'quoted'), ('under_review', 'cancelled'),
      ('under_review', 'rejected'),
      ('quoted', 'quoted'), ('quoted', 'under_review'), ('quoted', 'accepted'), ('quoted', 'cancelled'),
      ('quoted', 'rejected'),
      ('accepted', 'accepted'), ('accepted', 'quoted'), ('accepted', 'production_authorized'),
      ('accepted', 'cancelled'), ('accepted', 'rejected'))) THEN
    RAISE EXCEPTION 'alteracao_arte_transicao_invalida: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  -- Exceção registrada não é desfeita nem reescrita.
  IF OLD.exception_approved_by IS NOT NULL AND (
       NEW.exception_approved_by IS DISTINCT FROM OLD.exception_approved_by
       OR NEW.exception_approved_at IS DISTINCT FROM OLD.exception_approved_at
       OR NEW.exception_reason IS DISTINCT FROM OLD.exception_reason
       OR NEW.exception_feasibility IS DISTINCT FROM OLD.exception_feasibility) THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: excecao registrada nao muda' USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_requests_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cacr_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_artwork_change_requests
  FOR EACH ROW EXECUTE FUNCTION public.commercial_artwork_change_requests_protect();

CREATE FUNCTION public.commercial_artwork_change_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'alteracao_arte_imutavel: % e append-only', TG_TABLE_NAME USING ERRCODE = 'check_violation';
  END IF;
  -- Orçamento: só o status muda (aberto -> superado/aceito; aceito ->
  -- superado quando um orçamento revisado derruba o aceite).
  IF TG_TABLE_NAME = 'commercial_artwork_change_quotes' THEN
    IF ((to_jsonb(OLD)->>'status' = 'open' AND to_jsonb(NEW)->>'status' IN ('superseded', 'accepted'))
        OR (to_jsonb(OLD)->>'status' = 'accepted' AND to_jsonb(NEW)->>'status' = 'superseded'))
       -- (coluna gerada fora da comparação: em BEFORE ela ainda não foi calculada)
       AND (to_jsonb(NEW) - 'status' - 'partner_charge_cents') = (to_jsonb(OLD) - 'status' - 'partner_charge_cents') THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'alteracao_arte_imutavel: % e append-only', TG_TABLE_NAME USING ERRCODE = 'check_violation';
END $$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_append_only() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cacv_append_only BEFORE UPDATE OR DELETE ON public.commercial_artwork_change_versions
  FOR EACH ROW EXECUTE FUNCTION public.commercial_artwork_change_append_only();
CREATE TRIGGER cacq_append_only BEFORE UPDATE OR DELETE ON public.commercial_artwork_change_quotes
  FOR EACH ROW EXECUTE FUNCTION public.commercial_artwork_change_append_only();
CREATE TRIGGER cace_append_only BEFORE UPDATE OR DELETE ON public.commercial_artwork_change_events
  FOR EACH ROW EXECUTE FUNCTION public.commercial_artwork_change_append_only();
CREATE TRIGGER cacr_protect_truncate BEFORE TRUNCATE ON public.commercial_artwork_change_requests
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();
CREATE TRIGGER cacv_protect_truncate BEFORE TRUNCATE ON public.commercial_artwork_change_versions
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();
CREATE TRIGGER cacq_protect_truncate BEFORE TRUNCATE ON public.commercial_artwork_change_quotes
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();
CREATE TRIGGER cace_protect_truncate BEFORE TRUNCATE ON public.commercial_artwork_change_events
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

ALTER TABLE public.commercial_artwork_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_artwork_change_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_artwork_change_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_artwork_change_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_artwork_change_requests, public.commercial_artwork_change_versions,
              public.commercial_artwork_change_quotes, public.commercial_artwork_change_events
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_artwork_change_requests, public.commercial_artwork_change_versions,
                public.commercial_artwork_change_quotes, public.commercial_artwork_change_events TO service_role;

-- ===========================================================================
-- B. RPCs. Toda autorização é do servidor: auth.uid(), papel na empresa do
--    pedido (owner) ou administrador do Site. Manager lê, não decide.
--    Concorrência: cada transição exige a row_version que o chamador viu
--    (stale_request se outra transação já mudou a solicitação).
-- ===========================================================================
CREATE FUNCTION public.commercial_artwork_change_actor(p_company_id uuid)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN NULL
    WHEN public.is_site_admin() THEN 'site_admin'
    WHEN public.m2_is_company_owner(p_company_id) THEN 'partner_owner'
    WHEN public.m2_is_company_member(p_company_id) THEN 'partner_member'
    ELSE NULL END;
$$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_actor(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- Carrega com trava e confere papel, versão e estado. NULL = pode seguir.
CREATE FUNCTION public.commercial_artwork_change_gate(
  p_request_id uuid, p_expected_row_version integer, p_roles text[], p_statuses text[],
  OUT r public.commercial_artwork_change_requests, OUT actor text, OUT refusal jsonb)
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    refusal := pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
    RETURN;
  END IF;
  SELECT * INTO r FROM public.commercial_artwork_change_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    refusal := pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
    RETURN;
  END IF;
  actor := public.commercial_artwork_change_actor(r.company_id);
  IF actor IS NULL OR NOT (actor = ANY (p_roles)) THEN
    refusal := pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
    RETURN;
  END IF;
  IF p_expected_row_version IS DISTINCT FROM r.row_version THEN
    refusal := pg_catalog.jsonb_build_object('ok', false, 'reason', 'stale_request',
                                             'current_row_version', r.row_version, 'status', r.status);
    RETURN;
  END IF;
  IF NOT (r.status = ANY (p_statuses)) THEN
    refusal := pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_status', 'status', r.status);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_gate(uuid, integer, text[], text[]) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.commercial_artwork_change_event(
  p_request_id uuid, p_event text, p_from text, p_to text, p_actor text, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE sql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  INSERT INTO public.commercial_artwork_change_events (request_id, event, from_status, to_status, actor_uid, actor_role, detail)
  VALUES (p_request_id, p_event, p_from, p_to, auth.uid(), p_actor, coalesce(p_detail, '{}'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_event(uuid, text, text, text, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- 1. Owner abre o rascunho a partir de um pedido da própria empresa.
CREATE FUNCTION public.artwork_change_request_create(
  p_order_id uuid, p_target_campaign text DEFAULT 'next_campaign',
  p_phrase_text text DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_o  public.commercial_exclusivity_orders%ROWTYPE;
  v_id uuid;
  v_identidade text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF public.commercial_artwork_change_actor(v_o.company_id) IS DISTINCT FROM 'partner_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_o.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;
  IF p_target_campaign IS NULL OR p_target_campaign NOT IN ('next_campaign', 'current_campaign') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_target');
  END IF;
  IF p_phrase_text IS NOT NULL AND length(btrim(p_phrase_text)) NOT BETWEEN 1 AND 280 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_phrase');
  END IF;
  v_identidade := public.commercial_fidelity_identity(v_o.niche_code, v_o.segment_id);
  IF EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests
              WHERE company_id = v_o.company_id AND fidelity_identity = v_identidade
                AND status IN ('draft', 'submitted', 'under_review', 'quoted', 'accepted')) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_change_already_open');
  END IF;
  BEGIN
    INSERT INTO public.commercial_artwork_change_requests
      (company_id, base_order_id, fidelity_identity, target_campaign, phrase_text, request_note, requested_by)
    VALUES (v_o.company_id, v_o.id, v_identidade, p_target_campaign,
            nullif(btrim(coalesce(p_phrase_text, '')), ''), nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_change_already_open');
  END;
  PERFORM public.commercial_artwork_change_event(v_id, 'created', NULL, 'draft', 'partner_owner',
    pg_catalog.jsonb_build_object('target_campaign', p_target_campaign));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'request_id', v_id, 'status', 'draft', 'row_version', 1);
END $$;

-- 2. Caminho no bucket existente, derivado no servidor (preso ao pedido base,
--    para as políticas de Storage já existentes valerem).
CREATE FUNCTION public.artwork_change_image_path(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_r public.commercial_artwork_change_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_r FROM public.commercial_artwork_change_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF public.commercial_artwork_change_actor(v_r.company_id) IS DISTINCT FROM 'partner_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_r.status NOT IN ('draft', 'submitted', 'under_review', 'quoted') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_status', 'status', v_r.status);
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'bucket', 'partner-customization-images',
    'storage_path', v_r.base_order_id::text || '/alteracao-arte/' || v_r.id::text || '/'
                    || pg_catalog.replace(gen_random_uuid()::text, '-', ''));
END $$;

-- 3. Registra uma versão da arte (objeto real no Storage; MIME e tamanho do
--    Storage). Arte nova depois de orçada derruba o orçamento aberto.
CREATE FUNCTION public.artwork_change_register_version(
  p_request_id uuid, p_expected_row_version integer, p_storage_path text, p_sha256 text,
  p_phrase_text text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  g    record;
  v_obj storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
  v_n   integer;
  v_id  uuid;
  v_novo text;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['partner_owner'], ARRAY['draft', 'submitted', 'under_review', 'quoted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  IF p_storage_path IS NULL
     OR p_storage_path NOT LIKE ((g.r).base_order_id::text || '/alteracao-arte/' || (g.r).id::text || '/%') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_path');
  END IF;
  IF p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_sha256');
  END IF;
  IF p_phrase_text IS NOT NULL AND length(btrim(p_phrase_text)) NOT BETWEEN 1 AND 280 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_phrase');
  END IF;
  SELECT * INTO v_obj FROM storage.objects o
   WHERE o.bucket_id = 'partner-customization-images' AND o.name = p_storage_path;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_found');
  END IF;
  IF v_obj.owner IS NOT NULL AND v_obj.owner <> auth.uid() THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_owned');
  END IF;
  v_size := (v_obj.metadata->>'size')::bigint;
  v_mime := nullif(v_obj.metadata->>'mimetype', '');
  IF v_size IS NULL OR v_mime IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_metadata');
  END IF;
  IF v_mime NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_mime');
  END IF;
  IF v_size <= 0 OR v_size > 10485760 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_size');
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_artwork_change_versions WHERE storage_path = p_storage_path) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'path_already_registered');
  END IF;

  SELECT coalesce(max(version_no), 0) + 1 INTO v_n
    FROM public.commercial_artwork_change_versions WHERE request_id = (g.r).id;
  INSERT INTO public.commercial_artwork_change_versions
    (request_id, version_no, storage_path, mime_type, byte_size, sha256, phrase_text, registered_by)
  VALUES ((g.r).id, v_n, p_storage_path, v_mime, v_size, p_sha256,
          nullif(btrim(coalesce(p_phrase_text, '')), ''), auth.uid())
  RETURNING id INTO v_id;

  v_novo := (g.r).status;
  IF (g.r).status = 'quoted' THEN
    UPDATE public.commercial_artwork_change_quotes SET status = 'superseded'
     WHERE request_id = (g.r).id AND status = 'open';
    v_novo := 'under_review';
  END IF;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = v_novo,
         phrase_text = coalesce(nullif(btrim(coalesce(p_phrase_text, '')), ''), phrase_text)
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'artwork_version_registered', (g.r).status, v_novo,
    'partner_owner', pg_catalog.jsonb_build_object('version_id', v_id, 'version_no', v_n, 'sha256', p_sha256));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'version_id', v_id, 'version_no', v_n,
    'status', v_novo, 'row_version', (g.r).row_version + 1);
END $$;

-- 4. Owner envia para análise (exige arte).
CREATE FUNCTION public.artwork_change_submit(p_request_id uuid, p_expected_row_version integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['partner_owner'], ARRAY['draft']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.commercial_artwork_change_versions WHERE request_id = (g.r).id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_version_required');
  END IF;
  UPDATE public.commercial_artwork_change_requests SET row_version = row_version + 1, status = 'submitted'
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'submitted', 'draft', 'submitted', 'partner_owner');
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'submitted', 'row_version', (g.r).row_version + 1);
END $$;

-- 5. Owner aceita o orçamento vigente, confirmando o valor exato.
CREATE FUNCTION public.artwork_change_accept_quote(
  p_request_id uuid, p_expected_row_version integer, p_quote_id uuid, p_accepted_total_cents bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  g   record;
  v_q public.commercial_artwork_change_quotes%ROWTYPE;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['partner_owner'], ARRAY['quoted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  SELECT * INTO v_q FROM public.commercial_artwork_change_quotes
   WHERE id = p_quote_id AND request_id = (g.r).id;
  IF NOT FOUND OR v_q.status <> 'open' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quote_not_current');
  END IF;
  IF v_q.artwork_version_id IS DISTINCT FROM (SELECT id FROM public.commercial_artwork_change_versions
                                               WHERE request_id = (g.r).id ORDER BY version_no DESC LIMIT 1) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quote_not_current');
  END IF;
  IF p_accepted_total_cents IS DISTINCT FROM v_q.partner_charge_cents OR v_q.partner_charge_cents > v_q.cap_cents THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'accepted_total_mismatch',
      'partner_charge_cents', v_q.partner_charge_cents, 'cap_cents', v_q.cap_cents);
  END IF;
  UPDATE public.commercial_artwork_change_quotes SET status = 'accepted' WHERE id = v_q.id;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'accepted', accepted_quote_id = v_q.id,
         accepted_total_cents = v_q.partner_charge_cents, accepted_by = auth.uid(), accepted_at = pg_catalog.now()
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'quote_accepted', 'quoted', 'accepted', 'partner_owner',
    pg_catalog.jsonb_build_object('quote_id', v_q.id, 'partner_charge_cents', v_q.partner_charge_cents,
                                  'cap_cents', v_q.cap_cents));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'accepted', 'row_version', (g.r).row_version + 1);
END $$;

-- 6. Cancelamento: owner ou administrador, antes da produção autorizada.
CREATE FUNCTION public.artwork_change_cancel(p_request_id uuid, p_expected_row_version integer, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['partner_owner', 'site_admin'], ARRAY['draft', 'submitted', 'under_review', 'quoted', 'accepted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reason_required');
  END IF;
  UPDATE public.commercial_artwork_change_quotes SET status = 'superseded'
   WHERE request_id = (g.r).id AND status = 'open';
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'cancelled', closed_reason = btrim(p_reason),
         closed_by = auth.uid(), closed_at = pg_catalog.now()
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'cancelled', (g.r).status, 'cancelled', g.actor,
    pg_catalog.jsonb_build_object('reason', btrim(p_reason)));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'cancelled', 'row_version', (g.r).row_version + 1);
END $$;

-- 7. Administrador: análise.
CREATE FUNCTION public.admin_artwork_change_start_review(p_request_id uuid, p_expected_row_version integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['site_admin'], ARRAY['submitted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  UPDATE public.commercial_artwork_change_requests SET row_version = row_version + 1, status = 'under_review'
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'review_started', 'submitted', 'under_review', 'site_admin');
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'under_review', 'row_version', (g.r).row_version + 1);
END $$;

-- 8. Administrador: orçamento do fornecedor sobre a arte vigente. Substitui
--    o aberto e, se já havia aceite, o derruba (novo aceite obrigatório).
CREATE FUNCTION public.admin_artwork_change_register_quote(
  p_request_id uuid, p_expected_row_version integer,
  p_supplier_name text, p_supplier_document_reference text, p_supplier_document_sha256 text,
  p_scope text, p_pieces_count integer, p_supplier_unit_cost_cents bigint,
  p_supplier_total_cents bigint, p_cap_cents bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  g     record;
  v_ver uuid;
  v_n   integer;
  v_id  uuid;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['site_admin'], ARRAY['under_review', 'quoted', 'accepted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  SELECT id INTO v_ver FROM public.commercial_artwork_change_versions
   WHERE request_id = (g.r).id ORDER BY version_no DESC LIMIT 1;
  IF v_ver IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_version_required');
  END IF;
  IF p_supplier_name IS NULL OR length(btrim(p_supplier_name)) < 2
     OR p_supplier_document_reference IS NULL OR length(btrim(p_supplier_document_reference)) < 5
     OR p_supplier_document_sha256 IS NULL OR p_supplier_document_sha256 !~ '^[0-9a-f]{64}$'
     OR p_scope IS NULL OR length(btrim(p_scope)) < 5 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'supplier_document_required');
  END IF;
  IF p_pieces_count IS NULL OR p_pieces_count <= 0 OR p_supplier_unit_cost_cents IS NULL
     OR p_supplier_unit_cost_cents <= 0 OR p_supplier_total_cents IS NULL OR p_supplier_total_cents <= 0
     OR p_cap_cents IS NULL OR p_cap_cents < p_supplier_total_cents THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_quote_values');
  END IF;

  UPDATE public.commercial_artwork_change_quotes SET status = 'superseded'
   WHERE request_id = (g.r).id AND status IN ('open', 'accepted');
  SELECT coalesce(max(quote_no), 0) + 1 INTO v_n FROM public.commercial_artwork_change_quotes
   WHERE request_id = (g.r).id;
  INSERT INTO public.commercial_artwork_change_quotes
    (request_id, quote_no, artwork_version_id, supplier_name, supplier_document_reference,
     supplier_document_sha256, scope, pieces_count, supplier_unit_cost_cents, supplier_total_cents,
     cap_cents, registered_by)
  VALUES ((g.r).id, v_n, v_ver, btrim(p_supplier_name), btrim(p_supplier_document_reference),
          p_supplier_document_sha256, btrim(p_scope), p_pieces_count, p_supplier_unit_cost_cents,
          p_supplier_total_cents, p_cap_cents, auth.uid())
  RETURNING id INTO v_id;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'quoted', accepted_quote_id = NULL,
         accepted_total_cents = NULL, accepted_by = NULL, accepted_at = NULL
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id,
    CASE WHEN (g.r).status = 'accepted' THEN 'quote_revised_acceptance_cleared' ELSE 'quote_registered' END,
    (g.r).status, 'quoted', 'site_admin',
    pg_catalog.jsonb_build_object('quote_id', v_id, 'quote_no', v_n, 'supplier_total_cents', p_supplier_total_cents,
                                  'cap_cents', p_cap_cents, 'artwork_version_id', v_ver));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'quote_id', v_id, 'quote_no', v_n, 'status', 'quoted',
    'partner_charge_cents', p_supplier_total_cents, 'row_version', (g.r).row_version + 1);
END $$;

-- 9. Administrador competente: exceção para a campanha ATUAL.
CREATE FUNCTION public.admin_artwork_change_approve_exception(
  p_request_id uuid, p_expected_row_version integer, p_reason text, p_feasibility text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['site_admin'], ARRAY['submitted', 'under_review', 'quoted', 'accepted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  IF (g.r).target_campaign <> 'current_campaign' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exception_not_applicable');
  END IF;
  IF (g.r).exception_approved_by IS NOT NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exception_already_approved');
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 10 OR p_feasibility IS NULL OR length(btrim(p_feasibility)) < 10 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'exception_reason_and_feasibility_required');
  END IF;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, exception_reason = btrim(p_reason),
         exception_feasibility = btrim(p_feasibility), exception_approved_by = auth.uid(),
         exception_approved_at = pg_catalog.now()
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'current_campaign_exception_approved',
    (g.r).status, (g.r).status, 'site_admin',
    pg_catalog.jsonb_build_object('reason', btrim(p_reason), 'feasibility', btrim(p_feasibility)));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', (g.r).status, 'row_version', (g.r).row_version + 1);
END $$;

-- 10. Administrador: autoriza a produção (fim do fluxo implementado).
CREATE FUNCTION public.admin_artwork_change_authorize_production(p_request_id uuid, p_expected_row_version integer)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['site_admin'], ARRAY['accepted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  IF (g.r).target_campaign = 'current_campaign' AND (g.r).exception_approved_by IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'current_campaign_exception_required');
  END IF;
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'production_authorized',
         production_authorized_by = auth.uid(), production_authorized_at = pg_catalog.now()
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'production_authorized', 'accepted',
    'production_authorized', 'site_admin',
    pg_catalog.jsonb_build_object('accepted_quote_id', (g.r).accepted_quote_id,
                                  'accepted_total_cents', (g.r).accepted_total_cents));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'production_authorized',
    'row_version', (g.r).row_version + 1,
    'billing', 'not_available', 'production_dispatch', 'not_available');
END $$;

-- 11. Administrador: recusa.
CREATE FUNCTION public.admin_artwork_change_reject(p_request_id uuid, p_expected_row_version integer, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE g record;
BEGIN
  SELECT * INTO g FROM public.commercial_artwork_change_gate(p_request_id, p_expected_row_version,
    ARRAY['site_admin'], ARRAY['submitted', 'under_review', 'quoted', 'accepted']);
  IF g.refusal IS NOT NULL THEN RETURN g.refusal; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'reason_required');
  END IF;
  UPDATE public.commercial_artwork_change_quotes SET status = 'superseded'
   WHERE request_id = (g.r).id AND status = 'open';
  UPDATE public.commercial_artwork_change_requests
     SET row_version = row_version + 1, status = 'rejected', closed_reason = btrim(p_reason),
         closed_by = auth.uid(), closed_at = pg_catalog.now()
   WHERE id = (g.r).id;
  PERFORM public.commercial_artwork_change_event((g.r).id, 'rejected', (g.r).status, 'rejected', 'site_admin',
    pg_catalog.jsonb_build_object('reason', btrim(p_reason)));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'status', 'rejected', 'row_version', (g.r).row_version + 1);
END $$;

-- 12. Leitura: owner, membro (manager) e administrador.
CREATE FUNCTION public.artwork_change_requests_for_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_o    public.commercial_exclusivity_orders%ROWTYPE;
  v_ator text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  v_ator := public.commercial_artwork_change_actor(v_o.company_id);
  IF v_ator IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'viewer_role', v_ator,
    'can_request', v_ator = 'partner_owner',
    'requests', coalesce((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'request_id', r.id, 'status', r.status, 'row_version', r.row_version,
        'target_campaign', r.target_campaign, 'phrase_text', r.phrase_text,
        'created_at', r.created_at, 'updated_at', r.updated_at,
        'exception_approved', r.exception_approved_by IS NOT NULL,
        'accepted_total_cents', r.accepted_total_cents, 'closed_reason', r.closed_reason,
        'versions', coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'version_id', v.id, 'version_no', v.version_no, 'storage_path', v.storage_path,
            'mime_type', v.mime_type, 'byte_size', v.byte_size, 'sha256', v.sha256,
            'phrase_text', v.phrase_text, 'registered_at', v.registered_at) ORDER BY v.version_no)
          FROM public.commercial_artwork_change_versions v WHERE v.request_id = r.id), '[]'::jsonb),
        'quote', (SELECT pg_catalog.jsonb_build_object(
            'quote_id', q.id, 'quote_no', q.quote_no, 'status', q.status,
            'artwork_version_id', q.artwork_version_id, 'supplier_name', q.supplier_name,
            'supplier_document_reference', q.supplier_document_reference, 'scope', q.scope,
            'pieces_count', q.pieces_count, 'supplier_unit_cost_cents', q.supplier_unit_cost_cents,
            'supplier_total_cents', q.supplier_total_cents, 'partner_charge_cents', q.partner_charge_cents,
            'cap_cents', q.cap_cents, 'excluded_items', pg_catalog.to_jsonb(q.excluded_items))
          FROM public.commercial_artwork_change_quotes q
         WHERE q.request_id = r.id AND q.status IN ('open', 'accepted')
         ORDER BY q.quote_no DESC LIMIT 1))
        ORDER BY r.created_at DESC)
        FROM public.commercial_artwork_change_requests r WHERE r.base_order_id = v_o.id), '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION public.artwork_change_request_create(uuid, text, text, text),
                       public.artwork_change_image_path(uuid),
                       public.artwork_change_register_version(uuid, integer, text, text, text),
                       public.artwork_change_submit(uuid, integer),
                       public.artwork_change_accept_quote(uuid, integer, uuid, bigint),
                       public.artwork_change_cancel(uuid, integer, text),
                       public.admin_artwork_change_start_review(uuid, integer),
                       public.admin_artwork_change_register_quote(uuid, integer, text, text, text, text, integer, bigint, bigint, bigint),
                       public.admin_artwork_change_approve_exception(uuid, integer, text, text),
                       public.admin_artwork_change_authorize_production(uuid, integer),
                       public.admin_artwork_change_reject(uuid, integer, text),
                       public.artwork_change_requests_for_order(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.artwork_change_request_create(uuid, text, text, text),
                          public.artwork_change_image_path(uuid),
                          public.artwork_change_register_version(uuid, integer, text, text, text),
                          public.artwork_change_submit(uuid, integer),
                          public.artwork_change_accept_quote(uuid, integer, uuid, bigint),
                          public.artwork_change_cancel(uuid, integer, text),
                          public.admin_artwork_change_start_review(uuid, integer),
                          public.admin_artwork_change_register_quote(uuid, integer, text, text, text, text, integer, bigint, bigint, bigint),
                          public.admin_artwork_change_approve_exception(uuid, integer, text, text),
                          public.admin_artwork_change_authorize_production(uuid, integer),
                          public.admin_artwork_change_reject(uuid, integer, text),
                          public.artwork_change_requests_for_order(uuid)
  TO authenticated;

-- ===========================================================================
-- C. FIDELIDADE != REUTILIZAÇÃO (decisão B)
--    O pedido/intenção fidelizado registra QUAL fato substitui a produção de
--    84 peças no preço: reutilização verificada (como antes) OU alteração de
--    arte com produção autorizada para a próxima campanha. Em nenhum dos dois
--    casos o preço-base, os participantes ou a QA mudam; a produção da nova
--    arte é rubrica separada (orçamento aceito na solicitação).
-- ===========================================================================
ALTER TABLE public.commercial_checkout_intents
  ADD COLUMN artwork_change_request_id uuid REFERENCES public.commercial_artwork_change_requests(id);
ALTER TABLE public.commercial_exclusivity_orders
  ADD COLUMN artwork_change_request_id uuid REFERENCES public.commercial_artwork_change_requests(id);
COMMENT ON COLUMN public.commercial_exclusivity_orders.artwork_change_request_id IS
  'R4.2: renovacao fidelizada SEM reutilizacao das bandeiras antigas, por alteracao voluntaria de arte com '
  'producao autorizada (rubrica separada, custo do fornecedor sem margem). Preco-base fidelizado inalterado.';

ALTER TABLE public.commercial_checkout_intents DROP CONSTRAINT cci_bandeiras_coerente;
ALTER TABLE public.commercial_checkout_intents ADD CONSTRAINT cci_bandeiras_coerente CHECK (
  ((flag_production_new_units IS NULL) AND (flag_unit_reference_cents IS NULL)
   AND (flag_production_charge_cents IS NULL) AND (flag_reuse_set_id IS NULL)
   AND (flag_reuse_inspection_id IS NULL) AND (artwork_change_request_id IS NULL))
  OR ((NOT fidelized) AND (flag_production_new_units > 0) AND (flag_unit_reference_cents > 0)
   AND (flag_production_charge_cents = (flag_production_new_units * flag_unit_reference_cents))
   AND (flag_production_charge_cents <= smallflags_main_fee_cents)
   AND (flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)
   AND (artwork_change_request_id IS NULL))
  OR (fidelized AND (flag_production_new_units = 0) AND (flag_unit_reference_cents > 0)
   AND (flag_production_charge_cents = 0)
   AND (((flag_reuse_set_id IS NOT NULL) AND (flag_reuse_inspection_id IS NOT NULL)
         AND (artwork_change_request_id IS NULL))
     OR ((flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)
         AND (artwork_change_request_id IS NOT NULL)))));
ALTER TABLE public.commercial_exclusivity_orders DROP CONSTRAINT ceo_bandeiras_coerente;
ALTER TABLE public.commercial_exclusivity_orders ADD CONSTRAINT ceo_bandeiras_coerente CHECK (
  ((flag_production_new_units IS NULL) AND (flag_unit_reference_cents IS NULL)
   AND (flag_production_charge_cents IS NULL) AND (flag_reuse_set_id IS NULL)
   AND (flag_reuse_inspection_id IS NULL) AND (artwork_change_request_id IS NULL))
  OR ((NOT fidelized) AND (flag_production_new_units > 0) AND (flag_unit_reference_cents > 0)
   AND (flag_production_charge_cents = (flag_production_new_units * flag_unit_reference_cents))
   AND (flag_production_charge_cents <= smallflags_main_fee_cents)
   AND (flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)
   AND (artwork_change_request_id IS NULL))
  OR (fidelized AND (flag_production_new_units = 0) AND (flag_unit_reference_cents > 0)
   AND (flag_production_charge_cents = 0)
   AND (((flag_reuse_set_id IS NOT NULL) AND (flag_reuse_inspection_id IS NOT NULL)
         AND (artwork_change_request_id IS NULL))
     OR ((flag_reuse_set_id IS NULL) AND (flag_reuse_inspection_id IS NULL)
         AND (artwork_change_request_id IS NOT NULL)))));

-- Uma alteração autorizada serve a UMA renovação.
CREATE UNIQUE INDEX ceo_alteracao_arte_unica_idx
  ON public.commercial_exclusivity_orders (artwork_change_request_id)
  WHERE artwork_change_request_id IS NOT NULL AND status <> 'cancelled';

-- Alteração com produção autorizada para a PRÓXIMA campanha, da mesma
-- empresa e identidade, ainda não usada por pedido vivo.
CREATE FUNCTION public.commercial_artwork_change_for_renewal(p_company_id uuid, p_fidelity_identity text)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT r.id
    FROM public.commercial_artwork_change_requests r
   WHERE r.company_id = p_company_id
     AND r.fidelity_identity = p_fidelity_identity
     AND r.status = 'production_authorized'
     AND r.target_campaign = 'next_campaign'
     AND NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                      WHERE o.artwork_change_request_id = r.id AND o.status <> 'cancelled')
   ORDER BY r.production_authorized_at DESC, r.id
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.commercial_artwork_change_for_renewal(uuid, text) FROM PUBLIC, anon, authenticated, service_role;

-- C.2 Resolução nos gatilhos guardados (mudam o manifesto: R4.2)
CREATE OR REPLACE FUNCTION public.cci_validar_producao_bandeiras()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_status text;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_r      jsonb;
  v_arte   uuid;
BEGIN
  SELECT status INTO v_status FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_status = 'prepared' THEN
    RAISE EXCEPTION 'pricing_rule_not_published: versao % ainda nao e vigente', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.pricing_rule_version IS NOT NULL AND NEW.pricing_rule_version >= 3 THEN
    SELECT * INTO v_sched FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = NEW.pricing_rule_version
       AND commercial_category = CASE WHEN NEW.niche_code = 'supermarket'
                                      THEN 'supermarket' ELSE 'common' END
       AND fidelized = NEW.fidelized;
  END IF;

  -- Economia sem produção de bandeiras: nenhum fato de produção é aceito.
  IF v_sched.new_flag_units IS NULL THEN
    NEW.flag_production_new_units    := NULL;
    NEW.flag_unit_reference_cents    := NULL;
    NEW.flag_production_charge_cents := NULL;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  IF NOT NEW.fidelized THEN
    NEW.flag_production_new_units    := v_sched.new_flag_units;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_sched.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  -- R4.2 (decisão B): alteração voluntária de arte com produção AUTORIZADA
  -- para a próxima campanha substitui a reutilização das bandeiras antigas.
  -- Preço-base, participantes e QA fidelizados não mudam; a produção da nova
  -- arte é rubrica separada (orçamento aceito na solicitação).
  v_arte := public.commercial_artwork_change_for_renewal(NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF v_arte IS NOT NULL THEN
    NEW.flag_production_new_units    := 0;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := 0;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := v_arte;
    RETURN NEW;
  END IF;

  v_r := public.commercial_flag_reuse_resolution(
           NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF (v_r->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '%: %', v_r->>'reason', v_r->>'detail'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.flag_production_new_units    := 0;
  NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
  NEW.flag_production_charge_cents := 0;
  NEW.flag_reuse_set_id            := (v_r->>'flag_set_id')::uuid;
  NEW.flag_reuse_inspection_id     := (v_r->>'inspection_id')::uuid;
  NEW.artwork_change_request_id    := NULL;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.ceo_validar_producao_bandeiras()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_status text;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_i      public.commercial_checkout_intents%ROWTYPE;
  v_r      jsonb;
  v_arte   uuid;
BEGIN
  SELECT status INTO v_status FROM public.commercial_pricing_rules
   WHERE version = NEW.pricing_rule_version;
  IF v_status = 'prepared' THEN
    RAISE EXCEPTION 'pricing_rule_not_published: versao % ainda nao e vigente', NEW.pricing_rule_version
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.pricing_rule_version IS NOT NULL AND NEW.pricing_rule_version >= 3 THEN
    SELECT * INTO v_sched FROM public.commercial_pricing_schedule
     WHERE pricing_rule_version = NEW.pricing_rule_version
       AND commercial_category = CASE WHEN NEW.niche_code = 'supermarket'
                                      THEN 'supermarket' ELSE 'common' END
       AND fidelized = NEW.fidelized;
  END IF;

  IF v_sched.new_flag_units IS NULL THEN
    NEW.flag_production_new_units    := NULL;
    NEW.flag_unit_reference_cents    := NULL;
    NEW.flag_production_charge_cents := NULL;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  -- Pedido vindo de intenção: CÓPIA do que a reserva congelou.
  IF NEW.checkout_intent_id IS NOT NULL THEN
    SELECT * INTO v_i FROM public.commercial_checkout_intents WHERE id = NEW.checkout_intent_id;
    IF NOT FOUND
       OR v_i.pricing_rule_version IS DISTINCT FROM NEW.pricing_rule_version
       OR v_i.fidelized IS DISTINCT FROM NEW.fidelized
       OR v_i.flag_production_new_units IS NULL THEN
      RAISE EXCEPTION 'flag_production_snapshot_divergente: intencao sem fatos de producao coerentes'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.flag_production_new_units    := v_i.flag_production_new_units;
    NEW.flag_unit_reference_cents    := v_i.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_i.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := v_i.flag_reuse_set_id;
    NEW.flag_reuse_inspection_id     := v_i.flag_reuse_inspection_id;
    NEW.artwork_change_request_id    := v_i.artwork_change_request_id;
    RETURN NEW;
  END IF;

  -- Venda manual: mesma autoridade da intenção.
  IF NOT NEW.fidelized THEN
    NEW.flag_production_new_units    := v_sched.new_flag_units;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := v_sched.flag_production_charge_cents;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := NULL;
    RETURN NEW;
  END IF;

  -- R4.2 (decisão B): alteração voluntária de arte com produção AUTORIZADA
  -- para a próxima campanha substitui a reutilização das bandeiras antigas.
  -- Preço-base, participantes e QA fidelizados não mudam; a produção da nova
  -- arte é rubrica separada (orçamento aceito na solicitação).
  v_arte := public.commercial_artwork_change_for_renewal(NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF v_arte IS NOT NULL THEN
    NEW.flag_production_new_units    := 0;
    NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
    NEW.flag_production_charge_cents := 0;
    NEW.flag_reuse_set_id            := NULL;
    NEW.flag_reuse_inspection_id     := NULL;
    NEW.artwork_change_request_id    := v_arte;
    RETURN NEW;
  END IF;

  v_r := public.commercial_flag_reuse_resolution(
           NEW.company_id,
           CASE WHEN NEW.segment_classification_snapshot IS NOT NULL
                THEN 'segment:' || NEW.segment_classification_snapshot
                ELSE NEW.niche_code END);
  IF (v_r->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '%: %', v_r->>'reason', v_r->>'detail'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.flag_production_new_units    := 0;
  NEW.flag_unit_reference_cents    := v_sched.flag_unit_reference_cents;
  NEW.flag_production_charge_cents := 0;
  NEW.flag_reuse_set_id            := (v_r->>'flag_set_id')::uuid;
  NEW.flag_reuse_inspection_id     := (v_r->>'inspection_id')::uuid;
  NEW.artwork_change_request_id    := NULL;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.commercial_flag_facts_imutaveis()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF NEW.flag_production_new_units    IS DISTINCT FROM OLD.flag_production_new_units
  OR NEW.flag_unit_reference_cents    IS DISTINCT FROM OLD.flag_unit_reference_cents
  OR NEW.flag_production_charge_cents IS DISTINCT FROM OLD.flag_production_charge_cents
  OR NEW.flag_reuse_set_id            IS DISTINCT FROM OLD.flag_reuse_set_id
  OR NEW.flag_reuse_inspection_id     IS DISTINCT FROM OLD.flag_reuse_inspection_id
  OR NEW.artwork_change_request_id    IS DISTINCT FROM OLD.artwork_change_request_id THEN
    RAISE EXCEPTION 'pedido_imutavel: fatos de producao de bandeiras sao imutaveis (%, id=%)',
      TG_TABLE_NAME, OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $function$;

-- C.3 Reserva: a mesma regra antes de tocar na oportunidade
CREATE OR REPLACE FUNCTION public.create_commercial_checkout_intent(p_company_id uuid, p_niche_code text, p_benefit_settlement_mode text, p_segment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_eleg jsonb;
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
  v_seg      jsonb;
  v_reuso    jsonb;
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


  -- P0-1 PORTAO 1 de 4: elegibilidade do Acordo Mestre pela definicao UNICA.
  -- Falha CEDO: sem Mestre elegivel a empresa nao segura oportunidade escassa
  -- por 30 minutos nem gera aceite que jamais podera ser finalizado.
  v_eleg := public.m2_master_agreement_eligibility(p_company_id);
  IF (v_eleg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_eleg;
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

  IF EXISTS (
    SELECT 1
      FROM public.commercial_exclusivity_orders o
     WHERE o.exclusivity_id = v_excl
       AND o.company_id = p_company_id
       AND o.status <> 'cancelled'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'company_already_contracted_in_exclusivity');
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

  -- ---- posição × segmento: Supermercado sem segmento, Outros com segmento
  -- aprovado, substituto só em posição elegível, e o segmento ainda livre
  -- nesta exclusividade. Decidido aqui, nunca pelo navegador.
  v_seg := public.commercial_resolve_position_segment(
             p_niche_code, p_segment_id, v_excl, v_opp.id, true);
  IF (v_seg->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_seg;
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
    IF v_viva.segment_id IS DISTINCT FROM p_segment_id THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'reservation_segment_mismatch',
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
               v_company.cnpj, v_company.uf, v_company.city, p_niche_code, p_segment_id);

  v_p := public.calculate_niche_contract_pricing(p_niche_code, v_fidel);
  IF (v_p->>'ok')::boolean IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'pricing_unavailable');
  END IF;

  -- Nicho INTEIRO. A quantidade vem da oportunidade e da regra de preço, que
  -- têm de concordar; divergência é defeito de dados, não venda parcial.
  IF (v_p->>'nominal_quantity')::int <> v_opp.contracted_quantity THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'quantity_mismatch');
  END IF;

  -- ---- SF-v1.5: o preço fidelizado PRESSUPÕE reutilização das bandeiras.
  -- Sem conjunto do mesmo anunciante e da mesma identidade, com inspeção
  -- aprovando todas as peças e ainda não usada, não há reserva nem preço.
  -- Reposição sem política aprovada também não tem preço. Antes de tocar na
  -- oportunidade: nada fica reservado.
  -- R4.2 (decisão B): alteração de arte com produção autorizada para a próxima
  -- campanha substitui a reutilização; a fidelidade não depende das peças.
  IF v_p ? 'new_flag_units' AND v_fidel
     AND public.commercial_artwork_change_for_renewal(
           p_company_id, public.commercial_fidelity_identity(p_niche_code, p_segment_id)) IS NULL THEN
    v_reuso := public.commercial_flag_reuse_resolution(
                 p_company_id,
                 public.commercial_fidelity_identity(p_niche_code, p_segment_id));
    IF (v_reuso->>'ok')::boolean IS NOT TRUE THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', v_reuso->>'reason', 'detail', v_reuso->>'detail');
    END IF;
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
     created_by, segment_id, segment_code_snapshot, segment_name_snapshot,
     segment_classification_snapshot)
  VALUES
    (p_company_id, p_niche_code, 'draft', (v_p->>'pricing_rule_version')::int,
     2, v_fidel, v_p->>'payment_method',
     p_benefit_settlement_mode, 'BRL', (v_p->>'nominal_quantity')::int,
     (v_p->>'economic_value_cents')::bigint, v_pool, v_bdflow,
     v_cash, v_bdflow + v_cash,
     v_opp.id, v_excl, v_region, v_ate,
     v_uid, (v_seg->>'segment_id')::uuid, v_seg->>'segment_code',
     v_seg->>'segment_name', v_seg->>'segment_classification')
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('commercial_checkout.reserved', v_id, 'owner',
    pg_catalog.jsonb_build_object('company_id', p_company_id,
                                  'opportunity_id', v_opp.id,
                                  'niche_code', p_niche_code,
                                  'segment_code', v_seg->>'segment_code',
                                  'segment_classification', v_seg->>'segment_classification',
                                  'reserved_until', v_ate));

  SELECT * INTO v_viva FROM public.commercial_checkout_intents WHERE id = v_id;
  RETURN public.cci_resposta_intencao(v_viva, false);
END;
$function$;

-- ===========================================================================
-- D. IMAGEM DO PEDIDO TRAVADA DEPOIS DA PRODUÇÃO (decisão D)
-- ===========================================================================
CREATE FUNCTION public.commercial_order_artwork_locked(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT EXISTS (SELECT 1 FROM public.commercial_flag_sets s WHERE s.origin_order_id = p_order_id)
      OR EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                  WHERE o.id = p_order_id
                    AND (o.flag_reuse_set_id IS NOT NULL OR o.artwork_change_request_id IS NOT NULL));
$$;
REVOKE ALL ON FUNCTION public.commercial_order_artwork_locked(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.request_customization_image_path(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_ord public.commercial_exclusivity_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;
  SELECT * INTO v_ord FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_ord.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_ord.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;
  -- R4.2 (decisão D): depois que a produção existe (conjunto produzido para
  -- este pedido) ou quando o pedido usa bandeiras existentes/arte alterada, a
  -- imagem não é trocada aqui: a troca é por solicitação de alteração.
  IF public.commercial_order_artwork_locked(p_order_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_locked_use_change_request');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'bucket', 'partner-customization-images',
    -- Sempre um caminho NOVO: reenvio nunca sobrescreve objeto anterior.
    'storage_path', p_order_id::text || '/' ||
                    pg_catalog.replace(gen_random_uuid()::text, '-', ''));
END;
$$;

CREATE OR REPLACE FUNCTION public.register_customization_image(
  p_order_id     uuid,
  p_storage_path text,
  p_mime_type    text DEFAULT NULL,
  p_byte_size    bigint DEFAULT NULL,
  p_checksum     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_ord  public.commercial_exclusivity_orders%ROWTYPE;
  v_obj  storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
  v_id   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_ord FROM public.commercial_exclusivity_orders
   WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;
  IF NOT (public.m2_is_company_owner(v_ord.company_id) OR public.is_site_admin()) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;
  IF v_ord.status = 'cancelled' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_cancelled');
  END IF;
  -- R4.2 (decisão D): depois que a produção existe (conjunto produzido para
  -- este pedido) ou quando o pedido usa bandeiras existentes/arte alterada, a
  -- imagem não é trocada aqui: a troca é por solicitação de alteração.
  IF public.commercial_order_artwork_locked(p_order_id) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'artwork_locked_use_change_request');
  END IF;

  -- O caminho é preso ao pedido: nada de path arbitrário do navegador.
  IF p_storage_path IS NULL OR p_storage_path NOT LIKE (p_order_id::text || '/%') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_path');
  END IF;

  -- O objeto precisa EXISTIR no Storage.
  SELECT * INTO v_obj FROM storage.objects o
   WHERE o.bucket_id = 'partner-customization-images' AND o.name = p_storage_path;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_found');
  END IF;
  IF v_obj.owner IS NOT NULL AND v_obj.owner <> v_uid THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'storage_object_not_owned');
  END IF;

  -- MIME e tamanho AUTORITATIVOS do Storage; o cliente é apenas fallback.
  v_size := coalesce((v_obj.metadata->>'size')::bigint, p_byte_size);
  v_mime := coalesce(nullif(v_obj.metadata->>'mimetype',''), p_mime_type);
  IF v_size IS NULL OR v_mime IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_metadata');
  END IF;
  IF v_mime NOT IN ('image/jpeg','image/png','image/webp') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_mime');
  END IF;
  IF v_size <= 0 OR v_size > 10485760 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid_size');
  END IF;

  -- Substituição: a versão anterior vira histórico (append-only).
  UPDATE public.commercial_order_customization_images
     SET is_current = false, status = 'replaced', replaced_at = pg_catalog.now()
   WHERE order_id = p_order_id AND is_current;

  INSERT INTO public.commercial_order_customization_images
    (order_id, storage_path, mime_type, byte_size, checksum, registered_by)
  VALUES (p_order_id, p_storage_path, v_mime, v_size,
          nullif(pg_catalog.btrim(coalesce(p_checksum,'')), ''), v_uid)
  RETURNING id INTO v_id;

  PERFORM public.m1_auditar('order_customization_image.registered', p_order_id, 'owner',
    pg_catalog.jsonb_build_object('image_id', v_id, 'mime_type', v_mime,
                                  'byte_size', v_size));

  RETURN pg_catalog.jsonb_build_object('ok', true, 'image_id', v_id,
                                       'mime_type', v_mime, 'byte_size', v_size);
END;
$$;

-- ===========================================================================
-- E. MANIFESTO APROVADO R4.2 — docs/release/R42_MANIFESTO_GUARDAS.json
--    (SHA-256 155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246). Muda em relação ao R4.1 só o que esta migration
--    altera: cci_validar_producao_bandeiras, ceo_validar_producao_bandeiras e
--    commercial_flag_facts_imutaveis. O R4.1 permanece como linha histórica.
-- ===========================================================================
INSERT INTO public.commercial_guard_manifests (manifest_label, catalog, source_reference)
VALUES ('R4.2', $manifesto_r42${"format": "smallflags-guard-catalog/1 (R4.1, sha256)", "tables": [{"table": "public.commercial_checkout_intents", "present": true}, {"table": "public.commercial_exclusivity_orders", "present": true}, {"table": "public.commercial_flag_set_inspections", "present": true}, {"table": "public.commercial_flag_sets", "present": true}, {"table": "public.commercial_guard_manifests", "present": true}, {"table": "public.commercial_instrument_template_approvals", "present": true}, {"table": "public.commercial_payments", "present": true}, {"table": "public.commercial_pricing_activation_approvals", "present": true}, {"table": "public.commercial_pricing_activation_log", "present": true}, {"table": "public.commercial_pricing_rules", "present": true}, {"table": "public.commercial_pricing_schedule", "present": true}, {"table": "public.commercial_qa_operational_procedures", "present": true}, {"table": "public.commercial_settlement_terms", "present": true}], "triggers": {"public.commercial_flag_sets.cfs_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_flag_sets_protect()", "deferrable": false, "definition": "CREATE TRIGGER cfs_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_flag_sets FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_sets_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "2690264d59ff4dcb2b76e2e13059b8de8f7a7f474d2a256ba426b665fc817626", "definition_sha256": "d7cd3099ed10f7b31ea2d47f792af9d1690504e1154a997b9dde56edf6bd848b", "initially_deferred": false}, "public.commercial_payments.trg_cp_touch": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.fase2a_touch_updated_at()", "deferrable": false, "definition": "CREATE TRIGGER trg_cp_touch BEFORE UPDATE ON public.commercial_payments FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "f0fd417ae71a52338a298bf853ce507a8bc036c54c4f14cfea417ffffb7abc8f", "definition_sha256": "61b182d54029d5ebd2d91dfe1ae7abc80e1afc974323bb7180cabdb2bc6b604d", "initially_deferred": false}, "public.commercial_payments.trg_cp_proteger": {"when": null, "state": "O", "tgtype": 27, "columns": "", "function": "public.cp_proteger()", "deferrable": false, "definition": "CREATE TRIGGER trg_cp_proteger BEFORE DELETE OR UPDATE ON public.commercial_payments FOR EACH ROW EXECUTE FUNCTION public.cp_proteger()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "4f74486afa623f948f78ff3a90c8301892aed7da6e769c4a8d8c8e213d0f27be", "definition_sha256": "e6299f3b45f6c28dd9491915580a6f6d4d979a4a18f28dc232fe6a2312a4ae7f", "initially_deferred": false}, "public.commercial_pricing_rules.cpr_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_pricing_rules_protect()", "deferrable": false, "definition": "CREATE TRIGGER cpr_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_pricing_rules FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_rules_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "dcf4da0f184fe75d5919610690b0331d60b7c3145addd4d663a24ff4f6f31146", "definition_sha256": "b4aa3089c0860976b792a242dd2e300c8620cad898bdbc473ceec950cefca990", "initially_deferred": false}, "public.commercial_guard_manifests.cgm_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_guard_manifests_protect()", "deferrable": false, "definition": "CREATE TRIGGER cgm_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_guard_manifests FOR EACH ROW EXECUTE FUNCTION public.commercial_guard_manifests_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bc270768c7a81a5923a3bc1d303253925e1765e27540bf26b8618222d16b916e", "definition_sha256": "fc0ea03fced5b0738eed71512ebc1ef291d7a1ed2766bacf3a2d7364e21145b1", "initially_deferred": false}, "public.commercial_pricing_schedule.cps_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_pricing_schedule_protect()", "deferrable": false, "definition": "CREATE TRIGGER cps_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_pricing_schedule FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_schedule_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "334a31ec2adb96c33c47f422ab3a85a736ad18221dc55a1a99dec9811a8fc041", "definition_sha256": "b5e464973ac583f9d65585baaa82799341c4d54eaad6248466531244333e42a6", "initially_deferred": false}, "public.commercial_settlement_terms.cst_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_settlement_terms_protect()", "deferrable": false, "definition": "CREATE TRIGGER cst_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_settlement_terms FOR EACH ROW EXECUTE FUNCTION public.commercial_settlement_terms_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "3a5c45565bec15feeaa7863a01015351f1638acbe2bd77a882960c56a2d00da2", "definition_sha256": "da68b0fe1a20e56776f08a2a3e3d7f188db6861b6e32f2b465e22dc55100cdb7", "initially_deferred": false}, "public.commercial_flag_sets.cfs_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_flag_inventory_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cfs_protect_truncate BEFORE TRUNCATE ON public.commercial_flag_sets FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_flag_inventory_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bb12a8f32a55d6e71a5971e089e8756e9b2e86ddf007c999ea73076d1fe7baf4", "definition_sha256": "19bd053108da69913fa618a37e798e0fe21fbf2234ea75cc465ff9058cf4ba81", "initially_deferred": false}, "public.commercial_exclusivity_orders.trg_ceo_touch": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.fase2a_touch_updated_at()", "deferrable": false, "definition": "CREATE TRIGGER trg_ceo_touch BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "f0fd417ae71a52338a298bf853ce507a8bc036c54c4f14cfea417ffffb7abc8f", "definition_sha256": "563bc51d7a8a6bf51168d2b2580dcb6bdf86f1adf6b7d22c85748076aaedf5e7", "initially_deferred": false}, "public.commercial_flag_set_inspections.cfi_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_flag_set_inspections_protect()", "deferrable": false, "definition": "CREATE TRIGGER cfi_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_flag_set_inspections FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_set_inspections_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "da606f958f5af26fdf2b0ce9ba2d45aa2056aa76d9f7b9e641bc97e2b3e58932", "definition_sha256": "5dcde04f40a706b69419c37b0b0e5d3ea5d91f6c6793a2028630b3c871011726", "initially_deferred": false}, "public.commercial_payments.cp_valor_confere_pedido": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cp_valor_confere_pedido()", "deferrable": false, "definition": "CREATE TRIGGER cp_valor_confere_pedido BEFORE INSERT ON public.commercial_payments FOR EACH ROW EXECUTE FUNCTION public.cp_valor_confere_pedido()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "8aa0dccba55b27866c768dd03fbf8d8e3b03d72af60de9a8058094a2bbf61c28", "definition_sha256": "65dced9887329d202bfec38886491be8ac81797b041ebf2d8ad3d8a037677f5c", "initially_deferred": false}, "public.commercial_exclusivity_orders.trg_ceo_protect": {"when": null, "state": "O", "tgtype": 27, "columns": "", "function": "public.m2_orders_protect()", "deferrable": false, "definition": "CREATE TRIGGER trg_ceo_protect BEFORE DELETE OR UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.m2_orders_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "760f2f2de477e05f7d735d87cf49773ff3833347bfcb2b5a12cb3f160fb1f89f", "definition_sha256": "58b552a3c0a00efa697f439c30492979a23290b0c77938456b54a1bf36cec7bd", "initially_deferred": false}, "public.commercial_pricing_rules.cpr_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cpr_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_rules FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "5ac37ebab8b0edc8ae8ffc5decf8710e4f6b08b62136b80060c7874e4477cb8e", "initially_deferred": false}, "public.commercial_pricing_activation_log.cpal_protect": {"when": null, "state": "O", "tgtype": 27, "columns": "", "function": "public.commercial_pricing_activation_log_protect()", "deferrable": false, "definition": "CREATE TRIGGER cpal_protect BEFORE DELETE OR UPDATE ON public.commercial_pricing_activation_log FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_log_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "14f69adce2ca6f8db8aeff765f2586090c7915b493ef22607b4cd16e6d3ce76f", "definition_sha256": "8a2cd7c2fa9b6a526ab177710d8a6e47362162b459daffcacca1e40b9c7ad908", "initially_deferred": false}, "public.commercial_checkout_intents.cci_preencher_fatos": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_preencher_fatos_materiais()", "deferrable": false, "definition": "CREATE TRIGGER cci_preencher_fatos BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_preencher_fatos_materiais()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "e8f11915eee4edce7f485b10659a3b55e3648ec49456a5f98cd4a2d345307a2b", "definition_sha256": "4eb75e7db1801bef5f3eee45ab10a784a44f3ff701d082ce4d2c118cb66493ea", "initially_deferred": false}, "public.commercial_guard_manifests.cgm_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cgm_protect_truncate BEFORE TRUNCATE ON public.commercial_guard_manifests FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "e4e5c71d6746a5bb0ba5b58fdff3af610476f53f1a67c55ce797f0906e9148a6", "initially_deferred": false}, "public.commercial_pricing_schedule.cps_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cps_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_schedule FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "6633728ebde5056762302b66ff4f6b145f20b34b6e8a3e2cc194329f504e3632", "initially_deferred": false}, "public.commercial_settlement_terms.cst_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cst_protect_truncate BEFORE TRUNCATE ON public.commercial_settlement_terms FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "33a5d29ca46da23a1b977d44cb55ab9444291cade69880187f8a2ca63cfbfa4f", "initially_deferred": false}, "public.commercial_checkout_intents.cci_segmento_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_segment_snapshot_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER cci_segmento_imutavel BEFORE UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "044adf339fe704030567db9f03719eb1546c7f716c49930cb69816923be555a9", "definition_sha256": "092bf8d532482a93d8723d2cd5f5c637e772154eb7fd959e55235f0d30cd3ce3", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_preencher_fatos": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_preencher_fatos_materiais()", "deferrable": false, "definition": "CREATE TRIGGER ceo_preencher_fatos BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_preencher_fatos_materiais()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "4ec5ce9bd2913a981fd30937ee7765d8081db0afd844a92e1c2160ec13cfb972", "definition_sha256": "2b28b94bff75e42db350d501b02a3b7e837ad291e10c67455753e288a40cb5e4", "initially_deferred": false}, "public.commercial_qa_operational_procedures.cqop_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_qa_operational_procedures_protect()", "deferrable": false, "definition": "CREATE TRIGGER cqop_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_qa_operational_procedures FOR EACH ROW EXECUTE FUNCTION public.commercial_qa_operational_procedures_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "86436f51ea9a9a189569ac28e5980cd0074eb12cb75bf892bad96206fb80a591", "definition_sha256": "62aaf291f5148b0dc0ae32e74415441ac2ec1e31a82f6e21973614f0c0495311", "initially_deferred": false}, "public.commercial_checkout_intents.cci_bandeiras_imutaveis": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_flag_facts_imutaveis()", "deferrable": false, "definition": "CREATE TRIGGER cci_bandeiras_imutaveis BEFORE UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_facts_imutaveis()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "133b41d9abe71ee744c00f877e5e80bafc5307b6bcab95f6e7ad6b4d8a70d070", "definition_sha256": "081aad32c1ed444a205ec4c43a002d6a71a16fdedd4a20889fce477f22c93b85", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_segmento_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_segment_snapshot_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_segmento_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "044adf339fe704030567db9f03719eb1546c7f716c49930cb69816923be555a9", "definition_sha256": "a97532e32009ae2e02e7f429e232e371902c282cd4e144ed3106ac372580aaf6", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_emitir_instrumento": {"when": null, "state": "O", "tgtype": 5, "columns": "", "function": "public.ceo_emitir_instrumento()", "deferrable": false, "definition": "CREATE TRIGGER ceo_emitir_instrumento AFTER INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_emitir_instrumento()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "722fce1aeab8bc66225a7bef9556fe38d308e9478a0eb3ea3649224345897ae7", "definition_sha256": "cb1564e9f602799017054547d8b3c157761491755bc6017940d960669ed5e177", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_exigir_instrumento": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_exigir_instrumento_quando_assinavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_exigir_instrumento BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_exigir_instrumento_quando_assinavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "26f7000b7047e0a52eaa701d53cd09e2e351cd4a87d59c5af5c98702196e8308", "definition_sha256": "afed0e0d33d4379e5e1ceb589aecc7225e12723cd63a09fe7315d793ec16f07e", "initially_deferred": false}, "public.commercial_flag_set_inspections.cfi_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_flag_inventory_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cfi_protect_truncate BEFORE TRUNCATE ON public.commercial_flag_set_inspections FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_flag_inventory_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bb12a8f32a55d6e71a5971e089e8756e9b2e86ddf007c999ea73076d1fe7baf4", "definition_sha256": "6a342d851c3f5982542f5e63090acbe944c24ddee180731074fd8bb43308acfe", "initially_deferred": false}, "public.commercial_pricing_activation_approvals.cpaa_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_pricing_activation_approvals_protect()", "deferrable": false, "definition": "CREATE TRIGGER cpaa_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_pricing_activation_approvals FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_approvals_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "131059cb96fbcb894a09cb3e551282b9b5144d4c793f4150029afa1e7f71da27", "definition_sha256": "dc5099952532325cd2ee6347f8b9af9f4de20199d2ec291a8b2a2f1a3ee3982a", "initially_deferred": false}, "public.commercial_checkout_intents.cci_proteger_snapshot_trg": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.cci_proteger_snapshot()", "deferrable": false, "definition": "CREATE TRIGGER cci_proteger_snapshot_trg BEFORE UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_proteger_snapshot()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "fdb064d35ad871f0071b8d0d4f9d99d080ae1f09826f68ad4e86d9fee412ab40", "definition_sha256": "68427d6a4f344d8eaae271acb39819d48fc451a900005af8a1ff82203030b585", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_bandeiras_imutaveis": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_flag_facts_imutaveis()", "deferrable": false, "definition": "CREATE TRIGGER ceo_bandeiras_imutaveis BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_facts_imutaveis()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "133b41d9abe71ee744c00f877e5e80bafc5307b6bcab95f6e7ad6b4d8a70d070", "definition_sha256": "48d0c9cd0a2251cb20181a0ffb79277c54f7e261cfe0ac7679f07a631d34b997", "initially_deferred": false}, "public.commercial_flag_set_inspections.cfi_bloquear_conjunto": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.commercial_flag_set_lock_for_inspection()", "deferrable": false, "definition": "CREATE TRIGGER cfi_bloquear_conjunto BEFORE INSERT ON public.commercial_flag_set_inspections FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_set_lock_for_inspection()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "2271272d240a23dcd3007c6b7ce742459afb326d1102433995df2b4142301674", "definition_sha256": "a623c8387cf050cc6bfca4f318f92d3571c346bac0eb10216c0eff1ec0916218", "initially_deferred": false}, "public.commercial_checkout_intents.cci_aplicar_autoridade_v14": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_aplicar_autoridade_v14()", "deferrable": false, "definition": "CREATE TRIGGER cci_aplicar_autoridade_v14 BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_aplicar_autoridade_v14()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "d71265048360c982d951e77de2830fd3d23e0c97929b57605d1d4faa3a909f90", "definition_sha256": "a1421ae18d7ff1efcf4d66a74a71086aa412c8281905c4c7dda4eae085adcb67", "initially_deferred": false}, "public.commercial_checkout_intents.cci_portao_autoatendimento": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_portao_autoatendimento()", "deferrable": false, "definition": "CREATE TRIGGER cci_portao_autoatendimento BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_portao_autoatendimento()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "55f3678fdd292f426142f8a31fc8a49c023312b025bd1478251ea86756f52ae1", "definition_sha256": "79adddb7c04966063432e3d8575d14a437f84500a23a7ccb97cb01406da901a7", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_instrumento_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.ceo_instrumento_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_instrumento_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_instrumento_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bfdcb2188b8757ec8b4e55d40db7eef435f9e8456575343eb8e4e455981dea0d", "definition_sha256": "f78c4e15a45d01b052d372ef8c1327dfb0f3a41ba813f0724c9b0f24744ba7a5", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_segmento_da_intencao": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_segmento_da_intencao()", "deferrable": false, "definition": "CREATE TRIGGER ceo_segmento_da_intencao BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_segmento_da_intencao()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "a544f81886260476dfec5995d3ec1215bbc17e541042c21ba4492607e4657df8", "definition_sha256": "71938d7bced8dbc77639420a0373eb5b258c5b9bc2b33e96ab40ff86e237c9b2", "initially_deferred": false}, "public.commercial_exclusivity_orders.trg_ceo_origem_pagamento": {"when": null, "state": "O", "tgtype": 23, "columns": "", "function": "public.ceo_marcar_origem_manual()", "deferrable": false, "definition": "CREATE TRIGGER trg_ceo_origem_pagamento BEFORE INSERT OR UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_marcar_origem_manual()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "c52e0d3ac23ab3c33151edc905b25346d0cf812b412533bcb9dd7bd574ff9086", "definition_sha256": "77895cf9ce3d11af7c0312ab6ac8e595722e91072bc931da4d3f3b4a1eb9e777", "initially_deferred": false}, "public.commercial_instrument_template_approvals.citap_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_instrument_template_approvals_protect()", "deferrable": false, "definition": "CREATE TRIGGER citap_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_instrument_template_approvals FOR EACH ROW EXECUTE FUNCTION public.commercial_instrument_template_approvals_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "c77e8e880308a73f9f6ee9751e501c189b1226539b56f8278c2328af0abb803e", "definition_sha256": "d8d67c88181ba5672a4ee1bf1e5b15236028b1c5d4e8764cbb7417b80cb5cb45", "initially_deferred": false}, "public.commercial_checkout_intents.cci_liquidar_modalidade_v15": {"when": null, "state": "O", "tgtype": 23, "columns": "", "function": "public.cci_liquidar_modalidade_v15()", "deferrable": false, "definition": "CREATE TRIGGER cci_liquidar_modalidade_v15 BEFORE INSERT OR UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_liquidar_modalidade_v15()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "0bdce46677c0c4047c97f1ac0d8db2696b7eeff926a393e393a07fd49f4ab909", "definition_sha256": "4f99069e57b8738572a7c3c1a5cfb6749c2787c24a040241392b5f817918d32f", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_snapshot_v14_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.ceo_snapshot_v14_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_snapshot_v14_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_snapshot_v14_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "5c68326fdceca35d2fe6f5e573e6c677e7560d6b59289fd02db5324d7a21a4e7", "definition_sha256": "4764bf11bfe33265cc07c405c4cc4127e3d554f164de50965561a2396e706678", "initially_deferred": false}, "public.commercial_pricing_activation_log.cpal_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cpal_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_activation_log FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "3d7a811c361d8583b8643363348fa7663c799408fa89740984026e0a8fb68185", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_aplicar_autoridade_v14": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_aplicar_autoridade_v14()", "deferrable": false, "definition": "CREATE TRIGGER ceo_aplicar_autoridade_v14 BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_aplicar_autoridade_v14()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "aae838a149a33f7d720406fc023dc2eb2f6ac807507ac8eeab68527564423bb0", "definition_sha256": "47945a7ec8bc97e34feebda0dbf3c022d0b34333260c16e9cc7827175e0b6977", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_liquidacao_v15_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.ceo_liquidacao_v15_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_liquidacao_v15_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_liquidacao_v15_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "69ea27bbd7eac181b8f976f4f74237c96682b4ba2a4674503eb92638e35675e1", "definition_sha256": "bc7f62b342dc0799ff7986c3857060ec05adc36cfca9bd3609c5b8fb10837f49", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_liquidar_modalidade_v15": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_liquidar_modalidade_v15()", "deferrable": false, "definition": "CREATE TRIGGER ceo_liquidar_modalidade_v15 BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_liquidar_modalidade_v15()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b879abd9a8f44d9f497ac6b2601e813a6583bd2428e57b0c4f166a13d2681003", "definition_sha256": "8d86138970115b4bf658d16fa6041989aad9e089d910bd01940f31828037bbf3", "initially_deferred": false}, "public.commercial_checkout_intents.cci_validar_producao_bandeiras": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_validar_producao_bandeiras()", "deferrable": false, "definition": "CREATE TRIGGER cci_validar_producao_bandeiras BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_validar_producao_bandeiras()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bcea4a9bba705b5f0f9692850c116ca359a212f66ee6585b72973c76f6b36a2a", "definition_sha256": "beec37717a26e5671f4aa82ae697cab44339e50622115143579a5a7647335a7d", "initially_deferred": false}, "public.commercial_qa_operational_procedures.cqop_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cqop_protect_truncate BEFORE TRUNCATE ON public.commercial_qa_operational_procedures FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "54dfcd5195584c7f474d1eed88bd6c32edb0ee1dc79ac212420cc00da38a1401", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot": {"when": null, "state": "O", "tgtype": 23, "columns": "", "function": "public.ceo_pagamento_confere_snapshot()", "deferrable": false, "definition": "CREATE TRIGGER ceo_pagamento_confere_snapshot BEFORE INSERT OR UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_pagamento_confere_snapshot()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "44759806656f355ffff3d0f0bcc72f3127ac196b7dd0361f4910beca6b964962", "definition_sha256": "385a7e6b153d7700bc86913f88d6a498eb46b1dd7602ea0dd909fd8c34257d3c", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_validar_producao_bandeiras": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_validar_producao_bandeiras()", "deferrable": false, "definition": "CREATE TRIGGER ceo_validar_producao_bandeiras BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_validar_producao_bandeiras()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "66cfeacb26d51d529fac3329b219e71d154330a3bc5975b1ad4719c528b3a41e", "definition_sha256": "13090adec88f0356015f17a73b044e441e25ed47a0a2b4c0dd1224da0848c00d", "initially_deferred": false}, "public.commercial_pricing_activation_approvals.cpaa_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cpaa_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_activation_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "9f0587c3ec343af7a50674986e2bd4599a6563b2258e40884e73c56667a2e0f6", "initially_deferred": false}, "public.commercial_instrument_template_approvals.citap_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER citap_protect_truncate BEFORE TRUNCATE ON public.commercial_instrument_template_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "69bf7c3e038f1d5fe80dc97f0844f68504ca2f9760d0abb2b615154a3be40605", "initially_deferred": false}, "public.commercial_pricing_activation_log.cpal_somente_pelo_procedimento": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.commercial_pricing_activation_log_guard()", "deferrable": false, "definition": "CREATE TRIGGER cpal_somente_pelo_procedimento BEFORE INSERT ON public.commercial_pricing_activation_log FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_log_guard()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "e35df937f3a0064e62fab1eb576b3c4fea5f75eccd58e05569264931654c8fe2", "definition_sha256": "32359304d51ccb227c25884421d42087a26579f22382264e3bfc29a7c9d61bc7", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_revalidar_reutilizacao_bandeiras": {"when": null, "state": "O", "tgtype": 21, "columns": "23", "function": "public.ceo_revalidar_reutilizacao_bandeiras()", "deferrable": false, "definition": "CREATE TRIGGER ceo_revalidar_reutilizacao_bandeiras AFTER INSERT OR UPDATE OF payment_status ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_revalidar_reutilizacao_bandeiras()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "3e5b9e40d240d9914949ed322ce3b8abdc54f147aa866bc29b6136f75568ddc5", "definition_sha256": "97c03227b4a9bd27fc536217d3971ff0549bc795a22f60257762c2f39d7377c2", "initially_deferred": false}}, "functions": {"public.cp_proteger()": {"definition_sha256": "4f74486afa623f948f78ff3a90c8301892aed7da6e769c4a8d8c8e213d0f27be"}, "public.m2_orders_protect()": {"definition_sha256": "760f2f2de477e05f7d735d87cf49773ff3833347bfcb2b5a12cb3f160fb1f89f"}, "public.cci_proteger_snapshot()": {"definition_sha256": "fdb064d35ad871f0071b8d0d4f9d99d080ae1f09826f68ad4e86d9fee412ab40"}, "public.ceo_emitir_instrumento()": {"definition_sha256": "722fce1aeab8bc66225a7bef9556fe38d308e9478a0eb3ea3649224345897ae7"}, "public.cp_valor_confere_pedido()": {"definition_sha256": "8aa0dccba55b27866c768dd03fbf8d8e3b03d72af60de9a8058094a2bbf61c28"}, "public.fase2a_touch_updated_at()": {"definition_sha256": "f0fd417ae71a52338a298bf853ce507a8bc036c54c4f14cfea417ffffb7abc8f"}, "public.ceo_instrumento_imutavel()": {"definition_sha256": "bfdcb2188b8757ec8b4e55d40db7eef435f9e8456575343eb8e4e455981dea0d"}, "public.ceo_marcar_origem_manual()": {"definition_sha256": "c52e0d3ac23ab3c33151edc905b25346d0cf812b412533bcb9dd7bd574ff9086"}, "public.ceo_segmento_da_intencao()": {"definition_sha256": "a544f81886260476dfec5995d3ec1215bbc17e541042c21ba4492607e4657df8"}, "public.commercial_guard_catalog()": {"execute": ["service_role"], "definition_sha256": "ca9c1bd97cec36a68d1eb3f15e00e2f1de5f9882b96f752cb6c1dee03f395a82"}, "public.ceo_snapshot_v14_imutavel()": {"definition_sha256": "5c68326fdceca35d2fe6f5e573e6c677e7560d6b59289fd02db5324d7a21a4e7"}, "public.cci_aplicar_autoridade_v14()": {"definition_sha256": "d71265048360c982d951e77de2830fd3d23e0c97929b57605d1d4faa3a909f90"}, "public.cci_portao_autoatendimento()": {"definition_sha256": "55f3678fdd292f426142f8a31fc8a49c023312b025bd1478251ea86756f52ae1"}, "public.ceo_aplicar_autoridade_v14()": {"definition_sha256": "aae838a149a33f7d720406fc023dc2eb2f6ac807507ac8eeab68527564423bb0"}, "public.cci_liquidar_modalidade_v15()": {"definition_sha256": "0bdce46677c0c4047c97f1ac0d8db2696b7eeff926a393e393a07fd49f4ab909"}, "public.ceo_liquidacao_v15_imutavel()": {"definition_sha256": "69ea27bbd7eac181b8f976f4f74237c96682b4ba2a4674503eb92638e35675e1"}, "public.ceo_liquidar_modalidade_v15()": {"definition_sha256": "b879abd9a8f44d9f497ac6b2601e813a6583bd2428e57b0c4f166a13d2681003"}, "public.commercial_flag_sets_protect()": {"definition_sha256": "2690264d59ff4dcb2b76e2e13059b8de8f7a7f474d2a256ba426b665fc817626"}, "public.cci_preencher_fatos_materiais()": {"definition_sha256": "e8f11915eee4edce7f485b10659a3b55e3648ec49456a5f98cd4a2d345307a2b"}, "public.ceo_preencher_fatos_materiais()": {"definition_sha256": "4ec5ce9bd2913a981fd30937ee7765d8081db0afd844a92e1c2160ec13cfb972"}, "public.cci_validar_producao_bandeiras()": {"definition_sha256": "bcea4a9bba705b5f0f9692850c116ca359a212f66ee6585b72973c76f6b36a2a"}, "public.ceo_pagamento_confere_snapshot()": {"definition_sha256": "44759806656f355ffff3d0f0bcc72f3127ac196b7dd0361f4910beca6b964962"}, "public.ceo_validar_producao_bandeiras()": {"definition_sha256": "66cfeacb26d51d529fac3329b219e71d154330a3bc5975b1ad4719c528b3a41e"}, "public.commercial_flag_facts_imutaveis()": {"definition_sha256": "133b41d9abe71ee744c00f877e5e80bafc5307b6bcab95f6e7ad6b4d8a70d070"}, "public.commercial_pricing_rules_protect()": {"definition_sha256": "dcf4da0f184fe75d5919610690b0331d60b7c3145addd4d663a24ff4f6f31146"}, "public.commercial_guard_manifests_protect()": {"definition_sha256": "bc270768c7a81a5923a3bc1d303253925e1765e27540bf26b8618222d16b916e"}, "public.commercial_guard_integrity_failures()": {"execute": ["service_role"], "definition_sha256": "31bff3b751a8cd0a43a3c83fc1af6242ec952ea1dcd857d91ad33825a35cd742"}, "public.commercial_pricing_protect_truncate()": {"definition_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b"}, "public.commercial_pricing_schedule_protect()": {"definition_sha256": "334a31ec2adb96c33c47f422ab3a85a736ad18221dc55a1a99dec9811a8fc041"}, "public.commercial_settlement_terms_protect()": {"definition_sha256": "3a5c45565bec15feeaa7863a01015351f1638acbe2bd77a882960c56a2d00da2"}, "public.ceo_revalidar_reutilizacao_bandeiras()": {"definition_sha256": "3e5b9e40d240d9914949ed322ce3b8abdc54f147aa866bc29b6136f75568ddc5"}, "public.commercial_segment_snapshot_imutavel()": {"definition_sha256": "044adf339fe704030567db9f03719eb1546c7f716c49930cb69816923be555a9"}, "public.commercial_order_settlement_check(uuid)": {"execute": [], "definition_sha256": "d030911805a1013982a5006a56446d3719f6bbf0bcabf0abb56cd2f4e982a76f"}, "public.admin_activate_pricing_rule(integer,text)": {"execute": [], "definition_sha256": "ebb745215956a07cb6b63342edb3695313dedfa90db6156c0f78af22f733c424"}, "public.ceo_exigir_instrumento_quando_assinavel()": {"definition_sha256": "26f7000b7047e0a52eaa701d53cd09e2e351cd4a87d59c5af5c98702196e8308"}, "public.commercial_activation_guard_fingerprint()": {"execute": ["service_role"], "definition_sha256": "d18cfaf581560a16cef2e51e512de74c5216b13310c9396ff9080fd2ec296336"}, "public.commercial_flag_set_inspections_protect()": {"definition_sha256": "da606f958f5af26fdf2b0ce9ba2d45aa2056aa76d9f7b9e641bc97e2b3e58932"}, "public.commercial_flag_set_lock_for_inspection()": {"definition_sha256": "2271272d240a23dcd3007c6b7ce742459afb326d1102433995df2b4142301674"}, "public.commercial_pricing_activation_log_guard()": {"definition_sha256": "e35df937f3a0064e62fab1eb576b3c4fea5f75eccd58e05569264931654c8fe2"}, "public.commercial_activation_called_by_procedure()": {"execute": [], "definition_sha256": "c914658faee4fb50110c29838e3d0081b74294d75506f060096bb8ed882e0eea"}, "public.commercial_pricing_activation_log_protect()": {"definition_sha256": "14f69adce2ca6f8db8aeff765f2586090c7915b493ef22607b4cd16e6d3ce76f"}, "public.commercial_flag_inventory_protect_truncate()": {"definition_sha256": "bb12a8f32a55d6e71a5971e089e8756e9b2e86ddf007c999ea73076d1fe7baf4"}, "public.commercial_guard_function_entry(regprocedure)": {"execute": [], "definition_sha256": "2a73088e7683c3b65ccdc9903187fec65f03dd32129965a9198a058cb670f63a"}, "public.commercial_qa_operational_procedures_protect()": {"definition_sha256": "86436f51ea9a9a189569ac28e5980cd0074eb12cb75bf892bad96206fb80a591"}, "public.commercial_build_instrument_snapshot(uuid,uuid)": {"execute": ["service_role"], "definition_sha256": "43d17fca7b2f8caac9f77777ff06496f44eeca7259375bad77706c3715eb37ad"}, "public.commercial_pricing_activation_preflight(integer)": {"execute": [], "definition_sha256": "3378beea9ae0d6b7f6ee3810958381e41e6a5a4bb83cf9091b8132741eb6d6b6"}, "public.commercial_pricing_activation_approvals_protect()": {"definition_sha256": "131059cb96fbcb894a09cb3e551282b9b5144d4c793f4150029afa1e7f71da27"}, "public.commercial_instrument_template_approvals_protect()": {"definition_sha256": "c77e8e880308a73f9f6ee9751e501c189b1226539b56f8278c2328af0abb803e"}, "public.admin_confirm_manual_bdflow_payment(uuid,bigint,text,text)": {"execute": ["authenticated"], "definition_sha256": "07de6c5a333db89699234ffbebe222c54d38dad16995a531fd69f26327ea5ffb"}}}$manifesto_r42$::jsonb,
        'migration 20261116120000 / docs/release/R42_MANIFESTO_GUARDAS.json');

-- ===========================================================================
-- Z. AUTOVERIFICAÇÃO R4.2
-- ===========================================================================
DO $verifica_r42$
DECLARE
  v_pre jsonb;
BEGIN
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 3) <> 'active'
     OR (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared' THEN
    RAISE EXCEPTION 'r42_verificacao: estado das regras inesperado';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms WHERE benefit_settlement_mode = 'cash')
     OR EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log)
     OR EXISTS (SELECT 1 FROM public.commercial_pricing_activation_approvals)
     OR EXISTS (SELECT 1 FROM public.commercial_qa_operational_procedures)
     OR EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests) THEN
    RAISE EXCEPTION 'r42_verificacao: preco, ativacao, aprovacao, procedimento de QA ou solicitacao nao nascem aqui';
  END IF;
  IF (SELECT manifest_label || '|' || catalog_sha256 FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1)
     <> 'R4.2|155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246' THEN
    RAISE EXCEPTION 'r42_verificacao: manifesto vigente diferente do publicado';
  END IF;
  IF coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0) > 0 THEN
    RAISE EXCEPTION 'r42_verificacao: guardas divergentes: %', public.commercial_guard_integrity_failures();
  END IF;
  v_pre := public.commercial_pricing_activation_preflight(4);
  IF (v_pre->>'ok')::boolean OR NOT (v_pre->'failures' ? 'qa_operational_procedure_missing:SF-v1.5') THEN
    RAISE EXCEPTION 'r42_verificacao: a versao 4 nao pode estar apta a ativar (trava da QA): %', v_pre;
  END IF;
END $verifica_r42$;
