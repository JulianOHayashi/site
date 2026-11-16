-- ===========================================================================
-- SF-v1.5 — PREÇO DA MODALIDADE DINHEIRO — CENÁRIO B (preço econômico
-- mantido). NÃO APROVADO. NÃO EXECUTAR SEM DECISÃO COMERCIAL E JURÍDICA
-- REGISTRADA, INCLUSIVE DO FUNDAMENTO DO COMPONENTE.
--
-- Os valores publicados permanecem (32.939,00 / 28.176,00 / 22.939,00 /
-- 16.188,00). A diferença que antes correspondia à QA (121,68 / 60,84) NÃO é
-- QA e NÃO é renomeada como remuneração: entra como componente próprio
-- (cash_adjustment_cents) que EXIGE fundamento aprovado, texto livre do
-- operador, sem valor padrão. A parcela principal da SmallFlags não muda.
--
-- USO:
--   BEGIN;
--   SET LOCAL smallflags.decisao_dinheiro_sf_v15 = 'CENARIO-B-APROVADO';
--   SET LOCAL smallflags.decisao_referencia = '<ata/documento da decisão>';
--   SET LOCAL smallflags.cenario_b_fundamento = '<natureza e fundamento contratual aprovados>';
--   \i supabase/ops/20261113_sf_v15_dinheiro_cenario_b.sql
--   COMMIT;  -- ou ROLLBACK
-- ===========================================================================
-- R4.2: CENÁRIO B REJEITADO. A decisão comercial aprovada é o Cenário A
-- (DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115). Este roteiro fica só como
-- registro histórico e recusa qualquer execução.
DO $cenario_b_rejeitado$
BEGIN
  RAISE EXCEPTION 'cenario_b_rejeitado: o preco do DINHEIRO aprovado e o Cenario A; use 20261113_sf_v15_dinheiro_cenario_a.sql';
END $cenario_b_rejeitado$;

DO $cenario_b$
DECLARE
  v_ref  text := coalesce(current_setting('smallflags.decisao_referencia', true), '');
  v_fund text := coalesce(current_setting('smallflags.cenario_b_fundamento', true), '');
BEGIN
  RAISE EXCEPTION 'cenario_b_rejeitado: o preco do DINHEIRO aprovado e o Cenario A';
  IF coalesce(current_setting('smallflags.decisao_dinheiro_sf_v15', true), '') <> 'CENARIO-B-APROVADO' THEN
    RAISE EXCEPTION 'cenario_b_sem_decisao: defina smallflags.decisao_dinheiro_sf_v15 na transacao';
  END IF;
  IF length(btrim(v_ref)) < 10 THEN
    RAISE EXCEPTION 'cenario_b_sem_referencia: defina smallflags.decisao_referencia (>= 10 caracteres)';
  END IF;
  IF length(btrim(v_fund)) < 20 THEN
    RAISE EXCEPTION 'cenario_b_sem_fundamento: o componente nao e QA e exige fundamento aprovado (>= 20 caracteres)';
  END IF;
  IF v_fund ~* '\mqa\M|qualidade' THEN
    RAISE EXCEPTION 'cenario_b_qa_renomeada: o fundamento nao pode ser a QA';
  END IF;
  IF EXISTS (SELECT 1 FROM public.commercial_settlement_terms
              WHERE pricing_rule_version = 4 AND benefit_settlement_mode = 'cash') THEN
    RAISE EXCEPTION 'cenario_b_ja_definido: a versao 4 ja tem preco de dinheiro';
  END IF;

  INSERT INTO public.commercial_settlement_terms
    (pricing_rule_version, contract_economics_version, commercial_category, fidelized,
     benefit_settlement_mode, economic_value_cents, mei_consideration_cents,
     mei_in_kind_cents, mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents,
     qa_cash_cents, cash_adjustment_cents, cash_adjustment_basis,
     total_monetary_funding_required_cents, ordinary_participation_value_cents,
     decision_reference, notes)
  SELECT s.pricing_rule_version, s.contract_economics_version, s.commercial_category, s.fidelized,
         'cash', s.economic_value_cents, s.mei_consideration_cents,
         0, s.mei_consideration_cents, s.smallflags_main_fee_cents, 0,
         0, s.economic_value_cents - s.mei_consideration_cents - s.smallflags_main_fee_cents,
         btrim(v_fund),
         s.economic_value_cents, s.ordinary_participation_value_cents,
         'Cenario B: ' || btrim(v_ref),
         'Dinheiro com preco mantido: componente proprio, nao QA.'
    FROM public.commercial_pricing_schedule s
   WHERE s.pricing_rule_version = 4;
END $cenario_b$;

SELECT commercial_category, fidelized, benefit_settlement_mode, economic_value_cents,
       mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents, qa_cash_cents,
       cash_adjustment_cents, total_monetary_funding_required_cents
  FROM public.commercial_settlement_terms
 WHERE pricing_rule_version = 4
 ORDER BY commercial_category, fidelized, benefit_settlement_mode;
