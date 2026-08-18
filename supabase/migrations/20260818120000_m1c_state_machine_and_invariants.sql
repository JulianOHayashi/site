-- ===========================================================================
-- M1-C1 — CORREÇÕES DA AUDITORIA INDEPENDENTE (B1, B6, B7, B8, B11)
-- ===========================================================================
-- Migration CORRETIVA posterior às quatro do M1. Nada é reescrito: a trilha
-- auditada é preservada e as correções ficam explícitas neste arquivo.
--
-- Não toca: baseline, M0.5, lógica do H1, RPC legada.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- B6 — VALIDAÇÃO REAL DE CNPJ E CPF NO SERVIDOR
-- ---------------------------------------------------------------------------
-- O TypeScript não é autoridade de integridade. Chamada direta à RPC como
-- anon passa a ser rejeitada por dígito verificador incorreto.

CREATE FUNCTION public.m1_cnpj_valido(p_cnpj text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  c      text;
  soma   integer;
  peso   integer;
  resto  integer;
  dv1    integer;
  dv2    integer;
  i      integer;
BEGIN
  c := pg_catalog.regexp_replace(p_cnpj, '[^0-9]', '', 'g');
  IF pg_catalog.length(c) <> 14 THEN RETURN false; END IF;
  IF c ~ '^(.)\1{13}$' THEN RETURN false; END IF;

  soma := 0; peso := 5;
  FOR i IN 1..12 LOOP
    soma := soma + (pg_catalog.substr(c, i, 1))::integer * peso;
    peso := peso - 1;
    IF peso < 2 THEN peso := 9; END IF;
  END LOOP;
  resto := soma % 11;
  dv1 := CASE WHEN resto < 2 THEN 0 ELSE 11 - resto END;
  IF dv1 <> (pg_catalog.substr(c, 13, 1))::integer THEN RETURN false; END IF;

  soma := 0; peso := 6;
  FOR i IN 1..13 LOOP
    soma := soma + (pg_catalog.substr(c, i, 1))::integer * peso;
    peso := peso - 1;
    IF peso < 2 THEN peso := 9; END IF;
  END LOOP;
  resto := soma % 11;
  dv2 := CASE WHEN resto < 2 THEN 0 ELSE 11 - resto END;
  RETURN dv2 = (pg_catalog.substr(c, 14, 1))::integer;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_cnpj_valido(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_cnpj_valido(text) FROM service_role;

CREATE FUNCTION public.m1_cpf_valido(p_cpf text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  c     text;
  soma  integer;
  resto integer;
  i     integer;
BEGIN
  c := pg_catalog.regexp_replace(p_cpf, '[^0-9]', '', 'g');
  IF pg_catalog.length(c) <> 11 THEN RETURN false; END IF;
  IF c ~ '^(.)\1{10}$' THEN RETURN false; END IF;

  soma := 0;
  FOR i IN 1..9 LOOP
    soma := soma + (pg_catalog.substr(c, i, 1))::integer * (11 - i);
  END LOOP;
  resto := (soma * 10) % 11;
  IF resto = 10 THEN resto := 0; END IF;
  IF resto <> (pg_catalog.substr(c, 10, 1))::integer THEN RETURN false; END IF;

  soma := 0;
  FOR i IN 1..10 LOOP
    soma := soma + (pg_catalog.substr(c, i, 1))::integer * (12 - i);
  END LOOP;
  resto := (soma * 10) % 11;
  IF resto = 10 THEN resto := 0; END IF;
  RETURN resto = (pg_catalog.substr(c, 11, 1))::integer;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.m1_cpf_valido(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_cpf_valido(text) FROM service_role;

ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_cnpj_dv
    CHECK (public.m1_cnpj_valido(cnpj));

ALTER TABLE public.partner_application_representatives
  ADD CONSTRAINT par_cpf_dv
    CHECK (public.m1_cpf_valido(cpf));

-- ---------------------------------------------------------------------------
-- B1 — MÁQUINA DE ESTADOS COM ETAPA DE CONTA PROVISÓRIA
-- ---------------------------------------------------------------------------
-- pending_email_verification
--   → pending_account_setup   (e-mail confirmado, conta ainda não criada)
--   → under_review            (conta provisória vinculada)
--
-- Antes, a confirmação do e-mail já colocava a aplicação em under_review sem
-- conta provisória, permitindo análise administrativa de uma solicitação
-- ainda sem titular. Corrigido aqui por estado + invariantes de banco.

ALTER TABLE public.partner_applications
  DROP CONSTRAINT partner_applications_status_allowed;

ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_status_allowed
    CHECK (status = ANY (ARRAY[
      'pending_email_verification',
      'pending_account_setup',
      'under_review',
      'changes_requested',
      'approved',
      'rejected',
      'withdrawn'
    ]));

-- Invariante: só há conta vinculada a partir de under_review; e a partir de
-- under_review a conta é obrigatória.
ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_conta_por_estado
    CHECK (
      CASE
        WHEN status IN ('pending_email_verification','pending_account_setup')
          THEN account_user_id IS NULL AND account_kind = 'none'
        WHEN status IN ('under_review','changes_requested','approved','rejected')
          THEN account_user_id IS NOT NULL AND account_kind = 'provisional'
        ELSE true   -- withdrawn: pode ocorrer antes ou depois do vínculo
      END
    );

-- B8 — Invariante de aprovação: impossível aprovar sem as DUAS análises
-- aprovadas, mesmo sob concorrência ou escrita direta por service_role.
ALTER TABLE public.partner_applications
  ADD CONSTRAINT partner_applications_aprovacao_exige_reviews
    CHECK (
      status <> 'approved'
      OR (company_review_status = 'approved' AND authority_review_status = 'approved')
    );

-- Unicidade parcial de CNPJ passa a incluir o novo estado não terminal.
DROP INDEX public.partner_applications_cnpj_nao_terminal_uk;
CREATE UNIQUE INDEX partner_applications_cnpj_nao_terminal_uk
  ON public.partner_applications (cnpj)
  WHERE status IN (
    'pending_email_verification',
    'pending_account_setup',
    'under_review',
    'changes_requested'
  );

-- ---------------------------------------------------------------------------
-- B7 — UMA CONTA POR APLICAÇÃO *VIVA*, NÃO POR HISTÓRICO
-- ---------------------------------------------------------------------------
-- O índice anterior cobria também aplicações terminais, o que impedia a
-- mesma conta de reivindicar uma reaplicação após rejeição. O comentário
-- dizia "aplicação viva"; o predicado não dizia. Agora dizem a mesma coisa.
DROP INDEX public.partner_applications_account_user_uk;
CREATE UNIQUE INDEX partner_applications_account_user_viva_uk
  ON public.partner_applications (account_user_id)
  WHERE account_user_id IS NOT NULL
    AND status IN ('under_review','changes_requested');

-- Índice de apoio para localizar o histórico da conta.
CREATE INDEX partner_applications_account_user_hist_idx
  ON public.partner_applications (account_user_id, created_at DESC)
  WHERE account_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- B11 — HELPERS INTERNOS FICAM RESTRITOS AO OWNER
-- ---------------------------------------------------------------------------
-- Eles recebiam EXECUTE de service_role pelo default per-schema preservado
-- pelo H1, não por concessão declarada. Nenhum precisa ser chamado
-- diretamente pelo backend: as RPCs SECURITY DEFINER continuam podendo
-- chamá-los como owner. O H1 NÃO é alterado por isso.
REVOKE EXECUTE ON FUNCTION public.m1_token_hash(text)                                        FROM service_role;
REVOKE EXECUTE ON FUNCTION public.m1_emitir_token(uuid, text, text, interval)                FROM service_role;
REVOKE EXECUTE ON FUNCTION public.m1_auditar(text, uuid, text, jsonb, jsonb, jsonb)          FROM service_role;
REVOKE EXECUTE ON FUNCTION public.m1_enfileirar_email(text, text, jsonb, uuid, text)         FROM service_role;
REVOKE EXECUTE ON FUNCTION public.m1_exigir_admin()                                          FROM service_role;
