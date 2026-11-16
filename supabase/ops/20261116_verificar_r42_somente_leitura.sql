-- SUPERADO pela R4.2.1 (20261116180000): vale para um banco só até a R4.2. Com a
-- R4.2.1 use supabase/ops/20261116_verificar_r421_somente_leitura.sql.
-- ===========================================================================
-- VERIFICAÇÃO SOMENTE LEITURA da R4.2 (20261116120000; inclui a R4.1).
-- Não escreve nada.
--
-- O catálogo das guardas é recalculado AQUI, só com funções do pg_catalog,
-- sem confiar em nenhuma função do schema public (que o dono pode trocar).
-- Cada linha "item|valor" deve sair true. Depois vêm as listas a conferir
-- com o registro EXTERNO (manifestos, aprovações de lançamento, procedimentos
-- de QA e recibos de ativação).
--
-- Manifestos publicados:
--   R4.1 docs/release/R41_MANIFESTO_GUARDAS.json
--        SHA-256 bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7 (histórico)
--   R4.2 docs/release/R42_MANIFESTO_GUARDAS.json
--        SHA-256 155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246 (vigente)
-- Uma migration futura que mude uma guarda publica um manifesto novo; inclua
-- o SHA-256 dele na lista "manifestos_publicados" abaixo.
-- ===========================================================================
SET search_path TO pg_catalog;

WITH manifestos_publicados(sha) AS (
  VALUES ('bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7'),
         ('155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246')
), tabelas AS (
  SELECT x.nome, to_regclass('public.' || x.nome) AS rel
    FROM unnest(ARRAY[
      'commercial_pricing_rules', 'commercial_pricing_schedule', 'commercial_settlement_terms',
      'commercial_checkout_intents', 'commercial_exclusivity_orders', 'commercial_payments',
      'commercial_pricing_activation_log', 'commercial_pricing_activation_approvals',
      'commercial_flag_sets', 'commercial_flag_set_inspections',
      'commercial_instrument_template_approvals', 'commercial_qa_operational_procedures',
      'commercial_guard_manifests']) AS x(nome)
), gatilhos AS (
  SELECT t.* FROM pg_trigger t JOIN tabelas ON tabelas.rel = t.tgrelid WHERE NOT t.tgisinternal
), funcoes AS (
  SELECT p.oid FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname = ANY (ARRAY[
       'admin_activate_pricing_rule', 'commercial_pricing_activation_preflight',
       'commercial_activation_called_by_procedure', 'commercial_activation_guard_fingerprint',
       'commercial_guard_function_entry', 'commercial_guard_catalog', 'commercial_guard_integrity_failures',
       'admin_confirm_manual_bdflow_payment', 'commercial_build_instrument_snapshot',
       'commercial_order_settlement_check'])
  UNION SELECT g.tgfoid FROM gatilhos g
), entrada AS (
  SELECT p.oid,
         jsonb_build_object('definition_sha256',
           encode(sha256(convert_to(pg_get_functiondef(p.oid), 'UTF8')), 'hex'))
         || CASE WHEN p.prorettype = 'trigger'::regtype THEN '{}'::jsonb
                 ELSE jsonb_build_object('execute', coalesce((
                        SELECT jsonb_agg(x.r ORDER BY x.r)
                          FROM (SELECT DISTINCT coalesce(nullif(g.grantee, 0)::regrole::text, 'PUBLIC') AS r
                                  FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
                                 WHERE g.privilege_type = 'EXECUTE' AND g.grantee <> p.proowner) x),
                        '[]'::jsonb))
            END AS e
    FROM pg_proc p
   WHERE p.oid IN (SELECT oid FROM funcoes UNION SELECT tgfoid FROM gatilhos)
), catalogo AS (
  SELECT jsonb_build_object(
    'format', 'smallflags-guard-catalog/1 (R4.1, sha256)',
    'tables', (SELECT jsonb_agg(jsonb_build_object('table', 'public.' || nome, 'present', rel IS NOT NULL)
                                ORDER BY nome) FROM tabelas),
    'functions', coalesce((SELECT jsonb_object_agg(f.oid::regprocedure::text, en.e)
                             FROM funcoes f JOIN entrada en ON en.oid = f.oid), '{}'::jsonb),
    'triggers', coalesce((SELECT jsonb_object_agg(
        g.tgrelid::regclass::text || '.' || g.tgname,
        jsonb_build_object(
          'state', g.tgenabled::text,
          'definition', pg_get_triggerdef(g.oid, false),
          'definition_sha256', encode(sha256(convert_to(pg_get_triggerdef(g.oid, false), 'UTF8')), 'hex'),
          'function', g.tgfoid::regprocedure::text,
          'function_sha256', en.e->>'definition_sha256',
          'tgtype', g.tgtype,
          'args_sha256', encode(sha256(g.tgargs), 'hex'),
          'when', pg_get_expr(g.tgqual, g.tgrelid),
          'columns', g.tgattr::text,
          'deferrable', g.tgdeferrable,
          'initially_deferred', g.tginitdeferred))
        FROM gatilhos g JOIN entrada en ON en.oid = g.tgfoid), '{}'::jsonb)) AS c
), viva AS (
  SELECT c, encode(sha256(convert_to(c::text, 'UTF8')), 'hex') AS sha FROM catalogo
)
-- NULL conta como false (verificação que não conseguiu concluir).
SELECT item, coalesce(valor, 'false') AS valor FROM (
SELECT 'catalogo vivo (recalculado so com pg_catalog) = um manifesto publicado' AS item,
       (SELECT sha IN (SELECT sha FROM manifestos_publicados) FROM viva)::text AS valor
UNION ALL
SELECT 'nenhum gatilho guardado fora do estado O',
       (NOT EXISTS (SELECT 1 FROM gatilhos WHERE tgenabled <> 'O'))::text
UNION ALL
SELECT 'funcao public.commercial_guard_catalog() devolve o mesmo catalogo (nao foi trocada)',
       (SELECT public.commercial_guard_catalog() = c FROM viva)::text
UNION ALL
SELECT 'manifesto aprovado mais recente no banco = catalogo vivo, e todo manifesto do banco foi publicado',
       ((SELECT m.catalog_sha256 = v.sha AND m.catalog = v.c
           FROM public.commercial_guard_manifests m, viva v ORDER BY m.id DESC LIMIT 1)
        AND NOT EXISTS (SELECT 1 FROM public.commercial_guard_manifests m
                         WHERE m.catalog_sha256 NOT IN (SELECT sha FROM manifestos_publicados)
                            OR m.catalog_sha256 <> encode(sha256(convert_to(m.catalog::text, 'UTF8')), 'hex')))::text
UNION ALL
SELECT 'toda versao >= 4 publicada tem exatamente um registro de ativacao',
       (NOT EXISTS (SELECT 1 FROM public.commercial_pricing_rules r
                     WHERE r.version >= 4 AND r.status IN ('active', 'superseded')
                       AND (SELECT count(*) FROM public.commercial_pricing_activation_log l
                             WHERE l.pricing_rule_version = r.version) <> 1))::text
UNION ALL
SELECT 'registro de ativacao: mesma transacao da regra, catalogo = manifesto publicado, aprovacao externa correspondente',
       (NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log l
                      JOIN public.commercial_pricing_rules r ON r.version = l.pricing_rule_version
                      LEFT JOIN public.commercial_pricing_activation_approvals a ON a.id = l.activation_approval_id
                     WHERE (l.txid % 4294967296)::text <> l.xmin::text
                        OR (r.status = 'active' AND r.xmin::text <> l.xmin::text)
                        OR l.guard_catalog_sha256 IS DISTINCT FROM encode(sha256(convert_to(l.guard_fingerprint::text, 'UTF8')), 'hex')
                        OR l.guard_catalog_sha256 NOT IN (SELECT sha FROM manifestos_publicados)
                        OR a.id IS NULL
                        OR a.pricing_rule_version <> l.pricing_rule_version
                        OR a.approval_reference <> l.authorization_reference
                        OR a.approval_document_sha256 IS DISTINCT FROM l.approval_document_sha256))::text
UNION ALL
SELECT 'minutas assinaveis com modelo R3 tem aprovacao juridica do mesmo conteudo',
       (NOT EXISTS (SELECT 1 FROM public.commercial_instrument_templates t
                     WHERE t.lifecycle_status = 'signable' AND t.settlement_model IS NOT NULL
                       AND NOT EXISTS (SELECT 1 FROM public.commercial_instrument_template_approvals a
                                        WHERE a.template_id = t.id AND a.content_sha256 = t.source_hash)))::text
UNION ALL
SELECT 'pedidos v4 com instrumento: aprovacao juridica e, com QA em produtos, procedimento de QA no snapshot',
       (NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                     WHERE o.pricing_rule_version >= 4 AND o.instrument_snapshot IS NOT NULL
                       AND (NOT (o.instrument_snapshot->'snapshot' ? 'instrument_legal_approval_id'
                                 OR o.instrument_snapshot ? 'instrument_legal_approval_id')
                            OR (o.benefit_settlement_mode = 'direct_benefits' AND coalesce(o.qa_in_kind_cents, 0) > 0
                                AND coalesce(o.instrument_snapshot->'snapshot'->>'qa_operational_procedure_id',
                                             o.instrument_snapshot->>'qa_operational_procedure_id') IS NULL))))::text
UNION ALL
SELECT 'R4.2: renovacao fidelizada sem reutilizacao so com alteracao de arte autorizada (proxima campanha, mesma empresa e identidade, uso unico)',
       (NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                      LEFT JOIN public.commercial_artwork_change_requests r ON r.id = o.artwork_change_request_id
                     WHERE o.artwork_change_request_id IS NOT NULL
                       AND (r.id IS NULL OR r.status <> 'production_authorized' OR r.target_campaign <> 'next_campaign'
                            OR r.company_id <> o.company_id OR NOT o.fidelized
                            OR r.fidelity_identity <> public.commercial_fidelity_identity(o.niche_code, o.segment_id)
                            OR (SELECT count(*) FROM public.commercial_exclusivity_orders o2
                                 WHERE o2.artwork_change_request_id = r.id AND o2.status <> 'cancelled') > 1)))::text
UNION ALL
SELECT 'R4.2: aceite e producao de alteracao de arte = orcamento aceito, valor ao parceiro = custo do fornecedor (sem margem), excecao quando campanha atual',
       (NOT EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests r
                      LEFT JOIN public.commercial_artwork_change_quotes q ON q.id = r.accepted_quote_id
                     WHERE r.status IN ('accepted', 'production_authorized')
                       AND (q.id IS NULL OR q.request_id <> r.id OR q.partner_charge_cents <> q.supplier_total_cents
                            OR r.accepted_total_cents <> q.partner_charge_cents OR q.partner_charge_cents > q.cap_cents
                            OR (r.status = 'production_authorized' AND r.target_campaign = 'current_campaign'
                                AND r.exception_approved_by IS NULL))))::text
) verificacao;

-- ---------------------------------------------------------------------------
-- LISTAS PARA CONFRONTO COM O REGISTRO EXTERNO. O banco não distingue um
-- registro legítimo de um forjado pelo dono com session_replication_role =
-- replica; quem distingue é o documento guardado fora do banco por quem
-- aprovou. Cada linha precisa constar dele, idêntica.
-- ---------------------------------------------------------------------------
SELECT 'manifesto' AS tipo, id::text, manifest_label AS referencia, catalog_sha256 AS sha256,
       registered_by_db_role AS executor_tecnico, registered_at AS em
  FROM public.commercial_guard_manifests
UNION ALL
SELECT 'aprovacao_lancamento', id::text, approval_reference || ' (v' || pricing_rule_version || ', aprovador declarado: '
       || approver_as_stated || ', ' || approved_on_as_stated || ')', approval_document_sha256,
       registered_by_db_role, registered_at
  FROM public.commercial_pricing_activation_approvals
UNION ALL
SELECT 'procedimento_qa', id::text, procedure_reference || ' (' || contract_economics_version || ', aprovador declarado: '
       || approver_as_stated || ', ' || approved_on_as_stated || ')', procedure_document_sha256,
       registered_by_db_role, registered_at
  FROM public.commercial_qa_operational_procedures
UNION ALL
SELECT 'recibo_ativacao', l.id::text, 'v' || l.pricing_rule_version || ' txid ' || l.txid || ' aprovacao '
       || coalesce(l.authorization_reference, '?') || ' jwt_sub ' || coalesce(l.executor_jwt_sub, '-'),
       l.guard_catalog_sha256, l.executor_db_role, l.created_at
  FROM public.commercial_pricing_activation_log l
 ORDER BY 1, 6;

RESET search_path;
