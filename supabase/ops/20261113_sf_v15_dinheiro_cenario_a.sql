-- ===========================================================================
-- SF-v1.5 — PREÇO DA MODALIDADE DINHEIRO — CENÁRIO A (DECIDIDO).
-- Decisão: DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115 (missão R4.2,
-- 16/11/2026). O documento não estava anexado à sessão que preparou este
-- roteiro; a referência registrada é o nome dele.
--
-- Na modalidade DINHEIRO não há testes com produtos, logo não há QA, nem
-- substituto monetário de QA, nem ajuste para igualar o benefício direto:
--   econômico (dinheiro) = contraprestação dos participantes + parcela principal
--   Supermercado novo 32.817,32 | fidelizado 28.054,32
--   Demais novos      22.878,16 | fidelizados 16.127,16
-- Benefício direto (inalterado): 32.939,00 | 28.176,00 | 22.939,00 | 16.188,00.
-- A parcela principal da SmallFlags NÃO muda (é a da agenda).
--
-- R4.2: o roteiro confere os QUATRO valores aprovados e ABORTA se a agenda
-- produzir qualquer outro número. Gravar o preço NÃO ativa a versão: a
-- ativação continua exigindo pré-verificação, aprovação de lançamento e o
-- procedimento operacional de QA (trava R4.1), hoje inexistente.
--
-- Só grava com a versão 4 em 'prepared' (o gatilho cst_protect recusa depois).
-- Ato do dono, NÃO automatizado em migration. USO:
--   BEGIN;
--   SET LOCAL smallflags.decisao_dinheiro_sf_v15 = 'CENARIO-A-APROVADO';
--   SET LOCAL smallflags.decisao_referencia = 'DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115';
--   \i supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql
--   -- conferir a tabela impressa
--   COMMIT;  -- ou ROLLBACK
-- ===========================================================================
DO $cenario_a$
DECLARE
  v_ref text := coalesce(current_setting('smallflags.decisao_referencia', true), '');
BEGIN
  IF coalesce(current_setting('smallflags.decisao_dinheiro_sf_v15', true), '') <> 'CENARIO-A-APROVADO' THEN
    RAISE EXCEPTION 'cenario_a_sem_decisao: defina smallflags.decisao_dinheiro_sf_v15 na transacao';
  END IF;
  IF length(btrim(v_ref)) < 10 THEN
    RAISE EXCEPTION 'cenario_a_sem_referencia: defina smallflags.decisao_referencia (>= 10 caracteres)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms
              WHERE pricing_rule_version = 4 AND benefit_settlement_mode = 'cash') THEN
    RAISE EXCEPTION 'cenario_a_ja_definido: a versao 4 ja tem preco de dinheiro';
  END IF;

  INSERT INTO public.commercial_settlement_terms
    (pricing_rule_version, contract_economics_version, commercial_category, fidelized,
     benefit_settlement_mode, economic_value_cents, mei_consideration_cents,
     mei_in_kind_cents, mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents,
     qa_cash_cents, cash_adjustment_cents, cash_adjustment_basis,
     total_monetary_funding_required_cents, ordinary_participation_value_cents,
     decision_reference, notes)
  SELECT s.pricing_rule_version, s.contract_economics_version, s.commercial_category, s.fidelized,
         'cash', s.mei_consideration_cents + s.smallflags_main_fee_cents, s.mei_consideration_cents,
         0, s.mei_consideration_cents, s.smallflags_main_fee_cents, 0,
         0, 0, NULL,
         s.mei_consideration_cents + s.smallflags_main_fee_cents, s.ordinary_participation_value_cents,
         'Cenario A: ' || btrim(v_ref),
         'Dinheiro sem QA: a obrigacao inexistente nao integra o preco.'
    FROM public.commercial_pricing_schedule s
   WHERE s.pricing_rule_version = 4;

  -- R4.2: só os quatro valores APROVADOS; qualquer outro número aborta tudo.
  IF (SELECT count(*) FROM public.commercial_settlement_terms
       WHERE pricing_rule_version = 4 AND benefit_settlement_mode = 'cash') <> 4
     OR EXISTS (
       SELECT 1 FROM public.commercial_settlement_terms t
         JOIN (VALUES ('supermarket', false, 3281732::bigint, 3293900::bigint),
                      ('supermarket', true,  2805432::bigint, 2817600::bigint),
                      ('common',      false, 2287816::bigint, 2293900::bigint),
                      ('common',      true,  1612716::bigint, 1618800::bigint))
              AS a(categoria, fidelizado, dinheiro, direto)
           ON a.categoria = t.commercial_category AND a.fidelizado = t.fidelized
         JOIN public.commercial_settlement_terms d
           ON d.pricing_rule_version = 4 AND d.commercial_category = t.commercial_category
          AND d.fidelized = t.fidelized AND d.benefit_settlement_mode = 'direct_benefits'
        WHERE t.pricing_rule_version = 4 AND t.benefit_settlement_mode = 'cash'
          AND (t.economic_value_cents <> a.dinheiro OR d.economic_value_cents <> a.direto
               OR t.qa_in_kind_cents <> 0 OR t.qa_cash_cents <> 0 OR t.cash_adjustment_cents <> 0
               OR t.total_monetary_funding_required_cents <> a.dinheiro
               OR t.smallflags_main_fee_cents <> d.smallflags_main_fee_cents))
     OR (SELECT count(*) FROM (VALUES ('supermarket', false), ('supermarket', true),
                                      ('common', false), ('common', true)) AS c(categoria, fidelizado)
          WHERE EXISTS (SELECT 1 FROM public.commercial_settlement_terms t
                         WHERE t.pricing_rule_version = 4 AND t.benefit_settlement_mode = 'cash'
                           AND t.commercial_category = c.categoria AND t.fidelized = c.fidelizado)) <> 4 THEN
    RAISE EXCEPTION 'cenario_a_valores_divergentes: a agenda nao produz os quatro valores aprovados do Cenario A';
  END IF;
END $cenario_a$;

SELECT commercial_category, fidelized, benefit_settlement_mode, economic_value_cents,
       mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents, qa_cash_cents,
       cash_adjustment_cents, total_monetary_funding_required_cents
  FROM public.commercial_settlement_terms
 WHERE pricing_rule_version = 4
 ORDER BY commercial_category, fidelized, benefit_settlement_mode;
