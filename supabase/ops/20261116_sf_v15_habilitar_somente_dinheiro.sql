-- ===========================================================================
-- SF-v1.5 — HABILITAR SOMENTE A MODALIDADE DINHEIRO NA VERSÃO 4 (R4.3)
--
-- Autorização: proprietário, 16/11/2026 — preparar em ambiente LOCAL/STAGING
-- a habilitação exclusiva do DINHEIRO (Cenário A). NÃO executar em produção
-- sem autorização própria e específica para isso.
--
-- Pré-requisito: preço do DINHEIRO do Cenário A já gravado na versão 4
-- (supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql), conferido aqui.
--
-- Efeito: commercial_pricing_rules.enabled_settlement_modes = {cash} na
-- versão 4, ainda 'prepared'. Isso NÃO ativa a versão. A ativação continua
-- exigindo, pela pré-verificação:
--   * minutas assináveis (novo e fidelizado) com APROVAÇÃO JURÍDICA real que
--     cubra a modalidade DINHEIRO;
--   * atividades contratadas aprovadas no catálogo SF-v1.5 (6 posições);
--   * aprovação de lançamento registrada;
--   * guardas íntegras (manifesto vigente).
-- O BENEFÍCIO DIRETO fica indisponível nessa versão (recusado em reserva,
-- intenção e pedido) e por isso a QA operacional deixa de ser exigida para
-- ATIVAR a versão 4 — sem ser aprovada, criada ou dispensada para o
-- benefício direto. Reabrir o benefício direto exige nova versão de regra
-- com o procedimento de QA aprovado.
--
-- Depois da ativação a escolha é imutável (cpr_protect).
-- USO:
--   BEGIN;
--   SET LOCAL smallflags.habilitar_somente_dinheiro = 'SOMENTE-DINHEIRO-AUTORIZADO';
--   SET LOCAL smallflags.habilitacao_referencia = '<referencia da autorizacao, >= 10 caracteres>';
--   \i supabase/ops/20261116_sf_v15_habilitar_somente_dinheiro.sql
--   COMMIT;  -- ou ROLLBACK
-- ===========================================================================
DO $somente_dinheiro$
DECLARE
  v_ref text := coalesce(current_setting('smallflags.habilitacao_referencia', true), '');
  v_esperado jsonb := '{"supermarket/f": 3281732, "supermarket/t": 2805432, "common/f": 2287816, "common/t": 1612716}';
  v_n integer;
BEGIN
  IF coalesce(current_setting('smallflags.habilitar_somente_dinheiro', true), '') <> 'SOMENTE-DINHEIRO-AUTORIZADO' THEN
    RAISE EXCEPTION 'somente_dinheiro_sem_autorizacao: defina smallflags.habilitar_somente_dinheiro na transacao';
  END IF;
  IF length(btrim(v_ref)) < 10 THEN
    RAISE EXCEPTION 'somente_dinheiro_sem_referencia: defina smallflags.habilitacao_referencia (>= 10 caracteres)';
  END IF;
  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) IS DISTINCT FROM 'prepared' THEN
    RAISE EXCEPTION 'somente_dinheiro_recusado: a versao 4 nao esta prepared';
  END IF;
  -- Os quatro preços do Cenário A, e nenhum outro.
  SELECT count(*) INTO v_n FROM public.commercial_settlement_terms t
   WHERE t.pricing_rule_version = 4 AND t.benefit_settlement_mode = 'cash'
     AND t.economic_value_cents = (v_esperado->>(t.commercial_category || '/' || left(t.fidelized::text, 1)))::bigint
     AND t.qa_in_kind_cents = 0 AND t.qa_cash_cents = 0 AND t.cash_adjustment_cents = 0
     AND t.total_monetary_funding_required_cents = t.economic_value_cents;
  IF v_n <> 4 OR (SELECT count(*) FROM public.commercial_settlement_terms
                   WHERE pricing_rule_version = 4 AND benefit_settlement_mode = 'cash') <> 4 THEN
    RAISE EXCEPTION 'somente_dinheiro_sem_cenario_a: os quatro precos do Cenario A nao estao gravados (%)', v_n;
  END IF;

  UPDATE public.commercial_pricing_rules SET enabled_settlement_modes = ARRAY['cash']
   WHERE version = 4 AND status = 'prepared';
  RAISE NOTICE 'versao 4: somente DINHEIRO habilitado (%). Nada foi ativado.', btrim(v_ref);
END $somente_dinheiro$;

SELECT version, status, enabled_settlement_modes,
       public.commercial_pricing_activation_preflight(version)->'failures' AS pendencias_para_ativar
  FROM public.commercial_pricing_rules WHERE version = 4;
