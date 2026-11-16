-- SUPERADO pela R4.1 (20261113200000): vale para um banco só com a R4. Com a
-- R4.1 use supabase/ops/20261113_verificar_r41_somente_leitura.sql.
-- ===========================================================================
-- VERIFICAÇÃO SOMENTE LEITURA da R4 (20261113180000). Não escreve nada.
-- Detecta, DEPOIS do fato, o que o banco não pode impedir ao próprio dono
-- (DDL nas guardas, gatilhos desligados, session_replication_role = replica):
-- toda versão >= 4 vigente ou superada precisa de UM registro de ativação
-- íntegro, gravado na mesma transação da mudança de status, com a impressão
-- digital das guardas igual ao manifesto da versão. Cada linha deve sair true.
-- Manifesto: docs/release/R4_IMPRESSAO_DIGITAL_GUARDAS.txt (md5 fd2d2c38f81741a1e79b4178a0cd7ebd).
-- ===========================================================================
SELECT 'impressao digital ATUAL das guardas = manifesto' AS item,
       (md5(public.commercial_activation_guard_fingerprint()::text) = 'fd2d2c38f81741a1e79b4178a0cd7ebd')::text AS valor
UNION ALL
SELECT 'nenhum gatilho de guarda desligado',
       (NOT EXISTS (SELECT 1 FROM jsonb_each_text(public.commercial_activation_guard_fingerprint()->'triggers') t
                     WHERE t.value <> 'O'))::text
UNION ALL
SELECT 'toda versao >= 4 publicada tem exatamente um registro de ativacao',
       (NOT EXISTS (SELECT 1 FROM public.commercial_pricing_rules r
                     WHERE r.version >= 4 AND r.status IN ('active', 'superseded')
                       AND (SELECT count(*) FROM public.commercial_pricing_activation_log l
                             WHERE l.pricing_rule_version = r.version) <> 1))::text
UNION ALL
SELECT 'registro de ativacao gravado na mesma transacao da regra (xmin) e com impressao digital do manifesto',
       (NOT EXISTS (SELECT 1 FROM public.commercial_pricing_activation_log l
                      JOIN public.commercial_pricing_rules r ON r.version = l.pricing_rule_version
                     WHERE (l.txid % 4294967296)::text <> l.xmin::text
                        OR md5(l.guard_fingerprint::text) <> 'fd2d2c38f81741a1e79b4178a0cd7ebd'
                        OR (r.status = 'active' AND r.xmin::text <> l.xmin::text)))::text
UNION ALL
SELECT 'minutas assinaveis com modelo R3 tem aprovacao juridica do mesmo conteudo',
       (NOT EXISTS (SELECT 1 FROM public.commercial_instrument_templates t
                     WHERE t.lifecycle_status = 'signable' AND t.settlement_model IS NOT NULL
                       AND NOT EXISTS (SELECT 1 FROM public.commercial_instrument_template_approvals a
                                        WHERE a.template_id = t.id AND a.content_sha256 = t.source_hash)))::text
UNION ALL
SELECT 'pedidos v4 com instrumento carregam aprovacao juridica no snapshot',
       (NOT EXISTS (SELECT 1 FROM public.commercial_exclusivity_orders o
                     WHERE o.pricing_rule_version >= 4 AND o.instrument_snapshot IS NOT NULL
                       AND NOT (o.instrument_snapshot ? 'instrument_legal_approval_id')))::text;

-- ---------------------------------------------------------------------------
-- RECIBOS. O que o banco não detecta: com session_replication_role = replica
-- (liberado ao papel postgres no Supabase pelo supautils) o dono pode gravar
-- regra E registro forjado com a impressão digital correta, na mesma
-- transação; as seis linhas acima saem true. Só o confronto com o recibo
-- guardado FORA do banco no momento da ativação autorizada (documento de
-- release/ticket, por outra pessoa) separa o ato legítimo do forjado.
-- Cada linha abaixo precisa existir, idêntica, no registro externo.
-- ---------------------------------------------------------------------------
SELECT l.pricing_rule_version AS versao, l.id AS registro, l.txid, l.created_at,
       l.actor, l.authorization_reference, md5(l.guard_fingerprint::text) AS impressao_md5
  FROM public.commercial_pricing_activation_log l
 ORDER BY l.created_at;
