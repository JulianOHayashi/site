-- ===========================================================================
-- ATIVAÇÃO DA SF-v1.5 — NÃO EXECUTAR SEM AUTORIZAÇÃO EXPRESSA DO OPERADOR
--
-- Torna vigente a versão 4 (SF-v1.5) e supera a versão 3 (SF-v1.4). A partir
-- daí, toda nova reserva e venda manual usa os preços com fabricação de
-- bandeiras, e o fidelizado só contrata com reutilização verificada.
--
-- A ativação é deliberadamente IRREVERSÍVEL pelo banco: o gatilho
-- cpr_protect recusa active -> prepared e superseded -> active. Voltar atrás
-- exige decisão e migration própria.
--
-- Pré-requisitos fora do banco (ver docs/release/SF_V15_PLANO_APLICACAO_20261112.md):
--   * minutas V2 revisadas e aprovadas (Termos do Pedido, instrumento, anexos);
--   * redação de atividade contratada aprovada no catálogo 'SF-v1.5' para as
--     posições a vender (o catálogo é versionado pela economia);
--   * procedimento de inspeção de conservação aprovado e operadores treinados;
--   * decisão sobre a política de reposição (enquanto não houver, fidelizado
--     com peça inadequada não contrata);
--   * R3: preço da modalidade DINHEIRO aprovado (Cenário A ou B, scripts
--     20261113_sf_v15_dinheiro_cenario_{a,b}.sql) e minutas com
--     settlement_model = 'in_kind_direct_benefits_only'. Sem isso o banco
--     recusa a ativação (commercial_pricing_activation_preflight).
--
-- USO (uma única sessão, transação explícita):
--   BEGIN;
--   SET LOCAL smallflags.autorizacao_ativacao_sf_v15 = 'AUTORIZADO-PELO-OPERADOR';
--   SET LOCAL smallflags.autorizacao_referencia = '<ata/documento da autorizacao>';
--   \i supabase/ops/20261112_ativar_precificacao_sf_v15.sql
--   -- conferir o resultado impresso
--   COMMIT;   -- ou ROLLBACK
-- ===========================================================================
DO $ativar$
DECLARE
  v_vivas integer;
  v_r     jsonb;
BEGIN
  IF coalesce(current_setting('smallflags.autorizacao_ativacao_sf_v15', true), '')
     <> 'AUTORIZADO-PELO-OPERADOR' THEN
    RAISE EXCEPTION 'ativacao_sem_autorizacao: defina smallflags.autorizacao_ativacao_sf_v15 na transacao';
  END IF;

  IF (SELECT status FROM public.commercial_pricing_rules WHERE version = 3) <> 'active'
     OR (SELECT status FROM public.commercial_pricing_rules WHERE version = 4) <> 'prepared' THEN
    RAISE EXCEPTION 'ativacao_estado_inesperado: versao 3 deve estar active e versao 4 prepared';
  END IF;

  IF (SELECT string_agg(format('%s/%s/%s/%s/%s/%s/%s', commercial_category, fidelized::text,
            economic_value_cents, mei_consideration_cents, smallflags_qa_cents,
            smallflags_main_fee_cents, flag_production_charge_cents), ';'
            ORDER BY commercial_category, fidelized)
        FROM public.commercial_pricing_schedule WHERE pricing_rule_version = 4)
     IS DISTINCT FROM
     'common/false/2293900/1192716/6084/1095100/294000;common/true/1618800/1192716/6084/420000/0;'
     || 'supermarket/false/3293900/2385432/12168/896300/294000;supermarket/true/2817600/2385432/12168/420000/0' THEN
    RAISE EXCEPTION 'ativacao_agenda_divergente: a agenda da versao 4 nao e a aprovada';
  END IF;

  -- Reservas vivas sob a SF-v1.4 seriam finalizadas com o preço antigo:
  -- ativar só sem reserva em andamento.
  SELECT count(*) INTO v_vivas FROM public.commercial_checkout_intents
   WHERE status IN ('draft', 'awaiting_contract')
     AND reserved_until IS NOT NULL AND reserved_until > now();
  IF v_vivas > 0 THEN
    RAISE EXCEPTION 'ativacao_com_reservas_vivas: % reserva(s) em andamento', v_vivas;
  END IF;

  -- R3: a ativação passa pelo único caminho autorizado, que registra o ato e
  -- confere no banco as pré-condições A1–A6 (termos das DUAS modalidades,
  -- minutas com o modelo de liquidação, catálogo SF-v1.5 completo, travas
  -- ligadas, nenhuma reserva viva). Um UPDATE direto é recusado pelo gatilho.
  SELECT public.admin_activate_pricing_rule(4,
           current_setting('smallflags.autorizacao_referencia', true)) INTO v_r;
  IF (v_r->>'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'ativacao_recusada: %', v_r;
  END IF;
END
$ativar$;

-- Conferência imediata (ainda dentro da transação do operador).
SELECT 'vigente' AS item, (SELECT version::text || ' ' || status FROM public.commercial_pricing_rules WHERE status = 'active') AS valor
UNION ALL SELECT 'preco publico supermercado nao fidelizado',
       public.get_public_niche_pricing()->'niches'->0->'founding'->>'economic_value_cents'
UNION ALL SELECT 'bandeiras novas por anunciante',
       public.get_public_niche_pricing()->'niches'->0->'founding'->>'new_flag_units'
UNION ALL SELECT 'formacao nao fidelizada (centavos)',
       public.get_public_formation_economics()->>'economic_value_cents';
