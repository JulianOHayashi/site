-- ===========================================================================
-- VERIFICAÇÃO SOMENTE LEITURA da R4.3 (20261116210000; inclui R4.1, R4.2 e R4.2.1).
-- Não escreve nada.
--
-- O catálogo das guardas (versão 2) é recalculado AQUI, só com funções do
-- pg_catalog e leitura de storage.buckets, sem confiar em nenhuma função do
-- schema public (que o dono pode trocar). Cada linha "item|valor" deve sair
-- true. Depois vêm o ESTADO (prova de que nada foi ativado) e as listas a
-- conferir com o registro EXTERNO.
--
-- Manifestos publicados:
--   R4.1   docs/release/R41_MANIFESTO_GUARDAS.json   (histórico, catálogo v1)
--          SHA-256 bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7
--   R4.2   docs/release/R42_MANIFESTO_GUARDAS.json   (histórico, catálogo v1)
--          SHA-256 155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246
--   R4.2.1 docs/release/R421_MANIFESTO_GUARDAS.json  (histórico, catálogo v2)
--          SHA-256 812e47cd2f22b27c27d2cfbeca3cfca8f624bbda87fd6a27f594a411f98e662f
--   R4.3   docs/release/R43_MANIFESTO_GUARDAS.json   (vigente, catálogo v2)
--          SHA-256 0cab0fb36136652841593665b3cc481ab57454cfd939d389204df8f789198a79
-- ===========================================================================
SET search_path TO pg_catalog;

WITH manifestos_publicados(sha) AS (
  VALUES ('bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7'),
         ('155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246'),
         ('812e47cd2f22b27c27d2cfbeca3cfca8f624bbda87fd6a27f594a411f98e662f'),
         ('0cab0fb36136652841593665b3cc481ab57454cfd939d389204df8f789198a79')
), catalogo AS (
  SELECT (
  WITH tabelas AS (
    SELECT x.nome, pg_catalog.to_regclass('public.' || x.nome) AS rel
      FROM pg_catalog.unnest(ARRAY[
        'commercial_pricing_rules', 'commercial_pricing_schedule', 'commercial_settlement_terms',
        'commercial_checkout_intents', 'commercial_exclusivity_orders', 'commercial_payments',
        'commercial_pricing_activation_log', 'commercial_pricing_activation_approvals',
        'commercial_flag_sets', 'commercial_flag_set_inspections',
        'commercial_instrument_template_approvals', 'commercial_qa_operational_procedures',
        'commercial_guard_manifests',
        'commercial_artwork_change_requests', 'commercial_artwork_change_versions',
        'commercial_artwork_change_quotes', 'commercial_artwork_change_quote_items',
        'commercial_artwork_change_events', 'commercial_artwork_change_supplier_documents']) AS x(nome)
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
         'commercial_order_settlement_check',
         'commercial_artwork_change_actor', 'commercial_artwork_change_gate', 'commercial_artwork_change_event',
         'commercial_artwork_change_lock', 'commercial_artwork_change_readiness',
         'commercial_artwork_change_renewal_state', 'commercial_artwork_change_document_valid',
         'commercial_artwork_change_document_readable', 'commercial_artwork_change_quote_reconcile',
         'artwork_change_request_create', 'artwork_change_image_path', 'artwork_change_register_version',
         'artwork_change_submit', 'artwork_change_accept_quote', 'artwork_change_cancel',
         'artwork_change_requests_for_order', 'admin_artwork_change_start_review',
         'admin_artwork_change_register_quote', 'admin_artwork_change_approve_exception',
         'admin_artwork_change_authorize_production', 'admin_artwork_change_reject',
         'admin_artwork_change_supplier_document_path', 'admin_artwork_change_register_supplier_document',
         'service_artwork_change_attest_supplier_document',
         'commercial_order_artwork_locked', 'request_customization_image_path', 'register_customization_image',
         'create_commercial_checkout_intent', 'commercial_flag_reuse_resolution', 'commercial_fidelity_identity',
         'is_site_admin', 'm2_is_company_owner', 'm2_is_company_member',
         'commercial_enabled_settlement_modes', 'commercial_settlement_public_v15'])
    UNION
    SELECT g.tgfoid FROM gatilhos g
  ), entrada AS (
    SELECT p.oid,
           pg_catalog.jsonb_build_object('definition_sha256',
             pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid), 'UTF8')), 'hex'))
           || CASE WHEN p.prorettype = 'trigger'::pg_catalog.regtype THEN '{}'::jsonb
                   ELSE pg_catalog.jsonb_build_object('execute', coalesce((
                          SELECT pg_catalog.jsonb_agg(x.r ORDER BY x.r)
                            FROM (SELECT DISTINCT coalesce(nullif(g.grantee, 0)::pg_catalog.regrole::text, 'PUBLIC') AS r
                                    FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) g
                                   WHERE g.privilege_type = 'EXECUTE' AND g.grantee <> p.proowner) x),
                          '[]'::jsonb))
              END AS e
      FROM pg_catalog.pg_proc p
     WHERE p.oid IN (SELECT oid FROM funcoes)
  ), tab AS (
    SELECT tb.nome, tb.rel,
      pg_catalog.jsonb_build_object(
        'table', 'public.' || tb.nome,
        'present', tb.rel IS NOT NULL,
        'rls', c.relrowsecurity,
        'rls_forced', c.relforcerowsecurity,
        'acl', coalesce((SELECT pg_catalog.jsonb_agg(x.r ORDER BY x.r)
                           FROM (SELECT DISTINCT coalesce(nullif(a.grantee, 0)::pg_catalog.regrole::text, 'PUBLIC')
                                          || ':' || a.privilege_type AS r
                                   FROM pg_catalog.aclexplode(coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))) a
                                  -- MAINTAIN (PG17+) fora: só manutenção, não altera dados.
                                  WHERE a.grantee <> c.relowner AND a.privilege_type <> 'MAINTAIN') x), '[]'::jsonb),
        'columns_sha256', pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce((
            SELECT pg_catalog.string_agg(pg_catalog.concat_ws('|', a.attname,
                     pg_catalog.format_type(a.atttypid, a.atttypmod), a.attnotnull::text, a.attgenerated::text,
                     a.attidentity::text, pg_catalog.pg_get_expr(d.adbin, d.adrelid)), E'\n' ORDER BY a.attnum)
              FROM pg_catalog.pg_attribute a
              LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
             WHERE a.attrelid = tb.rel AND a.attnum > 0 AND NOT a.attisdropped), ''), 'UTF8')), 'hex'),
        'constraints', coalesce((SELECT pg_catalog.jsonb_object_agg(k.conname, pg_catalog.pg_get_constraintdef(k.oid))
                                   FROM pg_catalog.pg_constraint k WHERE k.conrelid = tb.rel), '{}'::jsonb),
        'indexes', coalesce((SELECT pg_catalog.jsonb_object_agg(ic.relname, pg_catalog.pg_get_indexdef(i.indexrelid))
                               FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid
                              WHERE i.indrelid = tb.rel), '{}'::jsonb),
        'policies', coalesce((SELECT pg_catalog.jsonb_object_agg(po.polname, pg_catalog.jsonb_build_object(
                                 'cmd', po.polcmd::text, 'permissive', po.polpermissive,
                                 'roles', (SELECT pg_catalog.jsonb_agg(coalesce(nullif(r, 0)::pg_catalog.regrole::text, 'PUBLIC') ORDER BY 1)
                                             FROM pg_catalog.unnest(po.polroles) r),
                                 'using', pg_catalog.pg_get_expr(po.polqual, po.polrelid),
                                 'check', pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid)))
                                FROM pg_catalog.pg_policy po WHERE po.polrelid = tb.rel), '{}'::jsonb)) AS j
      FROM tabelas tb LEFT JOIN pg_catalog.pg_class c ON c.oid = tb.rel
  )
  SELECT pg_catalog.jsonb_build_object(
    'format', 'smallflags-guard-catalog/2 (R4.3, sha256)',
    'tables', (SELECT pg_catalog.jsonb_agg(tab.j ORDER BY tab.nome) FROM tab),
    'functions', coalesce((SELECT pg_catalog.jsonb_object_agg(en.oid::pg_catalog.regprocedure::text, en.e)
                             FROM entrada en), '{}'::jsonb),
    'triggers', coalesce((SELECT pg_catalog.jsonb_object_agg(
        g.tgrelid::pg_catalog.regclass::text || '.' || g.tgname,
        pg_catalog.jsonb_build_object(
          'state', g.tgenabled::text,
          'definition', pg_catalog.pg_get_triggerdef(g.oid, false),
          'definition_sha256', pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
                                 pg_catalog.pg_get_triggerdef(g.oid, false), 'UTF8')), 'hex'),
          'function', g.tgfoid::pg_catalog.regprocedure::text,
          'function_sha256', en.e->>'definition_sha256',
          'tgtype', g.tgtype,
          'args_sha256', pg_catalog.encode(pg_catalog.sha256(g.tgargs), 'hex'),
          'when', pg_catalog.pg_get_expr(g.tgqual, g.tgrelid),
          'columns', g.tgattr::text,
          'deferrable', g.tgdeferrable,
          'initially_deferred', g.tginitdeferred))
        FROM gatilhos g JOIN entrada en ON en.oid = g.tgfoid), '{}'::jsonb),
    'storage', pg_catalog.jsonb_build_object(
      'objects_rls', (SELECT c.relrowsecurity FROM pg_catalog.pg_class c
                       WHERE c.oid = pg_catalog.to_regclass('storage.objects')),
      'buckets', coalesce((SELECT pg_catalog.jsonb_object_agg(b.id, pg_catalog.jsonb_build_object(
                             'public', b.public, 'file_size_limit', b.file_size_limit,
                             'allowed_mime_types', pg_catalog.to_jsonb(b.allowed_mime_types)))
                             FROM storage.buckets b
                            WHERE b.id IN ('partner-customization-images', 'supplier-quote-documents')), '{}'::jsonb),
      'policies', coalesce((SELECT pg_catalog.jsonb_object_agg(po.polname, pg_catalog.jsonb_build_object(
                             'cmd', po.polcmd::text, 'permissive', po.polpermissive,
                             'roles', (SELECT pg_catalog.jsonb_agg(coalesce(nullif(r, 0)::pg_catalog.regrole::text, 'PUBLIC') ORDER BY 1)
                                         FROM pg_catalog.unnest(po.polroles) r),
                             'using', pg_catalog.pg_get_expr(po.polqual, po.polrelid),
                             'check', pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid)))
                             FROM pg_catalog.pg_policy po
                            WHERE po.polrelid = pg_catalog.to_regclass('storage.objects')
                              AND (coalesce(pg_catalog.pg_get_expr(po.polqual, po.polrelid), '')
                                   || coalesce(pg_catalog.pg_get_expr(po.polwithcheck, po.polrelid), ''))
                                  ~ '(partner-customization-images|supplier-quote-documents)'), '{}'::jsonb)))
  ) AS c
), viva AS (
  SELECT c, encode(sha256(convert_to(c::text, 'UTF8')), 'hex') AS sha FROM catalogo
)
-- NULL conta como false (verificação que não conseguiu concluir).
SELECT item, coalesce(valor, 'false') AS valor FROM (
SELECT 'catalogo vivo (recalculado so com pg_catalog) = um manifesto publicado' AS item,
       (SELECT sha IN (SELECT sha FROM manifestos_publicados) FROM viva)::text AS valor
UNION ALL
SELECT 'nenhum gatilho guardado fora do estado O',
       (NOT EXISTS (SELECT 1 FROM viva, jsonb_each(viva.c->'triggers') t WHERE t.value->>'state' <> 'O'))::text
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
SELECT 'manifestos no banco na ordem publicada: R4.1, R4.2, R4.2.1 (historicos) e R4.3 (vigente)',
       ((SELECT string_agg(manifest_label, ',' ORDER BY id) FROM public.commercial_guard_manifests) = 'R4.1,R4.2,R4.2.1,R4.3')::text
UNION ALL
SELECT 'catalogo v2 cobre as 6 tabelas da alteracao de arte, seus gatilhos e o Storage dos dois buckets',
       (SELECT (SELECT count(*) FROM jsonb_array_elements(c->'tables') x
                 WHERE x->>'table' LIKE 'public.commercial_artwork_change_%' AND (x->>'present')::boolean) = 6
           AND (SELECT count(*) FROM jsonb_object_keys(c->'triggers') k WHERE k LIKE 'public.commercial_artwork_change_%') >= 11
           AND (SELECT count(*) FROM jsonb_object_keys(c->'storage'->'buckets')) = 2
           AND (SELECT count(*) FROM jsonb_object_keys(c->'storage'->'policies')) >= 6
         FROM viva)::text
UNION ALL
SELECT 'R4.2.1: renovacao com alteracao de arte so PRONTA, fidelizada, mesma empresa e identidade, na campanha alvo, uso unico',
       (NOT EXISTS (SELECT 1 FROM (SELECT o.company_id, o.niche_code, o.segment_id, o.exclusivity_id, o.fidelized,
                                          o.artwork_change_request_id, o.status, 'pedido' AS t
                                     FROM public.commercial_exclusivity_orders o
                                    UNION ALL
                                   SELECT i.company_id, i.niche_code, i.segment_id, i.exclusivity_id, i.fidelized,
                                          i.artwork_change_request_id, i.status, 'intencao'
                                     FROM public.commercial_checkout_intents i) o
                      JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
                      LEFT JOIN public.commercial_artwork_change_requests r ON r.id = o.artwork_change_request_id
                     WHERE o.artwork_change_request_id IS NOT NULL
                       AND (r.id IS NULL OR r.status <> 'production_authorized' OR r.target_campaign <> 'next_campaign'
                            OR (public.commercial_artwork_change_readiness(r.id)->>'ready')::boolean IS NOT TRUE
                            OR r.company_id <> o.company_id OR NOT o.fidelized
                            OR r.fidelity_identity <> public.commercial_fidelity_identity(o.niche_code, o.segment_id)
                            OR r.target_region_id <> e.region_id OR r.target_sequence_number <> e.sequence_number
                            OR (SELECT count(*) FROM public.commercial_exclusivity_orders o2
                                 WHERE o2.artwork_change_request_id = r.id AND o2.status <> 'cancelled') > 1)))::text
UNION ALL
SELECT 'R4.2.1: campanha alvo da solicitacao = base (+1 se proxima), uma viva por empresa, identidade e campanha',
       (NOT EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests r
                      JOIN public.commercial_exclusivity_orders o ON o.id = r.base_order_id
                      JOIN public.commercial_exclusivities e ON e.id = o.exclusivity_id
                     WHERE r.base_exclusivity_id <> o.exclusivity_id OR r.target_region_id <> e.region_id
                        OR r.target_sequence_number <> e.sequence_number
                                                      + CASE WHEN r.target_campaign = 'next_campaign' THEN 1 ELSE 0 END)
        AND NOT EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests r
                         WHERE r.status NOT IN ('cancelled', 'rejected')
                         GROUP BY r.company_id, r.fidelity_identity, r.target_region_id, r.target_sequence_number
                        HAVING count(*) > 1))::text
UNION ALL
SELECT 'R4.2.1: orcamento = soma dos itens (qtd x unitario), pecas = soma das quantidades, documento ATESTADO igual ao declarado, sem margem',
       (NOT EXISTS (SELECT 1 FROM public.commercial_artwork_change_quotes q
                      LEFT JOIN public.commercial_artwork_change_supplier_documents d ON d.id = q.supplier_document_id
                     WHERE d.id IS NULL OR d.request_id <> q.request_id OR d.attested_sha256 IS NULL
                        OR d.attested_sha256 <> d.declared_sha256 OR q.supplier_document_sha256 <> d.attested_sha256
                        OR q.partner_charge_cents <> q.supplier_total_cents
                        OR q.supplier_total_cents IS DISTINCT FROM (SELECT sum(it.line_total_cents)
                             FROM public.commercial_artwork_change_quote_items it WHERE it.quote_id = q.id)
                        OR q.pieces_count IS DISTINCT FROM (SELECT sum(it.quantity)
                             FROM public.commercial_artwork_change_quote_items it WHERE it.quote_id = q.id)
                        OR EXISTS (SELECT 1 FROM public.commercial_artwork_change_quote_items it
                                    WHERE it.quote_id = q.id AND it.line_total_cents <> it.quantity * it.unit_cost_cents)))::text
UNION ALL
SELECT 'R4.2.1: aceite e producao = orcamento aceito da solicitacao, valor = custo do fornecedor, teto, excecao quando campanha atual',
       (NOT EXISTS (SELECT 1 FROM public.commercial_artwork_change_requests r
                      LEFT JOIN public.commercial_artwork_change_quotes q ON q.id = r.accepted_quote_id
                     WHERE r.status IN ('accepted', 'production_authorized')
                       AND (q.id IS NULL OR q.request_id <> r.id OR q.partner_charge_cents <> q.supplier_total_cents
                            OR r.accepted_total_cents <> q.partner_charge_cents OR q.partner_charge_cents > q.cap_cents
                            OR (r.status = 'production_authorized' AND r.target_campaign = 'current_campaign'
                                AND r.exception_approved_by IS NULL))))::text
UNION ALL
SELECT 'R4.3: modalidade de toda intencao/pedido >= v4 esta habilitada na versao; habilitada vendida tem termos',
       (NOT EXISTS (SELECT 1 FROM (SELECT pricing_rule_version, benefit_settlement_mode FROM public.commercial_checkout_intents
                                   UNION ALL
                                   SELECT pricing_rule_version, benefit_settlement_mode FROM public.commercial_exclusivity_orders) x
                     WHERE x.pricing_rule_version >= 4
                       AND NOT (x.benefit_settlement_mode = ANY (public.commercial_enabled_settlement_modes(x.pricing_rule_version))))
        AND NOT EXISTS (SELECT 1 FROM public.commercial_pricing_rules r, unnest(coalesce(r.enabled_settlement_modes, '{}')) m
                         WHERE r.status IN ('active', 'superseded') AND r.version >= 4
                           AND (SELECT count(*) FROM public.commercial_settlement_terms t
                                 WHERE t.pricing_rule_version = r.version AND t.benefit_settlement_mode = m) < 4))::text
) verificacao;

-- ---------------------------------------------------------------------------
-- ESTADO (informativo, não é item true/false): versões de preço, registros de
-- ativação, termos em dinheiro e procedimentos de QA existentes.
-- ---------------------------------------------------------------------------
SELECT 'estado' AS tipo,
       (SELECT string_agg('v' || version || '=' || status, ',' ORDER BY version) FROM public.commercial_pricing_rules) AS regras,
       (SELECT count(*) FROM public.commercial_pricing_activation_log) AS registros_ativacao,
       (SELECT count(*) FROM public.commercial_settlement_terms WHERE benefit_settlement_mode = 'cash') AS termos_dinheiro,
       (SELECT count(*) FROM public.commercial_qa_operational_procedures) AS procedimentos_qa,
       (SELECT string_agg('v' || version || '=' || coalesce(array_to_string(enabled_settlement_modes, '+'), 'padrao'), ','
                          ORDER BY version) FROM public.commercial_pricing_rules WHERE version >= 4) AS modalidades;

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
