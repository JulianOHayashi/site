-- ============================================================================
-- RECONCILIAÇÃO do histórico de migrations de Production com o repositório
--
-- O QUE FAZ: troca apenas a coluna version de 31 linhas de
-- supabase_migrations.schema_migrations (versão de Production -> versão do arquivo no repositório),
-- casando pelo NOME. Não executa DDL, não toca em schema público, não muda
-- statements, name nem nenhum objeto do banco.
--
-- POR QUÊ: essas 31 migrations foram aplicadas por apply_migration, que grava
-- o horário da aplicação como versão. O conteúdo funcional é equivalente
-- (auditoria da Etapa B: 159/159 funções, colunas, índices, gatilhos e
-- políticas iguais), mas o CLI enxerga 31 migrations "remotas desconhecidas"
-- e 31 "locais pendentes". Um db push cego tentaria reaplicar todas.
--
-- PRÉ-CONDIÇÃO (verificada dentro da transação; qualquer diferença aborta):
--   exatamente 62 linhas, hash md5 de (version:name ordenado) = f13ee66fee74cc39a82cb2a69c99e205.
-- PÓS-CONDIÇÃO (verificada antes do COMMIT): 62 linhas, 0 versões antigas,
--   31 versões novas presentes e nomes inalterados.
--
-- NÃO EXECUTAR sem autorização explícita. Executar como um único comando
-- (SQL Editor ou execute_sql). Não usa apply_migration.
-- ============================================================================
BEGIN;

LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMP TABLE _remap (prod text PRIMARY KEY, repo text UNIQUE NOT NULL, name text UNIQUE NOT NULL)
  ON COMMIT DROP;
INSERT INTO _remap (prod, repo, name) VALUES
    ('20260924201111', '20260915120000', 'commercial_checkout_reservation'),
    ('20260924201129', '20260916120000', 'commercial_order_terms_and_finalization'),
    ('20260924201146', '20260917120000', 'commercial_payments_pagarme'),
    ('20260924201206', '20260918120000', 'commercial_payment_lookup_status'),
    ('20260924201220', '20260919120000', 'provider_customer_context'),
    ('20260924201236', '20260918160409', 'manager_revocation_pending_invites_hardening'),
    ('20260924201254', '20260918163224', 'manager_terminal_revocation_guard'),
    ('20260924201311', '20260918182105', 'commercial_one_niche_per_company_guard'),
    ('20260924201329', '20260919165938', 'commercial_future_interest_schema'),
    ('20260924201348', '20260919170019', 'commercial_future_interest_rpcs'),
    ('20260925213047', '20260925121500', 'public_write_hardening'),
    ('20260925213054', '20260925121700', 'public_write_service_acl'),
    ('20260925213100', '20260925121900', 'public_write_rate_limit_cleanup'),
    ('20260926005724', '20260925121600', 'public_write_rpc_acl'),
    ('20260926005727', '20260925121800', 'public_write_restrict_acl'),
    ('20261008173332', '20261005120000', 'legal_master_agreement_publication'),
    ('20261008173410', '20261005140000', 'legal_master_canonical_publication_and_linkage'),
    ('20261008173506', '20261005160000', 'commercial_order_instrument_snapshot'),
    ('20261008173710', '20261007120000', 'commercial_pricing_v14_authority'),
    ('20261008173745', '20261007130000', 'commercial_v14_manual_payment_alignment'),
    ('20261008173831', '20261007140000', 'p01_master_enforcement_lock'),
    ('20261008173908', '20261007150000', 'p03_pool_semantics_explicit'),
    ('20261008174037', '20261007160000', 'p01_master_eligibility_resolver'),
    ('20261008174122', '20261007170000', 'p02_instrument_template_authority'),
    ('20261008174155', '20261007180000', 'p02_material_fact_authorities'),
    ('20261008174248', '20261007190000', 'p02_snapshot_from_authorities_only'),
    ('20261008174434', '20261008120000', 'p0c_instrument_signability_and_emission'),
    ('20261008174607', '20261008130000', 'p0a_public_funding_by_settlement_mode'),
    ('20261008175714', '20261008140000', 'legal_documents_direct_acl_hardening'),
    ('20261029214922', '20261027154258', 'onboarding_legal_publication_v1'),
    ('20261029214928', '20261028003012', 'defer_onboarding_acceptances');

DO $pre$
DECLARE v_n int; v_h text;
BEGIN
  SELECT count(*), md5(string_agg(version||':'||name, ',' ORDER BY version||':'||name))
    INTO v_n, v_h FROM supabase_migrations.schema_migrations;
  IF v_n <> 62 OR v_h <> 'f13ee66fee74cc39a82cb2a69c99e205' THEN
    RAISE EXCEPTION 'reconciliacao_abortada: historico diferente do auditado (linhas=%, hash=%)', v_n, v_h;
  END IF;
  IF (SELECT count(*) FROM _remap) <> 31 THEN
    RAISE EXCEPTION 'reconciliacao_abortada: mapa incompleto';
  END IF;
  -- cada linha a mudar existe com o nome esperado, e o destino está livre
  IF EXISTS (SELECT 1 FROM _remap r WHERE NOT EXISTS (
       SELECT 1 FROM supabase_migrations.schema_migrations m WHERE m.version = r.prod AND m.name = r.name))
  OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations m JOIN _remap r ON m.version = r.repo) THEN
    RAISE EXCEPTION 'reconciliacao_abortada: linha ausente ou versao de destino ocupada';
  END IF;
END $pre$;

UPDATE supabase_migrations.schema_migrations m
   SET version = r.repo
  FROM _remap r
 WHERE m.version = r.prod AND m.name = r.name;

DO $pos$
BEGIN
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations) <> 62
  OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations m JOIN _remap r ON m.version = r.prod)
  OR (SELECT count(*) FROM supabase_migrations.schema_migrations m JOIN _remap r
        ON m.version = r.repo AND m.name = r.name) <> 31 THEN
    RAISE EXCEPTION 'reconciliacao_abortada: pos-condicao falhou';
  END IF;
END $pos$;

SELECT count(*) AS linhas,
       md5(string_agg(version||':'||name, ',' ORDER BY version||':'||name)) AS hash_final
  FROM supabase_migrations.schema_migrations;

COMMIT;
