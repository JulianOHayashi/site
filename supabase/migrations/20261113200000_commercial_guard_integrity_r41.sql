-- ===========================================================================
-- R4.1 — FECHAMENTO DO VERIFICADOR DE GUARDAS (auditoria da R4 cd4064a)
--
-- Migration PREPARATÓRIA, NÃO aplicada. Depende de 20261112120000 (SF-v1.5),
-- 20261113150000 (R3) e 20261113180000 (R4), também não aplicadas. Não grava
-- preço, modalidade, aprovação jurídica, aprovação de ativação nem
-- procedimento de QA; não ativa versão; não altera linha histórica.
--
--   1. ESTADO DOS GATILHOS: a pré-verificação deixa de aceitar "qualquer
--      estado diferente de D". Cada gatilho de guarda precisa estar no estado
--      APROVADO no manifesto (hoje 'O'); 'R' (ENABLE REPLICA), 'A' (ENABLE
--      ALWAYS), 'D' e ausente são recusados. A ativação também é recusada com
--      session_replication_role <> 'origin'.
--   2. IMPRESSÃO DIGITAL COMPLETA: o catálogo canônico das guardas registra,
--      por gatilho, a definição canônica (pg_get_triggerdef), a função
--      executada (assinatura e SHA-256 da definição dela), tgtype (momento,
--      nível e eventos), argumentos, condição WHEN, colunas e estado; por
--      função, o SHA-256 de pg_get_functiondef e, fora as de gatilho, quem
--      pode executá-la. Vale para TODOS os gatilhos das tabelas guardadas:
--      gatilho a mais também é divergência. O manifesto aprovado é gravado
--      nesta migration (commercial_guard_manifests) e a pré-verificação, a
--      transição prepared -> active e o registro de ativação exigem que o
--      catálogo vivo seja IGUAL a ele. SHA-256 em tudo (pg_catalog.sha256).
--   3. EXECUTOR × APROVADOR: a ativação exige uma aprovação de lançamento
--      registrada antes (referência e SHA-256 do documento externo, aprovador
--      como consta no documento). O registro separa o executor técnico
--      (papel de banco, sub do JWT se houver, application_name, endereço) da
--      aprovação. O banco não infere pessoa a partir do papel de banco.
--   4. PRÉ-REQUISITO DA QA: enquanto não houver procedimento operacional de
--      QA aprovado para a versão econômica (autorização, recebimento dos
--      produtos, execução dos testes, validação de evidências e não
--      cumprimento), a SF-v1.5 não ativa e nenhum instrumento com QA em
--      produtos é individualizado.
-- ===========================================================================

-- ===========================================================================
-- A. CATÁLOGO CANÔNICO DAS GUARDAS (SHA-256)
-- ===========================================================================

-- Entrada canônica de uma função: SHA-256 da definição completa produzida
-- pelo servidor (corpo, linguagem, argumentos, retorno, volatilidade,
-- SECURITY DEFINER, search_path) e, para funções que não são de gatilho, os
-- papéis com EXECUTE (sem o dono).
CREATE FUNCTION public.commercial_guard_function_entry(p_fn regprocedure)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT pg_catalog.jsonb_build_object(
           'definition_sha256',
           pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid), 'UTF8')), 'hex'))
         || CASE WHEN p.prorettype = 'trigger'::regtype THEN '{}'::jsonb
                 ELSE pg_catalog.jsonb_build_object('execute', coalesce((
                        SELECT pg_catalog.jsonb_agg(x.r ORDER BY x.r)
                          FROM (SELECT DISTINCT coalesce(nullif(g.grantee, 0)::regrole::text, 'PUBLIC') AS r
                                  FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) g
                                 WHERE g.privilege_type = 'EXECUTE' AND g.grantee <> p.proowner) x),
                        '[]'::jsonb))
            END
    FROM pg_catalog.pg_proc p
   WHERE p.oid = p_fn;
$$;

-- Catálogo vivo. Tabelas guardadas: TODO gatilho não interno delas entra.
-- Funções guardadas: a lista explícita (não-gatilho e guardas) mais a função
-- de cada gatilho guardado.
CREATE FUNCTION public.commercial_guard_catalog()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  WITH tabelas AS (
    SELECT x.nome, pg_catalog.to_regclass('public.' || x.nome) AS rel
      FROM pg_catalog.unnest(ARRAY[
        'commercial_pricing_rules', 'commercial_pricing_schedule', 'commercial_settlement_terms',
        'commercial_checkout_intents', 'commercial_exclusivity_orders', 'commercial_payments',
        'commercial_pricing_activation_log', 'commercial_pricing_activation_approvals',
        'commercial_flag_sets', 'commercial_flag_set_inspections',
        'commercial_instrument_template_approvals', 'commercial_qa_operational_procedures',
        'commercial_guard_manifests']) AS x(nome)
  ), gatilhos AS (
    SELECT t.*
      FROM pg_catalog.pg_trigger t
      JOIN tabelas ON tabelas.rel = t.tgrelid
     WHERE NOT t.tgisinternal
  ), funcoes AS (
    SELECT p.oid
      FROM pg_catalog.pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname = ANY (ARRAY[
         'admin_activate_pricing_rule', 'commercial_pricing_activation_preflight',
         'commercial_activation_called_by_procedure', 'commercial_activation_guard_fingerprint',
         'commercial_guard_function_entry', 'commercial_guard_catalog', 'commercial_guard_integrity_failures',
         'admin_confirm_manual_bdflow_payment', 'commercial_build_instrument_snapshot',
         'commercial_order_settlement_check'])
    UNION
    SELECT g.tgfoid FROM gatilhos g
  )
  SELECT pg_catalog.jsonb_build_object(
    'format', 'smallflags-guard-catalog/1 (R4.1, sha256)',
    'tables', (SELECT pg_catalog.jsonb_agg(
                        pg_catalog.jsonb_build_object('table', 'public.' || nome, 'present', rel IS NOT NULL)
                        ORDER BY nome) FROM tabelas),
    'functions', coalesce((SELECT pg_catalog.jsonb_object_agg(f.oid::regprocedure::text,
                                    public.commercial_guard_function_entry(f.oid::regprocedure))
                             FROM funcoes f), '{}'::jsonb),
    'triggers', coalesce((SELECT pg_catalog.jsonb_object_agg(
        g.tgrelid::regclass::text || '.' || g.tgname,
        pg_catalog.jsonb_build_object(
          'state', g.tgenabled::text,
          'definition', pg_catalog.pg_get_triggerdef(g.oid, false),
          'definition_sha256', pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
                                 pg_catalog.pg_get_triggerdef(g.oid, false), 'UTF8')), 'hex'),
          'function', g.tgfoid::regprocedure::text,
          'function_sha256', public.commercial_guard_function_entry(g.tgfoid::regprocedure)->>'definition_sha256',
          'tgtype', g.tgtype,
          'args_sha256', pg_catalog.encode(pg_catalog.sha256(g.tgargs), 'hex'),
          'when', pg_catalog.pg_get_expr(g.tgqual, g.tgrelid),
          'columns', g.tgattr::text,
          'deferrable', g.tgdeferrable,
          'initially_deferred', g.tginitdeferred))
        FROM gatilhos g), '{}'::jsonb));
$$;

-- A impressão digital gravada na ativação passa a ser o catálogo completo.
CREATE OR REPLACE FUNCTION public.commercial_activation_guard_fingerprint()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT public.commercial_guard_catalog();
$$;

-- ===========================================================================
-- B. MANIFESTO APROVADO (somente inserção)
-- ===========================================================================
CREATE TABLE public.commercial_guard_manifests (
  id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  manifest_label         text NOT NULL UNIQUE,
  catalog                jsonb NOT NULL,
  catalog_sha256         text NOT NULL,
  source_reference       text NOT NULL,
  registered_by_db_role  text NOT NULL,
  registered_at          timestamptz NOT NULL,
  registration_txid      bigint NOT NULL,
  CONSTRAINT cgm_sha256 CHECK (catalog_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cgm_label CHECK (length(btrim(manifest_label)) >= 2),
  CONSTRAINT cgm_ref CHECK (length(btrim(source_reference)) >= 10)
);
COMMENT ON TABLE public.commercial_guard_manifests IS
  'R4.1: configuracao APROVADA das guardas (catalogo canonico). A mais recente e a exigida. '
  'Somente insercao; cada linha precisa constar do registro externo (docs/release/R41_MANIFESTO_GUARDAS.*).';
ALTER TABLE public.commercial_guard_manifests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_guard_manifests FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_guard_manifests TO service_role;

-- O manifesto só registra o que está vivo: aprovar é congelar a configuração
-- presente, nunca uma configuração imaginada.
CREATE FUNCTION public.commercial_guard_manifests_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'manifesto_guardas_imutavel: manifesto aprovado nao muda nem e apagado'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.catalog IS DISTINCT FROM public.commercial_guard_catalog() THEN
    RAISE EXCEPTION 'manifesto_guardas_divergente: o manifesto informado nao e a configuracao viva das guardas'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.catalog_sha256        := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(NEW.catalog::text, 'UTF8')), 'hex');
  NEW.registered_by_db_role := session_user;
  NEW.registered_at         := pg_catalog.now();
  NEW.registration_txid     := pg_catalog.txid_current();
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_guard_manifests_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cgm_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_guard_manifests
  FOR EACH ROW EXECUTE FUNCTION public.commercial_guard_manifests_protect();
CREATE TRIGGER cgm_protect_truncate
  BEFORE TRUNCATE ON public.commercial_guard_manifests
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- ===========================================================================
-- C. APROVAÇÃO DE LANÇAMENTO (executor técnico × quem aprovou)
-- ===========================================================================
CREATE TABLE public.commercial_pricing_activation_approvals (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_rule_version      integer NOT NULL REFERENCES public.commercial_pricing_rules (version),
  approval_reference        text NOT NULL UNIQUE,
  approval_document_sha256  text NOT NULL,
  approver_as_stated        text NOT NULL,
  approved_on_as_stated     date NOT NULL,
  registered_by_db_role     text NOT NULL,
  registered_at             timestamptz NOT NULL,
  registration_txid         bigint NOT NULL,
  CONSTRAINT cpaa_ref CHECK (length(btrim(approval_reference)) >= 10),
  CONSTRAINT cpaa_sha256 CHECK (approval_document_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cpaa_aprovador CHECK (length(btrim(approver_as_stated)) >= 3)
);
COMMENT ON TABLE public.commercial_pricing_activation_approvals IS
  'R4.1: aprovacao EXTERNA do lancamento de uma versao de preco. approver_as_stated e o nome como consta '
  'no documento externo (sha256), DECLARADO e nao verificado pelo banco. registered_by_db_role e o papel '
  'de banco que registrou: executor tecnico, nao identidade humana.';
ALTER TABLE public.commercial_pricing_activation_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_pricing_activation_approvals FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_pricing_activation_approvals TO service_role;

CREATE FUNCTION public.commercial_pricing_activation_approvals_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'aprovacao_lancamento_imutavel: aprovacao registrada nao muda nem e apagada'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.registered_by_db_role := session_user;
  NEW.registered_at         := pg_catalog.now();
  NEW.registration_txid     := pg_catalog.txid_current();
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_pricing_activation_approvals_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cpaa_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_pricing_activation_approvals
  FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_approvals_protect();
CREATE TRIGGER cpaa_protect_truncate
  BEFORE TRUNCATE ON public.commercial_pricing_activation_approvals
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- Registro de ativação: executor técnico separado da aprovação.
ALTER TABLE public.commercial_pricing_activation_log
  ADD COLUMN activation_approval_id     uuid REFERENCES public.commercial_pricing_activation_approvals (id),
  ADD COLUMN approval_document_sha256   text,
  ADD COLUMN guard_catalog_sha256       text,
  ADD COLUMN guard_manifest_id          bigint REFERENCES public.commercial_guard_manifests (id),
  ADD COLUMN executor_db_role           text,
  ADD COLUMN executor_jwt_sub           text,
  ADD COLUMN executor_application_name  text,
  ADD COLUMN executor_client_addr       inet;
COMMENT ON COLUMN public.commercial_pricing_activation_log.actor IS
  'Papel de banco da conexao (session_user) que executou: EXECUTOR TECNICO. Nao identifica pessoa. '
  'Quem aprovou esta em activation_approval_id (documento externo com sha256).';
COMMENT ON COLUMN public.commercial_pricing_activation_log.executor_db_role IS
  'R4.1: igual a actor (session_user). Executor tecnico, nao identidade humana.';
COMMENT ON COLUMN public.commercial_pricing_activation_log.executor_jwt_sub IS
  'R4.1: sub do JWT da requisicao, se a chamada veio pela API; NULL em SQL direto. Nao e inferido.';
COMMENT ON COLUMN public.commercial_pricing_activation_log.guard_catalog_sha256 IS
  'R4.1: SHA-256 do catalogo canonico das guardas no ato; igual ao do manifesto aprovado guard_manifest_id.';

-- ===========================================================================
-- D. PROCEDIMENTO OPERACIONAL DE QA (pré-requisito, somente inserção)
-- ===========================================================================
CREATE TABLE public.commercial_qa_operational_procedures (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_economics_version   text NOT NULL,
  procedure_reference          text NOT NULL UNIQUE,
  procedure_document_sha256    text NOT NULL,
  covers_authorization         boolean NOT NULL,
  covers_product_receipt       boolean NOT NULL,
  covers_test_execution        boolean NOT NULL,
  covers_evidence_validation   boolean NOT NULL,
  covers_noncompliance         boolean NOT NULL,
  approver_as_stated           text NOT NULL,
  approved_on_as_stated        date NOT NULL,
  registered_by_db_role        text NOT NULL,
  registered_at                timestamptz NOT NULL,
  CONSTRAINT cqop_ref CHECK (length(btrim(procedure_reference)) >= 10),
  CONSTRAINT cqop_sha256 CHECK (procedure_document_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT cqop_aprovador CHECK (length(btrim(approver_as_stated)) >= 3),
  CONSTRAINT cqop_cobertura_completa CHECK (covers_authorization AND covers_product_receipt
    AND covers_test_execution AND covers_evidence_validation AND covers_noncompliance)
);
COMMENT ON TABLE public.commercial_qa_operational_procedures IS
  'R4.1: procedimento operacional de QA APROVADO (documento externo, sha256) para uma versao economica. '
  'Sem linha para a economia, a versao com QA em produtos nao ativa e o instrumento com QA nao e emitido. '
  'Nenhuma linha nasce em migration; o registro e ato do dono, com documento aprovado.';
ALTER TABLE public.commercial_qa_operational_procedures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.commercial_qa_operational_procedures FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.commercial_qa_operational_procedures TO service_role;

CREATE FUNCTION public.commercial_qa_operational_procedures_protect()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'procedimento_qa_imutavel: procedimento registrado nao muda nem e apagado'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.registered_by_db_role := session_user;
  NEW.registered_at         := pg_catalog.now();
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.commercial_qa_operational_procedures_protect() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cqop_protect
  BEFORE INSERT OR UPDATE OR DELETE ON public.commercial_qa_operational_procedures
  FOR EACH ROW EXECUTE FUNCTION public.commercial_qa_operational_procedures_protect();
CREATE TRIGGER cqop_protect_truncate
  BEFORE TRUNCATE ON public.commercial_qa_operational_procedures
  FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate();

-- ===========================================================================
-- E. COMPARAÇÃO DO CATÁLOGO VIVO COM O MANIFESTO APROVADO
-- ===========================================================================
-- Lista vazia = guardas íntegras. Nome sozinho nunca basta: estado,
-- definição, função executada (assinatura e definição), momento/eventos,
-- argumentos, condição e colunas precisam ser os aprovados.
CREATE FUNCTION public.commercial_guard_integrity_failures()
RETURNS text[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_m     public.commercial_guard_manifests%ROWTYPE;
  v_viva  jsonb;
  v_f     text[] := ARRAY[]::text[];
  v_k     text;
  v_a     jsonb;
  v_b     jsonb;
  v_camp  text;
  v_dif   text[];
BEGIN
  IF pg_catalog.current_setting('session_replication_role') <> 'origin' THEN
    v_f := v_f || ('session_replication_role_not_origin:' || pg_catalog.current_setting('session_replication_role'));
  END IF;
  SELECT * INTO v_m FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN v_f || 'guard_manifest_missing'::text;
  END IF;
  v_viva := public.commercial_guard_catalog();

  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(v_m.catalog->'triggers') LOOP
    v_a := v_m.catalog->'triggers'->v_k;
    v_b := v_viva->'triggers'->v_k;
    IF v_b IS NULL THEN
      v_f := v_f || ('guard_trigger_missing:' || v_k);
      CONTINUE;
    END IF;
    IF v_b->>'state' IS DISTINCT FROM v_a->>'state' THEN
      v_f := v_f || format('guard_trigger_state_not_approved:%s:%s(aprovado %s)', v_k, v_b->>'state', v_a->>'state');
    END IF;
    v_dif := ARRAY[]::text[];
    FOREACH v_camp IN ARRAY ARRAY['definition_sha256', 'function', 'function_sha256', 'tgtype',
                                  'args_sha256', 'when', 'columns', 'deferrable', 'initially_deferred'] LOOP
      IF v_b->v_camp IS DISTINCT FROM v_a->v_camp THEN
        v_dif := v_dif || v_camp;
      END IF;
    END LOOP;
    IF array_length(v_dif, 1) > 0 THEN
      v_f := v_f || format('guard_trigger_definition_divergent:%s:%s', v_k, array_to_string(v_dif, ','));
    END IF;
  END LOOP;
  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(v_viva->'triggers')
             EXCEPT SELECT pg_catalog.jsonb_object_keys(v_m.catalog->'triggers') LOOP
    v_f := v_f || ('guard_trigger_not_approved:' || v_k);
  END LOOP;

  FOR v_k IN SELECT pg_catalog.jsonb_object_keys(v_m.catalog->'functions')
             UNION SELECT pg_catalog.jsonb_object_keys(v_viva->'functions') LOOP
    IF v_viva->'functions'->v_k IS NULL THEN
      v_f := v_f || ('guard_function_missing:' || v_k);
    ELSIF v_m.catalog->'functions'->v_k IS NULL THEN
      v_f := v_f || ('guard_function_not_approved:' || v_k);
    ELSIF v_viva->'functions'->v_k IS DISTINCT FROM v_m.catalog->'functions'->v_k THEN
      v_f := v_f || ('guard_function_divergent:' || v_k);
    END IF;
  END LOOP;
  IF v_viva->'tables' IS DISTINCT FROM v_m.catalog->'tables' THEN
    v_f := v_f || 'guard_tables_divergent'::text;
  END IF;
  -- Rede de segurança: qualquer diferença não nomeada acima.
  IF v_viva IS DISTINCT FROM v_m.catalog AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.unnest(v_f) x WHERE x NOT LIKE 'session_replication_role%') THEN
    v_f := v_f || 'guard_manifest_divergent'::text;
  END IF;
  RETURN v_f;
END $$;

-- ===========================================================================
-- F. REGISTRO DE ATIVAÇÃO: guardas iguais ao manifesto, aprovação externa e
--    executor técnico gravados pelo servidor
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.commercial_pricing_activation_log_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_falhas text[];
  v_m      public.commercial_guard_manifests%ROWTYPE;
  v_apr    public.commercial_pricing_activation_approvals%ROWTYPE;
  v_claims text;
BEGIN
  IF NOT public.commercial_activation_called_by_procedure() THEN
    RAISE EXCEPTION 'activation_log_somente_pelo_procedimento: registro de ativacao so e gravado por admin_activate_pricing_rule'
      USING ERRCODE = 'check_violation';
  END IF;
  v_falhas := public.commercial_guard_integrity_failures();
  IF coalesce(array_length(v_falhas, 1), 0) > 0 THEN
    RAISE EXCEPTION 'activation_log_guardas_divergentes: %', v_falhas
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.guard_fingerprint IS DISTINCT FROM public.commercial_activation_guard_fingerprint() THEN
    RAISE EXCEPTION 'activation_log_impressao_divergente: impressao digital das guardas nao confere'
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_m FROM public.commercial_guard_manifests ORDER BY id DESC LIMIT 1;
  SELECT * INTO v_apr FROM public.commercial_pricing_activation_approvals a
   WHERE a.id = NEW.activation_approval_id
     AND a.pricing_rule_version = NEW.pricing_rule_version
     AND a.approval_reference = NEW.authorization_reference;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'activation_log_sem_aprovacao: ativacao exige aprovacao de lancamento registrada para a versao e a referencia'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.approval_document_sha256 := v_apr.approval_document_sha256;
  NEW.guard_catalog_sha256 := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(NEW.guard_fingerprint::text, 'UTF8')), 'hex');
  IF NEW.guard_catalog_sha256 IS DISTINCT FROM v_m.catalog_sha256 THEN
    RAISE EXCEPTION 'activation_log_guardas_divergentes: catalogo % difere do manifesto %', NEW.guard_catalog_sha256, v_m.catalog_sha256
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.guard_manifest_id := v_m.id;
  -- Executor TÉCNICO: o que o servidor sabe da conexão. Nunca uma pessoa.
  NEW.actor            := session_user;
  NEW.executor_db_role := session_user;
  v_claims := pg_catalog.current_setting('request.jwt.claims', true);
  BEGIN
    NEW.executor_jwt_sub := CASE WHEN coalesce(v_claims, '') = '' THEN NULL ELSE v_claims::jsonb->>'sub' END;
  EXCEPTION WHEN OTHERS THEN
    NEW.executor_jwt_sub := NULL;
  END;
  NEW.executor_application_name := nullif(pg_catalog.current_setting('application_name', true), '');
  NEW.executor_client_addr      := pg_catalog.inet_client_addr();
  NEW.txid       := pg_catalog.txid_current();
  NEW.created_at := pg_catalog.now();
  RETURN NEW;
END $$;

-- ===========================================================================
-- G. PROCEDIMENTO DE ATIVAÇÃO: exige aprovação externa registrada e devolve
--    o recibo a guardar fora do banco
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.admin_activate_pricing_rule(
  p_version integer, p_authorization_reference text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_pre      jsonb;
  v_anterior integer;
  v_apr      public.commercial_pricing_activation_approvals%ROWTYPE;
  v_log      public.commercial_pricing_activation_log%ROWTYPE;
BEGIN
  IF p_authorization_reference IS NULL OR length(btrim(p_authorization_reference)) < 10 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'authorization_reference_required');
  END IF;
  IF pg_catalog.current_setting('session_replication_role') <> 'origin' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'session_replication_role_not_origin',
      'session_replication_role', pg_catalog.current_setting('session_replication_role'));
  END IF;
  SELECT * INTO v_apr FROM public.commercial_pricing_activation_approvals a
   WHERE a.pricing_rule_version = p_version AND a.approval_reference = btrim(p_authorization_reference);
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'activation_approval_not_registered',
      'pricing_rule_version', p_version);
  END IF;
  v_pre := public.commercial_pricing_activation_preflight(p_version);
  IF (v_pre->>'ok')::boolean IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('ok', false,
      'reason', 'activation_preconditions_pending', 'failures', v_pre->'failures');
  END IF;

  INSERT INTO public.commercial_pricing_activation_log
    (pricing_rule_version, authorization_reference, preflight, guard_fingerprint, activation_approval_id)
  VALUES (p_version, v_apr.approval_reference, v_pre,
          public.commercial_activation_guard_fingerprint(), v_apr.id)
  RETURNING * INTO v_log;

  SELECT version INTO v_anterior FROM public.commercial_pricing_rules WHERE status = 'active';
  UPDATE public.commercial_pricing_rules SET status = 'superseded'
   WHERE status = 'active' AND version < p_version;
  UPDATE public.commercial_pricing_rules SET status = 'active', effective_from = pg_catalog.now()
   WHERE version = p_version;

  -- Recibo: a guardar FORA do banco por quem aprovou (não por quem executou).
  RETURN pg_catalog.jsonb_build_object('ok', true, 'activated_version', p_version,
    'superseded_version', v_anterior,
    'receipt', pg_catalog.jsonb_build_object(
      'activation_log_id', v_log.id,
      'pricing_rule_version', v_log.pricing_rule_version,
      'txid', v_log.txid,
      'created_at', v_log.created_at,
      'executor_db_role', v_log.executor_db_role,
      'executor_jwt_sub', v_log.executor_jwt_sub,
      'approval_reference', v_apr.approval_reference,
      'approval_document_sha256', v_apr.approval_document_sha256,
      'approver_as_stated', v_apr.approver_as_stated,
      'guard_catalog_sha256', v_log.guard_catalog_sha256,
      'guard_manifest_id', v_log.guard_manifest_id));
END $$;

-- H. PRÉ-VERIFICAÇÃO (R4.1): manifesto, aprovação de lançamento, QA
CREATE OR REPLACE FUNCTION public.commercial_pricing_activation_preflight(p_version integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_rule    public.commercial_pricing_rules%ROWTYPE;
  v_falhas  text[] := ARRAY[]::text[];
  v_econ    text;
  v_cat     text;
  v_fid     boolean;
  v_modo    text;
  v_n       integer;
  v_nichos  integer;
BEGIN
  SELECT * INTO v_rule FROM public.commercial_pricing_rules WHERE version = p_version;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'version', p_version,
      'failures', pg_catalog.to_jsonb(ARRAY['rule_not_found']));
  END IF;
  IF v_rule.status <> 'prepared' THEN
    v_falhas := v_falhas || ('rule_not_prepared:' || v_rule.status);
  END IF;

  -- A4: política de QA e termos das DUAS modalidades, coerentes.
  IF v_rule.qa_policy IS DISTINCT FROM 'in_kind_direct_benefits_only' THEN
    v_falhas := v_falhas || 'qa_policy_missing'::text;
  END IF;
  SELECT count(*) INTO v_n FROM public.commercial_pricing_schedule WHERE pricing_rule_version = p_version;
  IF v_n <> 4 THEN
    v_falhas := v_falhas || ('schedule_incomplete:' || v_n);
  END IF;
  SELECT max(contract_economics_version) INTO v_econ
    FROM public.commercial_pricing_schedule WHERE pricing_rule_version = p_version;
  FOREACH v_cat IN ARRAY ARRAY['supermarket', 'common'] LOOP
    FOREACH v_fid IN ARRAY ARRAY[false, true] LOOP
      FOREACH v_modo IN ARRAY ARRAY['direct_benefits', 'cash'] LOOP
        IF NOT EXISTS (SELECT 1 FROM public.commercial_settlement_terms t
                        WHERE t.pricing_rule_version = p_version AND t.commercial_category = v_cat
                          AND t.fidelized = v_fid AND t.benefit_settlement_mode = v_modo) THEN
          v_falhas := v_falhas || format('settlement_terms_missing:%s/%s/%s', v_cat,
                                         CASE WHEN v_fid THEN 'fidelizado' ELSE 'novo' END, v_modo);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  -- A6: minuta assinável que redige o modelo de liquidação, para as duas
  -- condições de fidelidade; e atividade contratada aprovada no catálogo da
  -- economia da versão, para toda posição ativa (A2).
  FOREACH v_fid IN ARRAY ARRAY[false, true] LOOP
    -- R4: minuta assinável COM aprovação jurídica do mesmo conteúdo, para a
    -- economia da versão, o modelo de liquidação e as DUAS modalidades.
    IF NOT EXISTS (SELECT 1 FROM public.commercial_instrument_templates t
                     JOIN public.commercial_instrument_template_approvals a
                       ON a.template_id = t.id
                      AND a.content_sha256 = t.source_hash
                      AND a.contract_economics_version = v_econ
                      AND a.settlement_model = v_rule.qa_policy
                      AND a.applies_to_fidelized = v_fid
                      AND a.settlement_modes @> ARRAY['direct_benefits', 'cash']::text[]
                    WHERE t.lifecycle_status = 'signable' AND t.applies_to_fidelized = v_fid
                      AND t.settlement_model IS NOT DISTINCT FROM v_rule.qa_policy
                      AND v_rule.qa_policy IS NOT NULL) THEN
      v_falhas := v_falhas || format('instrument_template_missing:%s',
                                     CASE WHEN v_fid THEN 'fidelizado' ELSE 'novo' END);
    END IF;
  END LOOP;
  SELECT count(*) INTO v_nichos FROM public.commercial_niches WHERE is_active;
  SELECT count(DISTINCT c.niche_code) INTO v_n
    FROM public.commercial_contract_activity_catalog c
    JOIN public.commercial_niches n ON n.code = c.niche_code AND n.is_active
   WHERE c.catalog_version = v_econ AND c.status = 'approved';
  IF v_econ IS NULL OR v_n < v_nichos THEN
    v_falhas := v_falhas || format('activity_catalog_incomplete:%s/%s', v_n, v_nichos);
  END IF;

  -- R4.1: as guardas precisam ser IGUAIS ao manifesto aprovado: estado
  -- aprovado ('O'; 'R', 'A', 'D' ou ausente recusados), definição, função
  -- executada, momento, eventos, argumentos e condição. Nome não basta.
  v_falhas := v_falhas || public.commercial_guard_integrity_failures();

  -- R4.1: lançamento aprovado fora do banco e registrado antes do ato.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_approvals a
                  WHERE a.pricing_rule_version = p_version) THEN
    v_falhas := v_falhas || 'activation_approval_missing'::text;
  END IF;

  -- R4.1: QA em produtos só com procedimento operacional aprovado para a
  -- economia da versão (autorização, recebimento, testes, evidências e não
  -- cumprimento).
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms t
              WHERE t.pricing_rule_version = p_version
                AND t.benefit_settlement_mode = 'direct_benefits' AND t.qa_in_kind_cents > 0)
     AND NOT EXISTS (SELECT 1 FROM public.commercial_qa_operational_procedures q
                      WHERE q.contract_economics_version = v_econ) THEN
    v_falhas := v_falhas || format('qa_operational_procedure_missing:%s', coalesce(v_econ, '?'));
  END IF;

  -- Reserva viva sob a versão anterior seria finalizada com o preço antigo.
  SELECT count(*) INTO v_n FROM public.commercial_checkout_intents
   WHERE status IN ('draft', 'awaiting_contract')
     AND reserved_until IS NOT NULL AND reserved_until > pg_catalog.now();
  IF v_n > 0 THEN
    v_falhas := v_falhas || ('live_reservations:' || v_n);
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', coalesce(array_length(v_falhas, 1), 0) = 0,
    'version', p_version,
    'failures', pg_catalog.to_jsonb(v_falhas));
END $$;

-- I. CONSTRUTOR DO INSTRUMENTO (R4.1): QA exige procedimento aprovado
CREATE OR REPLACE FUNCTION public.commercial_build_instrument_snapshot(p_order_id uuid, p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_o      public.commercial_exclusivity_orders%ROWTYPE;
  v_c      public.site_partner_companies%ROWTYPE;
  v_u      public.site_partner_units%ROWTYPE;
  v_a      public.commercial_master_agreements%ROWTYPE;
  v_rep    public.partner_application_representatives%ROWTYPE;
  v_ace    public.legal_acceptances%ROWTYPE;
  v_t      public.commercial_instrument_templates%ROWTYPE;
  v_sched  public.commercial_pricing_schedule%ROWTYPE;
  v_ativ   jsonb;
  v_snap   jsonb;
  v_prov   jsonb;
  v_faltam text[] := ARRAY[]::text[];
  v_campo  text;
  v_spec   public.commercial_advertising_specs%ROWTYPE;
  v_reg    public.commercial_regions%ROWTYPE;
  v_exc    public.commercial_exclusivities%ROWTYPE;
  v_ativ_ef jsonb;
  v_qa_policy text;
  v_liq    jsonb;
  v_apr    public.commercial_instrument_template_approvals%ROWTYPE;
  v_qap    public.commercial_qa_operational_procedures%ROWTYPE;
BEGIN
  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE id = p_template_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_unavailable');
  END IF;
  IF v_t.lifecycle_status <> 'signable' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_not_signable',
      'lifecycle_status', v_t.lifecycle_status, 'template_code', v_t.template_code);
  END IF;

  SELECT * INTO v_o FROM public.commercial_exclusivity_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF coalesce(v_o.fidelized, false) <> v_t.applies_to_fidelized THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_fidelity_mismatch',
      'order_fidelized', coalesce(v_o.fidelized, false),
      'template_applies_to_fidelized', v_t.applies_to_fidelized);
  END IF;

  -- OUTROS dormente: nicho fora do catalogo canonico nao individualiza nada.
  IF NOT EXISTS (SELECT 1 FROM public.commercial_niches n
                  WHERE n.code = v_o.niche_code AND n.is_active) THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_niche_not_canonical',
      'niche_code', v_o.niche_code);
  END IF;

  -- D9: a minuta vigente não identifica posição × segmento nem tem atividade
  -- contratada por segmento. Até a revisão jurídica, pedido com segmento (ou
  -- na posição Outros) não individualiza instrumento — falha fechado.
  IF v_o.segment_id IS NOT NULL OR v_o.niche_code = 'others' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_segment_activity_unavailable',
      'niche_code', v_o.niche_code,
      'segment_code', v_o.segment_code_snapshot);
  END IF;

  SELECT * INTO v_c FROM public.site_partner_companies WHERE id = v_o.company_id;
  SELECT * INTO v_a FROM public.commercial_master_agreements
   WHERE id = v_o.master_agreement_id;
  SELECT * INTO v_rep FROM public.partner_application_representatives
   WHERE application_id = v_c.source_application_id AND is_current;
  IF v_o.legal_acceptance_id IS NOT NULL THEN
    SELECT * INTO v_ace FROM public.legal_acceptances WHERE id = v_o.legal_acceptance_id;
  END IF;

  -- ---- UNIDADE DE EXECUCAO: persistida e revalidada, nunca "a primeira".
  IF v_o.execution_unit_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_selected', 'order_id', v_o.id);
  END IF;
  SELECT * INTO v_u FROM public.site_partner_units WHERE id = v_o.execution_unit_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_found');
  END IF;
  IF v_u.company_id IS DISTINCT FROM v_o.company_id THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_owned_by_company');
  END IF;
  IF v_u.status <> 'active' THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'execution_unit_not_active', 'status', v_u.status);
  END IF;

  -- ---- TOMADOR DE NFS-e: tem de ser o CNPJ da contratante no MVP fundador.
  IF v_o.nfse_taker_cnpj IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'nfse_taker_not_persisted');
  END IF;
  IF pg_catalog.regexp_replace(v_o.nfse_taker_cnpj, '[^0-9]', '', 'g')
       IS DISTINCT FROM
       pg_catalog.regexp_replace(v_c.cnpj, '[^0-9]', '', 'g') THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'alternate_nfse_taker_not_supported',
      'persisted_taker', v_o.nfse_taker_cnpj);
  END IF;

  -- ---- ECONOMIA: da autoridade, incluindo o valor da participacao.
  SELECT * INTO v_sched FROM public.commercial_pricing_schedule
   WHERE pricing_rule_version = v_o.pricing_rule_version
     AND contract_economics_version = v_o.contract_economics_version
     AND commercial_category = CASE WHEN v_o.niche_code = 'supermarket'
                                    THEN 'supermarket' ELSE 'common' END
     AND fidelized = coalesce(v_o.fidelized, false);
  IF NOT FOUND OR v_sched.ordinary_participation_value_cents IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'contract_economics_authority_unavailable',
      'pricing_rule_version', v_o.pricing_rule_version);
  END IF;

  -- ---- R3 / A6: a minuta precisa redigir o modelo de liquidacao da versao,
  -- e o pedido precisa conferir com os termos da modalidade escolhida.
  SELECT qa_policy INTO v_qa_policy FROM public.commercial_pricing_rules
   WHERE version = v_o.pricing_rule_version;
  IF v_t.settlement_model IS DISTINCT FROM v_qa_policy THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'commercial_instrument_template_settlement_model_mismatch',
      'template_code', v_t.template_code,
      'template_settlement_model', v_t.settlement_model,
      'pricing_qa_policy', v_qa_policy);
  END IF;
  IF v_o.pricing_rule_version >= 4 THEN
    v_liq := public.commercial_order_settlement_check(v_o.id);
    IF (v_liq->>'ok')::boolean IS NOT TRUE THEN
      RETURN v_liq;
    END IF;
    -- R4: aprovação jurídica DESTE conteúdo, para ESTA economia, modelo,
    -- modalidade e fidelidade. Qualquer divergência falha fechada.
    SELECT * INTO v_apr FROM public.commercial_instrument_template_approvals a
     WHERE a.template_id = v_t.id AND a.contract_economics_version = v_o.contract_economics_version;
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_approval_missing',
        'template_code', v_t.template_code, 'contract_economics_version', v_o.contract_economics_version);
    END IF;
    IF v_apr.content_sha256 IS DISTINCT FROM v_t.source_hash THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_content_mismatch', 'template_code', v_t.template_code);
    END IF;
    IF v_apr.settlement_model IS DISTINCT FROM v_qa_policy THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_settlement_model_mismatch', 'template_code', v_t.template_code);
    END IF;
    IF NOT (v_o.benefit_settlement_mode = ANY (v_apr.settlement_modes)) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_settlement_mode_not_covered',
        'template_code', v_t.template_code, 'benefit_settlement_mode', v_o.benefit_settlement_mode);
    END IF;
    IF v_apr.applies_to_fidelized IS DISTINCT FROM coalesce(v_o.fidelized, false) THEN
      RETURN pg_catalog.jsonb_build_object('ok', false,
        'reason', 'commercial_instrument_legal_fidelity_mismatch', 'template_code', v_t.template_code);
    END IF;
    -- R4.1: QA em produtos só com procedimento operacional aprovado.
    IF v_o.benefit_settlement_mode = 'direct_benefits' AND coalesce(v_o.qa_in_kind_cents, 0) > 0 THEN
      SELECT * INTO v_qap FROM public.commercial_qa_operational_procedures q
       WHERE q.contract_economics_version = v_o.contract_economics_version
       ORDER BY q.registered_at DESC, q.id LIMIT 1;
      IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('ok', false,
          'reason', 'commercial_qa_operational_procedure_missing',
          'contract_economics_version', v_o.contract_economics_version);
      END IF;
    END IF;
  END IF;

  -- ---- ATIVIDADE CONTRATADA: do catalogo. Bloqueada em producao.
  v_ativ := public.commercial_approved_contract_activity(
              v_o.niche_code, v_o.contract_economics_version);
  IF (v_ativ->>'ok')::boolean IS NOT TRUE THEN
    RETURN v_ativ;
  END IF;

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
    'nfse_taker_cnpj', v_o.nfse_taker_cnpj,
    'execution_unit_id', v_u.id,
    'execution_unit_name', v_u.name,
    'execution_unit_city', v_u.city,
    'execution_unit_uf', v_u.uf,
    'execution_unit_company_id', v_u.company_id,
    'activity_description', v_ativ->>'activity_description',
    'activity_code', v_ativ->>'activity_code',
    'activity_catalog_id', v_ativ->>'activity_catalog_id',
    'activity_source_hash', v_ativ->>'source_hash',
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
    'participation_value_cents', v_sched.ordinary_participation_value_cents,
    'acceptance_actor_id', coalesce(v_ace.linked_auth_user_id, v_o.registered_by),
    'acceptance_at', coalesce(v_ace.accepted_at, v_o.signed_at)));

  -- Proveniencia por REGISTRO CANONICO, nao por "veio do chamador".
  v_prov := pg_catalog.jsonb_build_object(
    'company_legal_name', 'site_company',
    'company_cnpj', 'site_company',
    'company_trade_name', 'site_company',
    'city', 'site_company',
    'uf', 'site_company',
    'nfse_taker_cnpj', 'site_company',
    'representative_full_name', 'site_representative',
    'representative_cpf', 'site_representative',
    'representative_role_title', 'site_representative',
    'representative_authority_status', 'site_representative',
    'execution_unit_id', 'site_unit',
    'execution_unit_name', 'site_unit',
    'execution_unit_city', 'site_unit',
    'execution_unit_uf', 'site_unit',
    'execution_unit_company_id', 'site_unit',
    'activity_description', 'commercial_activity_authority',
    'activity_code', 'commercial_activity_authority',
    'activity_catalog_id', 'commercial_activity_authority',
    'activity_source_hash', 'commercial_activity_authority',
    'participation_value_cents', 'contract_economics_authority',
    'economic_value_cents', 'contract_economics_authority',
    'mei_consideration_cents', 'contract_economics_authority',
    'smallflags_qa_cents', 'contract_economics_authority',
    'smallflags_main_fee_cents', 'contract_economics_authority',
    'smallflags_total_remuneration_cents', 'contract_economics_authority',
    'total_monetary_funding_required_cents', 'contract_economics_authority',
    'contract_economics_version', 'contract_economics_authority',
    'pricing_rule_version', 'contract_economics_authority',
    'master_agreement_id', 'master_agreement',
    'master_legal_document_id', 'master_agreement',
    'master_agreement_version', 'master_agreement',
    'master_document_hash', 'master_agreement',
    'acceptance_actor_id', 'legal_acceptance',
    'acceptance_at', 'legal_acceptance',
    'order_id', 'commercial_order',
    'region_id', 'commercial_order',
    'exclusivity_id', 'commercial_order',
    'niche_code', 'commercial_order',
    'nominal_quantity', 'commercial_order',
    'benefit_settlement_mode', 'commercial_order');

  -- ---- V2 (publicidade visual em veiculos): SO para modelo que exige
  -- especificacao tecnica. O modelo v1.4 nao exige e segue identico.
  -- Sem especificacao APROVADA para a modalidade, falha fechada.
  IF v_t.requires_advertising_spec THEN
    SELECT * INTO v_spec FROM public.commercial_advertising_specs
     WHERE modality = v_t.advertising_modality
       AND lifecycle_status = 'approved';
    IF NOT FOUND THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'commercial_advertising_spec_not_approved',
        'modality', v_t.advertising_modality, 'template_code', v_t.template_code);
    END IF;
    SELECT * INTO v_reg FROM public.commercial_regions WHERE id = v_o.region_id;
    SELECT * INTO v_exc FROM public.commercial_exclusivities WHERE id = v_o.exclusivity_id;
    v_ativ_ef := public.commercial_order_effective_activity(v_o.id);

    v_snap := v_snap || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'advertising_modality', v_spec.modality,
      'advertising_spec_id', v_spec.id,
      'advertising_spec_code', v_spec.spec_code,
      'advertising_spec_version', v_spec.spec_version,
      'advertising_spec_source_hash', v_spec.source_hash,
      'artwork_reference_width_mm', v_spec.artwork_reference_width_mm,
      'artwork_reference_height_mm', v_spec.artwork_reference_height_mm,
      'region_name', v_reg.name,
      'region_uf', v_reg.uf,
      'exclusivity_sequence_number', v_exc.sequence_number,
      'position_code', v_ativ_ef->>'position_code',
      'effective_activity_kind', v_ativ_ef->>'kind',
      'effective_activity_identity', v_ativ_ef->>'identity',
      'fidelized', v_o.fidelized,
      'exclusivity_period_days', v_o.exclusivity_period_days,
      'expected_operation_start', v_o.expected_operation_start));

    -- SF-v1.5: fatos de produção de bandeiras do PEDIDO (snapshot imutável).
    -- Ausentes sob a SF-v1.4; um modelo que os exija falha fechado ali.
    v_snap := v_snap || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'flag_production_new_units', v_o.flag_production_new_units,
      'flag_unit_reference_cents', v_o.flag_unit_reference_cents,
      'flag_production_charge_cents', v_o.flag_production_charge_cents,
      'flag_reuse_set_id', v_o.flag_reuse_set_id,
      'flag_reuse_inspection_id', v_o.flag_reuse_inspection_id));

    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'advertising_modality', 'advertising_spec_authority',
      'advertising_spec_id', 'advertising_spec_authority',
      'advertising_spec_code', 'advertising_spec_authority',
      'advertising_spec_version', 'advertising_spec_authority',
      'advertising_spec_source_hash', 'advertising_spec_authority',
      'artwork_reference_width_mm', 'advertising_spec_authority',
      'artwork_reference_height_mm', 'advertising_spec_authority',
      'region_name', 'commercial_region',
      'region_uf', 'commercial_region',
      'exclusivity_sequence_number', 'commercial_exclusivity',
      'position_code', 'commercial_order',
      'effective_activity_kind', 'commercial_order',
      'effective_activity_identity', 'commercial_order',
      'fidelized', 'commercial_order',
      'exclusivity_period_days', 'commercial_order',
      'expected_operation_start', 'commercial_order');
    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'flag_production_new_units', 'contract_economics_authority',
      'flag_unit_reference_cents', 'contract_economics_authority',
      'flag_production_charge_cents', 'contract_economics_authority',
      'flag_reuse_set_id', 'flag_inventory_authority',
      'flag_reuse_inspection_id', 'flag_inventory_authority');
  END IF;

  -- R3: composicao da modalidade, explicita no instrumento (versao >= 4).
  IF v_o.pricing_rule_version >= 4 THEN
    v_snap := v_snap || pg_catalog.jsonb_build_object(
      'qa_policy', v_qa_policy,
      'settlement_terms_id', v_o.settlement_terms_id,
      'mei_in_kind_cents', v_o.mei_in_kind_cents,
      'mei_cash_funding_cents', v_o.mei_cash_funding_cents,
      'qa_in_kind_cents', v_o.qa_in_kind_cents,
      'qa_cash_cents', v_o.qa_cash_cents,
      'cash_adjustment_cents', v_o.cash_adjustment_cents,
      'instrument_legal_approval_id', v_apr.id,
      'instrument_legal_approval_reference', v_apr.legal_approval_reference,
      'instrument_legal_content_sha256', v_apr.content_sha256,
      'instrument_legal_settlement_modes', pg_catalog.to_jsonb(v_apr.settlement_modes),
      'qa_operational_procedure_id', v_qap.id,
      'qa_operational_procedure_reference', v_qap.procedure_reference,
      'qa_operational_procedure_sha256', v_qap.procedure_document_sha256);
    v_prov := v_prov || pg_catalog.jsonb_build_object(
      'qa_policy', 'contract_economics_authority',
      'settlement_terms_id', 'contract_economics_authority',
      'mei_in_kind_cents', 'contract_economics_authority',
      'mei_cash_funding_cents', 'contract_economics_authority',
      'qa_in_kind_cents', 'contract_economics_authority',
      'qa_cash_cents', 'contract_economics_authority',
      'cash_adjustment_cents', 'contract_economics_authority',
      'instrument_legal_approval_id', 'instrument_legal_approval',
      'instrument_legal_approval_reference', 'instrument_legal_approval',
      'instrument_legal_content_sha256', 'instrument_legal_approval',
      'instrument_legal_settlement_modes', 'instrument_legal_approval',
      'qa_operational_procedure_id', 'qa_operational_procedure',
      'qa_operational_procedure_reference', 'qa_operational_procedure',
      'qa_operational_procedure_sha256', 'qa_operational_procedure');
  END IF;

  -- Falha fechada nomeando CADA fato material ausente.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_snap ? v_campo) THEN
      v_faltam := v_faltam || v_campo;
    END IF;
  END LOOP;
  IF array_length(v_faltam, 1) >= 1 THEN
    RETURN pg_catalog.jsonb_build_object(
      'ok', false, 'reason', 'instrument_snapshot_material_fact_missing',
      'missing_fields', pg_catalog.to_jsonb(v_faltam),
      'template_code', v_t.template_code);
  END IF;

  -- Nenhum fato do snapshot pode ter vindo de fora das autoridades: toda chave
  -- material tem de ter proveniencia declarada.
  FOREACH v_campo IN ARRAY v_t.required_snapshot_fields LOOP
    IF NOT (v_prov ? v_campo) THEN
      RETURN pg_catalog.jsonb_build_object(
        'ok', false, 'reason', 'instrument_snapshot_provenance_undeclared',
        'field', v_campo);
    END IF;
  END LOOP;

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
      pg_catalog.encode(extensions.digest(v_snap::text, 'sha256'), 'hex'));
END;
$function$;

-- ===========================================================================
-- J. EXECUÇÃO: privilégios explícitos das funções guardadas que não são de
--    gatilho (fazem parte do manifesto; iguais em qualquer ambiente)
-- ===========================================================================
REVOKE ALL ON FUNCTION public.commercial_guard_function_entry(regprocedure) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_guard_catalog() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_guard_integrity_failures() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_activation_guard_fingerprint() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_activation_called_by_procedure() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_activate_pricing_rule(integer, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_pricing_activation_preflight(integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_order_settlement_check(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_confirm_manual_bdflow_payment(uuid, bigint, text, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.commercial_guard_catalog() TO service_role;
GRANT EXECUTE ON FUNCTION public.commercial_guard_integrity_failures() TO service_role;
GRANT EXECUTE ON FUNCTION public.commercial_activation_guard_fingerprint() TO service_role;
GRANT EXECUTE ON FUNCTION public.commercial_build_instrument_snapshot(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_confirm_manual_bdflow_payment(uuid, bigint, text, text) TO authenticated;

-- ===========================================================================
-- L. REAFIRMAÇÃO DO TEXTO DO REPOSITÓRIO (preparação operacional)
--    Leitura somente-leitura de Production (2026-11-15) mostrou 7 funções de
--    guarda, aplicadas antes, com texto diferente do repositório: quebras de
--    linha CRLF, comentários removidos, espaços e literais concatenados num
--    só. Normalizados (sem comentários, sem espaços, literais adjacentes
--    unidos) os 7 são IGUAIS ao repositório: a diferença é só de forma.
--    O manifesto é byte a byte; sem esta reafirmação a R4.1 seria recusada em
--    Production (manifesto_guardas_divergente). O texto abaixo é exatamente o
--    do repositório (pg_get_functiondef do banco local); comportamento igual.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.fase2a_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.ceo_emitir_instrumento()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_t jsonb;
  v_b jsonb;
  v_code text;
BEGIN
  IF NEW.status <> 'signed'
     OR NEW.pricing_rule_version IS NULL
     OR NEW.pricing_rule_version < 3 THEN
    RETURN NEW;
  END IF;

  v_t := public.commercial_signable_instrument_template(coalesce(NEW.fidelized, false));
  IF (v_t->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'commercial_instrument_template_unavailable: fidelized=%',
      coalesce(NEW.fidelized, false)
      USING ERRCODE = 'check_violation';
  END IF;

  v_b := public.commercial_build_instrument_snapshot(
    NEW.id, (v_t->>'template_id')::uuid);
  IF (v_b->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'commercial_instrument_snapshot_unavailable: reason=%, detail=%',
      coalesce(v_b->>'reason', 'unknown'), v_b::text
      USING ERRCODE = 'check_violation';
  END IF;

  v_code := public.commercial_next_instrument_code();

  UPDATE public.commercial_exclusivity_orders
     SET instrument_code = v_code,
         instrument_template_id = (v_b->>'template_id')::uuid,
         instrument_template_version = v_b->>'template_version',
         instrument_template_hash = v_b->>'template_source_hash',
         instrument_template_date = (v_b->>'template_date')::date,
         instrument_snapshot = v_b->'snapshot',
         instrument_snapshot_hash = v_b->>'snapshot_hash'
   WHERE id = NEW.id;

  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.ceo_instrumento_imutavel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_primeiro_preenchimento boolean;
  v_build jsonb;
BEGIN
  IF OLD.signed_at IS NULL THEN
    RETURN NEW;
  END IF;

  v_primeiro_preenchimento :=
    OLD.instrument_code IS NULL
    AND OLD.instrument_template_id IS NULL
    AND OLD.instrument_template_version IS NULL
    AND OLD.instrument_template_hash IS NULL
    AND OLD.instrument_template_date IS NULL
    AND OLD.instrument_snapshot IS NULL
    AND OLD.instrument_snapshot_hash IS NULL
    AND NEW.instrument_code IS NOT NULL
    AND NEW.instrument_template_id IS NOT NULL
    AND NEW.instrument_template_version IS NOT NULL
    AND NEW.instrument_template_hash IS NOT NULL
    AND NEW.instrument_template_date IS NOT NULL
    AND NEW.instrument_snapshot IS NOT NULL
    AND NEW.instrument_snapshot_hash IS NOT NULL;

  IF v_primeiro_preenchimento THEN
    -- O preenchimento permitido tem de ser exatamente o snapshot que as
    -- autoridades do servidor constroem para este pedido e este modelo.
    v_build := public.commercial_build_instrument_snapshot(OLD.id, NEW.instrument_template_id);
    IF (v_build->>'ok')::boolean IS NOT TRUE
       OR NEW.instrument_template_version IS DISTINCT FROM v_build->>'template_version'
       OR NEW.instrument_template_date IS DISTINCT FROM (v_build->>'template_date')::date
       OR NEW.instrument_template_hash IS DISTINCT FROM v_build->>'template_source_hash'
       OR NEW.instrument_snapshot IS DISTINCT FROM v_build->'snapshot'
       OR NEW.instrument_snapshot_hash IS DISTINCT FROM v_build->>'snapshot_hash' THEN
      RAISE EXCEPTION 'instrumento_emissao_invalida: preenchimento nao corresponde as autoridades do servidor'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.instrument_snapshot IS DISTINCT FROM OLD.instrument_snapshot
     OR NEW.instrument_code IS DISTINCT FROM OLD.instrument_code
     OR NEW.instrument_template_id IS DISTINCT FROM OLD.instrument_template_id
     OR NEW.instrument_template_version IS DISTINCT FROM OLD.instrument_template_version
     OR NEW.instrument_template_hash IS DISTINCT FROM OLD.instrument_template_hash
     OR NEW.instrument_template_date IS DISTINCT FROM OLD.instrument_template_date
     OR NEW.instrument_snapshot_hash IS DISTINCT FROM OLD.instrument_snapshot_hash
     OR NEW.mei_consideration_cents IS DISTINCT FROM OLD.mei_consideration_cents
     OR NEW.smallflags_qa_cents IS DISTINCT FROM OLD.smallflags_qa_cents
     OR NEW.order_version IS DISTINCT FROM OLD.order_version
     OR NEW.document_hash IS DISTINCT FROM OLD.document_hash THEN
    RAISE EXCEPTION
      'instrumento assinado e imutavel: snapshot, identidade, versao, hash e decomposicao economica nao podem ser alterados apos signed_at'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.ceo_snapshot_v14_imutavel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF NEW.contract_economics_version          IS DISTINCT FROM OLD.contract_economics_version
  OR NEW.mei_consideration_cents             IS DISTINCT FROM OLD.mei_consideration_cents
  OR NEW.smallflags_qa_cents                 IS DISTINCT FROM OLD.smallflags_qa_cents
  OR NEW.smallflags_main_fee_cents           IS DISTINCT FROM OLD.smallflags_main_fee_cents
  OR NEW.smallflags_total_remuneration_cents IS DISTINCT FROM OLD.smallflags_total_remuneration_cents
  OR NEW.mei_cash_funding_cents              IS DISTINCT FROM OLD.mei_cash_funding_cents THEN
    -- Só bloqueia quando já havia snapshot: preencher de NULL uma única vez
    -- é a própria criação do snapshot, não uma reescrita.
    IF OLD.contract_economics_version IS NOT NULL THEN
      RAISE EXCEPTION
        'pedido_imutavel: snapshot economico v1.4 e imutavel (id=%).', OLD.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.cci_preencher_fatos_materiais()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_cnpj   text;
  v_unidade uuid;
  v_qtd    integer;
BEGIN
  -- O CNPJ da empresa pode estar gravado formatado; o tomador e sempre em
  -- digitos. Normalizar aqui evita que a formatacao do cadastro vire divergencia
  -- de tomador.
  SELECT pg_catalog.regexp_replace(c.cnpj, '[^0-9]', '', 'g') INTO v_cnpj
    FROM public.site_partner_companies c WHERE c.id = NEW.company_id;

  IF NEW.nfse_taker_cnpj IS NULL THEN
    NEW.nfse_taker_cnpj := v_cnpj;
  ELSIF pg_catalog.regexp_replace(NEW.nfse_taker_cnpj, '[^0-9]', '', 'g')
        IS DISTINCT FROM v_cnpj THEN
    -- O instrumento congelado admite filial ou outro CNPJ tomador, mas exige
    -- que esse CNPJ e a autoridade do representante dele sejam validamente
    -- identificados. O schema nao modela isso ainda, e fingir que modela seria
    -- pior que recusar.
    RAISE EXCEPTION
      'alternate_nfse_taker_not_supported: no MVP fundador o tomador da NFS-e e '
      'o CNPJ da contratante. CNPJ de filial exige modelagem propria e '
      'verificacao de autoridade do representante.'
      USING ERRCODE = 'check_violation';
  ELSE
    NEW.nfse_taker_cnpj := v_cnpj;
  END IF;

  IF NEW.execution_unit_id IS NULL THEN
    SELECT count(*) INTO v_qtd FROM public.site_partner_units u
     WHERE u.company_id = NEW.company_id AND u.status = 'active';
    IF v_qtd = 1 THEN
      SELECT u.id INTO v_unidade FROM public.site_partner_units u
       WHERE u.company_id = NEW.company_id AND u.status = 'active';
      NEW.execution_unit_id := v_unidade;
    END IF;
    -- Com zero ou com duas ou mais, fica NULL de proposito. O aceite juridico
    -- recusa intencao sem unidade, e o titular escolhe por RPC.
  END IF;

  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.ceo_preencher_fatos_materiais()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_cnpj text;
BEGIN
  -- O CNPJ da empresa pode estar gravado formatado; o tomador e sempre em
  -- digitos. Normalizar aqui evita que a formatacao do cadastro vire divergencia
  -- de tomador.
  SELECT pg_catalog.regexp_replace(c.cnpj, '[^0-9]', '', 'g') INTO v_cnpj
    FROM public.site_partner_companies c WHERE c.id = NEW.company_id;

  IF NEW.nfse_taker_cnpj IS NULL THEN
    NEW.nfse_taker_cnpj := v_cnpj;
  ELSIF pg_catalog.regexp_replace(NEW.nfse_taker_cnpj, '[^0-9]', '', 'g')
        IS DISTINCT FROM v_cnpj THEN
    RAISE EXCEPTION
      'alternate_nfse_taker_not_supported: no MVP fundador o tomador da NFS-e e '
      'o CNPJ da contratante.'
      USING ERRCODE = 'check_violation';
  ELSE
    NEW.nfse_taker_cnpj := v_cnpj;
  END IF;

  -- A unidade de execucao do pedido vem da INTENCAO, que ja foi validada. Na
  -- venda manual (sem intencao) ela e pre-selecionada so quando inequivoca.
  IF NEW.execution_unit_id IS NULL AND NEW.checkout_intent_id IS NOT NULL THEN
    SELECT i.execution_unit_id INTO NEW.execution_unit_id
      FROM public.commercial_checkout_intents i WHERE i.id = NEW.checkout_intent_id;
  END IF;
  IF NEW.execution_unit_id IS NULL THEN
    SELECT u.id INTO NEW.execution_unit_id
      FROM public.site_partner_units u
     WHERE u.company_id = NEW.company_id AND u.status = 'active'
     GROUP BY u.id
     HAVING (SELECT count(*) FROM public.site_partner_units u2
              WHERE u2.company_id = NEW.company_id AND u2.status = 'active') = 1;
  END IF;

  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION public.ceo_exigir_instrumento_quando_assinavel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_t public.commercial_instrument_templates%ROWTYPE;
BEGIN
  IF NEW.status <> 'signed'
     OR NEW.pricing_rule_version IS NULL
     OR NEW.pricing_rule_version < 3 THEN
    RETURN NEW;
  END IF;

  IF NEW.instrument_code IS NOT NULL
     OR NEW.instrument_template_id IS NOT NULL
     OR NEW.instrument_template_version IS NOT NULL
     OR NEW.instrument_template_hash IS NOT NULL
     OR NEW.instrument_template_date IS NOT NULL
     OR NEW.instrument_snapshot IS NOT NULL
     OR NEW.instrument_snapshot_hash IS NOT NULL THEN
    RAISE EXCEPTION 'instrumento_prepreenchido_nao_permitido: fatos instrumentais sao emitidos pelo servidor'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_t FROM public.commercial_instrument_templates
   WHERE lifecycle_status = 'signable'
     AND applies_to_fidelized = coalesce(NEW.fidelized, false);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'commercial_instrument_template_unavailable: fidelized=%',
      coalesce(NEW.fidelized, false)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$function$

;


-- ===========================================================================
-- K. MANIFESTO APROVADO R4.1 — o mesmo de docs/release/R41_MANIFESTO_GUARDAS.json
--    (SHA-256 bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7). O gatilho só aceita se for IGUAL à configuração viva:
--    ambiente com guarda divergente faz esta migration falhar inteira.
-- ===========================================================================
INSERT INTO public.commercial_guard_manifests (manifest_label, catalog, source_reference)
VALUES ('R4.1', $manifesto_r41${"format": "smallflags-guard-catalog/1 (R4.1, sha256)", "tables": [{"table": "public.commercial_checkout_intents", "present": true}, {"table": "public.commercial_exclusivity_orders", "present": true}, {"table": "public.commercial_flag_set_inspections", "present": true}, {"table": "public.commercial_flag_sets", "present": true}, {"table": "public.commercial_guard_manifests", "present": true}, {"table": "public.commercial_instrument_template_approvals", "present": true}, {"table": "public.commercial_payments", "present": true}, {"table": "public.commercial_pricing_activation_approvals", "present": true}, {"table": "public.commercial_pricing_activation_log", "present": true}, {"table": "public.commercial_pricing_rules", "present": true}, {"table": "public.commercial_pricing_schedule", "present": true}, {"table": "public.commercial_qa_operational_procedures", "present": true}, {"table": "public.commercial_settlement_terms", "present": true}], "triggers": {"public.commercial_flag_sets.cfs_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_flag_sets_protect()", "deferrable": false, "definition": "CREATE TRIGGER cfs_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_flag_sets FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_sets_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "2690264d59ff4dcb2b76e2e13059b8de8f7a7f474d2a256ba426b665fc817626", "definition_sha256": "d7cd3099ed10f7b31ea2d47f792af9d1690504e1154a997b9dde56edf6bd848b", "initially_deferred": false}, "public.commercial_payments.trg_cp_touch": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.fase2a_touch_updated_at()", "deferrable": false, "definition": "CREATE TRIGGER trg_cp_touch BEFORE UPDATE ON public.commercial_payments FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "f0fd417ae71a52338a298bf853ce507a8bc036c54c4f14cfea417ffffb7abc8f", "definition_sha256": "61b182d54029d5ebd2d91dfe1ae7abc80e1afc974323bb7180cabdb2bc6b604d", "initially_deferred": false}, "public.commercial_payments.trg_cp_proteger": {"when": null, "state": "O", "tgtype": 27, "columns": "", "function": "public.cp_proteger()", "deferrable": false, "definition": "CREATE TRIGGER trg_cp_proteger BEFORE DELETE OR UPDATE ON public.commercial_payments FOR EACH ROW EXECUTE FUNCTION public.cp_proteger()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "4f74486afa623f948f78ff3a90c8301892aed7da6e769c4a8d8c8e213d0f27be", "definition_sha256": "e6299f3b45f6c28dd9491915580a6f6d4d979a4a18f28dc232fe6a2312a4ae7f", "initially_deferred": false}, "public.commercial_pricing_rules.cpr_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_pricing_rules_protect()", "deferrable": false, "definition": "CREATE TRIGGER cpr_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_pricing_rules FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_rules_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "dcf4da0f184fe75d5919610690b0331d60b7c3145addd4d663a24ff4f6f31146", "definition_sha256": "b4aa3089c0860976b792a242dd2e300c8620cad898bdbc473ceec950cefca990", "initially_deferred": false}, "public.commercial_guard_manifests.cgm_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_guard_manifests_protect()", "deferrable": false, "definition": "CREATE TRIGGER cgm_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_guard_manifests FOR EACH ROW EXECUTE FUNCTION public.commercial_guard_manifests_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bc270768c7a81a5923a3bc1d303253925e1765e27540bf26b8618222d16b916e", "definition_sha256": "fc0ea03fced5b0738eed71512ebc1ef291d7a1ed2766bacf3a2d7364e21145b1", "initially_deferred": false}, "public.commercial_pricing_schedule.cps_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_pricing_schedule_protect()", "deferrable": false, "definition": "CREATE TRIGGER cps_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_pricing_schedule FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_schedule_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "334a31ec2adb96c33c47f422ab3a85a736ad18221dc55a1a99dec9811a8fc041", "definition_sha256": "b5e464973ac583f9d65585baaa82799341c4d54eaad6248466531244333e42a6", "initially_deferred": false}, "public.commercial_settlement_terms.cst_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_settlement_terms_protect()", "deferrable": false, "definition": "CREATE TRIGGER cst_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_settlement_terms FOR EACH ROW EXECUTE FUNCTION public.commercial_settlement_terms_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "3a5c45565bec15feeaa7863a01015351f1638acbe2bd77a882960c56a2d00da2", "definition_sha256": "da68b0fe1a20e56776f08a2a3e3d7f188db6861b6e32f2b465e22dc55100cdb7", "initially_deferred": false}, "public.commercial_flag_sets.cfs_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_flag_inventory_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cfs_protect_truncate BEFORE TRUNCATE ON public.commercial_flag_sets FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_flag_inventory_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bb12a8f32a55d6e71a5971e089e8756e9b2e86ddf007c999ea73076d1fe7baf4", "definition_sha256": "19bd053108da69913fa618a37e798e0fe21fbf2234ea75cc465ff9058cf4ba81", "initially_deferred": false}, "public.commercial_exclusivity_orders.trg_ceo_touch": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.fase2a_touch_updated_at()", "deferrable": false, "definition": "CREATE TRIGGER trg_ceo_touch BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.fase2a_touch_updated_at()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "f0fd417ae71a52338a298bf853ce507a8bc036c54c4f14cfea417ffffb7abc8f", "definition_sha256": "563bc51d7a8a6bf51168d2b2580dcb6bdf86f1adf6b7d22c85748076aaedf5e7", "initially_deferred": false}, "public.commercial_flag_set_inspections.cfi_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_flag_set_inspections_protect()", "deferrable": false, "definition": "CREATE TRIGGER cfi_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_flag_set_inspections FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_set_inspections_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "da606f958f5af26fdf2b0ce9ba2d45aa2056aa76d9f7b9e641bc97e2b3e58932", "definition_sha256": "5dcde04f40a706b69419c37b0b0e5d3ea5d91f6c6793a2028630b3c871011726", "initially_deferred": false}, "public.commercial_payments.cp_valor_confere_pedido": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cp_valor_confere_pedido()", "deferrable": false, "definition": "CREATE TRIGGER cp_valor_confere_pedido BEFORE INSERT ON public.commercial_payments FOR EACH ROW EXECUTE FUNCTION public.cp_valor_confere_pedido()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "8aa0dccba55b27866c768dd03fbf8d8e3b03d72af60de9a8058094a2bbf61c28", "definition_sha256": "65dced9887329d202bfec38886491be8ac81797b041ebf2d8ad3d8a037677f5c", "initially_deferred": false}, "public.commercial_exclusivity_orders.trg_ceo_protect": {"when": null, "state": "O", "tgtype": 27, "columns": "", "function": "public.m2_orders_protect()", "deferrable": false, "definition": "CREATE TRIGGER trg_ceo_protect BEFORE DELETE OR UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.m2_orders_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "760f2f2de477e05f7d735d87cf49773ff3833347bfcb2b5a12cb3f160fb1f89f", "definition_sha256": "58b552a3c0a00efa697f439c30492979a23290b0c77938456b54a1bf36cec7bd", "initially_deferred": false}, "public.commercial_pricing_rules.cpr_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cpr_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_rules FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "5ac37ebab8b0edc8ae8ffc5decf8710e4f6b08b62136b80060c7874e4477cb8e", "initially_deferred": false}, "public.commercial_pricing_activation_log.cpal_protect": {"when": null, "state": "O", "tgtype": 27, "columns": "", "function": "public.commercial_pricing_activation_log_protect()", "deferrable": false, "definition": "CREATE TRIGGER cpal_protect BEFORE DELETE OR UPDATE ON public.commercial_pricing_activation_log FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_log_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "14f69adce2ca6f8db8aeff765f2586090c7915b493ef22607b4cd16e6d3ce76f", "definition_sha256": "8a2cd7c2fa9b6a526ab177710d8a6e47362162b459daffcacca1e40b9c7ad908", "initially_deferred": false}, "public.commercial_checkout_intents.cci_preencher_fatos": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_preencher_fatos_materiais()", "deferrable": false, "definition": "CREATE TRIGGER cci_preencher_fatos BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_preencher_fatos_materiais()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "e8f11915eee4edce7f485b10659a3b55e3648ec49456a5f98cd4a2d345307a2b", "definition_sha256": "4eb75e7db1801bef5f3eee45ab10a784a44f3ff701d082ce4d2c118cb66493ea", "initially_deferred": false}, "public.commercial_guard_manifests.cgm_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cgm_protect_truncate BEFORE TRUNCATE ON public.commercial_guard_manifests FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "e4e5c71d6746a5bb0ba5b58fdff3af610476f53f1a67c55ce797f0906e9148a6", "initially_deferred": false}, "public.commercial_pricing_schedule.cps_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cps_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_schedule FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "6633728ebde5056762302b66ff4f6b145f20b34b6e8a3e2cc194329f504e3632", "initially_deferred": false}, "public.commercial_settlement_terms.cst_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cst_protect_truncate BEFORE TRUNCATE ON public.commercial_settlement_terms FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "33a5d29ca46da23a1b977d44cb55ab9444291cade69880187f8a2ca63cfbfa4f", "initially_deferred": false}, "public.commercial_checkout_intents.cci_segmento_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_segment_snapshot_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER cci_segmento_imutavel BEFORE UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "044adf339fe704030567db9f03719eb1546c7f716c49930cb69816923be555a9", "definition_sha256": "092bf8d532482a93d8723d2cd5f5c637e772154eb7fd959e55235f0d30cd3ce3", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_preencher_fatos": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_preencher_fatos_materiais()", "deferrable": false, "definition": "CREATE TRIGGER ceo_preencher_fatos BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_preencher_fatos_materiais()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "4ec5ce9bd2913a981fd30937ee7765d8081db0afd844a92e1c2160ec13cfb972", "definition_sha256": "2b28b94bff75e42db350d501b02a3b7e837ad291e10c67455753e288a40cb5e4", "initially_deferred": false}, "public.commercial_qa_operational_procedures.cqop_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_qa_operational_procedures_protect()", "deferrable": false, "definition": "CREATE TRIGGER cqop_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_qa_operational_procedures FOR EACH ROW EXECUTE FUNCTION public.commercial_qa_operational_procedures_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "86436f51ea9a9a189569ac28e5980cd0074eb12cb75bf892bad96206fb80a591", "definition_sha256": "62aaf291f5148b0dc0ae32e74415441ac2ec1e31a82f6e21973614f0c0495311", "initially_deferred": false}, "public.commercial_checkout_intents.cci_bandeiras_imutaveis": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_flag_facts_imutaveis()", "deferrable": false, "definition": "CREATE TRIGGER cci_bandeiras_imutaveis BEFORE UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_facts_imutaveis()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "7c432227c054e2e17e81ad3b8a8e2759b6afcad2165e693e37f9111dca67ec2b", "definition_sha256": "081aad32c1ed444a205ec4c43a002d6a71a16fdedd4a20889fce477f22c93b85", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_segmento_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_segment_snapshot_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_segmento_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.commercial_segment_snapshot_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "044adf339fe704030567db9f03719eb1546c7f716c49930cb69816923be555a9", "definition_sha256": "a97532e32009ae2e02e7f429e232e371902c282cd4e144ed3106ac372580aaf6", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_emitir_instrumento": {"when": null, "state": "O", "tgtype": 5, "columns": "", "function": "public.ceo_emitir_instrumento()", "deferrable": false, "definition": "CREATE TRIGGER ceo_emitir_instrumento AFTER INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_emitir_instrumento()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "722fce1aeab8bc66225a7bef9556fe38d308e9478a0eb3ea3649224345897ae7", "definition_sha256": "cb1564e9f602799017054547d8b3c157761491755bc6017940d960669ed5e177", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_exigir_instrumento": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_exigir_instrumento_quando_assinavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_exigir_instrumento BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_exigir_instrumento_quando_assinavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "26f7000b7047e0a52eaa701d53cd09e2e351cd4a87d59c5af5c98702196e8308", "definition_sha256": "afed0e0d33d4379e5e1ceb589aecc7225e12723cd63a09fe7315d793ec16f07e", "initially_deferred": false}, "public.commercial_flag_set_inspections.cfi_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_flag_inventory_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cfi_protect_truncate BEFORE TRUNCATE ON public.commercial_flag_set_inspections FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_flag_inventory_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bb12a8f32a55d6e71a5971e089e8756e9b2e86ddf007c999ea73076d1fe7baf4", "definition_sha256": "6a342d851c3f5982542f5e63090acbe944c24ddee180731074fd8bb43308acfe", "initially_deferred": false}, "public.commercial_pricing_activation_approvals.cpaa_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_pricing_activation_approvals_protect()", "deferrable": false, "definition": "CREATE TRIGGER cpaa_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_pricing_activation_approvals FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_approvals_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "131059cb96fbcb894a09cb3e551282b9b5144d4c793f4150029afa1e7f71da27", "definition_sha256": "dc5099952532325cd2ee6347f8b9af9f4de20199d2ec291a8b2a2f1a3ee3982a", "initially_deferred": false}, "public.commercial_checkout_intents.cci_proteger_snapshot_trg": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.cci_proteger_snapshot()", "deferrable": false, "definition": "CREATE TRIGGER cci_proteger_snapshot_trg BEFORE UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_proteger_snapshot()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "fdb064d35ad871f0071b8d0d4f9d99d080ae1f09826f68ad4e86d9fee412ab40", "definition_sha256": "68427d6a4f344d8eaae271acb39819d48fc451a900005af8a1ff82203030b585", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_bandeiras_imutaveis": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.commercial_flag_facts_imutaveis()", "deferrable": false, "definition": "CREATE TRIGGER ceo_bandeiras_imutaveis BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_facts_imutaveis()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "7c432227c054e2e17e81ad3b8a8e2759b6afcad2165e693e37f9111dca67ec2b", "definition_sha256": "48d0c9cd0a2251cb20181a0ffb79277c54f7e261cfe0ac7679f07a631d34b997", "initially_deferred": false}, "public.commercial_flag_set_inspections.cfi_bloquear_conjunto": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.commercial_flag_set_lock_for_inspection()", "deferrable": false, "definition": "CREATE TRIGGER cfi_bloquear_conjunto BEFORE INSERT ON public.commercial_flag_set_inspections FOR EACH ROW EXECUTE FUNCTION public.commercial_flag_set_lock_for_inspection()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "2271272d240a23dcd3007c6b7ce742459afb326d1102433995df2b4142301674", "definition_sha256": "a623c8387cf050cc6bfca4f318f92d3571c346bac0eb10216c0eff1ec0916218", "initially_deferred": false}, "public.commercial_checkout_intents.cci_aplicar_autoridade_v14": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_aplicar_autoridade_v14()", "deferrable": false, "definition": "CREATE TRIGGER cci_aplicar_autoridade_v14 BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_aplicar_autoridade_v14()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "d71265048360c982d951e77de2830fd3d23e0c97929b57605d1d4faa3a909f90", "definition_sha256": "a1421ae18d7ff1efcf4d66a74a71086aa412c8281905c4c7dda4eae085adcb67", "initially_deferred": false}, "public.commercial_checkout_intents.cci_portao_autoatendimento": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_portao_autoatendimento()", "deferrable": false, "definition": "CREATE TRIGGER cci_portao_autoatendimento BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_portao_autoatendimento()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "55f3678fdd292f426142f8a31fc8a49c023312b025bd1478251ea86756f52ae1", "definition_sha256": "79adddb7c04966063432e3d8575d14a437f84500a23a7ccb97cb01406da901a7", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_instrumento_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.ceo_instrumento_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_instrumento_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_instrumento_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "bfdcb2188b8757ec8b4e55d40db7eef435f9e8456575343eb8e4e455981dea0d", "definition_sha256": "f78c4e15a45d01b052d372ef8c1327dfb0f3a41ba813f0724c9b0f24744ba7a5", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_segmento_da_intencao": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_segmento_da_intencao()", "deferrable": false, "definition": "CREATE TRIGGER ceo_segmento_da_intencao BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_segmento_da_intencao()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "a544f81886260476dfec5995d3ec1215bbc17e541042c21ba4492607e4657df8", "definition_sha256": "71938d7bced8dbc77639420a0373eb5b258c5b9bc2b33e96ab40ff86e237c9b2", "initially_deferred": false}, "public.commercial_exclusivity_orders.trg_ceo_origem_pagamento": {"when": null, "state": "O", "tgtype": 23, "columns": "", "function": "public.ceo_marcar_origem_manual()", "deferrable": false, "definition": "CREATE TRIGGER trg_ceo_origem_pagamento BEFORE INSERT OR UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_marcar_origem_manual()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "c52e0d3ac23ab3c33151edc905b25346d0cf812b412533bcb9dd7bd574ff9086", "definition_sha256": "77895cf9ce3d11af7c0312ab6ac8e595722e91072bc931da4d3f3b4a1eb9e777", "initially_deferred": false}, "public.commercial_instrument_template_approvals.citap_protect": {"when": null, "state": "O", "tgtype": 31, "columns": "", "function": "public.commercial_instrument_template_approvals_protect()", "deferrable": false, "definition": "CREATE TRIGGER citap_protect BEFORE INSERT OR DELETE OR UPDATE ON public.commercial_instrument_template_approvals FOR EACH ROW EXECUTE FUNCTION public.commercial_instrument_template_approvals_protect()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "c77e8e880308a73f9f6ee9751e501c189b1226539b56f8278c2328af0abb803e", "definition_sha256": "d8d67c88181ba5672a4ee1bf1e5b15236028b1c5d4e8764cbb7417b80cb5cb45", "initially_deferred": false}, "public.commercial_checkout_intents.cci_liquidar_modalidade_v15": {"when": null, "state": "O", "tgtype": 23, "columns": "", "function": "public.cci_liquidar_modalidade_v15()", "deferrable": false, "definition": "CREATE TRIGGER cci_liquidar_modalidade_v15 BEFORE INSERT OR UPDATE ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_liquidar_modalidade_v15()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "0bdce46677c0c4047c97f1ac0d8db2696b7eeff926a393e393a07fd49f4ab909", "definition_sha256": "4f99069e57b8738572a7c3c1a5cfb6749c2787c24a040241392b5f817918d32f", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_snapshot_v14_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.ceo_snapshot_v14_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_snapshot_v14_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_snapshot_v14_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "5c68326fdceca35d2fe6f5e573e6c677e7560d6b59289fd02db5324d7a21a4e7", "definition_sha256": "4764bf11bfe33265cc07c405c4cc4127e3d554f164de50965561a2396e706678", "initially_deferred": false}, "public.commercial_pricing_activation_log.cpal_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cpal_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_activation_log FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "3d7a811c361d8583b8643363348fa7663c799408fa89740984026e0a8fb68185", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_aplicar_autoridade_v14": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_aplicar_autoridade_v14()", "deferrable": false, "definition": "CREATE TRIGGER ceo_aplicar_autoridade_v14 BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_aplicar_autoridade_v14()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "aae838a149a33f7d720406fc023dc2eb2f6ac807507ac8eeab68527564423bb0", "definition_sha256": "47945a7ec8bc97e34feebda0dbf3c022d0b34333260c16e9cc7827175e0b6977", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_liquidacao_v15_imutavel": {"when": null, "state": "O", "tgtype": 19, "columns": "", "function": "public.ceo_liquidacao_v15_imutavel()", "deferrable": false, "definition": "CREATE TRIGGER ceo_liquidacao_v15_imutavel BEFORE UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_liquidacao_v15_imutavel()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "69ea27bbd7eac181b8f976f4f74237c96682b4ba2a4674503eb92638e35675e1", "definition_sha256": "bc7f62b342dc0799ff7986c3857060ec05adc36cfca9bd3609c5b8fb10837f49", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_liquidar_modalidade_v15": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_liquidar_modalidade_v15()", "deferrable": false, "definition": "CREATE TRIGGER ceo_liquidar_modalidade_v15 BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_liquidar_modalidade_v15()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b879abd9a8f44d9f497ac6b2601e813a6583bd2428e57b0c4f166a13d2681003", "definition_sha256": "8d86138970115b4bf658d16fa6041989aad9e089d910bd01940f31828037bbf3", "initially_deferred": false}, "public.commercial_checkout_intents.cci_validar_producao_bandeiras": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.cci_validar_producao_bandeiras()", "deferrable": false, "definition": "CREATE TRIGGER cci_validar_producao_bandeiras BEFORE INSERT ON public.commercial_checkout_intents FOR EACH ROW EXECUTE FUNCTION public.cci_validar_producao_bandeiras()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "f86a78e0d0c97884245c66dd3fc2a31ec934e94cf3a53bf563d718a6e672918b", "definition_sha256": "beec37717a26e5671f4aa82ae697cab44339e50622115143579a5a7647335a7d", "initially_deferred": false}, "public.commercial_qa_operational_procedures.cqop_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cqop_protect_truncate BEFORE TRUNCATE ON public.commercial_qa_operational_procedures FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "54dfcd5195584c7f474d1eed88bd6c32edb0ee1dc79ac212420cc00da38a1401", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot": {"when": null, "state": "O", "tgtype": 23, "columns": "", "function": "public.ceo_pagamento_confere_snapshot()", "deferrable": false, "definition": "CREATE TRIGGER ceo_pagamento_confere_snapshot BEFORE INSERT OR UPDATE ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_pagamento_confere_snapshot()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "44759806656f355ffff3d0f0bcc72f3127ac196b7dd0361f4910beca6b964962", "definition_sha256": "385a7e6b153d7700bc86913f88d6a498eb46b1dd7602ea0dd909fd8c34257d3c", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_validar_producao_bandeiras": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.ceo_validar_producao_bandeiras()", "deferrable": false, "definition": "CREATE TRIGGER ceo_validar_producao_bandeiras BEFORE INSERT ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_validar_producao_bandeiras()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "ff8a4e146036fd361ca4e14d2a650764c4b59b4c09a6531ade0aeda04450ad7b", "definition_sha256": "13090adec88f0356015f17a73b044e441e25ed47a0a2b4c0dd1224da0848c00d", "initially_deferred": false}, "public.commercial_pricing_activation_approvals.cpaa_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER cpaa_protect_truncate BEFORE TRUNCATE ON public.commercial_pricing_activation_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "9f0587c3ec343af7a50674986e2bd4599a6563b2258e40884e73c56667a2e0f6", "initially_deferred": false}, "public.commercial_instrument_template_approvals.citap_protect_truncate": {"when": null, "state": "O", "tgtype": 34, "columns": "", "function": "public.commercial_pricing_protect_truncate()", "deferrable": false, "definition": "CREATE TRIGGER citap_protect_truncate BEFORE TRUNCATE ON public.commercial_instrument_template_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.commercial_pricing_protect_truncate()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b", "definition_sha256": "69bf7c3e038f1d5fe80dc97f0844f68504ca2f9760d0abb2b615154a3be40605", "initially_deferred": false}, "public.commercial_pricing_activation_log.cpal_somente_pelo_procedimento": {"when": null, "state": "O", "tgtype": 7, "columns": "", "function": "public.commercial_pricing_activation_log_guard()", "deferrable": false, "definition": "CREATE TRIGGER cpal_somente_pelo_procedimento BEFORE INSERT ON public.commercial_pricing_activation_log FOR EACH ROW EXECUTE FUNCTION public.commercial_pricing_activation_log_guard()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "e35df937f3a0064e62fab1eb576b3c4fea5f75eccd58e05569264931654c8fe2", "definition_sha256": "32359304d51ccb227c25884421d42087a26579f22382264e3bfc29a7c9d61bc7", "initially_deferred": false}, "public.commercial_exclusivity_orders.ceo_revalidar_reutilizacao_bandeiras": {"when": null, "state": "O", "tgtype": 21, "columns": "23", "function": "public.ceo_revalidar_reutilizacao_bandeiras()", "deferrable": false, "definition": "CREATE TRIGGER ceo_revalidar_reutilizacao_bandeiras AFTER INSERT OR UPDATE OF payment_status ON public.commercial_exclusivity_orders FOR EACH ROW EXECUTE FUNCTION public.ceo_revalidar_reutilizacao_bandeiras()", "args_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "function_sha256": "3e5b9e40d240d9914949ed322ce3b8abdc54f147aa866bc29b6136f75568ddc5", "definition_sha256": "97c03227b4a9bd27fc536217d3971ff0549bc795a22f60257762c2f39d7377c2", "initially_deferred": false}}, "functions": {"public.cp_proteger()": {"definition_sha256": "4f74486afa623f948f78ff3a90c8301892aed7da6e769c4a8d8c8e213d0f27be"}, "public.m2_orders_protect()": {"definition_sha256": "760f2f2de477e05f7d735d87cf49773ff3833347bfcb2b5a12cb3f160fb1f89f"}, "public.cci_proteger_snapshot()": {"definition_sha256": "fdb064d35ad871f0071b8d0d4f9d99d080ae1f09826f68ad4e86d9fee412ab40"}, "public.ceo_emitir_instrumento()": {"definition_sha256": "722fce1aeab8bc66225a7bef9556fe38d308e9478a0eb3ea3649224345897ae7"}, "public.cp_valor_confere_pedido()": {"definition_sha256": "8aa0dccba55b27866c768dd03fbf8d8e3b03d72af60de9a8058094a2bbf61c28"}, "public.fase2a_touch_updated_at()": {"definition_sha256": "f0fd417ae71a52338a298bf853ce507a8bc036c54c4f14cfea417ffffb7abc8f"}, "public.ceo_instrumento_imutavel()": {"definition_sha256": "bfdcb2188b8757ec8b4e55d40db7eef435f9e8456575343eb8e4e455981dea0d"}, "public.ceo_marcar_origem_manual()": {"definition_sha256": "c52e0d3ac23ab3c33151edc905b25346d0cf812b412533bcb9dd7bd574ff9086"}, "public.ceo_segmento_da_intencao()": {"definition_sha256": "a544f81886260476dfec5995d3ec1215bbc17e541042c21ba4492607e4657df8"}, "public.commercial_guard_catalog()": {"execute": ["service_role"], "definition_sha256": "ca9c1bd97cec36a68d1eb3f15e00e2f1de5f9882b96f752cb6c1dee03f395a82"}, "public.ceo_snapshot_v14_imutavel()": {"definition_sha256": "5c68326fdceca35d2fe6f5e573e6c677e7560d6b59289fd02db5324d7a21a4e7"}, "public.cci_aplicar_autoridade_v14()": {"definition_sha256": "d71265048360c982d951e77de2830fd3d23e0c97929b57605d1d4faa3a909f90"}, "public.cci_portao_autoatendimento()": {"definition_sha256": "55f3678fdd292f426142f8a31fc8a49c023312b025bd1478251ea86756f52ae1"}, "public.ceo_aplicar_autoridade_v14()": {"definition_sha256": "aae838a149a33f7d720406fc023dc2eb2f6ac807507ac8eeab68527564423bb0"}, "public.cci_liquidar_modalidade_v15()": {"definition_sha256": "0bdce46677c0c4047c97f1ac0d8db2696b7eeff926a393e393a07fd49f4ab909"}, "public.ceo_liquidacao_v15_imutavel()": {"definition_sha256": "69ea27bbd7eac181b8f976f4f74237c96682b4ba2a4674503eb92638e35675e1"}, "public.ceo_liquidar_modalidade_v15()": {"definition_sha256": "b879abd9a8f44d9f497ac6b2601e813a6583bd2428e57b0c4f166a13d2681003"}, "public.commercial_flag_sets_protect()": {"definition_sha256": "2690264d59ff4dcb2b76e2e13059b8de8f7a7f474d2a256ba426b665fc817626"}, "public.cci_preencher_fatos_materiais()": {"definition_sha256": "e8f11915eee4edce7f485b10659a3b55e3648ec49456a5f98cd4a2d345307a2b"}, "public.ceo_preencher_fatos_materiais()": {"definition_sha256": "4ec5ce9bd2913a981fd30937ee7765d8081db0afd844a92e1c2160ec13cfb972"}, "public.cci_validar_producao_bandeiras()": {"definition_sha256": "f86a78e0d0c97884245c66dd3fc2a31ec934e94cf3a53bf563d718a6e672918b"}, "public.ceo_pagamento_confere_snapshot()": {"definition_sha256": "44759806656f355ffff3d0f0bcc72f3127ac196b7dd0361f4910beca6b964962"}, "public.ceo_validar_producao_bandeiras()": {"definition_sha256": "ff8a4e146036fd361ca4e14d2a650764c4b59b4c09a6531ade0aeda04450ad7b"}, "public.commercial_flag_facts_imutaveis()": {"definition_sha256": "7c432227c054e2e17e81ad3b8a8e2759b6afcad2165e693e37f9111dca67ec2b"}, "public.commercial_pricing_rules_protect()": {"definition_sha256": "dcf4da0f184fe75d5919610690b0331d60b7c3145addd4d663a24ff4f6f31146"}, "public.commercial_guard_manifests_protect()": {"definition_sha256": "bc270768c7a81a5923a3bc1d303253925e1765e27540bf26b8618222d16b916e"}, "public.commercial_guard_integrity_failures()": {"execute": ["service_role"], "definition_sha256": "31bff3b751a8cd0a43a3c83fc1af6242ec952ea1dcd857d91ad33825a35cd742"}, "public.commercial_pricing_protect_truncate()": {"definition_sha256": "b8e1316f7e7b8d7e64cb0db52dd2bc48d0c0c08e729384bfcf6b563fee3e941b"}, "public.commercial_pricing_schedule_protect()": {"definition_sha256": "334a31ec2adb96c33c47f422ab3a85a736ad18221dc55a1a99dec9811a8fc041"}, "public.commercial_settlement_terms_protect()": {"definition_sha256": "3a5c45565bec15feeaa7863a01015351f1638acbe2bd77a882960c56a2d00da2"}, "public.ceo_revalidar_reutilizacao_bandeiras()": {"definition_sha256": "3e5b9e40d240d9914949ed322ce3b8abdc54f147aa866bc29b6136f75568ddc5"}, "public.commercial_segment_snapshot_imutavel()": {"definition_sha256": "044adf339fe704030567db9f03719eb1546c7f716c49930cb69816923be555a9"}, "public.commercial_order_settlement_check(uuid)": {"execute": [], "definition_sha256": "d030911805a1013982a5006a56446d3719f6bbf0bcabf0abb56cd2f4e982a76f"}, "public.admin_activate_pricing_rule(integer,text)": {"execute": [], "definition_sha256": "ebb745215956a07cb6b63342edb3695313dedfa90db6156c0f78af22f733c424"}, "public.ceo_exigir_instrumento_quando_assinavel()": {"definition_sha256": "26f7000b7047e0a52eaa701d53cd09e2e351cd4a87d59c5af5c98702196e8308"}, "public.commercial_activation_guard_fingerprint()": {"execute": ["service_role"], "definition_sha256": "d18cfaf581560a16cef2e51e512de74c5216b13310c9396ff9080fd2ec296336"}, "public.commercial_flag_set_inspections_protect()": {"definition_sha256": "da606f958f5af26fdf2b0ce9ba2d45aa2056aa76d9f7b9e641bc97e2b3e58932"}, "public.commercial_flag_set_lock_for_inspection()": {"definition_sha256": "2271272d240a23dcd3007c6b7ce742459afb326d1102433995df2b4142301674"}, "public.commercial_pricing_activation_log_guard()": {"definition_sha256": "e35df937f3a0064e62fab1eb576b3c4fea5f75eccd58e05569264931654c8fe2"}, "public.commercial_activation_called_by_procedure()": {"execute": [], "definition_sha256": "c914658faee4fb50110c29838e3d0081b74294d75506f060096bb8ed882e0eea"}, "public.commercial_pricing_activation_log_protect()": {"definition_sha256": "14f69adce2ca6f8db8aeff765f2586090c7915b493ef22607b4cd16e6d3ce76f"}, "public.commercial_flag_inventory_protect_truncate()": {"definition_sha256": "bb12a8f32a55d6e71a5971e089e8756e9b2e86ddf007c999ea73076d1fe7baf4"}, "public.commercial_guard_function_entry(regprocedure)": {"execute": [], "definition_sha256": "2a73088e7683c3b65ccdc9903187fec65f03dd32129965a9198a058cb670f63a"}, "public.commercial_qa_operational_procedures_protect()": {"definition_sha256": "86436f51ea9a9a189569ac28e5980cd0074eb12cb75bf892bad96206fb80a591"}, "public.commercial_build_instrument_snapshot(uuid,uuid)": {"execute": ["service_role"], "definition_sha256": "43d17fca7b2f8caac9f77777ff06496f44eeca7259375bad77706c3715eb37ad"}, "public.commercial_pricing_activation_preflight(integer)": {"execute": [], "definition_sha256": "3378beea9ae0d6b7f6ee3810958381e41e6a5a4bb83cf9091b8132741eb6d6b6"}, "public.commercial_pricing_activation_approvals_protect()": {"definition_sha256": "131059cb96fbcb894a09cb3e551282b9b5144d4c793f4150029afa1e7f71da27"}, "public.commercial_instrument_template_approvals_protect()": {"definition_sha256": "c77e8e880308a73f9f6ee9751e501c189b1226539b56f8278c2328af0abb803e"}, "public.admin_confirm_manual_bdflow_payment(uuid,bigint,text,text)": {"execute": ["authenticated"], "definition_sha256": "07de6c5a333db89699234ffbebe222c54d38dad16995a531fd69f26327ea5ffb"}}}$manifesto_r41$::jsonb,
        'migration 20261113200000 / docs/release/R41_MANIFESTO_GUARDAS.json');

-- ===========================================================================
-- Z. AUTOVERIFICAÇÃO R4.1
-- ===========================================================================
DO $verifica_r41$
DECLARE
  v_pre jsonb;
BEGIN
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 3) <> 'active'
     OR (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared' THEN
    RAISE EXCEPTION 'r41_verificacao: estado das regras inesperado';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms WHERE benefit_settlement_mode = 'cash')
     OR EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log)
     OR EXISTS (SELECT 1 FROM public.commercial_instrument_template_approvals)
     OR EXISTS (SELECT 1 FROM public.commercial_pricing_activation_approvals)
     OR EXISTS (SELECT 1 FROM public.commercial_qa_operational_procedures) THEN
    RAISE EXCEPTION 'r41_verificacao: preco de dinheiro, ativacao, aprovacao ou procedimento de QA nao nascem aqui';
  END IF;
  IF (SELECT count(*) FROM public.commercial_guard_manifests) <> 1
     OR (SELECT catalog_sha256 FROM public.commercial_guard_manifests) <> 'bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7' THEN
    RAISE EXCEPTION 'r41_verificacao: manifesto aprovado diferente do publicado';
  END IF;
  IF coalesce(array_length(public.commercial_guard_integrity_failures(), 1), 0) > 0 THEN
    RAISE EXCEPTION 'r41_verificacao: guardas divergentes: %', public.commercial_guard_integrity_failures();
  END IF;
  v_pre := public.commercial_pricing_activation_preflight(4);
  IF (v_pre->>'ok')::boolean
     OR NOT (v_pre->'failures' ? 'activation_approval_missing')
     OR NOT (v_pre->'failures' ? 'qa_operational_procedure_missing:SF-v1.5') THEN
    RAISE EXCEPTION 'r41_verificacao: a versao 4 nao pode estar apta a ativar: %', v_pre;
  END IF;
END $verifica_r41$;
